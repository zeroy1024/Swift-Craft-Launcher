//
//  YggdrasilAuthService+Password.swift
//  CommonFeature
//
//  © 2025-2026 Swift Craft Launcher Team. All rights reserved.
//

import Foundation

extension YggdrasilAuthService {
    @MainActor
    func startPasswordAuthentication(
        username: String,
        password: String,
        rememberPassword: Bool = false,
    ) async {
        guard let server = currentServer else {
            authState = .error("yggdrasil.error.server_not_selected".localized())
            return
        }

        guard server.supportedAuthMethods.contains(.password) else {
            authState = .error("yggdrasil.error.password_unsupported".localized())
            return
        }

        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedUsername.isEmpty else {
            authState = .error("error.player.invalid_username_empty".localized())
            return
        }
        guard !password.isEmpty else {
            authState = .error("yggdrasil.error.password_empty".localized())
            return
        }

        isLoading = true
        authState = .processing
        authenticatedProfiles = []

        do {
            let response = try await authenticate(
                username: normalizedUsername,
                password: password,
                server: server,
            )
            let candidates = response.availableProfiles.isEmpty
                ? [response.selectedProfile].compactMap(\.self)
                : response.availableProfiles

            guard !candidates.isEmpty else {
                throw GlobalError.validation(
                    i18nKey: "error.validation.yggdrasil_no_profiles",
                    level: .notification,
                    message: "Yggdrasil password authentication returned no profiles for \(server.name)",
                )
            }

            let clientToken = response.clientToken ?? ""
            // Authserver profiles usually only include id/name. Pull skins from the session endpoint.
            let enrichedCandidates = await enrichProfilesWithSessionTextures(
                candidates: candidates,
                server: server,
            )
            let rememberedUsername = rememberPassword ? normalizedUsername : ""
            let rememberedPassword = rememberPassword ? password : ""
            let profiles = enrichedCandidates.map { candidate in
                YggdrasilProfile(
                    id: candidate.id,
                    name: candidate.name,
                    skins: candidate.skins,
                    capes: candidate.capes,
                    accessToken: response.accessToken,
                    refreshToken: "",
                    serverBaseURL: server.baseURL.absoluteString,
                    authMethod: .password,
                    clientToken: clientToken,
                    loginUsername: rememberedUsername,
                    loginPassword: rememberedPassword,
                )
            }
            authenticatedProfiles = profiles
            authState = .authenticated(profile: profiles[0])
        } catch {
            let globalError = GlobalError.from(error)
            AppLog.common.error("Yggdrasil password authentication failed: \(globalError.description)")
            authState = .error(globalError.localizedDescription)
        }

        isLoading = false
    }

    func refreshPasswordToken(
        profile: YggdrasilProfile,
        server: YggdrasilServerConfig,
    ) async throws -> YggdrasilProfile {
        guard let authserverURL = server.authserverURL else {
            throw unsupportedPasswordAuthentication(server: server)
        }

        let request = YggdrasilRefreshRequest(
            accessToken: profile.accessToken,
            clientToken: profile.clientToken.isEmpty ? nil : profile.clientToken,
            selectedProfile: YggdrasilSelectedProfile(id: profile.id, name: profile.name),
            requestUser: true,
        )
        let data = try await requestYggdrasil(
            url: authserverURL.appendingPathComponent("refresh"),
            body: request,
            reauthOnClientError: true,
        )
        let response = try JSONDecoder().decode(YggdrasilRefreshResponse.self, from: data)
        let selectedProfile = response.selectedProfile

        guard selectedProfile == nil || selectedProfile?.id == profile.id else {
            throw GlobalError.authentication(
                i18nKey: "error.authentication.reauth_required",
                level: .popup,
                message: "Yggdrasil refreshed a different profile for \(profile.id)",
            )
        }

        return YggdrasilProfile(
            id: selectedProfile?.id ?? profile.id,
            name: selectedProfile?.name ?? profile.name,
            skins: profile.skins,
            capes: profile.capes,
            accessToken: response.accessToken,
            refreshToken: "",
            serverBaseURL: profile.serverBaseURL,
            authMethod: .password,
            clientToken: response.clientToken ?? profile.clientToken,
            accessTokenExpiresAt: nil,
            loginUsername: profile.loginUsername,
            loginPassword: profile.loginPassword,
        )
    }

    /// Re-authenticates with a remembered username/password and keeps the same selected profile.
    func reauthenticateWithRememberedPassword(
        profile: YggdrasilProfile,
        server: YggdrasilServerConfig,
    ) async throws -> YggdrasilProfile {
        let username = profile.loginUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = profile.loginPassword
        guard !username.isEmpty, !password.isEmpty else {
            throw GlobalError.authentication(
                i18nKey: "error.authentication.reauth_required",
                level: .popup,
                message: "No remembered password available for Yggdrasil profile \(profile.id)",
            )
        }

        let response = try await authenticate(
            username: username,
            password: password,
            server: server,
        )
        // Keep the launcher player mapping stable: never switch to another profile id.
        let candidates = response.availableProfiles.isEmpty
            ? [response.selectedProfile].compactMap(\.self)
            : response.availableProfiles
        let normalizedId = Self.normalizedProfileID(profile.id)
        guard let matched = candidates.first(where: {
            Self.normalizedProfileID($0.id) == normalizedId
        }) else {
            throw GlobalError.authentication(
                i18nKey: "error.authentication.reauth_required",
                level: .popup,
                message: "Remembered password login did not return the original profile \(profile.id)",
            )
        }

        return YggdrasilProfile(
            id: profile.id,
            name: matched.name.isEmpty ? profile.name : matched.name,
            skins: matched.skins.isEmpty ? profile.skins : matched.skins,
            capes: matched.capes ?? profile.capes,
            accessToken: response.accessToken,
            refreshToken: "",
            serverBaseURL: profile.serverBaseURL,
            authMethod: .password,
            clientToken: response.clientToken ?? profile.clientToken,
            accessTokenExpiresAt: nil,
            loginUsername: username,
            loginPassword: password,
        )
    }

    /// Whether refresh failure should fall back to remembered-password re-auth.
    /// Includes HTTP 400-403 and local auth-path failures, but not network/5xx.
    func shouldAttemptRememberedPasswordReauth(after error: Error) -> Bool {
        let globalError = (error as? GlobalError) ?? GlobalError.from(error)
        if globalError.kind == .network {
            return false
        }
        if let statusCode = globalError.statusCode {
            // 5xx/other statuses are treated as transient service issues.
            return (400 ... 403).contains(statusCode)
        }
        return globalError.kind == .authentication
            && globalError.i18nKey == "error.authentication.reauth_required"
    }

    /// Whether remembered password + access token should be wiped after a re-auth failure.
    /// Only confirmed client auth rejections (HTTP 400-403) clear secrets.
    func isYggdrasilCredentialInvalidationError(_ error: Error) -> Bool {
        let globalError = (error as? GlobalError) ?? GlobalError.from(error)
        if globalError.kind == .network {
            return false
        }
        guard let statusCode = globalError.statusCode else {
            return false
        }
        return (400 ... 403).contains(statusCode)
    }

    /// Drops remembered password + access token after a confirmed credential invalidation.
    func invalidatedPasswordCredentialProfile(from profile: YggdrasilProfile) -> YggdrasilProfile {
        YggdrasilProfile(
            id: profile.id,
            name: profile.name,
            skins: profile.skins,
            capes: profile.capes,
            accessToken: "",
            refreshToken: "",
            serverBaseURL: profile.serverBaseURL,
            authMethod: .password,
            clientToken: profile.clientToken,
            accessTokenExpiresAt: nil,
            loginUsername: profile.loginUsername,
            loginPassword: "",
        )
    }

    static func normalizedProfileID(_ id: String) -> String {
        id.replacingOccurrences(of: "-", with: "").lowercased()
    }
}

private extension YggdrasilAuthService {
    /// Loads skin/cape textures for password-login profiles via the Yggdrasil session-server API.
    /// Failures are non-fatal: login still succeeds with the bare id/name profile.
    func enrichProfilesWithSessionTextures(
        candidates: [YggdrasilProfileCandidate],
        server: YggdrasilServerConfig,
    ) async -> [YggdrasilProfileCandidate] {
        guard let profileBaseURL = server.profileURL else {
            return candidates
        }

        var enriched: [YggdrasilProfileCandidate] = []
        enriched.reserveCapacity(candidates.count)

        for candidate in candidates {
            let hasSkinURL = candidate.skins.contains { !$0.url.isEmpty }
            if hasSkinURL {
                enriched.append(candidate)
                continue
            }

            let profileURL = profileBaseURL.appendingPathComponent(candidate.id)
            do {
                let data = try await APIClient.get(url: profileURL)
                if let parsed = CommonYggdrasilProfileListParser.parse(data: data),
                   let match = parsed.first(where: {
                       $0.id.replacingOccurrences(of: "-", with: "")
                           == candidate.id.replacingOccurrences(of: "-", with: "")
                   }) ?? parsed.first {
                    enriched.append(
                        YggdrasilProfileCandidate(
                            id: candidate.id,
                            name: match.name.isEmpty ? candidate.name : match.name,
                            skins: match.skins,
                            capes: match.capes,
                        ),
                    )
                    continue
                }
            } catch {
                AppLog.common.error(
                    "Failed to load session textures for \(candidate.name): \(error.localizedDescription)",
                )
            }
            enriched.append(candidate)
        }

        return enriched
    }

    func authenticate(
        username: String,
        password: String,
        server: YggdrasilServerConfig,
    ) async throws -> YggdrasilAuthenticateResponse {
        guard let authserverURL = server.authserverURL else {
            throw unsupportedPasswordAuthentication(server: server)
        }

        let request = YggdrasilAuthenticateRequest(
            agent: YggdrasilAgent(name: "Minecraft", version: 1),
            username: username,
            password: password,
            requestUser: true,
        )
        let data = try await requestYggdrasil(
            url: authserverURL.appendingPathComponent("authenticate"),
            body: request,
            reauthOnClientError: false,
        )
        return try JSONDecoder().decode(YggdrasilAuthenticateResponse.self, from: data)
    }

    func requestYggdrasil(
        url: URL,
        body: some Encodable,
        reauthOnClientError: Bool,
    ) async throws -> Data {
        let encodedBody = try JSONEncoder().encode(body)
        let (data, statusCode) = try await APIClient.postUnchecked(
            url: url,
            body: encodedBody,
            headers: APIClient.DefaultHeaders.contentTypeJSON,
        )
        guard statusCode == 200 else {
            let message = (try? JSONDecoder().decode(YggdrasilErrorResponse.self, from: data).errorMessage)
                ?? "Yggdrasil request failed with HTTP \(statusCode)"
            let isClientAuthFailure = (400 ... 403).contains(statusCode)
            throw GlobalError.authentication(
                i18nKey: reauthOnClientError && isClientAuthFailure
                    ? "error.authentication.reauth_required"
                    : "yggdrasil.error.login_failed_retry",
                level: .popup,
                statusCode: statusCode,
                message: message,
            )
        }
        return data
    }

    func unsupportedPasswordAuthentication(server: YggdrasilServerConfig) -> GlobalError {
        GlobalError.authentication(
            i18nKey: "yggdrasil.error.password_unsupported",
            level: .popup,
            message: "Server \(server.name) does not provide a password authentication endpoint",
        )
    }
}

private struct YggdrasilAgent: Encodable {
    let name: String
    let version: Int
}

private struct YggdrasilAuthenticateRequest: Encodable {
    let agent: YggdrasilAgent
    let username: String
    let password: String
    let requestUser: Bool
}

private struct YggdrasilSelectedProfile: Codable {
    let id: String
    let name: String
}

private struct YggdrasilRefreshRequest: Encodable {
    let accessToken: String
    let clientToken: String?
    let selectedProfile: YggdrasilSelectedProfile
    let requestUser: Bool
}

private struct YggdrasilErrorResponse: Decodable {
    let errorMessage: String?
}

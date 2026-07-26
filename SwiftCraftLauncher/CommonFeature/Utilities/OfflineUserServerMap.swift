//
//  OfflineUserServerMap.swift
//  CommonFeature
//
//  © 2025-2026 Swift Craft Launcher Team. All rights reserved.
//

import Foundation

/// Maps offline player IDs to their Yggdrasil authentication profiles.
enum OfflineUserServerMap {
    private static let credentialStore = ThirdPartyCredentialStore()

    private static func loadMap() -> [String: YggdrasilProfile] {
        guard let data = UserDefaults.standard.data(forKey: AppConstants.UserDefaultsKeys.offlineUserServerMap),
              let map = try? JSONDecoder().decode([String: YggdrasilProfile].self, from: data) else {
            return [:]
        }
        return map
    }

    /// Associates a Yggdrasil profile with the specified user.
    @discardableResult
    static func setServer(_ profile: YggdrasilProfile) -> Bool {
        let credential = ThirdPartyCredential(
            userId: profile.id,
            accessToken: profile.accessToken,
            refreshToken: profile.refreshToken,
            clientToken: profile.clientToken,
            authMethod: profile.authMethod,
            accessTokenExpiresAt: profile.accessTokenExpiresAt,
            loginUsername: profile.loginUsername.isEmpty ? nil : profile.loginUsername,
            loginPassword: profile.loginPassword.isEmpty ? nil : profile.loginPassword,
        )
        guard credentialStore.saveCredential(credential) else {
            AppLog.common.error("Failed to save Yggdrasil credential for user \(profile.id)")
            return false
        }

        var map = loadMap()
        map[profile.id] = profile.withoutCredentials()
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: AppConstants.UserDefaultsKeys.offlineUserServerMap)
            AppLog.common.info("Updated Yggdrasil profile for user \(profile.id), server: \(profile.serverBaseURL)")
            return true
        } else {
            AppLog.common.error("Failed to encode Yggdrasil profile for user \(profile.id)")
            _ = credentialStore.deleteCredential(userId: profile.id)
            return false
        }
    }

    /// Removes the Yggdrasil profile for the specified user.
    /// - Parameter userId: The player identifier.
    static func removeServer(for userId: String) {
        var map = loadMap()
        map.removeValue(forKey: userId)
        _ = credentialStore.deleteCredential(userId: userId)
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: AppConstants.UserDefaultsKeys.offlineUserServerMap)
        }
    }

    /// Returns the Yggdrasil profile for the specified user.
    /// - Parameter userId: The player identifier.
    /// - Returns: The associated profile, or `nil` if none exists.
    static func serverKey(for userId: String) -> YggdrasilProfile? {
        guard let profile = loadMap()[userId] else { return nil }
        if let credential = credentialStore.loadCredential(userId: userId) {
            return profile.withCredential(credential)
        }

        guard !profile.accessToken.isEmpty || !profile.refreshToken.isEmpty else {
            return profile
        }

        let legacyCredential = ThirdPartyCredential(
            userId: userId,
            accessToken: profile.accessToken,
            refreshToken: profile.refreshToken,
            clientToken: profile.clientToken,
            authMethod: profile.authMethod,
            accessTokenExpiresAt: profile.accessTokenExpiresAt,
            loginUsername: profile.loginUsername.isEmpty ? nil : profile.loginUsername,
            loginPassword: profile.loginPassword.isEmpty ? nil : profile.loginPassword,
        )
        guard credentialStore.saveCredential(legacyCredential) else { return profile }

        var map = loadMap()
        map[userId] = profile.withoutCredentials()
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: AppConstants.UserDefaultsKeys.offlineUserServerMap)
        }
        return profile
    }

    /// Indicates whether the specified user has an associated Yggdrasil profile.
    static func contains(userId: String) -> Bool {
        loadMap()[userId] != nil
    }
}

private extension YggdrasilProfile {
    func withoutCredentials() -> YggdrasilProfile {
        YggdrasilProfile(
            id: id,
            name: name,
            skins: skins,
            capes: capes,
            accessToken: "",
            refreshToken: "",
            serverBaseURL: serverBaseURL,
            authMethod: authMethod,
            clientToken: "",
            accessTokenExpiresAt: accessTokenExpiresAt,
            loginUsername: "",
            loginPassword: "",
        )
    }

    func withCredential(_ credential: ThirdPartyCredential) -> YggdrasilProfile {
        YggdrasilProfile(
            id: id,
            name: name,
            skins: skins,
            capes: capes,
            accessToken: credential.accessToken,
            refreshToken: credential.refreshToken,
            serverBaseURL: serverBaseURL,
            authMethod: credential.authMethod,
            clientToken: credential.clientToken,
            accessTokenExpiresAt: credential.accessTokenExpiresAt,
            loginUsername: credential.loginUsername ?? "",
            loginPassword: credential.loginPassword ?? "",
        )
    }
}

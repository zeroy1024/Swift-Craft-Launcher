//
//  YggdrasilModels.swift
//  CommonFeature
//
//  © 2025-2026 Swift Craft Launcher Team. All rights reserved.
//

import Foundation

enum ThirdPartyAuthMethod: String, Codable, CaseIterable, Identifiable {
    case oauth2
    case password

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oauth2: return "yggdrasil.auth.method.oauth".localized()
        case .password: return "yggdrasil.auth.method.password".localized()
        }
    }
}

/// Identifies a Yggdrasil profile parser implementation.
enum YggdrasilProfileParserID: String, Codable, CaseIterable, Identifiable {
    case littleskin
    case mua
    case ely
    /// Generic Authlib-Injector / standard Yggdrasil session profile responses.
    case authlib

    var id: String { rawValue }
}

struct YggdrasilServerConfig: Codable, Equatable, Hashable {
    /// The display name for this server in the UI.
    var name: String
    var baseURL: URL
    var clientId: String?
    var clientSecret: String?
    var redirectURI: String
    var authorizePath: String
    var tokenPath: String
    var profilePath: String
    var scope: String
    var parserId: YggdrasilProfileParserID
    var token: String
    var supportedAuthMethods: Set<ThirdPartyAuthMethod>
    var authserverPath: String?

    init(
        name: String,
        baseURL: URL,
        clientId: String? = nil,
        clientSecret: String? = nil,
        redirectURI: String,
        authorizePath: String,
        tokenPath: String,
        profilePath: String,
        scope: String,
        parserId: YggdrasilProfileParserID,
        token: String,
        supportedAuthMethods: Set<ThirdPartyAuthMethod> = [.oauth2],
        authserverPath: String? = nil,
    ) {
        self.name = name
        self.baseURL = baseURL
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.redirectURI = redirectURI
        self.authorizePath = authorizePath
        self.tokenPath = tokenPath
        self.profilePath = profilePath
        self.scope = scope.trimmingCharacters(in: .whitespacesAndNewlines)
        self.parserId = parserId
        self.token = token
        self.supportedAuthMethods = supportedAuthMethods
        self.authserverPath = authserverPath
    }

    /// The full authorize URL derived from the base URL and authorize path.
    var authorizeURL: URL? {
        baseURL.appendingPathComponent(authorizePath)
    }

    /// The full token URL derived from the base URL and token path.
    var tokenURL: URL? {
        baseURL.appendingPathComponent(tokenPath)
    }

    /// The full profile URL derived from the base URL and profile path.
    var profileURL: URL? {
        baseURL.appendingPathComponent(profilePath)
    }

    var minecraftTokenURL: URL {
        baseURL.appendingPathComponent(token)
    }

    var authserverURL: URL? {
        guard let authserverPath else { return nil }
        return baseURL.appendingPathComponent(authserverPath)
    }
}

struct YggdrasilProfile: Codable, Equatable {
    let id: String
    let name: String
    let skins: [Skin]
    let capes: [Cape]?

    let accessToken: String
    let refreshToken: String
    let serverBaseURL: String
    let authMethod: ThirdPartyAuthMethod
    let clientToken: String
    let accessTokenExpiresAt: Date?
    /// Optional password-login username kept only for Keychain transport / silent re-auth.
    let loginUsername: String
    /// Optional remembered password kept only for Keychain transport / silent re-auth.
    let loginPassword: String

    init(
        id: String,
        name: String,
        skins: [Skin],
        capes: [Cape]?,
        accessToken: String,
        refreshToken: String,
        serverBaseURL: String,
        authMethod: ThirdPartyAuthMethod = .oauth2,
        clientToken: String = "",
        accessTokenExpiresAt: Date? = nil,
        loginUsername: String = "",
        loginPassword: String = "",
    ) {
        self.id = id
        self.name = name
        self.skins = skins
        self.capes = capes
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.serverBaseURL = serverBaseURL
        self.authMethod = authMethod
        self.clientToken = clientToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
        self.loginUsername = loginUsername
        self.loginPassword = loginPassword
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, skins, capes, accessToken, refreshToken, serverBaseURL, authMethod, clientToken, accessTokenExpiresAt, loginUsername, loginPassword
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        skins = try container.decode([Skin].self, forKey: .skins)
        capes = try container.decodeIfPresent([Cape].self, forKey: .capes)
        accessToken = try container.decodeIfPresent(String.self, forKey: .accessToken) ?? ""
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken) ?? ""
        serverBaseURL = try container.decode(String.self, forKey: .serverBaseURL)
        authMethod = try container.decodeIfPresent(ThirdPartyAuthMethod.self, forKey: .authMethod) ?? .oauth2
        clientToken = try container.decodeIfPresent(String.self, forKey: .clientToken) ?? ""
        accessTokenExpiresAt = try container.decodeIfPresent(Date.self, forKey: .accessTokenExpiresAt)
        loginUsername = try container.decodeIfPresent(String.self, forKey: .loginUsername) ?? ""
        // Passwords may exist only in-memory / Keychain transport; never trust encoded profile payloads.
        loginPassword = try container.decodeIfPresent(String.self, forKey: .loginPassword) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(skins, forKey: .skins)
        try container.encodeIfPresent(capes, forKey: .capes)
        try container.encode(accessToken, forKey: .accessToken)
        try container.encode(refreshToken, forKey: .refreshToken)
        try container.encode(serverBaseURL, forKey: .serverBaseURL)
        try container.encode(authMethod, forKey: .authMethod)
        try container.encode(clientToken, forKey: .clientToken)
        try container.encodeIfPresent(accessTokenExpiresAt, forKey: .accessTokenExpiresAt)
        try container.encode(loginUsername, forKey: .loginUsername)
        // Never serialize remembered passwords outside Keychain-backed credential storage.
        try container.encode("", forKey: .loginPassword)
    }
}

struct ThirdPartyCredential: Codable, Equatable {
    let userId: String
    var accessToken: String
    var refreshToken: String
    var clientToken: String
    var authMethod: ThirdPartyAuthMethod
    var accessTokenExpiresAt: Date?
    /// Username for password-login silent re-auth. Absent for OAuth-only credentials.
    var loginUsername: String?
    /// Remembered password for silent re-auth. Stored only in Keychain when user opts in.
    var loginPassword: String?

    private enum CodingKeys: String, CodingKey {
        case userId, accessToken, refreshToken, clientToken, authMethod, accessTokenExpiresAt, loginUsername, loginPassword
    }

    init(
        userId: String,
        accessToken: String,
        refreshToken: String,
        clientToken: String,
        authMethod: ThirdPartyAuthMethod,
        accessTokenExpiresAt: Date? = nil,
        loginUsername: String? = nil,
        loginPassword: String? = nil,
    ) {
        self.userId = userId
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.clientToken = clientToken
        self.authMethod = authMethod
        self.accessTokenExpiresAt = accessTokenExpiresAt
        self.loginUsername = loginUsername
        self.loginPassword = loginPassword
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(String.self, forKey: .userId)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        refreshToken = try container.decode(String.self, forKey: .refreshToken)
        clientToken = try container.decodeIfPresent(String.self, forKey: .clientToken) ?? ""
        authMethod = try container.decodeIfPresent(ThirdPartyAuthMethod.self, forKey: .authMethod) ?? .oauth2
        accessTokenExpiresAt = try container.decodeIfPresent(Date.self, forKey: .accessTokenExpiresAt)
        loginUsername = try container.decodeIfPresent(String.self, forKey: .loginUsername)
        loginPassword = try container.decodeIfPresent(String.self, forKey: .loginPassword)
    }
}

struct YggdrasilAuthenticateResponse: Decodable {
    let accessToken: String
    let clientToken: String?
    let selectedProfile: YggdrasilProfileCandidate?
    let availableProfiles: [YggdrasilProfileCandidate]

    private enum CodingKeys: String, CodingKey {
        case accessToken, clientToken, selectedProfile, availableProfiles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        clientToken = try container.decodeIfPresent(String.self, forKey: .clientToken)
        selectedProfile = try container.decodeIfPresent(YggdrasilProfileCandidate.self, forKey: .selectedProfile)
        availableProfiles = try container.decodeIfPresent([YggdrasilProfileCandidate].self, forKey: .availableProfiles) ?? []
    }
}

struct YggdrasilRefreshResponse: Decodable {
    let accessToken: String
    let clientToken: String?
    let selectedProfile: YggdrasilProfileCandidate?
}

struct YggdrasilProfileCandidate: Codable, Equatable {
    let id: String
    let name: String
    let skins: [Skin]
    let capes: [Cape]?

    init(id: String, name: String, skins: [Skin] = [], capes: [Cape]? = nil) {
        self.id = id
        self.name = name
        self.skins = skins
        self.capes = capes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        skins = (try? container.decode([Skin].self, forKey: .skins)) ?? []
        capes = try? container.decode([Cape].self, forKey: .capes)
    }
}

/// The current state of the Yggdrasil authentication flow.
typealias YggdrasilAuthState = AuthFlowState<YggdrasilProfile>

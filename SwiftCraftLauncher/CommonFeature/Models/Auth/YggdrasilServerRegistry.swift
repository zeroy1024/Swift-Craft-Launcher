//
//  YggdrasilServerRegistry.swift
//  CommonFeature
//
//  © 2025-2026 Swift Craft Launcher Team. All rights reserved.
//

import Foundation

/// Unified lookup for built-in presets and user-defined Authlib-Injector servers.
enum YggdrasilServerRegistry {
    static var presetServers: [YggdrasilServerConfig] {
        YggdrasilServerPresets.servers
    }

    static var customServers: [YggdrasilServerConfig] {
        CustomYggdrasilServerStore.load()
    }

    /// Preset servers first, then user-defined Authlib servers.
    static var allServers: [YggdrasilServerConfig] {
        presetServers + customServers
    }

    static func server(for baseURLString: String) -> YggdrasilServerConfig? {
        let key = normalizedBaseURLString(baseURLString)
        guard !key.isEmpty else { return nil }
        return allServers.first {
            normalizedBaseURLString($0.baseURL.absoluteString) == key
        }
    }

    static func isCustomServer(_ server: YggdrasilServerConfig) -> Bool {
        server.parserId == .authlib
    }

    static func normalizedBaseURLString(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }

    /// Builds a password-only Authlib-Injector config from an API root URL.
    /// - Parameters:
    ///   - name: Optional display name. Falls back to host when empty.
    ///   - apiRootString: Authlib-Injector API root, e.g. `https://example.com/api/yggdrasil`.
    static func makeAuthlibInjectorServer(
        name: String,
        apiRootString: String,
    ) throws -> YggdrasilServerConfig {
        let normalized = normalizedBaseURLString(apiRootString)
        guard let url = URL(string: normalized),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            throw GlobalError.validation(
                i18nKey: "yggdrasil.server.custom.invalid_url",
                level: .notification,
                message: "Invalid Authlib-Injector API root: \(apiRootString)",
            )
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmedName.isEmpty ? (url.host ?? "Authlib") : trimmedName

        return YggdrasilServerConfig(
            name: displayName,
            baseURL: url,
            clientId: nil,
            clientSecret: nil,
            redirectURI: "",
            authorizePath: "",
            tokenPath: "",
            profilePath: "sessionserver/session/minecraft/profile",
            scope: "",
            parserId: .authlib,
            token: "",
            supportedAuthMethods: [.password],
            authserverPath: "authserver",
        )
    }
}

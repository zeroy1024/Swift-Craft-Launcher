//
//  CustomYggdrasilServerStore.swift
//  CommonFeature
//
//  © 2025-2026 Swift Craft Launcher Team. All rights reserved.
//

import Foundation

/// Persists user-defined Authlib-Injector / Yggdrasil API roots.
enum CustomYggdrasilServerStore {
    private static var defaults: UserDefaults { .standard }

    static func load() -> [YggdrasilServerConfig] {
        guard let data = defaults.data(forKey: AppConstants.UserDefaultsKeys.customYggdrasilServers),
              let servers = try? JSONDecoder().decode([YggdrasilServerConfig].self, from: data) else {
            return []
        }
        return servers
    }

    @discardableResult
    static func save(_ servers: [YggdrasilServerConfig]) -> Bool {
        guard let data = try? JSONEncoder().encode(servers) else {
            AppLog.common.error("Failed to encode custom Yggdrasil servers")
            return false
        }
        defaults.set(data, forKey: AppConstants.UserDefaultsKeys.customYggdrasilServers)
        return true
    }

    /// Inserts or updates a custom server keyed by normalized API root.
    @discardableResult
    static func upsert(_ server: YggdrasilServerConfig) -> Bool {
        var servers = load()
        let key = YggdrasilServerRegistry.normalizedBaseURLString(server.baseURL.absoluteString)
        if let index = servers.firstIndex(where: {
            YggdrasilServerRegistry.normalizedBaseURLString($0.baseURL.absoluteString) == key
        }) {
            servers[index] = server
        } else {
            servers.append(server)
        }
        return save(servers)
    }

    @discardableResult
    static func remove(baseURLString: String) -> Bool {
        let key = YggdrasilServerRegistry.normalizedBaseURLString(baseURLString)
        let servers = load().filter {
            YggdrasilServerRegistry.normalizedBaseURLString($0.baseURL.absoluteString) != key
        }
        return save(servers)
    }
}

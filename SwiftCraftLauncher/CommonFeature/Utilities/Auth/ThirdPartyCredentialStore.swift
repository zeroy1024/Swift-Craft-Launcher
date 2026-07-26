//
//  ThirdPartyCredentialStore.swift
//  CommonFeature
//
//  © 2025-2026 Swift Craft Launcher Team. All rights reserved.
//

import Foundation

/// Manages third-party authentication credentials securely using the system Keychain.
final class ThirdPartyCredentialStore {
    func saveCredential(_ credential: ThirdPartyCredential) -> Bool {
        do {
            let data = try JSONEncoder().encode(credential)
            return KeychainManager.save(
                data: data,
                account: credential.userId,
                key: AppConstants.KeychainKeys.thirdPartyCredential,
            )
        } catch {
            AppLog.player.error("Failed to encode third-party credentials: \(error.localizedDescription)")
            return false
        }
    }

    func loadCredential(userId: String) -> ThirdPartyCredential? {
        guard let data = KeychainManager.load(
            account: userId,
            key: AppConstants.KeychainKeys.thirdPartyCredential,
        ) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(ThirdPartyCredential.self, from: data)
        } catch {
            AppLog.player.error("Failed to decode third-party credentials: \(error.localizedDescription)")
            return nil
        }
    }

    func deleteCredential(userId: String) -> Bool {
        KeychainManager.delete(
            account: userId,
            key: AppConstants.KeychainKeys.thirdPartyCredential,
        )
    }
}

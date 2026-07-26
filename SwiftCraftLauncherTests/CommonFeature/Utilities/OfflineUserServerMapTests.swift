//
//  OfflineUserServerMapTests.swift
//  SwiftCraftLauncherTests
//
//  © 2025-2026 Swift Craft Launcher Team. All rights reserved.
//

@testable import SwiftCraftLauncher
import XCTest

final class OfflineUserServerMapTests: XCTestCase {
    private let suiteName = "OfflineUserServerMapTests_\(UUID().uuidString)"
    private var defaults: UserDefaults?

    private func makeProfile(
        id: String = UUID().uuidString,
        name: String = "TestPlayer",
        serverBaseURL: String = "https://littleskin.cn/api",
    ) -> YggdrasilProfile {
        YggdrasilProfile(
            id: id,
            name: name,
            skins: [],
            capes: nil,
            accessToken: "token-\(id)",
            refreshToken: "refresh-\(id)",
            serverBaseURL: serverBaseURL,
        )
    }

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults?.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // NOTE: OfflineUserServerMap uses UserDefaults.standard internally.
    // These tests verify the public API behavior; they run against the real
    // standard UserDefaults and are isolated by unique user IDs.

    func testServerKey_noMapping_returnsNil() {
        let userId = "no-mapping-\(UUID().uuidString)"
        XCTAssertNil(OfflineUserServerMap.serverKey(for: userId))
    }

    func testSetServer_thenServerKey_returnsSameValue() {
        let userId = "round-trip-\(UUID().uuidString)"
        let profile = makeProfile(id: userId, serverBaseURL: "https://littleskin.cn/api")
        OfflineUserServerMap.setServer(profile)

        XCTAssertEqual(OfflineUserServerMap.serverKey(for: userId), profile)

        OfflineUserServerMap.removeServer(for: userId)
    }

    func testSetServer_overwritesPreviousValue() {
        let userId = "overwrite-\(UUID().uuidString)"
        let profileA = makeProfile(id: userId, serverBaseURL: "https://server-a.com")
        let profileB = makeProfile(id: userId, serverBaseURL: "https://server-b.com")
        OfflineUserServerMap.setServer(profileA)
        OfflineUserServerMap.setServer(profileB)

        XCTAssertEqual(OfflineUserServerMap.serverKey(for: userId), profileB)

        OfflineUserServerMap.removeServer(for: userId)
    }

    func testRemoveServer_existingMapping_returnsNil() {
        let userId = "remove-\(UUID().uuidString)"
        let profile = makeProfile(id: userId, serverBaseURL: "https://myserver.com")
        OfflineUserServerMap.setServer(profile)
        OfflineUserServerMap.removeServer(for: userId)

        XCTAssertNil(OfflineUserServerMap.serverKey(for: userId))
    }

    func testRemoveServer_nonExistingMapping_noop() {
        let userId = "remove-nonexist-\(UUID().uuidString)"
        OfflineUserServerMap.removeServer(for: userId)
        XCTAssertNil(OfflineUserServerMap.serverKey(for: userId))
    }

    func testMultipleUsers_independentMappings() {
        let userA = "multi-a-\(UUID().uuidString)"
        let userB = "multi-b-\(UUID().uuidString)"
        let profileA = makeProfile(id: userA, serverBaseURL: "https://serverA.com")
        let profileB = makeProfile(id: userB, serverBaseURL: "https://serverB.com")

        OfflineUserServerMap.setServer(profileA)
        OfflineUserServerMap.setServer(profileB)

        XCTAssertEqual(OfflineUserServerMap.serverKey(for: userA), profileA)
        XCTAssertEqual(OfflineUserServerMap.serverKey(for: userB), profileB)

        OfflineUserServerMap.removeServer(for: userA)
        XCTAssertNil(OfflineUserServerMap.serverKey(for: userA))
        XCTAssertEqual(OfflineUserServerMap.serverKey(for: userB), profileB)

        OfflineUserServerMap.removeServer(for: userB)
    }

    func testRemoveOneUser_doesNotAffectOther() {
        let userA = "iso-a-\(UUID().uuidString)"
        let userB = "iso-b-\(UUID().uuidString)"
        let profileA = makeProfile(id: userA, serverBaseURL: "https://s1.com")
        let profileB = makeProfile(id: userB, serverBaseURL: "https://s2.com")

        OfflineUserServerMap.setServer(profileA)
        OfflineUserServerMap.setServer(profileB)

        OfflineUserServerMap.removeServer(for: userA)

        XCTAssertNil(OfflineUserServerMap.serverKey(for: userA))
        XCTAssertEqual(OfflineUserServerMap.serverKey(for: userB), profileB)

        OfflineUserServerMap.removeServer(for: userB)
    }

    func testSetServer_specialCharacters() {
        let userId = "special-\(UUID().uuidString)"
        let profile = makeProfile(id: userId, serverBaseURL: "https://littleskin.cn/api")
        OfflineUserServerMap.setServer(profile)

        XCTAssertEqual(OfflineUserServerMap.serverKey(for: userId)?.serverBaseURL, "https://littleskin.cn/api")

        OfflineUserServerMap.removeServer(for: userId)
    }

    func testSetServer_emptyServerKey() {
        let userId = "empty-server-\(UUID().uuidString)"
        let profile = makeProfile(id: userId, serverBaseURL: "")
        OfflineUserServerMap.setServer(profile)

        XCTAssertEqual(OfflineUserServerMap.serverKey(for: userId)?.serverBaseURL, "")

        OfflineUserServerMap.removeServer(for: userId)
    }

    func testServerKey_longUserId() {
        let userId = String(repeating: "a", count: 1000)
        let profile = makeProfile(id: userId, serverBaseURL: "https://server.com")
        OfflineUserServerMap.setServer(profile)
        XCTAssertEqual(OfflineUserServerMap.serverKey(for: userId), profile)
        OfflineUserServerMap.removeServer(for: userId)
    }

    func testSetServer_emptyUserId() {
        let profile = makeProfile(id: "", serverBaseURL: "https://server.com")
        OfflineUserServerMap.setServer(profile)
        XCTAssertEqual(OfflineUserServerMap.serverKey(for: ""), profile)
        OfflineUserServerMap.removeServer(for: "")
    }

    func testSetServer_stripsCredentialsFromUserDefaultsAndRestoresFromKeychain() {
        let userId = "keychain-round-trip-\(UUID().uuidString)"
        let profile = makeProfile(id: userId, serverBaseURL: "https://littleskin.cn")
        XCTAssertTrue(OfflineUserServerMap.setServer(profile))

        // UserDefaults copy must not keep tokens.
        let defaultsData = UserDefaults.standard.data(forKey: AppConstants.UserDefaultsKeys.offlineUserServerMap)
        XCTAssertNotNil(defaultsData)
        if let defaultsData,
           let map = try? JSONDecoder().decode([String: YggdrasilProfile].self, from: defaultsData),
           let stored = map[userId] {
            XCTAssertEqual(stored.accessToken, "")
            XCTAssertEqual(stored.refreshToken, "")
            XCTAssertEqual(stored.clientToken, "")
        } else {
            XCTFail("Expected stripped profile in UserDefaults")
        }

        // Public API reconstructs full credentials from Keychain.
        let restored = OfflineUserServerMap.serverKey(for: userId)
        XCTAssertEqual(restored?.accessToken, profile.accessToken)
        XCTAssertEqual(restored?.refreshToken, profile.refreshToken)

        OfflineUserServerMap.removeServer(for: userId)
        XCTAssertNil(OfflineUserServerMap.serverKey(for: userId))
    }

    func testSetServer_passwordAuthMethod_roundTrip() {
        let userId = "password-auth-\(UUID().uuidString)"
        let profile = YggdrasilProfile(
            id: userId,
            name: "PwdPlayer",
            skins: [],
            capes: nil,
            accessToken: "access-\(userId)",
            refreshToken: "",
            serverBaseURL: "https://littleskin.cn",
            authMethod: .password,
            clientToken: "client-\(userId)",
        )
        XCTAssertTrue(OfflineUserServerMap.setServer(profile))
        let restored = OfflineUserServerMap.serverKey(for: userId)
        XCTAssertEqual(restored?.authMethod, .password)
        XCTAssertEqual(restored?.clientToken, "client-\(userId)")
        XCTAssertEqual(restored?.accessToken, "access-\(userId)")
        OfflineUserServerMap.removeServer(for: userId)
    }

    func testSetServer_rememberedPassword_staysInKeychainOnly() {
        let userId = "remember-password-\(UUID().uuidString)"
        let profile = YggdrasilProfile(
            id: userId,
            name: "PwdPlayer",
            skins: [],
            capes: nil,
            accessToken: "access-\(userId)",
            refreshToken: "",
            serverBaseURL: "https://littleskin.cn",
            authMethod: .password,
            clientToken: "client-\(userId)",
            loginUsername: "user@example.com",
            loginPassword: "secret-password",
        )
        XCTAssertTrue(OfflineUserServerMap.setServer(profile))

        let defaultsData = UserDefaults.standard.data(forKey: AppConstants.UserDefaultsKeys.offlineUserServerMap)
        XCTAssertNotNil(defaultsData)
        if let defaultsData,
           let map = try? JSONDecoder().decode([String: YggdrasilProfile].self, from: defaultsData),
           let stored = map[userId] {
            XCTAssertEqual(stored.loginUsername, "")
            XCTAssertEqual(stored.loginPassword, "")
            XCTAssertEqual(stored.accessToken, "")
        } else {
            XCTFail("Expected stripped profile in UserDefaults")
        }

        let restored = OfflineUserServerMap.serverKey(for: userId)
        XCTAssertEqual(restored?.loginUsername, "user@example.com")
        XCTAssertEqual(restored?.loginPassword, "secret-password")
        XCTAssertEqual(restored?.authMethod, .password)

        OfflineUserServerMap.removeServer(for: userId)
        XCTAssertNil(OfflineUserServerMap.serverKey(for: userId))
    }

    func testSetServer_withoutRememberPassword_doesNotPersistLoginSecrets() {
        let userId = "no-remember-\(UUID().uuidString)"
        let profile = YggdrasilProfile(
            id: userId,
            name: "PwdPlayer",
            skins: [],
            capes: nil,
            accessToken: "access-\(userId)",
            refreshToken: "",
            serverBaseURL: "https://littleskin.cn",
            authMethod: .password,
            clientToken: "client-\(userId)",
        )
        XCTAssertTrue(OfflineUserServerMap.setServer(profile))
        let restored = OfflineUserServerMap.serverKey(for: userId)
        XCTAssertEqual(restored?.loginUsername, "")
        XCTAssertEqual(restored?.loginPassword, "")
        OfflineUserServerMap.removeServer(for: userId)
    }
}

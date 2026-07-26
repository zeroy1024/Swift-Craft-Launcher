//
//  CustomYggdrasilServerStoreTests.swift
//  SwiftCraftLauncherTests
//
//  © 2025-2026 Swift Craft Launcher Team. All rights reserved.
//

@testable import SwiftCraftLauncher
import XCTest

final class CustomYggdrasilServerStoreTests: XCTestCase {
    private let storageKey = AppConstants.UserDefaultsKeys.customYggdrasilServers

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        super.tearDown()
    }

    func testMakeAuthlibInjectorServer_passwordOnlyAndStandardPaths() throws {
        let server = try YggdrasilServerRegistry.makeAuthlibInjectorServer(
            name: "My Skin",
            apiRootString: "https://skin.example.com/api/yggdrasil/",
        )
        XCTAssertEqual(server.name, "My Skin")
        XCTAssertEqual(server.baseURL.absoluteString, "https://skin.example.com/api/yggdrasil")
        XCTAssertEqual(server.supportedAuthMethods, [.password])
        XCTAssertEqual(server.parserId, .authlib)
        XCTAssertEqual(server.authserverURL?.absoluteString, "https://skin.example.com/api/yggdrasil/authserver")
        XCTAssertEqual(
            server.profileURL?.absoluteString.contains("/sessionserver/session/minecraft/profile"),
            true,
        )
        XCTAssertTrue(YggdrasilServerRegistry.isCustomServer(server))
    }

    func testMakeAuthlibInjectorServer_invalidURLThrows() {
        XCTAssertThrowsError(
            try YggdrasilServerRegistry.makeAuthlibInjectorServer(name: "", apiRootString: "not-a-url"),
        )
    }

    func testCustomStore_upsertAndLookup() throws {
        let server = try YggdrasilServerRegistry.makeAuthlibInjectorServer(
            name: "CustomA",
            apiRootString: "https://a.example.com/api/yggdrasil",
        )
        XCTAssertTrue(CustomYggdrasilServerStore.upsert(server))
        XCTAssertEqual(CustomYggdrasilServerStore.load().count, 1)

        let found = YggdrasilServerRegistry.server(for: "https://a.example.com/api/yggdrasil/")
        XCTAssertEqual(found?.name, "CustomA")
        XCTAssertEqual(found?.parserId, .authlib)

        XCTAssertTrue(CustomYggdrasilServerStore.remove(baseURLString: "https://a.example.com/api/yggdrasil"))
        XCTAssertNil(YggdrasilServerRegistry.server(for: "https://a.example.com/api/yggdrasil"))
    }

    func testRegistry_presetsStillResolvable() {
        let littleSkin = YggdrasilServerRegistry.server(for: "https://littleskin.cn")
        XCTAssertEqual(littleSkin?.parserId, .littleskin)
        XCTAssertTrue(YggdrasilServerRegistry.allServers.count >= 3)
    }
}

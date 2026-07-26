//
//  ThirdPartyAuthModelsTests.swift
//  SwiftCraftLauncherTests
//
//  © 2025-2026 Swift Craft Launcher Team. All rights reserved.
//

@testable import SwiftCraftLauncher
import XCTest

final class ThirdPartyAuthModelsTests: XCTestCase {
    func testLegacyYggdrasilProfile_defaultsToOAuth() throws {
        let data = Data(
            """
            {
              "id": "player-id",
              "name": "Player",
              "skins": [],
              "accessToken": "access",
              "refreshToken": "refresh",
              "serverBaseURL": "https://example.com"
            }
            """.utf8,
        )

        let profile = try JSONDecoder().decode(YggdrasilProfile.self, from: data)

        XCTAssertEqual(profile.authMethod, .oauth2)
        XCTAssertEqual(profile.clientToken, "")
        XCTAssertEqual(profile.accessToken, "access")
    }

    func testPasswordProfile_roundTripPreservesClientToken() throws {
        let profile = YggdrasilProfile(
            id: "player-id",
            name: "Player",
            skins: [],
            capes: nil,
            accessToken: "access",
            refreshToken: "",
            serverBaseURL: "https://example.com",
            authMethod: .password,
            clientToken: "client",
        )

        let decoded = try JSONDecoder().decode(
            YggdrasilProfile.self,
            from: JSONEncoder().encode(profile),
        )

        XCTAssertEqual(decoded, profile)
    }

    func testAuthenticateResponse_decodesMultipleProfiles() throws {
        let data = Data(
            """
            {
              "accessToken": "access",
              "clientToken": "client",
              "availableProfiles": [
                { "id": "one", "name": "One" },
                { "id": "two", "name": "Two" }
              ]
            }
            """.utf8,
        )

        let response = try JSONDecoder().decode(YggdrasilAuthenticateResponse.self, from: data)

        XCTAssertEqual(response.availableProfiles.map(\.id), ["one", "two"])
        XCTAssertEqual(response.clientToken, "client")
    }

    func testAuthenticateResponse_missingAvailableProfilesDefaultsToEmpty() throws {
        let data = Data(
            """
            {
              "accessToken": "access",
              "selectedProfile": { "id": "one", "name": "One" }
            }
            """.utf8,
        )

        let response = try JSONDecoder().decode(YggdrasilAuthenticateResponse.self, from: data)

        XCTAssertTrue(response.availableProfiles.isEmpty)
        XCTAssertEqual(response.selectedProfile?.id, "one")
    }

    func testAuthorizationCodeResponse_decodesState() {
        let response = AuthorizationCodeResponse(
            from: URL.require("swift-craft-launcher://auth?code=code&state=expected"),
        )

        XCTAssertEqual(response?.state, "expected")
    }

    func testTokenResponse_decodesExpiryMetadata() throws {
        let data = Data(
            """
            {
              "access_token": "access",
              "refresh_token": "refresh",
              "expires_in": 3600,
              "refresh_token_expires_in": 2592000
            }
            """.utf8,
        )

        let response = try JSONDecoder().decode(TokenResponse.self, from: data)

        XCTAssertEqual(response.expiresIn, 3600)
        XCTAssertEqual(response.refreshTokenExpiresIn, 2_592_000)
    }

    func testOAuthParameters_omitMissingClientId() {
        let parameters = OAuth2TokenOperations.exchangeCodeParameters(
            code: "code",
            clientId: nil,
            redirectURI: "launcher://auth",
            scope: nil,
        )

        XCTAssertNil(parameters["client_id"])
        XCTAssertNil(parameters["scope"])
    }

    func testOAuthParameters_includeConfiguredValues() {
        let parameters = OAuth2TokenOperations.refreshTokenParameters(
            refreshToken: "refresh",
            clientId: "client",
            additionalParameters: ["client_secret": "secret"],
        )

        XCTAssertEqual(parameters["client_id"], "client")
        XCTAssertEqual(parameters["client_secret"], "secret")
    }

    func testThirdPartyCredential_legacyDecodeWithoutRememberedPassword() throws {
        let data = Data(
            """
            {
              "userId": "player-id",
              "accessToken": "access",
              "refreshToken": "",
              "clientToken": "client",
              "authMethod": "password"
            }
            """.utf8,
        )

        let credential = try JSONDecoder().decode(ThirdPartyCredential.self, from: data)
        XCTAssertNil(credential.loginUsername)
        XCTAssertNil(credential.loginPassword)
        XCTAssertEqual(credential.authMethod, .password)
    }

    func testThirdPartyCredential_rememberedPasswordRoundTrip() throws {
        let credential = ThirdPartyCredential(
            userId: "player-id",
            accessToken: "access",
            refreshToken: "",
            clientToken: "client",
            authMethod: .password,
            loginUsername: "user@example.com",
            loginPassword: "secret",
        )
        let decoded = try JSONDecoder().decode(
            ThirdPartyCredential.self,
            from: JSONEncoder().encode(credential),
        )
        XCTAssertEqual(decoded, credential)
    }

    func testYggdrasilProfile_legacyDecodeLeavesLoginSecretsEmpty() throws {
        let data = Data(
            """
            {
              "id": "player-id",
              "name": "Player",
              "skins": [],
              "accessToken": "access",
              "refreshToken": "",
              "serverBaseURL": "https://example.com",
              "authMethod": "password",
              "clientToken": "client"
            }
            """.utf8,
        )
        let profile = try JSONDecoder().decode(YggdrasilProfile.self, from: data)
        XCTAssertEqual(profile.loginUsername, "")
        XCTAssertEqual(profile.loginPassword, "")
    }

    func testYggdrasilProfile_encodeNeverPersistsLoginPassword() throws {
        let profile = YggdrasilProfile(
            id: "player-id",
            name: "Player",
            skins: [],
            capes: nil,
            accessToken: "access",
            refreshToken: "",
            serverBaseURL: "https://example.com",
            authMethod: .password,
            clientToken: "client",
            loginUsername: "user@example.com",
            loginPassword: "super-secret",
        )

        let data = try JSONEncoder().encode(profile)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["loginPassword"] as? String, "")
        XCTAssertEqual(json["loginUsername"] as? String, "user@example.com")

        let decoded = try JSONDecoder().decode(YggdrasilProfile.self, from: data)
        XCTAssertEqual(decoded.loginPassword, "")
        XCTAssertEqual(decoded.loginUsername, "user@example.com")
        XCTAssertNotEqual(decoded.loginPassword, "super-secret")
    }

    func testYggdrasilCredentialInvalidation_detectsOnlyClientAuthFailures() {
        let service = YggdrasilAuthService()
        let authFailure = GlobalError.authentication(
            i18nKey: "error.authentication.reauth_required",
            statusCode: 403,
            message: "Forbidden",
        )
        let serverFailure = GlobalError.authentication(
            i18nKey: "yggdrasil.error.login_failed_retry",
            statusCode: 500,
            message: "Server exploded",
        )
        let networkFailure = GlobalError.network(
            i18nKey: "error.network.url",
            level: .notification,
            message: "offline",
        )
        let localReauthRequired = GlobalError.authentication(
            i18nKey: "error.authentication.reauth_required",
            message: "profile missing",
        )

        XCTAssertTrue(service.shouldAttemptRememberedPasswordReauth(after: authFailure))
        XCTAssertTrue(service.shouldAttemptRememberedPasswordReauth(after: localReauthRequired))
        XCTAssertFalse(service.shouldAttemptRememberedPasswordReauth(after: serverFailure))
        XCTAssertFalse(service.shouldAttemptRememberedPasswordReauth(after: networkFailure))

        XCTAssertTrue(service.isYggdrasilCredentialInvalidationError(authFailure))
        XCTAssertFalse(service.isYggdrasilCredentialInvalidationError(serverFailure))
        XCTAssertFalse(service.isYggdrasilCredentialInvalidationError(networkFailure))
        XCTAssertFalse(service.isYggdrasilCredentialInvalidationError(localReauthRequired))
    }

    func testInvalidatedPasswordCredentialProfile_clearsTokenAndPassword() {
        let service = YggdrasilAuthService()
        let profile = YggdrasilProfile(
            id: "player-id",
            name: "Player",
            skins: [],
            capes: nil,
            accessToken: "access",
            refreshToken: "",
            serverBaseURL: "https://example.com",
            authMethod: .password,
            clientToken: "client",
            loginUsername: "user@example.com",
            loginPassword: "super-secret",
        )
        let cleared = service.invalidatedPasswordCredentialProfile(from: profile)
        XCTAssertEqual(cleared.accessToken, "")
        XCTAssertEqual(cleared.loginPassword, "")
        XCTAssertEqual(cleared.loginUsername, "user@example.com")
        XCTAssertEqual(cleared.clientToken, "client")
        XCTAssertEqual(cleared.id, profile.id)
    }
}

//
//  YggdrasilAuthView.swift
//  CommonFeature
//
//  © 2025-2026 Swift Craft Launcher Team. All rights reserved.
//

import SwiftUI

/// A view for authenticating with Yggdrasil-compatible Minecraft servers.
struct YggdrasilAuthView: View {
    @Environment(DIContainer.self)
    private var container
    @State private var viewModel = YggdrasilAuthViewModel()
    @Binding var authMethod: ThirdPartyAuthMethod
    @Binding var username: String
    @Binding var password: String
    @Binding var rememberPassword: Bool
    var onLoginSuccess: ((YggdrasilProfile) -> Void)?

    @State private var isAddingCustomServer = false
    @State private var customServerName = ""
    @State private var customServerURL = ""
    @State private var customServerError: String?

    init(
        authMethod: Binding<ThirdPartyAuthMethod>,
        username: Binding<String>,
        password: Binding<String>,
        rememberPassword: Binding<Bool>,
        onLoginSuccess: ((YggdrasilProfile) -> Void)? = nil,
    ) {
        CommonYggdrasilProfileParsersConfigurator.bootstrap()
        _authMethod = authMethod
        _username = username
        _password = password
        _rememberPassword = rememberPassword
        self.onLoginSuccess = onLoginSuccess
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        VStack(spacing: 12) {
            serverToolbar

            if isAddingCustomServer {
                customServerForm
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            authContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: viewModel.selectedOption) { _, newValue in
            viewModel.onSelectedOptionChanged(newValue, authService: container.system.yggdrasilAuthService)
            if let newValue, YggdrasilServerRegistry.isCustomServer(newValue) {
                isAddingCustomServer = false
                customServerError = nil
                customServerName = ""
                customServerURL = ""
            }
            guard let newValue else { return }
            if !newValue.supportedAuthMethods.contains(authMethod) {
                authMethod = newValue.supportedAuthMethods.contains(.oauth2) ? .oauth2 : .password
                password = ""
                rememberPassword = false
            }
        }
        .onChange(of: authMethod) { _, _ in
            container.system.yggdrasilAuthService.authState = .idle
            password = ""
            rememberPassword = false
        }
        .onAppear {
            guard viewModel.selectedOption == nil else { return }
            let presetBaseURL = container.ui.playerSettingsManager.defaultYggdrasilServerBaseURL
            guard !presetBaseURL.isEmpty else { return }
            if let preset = YggdrasilServerRegistry.server(for: presetBaseURL) {
                viewModel.selectedOption = preset
            }
        }
        .onDisappear {
            viewModel.onDisappear(authService: container.system.yggdrasilAuthService)
        }
    }

    private var serverToolbar: some View {
        HStack(spacing: 10) {
            Picker("yggdrasil.server.picker".localized(), selection: $viewModel.selectedOption) {
                Text("yggdrasil.server.please_select".localized())
                    .tag(nil as YggdrasilServerConfig?)

                if !YggdrasilServerRegistry.presetServers.isEmpty {
                    Section("yggdrasil.server.section.presets".localized()) {
                        ForEach(YggdrasilServerRegistry.presetServers, id: \.self) { server in
                            Text(server.name).tag(server as YggdrasilServerConfig?)
                        }
                    }
                }

                if !YggdrasilServerRegistry.customServers.isEmpty {
                    Section("yggdrasil.server.section.custom".localized()) {
                        ForEach(YggdrasilServerRegistry.customServers, id: \.self) { server in
                            Text(server.name).tag(server as YggdrasilServerConfig?)
                        }
                    }
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()

            Spacer(minLength: 8)

            if let server = viewModel.selectedOption,
               YggdrasilServerRegistry.isCustomServer(server) {
                Button(role: .destructive) {
                    CustomYggdrasilServerStore.remove(baseURLString: server.baseURL.absoluteString)
                    viewModel.selectedOption = nil
                    container.system.yggdrasilAuthService.logout()
                } label: {
                    Label("common.delete".localized(), systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .fixedSize()
            }

            // Hide add when an existing custom server is selected; show delete instead.
            let isSelectedCustom = viewModel.selectedOption.map(YggdrasilServerRegistry.isCustomServer) ?? false
            if isAddingCustomServer {
                Button {
                    isAddingCustomServer = false
                    customServerError = nil
                    customServerName = ""
                    customServerURL = ""
                } label: {
                    Label("common.cancel".localized(), systemImage: "xmark")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .fixedSize()
            } else if !isSelectedCustom {
                Button {
                    isAddingCustomServer = true
                    customServerError = nil
                } label: {
                    Label("common.add".localized(), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var customServerForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("yggdrasil.server.custom.title".localized())
                .font(.subheadline.weight(.semibold))
            TextField("yggdrasil.server.custom.name".localized(), text: $customServerName)
            TextField("yggdrasil.server.custom.api_root".localized(), text: $customServerURL)
                .textContentType(.URL)
            Text("yggdrasil.server.custom.api_root.help".localized())
                .font(.caption)
                .foregroundStyle(.secondary)
            if let customServerError {
                Text(customServerError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("yggdrasil.server.custom.save".localized()) {
                    saveCustomServer()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(customServerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private func saveCustomServer() {
        do {
            let config = try YggdrasilServerRegistry.makeAuthlibInjectorServer(
                name: customServerName,
                apiRootString: customServerURL,
            )
            guard CustomYggdrasilServerStore.upsert(config) else {
                customServerError = "yggdrasil.server.custom.save_failed".localized()
                return
            }
            authMethod = .password
            password = ""
            rememberPassword = false
            viewModel.selectedOption = config
            isAddingCustomServer = false
            customServerError = nil
            customServerName = ""
            customServerURL = ""
        } catch {
            let globalError = GlobalError.from(error)
            customServerError = globalError.i18nKey.localized()
            if customServerError == globalError.i18nKey {
                customServerError = globalError.localizedDescription
            }
        }
    }

    @ViewBuilder private var authContent: some View {
        if let server = container.system.yggdrasilAuthService.currentServer {
            VStack(spacing: 16) {
                authMethodSection(server: server)

                switch container.system.yggdrasilAuthService.authState {
                case .idle:
                    // Password login already has its own form; hide the browser-login ready placeholder.
                    if authMethod != .password {
                        notAuthenticatedView
                    }
                case .waitingForBrowser:
                    waitingForBrowserView
                case .processing:
                    exchangingCodeView
                case let .authenticated(profile):
                    authenticatedView(profile: profile)
                case let .error(message):
                    failedView(message: message)
                }
            }
            .frame(maxWidth: 320)
            .frame(maxWidth: .infinity, alignment: .top)
        } else {
            statusView(
                systemImage: "server.rack",
                titleKey: "yggdrasil.server.select",
                subtitleKey: "yggdrasil.auth.ready.subtitle",
                subtitleFont: .caption,
            )
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private func authMethodSection(server: YggdrasilServerConfig) -> some View {
        if server.supportedAuthMethods.count > 1 {
            Picker("yggdrasil.auth.method".localized(), selection: $authMethod) {
                ForEach(ThirdPartyAuthMethod.allCases.filter(server.supportedAuthMethods.contains)) { method in
                    Text(method.title).tag(method)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)
        }

        if shouldShowPasswordFields {
            VStack(alignment: .leading, spacing: 10) {
                TextField("yggdrasil.auth.username".localized(), text: $username)
                    .textContentType(.username)
                SecureField("yggdrasil.auth.password".localized(), text: $password)
                    .textContentType(.password)
                Toggle("yggdrasil.auth.remember_password".localized(), isOn: $rememberPassword)
                    .toggleStyle(.checkbox)
                    .help("yggdrasil.auth.remember_password.help".localized())
            }
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: 320)
        }
    }

    private var shouldShowPasswordFields: Bool {
        guard authMethod == .password else { return false }
        switch container.system.yggdrasilAuthService.authState {
        case .idle, .error: return true
        default: return false
        }
    }

    private var notAuthenticatedView: some View {
        statusView(
            systemImage: "person.crop.circle.badge.questionmark",
            titleKey: "yggdrasil.auth.ready",
            subtitleKey: "yggdrasil.auth.ready.subtitle",
            subtitleFont: .caption,
        )
    }

    private var waitingForBrowserView: some View {
        statusView(
            systemImage: "person.crop.circle.badge.clock",
            titleKey: "yggdrasil.auth.waiting_browser",
            subtitleKey: "yggdrasil.auth.waiting_browser.subtitle",
            subtitleFont: .subheadline,
        )
    }

    private var exchangingCodeView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.small)
            Text("yggdrasil.auth.processing".localized())
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private func authenticatedView(profile: YggdrasilProfile) -> some View {
        let profiles = container.system.yggdrasilAuthService.authenticatedProfiles.isEmpty
            ? [profile]
            : container.system.yggdrasilAuthService.authenticatedProfiles
        let selection = Binding<String>(
            get: { profile.id },
            set: { newId in
                viewModel.selectAuthenticatedProfile(id: newId, authService: container.system.yggdrasilAuthService)
            },
        )

        return VStack(spacing: 20) {
            profileAvatarView(for: profile)
            VStack(spacing: 8) {
                profileNameSection(
                    profiles: profiles,
                    selection: selection,
                    currentProfile: profile,
                )
                Text(String(format: "minecraft.auth.uuid".localized(), profile.id))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)
            }
            Text("minecraft.auth.confirm_login".localized())
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func statusView(
        systemImage: String,
        titleKey: String,
        subtitleKey: String,
        subtitleFont: Font,
    ) -> some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 46))
                .symbolRenderingMode(.multicolor)
                .symbolVariant(.none)
                .foregroundColor(.secondary)
            Text(titleKey.localized())
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(subtitleKey.localized())
                .font(subtitleFont)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func profileAvatarView(for profile: YggdrasilProfile) -> some View {
        if let skinUrl = profile.skins.first?.url, !skinUrl.isEmpty {
            return AnyView(
                MinecraftSkinUtils(type: .url, src: skinUrl.httpToHttps())
                    .frame(width: 80, height: 80),
            )
        }

        return AnyView(
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 80, height: 80)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.largeTitle)
                        .foregroundColor(.gray),
                ),
        )
    }

    private func profileNameSection(
        profiles: [YggdrasilProfile],
        selection: Binding<String>,
        currentProfile: YggdrasilProfile,
    ) -> some View {
        Group {
            if profiles.count > 1 {
                Picker("", selection: selection) {
                    ForEach(profiles, id: \.id) { p in
                        Text(p.name).tag(p.id)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
                .labelsHidden()
            } else {
                Text(currentProfile.name)
                    .font(.headline)
            }
        }
    }

    private func failedView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.red)
            Text("minecraft.auth.failed".localized())
                .font(.headline)
                .foregroundColor(.red)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

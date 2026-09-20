import SwiftUI

// MARK: - Tab enum

enum AppTab: Int, CaseIterable {
    case game     = 0
    case menu     = 1
    case settings = 2

    var label: String {
        switch self {
        case .game:     return "Game"
        case .menu:     return "Menu"
        case .settings: return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .game:     return "gamecontroller"
        case .menu:     return "slider.horizontal.3"
        case .settings: return "gearshape"
        }
    }
}

// MARK: - Inject state

enum InjectState: Equatable {
    case idle, checking, ready, unavailable, injecting, done
    case failed(String)
}

// MARK: - MainMenuView

struct MainMenuView: View {
    @EnvironmentObject var session: SessionStore
    @StateObject private var cheat = CheatSettings.shared
    @State private var selectedTab: AppTab = .game
    @State private var isInjected = false
    @State private var ffState:    InjectState = .checking
    @State private var ffmaxState: InjectState = .checking
    @State private var ffSession:    InjectSession? = nil
    @State private var ffmaxSession: InjectSession? = nil
    @State private var now = Date()
    @State private var showLogoutAlert = false
    @State private var isOnline: Bool? = nil
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            // Content
            Group {
                switch selectedTab {
                case .game:     gameTab
                case .menu:     menuTab
                case .settings: settingsTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Tab bar
            HStack(spacing: 0) {
                ForEach(AppTab.allCases, id: \.rawValue) { tab in
                    Button {
                        if tab == .menu && !isInjected { return }
                        selectedTab = tab
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 20))
                            Text(tab.label)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(
                            tab == .menu && !isInjected ? .secondary.opacity(0.4) :
                            (selectedTab == tab ? .accentColor : .secondary)
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .disabled(tab == .menu && !isInjected)
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .onReceive(timer) { _ in now = Date() }
        .task { await checkAvailability() }
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
        ) { _ in handleForeground() }
        .alert("Logout", isPresented: $showLogoutAlert) {
            Button("Logout", role: .destructive) { terminateAll(); session.logout() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Are you sure you want to logout?") }
    }

    // MARK: - GAME Tab

    private var gameTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Status pill
                HStack(spacing: 6) {
                    Circle()
                        .fill(isOnline == true ? Color.green : (isOnline == nil ? Color.orange : Color.red))
                        .frame(width: 7, height: 7)
                    Text(isOnline == true ? "Online" : (isOnline == nil ? "Checking..." : "Offline"))
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    if isInjected {
                        Label("Injected", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.green)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                // Game cards
                gameCard(game: .freeFire,    state: $ffState,    activeSession: $ffSession)
                gameCard(game: .freefireMax, state: $ffmaxState, activeSession: $ffmaxSession)

                if isInjected {
                    Button {
                        selectedTab = .menu
                    } label: {
                        Label("Open Cheat Menu", systemImage: "slider.horizontal.3")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal, 20)
                }

                Spacer(minLength: 40)
            }
        }
    }

    @ViewBuilder
    private func gameCard(
        game: FFGame,
        state: Binding<InjectState>,
        activeSession: Binding<InjectSession?>
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.displayName)
                        .font(.system(size: 16, weight: .semibold))
                    Text(game.bundleID)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Spacer()
                injectButton(game: game, state: state, activeSession: activeSession)
            }
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(14)
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func injectButton(
        game: FFGame,
        state: Binding<InjectState>,
        activeSession: Binding<InjectSession?>
    ) -> some View {
        let cur = state.wrappedValue
        Button {
            Task { await doInject(game: game, state: state, activeSession: activeSession) }
        } label: {
            Group {
                switch cur {
                case .checking, .injecting:
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(width: 18, height: 18)
                case .done:
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                        Text("Injected").font(.system(size: 13, weight: .semibold))
                    }
                case .unavailable:
                    Text("Unavailable").font(.system(size: 12, weight: .semibold))
                default:
                    Text("Inject").font(.system(size: 13, weight: .semibold))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(stateColor(cur))
            .foregroundColor(.white)
            .cornerRadius(9)
        }
        .disabled(cur == .unavailable || cur == .checking || cur == .injecting)
    }

    private func stateColor(_ s: InjectState) -> Color {
        switch s {
        case .unavailable, .checking: return Color.secondary.opacity(0.4)
        case .done:    return .green
        case .failed:  return .red
        default:       return .accentColor
        }
    }

    // MARK: - MENU Tab

    @ViewBuilder private var aimTypePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Aim Type").font(.system(size: 14)).foregroundColor(.secondary)
            Picker("", selection: $cheat.aimType) {
                ForEach(CheatSettings.AimType.allCases, id: \.self) { t in Text(t.label).tag(t) }
            }.pickerStyle(.segmented)
        }.padding(.horizontal, 16).padding(.vertical, 10)
    }

    @ViewBuilder private var aimTargetPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Aim Target").font(.system(size: 14)).foregroundColor(.secondary)
            Picker("", selection: $cheat.aimTarget) {
                ForEach(CheatSettings.AimTarget.allCases, id: \.self) { t in Text(t.label).tag(t) }
            }.pickerStyle(.segmented)
        }.padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var menuTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Cheat Menu")
                    .font(.system(size: 17, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                // ESP
                settingsSection(header: "ESP") {
                    toggle("ESP ON/OFF", $cheat.espEnabled, risk: false)
                    toggle("Line", $cheat.espLine, risk: false)
                    toggle("Box", $cheat.espBox, risk: false)
                    toggle("Health", $cheat.espHealth, risk: false)
                    toggle("Name", $cheat.espName, risk: false)
                    toggle("Player Count", $cheat.espPlayerCount, risk: false)
                }

                // AIM
                settingsSection(header: "AIM") {
                    toggle("Enable AIM", $cheat.aimEnabled, risk: false)

                    aimTypePicker
                    aimTargetPicker

                    toggle("Ignore Knockdown", $cheat.aimIgnoreKnockdown, risk: false)
                    toggle("Draw FOV", $cheat.aimDrawFov, risk: false)

                    // FOV Slider
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Value FOV")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "%.0f", cheat.aimFovValue))
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        }
                        .padding(.horizontal, 16)
                        Slider(value: $cheat.aimFovValue, in: 0...500, step: 1)
                            .padding(.horizontal, 16)
                            .accentColor(.accentColor)
                    }
                    .padding(.vertical, 10)
                }

                // MISC
                settingsSection(header: "MISC") {
                    toggle("No Recoil", $cheat.miscNoRecoil, risk: true)
                    toggle("Speed", $cheat.miscSpeed, risk: true)
                    toggle("Fast Landing", $cheat.miscFastLanding, risk: true)
                    toggle("Fast Medkit", $cheat.miscFastMedkit, risk: true)
                    toggle("Fast Revive", $cheat.miscFastRevive, risk: true)
                }

                Spacer(minLength: 40)
            }
        }
        .onChange(of: cheat.espEnabled)      { [self] _ in cheat.save(); self.updateFeatureFiles() }
        .onChange(of: cheat.espLine) { _ in cheat.save() }
        .onChange(of: cheat.espBox) { _ in cheat.save() }
        .onChange(of: cheat.espHealth) { _ in cheat.save() }
        .onChange(of: cheat.espName) { _ in cheat.save() }
        .onChange(of: cheat.espPlayerCount) { _ in cheat.save() }
        .onChange(of: cheat.aimEnabled) { _ in cheat.save() }
        .onChange(of: cheat.aimType) { _ in cheat.save() }
        .onChange(of: cheat.aimTarget) { _ in cheat.save() }
        .onChange(of: cheat.aimIgnoreKnockdown) { _ in cheat.save() }
        .onChange(of: cheat.aimDrawFov) { _ in cheat.save() }
        .onChange(of: cheat.aimFovValue) { _ in cheat.save() }
        .onChange(of: cheat.miscNoRecoil) { _ in cheat.save() }
        .onChange(of: cheat.miscSpeed) { _ in cheat.save() }
        .onChange(of: cheat.miscFastLanding) { _ in cheat.save() }
        .onChange(of: cheat.miscFastMedkit) { _ in cheat.save() }
        .onChange(of: cheat.miscFastRevive) { _ in cheat.save() }
    }

    @ViewBuilder
    private func settingsSection<Content: View>(
        header: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(header)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                content()
            }
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(14)
            .padding(.horizontal, 20)
        }
    }

    @ViewBuilder
    private func toggle(_ label: String, _ binding: Binding<Bool>, risk: Bool) -> some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 15))
                    if risk {
                        Text("⚠ risk")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                    }
                }
                Spacer()
                Toggle("", isOn: binding)
                    .toggleStyle(SwitchToggleStyle(tint: .accentColor))
                    .labelsHidden()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider().padding(.leading, 16)
        }
    }

    // MARK: - SETTINGS Tab

    private var settingsTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Key + info card
                VStack(alignment: .leading, spacing: 12) {
                    if let key = session.licenseInfo?.key {
                        HStack {
                            Text("Key")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(LicenseService.maskedKey(key))
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                        }
                        Divider()
                    }

                    // Expiry countdown
                    HStack {
                        Text("Expired")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        Spacer()
                        if let exp = session.licenseInfo?.expiryDate {
                            Text(LicenseService.countdownString(from: exp))
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundColor(exp.timeIntervalSinceNow < 3600 ? .red : .primary)
                        }
                    }
                    Divider()

                    // Device model
                    HStack {
                        Text("Device Model")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(AppInfo.iPhoneModel)
                            .font(.system(size: 13, weight: .medium))
                    }
                    Divider()

                    // iOS version
                    HStack {
                        Text("iOS Version")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(AppInfo.iOSVersion)
                            .font(.system(size: 13, weight: .medium))
                    }
                    Divider()

                    // Support status
                    HStack {
                        Text("Supported")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        Spacer()
                        let vt = AppInfo.versionTuple
                        let supported = ExploitSupportPolicy.isSupported(
                            major: vt.major, minor: vt.minor,
                            patch: vt.patch, build: AppInfo.osBuild)
                        if supported {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.seal.fill")
                                    .foregroundColor(.green)
                                Text("Verified")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.green)
                            }
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark.seal.fill")
                                    .foregroundColor(.red)
                                Text("Not Supported")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(14)
                .padding(.horizontal, 20)
                .padding(.top, 16)

                // Language
                VStack(spacing: 0) {
                    ForEach(FFLanguage.allCases) { lang in
                        Button {
                            LanguageStore.shared.select(lang)
                        } label: {
                            HStack {
                                Text(lang.displayName)
                                    .font(.system(size: 14))
                                    .foregroundColor(.primary)
                                Spacer()
                                if LanguageStore.shared.current == lang {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                        }
                        .buttonStyle(.plain)
                        if lang != FFLanguage.allCases.last {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(14)
                .padding(.horizontal, 20)

                // Telegram
                Button {
                    if let url = URL(string: "https://t.me/ffexternal") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 14))
                        Text("t.me/ffexternal")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                }

                // Logout
                Button(role: .destructive) {
                    showLogoutAlert = true
                } label: {
                    Text("Logout")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                        .padding(.horizontal, 20)
                }

                Spacer(minLength: 40)
            }
        }
    }

    // MARK: - Inject flow

    private func doInject(
        game: FFGame,
        state: Binding<InjectState>,
        activeSession: Binding<InjectSession?>
    ) async {
        guard case .ready = state.wrappedValue else { return }
        guard let key = session.licenseInfo?.key else { return }

        // Check iOS support before inject
        let vt = AppInfo.versionTuple
        guard ExploitSupportPolicy.isSupported(
            major: vt.major, minor: vt.minor,
            patch: vt.patch, build: AppInfo.osBuild) else {
            await MainActor.run {
                showUnsupportedAlert()
            }
            return
        }

        let revalResult = await LicenseService.revalidateBackground(key: key)
        guard case .ok = revalResult else {
            await MainActor.run { session.logout() }
            return
        }

        await MainActor.run { state.wrappedValue = .injecting }

        do {
            let injectSession = try await FFInjectService.inject(game: game, key: key)
            await MainActor.run {
                activeSession.wrappedValue = injectSession
                state.wrappedValue = .done
                isInjected = true
                // Write feature .dat files
                FFInjectService.writeFeatureFiles(game: game, session: injectSession)
                // Auto switch to MENU tab
                selectedTab = .menu
            }
            try? await Task.sleep(nanoseconds: 600_000_000)
            FFInjectService.launchAndScheduleWipe(game: game, session: injectSession)
        } catch {
            await MainActor.run {
                state.wrappedValue = .failed(error.localizedDescription)
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run { state.wrappedValue = .ready }
        }
    }

    @State private var showUnsupported = false

    private func showUnsupportedAlert() {
        // Use a local alert instead of UIAlertController for simplicity
        showUnsupported = true
    }

    private func checkAvailability() async {
        let ok = await FFAvailabilityService.checkAvailability()
        await MainActor.run {
            isOnline   = ok
            ffState    = ok ? .ready : .unavailable
            ffmaxState = ok ? .ready : .unavailable
        }
    }

    // Called when user explicitly logs out or starts fresh session
    private func terminateAll() {
        if let s = ffSession    { FFInjectService.terminateSession(s); ffSession = nil }
        if let s = ffmaxSession { FFInjectService.terminateSession(s); ffmaxSession = nil }
        isInjected = false
        selectedTab = .game
    }

    // Update feature .dat files in game container when user changes toggle
    private func updateFeatureFiles() {
        guard isInjected else { return }
        if let s = ffSession {
            FFInjectService.writeFeatureFiles(game: .freeFire, session: s)
        } else if let s = ffmaxSession {
            FFInjectService.writeFeatureFiles(game: .freefireMax, session: s)
        }
    }

    // Called when FFEX comes to foreground (user switches back from FF)
    // Wipe files from disk (patch already loaded in FF memory) but keep menu accessible
    private func handleForeground() {
        // Wipe files — patch stays active in FF memory
        if let s = ffSession    { s.wipeNow() }
        if let s = ffmaxSession { s.wipeNow() }
        // Revalidate key immediately — instant logout if key deleted/banned
        guard let key = session.licenseInfo?.key else { return }
        Task {
            let result = await LicenseService.revalidateBackground(key: key)
            await MainActor.run {
                switch result {
                case .revoked(let reason):
                    session.logout(reason: reason)
                case .ok:
                    break // still valid
                case .networkError:
                    break // offline — keep session
                }
            }
        }
    }
}

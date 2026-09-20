import SwiftUI

struct LoginView: View {
    @EnvironmentObject var session: SessionStore

    @State private var keyInput    = ""
    @State private var isValidating = false
    @State private var errorMessage: String? = nil
    @State private var didAppear   = false
    @State private var keyVisible  = false

    // Support check
    private var vt: (major: Int, minor: Int, patch: Int) { AppInfo.versionTuple }
    private var isSupported: Bool {
        ExploitSupportPolicy.isSupported(
            major: vt.major, minor: vt.minor,
            patch: vt.patch, build: AppInfo.osBuild)
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 32) {

                    // ── Logo / title
                    VStack(spacing: 8) {
                        Text("FFEX")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)

                        Text("Free Fire External")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 60)

                    // ── Key input
                    VStack(spacing: 12) {
                        HStack {
                            Group {
                                if keyVisible {
                                    TextField("FFEX-XXXX-XXXX-XXXX", text: $keyInput)
                                } else {
                                    SecureField("FFEX-XXXX-XXXX-XXXX", text: $keyInput)
                                }
                            }
                            .font(.system(size: 15, design: .monospaced))
                            .autocapitalization(.allCharacters)
                            .disableAutocorrection(true)
                            .keyboardType(.asciiCapable)
                            .onChange(of: keyInput) { v in
                                keyInput = v.uppercased()
                                errorMessage = nil
                            }

                            Button {
                                keyVisible.toggle()
                            } label: {
                                Image(systemName: keyVisible ? "eye.slash" : "eye")
                                    .font(.system(size: 15))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(12)

                        // Error
                        if let err = errorMessage {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 13))
                                Text(err)
                                    .font(.system(size: 13))
                            }
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                        }

                        // Validate button
                        Button { validate() } label: {
                            ZStack {
                                if isValidating {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Text("Activate")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(
                                keyInput.isEmpty
                                    ? Color.accentColor.opacity(0.35)
                                    : Color.accentColor
                            )
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(keyInput.isEmpty || isValidating)
                    }
                    .padding(.horizontal, 24)

                    // ── Device info card
                    VStack(spacing: 0) {
                        row("Device",      AppInfo.iPhoneModel)
                        Divider().padding(.leading, 16)
                        row("iOS",         AppInfo.iOSVersion)
                        Divider().padding(.leading, 16)
                        HStack {
                            Text("Support")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                            Spacer()
                            if isSupported {
                                Label("Verified", systemImage: "checkmark.seal.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.green)
                            } else {
                                Label("Not Supported", systemImage: "xmark.seal.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                    }
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(14)
                    .padding(.horizontal, 24)

                    // ── Telegram
                    Button {
                        if let url = URL(string: "https://t.me/ffexternal") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("t.me/ffexternal", systemImage: "paperplane.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.accentColor)
                    }

                    Spacer(minLength: 40)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            guard !didAppear else { return }
            didAppear = true
            if let msg = session.revocationMessage {
                errorMessage = msg
                session.revocationMessage = nil
            }
            Task { await session.restoreAsync() }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }

    // MARK: - Validate

    private func validate() {
        guard !keyInput.isEmpty, !isValidating else { return }

        // iOS unsupported check
        if !isSupported {
            errorMessage = "YOUR DEVICE IOS IS NOT SUPPORTED"
            return
        }

        isValidating  = true
        errorMessage  = nil

        Task {
            do {
                let info = try await LicenseService.validate(key: keyInput)
                await MainActor.run { session.login(info: info) }
            } catch let e as LicenseError {
                await MainActor.run {
                    switch e {
                    case .revoked(let r): errorMessage = r.displayMessage
                    case .networkError:   errorMessage = "Unable to connect. Try again."
                    }
                    isValidating = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Invalid key."
                    isValidating = false
                }
            }
        }
    }
}

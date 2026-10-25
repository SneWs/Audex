import SwiftUI

struct ServerSetupView: View {
    @Environment(AppSession.self) private var session

    @State private var serverInput = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "waveform.book.closed.fill")
                            .font(.system(size: 46))
                            .foregroundStyle(AudexColor.coral)
                            .symbolRenderingMode(.hierarchical)

                        Text("Connect to Audex")
                            .font(.largeTitle.weight(.bold))

                        Text("Enter the URL of your self-hosted Audex server to access your audiobook library.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Server URL")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)

                        TextField("https://audex.example.com/api", text: $serverInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                            .textContentType(.URL)
                            .padding(14)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Button {
                        Task { await connect() }
                    } label: {
                        HStack {
                            if isSaving {
                                ProgressView().tint(.white)
                            } else {
                                Text("Save & Continue")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AudexColor.coral)
                    .disabled(isSaving || serverInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(24)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .onAppear {
                serverInput = session.settings.serverURLString
            }
        }
    }

    private func connect() async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }
        do {
            try await session.saveServerURL(serverInput)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct LoginView: View {
    @Environment(AppSession.self) private var session

    @State private var serverInput = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "headphones.circle.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(AudexColor.coral)

                        Text("Welcome back")
                            .font(.largeTitle.weight(.bold))

                        Text("Sign in to your Audex server")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let banner = session.sessionBannerMessage {
                        Label(banner, systemImage: "clock.badge.exclamationmark")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(AudexColor.coral)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(AudexColor.coral.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    }

                    VStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Server URL")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)

                            TextField("https://your-server.com/api", text: $serverInput)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                                .textContentType(.URL)
                                .padding(14)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Email")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)

                            TextField("you@example.com", text: $email)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.emailAddress)
                                .textContentType(.username)
                                .padding(14)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Password")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)

                            SecureField("Password", text: $password)
                                .textContentType(.password)
                                .padding(14)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }

                    Button {
                        Task { await signIn() }
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text("Sign In")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AudexColor.coral)
                    .disabled(
                        isLoading
                            || serverInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || password.isEmpty
                    )
                }
                .padding(24)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .onAppear {
                serverInput = !session.settings.serverURLString.isEmpty
                    ? session.settings.serverURLString
                    : (session.serverURL?.absoluteString ?? "")
            }
        }
    }

    private func signIn() async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try session.applyServerURLWithoutRemoteValidation(serverInput)
            try await session.login(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

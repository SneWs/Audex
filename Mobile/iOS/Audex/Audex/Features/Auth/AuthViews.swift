import SwiftUI

struct ServerSetupView: View {
    @Environment(AppSession.self) private var session
    @State private var url = ""
    @State private var error: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                brand
                Text("Connect to your Audex server")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("Enter the exact base URL of your Audex API. Nothing is added to it, so include any path you deployed under, for example http://192.168.1.10:5010/api")
                    .font(.subheadline)
                    .foregroundStyle(AudexColor.onSurfaceVariant)
                    .multilineTextAlignment(.center)

                TextField("https://your-server.example/api", text: $url)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.URL)
                    #if os(iOS)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    #endif

                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Task { await save() }
                } label: {
                    if isSaving {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Save and Continue")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isSaving || url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()
            }
            .padding(24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AudexColor.background.ignoresSafeArea())
            .navigationTitle("Audex")
        }
        .onAppear {
            if url.isEmpty {
                url = session.settings.serverURLString
            }
        }
    }

    private var brand: some View {
        Image(systemName: "headphones")
            .font(.system(size: 44, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 88, height: 88)
            .background(AudexColor.primary, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func save() async {
        error = nil
        isSaving = true
        defer { isSaving = false }
        do {
            try await session.saveServerURL(url)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct LoginView: View {
    @Environment(AppSession.self) private var session
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isRegistering = false
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "headphones")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 72, height: 72)
                        .background(AudexColor.primary, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .padding(.top, 32)

                    Text(isRegistering ? "Create account" : "Audex Login")
                        .font(.largeTitle.bold())

                    if let message = session.sessionExpiredMessage, !isRegistering {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(AudexColor.primary)
                    }

                    TextField("Email", text: $email)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.username)
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        #endif

                    SecureField("Password", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(isRegistering ? .newPassword : .password)

                    if isRegistering {
                        SecureField("Confirm password", text: $confirmPassword)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.newPassword)
                    }

                    if let error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        Task { await submit() }
                    } label: {
                        if isWorking {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text(isRegistering ? "Register" : "Login")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isWorking)

                    Button(isRegistering ? "Already have an account? Log in" : "Need an account? Register") {
                        isRegistering.toggle()
                        error = nil
                    }
                    .font(.subheadline)

                    Button("Change server") {
                        session.clearServerURL()
                    }
                    .font(.footnote)
                    .foregroundStyle(AudexColor.onSurfaceVariant)
                }
                .padding(24)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
            }
            .background(AudexColor.background.ignoresSafeArea())
        }
    }

    private func submit() async {
        error = nil
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            error = "Email and password are required."
            return
        }
        if isRegistering {
            guard password.count >= 6 else {
                error = "Password must be at least 6 characters."
                return
            }
            guard password == confirmPassword else {
                error = "Passwords do not match."
                return
            }
        }

        isWorking = true
        defer { isWorking = false }
        do {
            if isRegistering {
                try await session.register(email: trimmedEmail, password: password)
            } else {
                try await session.login(email: trimmedEmail, password: password)
            }
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            self.error = message.isEmpty ? "Login failed" : message
        }
    }
}

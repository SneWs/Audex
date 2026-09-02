import SwiftUI

struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @State private var serverURL = ""
    @State private var status: String?
    @State private var error: String?
    @State private var isSaving = false
    @State private var confirmLogout = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://your-server.example/api", text: $serverURL)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        #endif
                    Button {
                        Task { await saveServer() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save Settings")
                        }
                    }
                    .disabled(isSaving)
                    if let status {
                        Text(status).foregroundStyle(AudexColor.primary)
                    }
                    if let error {
                        Text(error).foregroundStyle(.red)
                    }
                } header: {
                    Text("Server")
                } footer: {
                    Text("Used as the API root with no extra path added. Include /api or any other prefix your deployment uses.")
                }

                Section("Appearance") {
                    Toggle("Dark mode", isOn: Binding(
                        get: { session.prefersDarkMode },
                        set: { session.prefersDarkMode = $0 }
                    ))
                }

                Section("Account") {
                    LabeledContent("Signed in as", value: session.account?.email ?? "—")
                }

                Section {
                    Button("Logout", role: .destructive) {
                        confirmLogout = true
                    }
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                serverURL = session.settings.serverURLString
            }
            .task {
                await session.loadAccount()
            }
            .confirmationDialog("Logout", isPresented: $confirmLogout) {
                Button("Logout", role: .destructive) {
                    session.logout()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Are you sure you want to logout? You will need to log in again to access your library.")
            }
        }
    }

    private func saveServer() async {
        error = nil
        status = nil
        isSaving = true
        defer { isSaving = false }
        do {
            try await session.saveServerURL(serverURL)
            status = "Settings saved and validated"
            serverURL = session.settings.serverURLString
        } catch {
            self.error = error.localizedDescription
        }
    }

}

import FamilyControls
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(AppBlocker.self) private var blocker

    @AppStorage(Prefs.doublePressKey) private var doublePress = "song"
    @AppStorage(Prefs.serverKey) private var server = Prefs.defaultServer
    @AppStorage(Prefs.userKey) private var user = ""
    @AppStorage(Prefs.passwordKey) private var password = ""
    @AppStorage("strongCreateRoutines") private var createRoutines = true
    @AppStorage(AppBlocker.enabledKey) private var blockApps = true
    @State private var showAppPicker = false

    @State private var connectionResult: String?
    @State private var importing = false
    @State private var importMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                VoiceSettingsSection()

                Section {
                    Picker("Double press", selection: $doublePress) {
                        Text("Next song").tag("song")
                        Text("Skip exercise").tag("skip")
                    }
                } header: {
                    Text("AirPods")
                } footer: {
                    Text("1× press: set done, or skip the rest.\n2× press: next song while music plays, otherwise skip the exercise.\n3× press: repeat the announcement.\nThis only works while a workout is running in this app. Music from other apps (Amperfy, Spotify) would take over the presses, so play your music here.")
                }

                Section {
                    Toggle("Block apps during workouts", isOn: $blockApps)
                    if blockApps {
                        if blocker.isAuthorized {
                            Button {
                                showAppPicker = true
                            } label: {
                                LabeledContent("Apps to block", value: blocker.selectedCount == 0 ? "None" : "\(blocker.selectedCount) selected")
                            }
                        } else {
                            Button("Allow Screen Time access") {
                                Task { await blocker.requestAuthorization() }
                            }
                        }
                        if let error = blocker.errorMessage {
                            Text(error).font(.caption).foregroundStyle(.red)
                        }
                    }
                } header: {
                    Text("Focus")
                } footer: {
                    Text("While a workout runs, the selected apps show a Screen Time block screen. They unlock when you finish or discard the workout.")
                }

                Section {
                    TextField("Server URL", text: $server)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Username", text: $user)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                    Button("Test connection") { testConnection() }
                        .disabled(server.isEmpty || user.isEmpty)
                    if let connectionResult {
                        Text(connectionResult).font(.caption)
                    }
                } header: {
                    Text("Music (Navidrome / Subsonic)")
                } footer: {
                    Text("Use the same server and login as in Amperfy.")
                }

                Section {
                    Toggle("Create routines from Strong workouts", isOn: $createRoutines)
                    Button {
                        importing = true
                    } label: {
                        Label("Import Strong CSV…", systemImage: "square.and.arrow.down")
                    }
                    ShareLink(item: store.fileURL) {
                        Label("Export backup (JSON)", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("In Strong: Settings → Export Strong Data, save the file, then import it here. Workouts that were already imported are skipped.")
                }

                Section {
                    Text("Tip: create an iOS Focus mode (e.g. “Gym”) that silences notifications and hides distracting apps while you train.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .onAppear { blocker.refreshAuthorization() }
            .familyActivityPicker(
                isPresented: $showAppPicker,
                selection: Binding(get: { blocker.selection }, set: { blocker.setSelection($0) }))
            .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText, .text, .data]) { result in
                handleImport(result)
            }
            .alert(
                "Strong import",
                isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })
            ) {
                Button("OK") {}
            } message: {
                Text(importMessage ?? "")
            }
        }
    }

    private func testConnection() {
        connectionResult = "Connecting…"
        let client = SubsonicClient(server: server, user: user, password: password)
        Task {
            do {
                try await client.ping()
                connectionResult = "Connected ✓"
            } catch {
                connectionResult = "Failed: \(error.localizedDescription)"
            }
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            importMessage = error.localizedDescription
        case .success(let url):
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let text: String
                if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
                    text = utf8
                } else {
                    text = try String(contentsOf: url, encoding: .isoLatin1)
                }
                let summary = try StrongImporter.importCSV(text, into: store, createRoutines: createRoutines)
                var message = "Imported \(summary.workouts) workouts, \(summary.exercises) new exercises and \(summary.routines) routines."
                if summary.duplicates > 0 { message += " Skipped \(summary.duplicates) already imported." }
                importMessage = message
            } catch {
                importMessage = error.localizedDescription
            }
        }
    }
}

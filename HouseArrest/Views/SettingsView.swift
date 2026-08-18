import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("ha.appearance") private var appearanceRaw = HAAppearance.system.rawValue
    @State private var copied = false

    var body: some View {
        NavigationStack {
            List {
                Section("Appearance") {
                    Picker("Theme", selection: $appearanceRaw) {
                        ForEach(HAAppearance.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Access") {
                    LabeledContent("Bundle ID", value: Bundle.main.bundleIdentifier ?? "—")
                    Text("Container access uses the MobileHouseArrest identity plus MCM / bad_query.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Diagnostics") {
                    NavigationLink {
                        LogsView()
                    } label: {
                        Label("Logs", systemImage: "terminal.fill")
                    }
                    Button {
                        appModel.copyLogs()
                        copied = true
                    } label: {
                        Label(copied ? "Copied" : "Copy logs", systemImage: "doc.on.doc")
                    }
                    .disabled(appModel.logLines.isEmpty)
                }

                Section("About") {
                    LabeledContent("App", value: "HouseArrest")
                    LabeledContent("Focus", value: "Patch tool (app + App Group)")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

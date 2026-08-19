import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
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
                        accentLabel("Logs", "terminal.fill")
                    }
                    Button {
                        appModel.copyLogs()
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            copied = false
                        }
                    } label: {
                        accentLabel(copied ? "Copied" : "Copy logs", "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .disabled(appModel.logLines.isEmpty)
                }

                Section("About") {
                    LabeledContent("App", value: "HouseArrest")
                    LabeledContent("Focus", value: "Patch tool (app + App Group)")
                }
            }
            .tint(HATheme.accent)
            .listItemTint(HATheme.accent)
            .navigationTitle("Settings")
        }
        .tint(HATheme.accent)
    }

    private func accentLabel(_ title: String, _ icon: String) -> some View {
        Label {
            Text(title).foregroundStyle(HATheme.accent)
        } icon: {
            Image(systemName: icon)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(HATheme.accent)
        }
    }
}

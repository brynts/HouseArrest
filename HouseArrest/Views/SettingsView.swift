import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Access") {
                    LabeledContent("Bundle ID", value: Bundle.main.bundleIdentifier ?? "—")
                    Text("Container access requires the MobileHouseArrest identity and a wired MCM / bad_query layer in ContainerAccess.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

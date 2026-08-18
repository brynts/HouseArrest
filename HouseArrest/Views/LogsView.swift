import SwiftUI

struct LogsView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            List {
                if appModel.logLines.isEmpty {
                    Text("No log lines yet.")
                        .foregroundStyle(HATheme.secondaryText)
                } else {
                    ForEach(Array(appModel.logLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Logs")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Copy") {
                        appModel.copyLogs()
                        copied = true
                    }
                    .disabled(appModel.logLines.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") { appModel.logLines.removeAll() }
                        .disabled(appModel.logLines.isEmpty)
                }
            }
        }
    }
}

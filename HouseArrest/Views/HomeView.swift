import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appModel: AppModel

    private var records: [InstalledPatchRecord] {
        appModel.installedPatches.values.sorted {
            $0.receipt.appliedAt > $1.receipt.appliedAt
        }
    }

    var body: some View {
        NavigationStack {
            List {
                deviceSection
                patchesSection
            }
            .navigationTitle("HouseArrest")
            .tint(HATheme.accent)
        }
        .tint(HATheme.accent)
    }

    private var deviceSection: some View {
        let d = appModel.device
        return Section("Device") {
            row("Hardware", d.hardwareModel)
            row("iOS", "\(d.systemVersion) (\(d.buildNumber))")
            HStack {
                Text("Compatibility")
                Spacer()
                if d.isSupported {
                    Label("Supported", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Limited", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                }
            }
            Text(d.supportNote)
                .font(.caption)
                .foregroundStyle(HATheme.secondaryText)
        }
    }

    private var patchesSection: some View {
        Section("Installed patches") {
            if records.isEmpty {
                Text("No patches applied")
                    .foregroundStyle(HATheme.secondaryText)
            } else {
                ForEach(records, id: \.bundleID) { record in
                    NavigationLink {
                        PatchRecordView(record: record)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.projectName)
                            Text(record.bundleID)
                                .font(.caption)
                                .foregroundStyle(HATheme.secondaryText)
                            Text("\(record.receipt.entries.count) file(s)")
                                .font(.caption)
                                .foregroundStyle(HATheme.secondaryText)
                        }
                    }
                }
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(HATheme.secondaryText)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct PatchRecordView: View {
    let record: InstalledPatchRecord

    private var groups: [(target: String, files: [ApplyReceipt.Entry])] {
        var map: [String: [ApplyReceipt.Entry]] = [:]
        for entry in record.receipt.entries {
            map[entry.targetID, default: []].append(entry)
        }
        return map.keys.sorted().map { ($0, map[$0] ?? []) }
    }

    var body: some View {
        List {
            Section("Patch") {
                row("Name", record.projectName)
                row("App", record.bundleID)
                row("Files", "\(record.receipt.entries.count)")
                row("Applied", record.receipt.appliedAt.formatted(date: .abbreviated, time: .shortened))
            }
            ForEach(groups, id: \.target) { group in
                Section(group.target) {
                    ForEach(group.files, id: \.relativePath) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.relativePath)
                            if entry.backupPath != nil {
                                Text("Original backed up")
                                    .font(.caption)
                                    .foregroundStyle(HATheme.secondaryText)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(record.projectName)
        .navigationBarTitleDisplayMode(.inline)
        .tint(HATheme.accent)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(HATheme.secondaryText)
                .multilineTextAlignment(.trailing)
        }
    }
}

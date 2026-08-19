import SwiftUI

struct DeviceStorage {
    var used: Int64
    var total: Int64

    var free: Int64 { max(total - used, 0) }
    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(Double(used) / Double(total), 1)
    }

    var usedLabel: String { Self.bytes(used) }
    var totalLabel: String { Self.bytes(total) }
    var freeLabel: String { Self.bytes(free) }

    static func current() -> DeviceStorage {
        let url = URL(fileURLWithPath: "/")
        let values = try? url.resourceValues(forKeys: [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ])
        let total = Int64(values?.volumeTotalCapacity ?? 0)
        let available = values?.volumeAvailableCapacityForImportantUsage ?? 0
        return DeviceStorage(used: max(total - available, 0), total: total)
    }

    private static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}

struct CleanerView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var apps: [InstalledApp] = []
    @State private var selected = Set<String>()
    @State private var storage = DeviceStorage.current()
    @State private var cleanCaches = true
    @State private var cleanTmp = true
    @State private var loading = false
    @State private var busy = false
    @State private var askClean = false
    @State private var progressText = ""
    @State private var message: String?

    private var selectedApps: [InstalledApp] {
        apps.filter { selected.contains($0.bundleID) }
    }

    var body: some View {
        NavigationStack {
            List {
                storageSection
                optionsSection
                appsSection
            }
            .navigationTitle("Cleaner")
            .tint(HATheme.accent)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(selected.count == apps.count && !apps.isEmpty ? "None" : "Select All") {
                        if selected.count == apps.count {
                            selected.removeAll()
                        } else {
                            selected = Set(apps.map(\.bundleID))
                        }
                    }
                    .disabled(apps.isEmpty || busy)
                    .foregroundStyle(HATheme.accent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if loading || busy {
                        ProgressView()
                    } else {
                        Button(action: reload) {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(HATheme.accent)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    askClean = true
                } label: {
                    Text(busy ? progressText : "Clean \(selected.count) app\(selected.count == 1 ? "" : "s")")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(HATheme.accent)
                .disabled(selected.isEmpty || (!cleanCaches && !cleanTmp) || busy || loading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.bar)
            }
            .onAppear {
                storage = DeviceStorage.current()
                if apps.isEmpty { reload() }
            }
            .confirmationDialog(
                "Clean selected apps?",
                isPresented: $askClean,
                titleVisibility: .visible
            ) {
                Button("Clean", role: .destructive, action: runClean)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(confirmText)
            }
            .alert("Cleaner", isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
        .tint(HATheme.accent)
    }

    private var confirmText: String {
        var parts: [String] = []
        if cleanCaches { parts.append("Caches") }
        if cleanTmp { parts.append("tmp") }
        return "Clears \(parts.joined(separator: " and ")) for \(selected.count) third-party app\(selected.count == 1 ? "" : "s")."
    }

    private var storageSection: some View {
        Section("iPhone") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Storage")
                    Spacer()
                    Text("\(storage.usedLabel) of \(storage.totalLabel) used")
                        .foregroundStyle(HATheme.secondaryText)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.25))
                        Capsule()
                            .fill(HATheme.accent)
                            .frame(width: max(geo.size.width * storage.fraction, 6))
                    }
                }
                .frame(height: 10)
                Text("\(storage.freeLabel) available")
                    .font(.caption)
                    .foregroundStyle(HATheme.secondaryText)
            }
            .padding(.vertical, 4)
        }
    }

    private var optionsSection: some View {
        Section("Clean") {
            Toggle("Caches", isOn: $cleanCaches)
            Toggle("tmp", isOn: $cleanTmp)
        } footer: {
            Text("Documents are not included. Clean those from an app page.")
        }
    }

    private var appsSection: some View {
        Section("Third-party apps") {
            if loading && apps.isEmpty {
                ProgressView()
            } else if apps.isEmpty {
                Text("No third-party apps")
                    .foregroundStyle(HATheme.secondaryText)
            } else {
                ForEach(apps) { app in
                    Button {
                        if selected.contains(app.bundleID) {
                            selected.remove(app.bundleID)
                        } else {
                            selected.insert(app.bundleID)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selected.contains(app.bundleID) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(HATheme.accent)
                            if let icon = app.icon {
                                Image(uiImage: icon)
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.displayName)
                                    .foregroundStyle(.primary)
                                Text(app.bundleID)
                                    .font(.caption)
                                    .foregroundStyle(HATheme.secondaryText)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }

    private func reload() {
        if loading || busy { return }
        loading = true
        HAWork.queue.async {
            let list = AppDiscoveryService.discover(thirdPartyOnly: true)
            let snap = DeviceStorage.current()
            DispatchQueue.main.async {
                apps = list
                storage = snap
                selected = selected.intersection(Set(list.map(\.bundleID)))
                loading = false
            }
        }
    }

    private func runClean() {
        let targets = selectedApps
        var areas: [AppCleanService.Area] = []
        if cleanCaches { areas.append(.caches) }
        if cleanTmp { areas.append(.tmp) }
        guard !targets.isEmpty, !areas.isEmpty else { return }
        busy = true
        progressText = "Cleaning 0/\(targets.count)"
        HAWork.queue.async {
            var removed = 0
            var failed = 0
            for (index, app) in targets.enumerated() {
                DispatchQueue.main.async {
                    progressText = "Cleaning \(index + 1)/\(targets.count)"
                }
                do {
                    removed += try AppCleanService.clean(
                        bundleID: app.bundleID,
                        containerPath: app.dataContainerPath,
                        areas: areas
                    ) { line in
                        DispatchQueue.main.async { appModel.log(line) }
                    }
                } catch {
                    failed += 1
                    DispatchQueue.main.async {
                        appModel.log("clean failed \(app.bundleID): \(error.localizedDescription)")
                    }
                }
            }
            let snap = DeviceStorage.current()
            DispatchQueue.main.async {
                storage = snap
                busy = false
                progressText = ""
                message = failed == 0
                    ? "Removed \(removed) item\(removed == 1 ? "" : "s")."
                    : "Removed \(removed) item\(removed == 1 ? "" : "s"). Failed \(failed) app\(failed == 1 ? "" : "s")."
            }
        }
    }
}

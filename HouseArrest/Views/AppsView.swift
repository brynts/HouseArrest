import SwiftUI

struct AppsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var apps: [InstalledApp] = []
    @State private var isLoading = false
    @State private var search = ""
    @State private var errorText: String?
    @State private var scanTitle = "Finding apps"
    @State private var scanCurrent = 0
    @State private var scanTotal = 0

    private var filtered: [InstalledApp] {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return apps }
        return apps.filter {
            $0.displayName.localizedCaseInsensitiveContains(q)
                || $0.bundleID.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && apps.isEmpty {
                    VStack(spacing: 8) {
                        Text(scanTitle)
                            .font(.headline)
                        if scanTotal > 0 {
                            Text("\(scanCurrent)/\(scanTotal)")
                                .font(.title3.monospacedDigit())
                                .foregroundStyle(HATheme.secondaryText)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorText, apps.isEmpty {
                    ContentUnavailableView(
                        "Could not list apps",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorText)
                    )
                } else if filtered.isEmpty {
                    ContentUnavailableView(
                        "No third-party apps",
                        systemImage: "square.grid.2x2",
                        description: Text("Pull to refresh.")
                    )
                } else {
                    List(filtered) { app in
                        NavigationLink(value: app.bundleID) {
                            appRow(app)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .safeAreaInset(edge: .top) {
                        if isLoading {
                            Text(scanTotal > 0 ? "\(scanTitle)  \(scanCurrent)/\(scanTotal)" : scanTitle)
                                .font(.footnote)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(HATheme.card)
                        }
                    }
                }
            }
            .background(Color.black)
            .navigationTitle("Apps")
            .navigationDestination(for: String.self) { bundleID in
                if let app = apps.first(where: { $0.bundleID == bundleID }) {
                    AppDetailView(app: app)
                } else {
                    ContentUnavailableView("App not found", systemImage: "app")
                }
            }
            .searchable(text: $search, prompt: "Name or bundle ID")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: refresh) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(isLoading ? Color.secondary : HATheme.accent)
                    }
                    .disabled(isLoading)
                }
            }
            .refreshable { refresh() }
            .onAppear {
                if apps.isEmpty { refresh() }
            }
        }
    }

    private func appRow(_ app: InstalledApp) -> some View {
        HStack(spacing: 12) {
            appIcon(app)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(app.bundleID)
                    .font(.caption)
                    .foregroundStyle(HATheme.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func appIcon(_ app: InstalledApp) -> some View {
        if let icon = app.icon {
            Image(uiImage: icon)
                .resizable()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 44, height: 44)
                Image(systemName: "app.fill")
                    .foregroundStyle(HATheme.accent)
            }
        }
    }

    private func refresh() {
        if isLoading { return }
        isLoading = true
        errorText = nil
        scanTitle = "Finding apps"
        scanCurrent = 0
        scanTotal = 0
        DispatchQueue.global(qos: .userInitiated).async {
            let list = AppDiscoveryService.discover(thirdPartyOnly: true) { title, current, total in
                DispatchQueue.main.async {
                    scanTitle = title
                    scanCurrent = current
                    scanTotal = total
                }
            }
            let probe = [
                HACatalogLastProbe(),
                LaunchServicesStore.lastProbe,
                AppDiscoveryService.lastProbe
            ].joined(separator: "\n")
            DispatchQueue.main.async {
                apps = list
                isLoading = false
                for line in probe.split(separator: "\n") where !line.isEmpty {
                    appModel.log(String(line))
                }
                appModel.log("apps scan third-party=\(list.count)")
                if list.isEmpty {
                    errorText = "No apps resolved. Copy logs from Settings."
                }
            }
        }
    }
}

struct AppDetailView: View {
    @EnvironmentObject private var appModel: AppModel
    let app: InstalledApp
    @State private var message: String?
    @State private var usage: ContainerUsage?
    @State private var measuring = false
    @State private var busy = false
    @State private var pending: PendingClean?
    @State private var showImporter = false

    private var installed: InstalledPatchRecord? {
        appModel.installedPatches[app.bundleID]
    }

    private var canUnpatch: Bool { installed != nil && !busy }

    private struct PendingClean: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let areas: [AppCleanService.Area]
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.secondary.opacity(0.25))
                            .frame(width: 64, height: 64)
                        if let icon = app.icon {
                            Image(uiImage: icon)
                                .resizable()
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        } else {
                            Image(systemName: "app.fill")
                                .font(.title)
                                .foregroundStyle(HATheme.accent)
                        }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.displayName).font(.title3.bold())
                        Text(app.bundleID)
                            .font(.caption.monospaced())
                            .foregroundStyle(HATheme.secondaryText)
                            .textSelection(.enabled)
                        if let path = app.dataContainerPath {
                            Text(path)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Actions") {
                Button { stub("Backup") } label: {
                    Label("Backup", systemImage: "externaldrive.badge.timemachine")
                }
                .disabled(busy)
                Button { stub("Browse files") } label: {
                    Label("Browse files", systemImage: "folder")
                }
                .disabled(busy)
                Button { showImporter = true } label: {
                    Label("Patch", systemImage: "wrench.and.screwdriver")
                }
                .disabled(busy)
            }

            Section {
                if let installed {
                    Text(installed.projectName)
                    Text("\(installed.receipt.entries.count) file(s)")
                        .font(.caption)
                        .foregroundStyle(HATheme.secondaryText)
                } else {
                    Text("Not patched")
                        .foregroundStyle(HATheme.secondaryText)
                }
                Button(action: unpatch) {
                    Text("Unpatch")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!canUnpatch)
                .foregroundStyle(canUnpatch ? Color.red : Color.secondary)
            } header: {
                Text("Patch")
            } footer: {
                Text(installed == nil
                     ? "Import a .ha package to patch this app."
                     : "Unpatch restores the original files from backup.")
            }

            Section {
                if measuring && usage == nil {
                    ProgressView()
                } else {
                    dataRow("Documents", usage?.documentsLabel) {
                        askClean(.documents)
                    }
                    dataRow("Caches", usage?.cachesLabel) {
                        askClean(.caches)
                    }
                    dataRow("tmp", usage?.tmpLabel) {
                        askClean(.tmp)
                    }
                }
            } header: {
                Text("Data")
            } footer: {
                Text(busy ? "Working…" : "Clean empties Documents, Caches, or tmp.")
            }
        }
        .navigationTitle(app.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadUsage)
        .sheet(isPresented: $showImporter) {
            FileImporterRepresentableView(
                allowedContentTypes: [.haPackage],
                allowsMultipleSelection: false
            ) { urls in
                showImporter = false
                guard !urls.isEmpty else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    handlePatch(urls)
                }
            }
            .ignoresSafeArea()
        }
        .alert("Apps", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
        .confirmationDialog(
            pending?.title ?? "Clean",
            isPresented: Binding(
                get: { pending != nil },
                set: { if !$0 { pending = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Clean", role: .destructive) {
                if let pending { runClean(pending.areas) }
            }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: {
            Text(pending?.detail ?? "")
        }
    }

    private func dataRow(_ title: String, _ size: String?, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(size ?? "—")
                    .font(.caption)
                    .foregroundStyle(HATheme.secondaryText)
            }
            Spacer()
            Button(action: action) {
                if busy {
                    ProgressView()
                } else {
                    Text("Clean")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(HATheme.accent.opacity(0.18), in: Capsule())
                        .foregroundStyle(HATheme.accent)
                }
            }
            .buttonStyle(.plain)
            .disabled(busy || app.dataContainerPath == nil)
        }
    }

    private func handlePatch(_ urls: [URL]) {
        guard let url = urls.first else { return }
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                guard url.pathExtension.lowercased() == "ha" else {
                    throw PatchError.invalidPackage
                }
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                let project = try HAPackageCodec.decode(data)
                let receipt = try PatchApplyService.apply(project: project) { line in
                    DispatchQueue.main.async { appModel.log(line) }
                }
                DispatchQueue.main.async {
                    appModel.addProject(project)
                    appModel.markPatched(bundleID: app.bundleID, projectName: project.name, receipt: receipt)
                    busy = false
                    message = "Applied \(receipt.entries.count) file(s) from \(project.name)."
                    appModel.log("apply ok from apps tab project=\(project.name) files=\(receipt.entries.count)")
                }
            } catch {
                DispatchQueue.main.async {
                    busy = false
                    message = error.localizedDescription
                    appModel.log("apply failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func unpatch() {
        guard let installed else { return }
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try PatchApplyService.restore(receipt: installed.receipt) { line in
                    DispatchQueue.main.async { appModel.log(line) }
                }
                DispatchQueue.main.async {
                    appModel.clearPatch(bundleID: app.bundleID)
                    busy = false
                    message = "Restored original files."
                }
            } catch {
                DispatchQueue.main.async {
                    busy = false
                    message = error.localizedDescription
                    appModel.log("unpatch failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func askClean(_ area: AppCleanService.Area) {
        pending = PendingClean(
            title: "Clean \(area.title)?",
            detail: "Deletes files in \(area.title) for \(app.displayName).",
            areas: [area]
        )
    }

    private func runClean(_ areas: [AppCleanService.Area]) {
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let removed = try AppCleanService.clean(
                    bundleID: app.bundleID,
                    containerPath: app.dataContainerPath,
                    areas: areas,
                    log: { line in
                        DispatchQueue.main.async { appModel.log(line) }
                    }
                )
                let result = app.dataContainerPath.map { AppDiscoveryService.usage(for: $0) }
                DispatchQueue.main.async {
                    if let result { usage = result }
                    busy = false
                    message = "Removed \(removed) item\(removed == 1 ? "" : "s")."
                }
            } catch {
                DispatchQueue.main.async {
                    busy = false
                    message = error.localizedDescription
                    appModel.log("clean failed \(app.bundleID): \(error.localizedDescription)")
                }
            }
        }
    }

    private func loadUsage() {
        guard let path = app.dataContainerPath, usage == nil else { return }
        measuring = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = AppDiscoveryService.usage(for: path)
            DispatchQueue.main.async {
                usage = result
                measuring = false
            }
        }
    }

    private func stub(_ action: String) {
        message = "\(action) for \(app.bundleID) — coming next."
        appModel.log("apps action stub: \(action) → \(app.bundleID)")
    }
}

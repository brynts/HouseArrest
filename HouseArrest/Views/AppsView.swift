import SwiftUI

struct AppsView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var apps: [InstalledApp] = []
    @State private var isLoading = false
    @State private var search = ""
    @State private var errorText: String?

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
                    ProgressView("Scanning apps…")
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
                        NavigationLink(value: app) {
                            appRow(app)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color.black)
            .navigationTitle("Apps")
            .navigationDestination(for: InstalledApp.self) { app in
                AppDetailView(app: app)
            }
            .searchable(text: $search, prompt: "Name or bundle ID")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: refresh) {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(HATheme.accent)
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
        isLoading = true
        errorText = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let list = AppDiscoveryService.discover(thirdPartyOnly: true)
            let probe = HACatalogLastProbe() + "\n" + LaunchServicesStore.lastProbe
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
                Button { stub("Browse files") } label: {
                    Label("Browse files", systemImage: "folder")
                }
                Button { stub("Patch") } label: {
                    Label("Patch", systemImage: "wrench.and.screwdriver")
                }
            }

            Section("Size") {
                if measuring && usage == nil {
                    ProgressView()
                } else {
                    LabeledContent("Documents", value: usage?.documentsLabel ?? "—")
                    LabeledContent("Caches", value: usage?.cachesLabel ?? "—")
                    LabeledContent("tmp", value: usage?.tmpLabel ?? "—")
                }
            }

            Section {
                Button { stub("Clean Caches") } label: {
                    Label("Clean Caches", systemImage: "trash")
                }
                Button { stub("Clean tmp") } label: {
                    Label("Clean tmp", systemImage: "trash")
                }
                Button(role: .destructive) { stub("Reset app data") } label: {
                    Label("Reset app data", systemImage: "arrow.counterclockwise")
                }
            } header: {
                Text("Clean")
            } footer: {
                Text("Backup / Browse / Patch / Clean will be wired next.")
            }
        }
        .navigationTitle(app.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadUsage)
        .alert("Apps", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
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

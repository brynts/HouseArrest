import SwiftUI
import UIKit

struct BrowseRoot: Identifiable, Hashable {
    var id: String { targetID + path }
    var title: String
    var targetID: String
    var path: String
    var isGroup: Bool
}

struct BrowseItem: Identifiable, Hashable {
    var id: String { path }
    var name: String
    var path: String
    var isDirectory: Bool
    var size: Int64?
}

struct ContainerBrowserView: View {
    @EnvironmentObject private var appModel: AppModel
    let app: InstalledApp

    @State private var roots: [BrowseRoot] = []
    @State private var loading = true
    @State private var customID = ""
    @State private var askGroup = false
    @State private var errorText: String?

    var body: some View {
        List {
            Section("App data") {
                if let data = roots.first(where: { !$0.isGroup }) {
                    NavigationLink(data.title) {
                        FolderBrowserView(
                            title: data.title,
                            targetID: data.targetID,
                            rootPath: data.path,
                            currentPath: data.path,
                            isGroup: false
                        )
                    }
                } else {
                    Text("Container unavailable")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach(roots.filter(\.isGroup)) { group in
                    NavigationLink(group.title) {
                        FolderBrowserView(
                            title: group.title,
                            targetID: group.targetID,
                            rootPath: group.path,
                            currentPath: group.path,
                            isGroup: true
                        )
                    }
                }
                Button("Open group ID…") { askGroup = true }
            } header: {
                Text("App Groups")
            } footer: {
                Text("If a group is missing, enter its ID (example: group.woodsign.widgy).")
            }
        }
        .navigationTitle("Browse")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if loading { ProgressView() }
        }
        .alert("App Group", isPresented: $askGroup) {
            TextField("group.example.app", text: $customID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Open") { openCustomGroup() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter the App Group identifier.")
        }
        .alert("Browse", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
        .onAppear(perform: loadRoots)
    }

    private func loadRoots() {
        loading = true
        let bundleID = app.bundleID
        let dataPath = app.dataContainerPath
        HAWork.queue.async {
            var next: [BrowseRoot] = []
            if let dataPath {
                _ = GrantCache.grantOnce(path: dataPath)
                next.append(BrowseRoot(
                    title: bundleID,
                    targetID: bundleID,
                    path: dataPath,
                    isGroup: false
                ))
            }
            for groupID in AppGroupLookup.candidates(for: bundleID) {
                if let path = AppGroupLookup.resolve(groupID) {
                    _ = GrantCache.grantOnce(path: path, groupID: groupID)
                    next.append(BrowseRoot(
                        title: groupID,
                        targetID: groupID,
                        path: path,
                        isGroup: true
                    ))
                    AppGroupLookup.remember(groupID, for: bundleID)
                }
            }
            DispatchQueue.main.async {
                roots = next
                loading = false
                appModel.log("browse roots app=\(next.filter { !$0.isGroup }.count) groups=\(next.filter(\.isGroup).count)")
            }
        }
    }

    private func openCustomGroup() {
        let id = customID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        HAWork.queue.async {
            guard let path = AppGroupLookup.resolve(id) else {
                DispatchQueue.main.async {
                    errorText = "Could not open \(id)"
                    appModel.log("browse group miss \(id)")
                }
                return
            }
            _ = GrantCache.grantOnce(path: path, groupID: id)
            AppGroupLookup.remember(id, for: app.bundleID)
            let root = BrowseRoot(title: id, targetID: id, path: path, isGroup: true)
            DispatchQueue.main.async {
                if !roots.contains(where: { $0.targetID == id }) {
                    roots.append(root)
                }
                customID = ""
                appModel.log("browse group ok \(id)")
            }
        }
    }
}

struct FolderBrowserView: View {
    @EnvironmentObject private var appModel: AppModel
    let title: String
    let targetID: String
    let rootPath: String
    let currentPath: String
    let isGroup: Bool

    @State private var items: [BrowseItem] = []
    @State private var loading = true
    @State private var errorText: String?
    @State private var shareURL: URL?

    var body: some View {
        Group {
            if loading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorText {
                ContentUnavailableView("Cannot read folder", systemImage: "folder.badge.questionmark", description: Text(errorText))
            } else if items.isEmpty {
                ContentUnavailableView("Empty", systemImage: "folder")
            } else {
                List(items) { item in
                    if item.isDirectory {
                        NavigationLink(value: item.path) {
                            row(item)
                        }
                    } else {
                        Button {
                            share(item)
                        } label: {
                            row(item)
                        }
                    }
                }
                .navigationDestination(for: String.self) { path in
                    FolderBrowserView(
                        title: URL(fileURLWithPath: path).lastPathComponent,
                        targetID: targetID,
                        rootPath: rootPath,
                        currentPath: path,
                        isGroup: isGroup
                    )
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .sheet(isPresented: Binding(
            get: { shareURL != nil },
            set: { if !$0 { shareURL = nil } }
        )) {
            if let shareURL {
                ActivityView(items: [shareURL])
            }
        }
    }

    private func row(_ item: BrowseItem) -> some View {
        HStack {
            Image(systemName: item.isDirectory ? "folder.fill" : "doc")
                .foregroundStyle(item.isDirectory ? HATheme.accent : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                if let size = item.size {
                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func load() {
        loading = true
        let path = currentPath
        let groupID = isGroup ? targetID : nil
        HAWork.queue.async {
            _ = GrantCache.grantOnce(path: rootPath, groupID: groupID)
            do {
                let listed = try ContainerLister.list(path: path, rootPath: rootPath)
                DispatchQueue.main.async {
                    items = listed
                    loading = false
                }
            } catch {
                DispatchQueue.main.async {
                    errorText = error.localizedDescription
                    loading = false
                    appModel.log("browse fail \(path): \(error.localizedDescription)")
                }
            }
        }
    }

    private func share(_ item: BrowseItem) {
        HAWork.queue.async {
            do {
                let url = try ContainerLister.exportCopy(path: item.path)
                DispatchQueue.main.async { shareURL = url }
            } catch {
                DispatchQueue.main.async {
                    appModel.log("browse share fail: \(error.localizedDescription)")
                }
            }
        }
    }
}

enum AppGroupLookup {
    static func candidates(for bundleID: String) -> [String] {
        var ids = remembered(for: bundleID)
        ids.append("group.\(bundleID)")
        ids.append("group.\(bundleID.lowercased())")
        let parts = bundleID.split(separator: ".").map(String.init)
        if parts.count >= 2 {
            let vendor = parts[0]
            let name = parts[1]
            ids.append("group.\(vendor).\(name)")
            ids.append("group.\(vendor).\(name.lowercased())")
            if parts.count >= 3 {
                ids.append("group.\(vendor).\(parts[1]).\(parts[2])")
            }
        }
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    static func resolve(_ groupID: String) -> String? {
        let attempts: [(UInt64, Bool)] = [(7, true), (7, false), (2, true), (1, true)]
        for (cls, asGroup) in attempts {
            var err: NSString?
            guard let path = MCMActivateContainerPath(cls, groupID, asGroup, &err) else { continue }
            if PathSafety.isAppGroupRoot(URL(fileURLWithPath: path)) { return path }
        }
        return nil
    }

    static func remember(_ groupID: String, for bundleID: String) {
        var list = remembered(for: bundleID)
        if !list.contains(groupID) {
            list.insert(groupID, at: 0)
            UserDefaults.standard.set(list, forKey: key(bundleID))
        }
    }

    static func remembered(for bundleID: String) -> [String] {
        UserDefaults.standard.stringArray(forKey: key(bundleID)) ?? []
    }

    private static func key(_ bundleID: String) -> String {
        "ha.groups.\(bundleID)"
    }
}

enum ContainerLister {
    static func list(path: String, rootPath: String) throws -> [BrowseItem] {
        let root = URL(fileURLWithPath: rootPath).standardizedFileURL.path
        let current = URL(fileURLWithPath: path).standardizedFileURL.path
        guard current == root || current.hasPrefix(root + "/") else {
            throw PatchError.unsafePath
        }
        let urls = try FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: current),
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: []
        )
        var items: [BrowseItem] = []
        for url in urls {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            let isDir = values?.isDirectory == true
            items.append(BrowseItem(
                name: url.lastPathComponent,
                path: url.path,
                isDirectory: isDir,
                size: isDir ? nil : Int64(values?.fileSize ?? 0)
            ))
        }
        return items.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory && !$1.isDirectory }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    static func exportCopy(path: String) throws -> URL {
        let src = URL(fileURLWithPath: path)
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent(src.lastPathComponent)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: src, to: dest)
        return dest
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

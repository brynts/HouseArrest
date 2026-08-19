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
    @State private var loaded = false
    @State private var customID = ""
    @State private var askGroup = false
    @State private var errorText: String?

    var body: some View {
        List {
            Section("App data") {
                if let data = roots.first(where: { !$0.isGroup }) {
                    NavigationLink {
                        FolderBrowserView(
                            title: data.title,
                            targetID: data.targetID,
                            rootPath: data.path,
                            currentPath: data.path,
                            isGroup: false
                        )
                    } label: {
                        Label(data.title, systemImage: "internaldrive")
                    }
                } else {
                    Text("Container unavailable")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach(roots.filter(\.isGroup)) { group in
                    NavigationLink {
                        FolderBrowserView(
                            title: group.title,
                            targetID: group.targetID,
                            rootPath: group.path,
                            currentPath: group.path,
                            isGroup: true
                        )
                    } label: {
                        Label(group.title, systemImage: "person.2")
                    }
                }
                Button("Open group ID…") { askGroup = true }
            } header: {
                Text("App Groups")
            } footer: {
                Text("Open a group by ID, for example group.woodsign.widgy. It is remembered for this app.")
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
        if loaded { return }
        loaded = true
        loading = true
        let bundleID = app.bundleID
        let dataPath = app.dataContainerPath
        HAWork.queue.async {
            var next: [BrowseRoot] = []
            if let dataPath {
                settleGrant(path: dataPath, groupID: nil)
                next.append(BrowseRoot(
                    title: bundleID,
                    targetID: bundleID,
                    path: dataPath,
                    isGroup: false
                ))
            }
            for groupID in AppGroupLookup.remembered(for: bundleID) {
                if let path = AppGroupLookup.resolve(groupID) {
                    settleGrant(path: path, groupID: groupID)
                    next.append(BrowseRoot(
                        title: groupID,
                        targetID: groupID,
                        path: path,
                        isGroup: true
                    ))
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
            settleGrant(path: path, groupID: id)
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
    @State private var message: String?

    private var isRoot: Bool {
        URL(fileURLWithPath: currentPath).standardizedFileURL.path
            == URL(fileURLWithPath: rootPath).standardizedFileURL.path
    }

    var body: some View {
        Group {
            if loading && items.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorText, items.isEmpty {
                ContentUnavailableView("Cannot read folder", systemImage: "folder.badge.questionmark", description: Text(errorText))
            } else if items.isEmpty {
                ContentUnavailableView("Empty", systemImage: "folder")
            } else {
                List(items) { item in
                    if item.isDirectory {
                        NavigationLink {
                            FolderBrowserView(
                                title: item.name,
                                targetID: targetID,
                                rootPath: rootPath,
                                currentPath: item.path,
                                isGroup: isGroup
                            )
                        } label: {
                            row(item)
                        }
                        .contextMenu { itemMenu(item) }
                    } else if FilePreviewView.canPreview(item.name) {
                        NavigationLink {
                            FilePreviewView(path: item.path, name: item.name, groupID: isGroup ? targetID : nil)
                        } label: {
                            row(item)
                        }
                        .contextMenu { itemMenu(item) }
                    } else {
                        Button { share(item) } label: { row(item) }
                            .contextMenu { itemMenu(item) }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: { load(force: true) }) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(HATheme.accent)
                }
                .disabled(loading)
            }
        }
        .onAppear { load(force: false) }
        .sheet(isPresented: Binding(
            get: { shareURL != nil },
            set: { if !$0 { shareURL = nil } }
        )) {
            if let shareURL {
                ActivityView(items: [shareURL])
            }
        }
        .alert("Browse", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    @ViewBuilder
    private func itemMenu(_ item: BrowseItem) -> some View {
        Button { share(item) } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        Button {
            UIPasteboard.general.string = item.path
            message = "Path copied"
        } label: {
            Label("Copy path", systemImage: "doc.on.doc")
        }
    }

    private func row(_ item: BrowseItem) -> some View {
        HStack {
            Image(systemName: item.isDirectory ? "folder.fill" : FilePreviewView.icon(for: item.name))
                .foregroundStyle(item.isDirectory ? HATheme.accent : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .foregroundStyle(item.name.hasPrefix(".") ? Color.secondary : Color.primary)
                if let size = item.size {
                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func load(force: Bool) {
        if !force && !items.isEmpty { return }
        loading = true
        let path = currentPath
        let root = rootPath
        let groupID = isGroup ? targetID : nil
        let showShortcuts = isRoot
        HAWork.queue.async {
            settleGrant(path: root, groupID: groupID)
            if path != root { settleGrant(path: path, groupID: groupID) }
            do {
                var listed = try ContainerLister.list(path: path, rootPath: root)
                if showShortcuts {
                    listed = ContainerLister.withRootShortcuts(listed, rootPath: root)
                }
                DispatchQueue.main.async {
                    items = listed
                    errorText = nil
                    loading = false
                    appModel.log("browse list \(path) items=\(listed.count)")
                }
            } catch {
                let fallback = showShortcuts ? ContainerLister.rootShortcuts(rootPath: root) : []
                DispatchQueue.main.async {
                    items = fallback
                    errorText = fallback.isEmpty ? error.localizedDescription : nil
                    loading = false
                    appModel.log("browse fail \(path): \(error.localizedDescription)")
                }
            }
        }
    }

    private func share(_ item: BrowseItem) {
        HAWork.queue.async {
            do {
                settleGrant(path: rootPath, groupID: isGroup ? targetID : nil)
                let url = try ContainerLister.exportCopy(path: item.path)
                DispatchQueue.main.async { shareURL = url }
            } catch {
                DispatchQueue.main.async {
                    message = error.localizedDescription
                    appModel.log("browse share fail: \(error.localizedDescription)")
                }
            }
        }
    }
}

struct FilePreviewView: View {
    let path: String
    let name: String
    let groupID: String?
    @State private var text = "Loading…"

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(.footnote, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .background(Color(.systemBackground))
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            HAWork.queue.async {
                settleGrant(path: path, groupID: groupID)
                let body = Self.read(path: path)
                DispatchQueue.main.async { text = body }
            }
        }
    }

    static func canPreview(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return ["plist", "json", "txt", "xml", "log", "strings", "entitlements", "ha"].contains(ext)
            || name.hasSuffix(".plist")
    }

    static func icon(for name: String) -> String {
        switch (name as NSString).pathExtension.lowercased() {
        case "plist": return "list.bullet.rectangle"
        case "json": return "curlybraces"
        case "txt", "log", "strings": return "doc.plaintext"
        default: return "doc"
        }
    }

    private static func read(path: String) -> String {
        let url = URL(fileURLWithPath: path)
        if (path as NSString).pathExtension.lowercased() == "plist",
           let data = try? Data(contentsOf: url),
           let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
           let pretty = try? PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0),
           let text = String(data: pretty, encoding: .utf8) {
            return text
        }
        if let data = try? Data(contentsOf: url) {
            if let text = String(data: data, encoding: .utf8) { return text }
            if let text = String(data: data, encoding: .utf16) { return text }
            return "Binary (\(data.count) bytes)"
        }
        return "Unable to read file."
    }
}

enum AppGroupLookup {
    static func resolve(_ groupID: String) -> String? {
        var err: NSString?
        if let path = MCMActivateContainerPath(7, groupID, true, &err),
           PathSafety.isAppGroupRoot(URL(fileURLWithPath: path)) {
            return path
        }
        err = nil
        if let path = MCMActivateContainerPath(7, groupID, false, &err),
           PathSafety.isAppGroupRoot(URL(fileURLWithPath: path)) {
            return path
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
    static let shortcutNames = ["Documents", "Library", "tmp", "StoreKit"]

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

    static func rootShortcuts(rootPath: String) -> [BrowseItem] {
        shortcutNames.compactMap { name in
            let path = (rootPath as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
                return nil
            }
            return BrowseItem(name: name, path: path, isDirectory: true, size: nil)
        }
    }

    static func withRootShortcuts(_ items: [BrowseItem], rootPath: String) -> [BrowseItem] {
        var result = items
        let existing = Set(items.map(\.name))
        for shortcut in rootShortcuts(rootPath: rootPath) where !existing.contains(shortcut.name) {
            result.insert(shortcut, at: 0)
        }
        return result
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

func settleGrant(path: String, groupID: String?) {
    if GrantCache.contains(path) { return }
    let handle = GrantCache.grantOnce(path: path, groupID: groupID)
    if handle > 0 {
        Thread.sleep(forTimeInterval: 0.2)
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

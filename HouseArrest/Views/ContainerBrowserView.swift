import SwiftUI
import UIKit

enum BrowseNav: Hashable {
    case folder(title: String, path: String, targetID: String, rootPath: String, isGroup: Bool)
    case preview(name: String, path: String, groupID: String?)
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
    @Environment(\.dismiss) private var dismiss
    let app: InstalledApp

    @State private var groups: [(id: String, path: String)] = []
    @State private var loading = true
    @State private var loaded = false
    @State private var customID = ""
    @State private var askGroup = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                if let dataPath = app.dataContainerPath {
                    Section("App data") {
                        ForEach(["Documents", "Library", "tmp", "StoreKit"], id: \.self) { name in
                            NavigationLink(value: BrowseNav.folder(
                                title: name,
                                path: (dataPath as NSString).appendingPathComponent(name),
                                targetID: app.bundleID,
                                rootPath: dataPath,
                                isGroup: false
                            )) {
                                Label(name, systemImage: "folder.fill")
                            }
                        }
                        NavigationLink(value: BrowseNav.folder(
                            title: app.bundleID,
                            path: dataPath,
                            targetID: app.bundleID,
                            rootPath: dataPath,
                            isGroup: false
                        )) {
                            Label("All files", systemImage: "internaldrive")
                        }
                    }
                } else {
                    Section("App data") {
                        Text("Container unavailable").foregroundStyle(.secondary)
                    }
                }
                Section {
                    ForEach(groups, id: \.id) { group in
                        NavigationLink(value: BrowseNav.folder(
                            title: group.id,
                            path: group.path,
                            targetID: group.id,
                            rootPath: group.path,
                            isGroup: true
                        )) {
                            Label(group.id, systemImage: "person.2")
                        }
                    }
                    Button("Open group ID…") { askGroup = true }
                } header: {
                    Text("App Groups")
                } footer: {
                    Text("Open a group by ID, for example group.woodsign.widgy.")
                }
            }
            .navigationTitle("Browse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .navigationDestination(for: BrowseNav.self) { route in
                switch route {
                case .folder(let title, let folder, let targetID, let root, let isGroup):
                    FolderBrowserView(
                        title: title,
                        targetID: targetID,
                        rootPath: root,
                        currentPath: folder,
                        isGroup: isGroup
                    )
                case .preview(let name, let file, let groupID):
                    FilePreviewView(path: file, name: name, groupID: groupID)
                }
            }
            .overlay { if loading { ProgressView() } }
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
    }

    private func loadRoots() {
        if loaded { return }
        loaded = true
        loading = true
        let bundleID = app.bundleID
        let dataPath = app.dataContainerPath
        HAWork.queue.async {
            if let dataPath { settleGrant(path: dataPath, groupID: nil) }
            var found: [(String, String)] = []
            for groupID in AppGroupLookup.remembered(for: bundleID) {
                if let path = AppGroupLookup.resolve(groupID) {
                    settleGrant(path: path, groupID: groupID)
                    found.append((groupID, path))
                }
            }
            DispatchQueue.main.async {
                groups = found
                loading = false
                appModel.log("browse roots app=\(dataPath == nil ? 0 : 1) groups=\(found.count)")
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
            DispatchQueue.main.async {
                if !groups.contains(where: { $0.id == id }) {
                    groups.append((id, path))
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
    @State private var shareURL: URL?
    @State private var message: String?

    var body: some View {
        Group {
            if loading && items.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                ContentUnavailableView("Empty", systemImage: "folder")
            } else {
                List(items) { item in
                    if item.isDirectory {
                        NavigationLink(value: BrowseNav.folder(
                            title: item.name,
                            path: item.path,
                            targetID: targetID,
                            rootPath: rootPath,
                            isGroup: isGroup
                        )) {
                            row(item)
                        }
                    } else {
                        NavigationLink(value: BrowseNav.preview(
                            name: item.name,
                            path: item.path,
                            groupID: isGroup ? targetID : nil
                        )) {
                            row(item)
                        }
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: load) {
                    Image(systemName: "arrow.clockwise").foregroundStyle(HATheme.accent)
                }
            }
        }
        .onAppear(perform: load)
        .sheet(isPresented: Binding(
            get: { shareURL != nil },
            set: { if !$0 { shareURL = nil } }
        )) {
            if let shareURL { ActivityView(items: [shareURL]) }
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

    private func row(_ item: BrowseItem) -> some View {
        HStack {
            Image(systemName: item.isDirectory ? "folder.fill" : FilePreviewView.icon(for: item.name))
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
        .contextMenu {
            Button {
                UIPasteboard.general.string = item.path
                message = "Path copied"
            } label: {
                Label("Copy path", systemImage: "doc.on.doc")
            }
            if !item.isDirectory {
                Button { share(item) } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private func load() {
        loading = true
        let path = currentPath
        let root = rootPath
        let groupID = isGroup ? targetID : nil
        HAWork.queue.async {
            settleGrant(path: root, groupID: groupID)
            if path != root { settleGrant(path: path, groupID: groupID) }
            let listed = (try? ContainerLister.list(path: path, rootPath: root)) ?? []
            DispatchQueue.main.async {
                items = listed
                loading = false
                appModel.log("browse list \(path) items=\(listed.count)")
            }
        }
    }

    private func share(_ item: BrowseItem) {
        HAWork.queue.async {
            settleGrant(path: rootPath, groupID: isGroup ? targetID : nil)
            do {
                let url = try ContainerLister.exportCopy(path: item.path)
                DispatchQueue.main.async { shareURL = url }
            } catch {
                DispatchQueue.main.async { message = error.localizedDescription }
            }
        }
    }
}

struct FilePreviewView: View {
    let path: String
    let name: String
    let groupID: String?
    @State private var text = "Loading…"
    @State private var shareURL: URL?

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .background(Color(.systemBackground))
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    HAWork.queue.async {
                        if let url = try? ContainerLister.exportCopy(path: path) {
                            DispatchQueue.main.async { shareURL = url }
                        }
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { shareURL != nil },
            set: { if !$0 { shareURL = nil } }
        )) {
            if let shareURL { ActivityView(items: [shareURL]) }
        }
        .onAppear {
            HAWork.queue.async {
                settleGrant(path: path, groupID: groupID)
                let body = Self.read(path: path)
                DispatchQueue.main.async { text = body }
            }
        }
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
        guard let data = try? Data(contentsOf: url) else { return "Unable to read file." }
        if (path as NSString).pathExtension.lowercased() == "plist",
           let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
           let pretty = try? PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0),
           let text = String(data: pretty, encoding: .utf8) {
            return text
        }
        if let text = String(data: data.prefix(200_000), encoding: .utf8) {
            return data.count > 200_000 ? text + "\n\u{2026}" : text
        }
        return "Binary (\(data.count) bytes)"
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
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            let isDir = values?.isDirectory == true
            return BrowseItem(
                name: url.lastPathComponent,
                path: url.path,
                isDirectory: isDir,
                size: isDir ? nil : Int64(values?.fileSize ?? 0)
            )
        }
        .sorted {
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

func settleGrant(path: String, groupID: String?) {
    if GrantCache.contains(path) { return }
    let handle = GrantCache.grantOnce(path: path, groupID: groupID)
    if handle > 0 { Thread.sleep(forTimeInterval: 0.2) }
}

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

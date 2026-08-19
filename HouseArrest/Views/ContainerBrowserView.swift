import SwiftUI
import UIKit

enum BrowseNav: Hashable {
    case folder(title: String, path: String, targetID: String, rootPath: String, isGroup: Bool)
    case preview(name: String, path: String, isGroup: Bool, groupID: String?)
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

    @State private var path = NavigationPath()
    @State private var roots: [String] = []
    @State private var groups: [(id: String, path: String)] = []
    @State private var loading = true
    @State private var loaded = false
    @State private var customID = ""
    @State private var askGroup = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let dataPath = app.dataContainerPath {
                    Section("App data") {
                        ForEach(ContainerLister.shortcutNames, id: \.self) { name in
                            let folder = (dataPath as NSString).appendingPathComponent(name)
                            if FileManager.default.fileExists(atPath: folder) || loading {
                                NavigationLink(value: BrowseNav.folder(
                                    title: name,
                                    path: folder,
                                    targetID: app.bundleID,
                                    rootPath: dataPath,
                                    isGroup: false
                                )) {
                                    Label(name, systemImage: "folder.fill")
                                }
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
                        Text("Container unavailable")
                            .foregroundStyle(.secondary)
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
                case .preview(let name, let file, let isGroup, let groupID):
                    FilePreviewView(path: file, name: name, groupID: isGroup ? groupID : nil)
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
    @State private var selecting = false
    @State private var selected = Set<String>()
    @State private var query = ""
    @State private var shareURL: URL?
    @State private var message: String?
    @State private var newFolder = ""
    @State private var askFolder = false
    @State private var renameItem: BrowseItem?
    @State private var renameText = ""
    @State private var deleteItems: [BrowseItem] = []
    @State private var askPatch = false
    @State private var patchName = ""

    private var visible: [BrowseItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        Group {
            if loading && items.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                ContentUnavailableView("Empty", systemImage: "folder")
            } else {
                List(visible, selection: selecting ? $selected : nil) { item in
                    rowLink(item)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { deleteItems = [item] } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button { beginRename(item) } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                        .contextMenu { itemMenu(item) }
                }
                .environment(\.
                    editMode,
                    .constant(selecting ? .active : .inactive)
                )
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search this folder")
        .toolbar { toolbar }
        .onAppear { load() }
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
        .alert("New folder", isPresented: $askFolder) {
            TextField("Name", text: $newFolder)
            Button("Create") { createFolder() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename", isPresented: Binding(
            get: { renameItem != nil },
            set: { if !$0 { renameItem = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Save") { applyRename() }
            Button("Cancel", role: .cancel) { renameItem = nil }
        }
        .alert("Create patch", isPresented: $askPatch) {
            TextField("Patch name", text: $patchName)
            Button("Export") { exportPatch() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Builds a .ha from the selected files.")
        }
        .confirmationDialog(
            "Delete \(deleteItems.count) item(s)?",
            isPresented: Binding(
                get: { !deleteItems.isEmpty },
                set: { if !$0 { deleteItems = [] } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { deleteSelected(deleteItems) }
            Button("Cancel", role: .cancel) { deleteItems = [] }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if selecting {
                Button("Done") {
                    selecting = false
                    selected.removeAll()
                }
            } else {
                Menu {
                    Button { selecting = true } label: {
                        Label("Select", systemImage: "checkmark.circle")
                    }
                    Button { askFolder = true } label: {
                        Label("New folder", systemImage: "folder.badge.plus")
                    }
                    if BrowseClipboard.hasItems {
                        Button { paste() } label: {
                            Label("Paste", systemImage: "doc.on.clipboard")
                        }
                    }
                    Button { load() } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(HATheme.accent)
                }
            }
        }
        if selecting {
            ToolbarItemGroup(placement: .bottomBar) {
                Button { copySelected() } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .disabled(selected.isEmpty)
                Button { shareSelected() } label: { Label("Share", systemImage: "square.and.arrow.up") }
                    .disabled(selected.isEmpty)
                Button {
                    patchName = targetID
                    askPatch = true
                } label: { Label("Patch", systemImage: "plus.rectangle.on.folder") }
                    .disabled(selected.isEmpty)
                Button(role: .destructive) {
                    deleteItems = items.filter { selected.contains($0.path) }
                } label: { Label("Delete", systemImage: "trash") }
                    .disabled(selected.isEmpty)
            }
        }
    }

    @ViewBuilder
    private func rowLink(_ item: BrowseItem) -> some View {
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
                isGroup: isGroup,
                groupID: targetID
            )) {
                row(item)
            }
        }
    }

    @ViewBuilder
    private func itemMenu(_ item: BrowseItem) -> some View {
        Button { share([item]) } label: { Label("Share", systemImage: "square.and.arrow.up") }
        Button { BrowseClipboard.copy([item]); message = "Copied" } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        Button {
            UIPasteboard.general.string = item.path
            message = "Path copied"
        } label: { Label("Copy path", systemImage: "link") }
        Button { beginRename(item) } label: { Label("Rename", systemImage: "pencil") }
        Button(role: .destructive) { deleteItems = [item] } label: {
            Label("Delete", systemImage: "trash")
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

    private func selectedItems() -> [BrowseItem] {
        items.filter { selected.contains($0.path) }
    }

    private func copySelected() {
        BrowseClipboard.copy(selectedItems())
        message = "Copied \(selected.count) item(s)"
    }

    private func shareSelected() { share(selectedItems()) }

    private func share(_ list: [BrowseItem]) {
        HAWork.queue.async {
            settleGrant(path: rootPath, groupID: isGroup ? targetID : nil)
            do {
                let url: URL
                if list.count == 1, !list[0].isDirectory {
                    url = try ContainerLister.exportCopy(path: list[0].path)
                } else {
                    url = try ContainerLister.exportArchive(items: list)
                }
                DispatchQueue.main.async { shareURL = url }
            } catch {
                DispatchQueue.main.async {
                    message = error.localizedDescription
                    appModel.log("browse share fail: \(error.localizedDescription)")
                }
            }
        }
    }

    private func beginRename(_ item: BrowseItem) {
        renameItem = item
        renameText = item.name
    }

    private func applyRename() {
        guard let item = renameItem else { return }
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        renameItem = nil
        guard !name.isEmpty, name != item.name else { return }
        HAWork.queue.async {
            do {
                try FileOps.rename(item.path, to: name, rootPath: rootPath)
                DispatchQueue.main.async { load() }
            } catch {
                DispatchQueue.main.async { message = error.localizedDescription }
            }
        }
    }

    private func createFolder() {
        let name = newFolder.trimmingCharacters(in: .whitespacesAndNewlines)
        newFolder = ""
        guard !name.isEmpty else { return }
        HAWork.queue.async {
            do {
                try FileOps.createFolder(name: name, in: currentPath, rootPath: rootPath)
                DispatchQueue.main.async { load() }
            } catch {
                DispatchQueue.main.async { message = error.localizedDescription }
            }
        }
    }

    private func deleteSelected(_ list: [BrowseItem]) {
        HAWork.queue.async {
            do {
                try FileOps.delete(list.map(\.path), rootPath: rootPath)
                DispatchQueue.main.async {
                    selected.removeAll()
                    deleteItems = []
                    load()
                }
            } catch {
                DispatchQueue.main.async { message = error.localizedDescription }
            }
        }
    }

    private func paste() {
        HAWork.queue.async {
            do {
                try FileOps.paste(into: currentPath, rootPath: rootPath)
                DispatchQueue.main.async { load(); message = "Pasted" }
            } catch {
                DispatchQueue.main.async { message = error.localizedDescription }
            }
        }
    }

    private func exportPatch() {
        let name = patchName.trimmingCharacters(in: .whitespacesAndNewlines)
        let list = selectedItems()
        HAWork.queue.async {
            do {
                settleGrant(path: rootPath, groupID: isGroup ? targetID : nil)
                let rules = try FileOps.rules(from: list, targetID: targetID, rootPath: rootPath)
                guard !rules.isEmpty else { throw PatchError.invalidPackage }
                var project = PatchProject(name: name.isEmpty ? targetID : name, rules: rules)
                project.updatedAt = Date()
                let data = try HAPackageCodec.encode(project: project)
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(project.name).ha")
                try data.write(to: dest, options: .atomic)
                DispatchQueue.main.async {
                    appModel.addProject(project)
                    shareURL = dest
                    selecting = false
                    selected.removeAll()
                    appModel.log("export patch \(project.name) files=\(rules.count)")
                }
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
        case "ha", "3105": return "shippingbox"
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
        if let text = String(data: data.prefix(200_000), encoding: .utf8),
           text.unicodeScalars.contains(where: { !$0.isASCII || $0 != "\0" }) {
            let visible = text.filter { $0.isASCII || $0 == "\n" || $0 == "\t" }
            if visible.count > data.count / 4 || text.contains("{") || text.contains("<") {
                return data.count > 200_000 ? text + "\n\u{2026}" : text
            }
        }
        return hexDump(data.prefix(8_192))
    }

    private static func hexDump(_ data: Data) -> String {
        var lines: [String] = ["Binary (\(data.count)+ bytes)"]
        var offset = 0
        for chunk in data.chunked(16) {
            let hex = chunk.map { String(format: "%02x", $0) }.joined(separator: " ")
            let ascii = chunk.map { let c = Int($0); return (32...126).contains(c) ? String(UnicodeScalar(c)!) : "." }.joined()
            lines.append(String(format: "%08x  %-47s  %@", offset, (hex as NSString).utf8String!, ascii))
            offset += chunk.count
        }
        return lines.joined(separator: "\n")
    }
}

enum BrowseClipboard {
    static var items: [BrowseItem] = []
    static var hasItems: Bool { !items.isEmpty }
    static func copy(_ list: [BrowseItem]) { items = list }
}

enum FileOps {
    static func rename(_ path: String, to name: String, rootPath: String) throws {
        try within(rootPath, path)
        guard !name.contains("/"), name != ".", name != ".." else { throw PatchError.unsafePath }
        let dest = URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent(name)
        try FileManager.default.moveItem(at: URL(fileURLWithPath: path), to: dest)
    }

    static func createFolder(name: String, in folder: String, rootPath: String) throws {
        try within(rootPath, folder)
        guard !name.contains("/"), name != ".", name != ".." else { throw PatchError.unsafePath }
        let dest = URL(fileURLWithPath: folder).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: false)
    }

    static func delete(_ paths: [String], rootPath: String) throws {
        for path in paths {
            try within(rootPath, path)
            try FileManager.default.removeItem(atPath: path)
        }
    }

    static func paste(into folder: String, rootPath: String) throws {
        try within(rootPath, folder)
        for item in BrowseClipboard.items {
            let dest = uniqueURL(in: folder, name: item.name)
            try FileManager.default.copyItem(at: URL(fileURLWithPath: item.path), to: dest)
        }
    }

    static func rules(from items: [BrowseItem], targetID: String, rootPath: String) throws -> [PatchRule] {
        var rules: [PatchRule] = []
        for item in items {
            let files = item.isDirectory ? try walkFiles(item.path) : [item.path]
            for file in files {
                try within(rootPath, file)
                let rel = relative(rootPath, file)
                let data = try Data(contentsOf: URL(fileURLWithPath: file))
                rules.append(PatchRule(
                    targetID: targetID,
                    relativePath: rel,
                    replacementFilename: URL(fileURLWithPath: file).lastPathComponent,
                    replacementData: data
                ))
            }
        }
        return rules
    }

    private static func walkFiles(_ folder: String) throws -> [String] {
        guard let enumerator = FileManager.default.enumerator(atPath: folder) else { return [] }
        var files: [String] = []
        for case let name as String in enumerator {
            let full = (folder as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: full, isDirectory: &isDir), !isDir.boolValue {
                files.append(full)
            }
        }
        return files
    }

    private static func relative(_ root: String, _ path: String) -> String {
        let r = URL(fileURLWithPath: root).standardizedFileURL.path
        let p = URL(fileURLWithPath: path).standardizedFileURL.path
        if p.hasPrefix(r + "/") { return String(p.dropFirst(r.count + 1)) }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private static func uniqueURL(in folder: String, name: String) -> URL {
        var dest = URL(fileURLWithPath: folder).appendingPathComponent(name)
        var i = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            let base = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            dest = URL(fileURLWithPath: folder).appendingPathComponent(
                ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)"
            )
            i += 1
        }
        return dest
    }

    private static func within(_ root: String, _ path: String) throws {
        let r = URL(fileURLWithPath: root).standardizedFileURL.path
        let p = URL(fileURLWithPath: path).standardizedFileURL.path
        guard p == r || p.hasPrefix(r + "/") else { throw PatchError.unsafePath }
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

    static func exportArchive(items: [BrowseItem]) throws -> URL {
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("export.zip")
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        for item in items {
            try fm.copyItem(
                at: URL(fileURLWithPath: item.path),
                to: staging.appendingPathComponent(item.name)
            )
        }
        try fm.zipItem(at: staging, to: dest)
        try? fm.removeItem(at: staging)
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

private extension Data {
    func chunked(_ size: Int) -> [Data] {
        stride(from: 0, to: count, by: size).map { self[$0..<Swift.min($0 + size, count)] }
    }
}

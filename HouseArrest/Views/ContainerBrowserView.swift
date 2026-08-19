import SwiftUI
import UIKit

enum BrowseNav: Hashable {
    case folder(title: String, path: String, targetID: String, rootPath: String, isGroup: Bool)
    case preview(name: String, path: String, isDirectory: Bool, isSymlink: Bool, size: Int64, groupID: String?)
}

enum BrowseSort: String, CaseIterable, Identifiable {
    case name, date, size, reverseName
    var id: String { rawValue }
    var title: String {
        switch self {
        case .name: return "Name"
        case .date: return "Date"
        case .size: return "Size"
        case .reverseName: return "Name (Z-A)"
        }
    }
}

struct BrowseItem: Identifiable, Hashable {
    var id: String { path }
    var name: String
    var path: String
    var isDirectory: Bool
    var isSymlink: Bool
    var size: Int64
    var created: Date?
    var modified: Date?
    var isHidden: Bool { name.hasPrefix(".") }
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
            .tint(HATheme.accent)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", action: { dismiss() })
                        .foregroundStyle(HATheme.accent)
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
                case .preview(let name, let file, let isDirectory, let isSymlink, let size, let groupID):
                    FileWorkspaceView(
                        item: BrowseItem(
                            name: name,
                            path: file,
                            isDirectory: isDirectory,
                            isSymlink: isSymlink,
                            size: size,
                            created: nil,
                            modified: nil
                        ),
                        groupID: groupID
                    )
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
        .tint(HATheme.accent)
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
    @State private var showSearch = false
    @State private var showHidden = false
    @State private var sort = BrowseSort.name
    @State private var shareURL: URL?
    @State private var message: String?
    @State private var deleteItems: [BrowseItem] = []
    @State private var askZip = false
    @State private var zipName = "archive.zip"
    @State private var zipPassword = ""
    @State private var unzipItem: BrowseItem?
    @State private var unzipPassword = ""
    @State private var createFolder = false
    @State private var createFile = false
    @State private var newName = ""
    @State private var renameItem: BrowseItem?
    @State private var renameTo = ""
    @State private var infoItem: BrowseItem?

    private var visibleItems: [BrowseItem] {
        var list = items
        if !showHidden { list = list.filter { !$0.isHidden } }
        if !query.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }
        switch sort {
        case .name:
            list.sort {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory && !$1.isDirectory }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        case .reverseName:
            list.sort {
                if $0.isDirectory != $1.isDirectory { return $0.isDirectory && !$1.isDirectory }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending
            }
        case .date:
            list.sort { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
        case .size:
            list.sort { $0.size > $1.size }
        }
        return list
    }

    var body: some View {
        Group {
            if loading && items.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visibleItems.isEmpty {
                ContentUnavailableView(query.isEmpty ? "Empty" : "No matches", systemImage: "folder")
            } else {
                List(visibleItems) { item in
                    rowContent(item)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { deleteItems = [item] } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                renameItem = item
                                renameTo = item.name
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(HATheme.accent)
                        }
                        .contextMenu { itemMenu(item) }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .tint(HATheme.accent)
        .searchable(text: $query, isPresented: $showSearch, prompt: "Search this folder")
        .toolbar { toolbar }
        .onAppear(perform: load)
        .sheet(isPresented: Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil } })) {
            if let shareURL { ActivityShareView(items: [shareURL]) }
        }
        .sheet(item: $infoItem) { item in
            FileInfoSheet(item: item)
        }
        .alert("Browse", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
        .alert("New folder", isPresented: $createFolder) {
            TextField("Name", text: $newName)
            Button("Create") { createItem(folder: true) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("New file", isPresented: $createFile) {
            TextField("Name", text: $newName)
            Button("Create") { createItem(folder: false) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename", isPresented: Binding(get: { renameItem != nil }, set: { if !$0 { renameItem = nil } })) {
            TextField("Name", text: $renameTo)
            Button("Save") { renameCurrent() }
            Button("Cancel", role: .cancel) { renameItem = nil }
        }
        .alert("Zip", isPresented: $askZip) {
            TextField("Name", text: $zipName)
            SecureField("Password (optional)", text: $zipPassword)
            Button("Create") { zipSelected() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Leave password empty for a normal zip.")
        }
        .alert("Unzip", isPresented: Binding(get: { unzipItem != nil }, set: { if !$0 { unzipItem = nil } })) {
            SecureField("Password (optional)", text: $unzipPassword)
            Button("Extract") { unzipCurrent() }
            Button("Cancel", role: .cancel) { unzipItem = nil }
        }
        .confirmationDialog(
            "Delete \(deleteItems.count) item(s)?",
            isPresented: Binding(get: { !deleteItems.isEmpty }, set: { if !$0 { deleteItems = [] } }),
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
                HStack(spacing: 12) {
                    Menu {
                        Button {
                            newName = "New Folder"
                            createFolder = true
                        } label: {
                            Label("New folder", systemImage: "folder.badge.plus")
                        }
                        Button {
                            newName = "untitled.txt"
                            createFile = true
                        } label: {
                            Label("New file", systemImage: "doc.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    Menu {
                        Button { selecting = true } label: {
                            Label("Select", systemImage: "checkmark.circle")
                        }
                        Button { showSearch = true } label: {
                            Label("Search", systemImage: "magnifyingglass")
                        }
                        Menu {
                            ForEach(BrowseSort.allCases) { option in
                                Button {
                                    sort = option
                                } label: {
                                    if sort == option {
                                        Label(option.title, systemImage: "checkmark")
                                    } else {
                                        Text(option.title)
                                    }
                                }
                            }
                        } label: {
                            Label("Sort", systemImage: "arrow.up.arrow.down")
                        }
                        Button {
                            showHidden.toggle()
                        } label: {
                            Label(showHidden ? "Hide hidden" : "Show hidden", systemImage: showHidden ? "eye.slash" : "eye")
                        }
                        if BrowseClipboard.hasItems {
                            Button { paste() } label: {
                                Label("Paste", systemImage: "doc.on.clipboard")
                            }
                        }
                        Button(action: load) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                .foregroundStyle(HATheme.accent)
            }
        }
        if selecting {
            ToolbarItemGroup(placement: .bottomBar) {
                Button { copySelected(move: false) } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .disabled(selected.isEmpty)
                Button { copySelected(move: true) } label: { Label("Move", systemImage: "arrow.right.doc.on.clipboard") }
                    .disabled(selected.isEmpty)
                Button {
                    zipName = "archive.zip"
                    zipPassword = ""
                    askZip = true
                } label: { Label("Zip", systemImage: "archivebox") }
                    .disabled(selected.isEmpty)
                Button(role: .destructive) {
                    deleteItems = items.filter { selected.contains($0.path) }
                } label: { Label("Delete", systemImage: "trash") }
                    .disabled(selected.isEmpty)
            }
        }
    }

    @ViewBuilder
    private func rowContent(_ item: BrowseItem) -> some View {
        if selecting {
            Button {
                if selected.contains(item.path) { selected.remove(item.path) }
                else { selected.insert(item.path) }
            } label: {
                HStack {
                    Image(systemName: selected.contains(item.path) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(HATheme.accent)
                    row(item)
                }
            }
            .foregroundStyle(.primary)
        } else if item.isDirectory {
            NavigationLink(value: BrowseNav.folder(
                title: item.name,
                path: item.path,
                targetID: targetID,
                rootPath: rootPath,
                isGroup: isGroup
            )) { row(item) }
        } else {
            NavigationLink(value: BrowseNav.preview(
                name: item.name,
                path: item.path,
                isDirectory: item.isDirectory,
                isSymlink: item.isSymlink,
                size: item.size,
                groupID: isGroup ? targetID : nil
            )) { row(item) }
        }
    }

    @ViewBuilder
    private func itemMenu(_ item: BrowseItem) -> some View {
        Button {
            renameItem = item
            renameTo = item.name
        } label: {
            Label("Rename", systemImage: "pencil")
        }
        Button { BrowseClipboard.copy([item], move: false); message = "Copied" } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        Button { BrowseClipboard.copy([item], move: true); message = "Ready to move" } label: {
            Label("Move", systemImage: "arrow.right.doc.on.clipboard")
        }
        Button {
            UIPasteboard.general.string = item.path
            message = "Path copied"
        } label: {
            Label("Copy path", systemImage: "link")
        }
        if ZipUtil.isZip(item.name) {
            Button { unzipItem = item; unzipPassword = "" } label: {
                Label("Unzip", systemImage: "archivebox")
            }
        }
        Button { infoItem = item } label: {
            Label("Info", systemImage: "info.circle")
        }
        Button { share(item) } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        Button(role: .destructive) { deleteItems = [item] } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func row(_ item: BrowseItem) -> some View {
        HStack {
            Image(systemName: item.isSymlink ? "link" : FileKind.of(name: item.name, isDirectory: item.isDirectory).icon)
                .foregroundStyle(item.isDirectory ? HATheme.accent : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                HStack(spacing: 8) {
                    if !item.isDirectory {
                        Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                    }
                    if let modified = item.modified {
                        Text(modified.formatted(date: .abbreviated, time: .omitted))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                infoItem = item
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(HATheme.accent)
            }
            .buttonStyle(.borderless)
        }
    }

    private func selectedItems() -> [BrowseItem] {
        items.filter { selected.contains($0.path) }
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

    private func createItem(folder: Bool) {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        HAWork.queue.async {
            do {
                settleGrant(path: rootPath, groupID: isGroup ? targetID : nil)
                let dest = try FileOps.uniquePath(in: currentPath, name: name, rootPath: rootPath)
                if folder {
                    try FileManager.default.createDirectory(atPath: dest, withIntermediateDirectories: true)
                } else {
                    FileManager.default.createFile(atPath: dest, contents: Data("\n".utf8))
                }
                DispatchQueue.main.async { load() }
            } catch {
                DispatchQueue.main.async { message = error.localizedDescription }
            }
        }
    }

    private func renameCurrent() {
        guard let item = renameItem else { return }
        let name = renameTo.trimmingCharacters(in: .whitespacesAndNewlines)
        renameItem = nil
        guard !name.isEmpty, name != item.name else { return }
        HAWork.queue.async {
            do {
                try FileOps.rename(item.path, to: name, folder: currentPath, rootPath: rootPath)
                DispatchQueue.main.async { load() }
            } catch {
                DispatchQueue.main.async { message = error.localizedDescription }
            }
        }
    }

    private func copySelected(move: Bool) {
        BrowseClipboard.copy(selectedItems(), move: move)
        message = move ? "Ready to move" : "Copied \(selected.count) item(s)"
        selecting = false
        selected.removeAll()
    }

    private func share(_ item: BrowseItem) {
        shareFile(path: item.path, groupID: isGroup ? targetID : nil) { shareURL = $0 }
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

    private func zipSelected() {
        let list = selectedItems()
        var name = zipName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = "archive.zip" }
        if !name.lowercased().hasSuffix(".zip") { name += ".zip" }
        let password = zipPassword
        HAWork.queue.async {
            do {
                settleGrant(path: rootPath, groupID: isGroup ? targetID : nil)
                let dest = try FileOps.uniquePath(in: currentPath, name: name, rootPath: rootPath)
                try ZipUtil.zip(paths: list.map(\.path), to: dest, password: password)
                DispatchQueue.main.async {
                    selecting = false
                    selected.removeAll()
                    zipPassword = ""
                    load()
                    message = "Created \(URL(fileURLWithPath: dest).lastPathComponent)"
                }
            } catch {
                DispatchQueue.main.async { message = error.localizedDescription }
            }
        }
    }

    private func unzipCurrent() {
        guard let item = unzipItem else { return }
        let password = unzipPassword
        unzipItem = nil
        HAWork.queue.async {
            do {
                settleGrant(path: rootPath, groupID: isGroup ? targetID : nil)
                let folderName = URL(fileURLWithPath: item.path).deletingPathExtension().lastPathComponent
                let dest = try FileOps.uniquePath(in: currentPath, name: folderName, rootPath: rootPath)
                try FileManager.default.createDirectory(atPath: dest, withIntermediateDirectories: true)
                try ZipUtil.unzip(file: item.path, to: dest, password: password)
                DispatchQueue.main.async {
                    unzipPassword = ""
                    load()
                    message = "Extracted"
                }
            } catch {
                DispatchQueue.main.async { message = error.localizedDescription }
            }
        }
    }
}

enum BrowseClipboard {
    static var items: [BrowseItem] = []
    static var move = false
    static var hasItems: Bool { !items.isEmpty }
    static func copy(_ list: [BrowseItem], move: Bool) {
        items = list
        self.move = move
    }
}

enum FileOps {
    static func delete(_ paths: [String], rootPath: String) throws {
        for path in paths {
            try within(rootPath, path)
            try FileManager.default.removeItem(atPath: path)
        }
    }

    static func rename(_ path: String, to name: String, folder: String, rootPath: String) throws {
        try within(rootPath, path)
        let dest = try uniquePath(in: folder, name: name, rootPath: rootPath)
        try FileManager.default.moveItem(atPath: path, toPath: dest)
    }

    static func paste(into folder: String, rootPath: String) throws {
        try within(rootPath, folder)
        for item in BrowseClipboard.items {
            let dest = uniqueURL(in: folder, name: item.name)
            if BrowseClipboard.move {
                try FileManager.default.moveItem(at: URL(fileURLWithPath: item.path), to: dest)
            } else {
                try FileManager.default.copyItem(at: URL(fileURLWithPath: item.path), to: dest)
            }
        }
        if BrowseClipboard.move { BrowseClipboard.items = [] }
    }

    static func uniquePath(in folder: String, name: String, rootPath: String) throws -> String {
        try within(rootPath, folder)
        return uniqueURL(in: folder, name: name).path
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
    static func list(path: String, rootPath: String) throws -> [BrowseItem] {
        let root = URL(fileURLWithPath: rootPath).standardizedFileURL.path
        let current = URL(fileURLWithPath: path).standardizedFileURL.path
        guard current == root || current.hasPrefix(root + "/") else {
            throw PatchError.unsafePath
        }
        let urls = try FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: current),
            includingPropertiesForKeys: [
                .isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey,
                .creationDateKey, .contentModificationDateKey
            ],
            options: []
        )
        return urls.map { url in
            let values = try? url.resourceValues(forKeys: [
                .isDirectoryKey, .fileSizeKey, .isSymbolicLinkKey,
                .creationDateKey, .contentModificationDateKey
            ])
            return BrowseItem(
                name: url.lastPathComponent,
                path: url.path,
                isDirectory: values?.isDirectory == true,
                isSymlink: values?.isSymbolicLink == true,
                size: Int64(values?.fileSize ?? 0),
                created: values?.creationDate,
                modified: values?.contentModificationDate
            )
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

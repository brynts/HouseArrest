import SwiftUI
import UIKit

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
                .listItemTint(HATheme.accent)
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
        .alert(
            "Delete \(deleteItems.count) item(s)?",
            isPresented: Binding(get: { !deleteItems.isEmpty }, set: { if !$0 { deleteItems = [] } })
        ) {
            Button("Delete", role: .destructive) { deleteSelected(deleteItems) }
            Button("Cancel", role: .cancel) { deleteItems = [] }
        } message: {
            Text(deleteItems.map(\.name).joined(separator: ", "))
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
                                Button { sort = option } label: {
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
                .symbolRenderingMode(.monochrome)
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

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
                                HStack {
                                    Image(systemName: "folder.fill")
                                        .foregroundStyle(HATheme.accent)
                                        .symbolRenderingMode(.monochrome)
                                    Text(name)
                                }
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
                            HStack {
                                Image(systemName: "person.2.fill")
                                    .foregroundStyle(HATheme.accent)
                                    .symbolRenderingMode(.monochrome)
                                Text(group.id)
                            }
                        }
                    }
                    Button("Open group ID…") { askGroup = true }
                } header: {
                    Text("App Groups")
                } footer: {
                    Text("Open a group by ID, for example group.woodsign.widgy.")
                }
            }
            .listItemTint(HATheme.accent)
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

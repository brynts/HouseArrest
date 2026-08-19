import SwiftUI
import UIKit

struct PatchPick: Hashable {
    var targetID: String
    var rootPath: String
    var path: String
    var isDirectory: Bool
    var name: String
}

struct CreatePatchView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    let app: InstalledApp

    @State private var groups: [(id: String, path: String)] = []
    @State private var loading = true
    @State private var selected: Set<PatchPick> = []
    @State private var askName = false
    @State private var patchName = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var busy = false
    @State private var errorText: String?
    @State private var shareURL: URL?
    @State private var customID = ""
    @State private var askGroup = false

    var body: some View {
        NavigationStack {
            List {
                if let dataPath = app.dataContainerPath {
                    Section("App data") {
                        ForEach(["Documents", "Library", "tmp", "StoreKit"], id: \.self) { name in
                            folderRow(
                                title: name,
                                path: (dataPath as NSString).appendingPathComponent(name),
                                targetID: app.bundleID,
                                rootPath: dataPath
                            )
                        }
                    }
                }
                Section("App Groups") {
                    ForEach(groups, id: \.id) { group in
                        folderRow(
                            title: group.id,
                            path: group.path,
                            targetID: group.id,
                            rootPath: group.path
                        )
                    }
                    Button("Open group ID…") { askGroup = true }
                }
            }
            .navigationTitle("Create patch")
            .navigationBarTitleDisplayMode(.inline)
            .tint(HATheme.accent)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(HATheme.accent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Next") { beginExport() }
                        .disabled(selected.isEmpty || busy)
                        .foregroundStyle(HATheme.accent)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text(selected.isEmpty ? "Select files to include" : "\(selected.count) selected")
                    .font(.footnote)
                    .foregroundStyle(HATheme.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(.bar)
            }
            .overlay { if loading { ProgressView() } }
            .onAppear(perform: loadRoots)
            .alert("App Group", isPresented: $askGroup) {
                TextField("group.example.app", text: $customID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Open") { openCustomGroup() }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Create patch", isPresented: $askName) {
                TextField("Patch name", text: $patchName)
                SecureField("Password (optional)", text: $password)
                SecureField("Confirm password", text: $confirmPassword)
                Button("Create") { export() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Paths are stored relative to the app or App Group so the package can be shared.")
            }
            .alert("Create patch", isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
            .sheet(isPresented: Binding(
                get: { shareURL != nil },
                set: { if !$0 { shareURL = nil } }
            )) {
                if let shareURL {
                    ShareSheet(items: [shareURL])
                }
            }
        }
        .tint(HATheme.accent)
    }

    private func folderRow(title: String, path: String, targetID: String, rootPath: String) -> some View {
        let pick = PatchPick(targetID: targetID, rootPath: rootPath, path: path, isDirectory: true, name: title)
        return HStack {
            Button {
                toggle(pick)
            } label: {
                Image(systemName: selected.contains(pick) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(HATheme.accent)
            }
            .buttonStyle(.plain)
            NavigationLink(value: pick) {
                HStack {
                    Image(systemName: title.hasPrefix("group.") ? "person.2.fill" : "folder.fill")
                        .foregroundStyle(HATheme.accent)
                    Text(title)
                }
            }
        }
        .navigationDestination(for: PatchPick.self) { item in
            CreatePatchFolderView(
                title: item.name,
                targetID: item.targetID,
                rootPath: item.rootPath,
                currentPath: item.path,
                selected: $selected
            )
        }
    }

    private func toggle(_ pick: PatchPick) {
        if selected.contains(pick) { selected.remove(pick) } else { selected.insert(pick) }
    }

    private func loadRoots() {
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
                patchName = app.displayName
            }
        }
    }

    private func openCustomGroup() {
        let id = customID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        HAWork.queue.async {
            guard let path = AppGroupLookup.resolve(id) else {
                DispatchQueue.main.async { errorText = "Could not open \(id)" }
                return
            }
            settleGrant(path: path, groupID: id)
            AppGroupLookup.remember(id, for: app.bundleID)
            DispatchQueue.main.async {
                if !groups.contains(where: { $0.id == id }) {
                    groups.append((id, path))
                }
                customID = ""
            }
        }
    }

    private func beginExport() {
        guard !selected.isEmpty else { return }
        if patchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            patchName = app.displayName
        }
        password = ""
        confirmPassword = ""
        askName = true
    }

    private func export() {
        let name = patchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorText = "Enter a patch name."
            return
        }
        if password != confirmPassword {
            errorText = "Passwords do not match."
            return
        }
        busy = true
        let picks = Array(selected)
        let pass = password.isEmpty ? nil : password
        HAWork.queue.async {
            do {
                let rules = try CreatePatchBuilder.rules(from: picks)
                guard !rules.isEmpty else { throw PatchError.nothingSelected }
                let project = PatchProject(name: name, rules: rules)
                let data = try HAPackageCodec.encode(project: project, password: pass)
                let safe = name.replacingOccurrences(of: "/", with: "-")
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe).ha")
                try data.write(to: url, options: .atomic)
                DispatchQueue.main.async {
                    busy = false
                    shareURL = url
                    appModel.log("create patch \(name) files=\(rules.count) password=\(pass == nil ? 0 : 1)")
                }
            } catch {
                DispatchQueue.main.async {
                    busy = false
                    errorText = error.localizedDescription
                    appModel.log("create patch failed: \(error.localizedDescription)")
                }
            }
        }
    }
}

struct CreatePatchFolderView: View {
    let title: String
    let targetID: String
    let rootPath: String
    let currentPath: String
    @Binding var selected: Set<PatchPick>
    @State private var items: [BrowseItem] = []
    @State private var errorText: String?

    var body: some View {
        List {
            ForEach(items) { item in
                let pick = PatchPick(
                    targetID: targetID,
                    rootPath: rootPath,
                    path: item.path,
                    isDirectory: item.isDirectory,
                    name: item.name
                )
                HStack(spacing: 10) {
                    Button {
                        if selected.contains(pick) { selected.remove(pick) } else { selected.insert(pick) }
                    } label: {
                        Image(systemName: selected.contains(pick) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(HATheme.accent)
                    }
                    .buttonStyle(.plain)
                    if item.isDirectory {
                        NavigationLink(value: pick) {
                            HStack {
                                Image(systemName: "folder.fill")
                                    .foregroundStyle(HATheme.accent)
                                Text(item.name)
                            }
                        }
                    } else {
                        Image(systemName: "doc")
                            .foregroundStyle(HATheme.accent)
                        Text(item.name)
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: PatchPick.self) { item in
            CreatePatchFolderView(
                title: item.name,
                targetID: item.targetID,
                rootPath: item.rootPath,
                currentPath: item.path,
                selected: $selected
            )
        }
        .onAppear(perform: load)
        .alert("Create patch", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
    }

    private func load() {
        do {
            settleGrant(path: currentPath, groupID: targetID.hasPrefix("group.") ? targetID : nil)
            items = try ContainerLister.list(path: currentPath, rootPath: rootPath)
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            errorText = error.localizedDescription
        }
    }
}

enum CreatePatchBuilder {
    static func rules(from picks: [PatchPick]) throws -> [PatchRule] {
        var rules: [PatchRule] = []
        for pick in picks {
            if pick.isDirectory {
                rules.append(contentsOf: try walk(pick))
            } else {
                if let rule = try fileRule(path: pick.path, targetID: pick.targetID, root: pick.rootPath) {
                    rules.append(rule)
                }
            }
        }
        var seen = Set<String>()
        return rules.filter { seen.insert($0.targetID + "/" + $0.relativePath).inserted }
    }

    private static func walk(_ pick: PatchPick) throws -> [PatchRule] {
        var rules: [PatchRule] = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: pick.path) else { return [] }
        while let rel = enumerator.nextObject() as? String {
            let name = (rel as NSString).lastPathComponent
            if name == ".DS_Store" { continue }
            let full = (pick.path as NSString).appendingPathComponent(rel)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir), !isDir.boolValue else { continue }
            if let rule = try fileRule(path: full, targetID: pick.targetID, root: pick.rootPath) {
                rules.append(rule)
            }
        }
        return rules
    }

    private static func fileRule(path: String, targetID: String, root: String) throws -> PatchRule? {
        let rootURL = URL(fileURLWithPath: root).standardizedFileURL
        let fileURL = URL(fileURLWithPath: path).standardizedFileURL
        let rootPath = rootURL.path
        let filePath = fileURL.path
        guard filePath == rootPath || filePath.hasPrefix(rootPath + "/") else {
            throw PatchError.unsafePath
        }
        let rel: String
        if filePath == rootPath {
            return nil
        } else {
            rel = String(filePath.dropFirst(rootPath.count + 1))
        }
        guard !rel.isEmpty, !rel.contains("..") else { throw PatchError.unsafePath }
        let data = try Data(contentsOf: fileURL)
        return PatchRule(
            targetID: targetID,
            relativePath: rel,
            replacementFilename: fileURL.lastPathComponent,
            replacementData: data
        )
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

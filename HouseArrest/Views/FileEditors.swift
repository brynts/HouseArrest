import SwiftUI
import UIKit

enum FileKind {
    case folder, text, plist, image, hex, zip, other

    static func of(name: String, isDirectory: Bool) -> FileKind {
        if isDirectory { return .folder }
        switch (name as NSString).pathExtension.lowercased() {
        case "txt", "log", "json", "xml", "strings", "swift", "js", "css", "md", "html", "csv", "conf", "ini":
            return .text
        case "plist", "entitlements", "loctable":
            return .plist
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "bmp":
            return .image
        case "zip":
            return .zip
        default:
            return .hex
        }
    }

    var icon: String {
        switch self {
        case .folder: return "folder.fill"
        case .text: return "doc.plaintext"
        case .plist: return "list.bullet.rectangle"
        case .image: return "photo"
        case .zip: return "archivebox"
        case .hex: return "doc"
        case .other: return "doc"
        }
    }
}

struct FileWorkspaceView: View {
    let item: BrowseItem
    let groupID: String?

    var body: some View {
        switch FileKind.of(name: item.name, isDirectory: item.isDirectory) {
        case .image:
            ImageFileView(path: item.path, name: item.name, groupID: groupID)
        case .plist:
            TextFileEditor(path: item.path, name: item.name, groupID: groupID, plistMode: true)
        case .text:
            TextFileEditor(path: item.path, name: item.name, groupID: groupID, plistMode: false)
        case .zip:
            ZipFileView(item: item, groupID: groupID)
        default:
            HexFileView(path: item.path, name: item.name, groupID: groupID)
        }
    }
}

struct TextFileEditor: View {
    let path: String
    let name: String
    let groupID: String?
    let plistMode: Bool
    @State private var text = ""
    @State private var status: String?
    @State private var shareURL: URL?

    var body: some View {
        TextEditor(text: $text)
            .font(.system(.footnote, design: .monospaced))
            .padding(8)
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .tint(HATheme.accent)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Save", action: save)
                    Button {
                        shareFile(path: path, groupID: groupID) { shareURL = $0 }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil } })) {
                if let shareURL { ActivityShareView(items: [shareURL]) }
            }
            .alert("File", isPresented: Binding(get: { status != nil }, set: { if !$0 { status = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(status ?? "")
            }
            .onAppear(perform: load)
    }

    private func load() {
        HAWork.queue.async {
            settleGrant(path: path, groupID: groupID)
            let body = readFileText(path: path, plistMode: plistMode)
            DispatchQueue.main.async { text = body }
        }
    }

    private func save() {
        HAWork.queue.async {
            settleGrant(path: path, groupID: groupID)
            do {
                if plistMode {
                    guard let data = text.data(using: .utf8),
                          let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else {
                        throw PatchError.invalidPackage
                    }
                    let xml = try PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
                    try xml.write(to: URL(fileURLWithPath: path), options: .atomic)
                } else {
                    try text.write(toFile: path, atomically: true, encoding: .utf8)
                }
                DispatchQueue.main.async { status = "Saved" }
            } catch {
                DispatchQueue.main.async { status = error.localizedDescription }
            }
        }
    }
}

struct ImageFileView: View {
    let path: String
    let name: String
    let groupID: String?
    @State private var image: UIImage?
    @State private var shareURL: URL?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding()
            } else {
                ContentUnavailableView("Unable to open image", systemImage: "photo")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .tint(HATheme.accent)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    shareFile(path: path, groupID: groupID) { shareURL = $0 }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil } })) {
            if let shareURL { ActivityShareView(items: [shareURL]) }
        }
        .onAppear {
            HAWork.queue.async {
                settleGrant(path: path, groupID: groupID)
                let loaded = UIImage(contentsOfFile: path)
                DispatchQueue.main.async { image = loaded }
            }
        }
    }
}

struct ZipFileView: View {
    let item: BrowseItem
    let groupID: String?
    @State private var password = ""
    @State private var status: String?
    @State private var shareURL: URL?

    var body: some View {
        List {
            Section("Archive") {
                LabeledContent("Name", value: item.name)
                LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
            }
            Section {
                SecureField("Password (optional)", text: $password)
                Button("Extract here") { extract() }
            }
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .tint(HATheme.accent)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    shareFile(path: item.path, groupID: groupID) { shareURL = $0 }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil } })) {
            if let shareURL { ActivityShareView(items: [shareURL]) }
        }
        .alert("Zip", isPresented: Binding(get: { status != nil }, set: { if !$0 { status = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(status ?? "")
        }
    }

    private func extract() {
        HAWork.queue.async {
            do {
                settleGrant(path: item.path, groupID: groupID)
                let folder = URL(fileURLWithPath: item.path).deletingLastPathComponent().path
                let name = URL(fileURLWithPath: item.path).deletingPathExtension().lastPathComponent
                let dest = try FileOps.uniquePath(in: folder, name: name, rootPath: folder)
                try FileManager.default.createDirectory(atPath: dest, withIntermediateDirectories: true)
                try ZipUtil.unzip(file: item.path, to: dest, password: password)
                DispatchQueue.main.async { status = "Extracted to \(URL(fileURLWithPath: dest).lastPathComponent)" }
            } catch {
                DispatchQueue.main.async { status = error.localizedDescription }
            }
        }
    }
}

struct HexFileView: View {
    let path: String
    let name: String
    let groupID: String?
    @State private var text = "Loading\u{2026}"
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
        .tint(HATheme.accent)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    shareFile(path: path, groupID: groupID) { shareURL = $0 }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil } })) {
            if let shareURL { ActivityShareView(items: [shareURL]) }
        }
        .onAppear {
            HAWork.queue.async {
                settleGrant(path: path, groupID: groupID)
                let dump = hexDump(path: path)
                DispatchQueue.main.async { text = dump }
            }
        }
    }
}

struct FileInfoSheet: View {
    let item: BrowseItem
    @State private var mode: Int = 0
    @State private var status: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Details") {
                    LabeledContent("Name", value: item.name)
                    LabeledContent("Kind", value: item.isDirectory ? "Folder" : "File")
                    if item.isSymlink { LabeledContent("Link", value: "Symbolic link") }
                    LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                    if let created = item.created {
                        LabeledContent("Created", value: created.formatted(date: .abbreviated, time: .shortened))
                    }
                    if let modified = item.modified {
                        LabeledContent("Modified", value: modified.formatted(date: .abbreviated, time: .shortened))
                    }
                    LabeledContent("Path", value: item.path)
                }
                Section("Permissions") {
                    permissionRow("Owner read", bit: 0o400)
                    permissionRow("Owner write", bit: 0o200)
                    permissionRow("Owner execute", bit: 0o100)
                    permissionRow("Group read", bit: 0o040)
                    permissionRow("Group write", bit: 0o020)
                    permissionRow("Group execute", bit: 0o010)
                    permissionRow("Others read", bit: 0o004)
                    permissionRow("Others write", bit: 0o002)
                    permissionRow("Others execute", bit: 0o001)
                }
            }
            .navigationTitle("Info")
            .navigationBarTitleDisplayMode(.inline)
            .tint(HATheme.accent)
            .onAppear(perform: loadMode)
            .alert("Info", isPresented: Binding(get: { status != nil }, set: { if !$0 { status = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(status ?? "")
            }
        }
    }

    private func permissionRow(_ title: String, bit: Int) -> some View {
        Toggle(title, isOn: Binding(
            get: { mode & bit != 0 },
            set: { on in toggle(bit: bit, on: on) }
        ))
    }

    private func loadMode() {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: item.path),
           let value = attrs[.posixPermissions] as? NSNumber {
            mode = value.intValue
        }
    }

    private func toggle(bit: Int, on: Bool) {
        var next = mode
        if on { next |= bit } else { next &= ~bit }
        do {
            try FileManager.default.setAttributes([.posixPermissions: next], ofItemAtPath: item.path)
            mode = next
        } catch {
            status = error.localizedDescription
        }
    }
}

func readFileText(path: String, plistMode: Bool) -> String {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
        return "Unable to read file."
    }
    if plistMode,
       let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
       let pretty = try? PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0),
       let text = String(data: pretty, encoding: .utf8) {
        return text
    }
    if let text = String(data: data.prefix(400_000), encoding: .utf8) {
        return data.count > 400_000 ? text + "\n\u{2026}" : text
    }
    return hexDump(path: path)
}

func hexDump(path: String) -> String {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
        return "Unable to read file."
    }
    let slice = data.prefix(16_384)
    var lines: [String] = []
    var offset = 0
    let bytes = [UInt8](slice)
    while offset < bytes.count {
        let chunk = bytes[offset..<min(offset + 16, bytes.count)]
        let hex = chunk.map { String(format: "%02X", $0) }.joined(separator: " ")
        let ascii = String(chunk.map { ($0 >= 32 && $0 < 127) ? Character(UnicodeScalar($0)) : "." })
        let padded = hex + String(repeating: " ", count: max(0, 47 - hex.count))
        lines.append(String(format: "%08X  ", offset) + padded + "  " + ascii)
        offset += 16
    }
    if data.count > slice.count {
        lines.append("... \(data.count - slice.count) more bytes")
    }
    return lines.joined(separator: "\n")
}

func shareFile(path: String, groupID: String?, done: @escaping (URL?) -> Void) {
    HAWork.queue.async {
        settleGrant(path: path, groupID: groupID)
        let url = try? ContainerLister.exportCopy(path: path)
        DispatchQueue.main.async { done(url) }
    }
}

struct ActivityShareView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

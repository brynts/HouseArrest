import SwiftUI
import UniformTypeIdentifiers

enum HADocumentTypes {
    /// Custom type for .ha packages (also accept generic data so picker is not empty).
    static var importTypes: [UTType] {
        var types: [UTType] = [.data, .item, .content]
        if let ha = UTType(filenameExtension: "ha") {
            types.insert(ha, at: 0)
        }
        if let ha = UTType(exportedAs: "app.housearrest.package") {
            types.insert(ha, at: 0)
        }
        return types
    }
}

struct PatchesView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var showImporter = false
    @State private var showNew = false
    @State private var alertMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if appModel.projects.isEmpty {
                    ContentUnavailableView(
                        "No patches",
                        systemImage: "shippingbox",
                        description: Text("Import a .ha package or create a new project.")
                    )
                } else {
                    List {
                        ForEach(appModel.projects) { project in
                            NavigationLink(value: project) {
                                projectRow(project)
                            }
                        }
                        .onDelete { indexSet in
                            appModel.projects.remove(atOffsets: indexSet)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .background(Color.black)
            .navigationTitle("Patches")
            .navigationDestination(for: PatchProject.self) { project in
                PatchDetailView(project: project)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Import .ha", systemImage: "square.and.arrow.down") {
                            showImporter = true
                        }
                        Button("New project", systemImage: "plus") {
                            showNew = true
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(HATheme.accent)
                    }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: HADocumentTypes.importTypes,
                allowsMultipleSelection: false
            ) { result in
                handleImport(result)
            }
            .sheet(isPresented: $showNew) {
                NewPatchSheet { project in
                    appModel.addProject(project)
                }
            }
            .alert("Patch", isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
        }
    }

    private func projectRow(_ project: PatchProject) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(project.name).font(.headline)
            Text("\(project.fileCount) files · \(project.groupTargetCount) app-group targets")
                .font(.caption)
                .foregroundStyle(HATheme.secondaryText)
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }

            let ext = url.pathExtension.lowercased()
            guard ext == "ha" || ext.isEmpty else {
                throw PatchError.invalidPackage
            }

            let data = try Data(contentsOf: url)
            let project = try HAPackageCodec.decode(data)
            appModel.addProject(project)
            appModel.log("imported \(url.lastPathComponent)")
        } catch {
            alertMessage = error.localizedDescription
            appModel.log("import failed: \(error.localizedDescription)")
        }
    }
}

struct PatchDetailView: View {
    @EnvironmentObject private var appModel: AppModel
    let project: PatchProject
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        List {
            Section("Targets") {
                ForEach(project.targets, id: \.self) { target in
                    HStack {
                        Image(systemName: target.hasPrefix("group.") ? "person.2.fill" : "app.fill")
                            .foregroundStyle(HATheme.accent)
                        Text(target)
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }
            Section("Rules") {
                ForEach(project.rules) { rule in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rule.relativePath).font(.subheadline)
                        Text("\(rule.targetID) · \(rule.replacementData.count) bytes")
                            .font(.caption)
                            .foregroundStyle(HATheme.secondaryText)
                    }
                }
            }
            Section {
                Button {
                    apply()
                } label: {
                    Label(busy ? "Applying…" : "Apply Patch", systemImage: "checkmark.shield.fill")
                }
                .disabled(busy)
                .foregroundStyle(HATheme.accent)
            } footer: {
                Text("App data and App Group targets are resolved on this device before write. Originals are backed up when present.")
            }
        }
        .navigationTitle(project.name)
        .alert("Result", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private func apply() {
        busy = true
        defer { busy = false }
        do {
            let receipt = try PatchApplyService.apply(project: project) { appModel.log($0) }
            message = "Applied \(receipt.entries.count) file(s)."
            appModel.log("apply ok project=\(project.name) files=\(receipt.entries.count)")
        } catch {
            message = error.localizedDescription
            appModel.log("apply failed: \(error.localizedDescription)")
        }
    }
}

struct NewPatchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var targetID = ""
    var onCreate: (PatchProject) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Project") {
                    TextField("Name", text: $name)
                }
                Section("First target (optional)") {
                    TextField("com.example.app or group.example.app", text: $targetID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("You can add files later. Use group.* for App Group containers.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New Patch")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        let project = PatchProject(
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? "Untitled"
                                : name.trimmingCharacters(in: .whitespacesAndNewlines),
                            rules: []
                        )
                        onCreate(project)
                        dismiss()
                    }
                }
            }
        }
    }
}

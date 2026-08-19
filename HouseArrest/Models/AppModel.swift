import Foundation
import Combine
import UIKit

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedTab: AppTab = .home
    @Published var projects: [PatchProject] = []
    @Published var logLines: [String] = []
    @Published var installedPatches: [String: InstalledPatchRecord] = [:]

    let device = DeviceInfo.current()

    private let patchStoreKey = "ha.installedPatches"

    init() {
        logLines = HALog.recentLines()
        loadPatches()
        log("session start")
    }

    var logsText: String {
        let disk = HALog.read()
        return disk.isEmpty ? logLines.joined(separator: "\n") : disk
    }

    func log(_ message: String) {
        HALog.write(message)
        let stamp = ISO8601DateFormatter().string(from: Date())
        logLines.insert("\(stamp)  \(message)", at: 0)
        if logLines.count > 500 { logLines = Array(logLines.prefix(500)) }
    }

    func copyLogs() {
        UIPasteboard.general.string = logsText.isEmpty ? "(empty)" : logsText
        log("logs copied")
    }

    func addProject(_ project: PatchProject) {
        projects.insert(project, at: 0)
        log("project added: \(project.name)")
    }

    func markPatched(bundleID: String, projectName: String, receipt: ApplyReceipt) {
        installedPatches[bundleID] = InstalledPatchRecord(
            bundleID: bundleID,
            projectName: projectName,
            receipt: receipt
        )
        savePatches()
    }

    func clearPatch(bundleID: String) {
        installedPatches.removeValue(forKey: bundleID)
        savePatches()
    }

    private func loadPatches() {
        guard let data = UserDefaults.standard.data(forKey: patchStoreKey),
              let decoded = try? JSONDecoder().decode([String: InstalledPatchRecord].self, from: data)
        else { return }
        installedPatches = decoded
    }

    private func savePatches() {
        if let data = try? JSONEncoder().encode(installedPatches) {
            UserDefaults.standard.set(data, forKey: patchStoreKey)
        }
    }
}

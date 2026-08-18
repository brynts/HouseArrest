import Foundation
import Combine

@MainActor
final class AppModel: ObservableObject {
    @Published var selectedTab: AppTab = .home
    @Published var projects: [PatchProject] = []
    @Published var logLines: [String] = []

    let device = DeviceInfo.current()

    func log(_ message: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        logLines.insert("\(stamp)  \(message)", at: 0)
        if logLines.count > 500 { logLines = Array(logLines.prefix(500)) }
    }

    func addProject(_ project: PatchProject) {
        projects.insert(project, at: 0)
        log("project added: \(project.name)")
    }
}

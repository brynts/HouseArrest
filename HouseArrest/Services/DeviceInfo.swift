import Foundation
import UIKit

struct DeviceInfo: Equatable {
    let hardwareModel: String
    let systemVersion: String
    let buildNumber: String
    let isSupported: Bool
    let supportNote: String

    static func current() -> DeviceInfo {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        let model = String(cString: machine)

        let version = UIDevice.current.systemVersion
        let build = Bundle.main.object(forInfoDictionaryKey: "DTPlatformBuild") as? String
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
            ?? "—"

        let major = Int(version.split(separator: ".").first ?? "0") ?? 0
        let supported = major >= 16
        let note = supported
            ? "Verified targets are set in Settings once MCM is wired."
            : "This iOS major may need a newer access layer."

        return DeviceInfo(
            hardwareModel: model.isEmpty ? "Unknown" : model,
            systemVersion: version,
            buildNumber: build,
            isSupported: supported,
            supportNote: note
        )
    }
}

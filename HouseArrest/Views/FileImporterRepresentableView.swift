import SwiftUI
import UniformTypeIdentifiers
import UIKit

enum HADocumentPicker {
    static func presentHA(completion: @escaping (Data?) -> Void) {
        Presenter.shared.present(types: [.haPackage], completion: completion)
    }

    private final class Presenter: NSObject, UIDocumentPickerDelegate {
        static let shared = Presenter()
        private var completion: ((Data?) -> Void)?

        func present(types: [UTType], completion: @escaping (Data?) -> Void) {
            self.completion = completion
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
            picker.delegate = self
            picker.allowsMultipleSelection = false
            picker.shouldShowFileExtensions = true
            guard let host = Self.topViewController() else {
                completion(nil)
                return
            }
            host.present(picker, animated: true)
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            var payload: Data?
            if let url = urls.first {
                let accessed = url.startAccessingSecurityScopedResource()
                payload = try? Data(contentsOf: url)
                if accessed { url.stopAccessingSecurityScopedResource() }
            }
            let done = completion
            completion = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                done?(payload)
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            let done = completion
            completion = nil
            DispatchQueue.main.async {
                done?(nil)
            }
        }

        private static func topViewController() -> UIViewController? {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
            var controller = window?.rootViewController
            while let presented = controller?.presentedViewController {
                controller = presented
            }
            return controller
        }
    }
}

/// Kept so existing sheets still compile.
struct FileImporterRepresentableView: UIViewControllerRepresentable {
    var allowedContentTypes: [UTType]
    var allowsMultipleSelection: Bool = false
    var onDocumentsPicked: ([URL]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDocumentsPicked: onDocumentsPicked)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let host = UIViewController()
        DispatchQueue.main.async {
            HADocumentPicker.presentHA { data in
                guard let data else {
                    onDocumentsPicked([])
                    return
                }
                let dest = FileManager.default.temporaryDirectory.appendingPathComponent("import.ha")
                try? data.write(to: dest)
                onDocumentsPicked([dest])
            }
        }
        return host
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    final class Coordinator {
        var onDocumentsPicked: ([URL]) -> Void
        init(onDocumentsPicked: @escaping ([URL]) -> Void) {
            self.onDocumentsPicked = onDocumentsPicked
        }
    }
}

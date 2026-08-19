import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @AppStorage("ha.appearance") private var appearanceRaw = HAAppearance.system.rawValue
    @State private var copied = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        accentLabel("About", "info.circle")
                    }
                    Link(destination: URL(string: "https://github.com/brynts/HouseArrest")!) {
                        accentLabel("GitHub Repository", "safari")
                    }
                }

                Section("Appearance") {
                    HStack {
                        Text("Theme")
                        Spacer()
                        Picker("Theme", selection: $appearanceRaw) {
                            ForEach(HAAppearance.allCases) { mode in
                                Text(mode.title).tag(mode.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: 220)
                    }
                }

                Section("Debug") {
                    NavigationLink {
                        LogsView()
                    } label: {
                        accentLabel("Logs", "terminal.fill")
                    }
                    Button {
                        appModel.copyLogs()
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            copied = false
                        }
                    } label: {
                        accentLabel(copied ? "Copied" : "Copy logs", "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .disabled(appModel.logLines.isEmpty)
                }
            }
            .tint(HATheme.accent)
            .listItemTint(HATheme.accent)
            .navigationTitle("Settings")
        }
        .tint(HATheme.accent)
    }

    private func accentLabel(_ title: String, _ icon: String) -> some View {
        Label {
            Text(title).foregroundStyle(HATheme.accent)
        } icon: {
            Image(systemName: icon)
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(HATheme.accent)
        }
    }
}

struct AboutView: View {
    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "Version \(version)"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    appIcon
                        .frame(width: 76, height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    Text("HouseArrest")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(HATheme.accent)
                    Text(versionText)
                        .font(.subheadline)
                        .foregroundStyle(HATheme.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowBackground(Color.clear)
            }

            Section("Credits") {
                Link(destination: URL(string: "https://github.com/brynts")!) {
                    HStack(spacing: 12) {
                        AuthorAvatarView()
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("brynts")
                                .foregroundStyle(.primary)
                            Text("Developer")
                                .font(.caption)
                                .foregroundStyle(HATheme.secondaryText)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Section("Special thanks!") {
                Link(destination: URL(string: "https://github.com/forcequitOS/bad_query")!) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("bad_query")
                            Text("forcequitOS")
                                .font(.caption)
                                .foregroundStyle(HATheme.secondaryText)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .tint(HATheme.accent)
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appIcon: some View {
        Group {
            if let icon = UIImage.appIcon {
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(HATheme.accent.opacity(0.2))
                    .overlay {
                        Image(systemName: "lock.house.fill")
                            .font(.largeTitle)
                            .foregroundStyle(HATheme.accent)
                    }
            }
        }
    }
}

struct AuthorAvatarView: View {
    var body: some View {
        AsyncImage(url: URL(string: "https://avatars.githubusercontent.com/u/13285110?v=4")) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                Image(systemName: "person.crop.square.fill")
                    .resizable()
                    .scaledToFill()
                    .foregroundStyle(HATheme.accent)
            }
        }
    }
}

private extension UIImage {
    static var appIcon: UIImage? {
        guard
            let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
            let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
            let files = primary["CFBundleIconFiles"] as? [String],
            let name = files.last
        else {
            return UIImage(named: "AppIcon")
        }
        return UIImage(named: name)
    }
}

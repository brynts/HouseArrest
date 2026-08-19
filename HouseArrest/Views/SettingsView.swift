import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel
    @AppStorage("ha.appearance") private var appearanceRaw = HAAppearance.system.rawValue
    @State private var copied = false

    private var versionText: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "v.\(version)"
    }

    var body: some View {
        NavigationStack {
            List {
                aboutSection
                appearanceSection
                thanksSection
                debugSection
            }
            .tint(HATheme.accent)
            .listItemTint(HATheme.accent)
            .navigationTitle("Settings")
        }
        .tint(HATheme.accent)
    }

    private var aboutSection: some View {
        Section {
            HStack(spacing: 14) {
                avatar
                VStack(alignment: .leading, spacing: 4) {
                    Text("HouseArrest")
                        .font(.headline)
                    Text(versionText)
                        .font(.subheadline)
                        .foregroundStyle(HATheme.secondaryText)
                }
            }
            .padding(.vertical, 4)

            Link(destination: URL(string: "https://github.com/brynts/HouseArrest")!) {
                HStack {
                    Label("GitHub", systemImage: "link")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var appearanceSection: some View {
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
    }

    private var thanksSection: some View {
        Section("Special Thanks") {
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

    private var debugSection: some View {
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

    private var avatar: some View {
        Group {
            if UIImage(named: "AuthorAvatar") != nil {
                Image("AuthorAvatar")
                    .resizable()
                    .scaledToFill()
            } else {
                AsyncImage(url: URL(string: "https://avatars.githubusercontent.com/u/13285110?v=4")) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .foregroundStyle(HATheme.accent)
                }
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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

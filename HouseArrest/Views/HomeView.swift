import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var showLogs = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    statusCard

                    deviceCard
                }
                .padding(16)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationBarHidden(true)
            .sheet(isPresented: $showLogs) { LogsView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("HouseArrest")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            Button { showLogs = true } label: {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(HATheme.accent)
                    .frame(width: 36, height: 36)
                    .background(HATheme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .accessibilityLabel("Logs")

            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(HATheme.accent)
                    .frame(width: 36, height: 36)
                    .background(HATheme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .accessibilityLabel("Settings")
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Patch tool", systemImage: "shippingbox.fill")
                .font(.headline)
                .foregroundStyle(HATheme.accent)

            Text("Apply file replacements into app data and App Group containers.")
                .font(.subheadline)
                .foregroundStyle(HATheme.secondaryText)

            HStack(spacing: 16) {
                metric(title: "Projects", value: "\(appModel.projects.count)")
                metric(title: "Log lines", value: "\(appModel.logLines.count)")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HATheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(HATheme.cardStroke, lineWidth: 1)
        )
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(HATheme.secondaryText)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var deviceCard: some View {
        let d = appModel.device
        return VStack(alignment: .leading, spacing: 0) {
            Text("DEVICE")
                .font(.caption.weight(.semibold))
                .foregroundStyle(HATheme.secondaryText)
                .padding(.bottom, 10)

            row("Hardware model", d.hardwareModel)
            Divider().background(HATheme.cardStroke)
            row("iOS Version", "\(d.systemVersion) (\(d.buildNumber))")
            Divider().background(HATheme.cardStroke)
            HStack {
                Text("Compatibility")
                    .foregroundStyle(.white)
                Spacer()
                if d.isSupported {
                    Label("Supported", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Label("Limited", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                }
            }
            .padding(.vertical, 10)

            Text(d.supportNote)
                .font(.caption)
                .foregroundStyle(HATheme.secondaryText)
                .padding(.top, 4)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HATheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(HATheme.cardStroke, lineWidth: 1)
        )
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.white)
            Spacer()
            Text(value).foregroundStyle(HATheme.secondaryText)
        }
        .padding(.vertical, 10)
    }
}

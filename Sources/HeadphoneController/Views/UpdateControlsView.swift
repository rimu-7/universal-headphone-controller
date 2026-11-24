import SwiftUI

struct UpdateControlsView: View {
    @ObservedObject var updater: AppUpdater
    let beforeChecking: () -> Void

    var body: some View {
        HStack {
            Text("v\(updater.version) · \(updater.build)")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .help("Build \(updater.build)")
            Spacer()
            Menu {
                Button("Check for Updates…") {
                    beforeChecking()
                    updater.checkForUpdates()
                }
                .disabled(!updater.canCheckForUpdates && updater.startupError == nil)
                Toggle("Check Automatically", isOn: Binding(
                    get: { updater.automaticallyChecks }, set: updater.setAutomaticChecks))
                Toggle("Download and Install Automatically", isOn: Binding(
                    get: { updater.automaticallyDownloads }, set: updater.setAutomaticDownloads))
                .disabled(!updater.canAutomaticallyDownload)
                Divider()
                if let checked = updater.lastChecked {
                    Text("Last checked: \(checked.formatted(date: .abbreviated, time: .shortened))")
                }
                Button("Open Latest Release", action: updater.openReleases)
            } label: {
                Label("Updates", systemImage: "arrow.down.circle")
                    .font(.system(size: 11, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help(updater.startupError ?? "Check for updates and manage automatic updates")
        }
        if updater.startupError != nil {
            Text("Updates could not start. Use Updates → Open Latest Release.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

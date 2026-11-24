import AppKit
import Combine
import Sparkle

/// Sparkle owns version comparison, network recovery, signature verification and atomic installation.
/// This model only exposes its real state to the menu-bar UI.
final class AppUpdater: ObservableObject {
    static let shared = AppUpdater()

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecks = false
    @Published private(set) var automaticallyDownloads = false
    @Published private(set) var lastChecked: Date?
    @Published private(set) var startupError: String?

    private let controller: SPUStandardUpdaterController
    private var started = false

    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development" }
    var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0" }
    var canAutomaticallyDownload: Bool { controller.updater.automaticallyChecksForUpdates }

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main).assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: DispatchQueue.main).assign(to: &$automaticallyChecks)
        controller.updater.publisher(for: \.automaticallyDownloadsUpdates)
            .receive(on: DispatchQueue.main).assign(to: &$automaticallyDownloads)
        controller.updater.publisher(for: \.lastUpdateCheckDate)
            .receive(on: DispatchQueue.main).assign(to: &$lastChecked)
    }

    func start() {
        guard !started else { return }
        do {
            try controller.updater.start()
            started = true
            startupError = nil
        } catch {
            startupError = error.localizedDescription
        }
    }

    func checkForUpdates() {
        if !started { start() }
        guard started, controller.updater.canCheckForUpdates else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    func setAutomaticChecks(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
    }

    func setAutomaticDownloads(_ enabled: Bool) {
        guard controller.updater.automaticallyChecksForUpdates || !enabled else { return }
        controller.updater.automaticallyDownloadsUpdates = enabled
    }

    func openReleases() {
        guard let url = URL(string: "https://github.com/rimu-7/universal-headphone-controller/releases/latest") else { return }
        NSWorkspace.shared.open(url)
    }
}

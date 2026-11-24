import AppKit
import Sparkle

/// CI runs the actual packaged executable, exercising dyld and Sparkle before publishing.
/// No Bluetooth/audio discovery, network checks, or installation occurs in this mode.
enum AppSelfTest {
    static func run() -> Int32 {
        do {
            let bundle = Bundle.main
            guard bundle.bundleIdentifier == "com.user.HeadphoneController",
                  let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                  let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
                  let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
                  URL(string: feed)?.scheme == "https",
                  let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
                  Data(base64Encoded: key)?.count == 32 else {
                throw NSError(domain: "AppSelfTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Incomplete packaged app/update configuration"])
            }
            NSApplication.shared.setActivationPolicy(.prohibited)
            let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
            // Validate configuration synchronously, then exit before the scheduled update cycle runs.
            try controller.updater.start()
            let report: [String: Any] = ["status": "ok", "version": version, "build": build,
                                         "bundleIdentifier": bundle.bundleIdentifier!, "updater": "configured"]
            let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
            print(String(decoding: data, as: UTF8.self))
            return 0
        } catch {
            fputs("Packaged app startup failed: \(error.localizedDescription)\n", stderr)
            return 1
        }
    }
}

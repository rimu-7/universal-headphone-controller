import AppKit
import CoreBluetooth

/// Control diagnosis in the real app bundle and its Bluetooth permission context.
/// Read-only by default; optional write verification re-applies the currently reported settings.
enum EdifierDiagnostics {
    static func run() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        let manager = EdifierBLEManager.shared
        var devices: [String: HeadphoneDevice] = [:]
        var summaries: [String: String] = [:]
        let verifyWrites = CommandLine.arguments.contains("--verify-current-settings")
        var phase = 0
        var sawPending = false
        var targetNoise: UInt8?
        var targetScene: EdifierScene?
        var targetID: String?
        var sawReconnect = false
        manager.onDeviceUpdated = { device in
            devices[device.id] = device
            let summary = "\(device.name): controls=\(device.controlState.rawValue) battery=\(device.batteryLevel.map(String.init) ?? "unknown") noise=\(device.edifierNoiseValue.map(String.init) ?? "unknown") scene=\(device.edifierScene?.title ?? "unknown") error=\(device.controlError ?? "none")"
            if summaries[device.id] != summary {
                summaries[device.id] = summary
                print(summary)
                fflush(stdout)
            }
            guard verifyWrites, device.edifierProfile == .fit900NB else { return }
            guard targetID == nil || targetID == device.id else { return }
            if phase == 0, device.canControl(.noiseControl), device.canControl(.sceneMode),
               let noise = device.edifierNoiseValue, let scene = device.edifierScene {
                targetNoise = noise
                targetScene = scene
                targetID = device.id
                phase = 1
                DispatchQueue.main.async { manager.setNoiseOption(for: device.id, value: noise, level: nil) }
            } else if phase == 1 {
                if device.pendingFeatures.contains(.noiseControl) { sawPending = true }
                else if sawPending, device.controlError == nil, device.edifierNoiseValue == targetNoise,
                        let scene = targetScene {
                    print("Verified noise command and GET confirmation: \(targetNoise!)")
                    fflush(stdout)
                    sawPending = false
                    phase = 2
                    DispatchQueue.main.async { manager.setScene(for: device.id, scene: scene) }
                }
            } else if phase == 2 {
                if device.pendingFeatures.contains(.sceneMode) { sawPending = true }
                else if sawPending, device.controlError == nil, device.edifierScene == targetScene {
                    print("Verified scene command and GET confirmation: \(targetScene!.title)")
                    fflush(stdout)
                    phase = 3
                    DispatchQueue.main.async { manager.retry(deviceID: device.id) }
                }
            } else if phase == 3 {
                if device.controlState != .ready { sawReconnect = true }
                if sawReconnect, device.canControl(.noiseControl), device.canControl(.sceneMode),
                   device.batteryIsFromControl, device.edifierNoiseValue == targetNoise,
                   device.edifierScene == targetScene, device.controlError == nil {
                    print("Verified fresh control connection and setting reads")
                    fflush(stdout)
                    phase = 4
                }
            }
        }
        manager.onDeviceRemoved = { devices.removeValue(forKey: $0) }
        print("Edifier diagnostics (\(verifyWrites ? "verify current settings only" : "read-only")). Bluetooth authorization=\(CBCentralManager.authorization.rawValue)")
        fflush(stdout)
        DispatchQueue.main.async { manager.start() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
            for device in devices.values.sorted(by: { $0.id < $1.id }) {
                print(manager.diagnosticReport(for: device.id))
            }
            fflush(stdout)
            manager.stop()
            exit(verifyWrites && phase != 4 ? 1 : 0)
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 35) {
            fputs("Edifier diagnostics exceeded its time limit\n", stderr)
            exit(2)
        }
        app.run()
        exit(0)
    }
}

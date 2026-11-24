import Foundation

struct SystemBluetoothDevice {
    let name: String
    let address: String
    let isConnected: Bool
    let battery: Int?
}

/// macOS reports HFP connectivity/battery even when IOBluetooth's proprietary-control API stalls.
/// Runs off the main queue, with a process timeout and a bounded JSON buffer.
enum BluetoothBatteryReader {
    static func fetch(completion: @escaping ([String: Int]) -> Void) {
        fetchDevices { devices in
            var batteries: [String: Int] = [:]
            for device in devices ?? [] where device.isConnected {
                if let battery = device.battery { batteries[device.address] = battery }
            }
            completion(batteries)
        }
    }

    static func fetchDevices(completion: @escaping ([SystemBluetoothDevice]?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            // "mini" removes device addresses, which are required for safe identity matching.
            process.arguments = ["SPBluetoothDataType", "-json", "-detailLevel", "full"]
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do { try process.run() }
            catch { DispatchQueue.main.async { completion(nil) }; return }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 10) {
                if process.isRunning { process.terminate() }
            }
            var data = Data()
            var oversized = false
            while true {
                let chunk = output.fileHandleForReading.readData(ofLength: 8192)
                if chunk.isEmpty { break }
                if !oversized && data.count + chunk.count <= 1_048_576 { data.append(chunk) }
                else { oversized = true }
            }
            process.waitUntilExit()
            let devices = process.terminationStatus == 0 && !oversized ? parseDevices(data) : nil
            DispatchQueue.main.async { completion(devices) }
        }
    }

    static func normalizedAddress(_ address: String) -> String {
        address.uppercased().replacingOccurrences(of: "-", with: ":")
    }

    static func parse(_ data: Data) -> [String: Int] {
        var result: [String: Int] = [:]
        for device in parseDevices(data) ?? [] where device.isConnected {
            if let level = device.battery { result[device.address] = level }
        }
        return result
    }

    static func parseDevices(_ data: Data) -> [SystemBluetoothDevice]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = json["SPBluetoothDataType"] as? [[String: Any]],
              controllers.contains(where: { $0["controller_properties"] != nil || $0["device_connected"] != nil || $0["device_not_connected"] != nil }) else { return nil }
        var result: [SystemBluetoothDevice] = []
        for controller in controllers {
            for (key, connected) in [("device_connected", true), ("device_not_connected", false)] {
                for entry in controller[key] as? [[String: Any]] ?? [] {
                    for (name, value) in entry {
                        guard let info = value as? [String: Any], let address = info["device_address"] as? String else { continue }
                        var battery: Int?
                        if connected, let raw = info["device_batteryLevelMain"] as? String,
                           let level = Int(raw.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)),
                           (0...100).contains(level) { battery = level }
                        result.append(SystemBluetoothDevice(name: name, address: normalizedAddress(address), isConnected: connected, battery: battery))
                    }
                }
            }
        }
        return result
    }
}

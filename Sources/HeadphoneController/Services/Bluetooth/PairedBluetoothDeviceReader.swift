import Foundation
import IOBluetooth

/// IOBluetooth's CoreBluetooth coordinator can wait for a main-queue callback while initializing.
/// Calling pairedDevices() on the main thread can therefore deadlock the entire menu bar app.
enum PairedBluetoothDeviceReader {
    private static let queue = DispatchQueue(label: "headphone.paired-device-discovery", qos: .utility)

    static func fetch(read: @escaping () -> [IOBluetoothDevice] = {
        IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
    }, completion: @escaping ([IOBluetoothDevice]) -> Void) {
        queue.async {
            let devices = read()
            DispatchQueue.main.async { completion(devices) }
        }
    }
}

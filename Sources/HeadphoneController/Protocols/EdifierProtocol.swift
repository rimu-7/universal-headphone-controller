import Foundation

public enum EdifierFraming: String, CaseIterable {
    case connex, legacy
}

public struct EdifierPacket {
    public let direction: UInt8
    public let app: UInt8
    public let command: UInt8
    public let data: Data
    public let isConnex: Bool

    public static let requestInit: UInt8 = 0xAA
    public static let responseInitBB: UInt8 = 0xBB
    public static let responseInitCC: UInt8 = 0xCC
    public static let appConneX: UInt8 = 0xEC
    public static let maximumPayload = 4096

    public static let cmdGameModeGet: UInt8 = 0x08
    public static let cmdGameModeSet: UInt8 = 0x09
    public static let cmdANCSet: UInt8 = 0xC1
    public static let cmdSoundEffectSet: UInt8 = 0xC4
    public static let cmdFirmwareGet: UInt8 = 0xC6
    public static let cmdClassicMACGet: UInt8 = 0xC8
    public static let cmdDeviceNameGet: UInt8 = 0xC9
    public static let cmdANCGet: UInt8 = 0xCC
    public static let cmdBatteryGet: UInt8 = 0xD0
    public static let cmdSoundEffectGet: UInt8 = 0xD5
    public static let cmdCapabilityGet: UInt8 = 0xD8
    public static let cmdHeadsetStateGet: UInt8 = 0xF2

    public var framing: EdifierFraming { isConnex ? .connex : .legacy }

    public init(direction: UInt8 = requestInit, app: UInt8 = appConneX,
                command: UInt8, data: Data = Data(), isConnex: Bool = true) {
        self.direction = direction
        self.app = app
        self.command = command
        self.data = Data(data)
        self.isConnex = isConnex
    }

    /// Invalid/oversized packets are never put on the wire.
    public func toData() -> Data {
        guard data.count <= Self.maximumPayload, isConnex || data.count <= 254 else { return Data() }
        if isConnex {
            var frame = Data([direction, app, command, UInt8(data.count >> 8), UInt8(data.count & 0xFF)])
            frame.append(data)
            frame.append(ChecksumUtility.connexChecksum(frame))
            return frame
        }
        var frame = Data([direction, UInt8(data.count + 1), command])
        frame.append(data)
        let checksum = ChecksumUtility.edifierChecksum(frame)
        frame.append(contentsOf: [UInt8(checksum >> 8), UInt8(checksum & 0xFF)])
        return frame
    }

    public static func fromData(_ buffer: Data) -> EdifierPacket? {
        // Data slices need not start at index zero.
        let bytes = [UInt8](buffer)
        guard bytes.count >= 5, [requestInit, responseInitBB, responseInitCC].contains(bytes[0]) else { return nil }
        if bytes[1] == appConneX || bytes[1] == 0xED {
            guard bytes.count >= 6 else { return nil }
            let length = Int(bytes[3]) << 8 | Int(bytes[4])
            guard length <= maximumPayload, bytes.count == length + 6,
                  ChecksumUtility.connexChecksum(Data(bytes.dropLast())) == bytes.last else { return nil }
            return EdifierPacket(direction: bytes[0], app: bytes[1], command: bytes[2],
                                 data: Data(bytes[5..<(5 + length)]))
        }
        let length = Int(bytes[1])
        guard length >= 1, bytes.count == length + 4 else { return nil }
        let checksum = UInt16(bytes[bytes.count - 2]) << 8 | UInt16(bytes[bytes.count - 1])
        guard ChecksumUtility.edifierChecksum(Data(bytes.dropLast(2))) == checksum else { return nil }
        return EdifierPacket(direction: bytes[0], app: 0, command: bytes[2],
                             data: Data(bytes[3..<(length + 2)]), isConnex: false)
    }
}

/// One decoder per connection; handles fragmentation, coalescing, garbage and stale partial frames.
public struct EdifierFrameDecoder {
    private var bytes: [UInt8] = []
    private var lastReceived: TimeInterval?
    public private(set) var rejectedFrames = 0
    public var bufferedByteCount: Int { bytes.count }

    public init() {}

    public mutating func append(_ data: Data, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> [EdifierPacket] {
        if let lastReceived, now - lastReceived > 5 { bytes.removeAll() }
        lastReceived = now
        if bytes.count + data.count > 2 * (EdifierPacket.maximumPayload + 6) { bytes.removeAll() }
        bytes.append(contentsOf: data.suffix(2 * (EdifierPacket.maximumPayload + 6)))
        var packets: [EdifierPacket] = []
        while !bytes.isEmpty {
            guard [UInt8(0xAA), 0xBB, 0xCC].contains(bytes[0]) else { bytes.removeFirst(); continue }
            guard bytes.count >= 2 else { break }
            let length: Int
            if bytes[1] == 0xEC || bytes[1] == 0xED {
                guard bytes.count >= 5 else { break }
                let payload = Int(bytes[3]) << 8 | Int(bytes[4])
                guard payload <= EdifierPacket.maximumPayload else {
                    bytes.removeFirst(); rejectedFrames += 1; continue
                }
                length = payload + 6
            } else {
                guard bytes[1] > 0 else { bytes.removeFirst(); rejectedFrames += 1; continue }
                length = Int(bytes[1]) + 4
            }
            guard bytes.count >= length else { break }
            if let packet = EdifierPacket.fromData(Data(bytes.prefix(length))) {
                packets.append(packet)
                bytes.removeFirst(length)
            } else {
                bytes.removeFirst()
                rejectedFrames += 1
            }
        }
        return packets
    }
}

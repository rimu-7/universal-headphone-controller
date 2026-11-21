import Foundation

public struct EdifierPacket {
    public let direction: UInt8
    public let command: UInt8
    public let data: Data
    
    public static let requestInit: UInt8 = 0xAA
    public static let responseInitBB: UInt8 = 0xBB
    public static let responseInitCC: UInt8 = 0xCC
    
    // Commands
    public static let cmdPromptVolGet: UInt8 = 0x05
    public static let cmdPromptVolSet: UInt8 = 0x06
    public static let cmdGameModeGet: UInt8 = 0x08
    public static let cmdGameModeSet: UInt8 = 0x09
    public static let cmdSoundEffectSet: UInt8 = 0xC4
    public static let cmdANCSet: UInt8 = 0xC1
    public static let cmdPlaybackState: UInt8 = 0xC3
    public static let cmdDeviceNameGet: UInt8 = 0xC9
    public static let cmdANCGet: UInt8 = 0xCC
    public static let cmdBatteryGet: UInt8 = 0xD0
    
    public init(direction: UInt8 = requestInit, command: UInt8, data: Data = Data()) {
        self.direction = direction
        self.command = command
        self.data = data
    }
    
    public func toData() -> Data {
        var packet = Data()
        packet.append(direction)
        packet.append(UInt8(data.count + 1))
        packet.append(command)
        packet.append(data)
        
        let crc = ChecksumUtility.edifierChecksum(packet)
        packet.append(UInt8((crc >> 8) & 0xFF))
        packet.append(UInt8(crc & 0xFF))
        return packet
    }
    
    public static func fromData(_ buffer: Data) -> EdifierPacket? {
        guard buffer.count >= 5 else { return nil }
        guard buffer[0] == responseInitBB || buffer[0] == responseInitCC || buffer[0] == requestInit else {
            return nil
        }
        
        let length = Int(buffer[1])
        guard buffer.count >= length + 4 else { return nil }
        
        let cmd = buffer[2]
        let payload = buffer.subdata(in: 3..<(length + 2))
        
        // Verify CRC
        let expectedCRC = (UInt16(buffer[length + 2]) << 8) | UInt16(buffer[length + 3])
        let calcCRC = ChecksumUtility.edifierChecksum(buffer.subdata(in: 0..<(length + 2)))
        guard expectedCRC == calcCRC else {
            return nil
        }
        
        return EdifierPacket(direction: buffer[0], command: cmd, data: payload)
    }
    
    // Packet builders
    public static func buildBatteryRequest() -> Data {
        let pkt = EdifierPacket(command: cmdBatteryGet)
        return pkt.toData()
    }
    
    public static func buildANCGetRequest() -> Data {
        let pkt = EdifierPacket(command: cmdANCGet)
        return pkt.toData()
    }
    
    public static func buildANCSetRequest(mode: ANCMode) -> Data {
        // Mode mapping:
        // 0x01: Disabled / Normal
        // 0x02: Noise Cancellation
        // 0x03: Ambient / Transparency
        let modeByte: UInt8
        switch mode {
        case .off:
            modeByte = 0x01
        case .cancellation:
            modeByte = 0x02
        case .awareness:
            modeByte = 0x03
        }
        let pkt = EdifierPacket(command: cmdANCSet, data: Data([modeByte]))
        return pkt.toData()
    }
    
    public static func buildGameModeGetRequest() -> Data {
        let pkt = EdifierPacket(command: cmdGameModeGet)
        return pkt.toData()
    }
    
    public static func buildGameModeSetRequest(enabled: Bool) -> Data {
        let pkt = EdifierPacket(command: cmdGameModeSet, data: Data([enabled ? 0x01 : 0x00]))
        return pkt.toData()
    }
    
    public static func buildSoundEffectRequest(effect: UInt8) -> Data {
        let pkt = EdifierPacket(command: cmdSoundEffectSet, data: Data([effect]))
        return pkt.toData()
    }
    
    public static func buildDeviceNameRequest() -> Data {
        let pkt = EdifierPacket(command: cmdDeviceNameGet)
        return pkt.toData()
    }
}

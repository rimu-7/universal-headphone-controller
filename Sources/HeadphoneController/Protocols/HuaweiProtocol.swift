import Foundation

public struct HuaweiTLV {
    public let type: UInt8
    public let value: Data
    
    public init(type: UInt8, value: Data) {
        self.type = type
        self.value = value
    }
}

public struct HuaweiPacket {
    public let command: UInt16
    public let parameters: [UInt8: Data]
    
    public static let magicByte: UInt8 = 0x5A
    
    // Command Constants
    public static let cmdBatteryRead: UInt16 = 0x0108
    public static let cmdBatteryNotify: UInt16 = 0x0127
    public static let cmdANCRead: UInt16 = 0x2B2A
    public static let cmdANCWrite: UInt16 = 0x2B04
    public static let cmdLowLatency: UInt16 = 0x2B6C
    public static let cmdEqualizer: UInt16 = 0x2B4A
    
    public init(command: UInt16, parameters: [UInt8: Data] = [:]) {
        self.command = command
        self.parameters = parameters
    }
    
    public func toData() -> Data {
        var body = Data()
        body.append(UInt8((command >> 8) & 0xFF))
        body.append(UInt8(command & 0xFF))
        
        for (pType, pValue) in parameters {
            body.append(pType)
            body.append(UInt8(pValue.count))
            body.append(pValue)
        }
        
        var packet = Data([HuaweiPacket.magicByte])
        let length = UInt16(body.count + 1)
        packet.append(UInt8((length >> 8) & 0xFF))
        packet.append(UInt8(length & 0xFF))
        packet.append(0x00) // Fixed direction indicator
        packet.append(body)
        
        let crc = ChecksumUtility.crc16Xmodem(packet)
        packet.append(UInt8((crc >> 8) & 0xFF))
        packet.append(UInt8(crc & 0xFF))
        return packet
    }
    
    public static func fromData(_ data: Data) -> HuaweiPacket? {
        guard data.count >= 8, data[0] == HuaweiPacket.magicByte, data[3] == 0x00 else {
            return nil
        }
        
        let length = (Int(data[1]) << 8) | Int(data[2])
        guard data.count >= length + 3 + 2 else {
            return nil
        }
        
        let command = (UInt16(data[4]) << 8) | UInt16(data[5])
        var params: [UInt8: Data] = [:]
        
        var pos = 6
        let endPos = 3 + length
        while pos + 1 < endPos && pos + 1 < data.count {
            let pType = data[pos]
            let pLen = Int(data[pos + 1])
            if pos + 2 + pLen <= data.count {
                let pVal = data.subdata(in: (pos + 2)..<(pos + 2 + pLen))
                params[pType] = pVal
            }
            pos += 2 + pLen
        }
        
        return HuaweiPacket(command: command, parameters: params)
    }
    
    // Quick packet builders
    public static func buildBatteryReadRequest() -> Data {
        let pkt = HuaweiPacket(command: cmdBatteryRead, parameters: [
            1: Data(),
            2: Data(),
            3: Data()
        ])
        return pkt.toData()
    }
    
    public static func buildANCReadRequest() -> Data {
        let pkt = HuaweiPacket(command: cmdANCRead, parameters: [
            1: Data(),
            2: Data()
        ])
        return pkt.toData()
    }
    
    public static func buildANCWriteRequest(mode: ANCMode, level: UInt8 = 0xFF) -> Data {
        let payload: Data
        switch mode {
        case .off:
            payload = Data([0x00, 0x00])
        case .cancellation:
            payload = Data([0x01, level])
        case .awareness:
            payload = Data([0x02, level])
        }
        let pkt = HuaweiPacket(command: cmdANCWrite, parameters: [
            1: payload
        ])
        return pkt.toData()
    }
    
    public static func buildLowLatencyRequest(enabled: Bool) -> Data {
        let val: UInt8 = enabled ? 0x01 : 0x00
        let pkt = HuaweiPacket(command: cmdLowLatency, parameters: [
            1: Data([val])
        ])
        return pkt.toData()
    }
    
    public static func buildEqualizerRequest(preset: EqualizerPreset) -> Data {
        let pkt = HuaweiPacket(command: cmdEqualizer, parameters: [
            1: Data([UInt8(preset.rawValue)])
        ])
        return pkt.toData()
    }
}

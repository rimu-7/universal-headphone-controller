import Foundation
import XCTest
@testable import HeadphoneController

final class EdifierProtocolTests: XCTestCase {
    func testCapturedLegacyVectors() {
        XCTAssertEqual(EdifierPacket(command: 0xC1, data: Data([1]), isConnex: false).toData(), Data([0xAA, 2, 0xC1, 1, 0x21, 0x87]))
        let response = Data([0xBB, 3, 0xC1, 1, 6, 0x21, 0x9F])
        let packet = EdifierPacket.fromData(response)
        XCTAssertEqual(packet?.command, 0xC1)
        XCTAssertEqual(packet?.data, Data([1, 6]))
        XCTAssertEqual(packet?.toData(), response)
    }

    func testCapturedConnexVectorAndDirectionPreserved() {
        XCTAssertEqual(EdifierPacket(command: 0xD8).toData(), Data([0xAA, 0xEC, 0xD8, 0, 0, 0x6E]))
        let response = Data([0xBB, 0xEC, 0xD5, 0, 1, 0, 0x7D])
        XCTAssertEqual(EdifierPacket.fromData(response)?.toData(), response)
    }

    func testRejectsCorruptTruncatedZeroLengthAndOversizeFrames() {
        XCTAssertNil(EdifierPacket.fromData(Data([0xBB, 0, 0, 0x20, 0xD4])))
        XCTAssertNil(EdifierPacket.fromData(Data([0xBB, 0xEC, 0xD0, 0xFF, 0xFF, 0])))
        for framing in EdifierFraming.allCases {
            let valid = EdifierPacket(direction: 0xBB, command: 0xD0, data: Data([40]), isConnex: framing == .connex).toData()
            XCTAssertNil(EdifierPacket.fromData(valid.dropLast()))
            var corrupt = valid
            corrupt[corrupt.count - 1] ^= 1
            XCTAssertNil(EdifierPacket.fromData(corrupt))
            XCTAssertNil(EdifierPacket.fromData(valid + valid))
        }
        XCTAssertTrue(EdifierPacket(command: 1, data: Data(repeating: 0, count: 255), isConnex: false).toData().isEmpty)
        XCTAssertTrue(EdifierPacket(command: 1, data: Data(repeating: 0, count: 4097)).toData().isEmpty)
    }

    func testNonZeroDataSliceIndices() {
        let frame = EdifierPacket(direction: 0xBB, command: 0xD0, data: Data([0])).toData()
        let storage = Data([7, 8, 9]) + frame
        XCTAssertEqual(EdifierPacket.fromData(storage.dropFirst(3))?.data, Data([0]))
    }

    func testEveryFragmentBoundaryAndCoalescing() {
        for framing in EdifierFraming.allCases {
            let frame = EdifierPacket(direction: 0xBB, command: 0xD0, data: Data([76]), isConnex: framing == .connex).toData()
            for split in 1..<frame.count {
                var decoder = EdifierFrameDecoder()
                XCTAssertTrue(decoder.append(frame.prefix(split), now: 0).isEmpty)
                let packets = decoder.append(frame.dropFirst(split) + frame, now: 1)
                XCTAssertEqual(packets.count, 2, "split \(split), \(framing)")
                XCTAssertTrue(packets.allSatisfy { $0.data == Data([76]) })
                XCTAssertEqual(decoder.bufferedByteCount, 0)
            }
        }
    }

    func testDecoderRecoversFromGarbageBadChecksumAndStaleFrame() {
        let frame = EdifierPacket(direction: 0xBB, command: 0xD0, data: Data([65])).toData()
        var bad = frame
        bad[bad.count - 1] ^= 1
        var decoder = EdifierFrameDecoder()
        XCTAssertEqual(decoder.append(Data([0, 1, 2]) + bad + frame, now: 0).count, 1)
        XCTAssertGreaterThan(decoder.rejectedFrames, 0)
        XCTAssertTrue(decoder.append(Data([0xBB, 0xEC, 0xD0, 0, 100]), now: 1).isEmpty)
        XCTAssertEqual(decoder.append(frame, now: 7).count, 1)
    }

    func testDecoderMemoryBound() {
        var decoder = EdifierFrameDecoder()
        _ = decoder.append(Data(repeating: 0xAA, count: 100_000), now: 0)
        XCTAssertLessThanOrEqual(decoder.bufferedByteCount, 2 * (EdifierPacket.maximumPayload + 6))
    }

    func testProfilesUseModelAndServiceAndConservativeFeatures() {
        XCTAssertEqual(EdifierProfile.resolve(name: "EDIFIER Fit 900NB"), .fit900NB)
        XCTAssertEqual(EdifierProfile.resolve(name: "EDIFIER BLE", service: "48097901" + EdifierProfile.serviceSuffix), .w820NBDoubleGold)
        XCTAssertFalse(EdifierProfile.w820NB.queries(.equalizer))
        XCTAssertFalse(EdifierProfile.w200BTPlus.queries(.noiseControl))
        XCTAssertFalse(EdifierProfile.unknown.queries(.equalizer))
        XCTAssertTrue(EdifierProfile.matches(name: "EDIFIER W830NB"))
        XCTAssertFalse(EdifierProfile.isControlService("0000180F-0000-1000-8000-00805F9B34FB"))
    }

    func testAdditiveChecksumsWrapWithoutOverflow() {
        let bytes = Data(repeating: 255, count: 4096)
        XCTAssertEqual(ChecksumUtility.connexChecksum(bytes), 0)
        XCTAssertEqual(ChecksumUtility.edifierChecksum(bytes), 0x1019)
    }
    func testSystemBatteryParserMatchesAddressesAndConnectedDevicesOnly() {
        let json = Data("""
        {"SPBluetoothDataType":[{
          "device_connected":[
            {"EDIFIER Fit900NB":{"device_address":"AA-BB-CC-DD-EE-FF","device_batteryLevelMain":"100%"}},
            {"Empty":{"device_address":"00:00:00:00:00:01","device_batteryLevelMain":"0%"}},
            {"Invalid":{"device_address":"00:00:00:00:00:02","device_batteryLevelMain":"255%"}},
            {"Unknown":{"device_address":"00:00:00:00:00:03"}}
          ],
          "device_not_connected":[
            {"Old":{"device_address":"00:00:00:00:00:04","device_batteryLevelMain":"80%"}}
          ]
        }]}
        """.utf8)
        let batteries = BluetoothBatteryReader.parse(json)
        XCTAssertEqual(batteries.count, 2)
        XCTAssertEqual(batteries["AA:BB:CC:DD:EE:FF"], 100)
        XCTAssertEqual(batteries["00:00:00:00:00:01"], 0)
        XCTAssertTrue(BluetoothBatteryReader.parse(Data("invalid".utf8)).isEmpty)
        XCTAssertTrue(BluetoothBatteryReader.parse(Data("{}".utf8)).isEmpty)
    }

    func testPairedDeviceDiscoveryRunsOffMainAndDeliversOnMain() {
        var readOffMain = false
        var completed = false
        PairedBluetoothDeviceReader.fetch(read: {
            readOffMain = !Thread.isMainThread
            return []
        }) { devices in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertTrue(readOffMain)
            XCTAssertTrue(devices.isEmpty)
            completed = true
        }
        let deadline = Date().addingTimeInterval(2)
        while !completed && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(completed)
    }

    func testSystemDiscoveryDoesNotNeedBatteryAndRejectsMissingControllerReports() {
        let json = Data("""
        {"SPBluetoothDataType":[{
          "controller_properties":{"controller_state":"attrib_on"},
          "device_connected":[{"EDIFIER Fit900NB":{"device_address":"AA:BB:CC:DD:EE:FF"}}],
          "device_not_connected":[{"EDIFIER W820NB":{"device_address":"11:22:33:44:55:66","device_batteryLevelMain":"80%"}}]
        }]}
        """.utf8)
        let devices = BluetoothBatteryReader.parseDevices(json)
        XCTAssertEqual(devices?.count, 2)
        XCTAssertEqual(devices?.first?.name, "EDIFIER Fit900NB")
        XCTAssertEqual(devices?.first?.isConnected, true)
        XCTAssertNil(devices?.first?.battery)
        XCTAssertEqual(devices?.last?.isConnected, false)
        XCTAssertNil(devices?.last?.battery)
        XCTAssertNil(BluetoothBatteryReader.parseDevices(Data("{\"SPBluetoothDataType\":[{}]}".utf8)))
    }

}

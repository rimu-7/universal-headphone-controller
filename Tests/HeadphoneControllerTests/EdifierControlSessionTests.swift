import Foundation
import XCTest
@testable import HeadphoneController

final class EdifierControlSessionTests: XCTestCase {
    private func device(_ id: String = "test", profile: EdifierProfile = .fit900NB) -> HeadphoneDevice {
        let device = HeadphoneDevice(id: id, name: "EDIFIER Fit900NB", brand: .edifier, isConnected: true)
        device.edifierProfile = profile
        return device
    }

    private func packet(_ command: UInt8, _ data: [UInt8], framing: EdifierFraming = .connex, direction: UInt8 = 0xBB) -> EdifierPacket {
        EdifierPacket(direction: direction, command: command, data: Data(data), isConnex: framing == .connex)
    }

    /// Simulate a headset answering supported reads. Mutations are tested separately.
    private func readySession(_ device: HeadphoneDevice, framing: EdifierFraming = .connex) -> (EdifierControlSession, TimeInterval) {
        let session = EdifierControlSession(device: device)
        var outbound: [EdifierPacket] = []
        session.send = { data in outbound.append(EdifierPacket.fromData(data)!); return true }
        session.start(now: 0)
        for index in 0...150 {
            let now = Double(index) / 10
            session.tick(now: now)
            let frames = outbound
            outbound.removeAll()
            for request in frames where request.framing == framing {
                let response: [UInt8]
                switch request.command {
                case 0xD8: response = [1, 2, 3]
                case 0xD0: response = [50]
                case 0xCC: response = framing == .connex ? [0x10, 1, 6] : [1, 6]
                case 0x08: response = [0]
                case 0xD5: response = [0]
                case 0xC6: response = [1, 0, 2]
                case 0xC9: response = Array("EDIFIER BLE".utf8)
                case 0xC8: response = [1, 2, 3, 4, 5, 6]
                default: continue
                }
                session.receive(packet(request.command, response, framing: framing), now: now)
            }
        }
        XCTAssertEqual(device.controlState, .ready)
        return (session, 15)
    }

    func testDetectsLegacyFallbackAndLoadsFeatures() {
        let device = device()
        let (session, _) = readySession(device, framing: .legacy)
        XCTAssertEqual(session.framing, .legacy)
        XCTAssertEqual(device.batteryLevel, 50)
        XCTAssertTrue(device.hasANCState)
        XCTAssertTrue(device.canControl(.noiseControl))
        XCTAssertTrue(device.canControl(.sceneMode))
        XCTAssertFalse(device.canControl(.equalizer))
        XCTAssertEqual(device.firmwareVersion, "1.0.2")
    }

    func testZeroBatteryIsValidAndInvalidValuesDoNotOverwrite() {
        let device = device()
        let (session, now) = readySession(device)
        session.receive(packet(0xD0, [0]), now: now)
        XCTAssertEqual(device.batteryLevel, 0)
        session.receive(packet(0xD0, [255]), now: now)
        session.receive(packet(0xD0, [50, 60]), now: now)
        XCTAssertEqual(device.batteryLevel, 0)
    }

    func testUnrecognizedStateDoesNotBecomeOffOrDefault() {
        let device = device()
        let (session, now) = readySession(device)
        session.receive(packet(0xCC, [0x10, 2, 8]), now: now)
        session.receive(packet(0xCC, [0xFF]), now: now)
        session.receive(packet(0x08, [0xFF]), now: now)
        session.receive(packet(0xD5, [0xFF]), now: now)
        XCTAssertEqual(device.ancMode, .cancellation)
        XCTAssertEqual(device.ancLevel, 8)
        XCTAssertEqual(device.gameModeEnabled, false)
        XCTAssertNil(device.equalizerPreset)
    }

    func testANCRequiresReadbackAndUsesObservedIndexedPayload() {
        let device = device()
        let (session, now) = readySession(device)
        var sent: [EdifierPacket] = []
        session.send = { sent.append(EdifierPacket.fromData($0)!); return true }
        session.setANC(.awareness, level: 8)
        XCTAssertEqual(device.ancMode, .cancellation)
        XCTAssertTrue(device.pendingFeatures.contains(.noiseControl))
        session.tick(now: now + 0.2)
        XCTAssertEqual(sent.last?.command, 0xC1)
        XCTAssertEqual(sent.last?.data, Data([0x10, 4, 8]))
        session.receive(packet(0xC1, [1]), now: now + 0.3) // ConneX BB ACK, not a mode value.
        XCTAssertEqual(device.ancMode, .cancellation)
        session.receive(packet(0xCC, [0x10, 1, 6]), now: now + 0.4) // Stale push.
        XCTAssertEqual(device.ancMode, .cancellation)
        session.tick(now: now + 2.6)
        XCTAssertEqual(sent.last?.command, 0xCC)
        session.receive(packet(0xCC, [0x10, 4, 8]), now: now + 2.7)
        XCTAssertEqual(device.ancMode, .awareness)
        XCTAssertEqual(device.ancLevel, 8)
        XCTAssertFalse(device.pendingFeatures.contains(.noiseControl))
        XCTAssertNil(device.controlError)
    }

    func testGameModeACKCannotPretendToBeConfirmedState() {
        let device = device()
        let (session, now) = readySession(device)
        session.send = { _ in true }
        session.setGameMode(true)
        session.tick(now: now + 0.2)
        session.receive(packet(0x09, [1], direction: 0xCC), now: now + 0.3)
        XCTAssertEqual(device.gameModeEnabled, false)
        session.tick(now: now + 0.8)
        session.receive(packet(0x08, [1]), now: now + 0.9)
        XCTAssertEqual(device.gameModeEnabled, true)
        XCTAssertTrue(device.pendingFeatures.isEmpty)
    }

    func testTimedOutChangeRetainsConfirmedValueAndShowsError() {
        let device = device(profile: .w820NBDoubleGold)
        let (session, now) = readySession(device)
        session.send = { _ in true }
        session.setEqualizer(.bass)
        for index in 1...50 { session.tick(now: now + Double(index) / 10) }
        XCTAssertEqual(device.equalizerPreset, .defaultPreset)
        XCTAssertTrue(device.pendingFeatures.isEmpty)
        XCTAssertNotNil(device.controlError)
    }

    func testRejectedWriteClearsPendingAndDoesNotSendConfirmation() {
        let device = device()
        let (session, now) = readySession(device)
        session.send = { _ in true }
        session.setGameMode(true)
        session.tick(now: now + 0.2)
        session.receive(packet(0x09, [0], direction: 0xCC), now: now + 0.3)
        XCTAssertTrue(device.pendingFeatures.isEmpty)
        XCTAssertEqual(device.gameModeEnabled, false)
        XCTAssertNotNil(device.controlError)
    }

    func testUnsupportedAndDisconnectedControlsCannotSendOrChangeState() {
        let device = device()
        let session = EdifierControlSession(device: device)
        var writes = 0
        session.send = { _ in writes += 1; return true }
        session.setANC(.cancellation, level: nil)
        session.setGameMode(true)
        session.setEqualizer(.bass)
        session.tick(now: 1)
        XCTAssertEqual(writes, 0)
        XCTAssertEqual(device.ancMode, .off)
        XCTAssertTrue(device.pendingFeatures.isEmpty)
    }

    func testNoResponsesEventuallyReportsUnavailableWithoutWrites() {
        let device = device()
        let session = EdifierControlSession(device: device)
        var sent: [UInt8] = []
        session.send = { sent.append(EdifierPacket.fromData($0)!.command); return true }
        session.start(now: 0)
        for index in 0...100 { session.tick(now: Double(index) / 10) }
        XCTAssertEqual(device.controlState, .unavailable)
        XCTAssertTrue(device.supportedFeatures.isEmpty)
        XCTAssertEqual(Set(sent), Set([0xD8, 0xD0, 0xC9]))
    }

    func testIndependentSessionsAndResetDiscardPartialFrames() {
        let a = device("a"), b = device("b")
        let (first, now) = readySession(a)
        let (second, _) = readySession(b)
        first.receive(packet(0xD0, [80]), now: now)
        XCTAssertEqual(a.batteryLevel, 80)
        XCTAssertEqual(b.batteryLevel, 50)
        let frame = packet(0xD0, [20]).toData()
        second.receive(frame.prefix(4), now: now)
        second.disconnect()
        second.receive(frame.dropFirst(4), now: now + 0.1)
        XCTAssertEqual(b.batteryLevel, 50)
        XCTAssertFalse(b.canControl(.noiseControl))
        XCTAssertTrue(b.supportedFeatures.isEmpty)
    }

    func testTransportFailureClearsPendingAndReportsUnavailable() {
        let device = device()
        let (session, now) = readySession(device)
        session.send = { _ in false }
        session.setGameMode(true)
        session.tick(now: now + 0.2)
        XCTAssertEqual(device.controlState, .unavailable)
        XCTAssertTrue(device.pendingFeatures.isEmpty)
        XCTAssertNotNil(device.controlError)
    }

    func testMismatchingReadbackShowsActualHardwareState() {
        let device = device(profile: .w820NBDoubleGold)
        let (session, now) = readySession(device)
        session.send = { _ in true }
        session.setEqualizer(.bass)
        session.tick(now: now + 0.2)
        session.receive(packet(0xC4, [1]), now: now + 0.3)
        session.tick(now: now + 0.8)
        session.receive(packet(0xD5, [2]), now: now + 0.9)
        XCTAssertEqual(device.equalizerPreset, .treble)
        XCTAssertTrue(device.pendingFeatures.isEmpty)
        XCTAssertNotNil(device.controlError)
    }
    func testCapturedFit900BatteryAndChargingStatus() {
        let device = device()
        let (session, now) = readySession(device)
        session.receive(Data([0xBB, 0xEC, 0xD0, 0, 1, 0x60, 0xD8]), now: now)
        XCTAssertEqual(device.batteryLevel, 96)
        session.receive(Data([0xBB, 0xEC, 0xF2, 0, 6, 4, 0, 0, 0x60, 0, 0, 3]), now: now)
        XCTAssertEqual(device.batteryLevel, 96)
        XCTAssertFalse(device.isCharging)
        session.receive(packet(0xF2, [4, 0, 0, 0, 1, 0]), now: now)
        XCTAssertEqual(device.batteryLevel, 0)
        XCTAssertTrue(device.isCharging)
        session.receive(packet(0xF2, [4, 0, 0, 255, 1, 0]), now: now)
        XCTAssertEqual(device.batteryLevel, 0)
    }

    func testFit900HasFiveIndexedNoiseModes() {
        let device = device()
        let (session, now) = readySession(device)
        let modes: [ANCMode] = [.cancellation, .cancellation, .cancellation, .awareness, .off]
        for (index, mode) in modes.enumerated() {
            session.receive(packet(0xCC, [0x10, UInt8(index + 1), 6]), now: now)
            XCTAssertEqual(device.edifierANCIndex, 0x10)
            XCTAssertEqual(device.edifierNoiseValue, UInt8(index + 1))
            XCTAssertEqual(device.ancMode, mode)
        }
        session.receive(packet(0xCC, [0x10, 6, 6]), now: now)
        XCTAssertEqual(device.edifierNoiseValue, 5)
        session.receive(packet(0xCC, [0x99, 1, 6]), now: now)
        XCTAssertEqual(device.edifierANCIndex, 0x10)
    }

    func testFit900OffUsesValueFiveAndOmitsUnrequestedGain() {
        let device = device()
        let (session, now) = readySession(device)
        var sent: EdifierPacket?
        session.send = { sent = EdifierPacket.fromData($0); return true }
        session.setANC(.off, level: nil)
        session.tick(now: now + 0.2)
        XCTAssertEqual(sent?.data, Data([0x10, 5]))
        XCTAssertEqual(device.ancMode, .cancellation)
    }

    func testFit900TwoByteMusicGameSpatialResponses() {
        let device = device()
        let (session, now) = readySession(device)
        for scene in EdifierScene.allCases {
            session.receive(packet(0x08, [scene.rawValue, 6]), now: now)
            XCTAssertEqual(device.edifierScene, scene)
            XCTAssertEqual(device.gameModeEnabled, scene == .game)
        }
        session.receive(packet(0x08, [255, 6]), now: now)
        XCTAssertEqual(device.edifierScene, .spatial)
        XCTAssertTrue(device.canControl(.sceneMode))
        session.send = { _ in true }
        session.setScene(.music)
        session.tick(now: now + 0.2)
        session.receive(packet(0x09, [1]), now: now + 0.3)
        XCTAssertEqual(device.edifierScene, .spatial)
        session.tick(now: now + 0.8)
        session.receive(packet(0x08, [0, 6]), now: now + 0.9)
        XCTAssertEqual(device.edifierScene, .music)
        XCTAssertTrue(device.pendingFeatures.isEmpty)
    }

    func testFit900DoesNotExposeUnverifiedEqualizer() {
        let device = device()
        let (session, now) = readySession(device)
        var sent = false
        session.send = { _ in sent = true; return true }
        session.receive(packet(0xD5, [0]), now: now)
        session.setEqualizer(.bass)
        XCTAssertNil(device.equalizerPreset)
        XCTAssertFalse(device.canControl(.equalizer))
        XCTAssertFalse(sent)
    }

    func testReturningToANCUsesLastConfirmedStrengthWithoutOptimisticSelection() {
        let device = device()
        let (session, now) = readySession(device)
        session.receive(packet(0xCC, [0x10, 3, 6]), now: now) // Wind reduction confirmed.
        session.receive(packet(0xCC, [0x10, 5, 6]), now: now) // Switched off on the headset.
        XCTAssertEqual(device.edifierCancellationSelection?.index, 0x10)
        XCTAssertEqual(device.edifierCancellationSelection?.value, 3)
        var sent: EdifierPacket?
        session.send = { sent = EdifierPacket.fromData($0); return true }
        session.setANC(.cancellation, level: nil)
        session.tick(now: now + 0.2)
        XCTAssertEqual(sent?.data, Data([0x10, 3]))
        XCTAssertEqual(device.ancMode, .off)
        XCTAssertEqual(device.edifierNoiseValue, 5)
        XCTAssertTrue(device.pendingFeatures.contains(.noiseControl))
    }

}

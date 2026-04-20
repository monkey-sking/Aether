import XCTest
import simd
@testable import RemoteProtocol

final class PacketRoundtripTests: XCTestCase {

    // MARK: - Helpers

    private func roundtrip(_ packet: Packet, file: StaticString = #filePath, line: UInt = #line) throws -> Packet {
        let data = try packet.encode()
        return try Packet.decode(from: data)
    }

    private func assertRoundtrip(_ packet: Packet, file: StaticString = #filePath, line: UInt = #line) throws {
        let decoded = try roundtrip(packet)
        XCTAssertEqual(decoded, packet, file: file, line: line)
    }

    // MARK: - Cases

    func testHelloRoundtrip() throws {
        let packet = Packet.hello(Hello(
            protocolVersion: protocolVersion,
            appVersion: "0.1.0",
            deviceName: "runking's iPhone",
            pairingCode: "123456",
            capabilities: [.arWorldTracking, .textInput, .pttButton]
        ))
        try assertRoundtrip(packet)
    }

    func testHelloRoundtripWithoutPairingCode() throws {
        let packet = Packet.hello(Hello(
            protocolVersion: protocolVersion,
            appVersion: "0.1.0",
            deviceName: "runking's iPhone",
            pairingCode: nil,
            capabilities: [.gyroFallback]
        ))
        try assertRoundtrip(packet)
    }

    func testHelloAckRoundtrip() throws {
        let packet = Packet.helloAck(HelloAck(
            protocolVersion: protocolVersion,
            macLicenseStatus: .trial,
            displays: [
                DisplayInfo(displayID: 1, pixelSize: SIMD2<Float>(3456, 2234), calibrated: true),
                DisplayInfo(displayID: 2, pixelSize: SIMD2<Float>(1920, 1080), calibrated: false)
            ]
        ))
        try assertRoundtrip(packet)
    }

    func testMotionRoundtrip() throws {
        let orientation = simd_quatf(angle: .pi / 4, axis: SIMD3<Float>(0, 1, 0))
        let packet = Packet.motion(MotionFrame(
            timestamp: 12345.6789,
            position: SIMD3<Float>(0.12, -0.34, 0.56),
            orientation: orientation,
            trackingState: .normal
        ))
        let decoded = try roundtrip(packet)
        XCTAssertEqual(decoded, packet)

        guard case let .motion(frame) = decoded else { XCTFail("expected motion"); return }
        XCTAssertEqual(frame.orientation.simd.vector.w, orientation.vector.w, accuracy: 1e-6)
    }

    func testButtonRoundtrip() throws {
        try assertRoundtrip(.button(ButtonEvent(kind: .pttDown, timestamp: 1)))
        try assertRoundtrip(.button(ButtonEvent(kind: .pttUp, timestamp: 2)))
        try assertRoundtrip(.button(ButtonEvent(kind: .tap, timestamp: 3)))
        try assertRoundtrip(.button(ButtonEvent(kind: .doubleTap, timestamp: 4)))
    }

    func testTextPartialRoundtrip() throws {
        let packet = Packet.textPartial(TextPayload(
            utteranceID: UUID(uuidString: "DEADBEEF-0000-0000-0000-000000000001")!,
            text: "你好 world",
            timestamp: 42
        ))
        try assertRoundtrip(packet)
    }

    func testTextFinalRoundtrip() throws {
        let packet = Packet.textFinal(TextPayload(
            utteranceID: UUID(),
            text: "final text",
            timestamp: 42
        ))
        try assertRoundtrip(packet)
    }

    func testCalibrationCueRoundtrip() throws {
        let packet = Packet.calibrationCue(CalibrationCue(
            displayID: 1,
            marker: .topLeft,
            displayPixelSize: SIMD2<Float>(3456, 2234)
        ))
        try assertRoundtrip(packet)
    }

    func testCalibrationSampleRoundtrip() throws {
        let packet = Packet.calibrationSample(CalibrationSample(
            displayID: 1,
            marker: .center,
            position: SIMD3<Float>(1, 2, 3),
            orientation: simd_quatf(angle: .pi / 3, axis: SIMD3<Float>(1, 0, 0)),
            timestamp: 100
        ))
        try assertRoundtrip(packet)
    }

    func testHeartbeatRoundtrip() throws {
        try assertRoundtrip(.heartbeat(Heartbeat(timestamp: 99)))
    }

    func testErrorRoundtrip() throws {
        try assertRoundtrip(.error(ErrorPayload(code: .incompatibleVersion, message: "expected 1")))
        try assertRoundtrip(.error(ErrorPayload(code: .pairingRejected, message: nil)))
    }

    // MARK: - Wire size

    /// Motion frames are sent at 60 Hz over MPC unreliable channel. Budget: < 256 bytes.
    /// Raw payload is ~37 bytes; binary-plist overhead (field names, type tags, offset
    /// table) roughly triples that. If we ever need to shrink further (bandwidth-
    /// constrained MPC networks), revisit by hand-writing a packed binary encoder.
    func testMotionFrameWireSize() throws {
        let orientation = simd_quatf(angle: .pi / 4, axis: SIMD3<Float>(0, 1, 0))
        let packet = Packet.motion(MotionFrame(
            timestamp: 12345.6789,
            position: SIMD3<Float>(0.12, -0.34, 0.56),
            orientation: orientation,
            trackingState: .normal
        ))
        let data = try packet.encode()
        XCTAssertLessThan(
            data.count,
            256,
            "motion packet \(data.count) bytes exceeds 256-byte budget"
        )
    }

    // MARK: - Corrupted data

    func testDecodeEmptyDataThrows() {
        XCTAssertThrowsError(try Packet.decode(from: Data())) { error in
            guard case PacketDecodingError.empty = error else {
                XCTFail("expected .empty, got \(error)")
                return
            }
        }
    }

    func testDecodeCorruptedDataThrows() {
        let garbage = Data([0x00, 0x01, 0x02, 0x03, 0x04])
        XCTAssertThrowsError(try Packet.decode(from: garbage)) { error in
            guard case PacketDecodingError.corrupted = error else {
                XCTFail("expected .corrupted, got \(error)")
                return
            }
        }
    }
}

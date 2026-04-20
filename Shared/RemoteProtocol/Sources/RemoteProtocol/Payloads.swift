import Foundation
import simd

/// Codable wrapper around `simd_quatf` so payloads containing quaternions can be
/// (de)serialized across the wire. `simd_quatf` has no synthesized Codable.
public struct Quaternion: Codable, Sendable, Equatable {
    public var x: Float
    public var y: Float
    public var z: Float
    public var w: Float

    public init(x: Float, y: Float, z: Float, w: Float) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }

    public init(_ q: simd_quatf) {
        let v = q.vector
        self.init(x: v.x, y: v.y, z: v.z, w: v.w)
    }

    public var simd: simd_quatf {
        simd_quatf(vector: SIMD4<Float>(x, y, z, w))
    }
}

public enum Capability: String, Codable, Sendable, CaseIterable {
    case arWorldTracking
    case gyroFallback
    case textInput
    case pttButton
}

public enum LicenseStatus: String, Codable, Sendable {
    case active
    case trial
    case expired
}

public enum TrackingState: UInt8, Codable, Sendable {
    case notAvailable = 0
    case limited = 1
    case normal = 2
}

public struct Hello: Codable, Sendable, Equatable {
    public let protocolVersion: UInt16
    public let appVersion: String
    public let deviceName: String
    /// Only present on first pairing; nil on reconnects.
    public let pairingCode: String?
    public let capabilities: Set<Capability>

    public init(
        protocolVersion: UInt16,
        appVersion: String,
        deviceName: String,
        pairingCode: String?,
        capabilities: Set<Capability>
    ) {
        self.protocolVersion = protocolVersion
        self.appVersion = appVersion
        self.deviceName = deviceName
        self.pairingCode = pairingCode
        self.capabilities = capabilities
    }
}

public struct DisplayInfo: Codable, Sendable, Equatable {
    /// Mirrors `CGDirectDisplayID` on macOS.
    public let displayID: UInt32
    public let pixelSize: SIMD2<Float>
    public let calibrated: Bool

    public init(displayID: UInt32, pixelSize: SIMD2<Float>, calibrated: Bool) {
        self.displayID = displayID
        self.pixelSize = pixelSize
        self.calibrated = calibrated
    }
}

public struct HelloAck: Codable, Sendable, Equatable {
    public let protocolVersion: UInt16
    public let macLicenseStatus: LicenseStatus
    public let displays: [DisplayInfo]

    public init(
        protocolVersion: UInt16,
        macLicenseStatus: LicenseStatus,
        displays: [DisplayInfo]
    ) {
        self.protocolVersion = protocolVersion
        self.macLicenseStatus = macLicenseStatus
        self.displays = displays
    }
}

/// 60 Hz unreliable motion frame. Kept small — target < 120 bytes on the wire.
public struct MotionFrame: Codable, Sendable, Equatable {
    public let timestamp: TimeInterval
    /// ARKit world-space meters.
    public let position: SIMD3<Float>
    /// ARKit world-space orientation.
    public let orientation: Quaternion
    public let trackingState: TrackingState

    public init(
        timestamp: TimeInterval,
        position: SIMD3<Float>,
        orientation: simd_quatf,
        trackingState: TrackingState
    ) {
        self.timestamp = timestamp
        self.position = position
        self.orientation = Quaternion(orientation)
        self.trackingState = trackingState
    }

    public init(
        timestamp: TimeInterval,
        position: SIMD3<Float>,
        orientation: Quaternion,
        trackingState: TrackingState
    ) {
        self.timestamp = timestamp
        self.position = position
        self.orientation = orientation
        self.trackingState = trackingState
    }
}

public struct ButtonEvent: Codable, Sendable, Equatable {
    public enum Kind: UInt8, Codable, Sendable {
        case pttDown
        case pttUp
        case tap
        case doubleTap
    }

    public let kind: Kind
    public let timestamp: TimeInterval

    public init(kind: Kind, timestamp: TimeInterval) {
        self.kind = kind
        self.timestamp = timestamp
    }
}

public struct TextPayload: Codable, Sendable, Equatable {
    /// Identifies one logical utterance so partial and final chunks can be correlated.
    public let utteranceID: UUID
    /// For partials this is the cumulative text so far, not a delta.
    public let text: String
    public let timestamp: TimeInterval

    public init(utteranceID: UUID, text: String, timestamp: TimeInterval) {
        self.utteranceID = utteranceID
        self.text = text
        self.timestamp = timestamp
    }
}

public enum CalibrationMarker: UInt8, Codable, Sendable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case center
}

public struct CalibrationCue: Codable, Sendable, Equatable {
    public let displayID: UInt32
    public let marker: CalibrationMarker
    public let displayPixelSize: SIMD2<Float>

    public init(displayID: UInt32, marker: CalibrationMarker, displayPixelSize: SIMD2<Float>) {
        self.displayID = displayID
        self.marker = marker
        self.displayPixelSize = displayPixelSize
    }
}

public struct CalibrationSample: Codable, Sendable, Equatable {
    public let displayID: UInt32
    public let marker: CalibrationMarker
    public let position: SIMD3<Float>
    public let orientation: Quaternion
    public let timestamp: TimeInterval

    public init(
        displayID: UInt32,
        marker: CalibrationMarker,
        position: SIMD3<Float>,
        orientation: simd_quatf,
        timestamp: TimeInterval
    ) {
        self.displayID = displayID
        self.marker = marker
        self.position = position
        self.orientation = Quaternion(orientation)
        self.timestamp = timestamp
    }

    public init(
        displayID: UInt32,
        marker: CalibrationMarker,
        position: SIMD3<Float>,
        orientation: Quaternion,
        timestamp: TimeInterval
    ) {
        self.displayID = displayID
        self.marker = marker
        self.position = position
        self.orientation = orientation
        self.timestamp = timestamp
    }
}

public struct Heartbeat: Codable, Sendable, Equatable {
    public let timestamp: TimeInterval

    public init(timestamp: TimeInterval) {
        self.timestamp = timestamp
    }
}

public struct ErrorPayload: Codable, Sendable, Equatable {
    public enum Code: UInt8, Codable, Sendable {
        case incompatibleVersion
        case macNotActivated
        case pairingRejected
        case calibrationTimeout
        case internalError
    }

    public let code: Code
    public let message: String?

    public init(code: Code, message: String?) {
        self.code = code
        self.message = message
    }
}

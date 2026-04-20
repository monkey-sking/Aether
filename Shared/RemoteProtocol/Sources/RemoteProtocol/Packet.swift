import Foundation

public enum Packet: Codable, Sendable, Equatable {
    case hello(Hello)
    case helloAck(HelloAck)
    case motion(MotionFrame)
    case button(ButtonEvent)
    case textPartial(TextPayload)
    case textFinal(TextPayload)
    case calibrationCue(CalibrationCue)
    case calibrationSample(CalibrationSample)
    case heartbeat(Heartbeat)
    case error(ErrorPayload)
}

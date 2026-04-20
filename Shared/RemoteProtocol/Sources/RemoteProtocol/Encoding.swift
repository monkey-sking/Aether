import Foundation

public enum PacketDecodingError: Error, Sendable {
    case empty
    case corrupted(underlying: Error)
}

extension Packet {
    /// Binary plist encoding. Compact on the wire for motion-frame frequency.
    public func encode() throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(self)
    }

    public static func decode(from data: Data) throws -> Packet {
        guard !data.isEmpty else { throw PacketDecodingError.empty }
        do {
            return try PropertyListDecoder().decode(Packet.self, from: data)
        } catch {
            throw PacketDecodingError.corrupted(underlying: error)
        }
    }
}

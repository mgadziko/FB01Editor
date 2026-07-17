import Foundation

public struct FB01VoiceData: Equatable, Sendable {
    public static let byteCount = 64

    public var bytes: [UInt8]

    public init(bytes: [UInt8]) throws {
        guard bytes.count == Self.byteCount else {
            throw FB01SysExError.invalidPayloadLength(expected: Self.byteCount, actual: bytes.count)
        }
        self.bytes = try bytes.map { try FB01.validateByte($0) }
    }

    public var nibbleEncodedBytes: [UInt8] {
        FB01.nibbleEncode(bytes)
    }
}

public struct FB01ConfigurationData: Equatable, Sendable {
    public var bytes: [UInt8]

    public init(bytes: [UInt8]) throws {
        self.bytes = try bytes.map { try FB01.validateSevenBit($0) }
    }
}

public struct FB01BulkPacket: Equatable, Sendable {
    public var payload: [UInt8]
    public var checksum: UInt8

    public init(payload: [UInt8]) throws {
        self.payload = try payload.map { try FB01.validateSevenBit($0) }
        self.checksum = FB01.checksum(for: self.payload)
    }

    public init(payload: [UInt8], checksum: UInt8) throws {
        self.payload = try payload.map { try FB01.validateSevenBit($0) }
        self.checksum = try FB01.validateSevenBit(checksum)
        guard FB01.checksum(for: self.payload) == self.checksum else {
            throw FB01SysExError.checksumMismatch(expected: FB01.checksum(for: self.payload), actual: self.checksum)
        }
    }
}

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
    public static let byteCount = 160
    public static let instrumentCount = 8
    public static let instrumentBlockByteCount = 16

    public var bytes: [UInt8]

    public init(bytes: [UInt8]) throws {
        guard bytes.count == Self.byteCount else {
            throw FB01SysExError.invalidPayloadLength(expected: Self.byteCount, actual: bytes.count)
        }
        self.bytes = try bytes.map { try FB01.validateSevenBit($0) }
    }

    public var name: String {
        let nameBytes = bytes.prefix(8).filter { $0 != 0 }
        return String(bytes: nameBytes, encoding: .ascii)?
            .trimmingCharacters(in: .whitespaces)
            ?? ""
    }

    public var combineModeEnabled: Bool {
        bytes[0x08] & 0x01 == 0x01
    }

    public var lfoSpeed: Int {
        Int(bytes[0x09])
    }

    public var amplitudeModulationDepth: Int {
        Int(bytes[0x0A])
    }

    public var pitchModulationDepth: Int {
        Int(bytes[0x0B])
    }

    public var lfoWaveform: Int {
        Int(bytes[0x0C] & 0x03)
    }

    public var keyCodeReceiveMode: FB01KeyCodeReceiveMode {
        FB01KeyCodeReceiveMode(rawValue: bytes[0x0D] & 0x03) ?? .unknown
    }

    public var instruments: [FB01InstrumentConfiguration] {
        (0..<Self.instrumentCount).map { index in
            let offset = 0x20 + index * Self.instrumentBlockByteCount
            return FB01InstrumentConfiguration(index: index, bytes: Array(bytes[offset..<(offset + Self.instrumentBlockByteCount)]))
        }
    }
}

public enum FB01KeyCodeReceiveMode: UInt8, Equatable, Sendable {
    case all = 0
    case even = 1
    case odd = 2
    case unknown = 0x7F
}

public enum FB01MonoPolyMode: UInt8, Equatable, Sendable {
    case poly = 0
    case mono = 1
    case unknown = 0x7F
}

public enum FB01PMDControllerAssignment: UInt8, Equatable, Sendable {
    case notAssigned = 0
    case afterTouch = 1
    case modulationWheel = 2
    case breathController = 3
    case footController = 4
    case unknown = 0x7F
}

public struct FB01InstrumentConfiguration: Equatable, Sendable {
    public var index: Int
    public var bytes: [UInt8]

    public var noteCount: Int { Int(bytes[0x00]) }
    public var midiChannel: Int { Int(bytes[0x01]) }
    public var highKeyLimit: Int { Int(bytes[0x02]) }
    public var lowKeyLimit: Int { Int(bytes[0x03]) }
    public var voiceBank: Int { Int(bytes[0x04]) }
    public var voiceNumber: Int { Int(bytes[0x05]) }
    public var detune: Int { Int(Int8(bitPattern: bytes[0x06])) }
    public var octaveTransposeRaw: Int { Int(bytes[0x07]) }
    public var octaveTranspose: Int { octaveTransposeRaw - 2 }
    public var outputLevel: Int { Int(bytes[0x08]) }
    public var pan: Int { Int(bytes[0x09]) }
    public var lfoEnabled: Bool { bytes[0x0A] & 0x01 == 0x01 }
    public var portamentoTime: Int { Int(bytes[0x0B]) }
    public var pitchBendRange: Int { Int(bytes[0x0C]) }
    public var monoPolyMode: FB01MonoPolyMode {
        FB01MonoPolyMode(rawValue: bytes[0x0D] & 0x01) ?? .unknown
    }
    public var pmdControllerAssignment: FB01PMDControllerAssignment {
        FB01PMDControllerAssignment(rawValue: bytes[0x0E]) ?? .unknown
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

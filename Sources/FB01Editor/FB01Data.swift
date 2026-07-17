import Foundation

public struct FB01VoiceData: Equatable, Sendable {
    public static let byteCount = 64
    public static let nameLength = 7
    public static let operatorCount = 4
    public static let operatorBlockByteCount = 8

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

    public func instrumentVoiceArtifact(systemChannel: Int = 0, instrument: Int = 0) throws -> FB01Artifact {
        let packet = try FB01SysExPacket(payload: nibbleEncodedBytes)
        return FB01Artifact(message: .instrumentVoiceDump(systemChannel: systemChannel, instrument: instrument, packet: packet))
    }

    public func settingName(_ name: String) throws -> FB01VoiceData {
        var copy = bytes
        let allowed = name.prefix(Self.nameLength).map { character -> UInt8 in
            guard character.unicodeScalars.count == 1,
                  let scalar = character.unicodeScalars.first,
                  scalar.isASCII,
                  (0x20...0x7E).contains(UInt8(scalar.value)) else {
                return 0x20
            }
            return UInt8(scalar.value)
        }
        copy.replaceSubrange(0..<Self.nameLength, with: allowed + Array(repeating: 0x20, count: Self.nameLength - allowed.count))
        return try FB01VoiceData(bytes: copy)
    }

    public func settingLFOSpeed(_ value: Int) throws -> FB01VoiceData {
        try settingByte(at: 0x08, value: value, name: "lfoSpeed", range: 0...255)
    }

    public func settingFeedbackLevel(_ value: Int) throws -> FB01VoiceData {
        let feedback = try FB01.validate(value, name: "feedbackLevel", range: 0...7)
        var copy = bytes
        copy[0x0C] = (copy[0x0C] & 0xC7) | (feedback << 3)
        return try FB01VoiceData(bytes: copy)
    }

    public func settingAlgorithm(_ value: Int) throws -> FB01VoiceData {
        let algorithm = try FB01.validate(value, name: "algorithm", range: 0...7)
        var copy = bytes
        copy[0x0C] = (copy[0x0C] & 0xF8) | algorithm
        return try FB01VoiceData(bytes: copy)
    }

    public var name: String {
        String(bytes: bytes.prefix(Self.nameLength), encoding: .ascii)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
    }

    public var userCode: Int { Int(bytes[0x07]) }
    public var lfoSpeed: Int { Int(bytes[0x08]) }
    public var loadLFODataEnabled: Bool { bytes[0x09] & 0x80 == 0x80 }
    public var amplitudeModulationDepth: Int { Int(bytes[0x09] & 0x7F) }
    public var lfoSyncEnabled: Bool { bytes[0x0A] & 0x80 == 0x80 }
    public var pitchModulationDepth: Int { Int(bytes[0x0A] & 0x7F) }
    public var operatorEnabled: [Bool] {
        (0..<Self.operatorCount).map { index in
            bytes[0x0B] & (1 << (index + 3)) != 0
        }
    }
    public var leftOutputEnabled: Bool { bytes[0x0C] & 0x80 == 0x80 }
    public var rightOutputEnabled: Bool { bytes[0x0C] & 0x40 == 0x40 }
    public var feedbackLevel: Int { Int((bytes[0x0C] >> 3) & 0x07) }
    public var algorithm: Int { Int(bytes[0x0C] & 0x07) }
    public var pitchModulationSensitivity: Int { Int((bytes[0x0D] >> 4) & 0x07) }
    public var amplitudeModulationSensitivity: Int { Int(bytes[0x0D] & 0x03) }
    public var lfoWaveform: Int { Int((bytes[0x0E] >> 5) & 0x03) }
    public var transpose: Int { Int(Int8(bitPattern: bytes[0x0F])) }
    public var operators: [FB01VoiceOperatorData] {
        (0..<Self.operatorCount).map { index in
            let offset = 0x10 + index * Self.operatorBlockByteCount
            return FB01VoiceOperatorData(index: index, bytes: Array(bytes[offset..<(offset + Self.operatorBlockByteCount)]))
        }
    }

    private func settingByte(at offset: Int, value: Int, name: String, range: ClosedRange<Int>) throws -> FB01VoiceData {
        var copy = bytes
        copy[offset] = try FB01.validate(value, name: name, range: range)
        return try FB01VoiceData(bytes: copy)
    }
}

public struct FB01VoiceSummary: Equatable, Identifiable, Sendable {
    public var id: Int { number }
    public var number: Int
    public var voice: FB01VoiceData
    public var encodedRecordBytes: [UInt8]

    public init(number: Int, voice: FB01VoiceData, encodedRecordBytes: [UInt8]) {
        self.number = number
        self.voice = voice
        self.encodedRecordBytes = encodedRecordBytes
    }

    public var name: String { voice.name }
}

public struct FB01VoiceOperatorData: Equatable, Sendable {
    public var index: Int
    public var bytes: [UInt8]

    public var totalLevel: Int { Int(bytes[0x00] & 0x7F) }
    public var keyboardLevelScalingTypeBit0: Bool { bytes[0x01] & 0x80 == 0x80 }
    public var velocitySensitivityForTotalLevel: Int { Int((bytes[0x01] >> 4) & 0x07) }
    public var keyboardLevelScalingDepth: Int { Int((bytes[0x02] >> 4) & 0x0F) }
    public var totalLevelAdjust: Int { Int(bytes[0x02] & 0x0F) }
    public var keyboardLevelScalingTypeBit1: Bool { bytes[0x03] & 0x80 == 0x80 }
    public var detune1: Int { Int((bytes[0x03] >> 4) & 0x07) }
    public var multiple: Int { Int(bytes[0x03] & 0x0F) }
    public var keyboardRateScalingDepth: Int { Int((bytes[0x04] >> 5) & 0x07) }
    public var attackRate: Int { Int(bytes[0x04] & 0x1F) }
    public var carrier: Bool { bytes[0x05] & 0x80 == 0x80 }
    public var velocitySensitivityForAttackRate: Int { Int((bytes[0x05] >> 4) & 0x07) }
    public var decay1Rate: Int { Int(bytes[0x05] & 0x0F) }
    public var detune2: Int { Int((bytes[0x06] >> 5) & 0x03) }
    public var decay2Rate: Int { Int(bytes[0x06] & 0x1F) }
    public var sustainLevel: Int { Int((bytes[0x07] >> 4) & 0x0F) }
    public var releaseRate: Int { Int(bytes[0x07] & 0x0F) }
}

public struct FB01VoiceBankData: Equatable, Sendable {
    public static let voiceCount = 48
    public static let bankHeaderByteCount = 64
    public static let encodedRecordByteCount = 131
    public static let encodedRecordPrefixByteCount = 3

    public var bank: Int
    public var data: [UInt8]

    public init(bank: Int, data: [UInt8]) throws {
        guard (0...6).contains(bank) else {
            throw FB01SysExError.valueOutOfRange(name: "voiceBank", value: bank, range: 0...6)
        }

        self.bank = bank
        self.data = try data.map { try FB01.validateSevenBit($0) }

        let expectedLength = Self.bankHeaderByteCount + Self.voiceCount * Self.encodedRecordByteCount
        guard self.data.count == expectedLength else {
            throw FB01SysExError.invalidPayloadLength(expected: expectedLength, actual: self.data.count)
        }

        for index in 0..<Self.voiceCount {
            let recordStart = Self.bankHeaderByteCount + index * Self.encodedRecordByteCount
            let recordEnd = recordStart + Self.encodedRecordByteCount
            _ = try Self.decodeVoiceRecord(Array(self.data[recordStart..<recordEnd]))
        }
    }

    public var headerBytes: [UInt8] {
        Array(data.prefix(Self.bankHeaderByteCount))
    }

    public var voices: [FB01VoiceSummary] {
        (0..<Self.voiceCount).map { index in
            let recordStart = Self.bankHeaderByteCount + index * Self.encodedRecordByteCount
            let recordEnd = recordStart + Self.encodedRecordByteCount
            let encodedRecordBytes = Array(data[recordStart..<recordEnd])
            let voice = try! Self.decodeVoiceRecord(encodedRecordBytes)
            return FB01VoiceSummary(
                number: index + 1,
                voice: voice,
                encodedRecordBytes: encodedRecordBytes
            )
        }
    }

    public func replacingVoices(_ editedVoices: [Int: FB01VoiceData]) throws -> FB01VoiceBankData {
        var editedData = data

        for (number, voice) in editedVoices {
            guard (1...Self.voiceCount).contains(number) else {
                throw FB01SysExError.valueOutOfRange(name: "voiceNumber", value: number, range: 1...Self.voiceCount)
            }

            let recordStart = Self.bankHeaderByteCount + (number - 1) * Self.encodedRecordByteCount
            let nibbleStart = recordStart + Self.encodedRecordPrefixByteCount
            let nibbleEnd = recordStart + Self.encodedRecordByteCount
            editedData.replaceSubrange(nibbleStart..<nibbleEnd, with: voice.nibbleEncodedBytes)
        }

        return try FB01VoiceBankData(bank: bank, data: editedData)
    }

    private static func decodeVoiceRecord(_ encodedRecordBytes: [UInt8]) throws -> FB01VoiceData {
        guard encodedRecordBytes.count == Self.encodedRecordByteCount else {
            throw FB01SysExError.invalidPayloadLength(expected: Self.encodedRecordByteCount, actual: encodedRecordBytes.count)
        }

        let nibbleBytes = Array(encodedRecordBytes.dropFirst(Self.encodedRecordPrefixByteCount))
        return try FB01VoiceData(bytes: FB01.nibbleDecode(nibbleBytes))
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

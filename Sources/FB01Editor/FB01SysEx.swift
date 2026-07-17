import Foundation

public enum FB01SysExError: Error, Equatable, Sendable {
    case valueOutOfRange(name: String, value: Int, range: ClosedRange<Int>)
    case invalidPayloadLength(expected: Int, actual: Int)
    case invalidSysEx
    case unsupportedSysEx
    case checksumMismatch(expected: UInt8, actual: UInt8)
}

public enum FB01 {
    public static let start: UInt8 = 0xF0
    public static let yamahaID: UInt8 = 0x43
    public static let fb01Substatus: UInt8 = 0x75
    public static let parameterGroup: UInt8 = 0x15
    public static let end: UInt8 = 0xF7

    public static func validateSystemChannel(_ value: Int) throws -> UInt8 {
        try validate(value, name: "systemChannel", range: 0...15)
    }

    public static func validateMIDIChannel(_ value: Int) throws -> UInt8 {
        try validate(value, name: "midiChannel", range: 0...15)
    }

    public static func validateInstrument(_ value: Int) throws -> UInt8 {
        try validate(value, name: "instrument", range: 0...7)
    }

    public static func validateVoiceBank(_ value: Int) throws -> UInt8 {
        try validate(value, name: "voiceBank", range: 1...7)
    }

    public static func validateVoiceNumber(_ value: Int) throws -> UInt8 {
        try validate(value, name: "voiceNumber", range: 0...95)
    }

    public static func validateConfigurationNumber(_ value: Int) throws -> UInt8 {
        try validate(value, name: "configurationNumber", range: 0...19)
    }

    public static func validateParameter(_ value: Int) throws -> UInt8 {
        try validate(value, name: "parameter", range: 0...127)
    }

    public static func validateSevenBit(_ value: UInt8) throws -> UInt8 {
        guard value <= 0x7F else {
            throw FB01SysExError.valueOutOfRange(name: "sevenBitByte", value: Int(value), range: 0...127)
        }
        return value
    }

    public static func validateByte(_ value: UInt8) throws -> UInt8 {
        value
    }

    public static func checksum(for bytes: [UInt8]) -> UInt8 {
        let sum = bytes.reduce(0) { ($0 + Int($1)) & 0x7F }
        return UInt8((0x80 - sum) & 0x7F)
    }

    public static func nibbleEncode(_ bytes: [UInt8]) -> [UInt8] {
        bytes.flatMap { [$0 & 0x0F, ($0 >> 4) & 0x0F] }
    }

    public static func nibbleDecode(_ bytes: [UInt8]) throws -> [UInt8] {
        guard bytes.count.isMultiple(of: 2) else {
            throw FB01SysExError.invalidPayloadLength(expected: bytes.count + 1, actual: bytes.count)
        }

        var decoded: [UInt8] = []
        decoded.reserveCapacity(bytes.count / 2)

        var index = bytes.startIndex
        while index < bytes.endIndex {
            let low = try validate(Int(bytes[index]), name: "lowNibble", range: 0...15)
            let high = try validate(Int(bytes[bytes.index(after: index)]), name: "highNibble", range: 0...15)
            decoded.append(low | (high << 4))
            index = bytes.index(index, offsetBy: 2)
        }

        return decoded
    }

    public static func validateSysExEnvelope(_ bytes: [UInt8]) throws {
        guard bytes.first == start, bytes.last == end, bytes.count >= 4, bytes[1] == yamahaID else {
            throw FB01SysExError.invalidSysEx
        }
    }

    public static func packetByteCount(high: UInt8, low: UInt8) throws -> Int {
        let high = try validateSevenBit(high)
        let low = try validateSevenBit(low)
        return Int(high) * 128 + Int(low)
    }

    public static func byteCountPair(for count: Int) throws -> (high: UInt8, low: UInt8) {
        guard (0...16_383).contains(count) else {
            throw FB01SysExError.valueOutOfRange(name: "byteCount", value: count, range: 0...16_383)
        }
        return (UInt8(count / 128), UInt8(count % 128))
    }

    private static func validate(_ value: Int, name: String, range: ClosedRange<Int>) throws -> UInt8 {
        guard range.contains(value) else {
            throw FB01SysExError.valueOutOfRange(name: name, value: value, range: range)
        }
        return UInt8(value)
    }
}

public enum FB01ParameterValue: Equatable, Sendable {
    case oneByte(UInt8)
    case twoByte(UInt8)

    public var bytes: [UInt8] {
        switch self {
        case .oneByte(let value):
            [value & 0x7F]
        case .twoByte(let value):
            [value & 0x0F, (value >> 4) & 0x0F]
        }
    }
}

public enum FB01Command: Equatable, Sendable {
    case instrumentParameterChange(systemChannel: Int, instrument: Int, parameter: Int, value: FB01ParameterValue)
    case midiChannelParameterChange(midiChannel: Int, parameter: Int, value: FB01ParameterValue)
    case systemParameterChange(systemChannel: Int, parameter: Int, value: UInt8)
    case requestInstrumentVoice(systemChannel: Int, instrument: Int)
    case storeCurrentInstrumentVoice(systemChannel: Int, instrument: Int, voiceNumber: Int)
    case requestVoiceRAM1(systemChannel: Int)
    case requestVoiceBank(systemChannel: Int, bank: Int)
    case requestCurrentConfiguration(systemChannel: Int)
    case requestConfiguration(systemChannel: Int, number: Int)
    case requestAllConfigurations(systemChannel: Int)
    case requestUnitID(systemChannel: Int)
    case storeCurrentConfiguration(systemChannel: Int, number: Int)

    public var bytes: [UInt8] {
        get throws {
            switch self {
            case let .instrumentParameterChange(systemChannel, instrument, parameter, value):
                let system = try FB01.validateSystemChannel(systemChannel)
                let inst = try FB01.validateInstrument(instrument)
                let param = try FB01.validateParameter(parameter)
                let encodedParameter = try parameterByte(param, value: value)
                let valueBytes = try validatedValueBytes(value)
                return envelope([FB01.fb01Substatus, system, 0x18 | inst, encodedParameter] + valueBytes)

            case let .midiChannelParameterChange(midiChannel, parameter, value):
                let channel = try FB01.validateMIDIChannel(midiChannel)
                let param = try FB01.validateParameter(parameter)
                let encodedParameter = try parameterByte(param, value: value)
                let valueBytes = try validatedValueBytes(value)
                return envelope([0x10 | channel, FB01.parameterGroup, encodedParameter] + valueBytes, includesFB01Substatus: false)

            case let .systemParameterChange(systemChannel, parameter, value):
                let system = try FB01.validateSystemChannel(systemChannel)
                let param = try FB01.validateParameter(parameter)
                let data = try FB01.validateSevenBit(value)
                return envelope([FB01.fb01Substatus, system, 0x10, param, data])

            case let .requestInstrumentVoice(systemChannel, instrument):
                let system = try FB01.validateSystemChannel(systemChannel)
                let inst = try FB01.validateInstrument(instrument)
                return envelope([FB01.fb01Substatus, system, 0x28 | inst, 0x40, 0x00])

            case let .storeCurrentInstrumentVoice(systemChannel, instrument, voiceNumber):
                let system = try FB01.validateSystemChannel(systemChannel)
                let inst = try FB01.validateInstrument(instrument)
                let voice = try FB01.validateVoiceNumber(voiceNumber)
                return envelope([FB01.fb01Substatus, system, 0x28 | inst, 0x00, voice])

            case let .requestVoiceRAM1(systemChannel):
                let system = try FB01.validateSystemChannel(systemChannel)
                return envelope([0x20 | system, 0x0C], includesFB01Substatus: false)

            case let .requestVoiceBank(systemChannel, bank):
                let system = try FB01.validateSystemChannel(systemChannel)
                let bank = try FB01.validateVoiceBank(bank)
                return envelope([FB01.fb01Substatus, system, 0x20, 0x00, bank])

            case let .requestCurrentConfiguration(systemChannel):
                let system = try FB01.validateSystemChannel(systemChannel)
                return envelope([FB01.fb01Substatus, system, 0x20, 0x01, 0x00])

            case let .requestConfiguration(systemChannel, number):
                let system = try FB01.validateSystemChannel(systemChannel)
                let config = try FB01.validateConfigurationNumber(number)
                return envelope([FB01.fb01Substatus, system, 0x20, 0x02, config])

            case let .requestAllConfigurations(systemChannel):
                let system = try FB01.validateSystemChannel(systemChannel)
                return envelope([FB01.fb01Substatus, system, 0x20, 0x03, 0x00])

            case let .requestUnitID(systemChannel):
                let system = try FB01.validateSystemChannel(systemChannel)
                return envelope([FB01.fb01Substatus, system, 0x20, 0x04, 0x00])

            case let .storeCurrentConfiguration(systemChannel, number):
                let system = try FB01.validateSystemChannel(systemChannel)
                let config = try FB01.validateConfigurationNumber(number)
                return envelope([FB01.fb01Substatus, system, 0x20, 0x40, config])
            }
        }
    }

    private func envelope(_ body: [UInt8], includesFB01Substatus _: Bool = true) -> [UInt8] {
        [FB01.start, FB01.yamahaID] + body + [FB01.end]
    }

    private func parameterByte(_ parameter: UInt8, value: FB01ParameterValue) throws -> UInt8 {
        switch value {
        case .oneByte:
            guard parameter <= 0x3F else {
                throw FB01SysExError.valueOutOfRange(name: "oneByteParameter", value: Int(parameter), range: 0...63)
            }
            return parameter
        case .twoByte:
            guard (0x40...0x7F).contains(parameter) else {
                throw FB01SysExError.valueOutOfRange(name: "twoByteParameter", value: Int(parameter), range: 64...127)
            }
            return parameter
        }
    }

    private func validatedValueBytes(_ value: FB01ParameterValue) throws -> [UInt8] {
        switch value {
        case .oneByte(let byte):
            [try FB01.validateSevenBit(byte)]
        case .twoByte:
            value.bytes
        }
    }
}

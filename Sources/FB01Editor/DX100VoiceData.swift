import Foundation

public enum DX100SysExError: Error, Equatable, CustomStringConvertible {
    case invalidByte(UInt8)
    case invalidChannel(Int)
    case invalidVoiceDataLength(expected: Int, actual: Int)
    case invalidSingleVoiceBulkLength(expected: Int, actual: Int)
    case invalidSingleVoiceBulkHeader
    case checksumMismatch(expected: UInt8, actual: UInt8)
    case operatorNumberOutOfRange(Int)

    public var description: String {
        switch self {
        case let .invalidByte(byte):
            "DX100 data bytes must be 7-bit, got 0x\(String(byte, radix: 16))"
        case let .invalidChannel(channel):
            "DX100 SysEx channel must be 0...15, got \(channel)"
        case let .invalidVoiceDataLength(expected, actual):
            "Invalid DX100 voice data length: expected \(expected), got \(actual)"
        case let .invalidSingleVoiceBulkLength(expected, actual):
            "Invalid DX100 single-voice bulk length: expected \(expected), got \(actual)"
        case .invalidSingleVoiceBulkHeader:
            "Invalid DX100 single-voice bulk header"
        case let .checksumMismatch(expected, actual):
            "Invalid DX100 checksum: expected 0x\(String(expected, radix: 16)), got 0x\(String(actual, radix: 16))"
        case let .operatorNumberOutOfRange(number):
            "DX100 operator number must be 1...4, got \(number)"
        }
    }
}

public enum DX100 {
    public static let start: UInt8 = 0xF0
    public static let end: UInt8 = 0xF7
    public static let yamahaID: UInt8 = 0x43
    public static let singleVoiceFormat: UInt8 = 0x03
    public static let singleVoiceByteCountMSB: UInt8 = 0x00
    public static let singleVoiceByteCountLSB: UInt8 = 0x5D

    public static func requestSingleVoiceBulk(channel: Int = 0) throws -> [UInt8] {
        guard (0...15).contains(channel) else {
            throw DX100SysExError.invalidChannel(channel)
        }
        return [start, yamahaID, 0x20 | UInt8(channel), singleVoiceFormat, end]
    }

    public static func checksum(for data: [UInt8]) -> UInt8 {
        let sum = data.reduce(0) { ($0 + Int($1)) & 0x7F }
        return UInt8((128 - sum) & 0x7F)
    }

    public static func validateDataByte(_ byte: UInt8) throws -> UInt8 {
        guard byte <= 0x7F else {
            throw DX100SysExError.invalidByte(byte)
        }
        return byte
    }
}

public struct DX100VoiceData: Equatable, Sendable {
    public static let byteCount = 93
    public static let nameLength = 10
    public static let operatorCount = 4
    public static let operatorBlockByteCount = 13
    public static let operatorNumbersInDataOrder = [4, 2, 3, 1]

    public var bytes: [UInt8]

    public init(bytes: [UInt8]) throws {
        guard bytes.count == Self.byteCount else {
            throw DX100SysExError.invalidVoiceDataLength(expected: Self.byteCount, actual: bytes.count)
        }
        self.bytes = try bytes.map { try DX100.validateDataByte($0) }
    }

    public init(singleVoiceBulkSysEx bytes: [UInt8]) throws {
        guard bytes.count == 101 else {
            throw DX100SysExError.invalidSingleVoiceBulkLength(expected: 101, actual: bytes.count)
        }
        guard bytes[0] == DX100.start,
              bytes[1] == DX100.yamahaID,
              (bytes[2] & 0xF0) == 0x00,
              bytes[3] == DX100.singleVoiceFormat,
              bytes[4] == DX100.singleVoiceByteCountMSB,
              bytes[5] == DX100.singleVoiceByteCountLSB,
              bytes[100] == DX100.end else {
            throw DX100SysExError.invalidSingleVoiceBulkHeader
        }

        let voiceBytes = Array(bytes[6..<99])
        let expectedChecksum = DX100.checksum(for: voiceBytes)
        let actualChecksum = bytes[99]
        guard actualChecksum == expectedChecksum else {
            throw DX100SysExError.checksumMismatch(expected: expectedChecksum, actual: actualChecksum)
        }

        try self.init(bytes: voiceBytes)
    }

    public func singleVoiceBulkSysEx(channel: Int = 0) throws -> [UInt8] {
        guard (0...15).contains(channel) else {
            throw DX100SysExError.invalidChannel(channel)
        }
        return [
            DX100.start,
            DX100.yamahaID,
            UInt8(channel),
            DX100.singleVoiceFormat,
            DX100.singleVoiceByteCountMSB,
            DX100.singleVoiceByteCountLSB,
        ] + bytes + [DX100.checksum(for: bytes), DX100.end]
    }

    public var name: String {
        String(bytes: bytes[77..<87], encoding: .ascii)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
    }

    public var algorithm: Int { Int(bytes[52]) }
    public var feedback: Int { Int(bytes[53]) }
    public var lfoSpeed: Int { Int(bytes[54]) }
    public var lfoDelay: Int { Int(bytes[55]) }
    public var pitchModulationDepth: Int { Int(bytes[56]) }
    public var amplitudeModulationDepth: Int { Int(bytes[57]) }
    public var lfoSyncEnabled: Bool { bytes[58] != 0 }
    public var lfoWaveform: Int { Int(bytes[59]) }
    public var pitchModulationSensitivity: Int { Int(bytes[60]) }
    public var amplitudeModulationSensitivity: Int { Int(bytes[61]) }
    public var transpose: Int { Int(bytes[62]) - 24 }
    public var playMode: Int { Int(bytes[63]) }
    public var pitchBendRange: Int { Int(bytes[64]) }
    public var portamentoMode: Int { Int(bytes[65]) }
    public var portamentoTime: Int { Int(bytes[66]) }
    public var footVolumeRange: Int { Int(bytes[67]) }
    public var sustainFootSwitchEnabled: Bool { bytes[68] != 0 }
    public var portamentoFootSwitchEnabled: Bool { bytes[69] != 0 }
    public var chorusEnabled: Bool { bytes[70] != 0 }
    public var modulationWheelPitchRange: Int { Int(bytes[71]) }
    public var modulationWheelAmplitudeRange: Int { Int(bytes[72]) }
    public var breathControlPitchRange: Int { Int(bytes[73]) }
    public var breathControlAmplitudeRange: Int { Int(bytes[74]) }
    public var breathControlPitchBiasRange: Int { Int(bytes[75]) }
    public var breathControlEGBiasRange: Int { Int(bytes[76]) }

    public var operatorsInDataOrder: [DX100VoiceOperatorData] {
        Self.operatorNumbersInDataOrder.enumerated().map { offset, operatorNumber in
            let start = offset * Self.operatorBlockByteCount
            let end = start + Self.operatorBlockByteCount
            return DX100VoiceOperatorData(
                operatorNumber: operatorNumber,
                bytes: Array(bytes[start..<end])
            )
        }
    }

    public var operators: [DX100VoiceOperatorData] {
        operatorsInDataOrder.sorted { $0.operatorNumber < $1.operatorNumber }
    }

    public func `operator`(number: Int) throws -> DX100VoiceOperatorData {
        guard (1...4).contains(number) else {
            throw DX100SysExError.operatorNumberOutOfRange(number)
        }
        return operatorsInDataOrder.first { $0.operatorNumber == number }!
    }

    public var fourOperatorVoice: FourOperatorVoiceData {
        FourOperatorVoiceData(
            sourceModelName: "DX100",
            name: name,
            algorithm: algorithm,
            feedback: feedback,
            transpose: transpose,
            lfoSpeed: lfoSpeed,
            lfoWaveform: lfoWaveform,
            lfoSyncEnabled: lfoSyncEnabled,
            pitchModulationDepth: pitchModulationDepth,
            amplitudeModulationDepth: amplitudeModulationDepth,
            pitchModulationSensitivity: pitchModulationSensitivity,
            amplitudeModulationSensitivity: amplitudeModulationSensitivity,
            operators: operators.map { op in
                FourOperatorVoiceOperatorData(
                    operatorNumber: op.operatorNumber,
                    isCarrier: FourOperatorVoiceData.carrierOperatorNumbers(forAlgorithm: algorithm).contains(op.operatorNumber),
                    totalLevel: op.outputLevel,
                    frequencyValue: op.oscillatorFrequency,
                    detune: op.detune - 3,
                    keyboardLevelScalingDepth: op.keyboardScalingLevel,
                    keyboardRateScalingDepth: op.keyboardScalingRate,
                    velocityToTotalLevel: op.keyVelocitySensitivity,
                    velocityToAttack: 0,
                    amplitudeModulationEnabled: op.amplitudeModulationEnabled,
                    attack: op.attackRate,
                    decay1: op.decay1Rate,
                    decay2: op.decay2Rate,
                    sustain: op.decay1Level,
                    release: op.releaseRate
                )
            }
        )
    }
}

public struct DX100VoiceOperatorData: Equatable, Sendable {
    public var operatorNumber: Int
    public var bytes: [UInt8]

    public var attackRate: Int { Int(bytes[0]) }
    public var decay1Rate: Int { Int(bytes[1]) }
    public var decay2Rate: Int { Int(bytes[2]) }
    public var releaseRate: Int { Int(bytes[3]) }
    public var decay1Level: Int { Int(bytes[4]) }
    public var keyboardScalingLevel: Int { Int(bytes[5]) }
    public var keyboardScalingRate: Int { Int(bytes[6]) }
    public var egBiasSensitivity: Int { Int(bytes[7]) }
    public var amplitudeModulationEnabled: Bool { bytes[8] != 0 }
    public var keyVelocitySensitivity: Int { Int(bytes[9]) }
    public var outputLevel: Int { Int(bytes[10]) }
    public var oscillatorFrequency: Int { Int(bytes[11]) }
    public var detune: Int { Int(bytes[12]) }
}

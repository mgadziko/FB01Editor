import Foundation

public enum DX100SysExError: Error, Equatable, CustomStringConvertible {
    case invalidByte(UInt8)
    case invalidChannel(Int)
    case invalidVoiceDataLength(expected: Int, actual: Int)
    case invalidSingleVoiceBulkLength(expected: Int, actual: Int)
    case invalidSingleVoiceBulkHeader
    case invalidThirtyTwoVoiceBulkHeader
    case checksumMismatch(expected: UInt8, actual: UInt8)
    case operatorNumberOutOfRange(Int)
    case voiceIndexOutOfRange(Int)

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
        case .invalidThirtyTwoVoiceBulkHeader:
            "Invalid DX100 32-voice bulk header or checksum"
        case let .checksumMismatch(expected, actual):
            "Invalid DX100 checksum: expected 0x\(String(expected, radix: 16)), got 0x\(String(actual, radix: 16))"
        case let .operatorNumberOutOfRange(number):
            "DX100 operator number must be 1...4, got \(number)"
        case let .voiceIndexOutOfRange(index):
            "DX100 packed voice index must be 0...31, got \(index)"
        }
    }
}

public enum DX100 {
    public static let start: UInt8 = 0xF0
    public static let end: UInt8 = 0xF7
    public static let yamahaID: UInt8 = 0x43
    public static let parameterChangeStatusBase: UInt8 = 0x10
    public static let parameterChangeGroup: UInt8 = 0x12
    public static let singleVoiceFormat: UInt8 = 0x03
    public static let singleVoiceByteCountMSB: UInt8 = 0x00
    public static let singleVoiceByteCountLSB: UInt8 = 0x5D
    public static let thirtyTwoVoiceFormat: UInt8 = 0x04
    public static let thirtyTwoVoiceByteCountMSB: UInt8 = 0x20
    public static let thirtyTwoVoiceByteCountLSB: UInt8 = 0x00
    public static let thirtyTwoVoiceDataByteCount = 4096

    public static func requestSingleVoiceBulk(channel: Int = 0) throws -> [UInt8] {
        guard (0...15).contains(channel) else {
            throw DX100SysExError.invalidChannel(channel)
        }
        return [start, yamahaID, 0x20 | UInt8(channel), singleVoiceFormat, end]
    }

    public static func requestThirtyTwoVoiceBulk(channel: Int = 0) throws -> [UInt8] {
        guard (0...15).contains(channel) else {
            throw DX100SysExError.invalidChannel(channel)
        }
        return [start, yamahaID, 0x20 | UInt8(channel), thirtyTwoVoiceFormat, end]
    }

    public static func parameterChange(channel: Int = 0, parameter: Int, data: Int) throws -> [UInt8] {
        guard (0...15).contains(channel) else {
            throw DX100SysExError.invalidChannel(channel)
        }
        guard (0...127).contains(parameter) else {
            throw DX100SysExError.invalidByte(UInt8(clamping: parameter))
        }
        guard (0...127).contains(data) else {
            throw DX100SysExError.invalidByte(UInt8(clamping: data))
        }
        return [
            start,
            yamahaID,
            parameterChangeStatusBase | UInt8(channel),
            parameterChangeGroup,
            UInt8(parameter),
            UInt8(data),
            end
        ]
    }

    public static func isThirtyTwoVoiceBulkSysEx(_ bytes: [UInt8]) -> Bool {
        guard bytes.count == thirtyTwoVoiceDataByteCount + 8,
              bytes[0] == start,
              bytes[1] == yamahaID,
              (bytes[2] & 0xF0) == 0x00,
              bytes[3] == thirtyTwoVoiceFormat,
              bytes[4] == thirtyTwoVoiceByteCountMSB,
              bytes[5] == thirtyTwoVoiceByteCountLSB,
              bytes.last == end else {
            return false
        }

        let data = Array(bytes[6..<(6 + thirtyTwoVoiceDataByteCount)])
        return checksum(for: data) == bytes[6 + thirtyTwoVoiceDataByteCount]
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

    public static func splitSysExMessages(from bytes: [UInt8]) -> [[UInt8]] {
        var messages: [[UInt8]] = []
        var buffer: [UInt8] = []

        for byte in bytes {
            if byte == start {
                buffer = [byte]
                continue
            }

            guard !buffer.isEmpty else {
                continue
            }

            buffer.append(byte)
            if byte == end {
                messages.append(buffer)
                buffer.removeAll(keepingCapacity: true)
            }
        }

        return messages
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

    public func settingName(_ name: String) throws -> DX100VoiceData {
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
        copy.replaceSubrange(77..<87, with: allowed + Array(repeating: 0x20, count: Self.nameLength - allowed.count))
        return try DX100VoiceData(bytes: copy)
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
                    oscillatorFrequencyControl: op.oscillatorFrequency,
                    detune: op.detune - 3,
                    keyboardLevelScalingDepth: op.keyboardScalingLevel,
                    keyboardRateScalingDepth: op.keyboardScalingRate,
                    keyVelocityLevelSensitivity: op.keyVelocitySensitivity,
                    velocityToAttack: 0,
                    amplitudeModulationResponseEnabled: op.amplitudeModulationEnabled,
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

public struct DX100VoiceBankData: Equatable, Sendable {
    public static let packedVoiceCount = 32
    public static let packedVoiceByteCount = 128
    public static let dx100DisplayedVoiceCount = 24
    public static let packedVoiceNameRange = 57..<67

    public var bytes: [UInt8]
    public var channel: Int

    public init(bytes: [UInt8], channel: Int = 0) throws {
        guard bytes.count == DX100.thirtyTwoVoiceDataByteCount else {
            throw DX100SysExError.invalidVoiceDataLength(
                expected: DX100.thirtyTwoVoiceDataByteCount,
                actual: bytes.count
            )
        }
        guard (0...15).contains(channel) else {
            throw DX100SysExError.invalidChannel(channel)
        }
        self.bytes = try bytes.map { try DX100.validateDataByte($0) }
        self.channel = channel
    }

    public init(thirtyTwoVoiceBulkSysEx bytes: [UInt8]) throws {
        guard DX100.isThirtyTwoVoiceBulkSysEx(bytes) else {
            throw DX100SysExError.invalidThirtyTwoVoiceBulkHeader
        }
        let dataStart = 6
        try self.init(
            bytes: Array(bytes[dataStart..<(dataStart + DX100.thirtyTwoVoiceDataByteCount)]),
            channel: Int(bytes[2] & 0x0F)
        )
    }

    public var voiceNames: [String] {
        (0..<Self.packedVoiceCount).map { index in
            name(atPackedVoiceIndex: index)
        }
    }

    public var dx100DisplayedVoiceNames: [String] {
        Array(voiceNames.prefix(Self.dx100DisplayedVoiceCount))
    }

    public static func packedVoiceRecord(from voice: DX100VoiceData) -> [UInt8] {
        var packed = Array(repeating: UInt8(0), count: packedVoiceByteCount)

        for operatorIndex in 0..<DX100VoiceData.operatorNumbersInDataOrder.count {
            let packedOperatorStart = operatorIndex * 10
            let expandedOperatorStart = operatorIndex * DX100VoiceData.operatorBlockByteCount
            packed[packedOperatorStart + 0] = voice.bytes[expandedOperatorStart + 0]
            packed[packedOperatorStart + 1] = voice.bytes[expandedOperatorStart + 1]
            packed[packedOperatorStart + 2] = voice.bytes[expandedOperatorStart + 2]
            packed[packedOperatorStart + 3] = voice.bytes[expandedOperatorStart + 3]
            packed[packedOperatorStart + 4] = voice.bytes[expandedOperatorStart + 4]
            packed[packedOperatorStart + 5] = voice.bytes[expandedOperatorStart + 5]
            packed[packedOperatorStart + 6] =
                ((voice.bytes[expandedOperatorStart + 8] & 0x01) << 6)
                | ((voice.bytes[expandedOperatorStart + 7] & 0x07) << 3)
                | (voice.bytes[expandedOperatorStart + 9] & 0x07)
            packed[packedOperatorStart + 7] = voice.bytes[expandedOperatorStart + 10]
            packed[packedOperatorStart + 8] = voice.bytes[expandedOperatorStart + 11]
            packed[packedOperatorStart + 9] =
                ((voice.bytes[expandedOperatorStart + 6] & 0x03) << 3)
                | (voice.bytes[expandedOperatorStart + 12] & 0x07)
        }

        packed[40] =
            ((voice.bytes[58] & 0x01) << 6)
            | ((voice.bytes[53] & 0x07) << 3)
            | (voice.bytes[52] & 0x07)
        packed[41] = voice.bytes[54]
        packed[42] = voice.bytes[55]
        packed[43] = voice.bytes[56]
        packed[44] = voice.bytes[57]
        packed[45] =
            ((voice.bytes[60] & 0x07) << 4)
            | ((voice.bytes[61] & 0x03) << 2)
            | (voice.bytes[59] & 0x03)
        packed[46] = voice.bytes[62]
        packed[47] = voice.bytes[64]
        packed[48] =
            (voice.bytes[63] & 0x01)
            | ((voice.bytes[65] & 0x01) << 1)
            | ((voice.bytes[68] & 0x01) << 2)
            | ((voice.bytes[69] & 0x01) << 3)
            | ((voice.bytes[70] & 0x01) << 4)
        packed[49] = voice.bytes[66]
        packed[50] = voice.bytes[67]
        packed[51] = voice.bytes[71]
        packed[52] = voice.bytes[72]
        packed[53] = voice.bytes[73]
        packed[54] = voice.bytes[74]
        packed[55] = voice.bytes[75]
        packed[56] = voice.bytes[76]
        packed.replaceSubrange(packedVoiceNameRange, with: voice.bytes[77..<87])
        packed.replaceSubrange(67..<73, with: voice.bytes[87..<93])

        return packed
    }

    public func voice(atPackedVoiceIndex index: Int) throws -> DX100VoiceData {
        guard (0..<Self.packedVoiceCount).contains(index) else {
            throw DX100SysExError.voiceIndexOutOfRange(index)
        }

        let packedStart = index * Self.packedVoiceByteCount
        let packed = Array(bytes[packedStart..<(packedStart + Self.packedVoiceByteCount)])
        var expanded = Array(repeating: UInt8(0), count: DX100VoiceData.byteCount)

        for operatorIndex in 0..<DX100VoiceData.operatorNumbersInDataOrder.count {
            let packedOperatorStart = operatorIndex * 10
            let expandedOperatorStart = operatorIndex * DX100VoiceData.operatorBlockByteCount
            expanded[expandedOperatorStart + 0] = packed[packedOperatorStart + 0]
            expanded[expandedOperatorStart + 1] = packed[packedOperatorStart + 1]
            expanded[expandedOperatorStart + 2] = packed[packedOperatorStart + 2]
            expanded[expandedOperatorStart + 3] = packed[packedOperatorStart + 3]
            expanded[expandedOperatorStart + 4] = packed[packedOperatorStart + 4]
            expanded[expandedOperatorStart + 5] = packed[packedOperatorStart + 5]

            let sensitivityByte = packed[packedOperatorStart + 6]
            expanded[expandedOperatorStart + 7] = (sensitivityByte >> 3) & 0x07
            expanded[expandedOperatorStart + 8] = (sensitivityByte >> 6) & 0x01
            expanded[expandedOperatorStart + 9] = sensitivityByte & 0x07

            expanded[expandedOperatorStart + 10] = packed[packedOperatorStart + 7]
            expanded[expandedOperatorStart + 11] = packed[packedOperatorStart + 8]

            let scalingAndDetuneByte = packed[packedOperatorStart + 9]
            expanded[expandedOperatorStart + 6] = (scalingAndDetuneByte >> 3) & 0x03
            expanded[expandedOperatorStart + 12] = scalingAndDetuneByte & 0x07
        }

        let algorithmByte = packed[40]
        expanded[52] = algorithmByte & 0x07
        expanded[53] = (algorithmByte >> 3) & 0x07
        expanded[58] = (algorithmByte >> 6) & 0x01
        expanded[54] = packed[41]
        expanded[55] = packed[42]
        expanded[56] = packed[43]
        expanded[57] = packed[44]

        let lfoShapeByte = packed[45]
        expanded[59] = lfoShapeByte & 0x03
        expanded[61] = (lfoShapeByte >> 2) & 0x03
        expanded[60] = (lfoShapeByte >> 4) & 0x07

        expanded[62] = packed[46]
        expanded[64] = packed[47]

        let performanceByte = packed[48]
        expanded[63] = performanceByte & 0x01
        expanded[65] = (performanceByte >> 1) & 0x01
        expanded[68] = (performanceByte >> 2) & 0x01
        expanded[69] = (performanceByte >> 3) & 0x01
        expanded[70] = (performanceByte >> 4) & 0x01

        expanded[66] = packed[49]
        expanded[67] = packed[50]
        expanded[71] = packed[51]
        expanded[72] = packed[52]
        expanded[73] = packed[53]
        expanded[74] = packed[54]
        expanded[75] = packed[55]
        expanded[76] = packed[56]
        expanded.replaceSubrange(77..<87, with: packed[Self.packedVoiceNameRange])
        expanded.replaceSubrange(87..<93, with: packed[67..<73])

        return try DX100VoiceData(bytes: expanded)
    }

    public func replacingVoice(atPackedVoiceIndex index: Int, with voice: DX100VoiceData) throws -> DX100VoiceBankData {
        guard (0..<Self.packedVoiceCount).contains(index) else {
            throw DX100SysExError.voiceIndexOutOfRange(index)
        }

        var copy = bytes
        let start = index * Self.packedVoiceByteCount
        copy.replaceSubrange(start..<(start + Self.packedVoiceByteCount), with: Self.packedVoiceRecord(from: voice))
        return try DX100VoiceBankData(bytes: copy, channel: channel)
    }

    public func thirtyTwoVoiceBulkSysEx(channel: Int? = nil) throws -> [UInt8] {
        let channel = channel ?? self.channel
        guard (0...15).contains(channel) else {
            throw DX100SysExError.invalidChannel(channel)
        }

        return [
            DX100.start,
            DX100.yamahaID,
            UInt8(channel),
            DX100.thirtyTwoVoiceFormat,
            DX100.thirtyTwoVoiceByteCountMSB,
            DX100.thirtyTwoVoiceByteCountLSB,
        ] + bytes + [DX100.checksum(for: bytes), DX100.end]
    }

    private func name(atPackedVoiceIndex index: Int) -> String {
        let start = index * Self.packedVoiceByteCount
        let range = Self.packedVoiceNameRange
        let nameBytes = bytes[(start + range.lowerBound)..<(start + range.upperBound)]
        let name = String(bytes: nameBytes, encoding: .ascii) ?? ""
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
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

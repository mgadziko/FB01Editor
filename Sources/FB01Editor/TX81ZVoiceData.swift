import Foundation

public enum TX81ZSysExError: Error, Equatable, CustomStringConvertible {
    case invalidChannel(Int)
    case invalidAdditionalVoiceDataLength(expected: Int, actual: Int)
    case invalidAdditionalVoiceBulkHeader
    case checksumMismatch(expected: UInt8, actual: UInt8)
    case missingVoiceEditData
    case missingAdditionalVoiceData
    case invalidPerformanceDataLength(expected: Int, actual: Int)
    case invalidPerformanceBulkHeader
    case operatorNumberOutOfRange(Int)

    public var description: String {
        switch self {
        case let .invalidChannel(channel):
            "TX81Z SysEx channel must be 0...15, got \(channel)"
        case let .invalidAdditionalVoiceDataLength(expected, actual):
            "Invalid TX81Z additional voice data length: expected \(expected), got \(actual)"
        case .invalidAdditionalVoiceBulkHeader:
            "Invalid TX81Z additional voice bulk header"
        case let .checksumMismatch(expected, actual):
            "Invalid TX81Z checksum: expected 0x\(String(expected, radix: 16)), got 0x\(String(actual, radix: 16))"
        case .missingVoiceEditData:
            "The SysEx response does not contain TX81Z VCED voice data."
        case .missingAdditionalVoiceData:
            "The SysEx response does not contain TX81Z ACED additional voice data."
        case let .invalidPerformanceDataLength(expected, actual):
            "Invalid TX81Z Performance data length: expected \(expected), got \(actual)"
        case .invalidPerformanceBulkHeader:
            "Invalid TX81Z Performance bulk data header"
        case let .operatorNumberOutOfRange(number):
            "TX81Z operator number must be 1...4, got \(number)"
        }
    }
}

/// Yamaha TX81Z voice SysEx constants and documented read-only dump requests.
public enum TX81Z {
    public static let start: UInt8 = 0xF0
    public static let end: UInt8 = 0xF7
    public static let yamahaID: UInt8 = 0x43
    public static let dumpRequestStatusBase: UInt8 = 0x20
    public static let voiceEditFormat: UInt8 = 0x03
    public static let additionalVoiceFormat: UInt8 = 0x7E
    /// The bulk size field is 33 because it includes the 10-byte ASCII header;
    /// the ACED parameter payload itself contains 23 bytes.
    public static let additionalVoiceDataLength = 23
    public static let additionalVoiceByteCountMSB: UInt8 = 0x00
    public static let additionalVoiceByteCountLSB: UInt8 = 0x21
    public static let additionalVoiceIdentifier = Array("LM  8976AE".utf8)
    public static let systemParameterGroup: UInt8 = 0x10
    public static let systemParameterClass: UInt8 = 0x7B
    public static let memoryProtectParameter: UInt8 = 8

    public static func requestVoiceEditData(channel: Int = 0) throws -> [UInt8] {
        guard (0...15).contains(channel) else {
            throw TX81ZSysExError.invalidChannel(channel)
        }
        return [start, yamahaID, dumpRequestStatusBase | UInt8(channel), voiceEditFormat, end]
    }

    /// Requests both TX81Z-only ACED data and the compatible VCED voice data.
    public static func requestAdditionalAndVoiceEditData(channel: Int = 0) throws -> [UInt8] {
        guard (0...15).contains(channel) else {
            throw TX81ZSysExError.invalidChannel(channel)
        }
        return [start, yamahaID, dumpRequestStatusBase | UInt8(channel), additionalVoiceFormat]
            + additionalVoiceIdentifier
            + [end]
    }

    /// Requests the TX81Z's 32-voice VMEM bank. The payload uses the same
    /// packed 128-byte voice record shape as Yamaha's other 4-op VMEM dumps.
    public static func requestVoiceMemoryBank(channel: Int = 0) throws -> [UInt8] {
        guard (0...15).contains(channel) else {
            throw TX81ZSysExError.invalidChannel(channel)
        }
        return [start, yamahaID, dumpRequestStatusBase | UInt8(channel), DX100.thirtyTwoVoiceFormat, end]
    }

    /// Sets TX81Z System Setup MLOCK (Memory Protect). The TX resets MLOCK
    /// to ON after power-up and after receiving any bulk data message.
    public static func memoryProtectMessage(channel: Int = 0, enabled: Bool) throws -> [UInt8] {
        guard (0...15).contains(channel) else {
            throw TX81ZSysExError.invalidChannel(channel)
        }
        return [
            start,
            yamahaID,
            0x10 | UInt8(channel),
            systemParameterGroup,
            systemParameterClass,
            memoryProtectParameter,
            enabled ? 1 : 0,
            end,
        ]
    }

    /// TX81Z ACED checksums cover the identifier and its data payload.
    public static func additionalVoiceChecksum(for data: [UInt8]) -> UInt8 {
        let sum = (additionalVoiceIdentifier + data).reduce(0) { ($0 + Int($1)) & 0x7F }
        return UInt8((128 - sum) & 0x7F)
    }

    public static func splitSysExMessages(from bytes: [UInt8]) -> [[UInt8]] {
        DX100.splitSysExMessages(from: bytes)
    }
}

public struct TX81ZAdditionalVoiceData: Equatable, Sendable {
    public static let byteCount = TX81Z.additionalVoiceDataLength
    // ACED follows the same physical operator order as VCED and VMEM.
    public static let operatorNumbersInDataOrder = [4, 2, 3, 1]

    public var bytes: [UInt8]

    public init(bytes: [UInt8]) throws {
        guard bytes.count == Self.byteCount else {
            throw TX81ZSysExError.invalidAdditionalVoiceDataLength(expected: Self.byteCount, actual: bytes.count)
        }
        guard bytes.allSatisfy({ $0 <= 0x7F }) else {
            throw TX81ZSysExError.invalidAdditionalVoiceBulkHeader
        }
        self.bytes = bytes
    }

    public init(additionalVoiceBulkSysEx bytes: [UInt8]) throws {
        let expectedLength = 16 + Self.byteCount + 2
        guard bytes.count == expectedLength,
              bytes[0] == TX81Z.start,
              bytes[1] == TX81Z.yamahaID,
              (bytes[2] & 0xF0) == 0x00,
              bytes[3] == TX81Z.additionalVoiceFormat,
              bytes[4] == TX81Z.additionalVoiceByteCountMSB,
              bytes[5] == TX81Z.additionalVoiceByteCountLSB,
              Array(bytes[6..<16]) == TX81Z.additionalVoiceIdentifier,
              bytes.last == TX81Z.end else {
            throw TX81ZSysExError.invalidAdditionalVoiceBulkHeader
        }

        let data = Array(bytes[16..<(16 + Self.byteCount)])
        let expectedChecksum = TX81Z.additionalVoiceChecksum(for: data)
        let actualChecksum = bytes[16 + Self.byteCount]
        guard expectedChecksum == actualChecksum else {
            throw TX81ZSysExError.checksumMismatch(expected: expectedChecksum, actual: actualChecksum)
        }
        try self.init(bytes: data)
    }

    public func additionalVoiceBulkSysEx(channel: Int = 0) throws -> [UInt8] {
        guard (0...15).contains(channel) else {
            throw TX81ZSysExError.invalidChannel(channel)
        }
        return [
            TX81Z.start,
            TX81Z.yamahaID,
            UInt8(channel),
            TX81Z.additionalVoiceFormat,
            TX81Z.additionalVoiceByteCountMSB,
            TX81Z.additionalVoiceByteCountLSB,
        ] + TX81Z.additionalVoiceIdentifier + bytes + [TX81Z.additionalVoiceChecksum(for: bytes), TX81Z.end]
    }

    public func `operator`(number: Int) throws -> TX81ZOperatorExtensionData {
        guard let index = Self.operatorNumbersInDataOrder.firstIndex(of: number) else {
            throw TX81ZSysExError.operatorNumberOutOfRange(number)
        }
        return TX81ZOperatorExtensionData(
            operatorNumber: number,
            fixedFrequencyEnabled: bytes[index * 5] != 0,
            fixedFrequencyRange: Int(bytes[index * 5 + 1]),
            fineFrequency: Int(bytes[index * 5 + 2]),
            waveform: Int(bytes[index * 5 + 3]),
            envelopeShift: Int(bytes[index * 5 + 4])
        )
    }

    public func settingOperator(
        number: Int,
        fixedFrequencyEnabled: Bool? = nil,
        fixedFrequencyRange: Int? = nil,
        fineFrequency: Int? = nil,
        waveform: Int? = nil,
        envelopeShift: Int? = nil
    ) throws -> TX81ZAdditionalVoiceData {
        guard let index = Self.operatorNumbersInDataOrder.firstIndex(of: number) else {
            throw TX81ZSysExError.operatorNumberOutOfRange(number)
        }

        var updated = bytes
        let start = index * 5
        if let fixedFrequencyEnabled {
            updated[start] = fixedFrequencyEnabled ? 1 : 0
        }
        if let fixedFrequencyRange {
            updated[start + 1] = try Self.validated(fixedFrequencyRange, range: 0...7)
        }
        if let fineFrequency {
            updated[start + 2] = try Self.validated(fineFrequency, range: 0...15)
        }
        if let waveform {
            updated[start + 3] = try Self.validated(waveform, range: 0...7)
        }
        if let envelopeShift {
            updated[start + 4] = try Self.validated(envelopeShift, range: 0...3)
        }
        return try TX81ZAdditionalVoiceData(bytes: updated)
    }

    public func settingReverbRate(_ value: Int) throws -> TX81ZAdditionalVoiceData {
        var updated = bytes
        updated[20] = try Self.validated(value, range: 0...7)
        return try TX81ZAdditionalVoiceData(bytes: updated)
    }

    public var reverbRate: Int { Int(bytes[20]) }
    public var footControllerPitchDepth: Int { Int(bytes[21]) }
    public var footControllerAmplitudeDepth: Int { Int(bytes[22]) }

    private static func validated(_ value: Int, range: ClosedRange<Int>) throws -> UInt8 {
        guard range.contains(value) else {
            throw TX81ZSysExError.invalidAdditionalVoiceBulkHeader
        }
        return UInt8(value)
    }
}

public struct TX81ZOperatorExtensionData: Equatable, Sendable {
    public var operatorNumber: Int
    public var fixedFrequencyEnabled: Bool
    public var fixedFrequencyRange: Int
    public var fineFrequency: Int
    public var waveform: Int
    public var envelopeShift: Int

    public init(
        operatorNumber: Int,
        fixedFrequencyEnabled: Bool,
        fixedFrequencyRange: Int,
        fineFrequency: Int,
        waveform: Int,
        envelopeShift: Int
    ) {
        self.operatorNumber = operatorNumber
        self.fixedFrequencyEnabled = fixedFrequencyEnabled
        self.fixedFrequencyRange = fixedFrequencyRange
        self.fineFrequency = fineFrequency
        self.waveform = waveform
        self.envelopeShift = envelopeShift
    }
}

/// TX81Z Voice Memory (VMEM): 32 packed 128-byte records. Each record carries
/// both the common VCED parameters and TX81Z-only ACED parameters.
public struct TX81ZVoiceBankData: Equatable, Sendable {
    public static let voiceCount = DX100VoiceBankData.packedVoiceCount

    private var packedBank: DX100VoiceBankData
    private var rawBytes: [UInt8]

    public var channel: Int { packedBank.channel }
    public var voiceNames: [String] { packedBank.voiceNames }

    public init(voiceMemoryBulkSysEx bytes: [UInt8]) throws {
        guard DX100.isThirtyTwoVoiceBulkSysEx(bytes) else {
            throw DX100SysExError.invalidThirtyTwoVoiceBulkHeader
        }
        packedBank = try DX100VoiceBankData(thirtyTwoVoiceBulkSysEx: bytes)
        rawBytes = Array(bytes[6..<(6 + DX100.thirtyTwoVoiceDataByteCount)])
    }

    /// Builds a read-only snapshot from 32 complete ACED + VCED captures.
    /// Factory banks cannot be returned as VMEM dumps, so this supports the
    /// sequential capture path after the user selects a factory bank's Voice 1.
    public init(voices: [TX81ZVoiceData], channel: Int = 0) throws {
        guard voices.count == Self.voiceCount else {
            throw DX100SysExError.invalidVoiceDataLength(expected: Self.voiceCount, actual: voices.count)
        }

        var bytes = Array(repeating: UInt8(0), count: DX100.thirtyTwoVoiceDataByteCount)
        for (index, voice) in voices.enumerated() {
            let start = index * DX100VoiceBankData.packedVoiceByteCount
            var record = Array(repeating: UInt8(0), count: DX100VoiceBankData.packedVoiceByteCount)
            record.replaceSubrange(0..<73, with: DX100VoiceBankData.packedVoiceRecord(from: voice.voiceEdit).prefix(73))
            Self.pack(voice.additionalVoice, into: &record)
            bytes.replaceSubrange(start..<(start + DX100VoiceBankData.packedVoiceByteCount), with: record)
        }
        try self.init(bytes: bytes, channel: channel)
    }

    public func commonVoice(at index: Int) throws -> DX100VoiceData {
        try packedBank.voice(atPackedVoiceIndex: index)
    }

    public func voice(at index: Int) throws -> TX81ZVoiceData {
        guard (0..<Self.voiceCount).contains(index) else {
            throw DX100SysExError.voiceIndexOutOfRange(index)
        }

        let recordStart = index * DX100VoiceBankData.packedVoiceByteCount
        let record = Array(rawBytes[recordStart..<(recordStart + DX100VoiceBankData.packedVoiceByteCount)])
        let additional = try Self.unpackAdditionalVoice(from: record)
        return try TX81ZVoiceData(
            voiceEdit: try commonVoice(at: index),
            additionalVoice: additional,
            channel: channel
        )
    }

    public func replacingVoice(at index: Int, with voice: TX81ZVoiceData) throws -> TX81ZVoiceBankData {
        guard (0..<Self.voiceCount).contains(index) else {
            throw DX100SysExError.voiceIndexOutOfRange(index)
        }

        var updatedBytes = rawBytes
        let recordStart = index * DX100VoiceBankData.packedVoiceByteCount
        var record = Array(updatedBytes[recordStart..<(recordStart + DX100VoiceBankData.packedVoiceByteCount)])
        record.replaceSubrange(0..<73, with: DX100VoiceBankData.packedVoiceRecord(from: voice.voiceEdit).prefix(73))
        Self.pack(voice.additionalVoice, into: &record)
        updatedBytes.replaceSubrange(recordStart..<(recordStart + DX100VoiceBankData.packedVoiceByteCount), with: record)
        return try Self(bytes: updatedBytes, channel: channel)
    }

    public func voiceMemoryBulkSysEx(channel: Int? = nil) throws -> [UInt8] {
        try Self.bulkSysEx(bytes: rawBytes, channel: channel ?? self.channel)
    }

    private init(bytes: [UInt8], channel: Int) throws {
        guard bytes.count == DX100.thirtyTwoVoiceDataByteCount else {
            throw DX100SysExError.invalidVoiceDataLength(
                expected: DX100.thirtyTwoVoiceDataByteCount,
                actual: bytes.count
            )
        }
        rawBytes = bytes
        let message = try Self.bulkSysEx(bytes: bytes, channel: channel)
        packedBank = try DX100VoiceBankData(thirtyTwoVoiceBulkSysEx: message)
    }

    private static func bulkSysEx(bytes: [UInt8], channel: Int) throws -> [UInt8] {
        guard (0...15).contains(channel) else {
            throw TX81ZSysExError.invalidChannel(channel)
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

    private static func unpackAdditionalVoice(from record: [UInt8]) throws -> TX81ZAdditionalVoiceData {
        precondition(record.count == DX100VoiceBankData.packedVoiceByteCount)
        var data = Array(repeating: UInt8(0), count: TX81ZAdditionalVoiceData.byteCount)
        for (operatorIndex, dataStart) in stride(from: 0, to: 20, by: 5).enumerated() {
            let memoryStart = 73 + (operatorIndex * 2)
            let first = record[memoryStart]
            let second = record[memoryStart + 1]
            data[dataStart] = (first >> 3) & 0x01
            data[dataStart + 1] = first & 0x07
            data[dataStart + 2] = second & 0x0F
            data[dataStart + 3] = (second >> 4) & 0x07
            data[dataStart + 4] = (first >> 4) & 0x03
        }
        data[20] = record[81] & 0x07
        data[21] = record[82]
        data[22] = record[83]
        return try TX81ZAdditionalVoiceData(bytes: data)
    }

    private static func pack(_ additional: TX81ZAdditionalVoiceData, into record: inout [UInt8]) {
        precondition(record.count == DX100VoiceBankData.packedVoiceByteCount)
        for (operatorIndex, dataStart) in stride(from: 0, to: 20, by: 5).enumerated() {
            let memoryStart = 73 + (operatorIndex * 2)
            record[memoryStart] &= 0xC0
            record[memoryStart] |= (additional.bytes[dataStart] & 0x01) << 3
            record[memoryStart] |= additional.bytes[dataStart + 1] & 0x07
            record[memoryStart] |= (additional.bytes[dataStart + 4] & 0x03) << 4
            record[memoryStart + 1] &= 0x80
            record[memoryStart + 1] |= additional.bytes[dataStart + 2] & 0x0F
            record[memoryStart + 1] |= (additional.bytes[dataStart + 3] & 0x07) << 4
        }
        record[81] = (record[81] & 0x78) | (additional.bytes[20] & 0x07)
        record[82] = additional.bytes[21]
        record[83] = additional.bytes[22]
    }
}

/// A complete TX81Z current voice: common 4-op VCED data plus TX-only ACED data.
public struct TX81ZVoiceData: Equatable, Sendable {
    public var voiceEdit: DX100VoiceData
    public var additionalVoice: TX81ZAdditionalVoiceData
    public var channel: Int

    public init(voiceEdit: DX100VoiceData, additionalVoice: TX81ZAdditionalVoiceData, channel: Int = 0) throws {
        guard (0...15).contains(channel) else {
            throw TX81ZSysExError.invalidChannel(channel)
        }
        self.voiceEdit = voiceEdit
        self.additionalVoice = additionalVoice
        self.channel = channel
    }

    public init(messages: [[UInt8]]) throws {
        guard let voiceMessage = messages.first(where: { message in
            (try? DX100VoiceData(singleVoiceBulkSysEx: message)) != nil
        }) else {
            throw TX81ZSysExError.missingVoiceEditData
        }
        guard let additionalMessage = messages.first(where: { message in
            (try? TX81ZAdditionalVoiceData(additionalVoiceBulkSysEx: message)) != nil
        }) else {
            throw TX81ZSysExError.missingAdditionalVoiceData
        }
        let voiceEdit = try DX100VoiceData(singleVoiceBulkSysEx: voiceMessage)
        let additionalVoice = try TX81ZAdditionalVoiceData(additionalVoiceBulkSysEx: additionalMessage)
        try self.init(voiceEdit: voiceEdit, additionalVoice: additionalVoice, channel: Int(voiceMessage[2] & 0x0F))
    }

    public var name: String { voiceEdit.name }

    public var fourOperatorVoice: FourOperatorVoiceData {
        var neutral = voiceEdit.fourOperatorVoice
        neutral.sourceModelName = "TX81Z"
        return neutral
    }

    /// Applies Forest's shared 4-op controls without replacing TX81Z-only or
    /// otherwise unmodeled VCED bytes captured from the device.
    public func applying(neutralVoice: FourOperatorVoiceData) throws -> TX81ZVoiceData {
        var bytes = voiceEdit.bytes
        let nameBytes = Array(neutralVoice.name.prefix(DX100VoiceData.nameLength).utf8)
        for index in 0..<DX100VoiceData.nameLength {
            bytes[77 + index] = index < nameBytes.count ? min(nameBytes[index], 0x7E) : 0x20
        }

        bytes[52] = UInt8(clamped(neutralVoice.algorithm, range: 0...7))
        bytes[53] = UInt8(clamped(neutralVoice.feedback, range: 0...7))
        bytes[54] = UInt8(clamped(neutralVoice.lfoSpeed, range: 0...99))
        bytes[56] = UInt8(clamped(neutralVoice.pitchModulationDepth, range: 0...99))
        bytes[57] = UInt8(clamped(neutralVoice.amplitudeModulationDepth, range: 0...99))
        bytes[58] = neutralVoice.lfoSyncEnabled ? 1 : 0
        bytes[59] = UInt8(clamped(neutralVoice.lfoWaveform, range: 0...3))
        bytes[60] = UInt8(clamped(neutralVoice.pitchModulationSensitivity, range: 0...7))
        bytes[61] = UInt8(clamped(neutralVoice.amplitudeModulationSensitivity, range: 0...3))
        bytes[62] = UInt8(clamped(neutralVoice.transpose + 24, range: 0...48))

        for op in neutralVoice.operators {
            guard let dataOrderIndex = DX100VoiceData.operatorNumbersInDataOrder.firstIndex(of: op.operatorNumber) else {
                throw DX100SysExError.operatorNumberOutOfRange(op.operatorNumber)
            }
            let start = dataOrderIndex * DX100VoiceData.operatorBlockByteCount
            bytes[start] = UInt8(clamped(op.attack, range: 0...31))
            bytes[start + 1] = UInt8(clamped(op.decay1, range: 0...31))
            bytes[start + 2] = UInt8(clamped(op.decay2, range: 0...31))
            bytes[start + 3] = UInt8(clamped(op.release, range: 0...15))
            bytes[start + 4] = UInt8(clamped(op.sustain, range: 0...15))
            bytes[start + 5] = UInt8(clamped(op.keyboardLevelScalingDepth, range: 0...99))
            bytes[start + 6] = UInt8(clamped(op.keyboardRateScalingDepth, range: 0...3))
            bytes[start + 7] = UInt8(clamped(op.velocityToAttack, range: 0...7))
            bytes[start + 8] = op.amplitudeModulationResponseEnabled ? 1 : 0
            bytes[start + 9] = UInt8(clamped(op.keyVelocityLevelSensitivity, range: 0...7))
            bytes[start + 10] = UInt8(clamped(op.totalLevel, range: 0...99))
            bytes[start + 11] = UInt8(clamped(op.oscillatorFrequencyControl, range: 0...63))
            bytes[start + 12] = UInt8(clamped(op.detune + 3, range: 0...6))
        }

        return try TX81ZVoiceData(
            voiceEdit: DX100VoiceData(bytes: bytes),
            additionalVoice: additionalVoice,
            channel: channel
        )
    }

    public func settingOperatorExtension(
        number: Int,
        fixedFrequencyEnabled: Bool? = nil,
        fixedFrequencyRange: Int? = nil,
        fineFrequency: Int? = nil,
        waveform: Int? = nil,
        envelopeShift: Int? = nil
    ) throws -> TX81ZVoiceData {
        try TX81ZVoiceData(
            voiceEdit: voiceEdit,
            additionalVoice: additionalVoice.settingOperator(
                number: number,
                fixedFrequencyEnabled: fixedFrequencyEnabled,
                fixedFrequencyRange: fixedFrequencyRange,
                fineFrequency: fineFrequency,
                waveform: waveform,
                envelopeShift: envelopeShift
            ),
            channel: channel
        )
    }

    public func settingReverbRate(_ value: Int) throws -> TX81ZVoiceData {
        try TX81ZVoiceData(
            voiceEdit: voiceEdit,
            additionalVoice: additionalVoice.settingReverbRate(value),
            channel: channel
        )
    }

    public func bulkMessages(channel: Int? = nil) throws -> [[UInt8]] {
        let destinationChannel = channel ?? self.channel
        return [
            try additionalVoice.additionalVoiceBulkSysEx(channel: destinationChannel),
            try voiceEdit.singleVoiceBulkSysEx(channel: destinationChannel),
        ]
    }

    private func clamped(_ value: Int, range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

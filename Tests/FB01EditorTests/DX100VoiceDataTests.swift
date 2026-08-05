import Foundation
import Testing
@testable import FB01Editor

private let ivoryEbonySingleVoiceDump: [UInt8] = [
    0xF0, 0x43, 0x00, 0x03, 0x00, 0x5D,
    0x18, 0x01, 0x01, 0x03, 0x00, 0x34, 0x01, 0x00, 0x00, 0x00, 0x41, 0x04, 0x05,
    0x16, 0x01, 0x01, 0x04, 0x0C, 0x63, 0x01, 0x00, 0x00, 0x00, 0x4B, 0x00, 0x03,
    0x18, 0x05, 0x01, 0x03, 0x00, 0x63, 0x02, 0x00, 0x00, 0x00, 0x32, 0x16, 0x00,
    0x14, 0x08, 0x01, 0x06, 0x0C, 0x00, 0x02, 0x00, 0x00, 0x00, 0x63, 0x04, 0x03,
    0x02, 0x06, 0x23, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x18, 0x00, 0x00,
    0x00, 0x00, 0x63, 0x01, 0x00, 0x00, 0x32, 0x00, 0x00, 0x00, 0x32, 0x00, 0x49,
    0x76, 0x6F, 0x72, 0x79, 0x45, 0x62, 0x6F, 0x6E, 0x79, 0x63, 0x63, 0x63, 0x32,
    0x32, 0x32,
    0x3F, 0xF7,
]

private let ivoryEbonyPackedVoiceRecord: [UInt8] = [
    0x18, 0x01, 0x01, 0x03, 0x00, 0x34, 0x00, 0x41,
    0x04, 0x0D, 0x16, 0x01, 0x01, 0x04, 0x0C, 0x63,
    0x00, 0x4B, 0x00, 0x0B, 0x18, 0x05, 0x01, 0x03,
    0x00, 0x63, 0x00, 0x32, 0x16, 0x10, 0x14, 0x08,
    0x01, 0x06, 0x0C, 0x00, 0x00, 0x63, 0x04, 0x13,
    0x32, 0x23, 0x00, 0x00, 0x00, 0x02, 0x18, 0x00,
    0x04, 0x00, 0x63, 0x32, 0x00, 0x00, 0x00, 0x32,
    0x00, 0x49, 0x76, 0x6F, 0x72, 0x79, 0x45, 0x62,
    0x6F, 0x6E, 0x79, 0x63, 0x63, 0x63, 0x32, 0x32,
    0x32,
] + Array(repeating: UInt8(0), count: 55)

@Test func dx100BuildsSingleVoiceDumpRequest() throws {
    #expect(try DX100.requestSingleVoiceBulk(channel: 0) == [0xF0, 0x43, 0x20, 0x03, 0xF7])
    #expect(try DX100.requestSingleVoiceBulk(channel: 3) == [0xF0, 0x43, 0x23, 0x03, 0xF7])
    #expect(throws: DX100SysExError.invalidChannel(16)) {
        try DX100.requestSingleVoiceBulk(channel: 16)
    }
}

@Test func dx100BuildsAndRecognizesThirtyTwoVoiceBulkRequest() throws {
    #expect(try DX100.requestThirtyTwoVoiceBulk(channel: 0) == [0xF0, 0x43, 0x20, 0x04, 0xF7])
    #expect(try DX100.requestThirtyTwoVoiceBulk(channel: 3) == [0xF0, 0x43, 0x23, 0x04, 0xF7])

    let data = Array(repeating: UInt8(0), count: DX100.thirtyTwoVoiceDataByteCount)
    let message: [UInt8] = [
        DX100.start,
        DX100.yamahaID,
        0x00,
        DX100.thirtyTwoVoiceFormat,
        DX100.thirtyTwoVoiceByteCountMSB,
        DX100.thirtyTwoVoiceByteCountLSB,
    ] + data + [DX100.checksum(for: data), DX100.end]

    #expect(DX100.isThirtyTwoVoiceBulkSysEx(message))
    #expect(!DX100.isThirtyTwoVoiceBulkSysEx(message.dropLast(2) + [0x01, DX100.end]))
}

@Test func dx100VoiceBankParsesPackedVoiceNamesAndRoundTrips() throws {
    var data = Array(repeating: UInt8(0), count: DX100.thirtyTwoVoiceDataByteCount)
    for (index, name) in ["IvoryEbony", "Uprt piano", "Vibrabell"].enumerated() {
        let paddedName = Array(name.utf8.prefix(10)) + Array(repeating: UInt8(ascii: " "), count: 10 - min(name.count, 10))
        let start = index * DX100VoiceBankData.packedVoiceByteCount + DX100VoiceBankData.packedVoiceNameRange.lowerBound
        data.replaceSubrange(start..<(start + 10), with: paddedName)
    }

    let message: [UInt8] = [
        DX100.start,
        DX100.yamahaID,
        0x00,
        DX100.thirtyTwoVoiceFormat,
        DX100.thirtyTwoVoiceByteCountMSB,
        DX100.thirtyTwoVoiceByteCountLSB,
    ] + data + [DX100.checksum(for: data), DX100.end]

    let bank = try DX100VoiceBankData(thirtyTwoVoiceBulkSysEx: message)
    #expect(bank.channel == 0)
    #expect(bank.voiceNames.prefix(3) == ["IvoryEbony", "Uprt piano", "Vibrabell"])
    #expect(bank.dx100DisplayedVoiceNames.count == 24)
    #expect(try bank.thirtyTwoVoiceBulkSysEx() == message)
}

@Test func dx100VoiceBankExpandsPackedVoiceIntoEditableVoice() throws {
    let currentVoice = try DX100VoiceData(singleVoiceBulkSysEx: ivoryEbonySingleVoiceDump)
    var bankData = Array(repeating: UInt8(0), count: DX100.thirtyTwoVoiceDataByteCount)
    bankData.replaceSubrange(0..<DX100VoiceBankData.packedVoiceByteCount, with: ivoryEbonyPackedVoiceRecord)
    let bank = try DX100VoiceBankData(bytes: bankData)

    let expandedVoice = try bank.voice(atPackedVoiceIndex: 0)

    #expect(expandedVoice == currentVoice)
    #expect(expandedVoice.name == "IvoryEbony")
    #expect(throws: DX100SysExError.voiceIndexOutOfRange(32)) {
        try bank.voice(atPackedVoiceIndex: 32)
    }
}

@Test func dx100VoiceBankPacksEditableVoiceIntoPackedRecord() throws {
    let currentVoice = try DX100VoiceData(singleVoiceBulkSysEx: ivoryEbonySingleVoiceDump)
    let packed = DX100VoiceBankData.packedVoiceRecord(from: currentVoice)

    #expect(packed == ivoryEbonyPackedVoiceRecord)
}

@Test func dx100VoiceBankReplacesPackedVoiceSlot() throws {
    let currentVoice = try DX100VoiceData(singleVoiceBulkSysEx: ivoryEbonySingleVoiceDump)
    let initialBank = try DX100VoiceBankData(bytes: Array(repeating: 0, count: DX100.thirtyTwoVoiceDataByteCount))

    let editedBank = try initialBank.replacingVoice(atPackedVoiceIndex: 3, with: currentVoice)

    #expect(editedBank.voiceNames[3] == "IvoryEbony")
    #expect(try editedBank.voice(atPackedVoiceIndex: 3) == currentVoice)
    #expect(throws: DX100SysExError.voiceIndexOutOfRange(32)) {
        try initialBank.replacingVoice(atPackedVoiceIndex: 32, with: currentVoice)
    }
}

@Test func dx100ParsesCapturedIvoryEbonySingleVoiceDump() throws {
    let voice = try DX100VoiceData(singleVoiceBulkSysEx: ivoryEbonySingleVoiceDump)

    #expect(voice.name == "IvoryEbony")
    #expect(voice.algorithm == 2)
    #expect(voice.feedback == 6)
    #expect(voice.lfoSpeed == 35)
    #expect(voice.lfoDelay == 0)
    #expect(voice.pitchModulationDepth == 0)
    #expect(voice.amplitudeModulationDepth == 0)
    #expect(!voice.lfoSyncEnabled)
    #expect(voice.lfoWaveform == 2)
    #expect(voice.transpose == 0)
    #expect(voice.modulationWheelPitchRange == 50)
    #expect(voice.breathControlPitchBiasRange == 50)
    #expect(voice.operatorsInDataOrder.map(\.operatorNumber) == [4, 2, 3, 1])
    #expect(voice.operators.map(\.operatorNumber) == [1, 2, 3, 4])

    let op4 = try voice.operator(number: 4)
    #expect(op4.attackRate == 24)
    #expect(op4.keyboardScalingLevel == 52)
    #expect(op4.outputLevel == 65)
    #expect(op4.oscillatorFrequency == 4)
    #expect(op4.detune == 5)

    let op1 = try voice.operator(number: 1)
    #expect(op1.attackRate == 20)
    #expect(op1.decay1Level == 12)
    #expect(op1.outputLevel == 99)
    #expect(op1.oscillatorFrequency == 4)
    #expect(op1.detune == 3)
}

@Test func dx100SingleVoiceDumpRoundTripsWithChecksum() throws {
    let voice = try DX100VoiceData(singleVoiceBulkSysEx: ivoryEbonySingleVoiceDump)
    let rebuilt = try voice.singleVoiceBulkSysEx(channel: 0)

    #expect(rebuilt == ivoryEbonySingleVoiceDump)
    #expect(DX100.checksum(for: voice.bytes) == 0x3F)
}

@Test func dx100RejectsBadChecksum() throws {
    var damaged = ivoryEbonySingleVoiceDump
    damaged[99] = 0x00

    #expect(throws: DX100SysExError.checksumMismatch(expected: 0x3F, actual: 0x00)) {
        try DX100VoiceData(singleVoiceBulkSysEx: damaged)
    }
}

@Test func dx100MapsVoiceIntoNeutralFourOperatorShape() throws {
    let voice = try DX100VoiceData(singleVoiceBulkSysEx: ivoryEbonySingleVoiceDump)
    let neutral = voice.fourOperatorVoice

    #expect(neutral.sourceModelName == "DX100")
    #expect(neutral.name == "IvoryEbony")
    #expect(neutral.algorithm == 2)
    #expect(neutral.feedback == 6)
    #expect(neutral.transpose == 0)
    #expect(neutral.lfoWaveform == 2)
    #expect(neutral.operators.map(\.operatorNumber) == [1, 2, 3, 4])
    #expect(neutral.operators.filter(\.isCarrier).map(\.operatorNumber) == [1])

    let op1 = try #require(neutral.operators.first { $0.operatorNumber == 1 })
    #expect(op1.isCarrier)
    #expect(op1.totalLevel == 99)
    #expect(op1.frequencyValue == 4)
    #expect(op1.detune == 0)
    #expect(op1.attack == 20)
    #expect(op1.sustain == 12)

    let op4 = try #require(neutral.operators.first { $0.operatorNumber == 4 })
    #expect(!op4.isCarrier)
    #expect(op4.totalLevel == 65)
    #expect(op4.frequencyValue == 4)
    #expect(op4.detune == 2)
}

@Test func dx100VoiceServiceExtractsCurrentVoiceAndBuildsEditBufferMessage() throws {
    let service = DX100VoiceService.shared
    let fetched = try service.currentVoice(fromSingleVoiceBulkSysEx: ivoryEbonySingleVoiceDump)

    #expect(fetched.voice.name == "IvoryEbony")
    #expect(fetched.channel == 0)
    #expect(fetched.title == "Current Voice: IvoryEbony")
    #expect(try service.currentVoice(from: [ivoryEbonySingleVoiceDump]).voice == fetched.voice)
    #expect(try service.neutralVoice(fromSingleVoiceBulkSysEx: ivoryEbonySingleVoiceDump).name == "IvoryEbony")
    #expect(try service.editBufferMessages(for: fetched.voice, channel: fetched.channel) == [ivoryEbonySingleVoiceDump])
}

@Test func dx100VoiceServiceBuildsAndParsesVoiceBankMessages() throws {
    let service = DX100VoiceService.shared
    #expect(try service.voiceBankDumpRequest(channel: 0) == [0xF0, 0x43, 0x20, 0x04, 0xF7])

    var bankData = Array(repeating: UInt8(0), count: DX100.thirtyTwoVoiceDataByteCount)
    bankData.replaceSubrange(0..<DX100VoiceBankData.packedVoiceByteCount, with: ivoryEbonyPackedVoiceRecord)
    let bank = try DX100VoiceBankData(bytes: bankData, channel: 0)
    let message = try bank.thirtyTwoVoiceBulkSysEx()

    let parsedBank = try service.voiceBank(fromThirtyTwoVoiceBulkSysEx: message)
    #expect(parsedBank.voiceNames.first == "IvoryEbony")
    #expect(try service.voiceBankMessages(for: parsedBank, channel: 0) == [message])
}

@Test func dx100DocumentServiceTemplatesAndRoundTripsSingleVoiceFiles() throws {
    let service = DX100DocumentService.shared
    let template = try service.templateVoice()
    #expect(template.name == "Init")

    let voice = try DX100VoiceData(singleVoiceBulkSysEx: ivoryEbonySingleVoiceDump)
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("DX100DocumentServiceTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }

    let voiceURL = directory.appendingPathComponent("ivory-ebony.dxv")
    try service.writeVoice(voice, channel: 0, to: voiceURL)

    let candidates = try service.readVoiceCandidates(from: voiceURL)
    #expect(candidates.count == 1)
    #expect(candidates[0].voice == voice)
    #expect(candidates[0].channel == 0)
    #expect(candidates[0].title == "Current Voice: IvoryEbony")
}

@Test func dx100DocumentServiceRoundTripsVoiceBankFiles() throws {
    var bankData = Array(repeating: UInt8(0), count: DX100.thirtyTwoVoiceDataByteCount)
    bankData.replaceSubrange(0..<DX100VoiceBankData.packedVoiceByteCount, with: ivoryEbonyPackedVoiceRecord)
    let bank = try DX100VoiceBankData(bytes: bankData, channel: 2)

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("DX100BankDocumentServiceTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }

    let bankURL = directory.appendingPathComponent("current-bank.dxvb")
    try DX100DocumentService.shared.writeVoiceBank(bank, to: bankURL)

    let candidates = try DX100DocumentService.shared.readVoiceCandidates(from: bankURL)
    #expect(candidates.count == 24)
    #expect(candidates[0].channel == 2)
    #expect(candidates[0].voice.name == "IvoryEbony")
    #expect(candidates[0].title == "Voice 1: IvoryEbony")
}

@Test func dx100DocumentServiceReadsMultipleSingleVoiceMessagesFromSysEx() throws {
    let candidates = try DX100DocumentService.shared.voiceCandidates(
        fromSysExBytes: ivoryEbonySingleVoiceDump + ivoryEbonySingleVoiceDump
    )

    #expect(candidates.count == 2)
    #expect(candidates.map(\.voice.name) == ["IvoryEbony", "IvoryEbony"])
}

@Test func dx100DocumentServiceExtractsEditableVoicesFromPackedBankDump() throws {
    var bankData = Array(repeating: UInt8(0), count: DX100.thirtyTwoVoiceDataByteCount)
    bankData.replaceSubrange(0..<DX100VoiceBankData.packedVoiceByteCount, with: ivoryEbonyPackedVoiceRecord)
    let bank = try DX100VoiceBankData(bytes: bankData, channel: 0)

    let candidates = try DX100DocumentService.shared.voiceCandidates(
        fromSysExBytes: try bank.thirtyTwoVoiceBulkSysEx()
    )

    #expect(candidates.count == 24)
    #expect(candidates.first?.title == "Voice 1: IvoryEbony")
    let currentVoice = try DX100VoiceData(singleVoiceBulkSysEx: ivoryEbonySingleVoiceDump)
    #expect(candidates.first?.voice == currentVoice)
    #expect(candidates.allSatisfy { $0.channel == 0 })
}

@Test func fb01VoiceAlsoProjectsIntoNeutralFourOperatorShape() throws {
    let fb01Voice = try FB01DocumentService.shared.templateVoice()
    let neutral = fb01Voice.fourOperatorVoice

    #expect(neutral.sourceModelName == "FB-01")
    #expect(neutral.operators.count == 4)
    #expect(neutral.operators.map(\.operatorNumber) == [1, 2, 3, 4])
    #expect(neutral.algorithm == fb01Voice.algorithm)
    #expect(neutral.feedback == fb01Voice.feedbackLevel)
}

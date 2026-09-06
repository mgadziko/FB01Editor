import Foundation
import Testing
@testable import FB01Editor

private func makeTX81ZVCED(name: String = "TX Voice") throws -> [UInt8] {
    var bytes = Array(repeating: UInt8(0), count: DX100VoiceData.byteCount)
    bytes[3] = 1 // TX81Z release rate minimum is 1.
    bytes[16] = 1
    bytes[29] = 1
    bytes[42] = 1
    bytes[52] = 2
    bytes.replaceSubrange(77..<87, with: Array(repeating: UInt8(ascii: " "), count: 10))
    let nameBytes = Array(name.utf8.prefix(DX100VoiceData.nameLength))
    bytes.replaceSubrange(77..<(77 + nameBytes.count), with: nameBytes)
    return try DX100VoiceData(bytes: bytes).singleVoiceBulkSysEx(channel: 0)
}

private func makeTX81ZACED() throws -> [UInt8] {
    var bytes = Array(repeating: UInt8(0), count: TX81ZAdditionalVoiceData.byteCount)
    // Operator 4, then 2, 3, 1: FIX, FIXRG, FINE, OSW, EGSFT.
    bytes.replaceSubrange(0..<5, with: [1, 3, 12, 6, 2])
    bytes.replaceSubrange(5..<10, with: [0, 1, 4, 3, 1])
    bytes.replaceSubrange(10..<15, with: [1, 7, 15, 7, 3])
    bytes.replaceSubrange(15..<20, with: [0, 2, 1, 0, 0])
    bytes[20] = 5
    bytes[21] = 44
    bytes[22] = 55
    return try TX81ZAdditionalVoiceData(bytes: bytes).additionalVoiceBulkSysEx(channel: 0)
}

@Test func tx81zBuildsDocumentedCurrentVoiceRequests() throws {
    #expect(try TX81Z.requestVoiceEditData(channel: 0) == [0xF0, 0x43, 0x20, 0x03, 0xF7])
    #expect(try TX81Z.requestVoiceEditData(channel: 5) == [0xF0, 0x43, 0x25, 0x03, 0xF7])
    #expect(
        try TX81Z.requestAdditionalAndVoiceEditData(channel: 0)
            == [0xF0, 0x43, 0x20, 0x7E] + Array("LM  8976AE".utf8) + [0xF7]
    )
    #expect(throws: TX81ZSysExError.invalidChannel(16)) {
        try TX81Z.requestVoiceEditData(channel: 16)
    }
    #expect(try TX81Z.requestVoiceMemoryBank(channel: 0) == [0xF0, 0x43, 0x20, 0x04, 0xF7])
    #expect(try TX81Z.requestPerformanceEditData(channel: 0) == [0xF0, 0x43, 0x20, 0x7E] + Array("LM  8976PE".utf8) + [0xF7])
    #expect(try TX81Z.requestPerformanceMemoryBank(channel: 3) == [0xF0, 0x43, 0x23, 0x7E] + Array("LM  8976PM".utf8) + [0xF7])
}

@Test func tx81zPerformanceBankParsesTwentyFourInternalAndEightInitialPerformances() throws {
    var records: [UInt8] = []
    for index in 0..<TX81ZPerformanceBankData.performanceCount {
        var record = Array(repeating: UInt8(0), count: TX81ZPerformanceData.memoryDataLength)
        let name = String(format: "Perf %02d", index + 1)
        record.replaceSubrange(
            TX81ZPerformanceData.memoryNameOffset..<(TX81ZPerformanceData.memoryNameOffset + TX81ZPerformanceData.nameLength),
            with: Array(name.utf8) + Array(repeating: UInt8(ascii: " "), count: TX81ZPerformanceData.nameLength - name.utf8.count)
        )
        record[0] = UInt8(index % 9)
        record[1] = UInt8(index % 5)
        record[2] = UInt8(index)
        records += record
    }
    let identifier = TX81Z.performanceMemoryIdentifier
    let message = [TX81Z.start, TX81Z.yamahaID, 0, TX81Z.additionalVoiceFormat, 0x13, 0x0A]
        + identifier
        + records
        + [TX81Z.performanceChecksum(identifier: identifier, data: records), TX81Z.end]

    let bank = try TX81ZPerformanceBankData(performanceMemoryBulkSysEx: message)
    #expect(bank.performances.count == 32)
    #expect(bank.performances[0].name == "Perf 01")
    #expect(bank.performances[23].name == "Perf 24")
    #expect(bank.performances[24].name == "Perf 25")
    #expect(bank.performances[0].instruments[0].isCompactMemoryRecord)
}

@Test func tx81zVoiceMemoryBankParsesAllThirtyTwoNames() throws {
    let first = try makeTX81ZVCED(name: "Bank One")
    let second = try makeTX81ZVCED(name: "Bank Two")
    let firstVoice = try DX100VoiceData(singleVoiceBulkSysEx: first)
    let secondVoice = try DX100VoiceData(singleVoiceBulkSysEx: second)
    let firstPacked = DX100VoiceBankData.packedVoiceRecord(from: firstVoice)
    let secondPacked = DX100VoiceBankData.packedVoiceRecord(from: secondVoice)
    let filler = DX100VoiceBankData.packedVoiceRecord(from: firstVoice)
    let data = firstPacked + secondPacked + Array(repeating: filler, count: 30).flatMap { $0 }
    let dump = try DX100VoiceBankData(bytes: data, channel: 0).thirtyTwoVoiceBulkSysEx(channel: 0)

    let bank = try TX81ZVoiceBankData(voiceMemoryBulkSysEx: dump)
    #expect(bank.voiceNames.count == 32)
    #expect(bank.voiceNames[0] == "Bank One")
    #expect(bank.voiceNames[1] == "Bank Two")
    #expect(try bank.commonVoice(at: 1).name == "Bank Two")
}

@Test func tx81zVoiceMemoryBankRoundTripsCompleteVoiceData() throws {
    let voice = try TX81ZVoiceData(messages: [
        try makeTX81ZACED(),
        try makeTX81ZVCED(name: "Complete TX")
    ])
    var record = DX100VoiceBankData.packedVoiceRecord(from: voice.voiceEdit)
    record[73] = 0x2B
    record[74] = 0x6C
    record[75] = 0x1F
    record[76] = 0x34
    record[77] = 0x3F
    record[78] = 0x7F
    record[79] = 0x02
    record[80] = 0x01
    record[81] = 0x05
    record[82] = 44
    record[83] = 55
    let data = record + Array(repeating: record, count: 31).flatMap { $0 }
    let dump = try DX100VoiceBankData(bytes: data, channel: 0).thirtyTwoVoiceBulkSysEx(channel: 0)

    let bank = try TX81ZVoiceBankData(voiceMemoryBulkSysEx: dump)
    let decoded = try bank.voice(at: 0)
    #expect(decoded.name == "Complete T")
    #expect(decoded.additionalVoice.reverbRate == 5)
    #expect(decoded.additionalVoice.footControllerPitchDepth == 44)
    #expect(decoded.additionalVoice.footControllerAmplitudeDepth == 55)

    let updated = try decoded.settingOperatorExtension(number: 1, fineFrequency: 13, waveform: 6)
    let rewritten = try bank.replacingVoice(at: 0, with: updated)
    let roundTripped = try TX81ZVoiceBankData(voiceMemoryBulkSysEx: rewritten.voiceMemoryBulkSysEx())
    #expect(try roundTripped.voice(at: 0) == updated)
    #expect(try roundTripped.voice(at: 1) == decoded)
}

@Test func tx81zAdditionalVoiceDataParsesAndRoundTrips() throws {
    let message = try makeTX81ZACED()
    let additional = try TX81ZAdditionalVoiceData(additionalVoiceBulkSysEx: message)

    #expect(try additional.additionalVoiceBulkSysEx(channel: 0) == message)
    #expect(additional.reverbRate == 5)
    #expect(additional.footControllerPitchDepth == 44)
    #expect(additional.footControllerAmplitudeDepth == 55)

    let op4 = try additional.operator(number: 4)
    #expect(op4.fixedFrequencyEnabled)
    #expect(op4.fixedFrequencyRange == 3)
    #expect(op4.fineFrequency == 12)
    #expect(op4.waveform == 6)
    #expect(op4.envelopeShift == 2)

    let op2 = try additional.operator(number: 2)
    #expect(!op2.fixedFrequencyEnabled)
    #expect(op2.fixedFrequencyRange == 1)
    #expect(op2.fineFrequency == 4)
    #expect(op2.waveform == 3)
    #expect(op2.envelopeShift == 1)
}

@Test func tx81zAdditionalVoiceChecksumUsesTheDocumentedIdentifier() throws {
    let empty = try TX81ZAdditionalVoiceData(bytes: Array(repeating: 0, count: TX81ZAdditionalVoiceData.byteCount))
    let message = try empty.additionalVoiceBulkSysEx(channel: 0)

    #expect(message.suffix(2) == [0x43, 0xF7])
    #expect(try TX81ZAdditionalVoiceData(additionalVoiceBulkSysEx: message) == empty)
}

@Test func tx81zCurrentVoiceCombinesACEDAndVCEDLosslessly() throws {
    let vcedMessage = try makeTX81ZVCED(name: "TX Hands")
    let acedMessage = try makeTX81ZACED()
    let voice = try TX81ZVoiceData(messages: [acedMessage, vcedMessage])

    #expect(voice.name == "TX Hands")
    #expect(voice.channel == 0)
    #expect(voice.fourOperatorVoice.sourceModelName == "TX81Z")
    #expect(try voice.bulkMessages() == [acedMessage, vcedMessage])

    let fetched = try TX81ZVoiceService.shared.currentVoice(from: [acedMessage, vcedMessage])
    #expect(fetched.title == "Current Voice: TX Hands")
}

@Test func tx81zEditsPreserveUnmodeledBytesAndRebuildBothBulkMessages() throws {
    let original = try TX81ZVoiceData(messages: [try makeTX81ZACED(), try makeTX81ZVCED(name: "TX Hands")])
    var neutral = original.fourOperatorVoice
    neutral.name = "Edited TX"
    neutral.feedback = 6
    neutral.operators[0].totalLevel = 72

    let edited = try original
        .applying(neutralVoice: neutral)
        .settingOperatorExtension(number: 1, fineFrequency: 9, waveform: 5)
        .settingReverbRate(3)

    #expect(edited.name == "Edited TX")
    #expect(edited.voiceEdit.bytes[55] == original.voiceEdit.bytes[55])
    #expect(edited.additionalVoice.footControllerPitchDepth == 44)
    #expect(edited.additionalVoice.reverbRate == 3)
    #expect(try edited.additionalVoice.operator(number: 1).waveform == 5)
    #expect(try edited.additionalVoice.operator(number: 1).fineFrequency == 9)

    let roundTripped = try TX81ZVoiceData(messages: try edited.bulkMessages())
    #expect(roundTripped == edited)
}

@Test func tx81zModuleDeclaresWritableBankIAndFetchOnlyFactoryBanks() throws {
    let module = TX81ZSynthModule.shared

    #expect(module.identity.modelName == "TX81Z")
    #expect(module.vocabulary.configurationDisplayName == "Performance")
    #expect(module.fileProfile.singleVoiceExtension == "txv")
    #expect(module.supportedDocumentKinds == [.voice, .configuration, .voiceBank, .configurationBank])
    #expect(module.supportedDocumentDescriptors.first?.supportsFetchFromDevice == true)
    #expect(module.supportedDocumentDescriptors.first?.supportsStoreToDevice == true)
    #expect(module.parameterDescriptors.contains { $0.id == "voice.operator.waveform" })
    #expect(module.parameterBindingDescriptors.contains { $0.fieldName == "additionalVoice.fineFrequency" })
    #expect(module.capabilities.supportsLiveAuditionBuffer)
    #expect(module.capabilities.supportsConfigurations)
    #expect(module.capabilities.supportsWritableVoiceBanks)
    #expect(module.capabilities.supportsReadOnlyVoiceBanks)
    #expect(module.writableVoiceBanks == [1])
    #expect(module.readOnlyVoiceBanks == [2, 3, 4, 5])
    #expect(module.voicesPerBank == 32)
    #expect(try TX81ZModuleServices.shared.voiceService.currentVoiceDumpRequest(channel: 0) == [0xF0, 0x43, 0x20, 0x7E] + Array("LM  8976AE".utf8) + [0xF7])
    #expect(try TX81ZModuleServices.shared.voiceService.remoteSwitchMessages(.dataEntryPlus, channel: 0) == [
        [0xF0, 0x43, 0x10, 0x13, 72, 0x7F, 0xF7],
        [0xF0, 0x43, 0x10, 0x13, 72, 0x00, 0xF7],
    ])
    #expect(try TX81Z.memoryProtectMessage(channel: 0, enabled: false) == [0xF0, 0x43, 0x10, 0x10, 0x7B, 8, 0, 0xF7])
    #expect(try TX81Z.memoryProtectMessage(channel: 0, enabled: true) == [0xF0, 0x43, 0x10, 0x10, 0x7B, 8, 1, 0xF7])
}

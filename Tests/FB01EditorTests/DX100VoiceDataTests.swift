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

@Test func dx100BuildsSingleVoiceDumpRequest() throws {
    #expect(try DX100.requestSingleVoiceBulk(channel: 0) == [0xF0, 0x43, 0x20, 0x03, 0xF7])
    #expect(try DX100.requestSingleVoiceBulk(channel: 3) == [0xF0, 0x43, 0x23, 0x03, 0xF7])
    #expect(throws: DX100SysExError.invalidChannel(16)) {
        try DX100.requestSingleVoiceBulk(channel: 16)
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

@Test func fb01VoiceAlsoProjectsIntoNeutralFourOperatorShape() throws {
    let fb01Voice = try FB01DocumentService.shared.templateVoice()
    let neutral = fb01Voice.fourOperatorVoice

    #expect(neutral.sourceModelName == "FB-01")
    #expect(neutral.operators.count == 4)
    #expect(neutral.operators.map(\.operatorNumber) == [1, 2, 3, 4])
    #expect(neutral.algorithm == fb01Voice.algorithm)
    #expect(neutral.feedback == fb01Voice.feedbackLevel)
}

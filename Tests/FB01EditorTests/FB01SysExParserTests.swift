import Foundation
import Testing
@testable import FB01Editor

@Test func parsesGeneratedCommandBytes() throws {
    let bytes = try FB01Command.requestVoiceBank(systemChannel: 2, bank: 4).bytes
    let message = try FB01SysExMessage(bytes: bytes)

    #expect(message == .command(.requestVoiceBank(systemChannel: 2, bank: 4)))
    #expect(try message.bytes == bytes)
}

@Test func parsesGeneratedVoiceRAMRequestBytes() throws {
    let bytes = try FB01Command.requestVoiceRAM1(systemChannel: 2).bytes
    let message = try FB01SysExMessage(bytes: bytes)

    #expect(message == .command(.requestVoiceRAM1(systemChannel: 2)))
    #expect(try message.bytes == bytes)
}

@Test func parsesDeviceStatusResponse() throws {
    let bytes: [UInt8] = [0xF0, 0x43, 0x60, 0x04, 0xF7]
    let message = try FB01SysExMessage(bytes: bytes)

    #expect(message == .deviceStatus(code: 0x04))
    #expect(try message.bytes == bytes)
    #expect(try FB01Artifact(sysexBytes: bytes).kind == .rawSysEx)
}

@Test func parsesSingleInstrumentVoiceDump() throws {
    let rawVoice = Array(0..<64).map(UInt8.init)
    let packet = try FB01SysExPacket(payload: FB01.nibbleEncode(rawVoice))
    let message = FB01SysExMessage.instrumentVoiceDump(systemChannel: 0, instrument: 3, packet: packet)

    let parsed = try FB01SysExMessage(bytes: try message.bytes)

    guard case let .instrumentVoiceDump(systemChannel, instrument, parsedPacket) = parsed else {
        Issue.record("Expected instrument voice dump")
        return
    }

    #expect(systemChannel == 0)
    #expect(instrument == 3)
    #expect(try FB01.nibbleDecode(parsedPacket.payload) == rawVoice)
    #expect(parsedPacket.checksum == packet.checksum)
}

@Test func parsesVoiceBankDumpAsSeparateArtifactKind() throws {
    let voiceA = try FB01VoiceData(bytes: Array(repeating: 0x11, count: FB01VoiceData.byteCount))
    let voiceB = try FB01VoiceData(bytes: Array(repeating: 0x22, count: FB01VoiceData.byteCount))
    let packets = [
        try FB01SysExPacket(payload: voiceA.nibbleEncodedBytes),
        try FB01SysExPacket(payload: voiceB.nibbleEncodedBytes),
    ]
    let message = FB01SysExMessage.voiceBankDump(systemChannel: 1, bank: 2, packets: packets)
    let artifact = try FB01Artifact(sysexBytes: try message.bytes)

    #expect(artifact.kind == .voiceBank)
    #expect(artifact.messages.count == 1)
    #expect(try artifact.sysexBytes == message.bytes)

    guard case let .voiceBankDump(systemChannel, bank, parsedPackets) = artifact.messages[0] else {
        Issue.record("Expected voice bank dump")
        return
    }

    #expect(systemChannel == 1)
    #expect(bank == 2)
    #expect(parsedPackets == packets)
}

@Test func parsesCurrentAndStoredConfigurationsAsSeparateArtifactKinds() throws {
    let currentPacket = try FB01SysExPacket(payload: [0x01, 0x02, 0x03])
    let storedPacket = try FB01SysExPacket(payload: [0x04, 0x05, 0x06])

    let current = FB01SysExMessage.currentConfigurationDump(systemChannel: 0, packet: currentPacket)
    let stored = FB01SysExMessage.configurationDump(systemChannel: 0, number: 12, packet: storedPacket)

    #expect(try FB01Artifact(sysexBytes: current.bytes).kind == .currentConfiguration)
    #expect(try FB01Artifact(sysexBytes: stored.bytes).kind == .storedConfiguration)

    let combined = try FB01Artifact(sysexBytes: current.bytes + stored.bytes)
    #expect(combined.kind == .configurationSet)
    #expect(combined.messages.count == 2)
}

@Test func roundTripsTwentyStoredConfigurationSet() throws {
    let messages = try (0..<20).map { number in
        let payload = Array(repeating: UInt8(number), count: FB01ConfigurationData.byteCount)
        return FB01SysExMessage.configurationDump(
            systemChannel: 0,
            number: number,
            packet: try FB01SysExPacket(payload: payload)
        )
    }
    let artifact = FB01Artifact(kind: .configurationSet, messages: messages)
    let reparsed = try FB01Artifact(sysexBytes: artifact.sysexBytes)

    #expect(reparsed.kind == .configurationSet)
    #expect(reparsed.messages.count == 20)
    #expect(reparsed == artifact)

    for (index, message) in reparsed.messages.enumerated() {
        guard case let .configurationDump(_, number, packet) = message else {
            Issue.record("Expected stored configuration \(index)")
            return
        }
        #expect(number == index)
        #expect(packet.payload == Array(repeating: UInt8(index), count: FB01ConfigurationData.byteCount))
    }
}

@Test func roundTripsArtifactThroughSyxFile() throws {
    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension("syx")

    let packet = try FB01SysExPacket(payload: [0x10, 0x20, 0x30])
    let artifact = FB01Artifact(message: .configurationDump(systemChannel: 0, number: 7, packet: packet))

    try artifact.writeSysEx(to: tempURL)
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let loaded = try FB01Artifact.readSysEx(from: tempURL)
    #expect(loaded == artifact)
    #expect(loaded.kind == .storedConfiguration)
}

@Test func rejectsBadChecksumInDumpPacket() throws {
    let bytes: [UInt8] = [
        0xF0, 0x43, 0x75, 0x00, 0x00, 0x01, 0x00,
        0x00, 0x03, 0x01, 0x02, 0x03, 0x00,
        0xF7,
    ]

    #expect(throws: FB01SysExError.self) {
        _ = try FB01SysExMessage(bytes: bytes)
    }
}

@Test func parsesCapturedCurrentConfigurationFixture() throws {
    let fixtureURL = Bundle.module.url(
        forResource: "current-configuration-single",
        withExtension: "syx",
        subdirectory: "Fixtures"
    )!

    let artifact = try FB01Artifact.readSysEx(from: fixtureURL)

    #expect(artifact.kind == .currentConfiguration)
    #expect(artifact.messages.count == 1)

    guard case let .currentConfigurationDump(systemChannel, packet) = artifact.messages[0] else {
        Issue.record("Expected current configuration dump")
        return
    }

    let configuration = try FB01ConfigurationData(bytes: packet.payload)
    #expect(systemChannel == 0)
    #expect(packet.payload.count == 160)
    #expect(packet.checksum == 0x55)
    #expect(configuration.name == "single")
    #expect(configuration.combineModeEnabled == false)
    #expect(configuration.lfoSpeed == 102)
    #expect(configuration.amplitudeModulationDepth == 4)
    #expect(configuration.pitchModulationDepth == 33)
    #expect(configuration.lfoWaveform == 2)
    #expect(configuration.keyCodeReceiveMode == .all)

    let instruments = configuration.instruments
    #expect(instruments.count == 8)
    #expect(instruments.map(\.midiChannel) == Array(0...7))
    #expect(instruments.map(\.noteCount) == [8, 0, 0, 0, 0, 0, 0, 0])

    let instrument0 = instruments[0]
    #expect(instrument0.lowKeyLimit == 0)
    #expect(instrument0.highKeyLimit == 127)
    #expect(instrument0.voiceBank == 2)
    #expect(instrument0.voiceNumber == 5)
    #expect(instrument0.detune == 0)
    #expect(instrument0.octaveTranspose == 0)
    #expect(instrument0.outputLevel == 127)
    #expect(instrument0.pan == 64)
    #expect(instrument0.lfoEnabled == false)
    #expect(instrument0.portamentoTime == 0)
    #expect(instrument0.pitchBendRange == 5)
    #expect(instrument0.monoPolyMode == .poly)
    #expect(instrument0.pmdControllerAssignment == .modulationWheel)
}

@Test func editsConfigurationDataAndRebuildsChecksum() throws {
    let fixtureURL = Bundle.module.url(
        forResource: "current-configuration-single",
        withExtension: "syx",
        subdirectory: "Fixtures"
    )!

    let artifact = try FB01Artifact.readSysEx(from: fixtureURL)
    guard case let .currentConfigurationDump(systemChannel, packet) = artifact.messages[0] else {
        Issue.record("Expected current configuration dump")
        return
    }

    var configuration = try FB01ConfigurationData(bytes: packet.payload)
    var instrument = configuration.instruments[0]
    instrument = try instrument
        .settingMIDIChannel(4)
        .settingLowKeyLimit(12)
        .settingHighKeyLimit(108)
        .settingVoiceBank(7)
        .settingVoiceNumber(42)
        .settingOctaveTranspose(1)
        .settingOutputLevel(96)
        .settingPan(33)
        .settingLFOEnabled(false)
        .settingPortamentoTime(22)
        .settingPitchBendRange(9)
        .settingMonoPolyMode(.mono)
        .settingPMDControllerAssignment(.breathController)

    configuration = try configuration
        .settingName("EDITCFG")
        .settingCombineModeEnabled(true)
        .settingKeyCodeReceiveMode(.odd)
        .settingLFOSpeed(77)
        .settingAmplitudeModulationDepth(12)
        .settingPitchModulationDepth(34)
        .settingLFOWaveform(1)
        .replacingInstrument(instrument)

    let editedPacket = try FB01SysExPacket(payload: configuration.bytes)
    let editedMessage = FB01SysExMessage.currentConfigurationDump(systemChannel: systemChannel, packet: editedPacket)
    let reparsed = try FB01Artifact(sysexBytes: editedMessage.bytes)

    guard case let .currentConfigurationDump(_, reparsedPacket) = reparsed.messages[0] else {
        Issue.record("Expected edited current configuration dump")
        return
    }

    let reparsedConfiguration = try FB01ConfigurationData(bytes: reparsedPacket.payload)
    #expect(reparsedPacket.checksum == FB01.checksum(for: configuration.bytes))
    #expect(reparsedConfiguration.name == "EDITCFG")
    #expect(reparsedConfiguration.combineModeEnabled)
    #expect(reparsedConfiguration.keyCodeReceiveMode == .odd)
    #expect(reparsedConfiguration.lfoSpeed == 77)
    #expect(reparsedConfiguration.amplitudeModulationDepth == 12)
    #expect(reparsedConfiguration.pitchModulationDepth == 34)
    #expect(reparsedConfiguration.lfoWaveform == 1)

    let reparsedInstrument = reparsedConfiguration.instruments[0]
    #expect(reparsedInstrument.midiChannel == 4)
    #expect(reparsedInstrument.lowKeyLimit == 12)
    #expect(reparsedInstrument.highKeyLimit == 108)
    #expect(reparsedInstrument.voiceBank == 7)
    #expect(reparsedInstrument.voiceNumber == 42)
    #expect(reparsedInstrument.octaveTranspose == 1)
    #expect(reparsedInstrument.outputLevel == 96)
    #expect(reparsedInstrument.pan == 33)
    #expect(!reparsedInstrument.lfoEnabled)
    #expect(reparsedInstrument.portamentoTime == 22)
    #expect(reparsedInstrument.pitchBendRange == 9)
    #expect(reparsedInstrument.monoPolyMode == .mono)
    #expect(reparsedInstrument.pmdControllerAssignment == .breathController)
}

@Test func parsesCapturedVoiceBankFixtures() throws {
    for bank in 1...7 {
        let fixtureURL = Bundle.module.url(
            forResource: "voice-bank-\(bank)",
            withExtension: "syx",
            subdirectory: "Fixtures"
        )!

        let artifact = try FB01Artifact.readSysEx(from: fixtureURL)

        #expect(artifact.kind == .voiceBank)
        #expect(artifact.messages.count == 1)

        guard case let .voiceBankDumpData(systemChannel, parsedBank, byteCount, data, _) = artifact.messages[0] else {
            Issue.record("Expected captured voice bank dump")
            continue
        }

        #expect(systemChannel == 0)
        #expect(parsedBank == bank - 1)
        #expect(byteCount == 64)
        #expect(data.count == 6_352)
        #expect(try artifact.sysexBytes == Array(Data(contentsOf: fixtureURL)))

        let voiceBank = try FB01VoiceBankData(bank: parsedBank, data: data)
        #expect(voiceBank.voices.count == 48)
    }
}

@Test func decodesCapturedVoiceBankNames() throws {
    let fixtureURL = Bundle.module.url(
        forResource: "voice-bank-3",
        withExtension: "syx",
        subdirectory: "Fixtures"
    )!

    let artifact = try FB01Artifact.readSysEx(from: fixtureURL)

    #expect(artifact.kind == .voiceBank)
    #expect(artifact.messages.count == 1)

    guard case let .voiceBankDumpData(systemChannel, bank, byteCount, data, checksum) = artifact.messages[0] else {
        Issue.record("Expected captured voice bank dump")
        return
    }

    #expect(systemChannel == 0)
    #expect(bank == 2)
    #expect(byteCount == 64)
    #expect(data.count == 6_352)
    #expect(checksum == 0x5C)
    #expect(try artifact.sysexBytes == Array(Data(contentsOf: fixtureURL)))

    let voiceBank = try FB01VoiceBankData(bank: bank, data: data)
    #expect(voiceBank.voices.count == 48)
    #expect(voiceBank.headerBytes.count == 64)
    #expect(voiceBank.voices.prefix(20).map(\.name) == [
        "Brass",
        "Horn",
        "Trumpet",
        "LoStrig",
        "Strings",
        "Piano",
        "NewEP",
        "EGrand",
        "Jazz Gt",
        "EBass",
        "WodBass",
        "EOrgan1",
        "EOrgan2",
        "POrgan1",
        "POrgan2",
        "Flute",
        "Piccolo",
        "Oboe",
        "Clarine",
        "Glocken",
    ])

    let brass = voiceBank.voices[0]
    #expect(brass.encodedRecordBytes.count == 131)
    #expect(brass.voice.name == "Brass")
    #expect(brass.voice.lfoSpeed == 200)
    #expect(brass.voice.loadLFODataEnabled == true)
    #expect(brass.voice.amplitudeModulationDepth == 0)
    #expect(brass.voice.lfoSyncEnabled == false)
    #expect(brass.voice.pitchModulationDepth == 50)
    #expect(brass.voice.operatorEnabled == [true, true, true, true])
    #expect(brass.voice.feedbackLevel == 7)
    #expect(brass.voice.algorithm == 5)
    #expect(brass.voice.pitchModulationSensitivity == 3)
    #expect(brass.voice.amplitudeModulationSensitivity == 0)
    #expect(brass.voice.lfoWaveform == 2)
    #expect(brass.voice.transpose == 0)

    let firstOperator = brass.voice.operators[0]
    #expect(firstOperator.totalLevel == 18)
    #expect(firstOperator.multiple == 1)
    #expect(firstOperator.attackRate == 13)
    #expect(firstOperator.decay1Rate == 9)
    #expect(firstOperator.decay2Rate == 4)
    #expect(firstOperator.sustainLevel == 1)
    #expect(firstOperator.releaseRate == 8)
}

@Test func exportsCapturedVoiceAsSingleVoiceArtifact() throws {
    let fixtureURL = Bundle.module.url(
        forResource: "voice-bank-3",
        withExtension: "syx",
        subdirectory: "Fixtures"
    )!
    let artifact = try FB01Artifact.readSysEx(from: fixtureURL)

    guard case let .voiceBankDumpData(_, bank, _, data, _) = artifact.messages[0] else {
        Issue.record("Expected captured voice bank dump")
        return
    }

    let voiceBank = try FB01VoiceBankData(bank: bank, data: data)
    let brass = voiceBank.voices[0].voice
    let exported = try brass.instrumentVoiceArtifact(systemChannel: 0, instrument: 0)

    #expect(exported.kind == .singleVoice)
    #expect(exported.messages.count == 1)

    guard case let .instrumentVoiceDump(systemChannel, instrument, packet) = exported.messages[0] else {
        Issue.record("Expected exported instrument voice dump")
        return
    }

    #expect(systemChannel == 0)
    #expect(instrument == 0)
    #expect(try FB01.nibbleDecode(packet.payload) == brass.bytes)
    #expect(try FB01Artifact(sysexBytes: exported.sysexBytes) == exported)
}

@Test func operatorDisplayNumbersMapToReverseStoredDataOrder() throws {
    #expect(FB01VoiceData.operatorNumber(forDataIndex: 0) == 4)
    #expect(FB01VoiceData.operatorNumber(forDataIndex: 1) == 3)
    #expect(FB01VoiceData.operatorNumber(forDataIndex: 2) == 2)
    #expect(FB01VoiceData.operatorNumber(forDataIndex: 3) == 1)

    #expect(FB01VoiceData.dataIndex(forOperatorNumber: 1) == 3)
    #expect(FB01VoiceData.dataIndex(forOperatorNumber: 2) == 2)
    #expect(FB01VoiceData.dataIndex(forOperatorNumber: 3) == 1)
    #expect(FB01VoiceData.dataIndex(forOperatorNumber: 4) == 0)
}

@Test func settingAlgorithmAlsoAppliesUserFacingCarrierRoles() throws {
    let fixtureURL = Bundle.module.url(
        forResource: "voice-bank-3",
        withExtension: "syx",
        subdirectory: "Fixtures"
    )!
    let artifact = try FB01Artifact.readSysEx(from: fixtureURL)

    guard case let .voiceBankDumpData(_, bank, _, data, _) = artifact.messages[0] else {
        Issue.record("Expected captured voice bank dump")
        return
    }

    let voiceBank = try FB01VoiceBankData(bank: bank, data: data)
    let brass = voiceBank.voices[0].voice

    let algorithm3 = try brass.settingAlgorithmAndOperatorRoles(2)
    #expect(algorithm3.algorithm == 2)
    #expect(carrierOperatorNumbers(in: algorithm3) == [1])

    let algorithm5 = try brass.settingAlgorithmAndOperatorRoles(4)
    #expect(algorithm5.algorithm == 4)
    #expect(carrierOperatorNumbers(in: algorithm5) == [1, 3])

    let algorithm8 = try brass.settingAlgorithmAndOperatorRoles(7)
    #expect(algorithm8.algorithm == 7)
    #expect(carrierOperatorNumbers(in: algorithm8) == [1, 2, 3, 4])
}

@Test func editsVoiceDataAndExportsEditedSingleVoiceArtifact() throws {
    let fixtureURL = Bundle.module.url(
        forResource: "voice-bank-3",
        withExtension: "syx",
        subdirectory: "Fixtures"
    )!
    let artifact = try FB01Artifact.readSysEx(from: fixtureURL)

    guard case let .voiceBankDumpData(_, bank, _, data, _) = artifact.messages[0] else {
        Issue.record("Expected captured voice bank dump")
        return
    }

    let voiceBank = try FB01VoiceBankData(bank: bank, data: data)
    let brass = voiceBank.voices[0].voice
    let edited = try brass
        .settingName("EDITED!")
        .settingAlgorithm(2)
        .settingFeedbackLevel(3)
        .settingLFOSpeed(99)
        .settingLFOWaveform(3)
        .settingLFOSyncEnabled(true)
        .settingAmplitudeModulationDepth(44)
        .settingPitchModulationDepth(55)
        .settingAmplitudeModulationSensitivity(2)
        .settingPitchModulationSensitivity(6)
        .settingTranspose(-12)
        .settingLeftOutputEnabled(true)
        .settingRightOutputEnabled(false)
        .settingOperatorEnabled(index: 0, enabled: false)
        .replacingOperator(
            try brass.operators[1]
                .settingTotalLevel(77)
                .settingKeyboardLevelScalingTypeBit0(true)
                .settingVelocitySensitivityForTotalLevel(5)
                .settingKeyboardLevelScalingDepth(11)
                .settingTotalLevelAdjust(6)
                .settingKeyboardLevelScalingTypeBit1(true)
                .settingDetune1(4)
                .settingMultiple(12)
                .settingKeyboardRateScalingDepth(3)
                .settingAttackRate(24)
                .settingVelocitySensitivityForAttackRate(6)
                .settingDecay1Rate(9)
                .settingDetune2(2)
                .settingDecay2Rate(18)
                .settingSustainLevel(10)
                .settingReleaseRate(7)
                .settingCarrier(true)
        )

    #expect(edited.name == "EDITED!")
    #expect(edited.algorithm == 2)
    #expect(edited.feedbackLevel == 3)
    #expect(edited.lfoSpeed == 99)
    #expect(edited.lfoWaveform == 3)
    #expect(edited.lfoSyncEnabled)
    #expect(edited.amplitudeModulationDepth == 44)
    #expect(edited.pitchModulationDepth == 55)
    #expect(edited.amplitudeModulationSensitivity == 2)
    #expect(edited.pitchModulationSensitivity == 6)
    #expect(edited.transpose == -12)
    #expect(edited.leftOutputEnabled)
    #expect(!edited.rightOutputEnabled)
    #expect(!edited.operatorEnabled[0])
    #expect(edited.operators[1].totalLevel == 77)
    #expect(edited.operators[1].keyboardLevelScalingTypeBit0)
    #expect(edited.operators[1].velocitySensitivityForTotalLevel == 5)
    #expect(edited.operators[1].keyboardLevelScalingDepth == 11)
    #expect(edited.operators[1].totalLevelAdjust == 6)
    #expect(edited.operators[1].keyboardLevelScalingTypeBit1)
    #expect(edited.operators[1].detune1 == 4)
    #expect(edited.operators[1].multiple == 12)
    #expect(edited.operators[1].keyboardRateScalingDepth == 3)
    #expect(edited.operators[1].attackRate == 24)
    #expect(edited.operators[1].velocitySensitivityForAttackRate == 6)
    #expect(edited.operators[1].decay1Rate == 9)
    #expect(edited.operators[1].detune2 == 2)
    #expect(edited.operators[1].decay2Rate == 18)
    #expect(edited.operators[1].sustainLevel == 10)
    #expect(edited.operators[1].releaseRate == 7)
    #expect(edited.operators[1].carrier)

    let exported = try edited.instrumentVoiceArtifact(systemChannel: 0, instrument: 0)

    guard case let .instrumentVoiceDump(_, _, packet) = exported.messages[0] else {
        Issue.record("Expected exported instrument voice dump")
        return
    }

    #expect(try FB01.nibbleDecode(packet.payload) == edited.bytes)
    #expect(try FB01Artifact(sysexBytes: exported.sysexBytes) == exported)
}

private func carrierOperatorNumbers(in voice: FB01VoiceData) -> [Int] {
    voice.operators
        .filter(\.carrier)
        .map { FB01VoiceData.operatorNumber(forDataIndex: $0.index) }
        .sorted()
}

@Test func editsVoiceBankDataAndRoundTripsRebuiltBankArtifact() throws {
    let fixtureURL = Bundle.module.url(
        forResource: "voice-bank-3",
        withExtension: "syx",
        subdirectory: "Fixtures"
    )!
    let artifact = try FB01Artifact.readSysEx(from: fixtureURL)

    guard case let .voiceBankDumpData(systemChannel, bank, byteCount, data, _) = artifact.messages[0] else {
        Issue.record("Expected captured voice bank dump")
        return
    }

    let voiceBank = try FB01VoiceBankData(bank: bank, data: data)
    let editedVoice = try voiceBank.voices[0].voice
        .settingName("BANKED")
        .settingAlgorithm(1)
        .settingFeedbackLevel(2)
    let editedBank = try voiceBank.replacingVoices([1: editedVoice])
    let editedChecksum = FB01.checksum(for: editedBank.data)
    let rebuilt = FB01Artifact(message: .voiceBankDumpData(
        systemChannel: systemChannel,
        bank: bank,
        byteCount: byteCount,
        data: editedBank.data,
        checksum: editedChecksum
    ))
    let reparsed = try FB01Artifact(sysexBytes: rebuilt.sysexBytes)

    guard case let .voiceBankDumpData(_, reparsedBank, _, reparsedData, reparsedChecksum) = reparsed.messages[0] else {
        Issue.record("Expected rebuilt voice bank dump")
        return
    }

    let reparsedVoiceBank = try FB01VoiceBankData(bank: reparsedBank, data: reparsedData)
    #expect(reparsedChecksum == editedChecksum)
    #expect(reparsedVoiceBank.voices[0].voice == editedVoice)
    #expect(reparsedVoiceBank.voices[1].voice == voiceBank.voices[1].voice)
    #expect(reparsedData.prefix(FB01VoiceBankData.bankHeaderByteCount) == data.prefix(FB01VoiceBankData.bankHeaderByteCount))
}

@Test func parsesCapturedVoiceRAMFixture() throws {
    let fixtureURL = Bundle.module.url(
        forResource: "voice-ram1",
        withExtension: "syx",
        subdirectory: "Fixtures"
    )!

    let artifact = try FB01Artifact.readSysEx(from: fixtureURL)

    #expect(artifact.kind == .voiceBank)
    #expect(artifact.messages.count == 1)

    guard case let .voiceRAMDumpData(systemChannel, byteCount, data, checksum) = artifact.messages[0] else {
        Issue.record("Expected captured voice RAM dump")
        return
    }

    #expect(systemChannel == 0)
    #expect(byteCount == 64)
    #expect(data.count == 6_352)
    #expect(checksum == 0x5C)
    #expect(try artifact.sysexBytes == Array(Data(contentsOf: fixtureURL)))

    let voiceBank = try FB01VoiceBankData(bank: 0, data: data)
    #expect(voiceBank.voices.count == 48)
}

@Test func editsVoiceRAMDataAndRoundTripsRebuiltRAMArtifact() throws {
    let fixtureURL = Bundle.module.url(
        forResource: "voice-ram1",
        withExtension: "syx",
        subdirectory: "Fixtures"
    )!
    let artifact = try FB01Artifact.readSysEx(from: fixtureURL)

    guard case let .voiceRAMDumpData(systemChannel, byteCount, data, _) = artifact.messages[0] else {
        Issue.record("Expected captured voice RAM dump")
        return
    }

    let voiceBank = try FB01VoiceBankData(bank: 0, data: data)
    let editedVoice = try voiceBank.voices[5].voice.settingName("RAMEDIT")
    let editedBank = try voiceBank.replacingVoices([6: editedVoice])
    let editedChecksum = FB01.checksum(for: editedBank.data)
    let rebuilt = FB01Artifact(message: .voiceRAMDumpData(
        systemChannel: systemChannel,
        byteCount: byteCount,
        data: editedBank.data,
        checksum: editedChecksum
    ))
    let reparsed = try FB01Artifact(sysexBytes: rebuilt.sysexBytes)

    guard case let .voiceRAMDumpData(_, _, reparsedData, reparsedChecksum) = reparsed.messages[0] else {
        Issue.record("Expected rebuilt voice RAM dump")
        return
    }

    let reparsedVoiceBank = try FB01VoiceBankData(bank: 0, data: reparsedData)
    #expect(reparsedChecksum == editedChecksum)
    #expect(reparsedVoiceBank.voices[5].voice == editedVoice)
    #expect(reparsedVoiceBank.voices[4].voice == voiceBank.voices[4].voice)
}

@Test func parsesInvalidBankByte7ResponseAsDeviceStatus() throws {
    let fixtureURL = Bundle.module.url(
        forResource: "invalid-bank-byte-7-response",
        withExtension: "syx",
        subdirectory: "Fixtures"
    )!

    let artifact = try FB01Artifact.readSysEx(from: fixtureURL)

    #expect(artifact.kind == .rawSysEx)
    #expect(artifact.messages.count == 1)

    guard case let .deviceStatus(code) = artifact.messages[0] else {
        Issue.record("Expected device status response")
        return
    }

    #expect(code == 0x04)
    #expect(try artifact.sysexBytes == [0xF0, 0x43, 0x60, 0x04, 0xF7])
}

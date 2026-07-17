import Foundation
import Testing
@testable import FB01Editor

@Test func parsesGeneratedCommandBytes() throws {
    let bytes = try FB01Command.requestVoiceBank(systemChannel: 2, bank: 4).bytes
    let message = try FB01SysExMessage(bytes: bytes)

    #expect(message == .command(.requestVoiceBank(systemChannel: 2, bank: 4)))
    #expect(try message.bytes == bytes)
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

@Test func parsesCapturedVoiceBankFixture() throws {
    let fixtureURL = Bundle.module.url(
        forResource: "voice-bank-2",
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
}

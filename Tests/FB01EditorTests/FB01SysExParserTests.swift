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

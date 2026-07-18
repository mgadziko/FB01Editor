import Testing
@testable import FB01Editor

@Test func buildsInstrumentParameterChange() throws {
    let command = FB01Command.instrumentParameterChange(
        systemChannel: 0,
        instrument: 2,
        parameter: 0x10,
        value: .oneByte(0x7F)
    )

    #expect(try command.bytes == [0xF0, 0x43, 0x75, 0x00, 0x1A, 0x10, 0x7F, 0xF7])
}

@Test func buildsTwoByteVoiceParameterChange() throws {
    let command = FB01Command.midiChannelParameterChange(
        midiChannel: 3,
        parameter: 0x40,
        value: .twoByte(0xAB)
    )

    #expect(try command.bytes == [0xF0, 0x43, 0x13, 0x15, 0x40, 0x0B, 0x0A, 0xF7])
}

@Test func buildsCommonDumpRequests() throws {
    #expect(try FB01Command.requestVoiceRAM1(systemChannel: 4).bytes == [0xF0, 0x43, 0x24, 0x0C, 0xF7])
    #expect(try FB01Command.requestVoiceBank(systemChannel: 0, bank: 1).bytes == [0xF0, 0x43, 0x75, 0x00, 0x20, 0x00, 0x00, 0xF7])
    #expect(try FB01Command.requestVoiceBank(systemChannel: 0, bank: 7).bytes == [0xF0, 0x43, 0x75, 0x00, 0x20, 0x00, 0x06, 0xF7])
    #expect(try FB01Command.requestCurrentConfiguration(systemChannel: 0).bytes == [0xF0, 0x43, 0x75, 0x00, 0x20, 0x01, 0x00, 0xF7])
    #expect(try FB01Command.requestConfiguration(systemChannel: 0, number: 19).bytes == [0xF0, 0x43, 0x75, 0x00, 0x20, 0x02, 0x13, 0xF7])
    #expect(try FB01Command.requestAllConfigurations(systemChannel: 0).bytes == [0xF0, 0x43, 0x75, 0x00, 0x20, 0x03, 0x00, 0xF7])
    #expect(try FB01Command.requestUnitID(systemChannel: 0).bytes == [0xF0, 0x43, 0x75, 0x00, 0x20, 0x04, 0x00, 0xF7])
}

@Test func buildsUserFacingStoredConfigurationRequests() throws {
    #expect(try FB01MIDIRequestKind.configuration(1).bytes(systemChannel: 0) == [0xF0, 0x43, 0x75, 0x00, 0x20, 0x02, 0x00, 0xF7])
    #expect(try FB01MIDIRequestKind.configuration(20).bytes(systemChannel: 0) == [0xF0, 0x43, 0x75, 0x00, 0x20, 0x02, 0x13, 0xF7])
    #expect(try FB01MIDIRequestKind.instrumentVoice(1).bytes(systemChannel: 0) == [0xF0, 0x43, 0x75, 0x00, 0x28, 0x40, 0x00, 0xF7])
    #expect(try FB01MIDIRequestKind.instrumentVoice(8).bytes(systemChannel: 0) == [0xF0, 0x43, 0x75, 0x00, 0x2F, 0x40, 0x00, 0xF7])
}

@Test func buildsStoreCommands() throws {
    #expect(try FB01Command.storeCurrentInstrumentVoice(systemChannel: 1, instrument: 7, voiceNumber: 95).bytes == [0xF0, 0x43, 0x75, 0x01, 0x2F, 0x00, 0x5F, 0xF7])
    #expect(try FB01Command.storeCurrentConfiguration(systemChannel: 1, number: 15).bytes == [0xF0, 0x43, 0x75, 0x01, 0x20, 0x40, 0x0F, 0xF7])
}

@Test func nibbleEncodingRoundTripsVoiceBytes() throws {
    let voice = try FB01VoiceData(bytes: Array(0..<64).map(UInt8.init))

    #expect(voice.nibbleEncodedBytes.prefix(6) == [0x00, 0x00, 0x01, 0x00, 0x02, 0x00])
    #expect(try FB01.nibbleDecode(voice.nibbleEncodedBytes) == voice.bytes)
}

@Test func checksumIsSevenBitTwosComplement() throws {
    let packet = try FB01BulkPacket(payload: [0x01, 0x02, 0x7F])

    #expect(packet.checksum == 0x7E)
    #expect(throws: Never.self) {
        _ = try FB01BulkPacket(payload: [0x01, 0x02, 0x7F], checksum: 0x7E)
    }
}

@Test func rejectsOutOfRangeCommandValues() {
    #expect(throws: FB01SysExError.self) {
        _ = try FB01Command.requestVoiceBank(systemChannel: 0, bank: 0).bytes
    }

    #expect(throws: FB01SysExError.self) {
        _ = try FB01Command.instrumentParameterChange(systemChannel: 0, instrument: 8, parameter: 0x10, value: .oneByte(0)).bytes
    }
}

public struct FB01VoiceService: Sendable {
    public static let shared = FB01VoiceService(module: .shared)

    public var module: FB01SynthModule

    public init(module: FB01SynthModule) {
        self.module = module
    }

    public func voiceBankData(from bytes: [UInt8], expectedDisplayBank: Int) throws -> FB01VoiceBankData {
        let artifact = try FB01Artifact(sysexBytes: bytes)
        for message in artifact.messages {
            if case let .voiceBankDumpData(_, bank, _, data, _) = message,
               bank == module.storageVoiceBank(forDisplayBank: expectedDisplayBank) {
                return try FB01VoiceBankData(bank: bank, data: data)
            }
            if case let .voiceRAMDumpData(_, _, data, _) = message,
               expectedDisplayBank == module.writableVoiceBanks.first {
                return try FB01VoiceBankData(bank: 0, data: data)
            }
        }
        throw FB01SysExError.unsupportedSysEx
    }

    public func voiceNames(fromVoiceBankDump bytes: [UInt8], expectedDisplayBank: Int) throws -> [String] {
        try voiceBankData(from: bytes, expectedDisplayBank: expectedDisplayBank)
            .voices
            .map { summary in
                summary.voice.name.isEmpty ? "Untitled" : summary.voice.name
            }
    }

    public func storedVoice(fromVoiceBankDump bytes: [UInt8], expectedDisplayBank: Int, zeroBasedVoiceNumber: Int) throws -> FB01VoiceData? {
        let bankData = try voiceBankData(from: bytes, expectedDisplayBank: expectedDisplayBank)
        guard bankData.voices.indices.contains(zeroBasedVoiceNumber) else {
            throw FB01SysExError.valueOutOfRange(
                name: "voiceNumber",
                value: zeroBasedVoiceNumber,
                range: 0...(module.voicesPerBank - 1)
            )
        }
        return bankData.voices[zeroBasedVoiceNumber].voice
    }

    public func storedVoice(fromVoiceRAMDump bytes: [UInt8], zeroBasedVoiceNumber: Int) throws -> FB01VoiceData? {
        let artifact = try FB01Artifact(sysexBytes: bytes)
        for message in artifact.messages {
            if case let .voiceRAMDumpData(_, _, data, _) = message {
                let bankData = try FB01VoiceBankData(bank: 0, data: data)
                guard bankData.voices.indices.contains(zeroBasedVoiceNumber) else {
                    throw FB01SysExError.valueOutOfRange(
                        name: "voiceNumber",
                        value: zeroBasedVoiceNumber,
                        range: 0...(module.voicesPerBank - 1)
                    )
                }
                return bankData.voices[zeroBasedVoiceNumber].voice
            }
        }
        return nil
    }

    public func fetchStoredVoice(
        bank: Int,
        zeroBasedVoiceNumber: Int,
        sourceIndex: Int,
        destinationIndex: Int,
        systemChannel: Int,
        timeout: Double = 15
    ) throws -> FB01VoiceData {
        let bytes = try FB01MIDI.request(
            .voiceBank(bank),
            sourceIndex: sourceIndex,
            destinationIndex: destinationIndex,
            systemChannel: systemChannel,
            timeout: timeout
        )
        guard let voice = try storedVoice(
            fromVoiceBankDump: bytes,
            expectedDisplayBank: bank,
            zeroBasedVoiceNumber: zeroBasedVoiceNumber
        ) else {
            throw FB01SysExError.unsupportedSysEx
        }
        return voice
    }

    public func fetchWritableRAMVoiceNames(
        sourceIndex: Int,
        destinationIndex: Int,
        systemChannel: Int,
        timeout: Double = 25
    ) -> [Int: [String]] {
        var namesByBank: [Int: [String]] = [:]
        for bank in module.writableVoiceBanks {
            guard let bytes = try? FB01MIDI.request(
                .voiceBank(bank),
                sourceIndex: sourceIndex,
                destinationIndex: destinationIndex,
                systemChannel: systemChannel,
                timeout: timeout
            ),
                  let names = try? voiceNames(fromVoiceBankDump: bytes, expectedDisplayBank: bank) else {
                continue
            }
            namesByBank[bank] = names
        }
        return namesByBank
    }

    public func voiceBankLoadMessage(bank: FB01VoiceBankData, systemChannel: Int) throws -> [UInt8] {
        try FB01SysExMessage.voiceBankDumpData(
            systemChannel: systemChannel,
            bank: bank.bank,
            byteCount: FB01VoiceBankData.bankHeaderByteCount,
            data: bank.data,
            checksum: FB01.checksum(for: bank.data)
        ).bytes
    }
}

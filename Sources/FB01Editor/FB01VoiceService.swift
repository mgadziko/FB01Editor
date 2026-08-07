public enum FB01VoiceFetchLocation: Sendable {
    case bank(Int)
    case voiceRAM1

    public var requestKind: FB01MIDIRequestKind {
        switch self {
        case .bank(let bank):
            .voiceBank(bank)
        case .voiceRAM1:
            .voiceRAM1
        }
    }
}

public enum FB01InstrumentParameter {
    public static let noteCount = 0x00
    public static let midiChannel = 0x01
    public static let highKeyLimit = 0x02
    public static let lowKeyLimit = 0x03
    public static let outputLevel = 0x08
    public static let portamentoTime = 0x0B
}

public struct FB01FetchedVoice: Sendable {
    public var voice: FB01VoiceData
    public var systemChannel: Int
    public var title: String

    public init(voice: FB01VoiceData, systemChannel: Int, title: String) {
        self.voice = voice
        self.systemChannel = systemChannel
        self.title = title
    }
}

public struct FB01VoiceSendConfirmation: Sendable {
    public var statusCode: UInt8?

    public init(statusCode: UInt8?) {
        self.statusCode = statusCode
    }
}

public enum FB01VoiceBankImageStoreEvent: Equatable, Sendable {
    case turningProtectOff
    case storePass(Int)
}

public enum FB01VoiceBankStoreEvent: Equatable, Sendable {
    case turningProtectOff
    case storingBank
    case verifyingBank
}

public enum FB01VoiceStoreError: Error, Equatable, Sendable {
    case verificationFailed(bank: Int, voiceNumber: Int, maximumPasses: Int)
    case bankVerificationFailed(bank: Int)
}

public struct FB01VoiceService: SynthVoiceServicing {
    public typealias Voice = FB01VoiceData
    public typealias VoiceBank = FB01VoiceBankData

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

    public func currentInstrumentVoice(fromDump bytes: [UInt8]) throws -> (voice: FB01VoiceData, systemChannel: Int)? {
        let artifact = try FB01Artifact(sysexBytes: bytes)
        for message in artifact.messages {
            if case let .instrumentVoiceDump(systemChannel, _, packet) = message {
                return (try FB01VoiceData(bytes: FB01.nibbleDecode(packet.payload)), systemChannel)
            }
        }
        return nil
    }

    public func storedVoice(fromDump bytes: [UInt8], location: FB01VoiceFetchLocation, zeroBasedVoiceNumber: Int) throws -> FB01VoiceData? {
        switch location {
        case .bank(let bank):
            return try storedVoice(
                fromVoiceBankDump: bytes,
                expectedDisplayBank: bank,
                zeroBasedVoiceNumber: zeroBasedVoiceNumber
            )
        case .voiceRAM1:
            return try storedVoice(
                fromVoiceRAMDump: bytes,
                zeroBasedVoiceNumber: zeroBasedVoiceNumber
            )
        }
    }

    public func fetchInstrumentVoice(
        instrument: Int,
        sourceIndex: Int,
        destinationIndex: Int,
        systemChannel: Int,
        timeout: Double = 8
    ) throws -> FB01FetchedVoice {
        let displayInstrument = instrument + 1
        let bytes = try FB01MIDI.request(
            .instrumentVoice(displayInstrument),
            sourceIndex: sourceIndex,
            destinationIndex: destinationIndex,
            systemChannel: systemChannel,
            timeout: timeout
        )
        guard let payload = try currentInstrumentVoice(fromDump: bytes) else {
            throw FB01SysExError.unsupportedSysEx
        }
        return FB01FetchedVoice(
            voice: payload.voice,
            systemChannel: payload.systemChannel,
            title: "instrument \(displayInstrument) voice"
        )
    }

    public func sendInstrumentVoiceAndConfirm(
        _ voice: FB01VoiceData,
        instrument: Int,
        sourceIndex: Int,
        destinationIndex: Int,
        systemChannel: Int,
        timeout: Double = 8
    ) async throws -> FB01VoiceSendConfirmation {
        let status = try await Task.detached(priority: .userInitiated) {
            let artifact = try voice.instrumentVoiceArtifact(systemChannel: systemChannel, instrument: instrument)
            let request = try FB01MIDIRequestKind.instrumentVoice(instrument + 1).bytes(systemChannel: systemChannel)
            return try FB01MIDI.sendAndReceive(
                [try artifact.sysexBytes, request],
                sourceIndex: sourceIndex,
                destinationIndex: destinationIndex,
                timeout: timeout,
                maxMessages: 1,
                delayBetweenMessages: 0.35
            )
        }.value

        return FB01VoiceSendConfirmation(statusCode: try deviceStatusCode(from: status))
    }

    private func deviceStatusCode(from messages: [[UInt8]]) throws -> UInt8? {
        for bytes in messages {
            let artifact = try FB01Artifact(sysexBytes: bytes)
            for message in artifact.messages {
                if case .deviceStatus(let code) = message {
                    return code
                }
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

    public func fetchStoredVoice(
        location: FB01VoiceFetchLocation,
        zeroBasedVoiceNumber: Int,
        sourceIndex: Int,
        destinationIndex: Int,
        systemChannel: Int,
        timeout: Double = 15
    ) throws -> FB01FetchedVoice {
        let bytes = try FB01MIDI.request(
            location.requestKind,
            sourceIndex: sourceIndex,
            destinationIndex: destinationIndex,
            systemChannel: systemChannel,
            timeout: timeout
        )
        guard let voice = try storedVoice(
            fromDump: bytes,
            location: location,
            zeroBasedVoiceNumber: zeroBasedVoiceNumber
        ) else {
            throw FB01SysExError.unsupportedSysEx
        }

        let title: String
        switch location {
        case .bank(let bank):
            title = "Bank \(bank) Voice \(zeroBasedVoiceNumber + 1)"
        case .voiceRAM1:
            title = "Voice RAM 1 Voice \(zeroBasedVoiceNumber + 1)"
        }

        return FB01FetchedVoice(
            voice: voice,
            systemChannel: systemChannel,
            title: title
        )
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
        return try FB01SysExMessage.voiceBankDumpData(
            systemChannel: systemChannel,
            bank: bank.bank,
            byteCount: FB01VoiceBankData.bankHeaderByteCount,
            data: bank.data,
            checksum: FB01.checksum(for: bank.data)
        ).bytes
    }

    public func retargetedVoiceBank(_ voiceBank: FB01VoiceBankData, displayBank: Int) throws -> FB01VoiceBankData {
        guard module.isWritableVoiceBank(displayBank) else {
            throw FB01SysExError.valueOutOfRange(
                name: "voiceBank",
                value: displayBank,
                range: module.writableVoiceBankRange.closedRange
            )
        }

        return try FB01VoiceBankData(
            bank: module.storageVoiceBank(forDisplayBank: displayBank),
            data: voiceBank.data
        )
    }

    public func storeVoiceBank(
        _ voiceBank: FB01VoiceBankData,
        displayBank: Int,
        sourceIndex: Int,
        destinationIndex: Int,
        systemChannel: Int,
        progress: (@Sendable (FB01VoiceBankStoreEvent) async -> Void)? = nil
    ) async throws -> FB01VoiceBankData {
        let targetBank = try retargetedVoiceBank(voiceBank, displayBank: displayBank)

        await progress?(.turningProtectOff)
        let protectOff = try FB01SysExMessage.command(.setMemoryProtect(systemChannel: systemChannel, .off)).bytes
        try await Task.detached(priority: .userInitiated) {
            try FB01MIDI.sendSysEx([protectOff], destinationIndex: destinationIndex, delayBetweenMessages: 0)
        }.value
        try await Task.sleep(for: .milliseconds(300))
        try Task.checkCancellation()

        await progress?(.storingBank)
        let requestKind = try FB01DeviceService.shared.requestKind(forDisplayBank: displayBank)
        var readback = try await fetchReadbackVoiceBank(
            requestKind: requestKind,
            expectedDisplayBank: displayBank,
            sourceIndex: sourceIndex,
            destinationIndex: destinationIndex,
            systemChannel: systemChannel
        )
        var pass = 0

        while readback.data != targetBank.data {
            try Task.checkCancellation()
            pass += 1
            guard pass <= 60 else {
                throw FB01VoiceStoreError.bankVerificationFailed(bank: displayBank)
            }

            let loadMessage = try voiceBankLoadMessage(bank: targetBank, systemChannel: systemChannel)
            try await Task.detached(priority: .userInitiated) {
                try FB01MIDI.sendLongSysEx(loadMessage, destinationIndex: destinationIndex, timeout: 45)
            }.value
            try Task.checkCancellation()

            await progress?(.verifyingBank)
            readback = try await fetchReadbackVoiceBank(
                requestKind: requestKind,
                expectedDisplayBank: displayBank,
                sourceIndex: sourceIndex,
                destinationIndex: destinationIndex,
                systemChannel: systemChannel
            )
        }

        return readback
    }

    private func fetchReadbackVoiceBank(
        requestKind: FB01MIDIRequestKind,
        expectedDisplayBank: Int,
        sourceIndex: Int,
        destinationIndex: Int,
        systemChannel: Int
    ) async throws -> FB01VoiceBankData {
        let readbackBytes = try await Task.detached(priority: .userInitiated) {
            try await Task.sleep(for: .milliseconds(1500))
            return try FB01MIDI.request(
                requestKind,
                sourceIndex: sourceIndex,
                destinationIndex: destinationIndex,
                systemChannel: systemChannel,
                timeout: 15
            )
        }.value
        return try voiceBankData(from: readbackBytes, expectedDisplayBank: expectedDisplayBank)
    }

    public func storeVoiceInBankImage(
        _ voice: FB01VoiceData,
        displayBank: Int,
        zeroBasedVoiceNumber: Int,
        initialBankDumpBytes: [UInt8],
        sourceIndex: Int,
        destinationIndex: Int,
        systemChannel: Int,
        maximumPasses: Int = 60,
        sendProtectOff: Bool = true,
        progress: (@Sendable (FB01VoiceBankImageStoreEvent) async -> Void)? = nil
    ) async throws -> FB01VoiceBankData {
        guard (0..<module.voicesPerBank).contains(zeroBasedVoiceNumber) else {
            throw FB01SysExError.valueOutOfRange(
                name: "voiceNumber",
                value: zeroBasedVoiceNumber,
                range: 0...(module.voicesPerBank - 1)
            )
        }

        let voiceNumber = zeroBasedVoiceNumber + 1
        var readback = try voiceBankData(from: initialBankDumpBytes, expectedDisplayBank: displayBank)

        if sendProtectOff {
            await progress?(.turningProtectOff)
            let protectOff = try FB01SysExMessage.command(.setMemoryProtect(systemChannel: systemChannel, .off)).bytes
            try await Task.detached(priority: .userInitiated) {
                try FB01MIDI.sendSysEx([protectOff], destinationIndex: destinationIndex, delayBetweenMessages: 0)
            }.value
            try await Task.sleep(for: .milliseconds(300))
        }

        var pass = 0
        while readback.voices[zeroBasedVoiceNumber].voice.bytes != voice.bytes {
            try Task.checkCancellation()
            pass += 1
            guard pass <= maximumPasses else {
                throw FB01VoiceStoreError.verificationFailed(
                    bank: displayBank,
                    voiceNumber: voiceNumber,
                    maximumPasses: maximumPasses
                )
            }

            await progress?(.storePass(pass))
            let editedBank = try readback.replacingVoices([voiceNumber: voice])
            let loadMessage = try voiceBankLoadMessage(bank: editedBank, systemChannel: systemChannel)
            let requestKind = try FB01DeviceService.shared.requestKind(forDisplayBank: displayBank)
            let nextReadbackBytes = try await Task.detached(priority: .userInitiated) {
                try FB01MIDI.sendLongSysEx(loadMessage, destinationIndex: destinationIndex, timeout: 45)
                try await Task.sleep(for: .milliseconds(1500))
                return try FB01MIDI.request(
                    requestKind,
                    sourceIndex: sourceIndex,
                    destinationIndex: destinationIndex,
                    systemChannel: systemChannel,
                    timeout: 15
                )
            }.value
            readback = try voiceBankData(from: nextReadbackBytes, expectedDisplayBank: displayBank)
        }

        return readback
    }

    public func storeCurrentInstrumentVoiceMessages(
        voice: FB01VoiceData,
        systemChannel: Int,
        instrument: Int,
        voiceSlot: Int
    ) throws -> [[UInt8]] {
        let protectOffCommand = FB01SysExMessage.command(.setMemoryProtect(systemChannel: systemChannel, .off))
        let voiceMessage = try voice.instrumentVoiceArtifact(systemChannel: systemChannel, instrument: instrument).messages[0]
        let storeCommand = FB01SysExMessage.command(.storeCurrentInstrumentVoice(
            systemChannel: systemChannel,
            instrument: instrument,
            voiceNumber: voiceSlot
        ))
        return try [protectOffCommand.bytes, voiceMessage.bytes, storeCommand.bytes]
    }

    public func auditionPreparationMessages(voice: FB01VoiceData, systemChannel: Int, midiChannel: Int) throws -> [[UInt8]] {
        let artifact = try voice.instrumentVoiceArtifact(systemChannel: systemChannel, instrument: 0)
        return [try artifact.sysexBytes] + (try keyboardAuditionPreparationMessages(systemChannel: systemChannel, midiChannel: midiChannel))
    }

    public func keyboardAuditionPreparationMessages(systemChannel: Int, midiChannel: Int) throws -> [[UInt8]] {
        var messages: [[UInt8]] = []

        for instrument in 1..<FB01ConfigurationData.instrumentCount {
            messages.append(try FB01SysExMessage.command(.instrumentParameterChange(
                systemChannel: systemChannel,
                instrument: instrument,
                parameter: FB01InstrumentParameter.noteCount,
                value: .oneByte(0)
            )).bytes)
        }

        messages += [
            try FB01SysExMessage.command(.instrumentParameterChange(
                systemChannel: systemChannel,
                instrument: 0,
                parameter: FB01InstrumentParameter.noteCount,
                value: .oneByte(8)
            )).bytes,
            try FB01SysExMessage.command(.instrumentParameterChange(
                systemChannel: systemChannel,
                instrument: 0,
                parameter: FB01InstrumentParameter.midiChannel,
                value: .oneByte(UInt8(min(max(midiChannel, 0), 15)))
            )).bytes,
            try FB01SysExMessage.command(.instrumentParameterChange(
                systemChannel: systemChannel,
                instrument: 0,
                parameter: FB01InstrumentParameter.highKeyLimit,
                value: .oneByte(127)
            )).bytes,
            try FB01SysExMessage.command(.instrumentParameterChange(
                systemChannel: systemChannel,
                instrument: 0,
                parameter: FB01InstrumentParameter.lowKeyLimit,
                value: .oneByte(0)
            )).bytes,
            try FB01SysExMessage.command(.instrumentParameterChange(
                systemChannel: systemChannel,
                instrument: 0,
                parameter: FB01InstrumentParameter.outputLevel,
                value: .oneByte(127)
            )).bytes,
        ]

        return messages
    }
}

import FB01Editor
import Foundation

struct EditorFetchedVoiceDocument: Sendable {
    var neutralVoice: FourOperatorVoiceData
    var projectionOverlay: FB01VoiceProjectionOverlay
    var systemChannel: Int
    var title: String
    var sourceDevice: EditorDeviceSelection
}

enum EditorVoiceDocumentService {
    enum DX100InternalStoreProgress: Sendable {
        case preparingBank
        case sendingBank(slotIndex: Int)
        case verifying(slotIndex: Int)
    }

    static func prepareDX100AssistedDeviceVoiceRecall(
        bank: Int,
        voiceNumber: Int,
        destinationIndex: Int,
        systemChannel: Int,
        selectionDelay: TimeInterval = 0.35,
        releaseDelay: TimeInterval = 0.1
    ) throws {
        let playSwitch = 27
        let bankSwitchMap = [1: 28, 2: 29, 3: 30, 4: 31]
        guard let bankSwitch = bankSwitchMap[bank] else {
            throw EditorVoiceDocumentServiceError.unsupportedRecentVoiceFetchForDevice(.dx100)
        }

        try sendDX100SwitchPress(
            switchNumber: playSwitch,
            destinationIndex: destinationIndex,
            systemChannel: systemChannel,
            releaseDelay: releaseDelay
        )
        Thread.sleep(forTimeInterval: selectionDelay)

        try sendDX100SwitchPress(
            switchNumber: bankSwitch,
            destinationIndex: destinationIndex,
            systemChannel: systemChannel,
            releaseDelay: releaseDelay
        )
        Thread.sleep(forTimeInterval: selectionDelay)

        try sendDX100SwitchPress(
            switchNumber: voiceNumber,
            destinationIndex: destinationIndex,
            systemChannel: systemChannel,
            releaseDelay: releaseDelay
        )
        Thread.sleep(forTimeInterval: selectionDelay)
    }

    static func prepareDX100AssistedCurrentBankVoiceRecall(
        voiceNumber: Int,
        destinationIndex: Int,
        systemChannel: Int,
        playFirst: Bool = true,
        selectionDelay: TimeInterval = 0.35,
        releaseDelay: TimeInterval = 0.1
    ) throws {
        if playFirst {
            try sendDX100SwitchPress(
                switchNumber: 27,
                destinationIndex: destinationIndex,
                systemChannel: systemChannel,
                releaseDelay: releaseDelay
            )
            Thread.sleep(forTimeInterval: selectionDelay)
        }

        try sendDX100SwitchPress(
            switchNumber: voiceNumber,
            destinationIndex: destinationIndex,
            systemChannel: systemChannel,
            releaseDelay: releaseDelay
        )
        Thread.sleep(forTimeInterval: selectionDelay)
    }

    static func fetchDX100CurrentVoice(
        sourceIndex: Int,
        destinationIndex: Int,
        systemChannel: Int,
        timeout: Double = 8
    ) throws -> DX100FetchedVoice {
        let request = try DX100ModuleServices.shared.voiceService.singleVoiceDumpRequest(channel: systemChannel)
        let messages = try FB01MIDI.sendAndReceive(
            [request],
            sourceIndex: sourceIndex,
            destinationIndex: destinationIndex,
            timeout: timeout,
            maxMessages: 1,
            delayBetweenMessages: 0.05
        )
        return try DX100ModuleServices.shared.voiceService.currentVoice(from: messages)
    }

    static func fetchDX100InternalBank(
        sourceIndex: Int,
        destinationIndex: Int,
        systemChannel: Int,
        timeout: Double = 10,
        attempts: Int = 3,
        preflightDelay: TimeInterval = 0.35
    ) throws -> DX100VoiceBankData {
        let request = try DX100ModuleServices.shared.voiceService.voiceBankDumpRequest(channel: systemChannel)
        let currentVoiceRequest = try DX100ModuleServices.shared.voiceService.singleVoiceDumpRequest(channel: systemChannel)
        var lastError: Error?
        let preflightDelays: [TimeInterval] = [preflightDelay, max(preflightDelay, 0.6), max(preflightDelay, 1.0)]

        for attemptIndex in 0..<max(1, attempts) {
            do {
                try sendDX100SwitchPress(
                    switchNumber: 27,
                    destinationIndex: destinationIndex,
                    systemChannel: systemChannel,
                    releaseDelay: 0.1
                )
                let attemptDelay = attemptIndex < preflightDelays.count ? preflightDelays[attemptIndex] : preflightDelays.last!
                Thread.sleep(forTimeInterval: attemptDelay)

                // A successful single-voice SysEx round trip often "primes" the DX100's
                // receive/transmit state before asking for the larger 32-voice bulk dump.
                _ = try? FB01MIDI.sendAndReceive(
                    [currentVoiceRequest],
                    sourceIndex: sourceIndex,
                    destinationIndex: destinationIndex,
                    timeout: min(timeout, 2.0),
                    maxMessages: 1,
                    delayBetweenMessages: 0
                )
                Thread.sleep(forTimeInterval: 0.12)

                let responseMessages = try FB01MIDI.sendAndReceive(
                    [request],
                    sourceIndex: sourceIndex,
                    destinationIndex: destinationIndex,
                    timeout: timeout,
                    maxMessages: 1,
                    delayBetweenMessages: 0
                )
                guard let response = responseMessages.first else {
                    throw FB01MIDIError.timedOut("DX100 Internal bank")
                }
                return try DX100ModuleServices.shared.voiceService.voiceBank(fromThirtyTwoVoiceBulkSysEx: response)
            } catch {
                lastError = error
                try? recoverDX100PlayMode(
                    destinationIndex: destinationIndex,
                    systemChannel: systemChannel,
                    settleDelay: 0.1
                )
                Thread.sleep(forTimeInterval: 0.25)
            }
        }

        throw lastError ?? FB01MIDIError.timedOut("DX100 Internal bank")
    }

    static func receiveDX100InternalBankManually(
        sourceIndex: Int,
        timeout: Double = 25
    ) throws -> DX100VoiceBankData {
        let responseMessages = try FB01MIDI.receiveSysEx(
            sourceIndex: sourceIndex,
            timeout: timeout,
            maxMessages: 1
        )
        guard let response = responseMessages.first else {
            throw FB01MIDIError.timedOut("manual DX100 Internal bank")
        }
        return try DX100ModuleServices.shared.voiceService.voiceBank(fromThirtyTwoVoiceBulkSysEx: response)
    }

    static func fetchDX100DeviceVoice(
        bank: Int,
        voiceNumber: Int,
        sourceIndex: Int,
        destinationIndex: Int,
        systemChannel: Int
    ) throws -> DX100FetchedVoice {
        guard let bankKind = DX100ModuleServices.shared.module.voiceBankKind(displayBank: bank) else {
            throw EditorVoiceDocumentServiceError.unsupportedRecentVoiceFetchForDevice(.dx100)
        }

        let request = try DX100ModuleServices.shared.voiceService.singleVoiceDumpRequest(channel: systemChannel)
        let selectionAttempts: [[UInt8]]
        switch bankKind {
        case .internalRAM:
            guard let programNumber = bankKind.programNumber(forVoiceIndex: voiceNumber) else {
                throw EditorVoiceDocumentServiceError.unsupportedRecentVoiceFetchForDevice(.dx100)
            }
            selectionAttempts = [
                try dx100ProgramChangeMessage(channel: systemChannel, programNumber: programNumber),
            ]
        case .bankMemory:
            guard let bankVoiceNumber = bankKind.bankVoiceNumber(forVoiceIndex: voiceNumber) else {
                throw EditorVoiceDocumentServiceError.unsupportedRecentVoiceFetchForDevice(.dx100)
            }
            selectionAttempts = [
                try DX100.parameterChange(channel: systemChannel, parameter: 126, data: bankVoiceNumber),
                try dx100ProgramChangeMessage(channel: systemChannel, programNumber: 24 + bankVoiceNumber),
            ]
        case .preset:
            throw EditorVoiceDocumentServiceError.unsupportedRecentVoiceFetchForDevice(.dx100)
        }

        var lastError: Error?
        for selection in selectionAttempts {
            do {
                let messages = try FB01MIDI.sendAndReceive(
                    [selection, request],
                    sourceIndex: sourceIndex,
                    destinationIndex: destinationIndex,
                    timeout: 8,
                    maxMessages: 1,
                    delayBetweenMessages: 0.6
                )
                return try DX100ModuleServices.shared.voiceService.currentVoice(from: messages)
            } catch {
                lastError = error
            }
        }

        throw lastError ?? FB01MIDIError.timedOut("DX100 bank voice")
    }

    static func fetchVoiceDocument(
        for device: EditorDeviceSelection,
        source: VoiceDocumentFetchSource?,
        sourceIndex: Int,
        destinationIndex: Int,
        systemChannel: Int,
        documentModel _: DocumentModel,
        recentTitle: String? = nil
    ) throws -> EditorFetchedVoiceDocument {
        switch device {
        case .fb01:
            let resolvedSource = source ?? .instrument(0)
            let result = try FB01VoiceDocumentService.fetchVoice(
                source: resolvedSource,
                sourceIndex: sourceIndex,
                destinationIndex: destinationIndex,
                systemChannel: systemChannel
            )
            return EditorFetchedVoiceDocument(
                neutralVoice: result.voice.fourOperatorVoice,
                projectionOverlay: FB01VoiceProjectionOverlay(voice: result.voice),
                systemChannel: result.systemChannel,
                title: recentTitle ?? resolvedSource.title(),
                sourceDevice: .fb01
            )
        case .dx100:
            switch source {
            case nil, .some(.currentVoice), .some(.instrument):
                let fetched = try fetchDX100CurrentVoice(
                    sourceIndex: sourceIndex,
                    destinationIndex: destinationIndex,
                    systemChannel: systemChannel
                )
                return EditorFetchedVoiceDocument(
                    neutralVoice: fetched.voice.fourOperatorVoice,
                    projectionOverlay: try EditorVoiceProjectionBridge.loadedDocument(from: fetched.voice, channel: fetched.channel).projectionOverlay,
                    systemChannel: fetched.channel,
                    title: recentTitle ?? fetched.title,
                    sourceDevice: .dx100
                )
            case .some(.dx100Bank(let bank, let voiceNumber)):
                let fetched = try fetchDX100DeviceVoice(
                    bank: bank,
                    voiceNumber: voiceNumber,
                    sourceIndex: sourceIndex,
                    destinationIndex: destinationIndex,
                    systemChannel: systemChannel
                )
                let dxVoice = fetched.voice
                let voiceName = dxVoice.name.isEmpty ? "Untitled" : dxVoice.name
                let bankTitle = DX100ModuleServices.shared.module.voiceBankKind(displayBank: bank)?.displayName ?? "Bank \(bank)"
                return EditorFetchedVoiceDocument(
                    neutralVoice: dxVoice.fourOperatorVoice,
                    projectionOverlay: try EditorVoiceProjectionBridge.loadedDocument(from: dxVoice, channel: fetched.channel).projectionOverlay,
                    systemChannel: fetched.channel,
                    title: recentTitle ?? "DX100 \(bankTitle) Voice \(voiceNumber + 1): \(voiceName)",
                    sourceDevice: .dx100
                )
            case .some(.storedSlot):
                throw EditorVoiceDocumentServiceError.unsupportedRecentVoiceFetchForDevice(.dx100)
            }
        }
    }

    static func storeVoiceDocument(
        _ voice: FourOperatorVoiceData,
        to device: EditorDeviceSelection,
        sourceIndex: Int,
        destinationIndex: Int,
        systemChannel: Int
    ) throws {
        switch device {
        case .fb01:
            preconditionFailure("FB-01 voice bank store remains in VoiceDocumentModel for now.")
        case .dx100:
            let translated = try voice.dx100Voice()
            let messages = try DX100ModuleServices.shared.voiceService.editBufferMessages(for: translated, channel: systemChannel)
            _ = try FB01MIDI.sendAndReceive(
                messages + [try DX100ModuleServices.shared.voiceService.singleVoiceDumpRequest(channel: systemChannel)],
                sourceIndex: sourceIndex,
                destinationIndex: destinationIndex,
                timeout: 8,
                maxMessages: 1,
                delayBetweenMessages: 0.05
            )
        }
    }

    static func writeDX100VoiceInInternalBank(
        _ voice: FourOperatorVoiceData,
        slotIndex: Int,
        destinationIndex: Int,
        systemChannel: Int,
        currentBank: DX100VoiceBankData,
        settleDelay: TimeInterval = 0.4,
        progress: (@Sendable (DX100InternalStoreProgress) -> Void)? = nil
    ) throws {
        progress?(.preparingBank)
        let translatedVoice = try voice.dx100Voice()
        let updatedBank = try currentBank.replacingVoice(atPackedVoiceIndex: slotIndex, with: translatedVoice)
        let messages = try DX100ModuleServices.shared.voiceService.voiceBankMessages(
            for: updatedBank,
            channel: systemChannel
        )
        guard let loadMessage = messages.first else {
            throw FB01AppError.message("Forest could not build a DX100 Internal bank store message.")
        }

        try sendDX100SwitchPress(
            switchNumber: 27,
            destinationIndex: destinationIndex,
            systemChannel: systemChannel,
            releaseDelay: 0.1
        )
        Thread.sleep(forTimeInterval: 0.35)

        progress?(.sendingBank(slotIndex: slotIndex))
        try FB01MIDI.sendLongSysEx(loadMessage, destinationIndex: destinationIndex, timeout: 45)
        if settleDelay > 0 {
            Thread.sleep(forTimeInterval: settleDelay)
        }
    }

    static func writeDX100InternalBank(
        _ bank: DX100VoiceBankData,
        destinationIndex: Int,
        systemChannel: Int,
        settleDelay: TimeInterval = 0.4
    ) throws {
        let messages = try DX100ModuleServices.shared.voiceService.voiceBankMessages(
            for: bank,
            channel: systemChannel
        )
        guard let loadMessage = messages.first else {
            throw FB01AppError.message("Forest could not build a DX100 Internal bank store message.")
        }

        try sendDX100SwitchPress(
            switchNumber: 27,
            destinationIndex: destinationIndex,
            systemChannel: systemChannel,
            releaseDelay: 0.1
        )
        Thread.sleep(forTimeInterval: 0.35)

        try FB01MIDI.sendLongSysEx(loadMessage, destinationIndex: destinationIndex, timeout: 45)
        if settleDelay > 0 {
            Thread.sleep(forTimeInterval: settleDelay)
        }
    }

    static func recoverDX100PlayMode(
        destinationIndex: Int,
        systemChannel: Int,
        settleDelay: TimeInterval = 0.2
    ) throws {
        try sendDX100SwitchPress(
            switchNumber: 27,
            destinationIndex: destinationIndex,
            systemChannel: systemChannel,
            releaseDelay: 0.1
        )
        if settleDelay > 0 {
            Thread.sleep(forTimeInterval: settleDelay)
        }
    }

    private static func dx100ProgramChangeMessage(channel: Int, programNumber: Int) throws -> [UInt8] {
        guard (0...15).contains(channel) else {
            throw DX100SysExError.invalidChannel(channel)
        }
        guard (0...127).contains(programNumber) else {
            throw FB01MIDIError.timedOut("DX100 program selection")
        }
        return [0xC0 | UInt8(channel), UInt8(programNumber)]
    }

    private static func sendDX100SwitchPress(
        switchNumber: Int,
        destinationIndex: Int,
        systemChannel: Int,
        releaseDelay: TimeInterval
    ) throws {
        let pressBytes = try DX100.switchModeMessage(channel: systemChannel, switchNumber: switchNumber, value: 127)
        let releaseBytes = try DX100.switchModeMessage(channel: systemChannel, switchNumber: switchNumber, value: 0)
        try FB01MIDI.sendImmediate(pressBytes, destinationIndex: destinationIndex)
        Thread.sleep(forTimeInterval: releaseDelay)
        try FB01MIDI.sendImmediate(releaseBytes, destinationIndex: destinationIndex)
    }
}

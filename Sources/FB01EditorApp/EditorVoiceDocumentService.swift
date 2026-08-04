import FB01Editor
import Foundation

enum EditorVoiceDocumentServiceError: Error, CustomStringConvertible {
    case unsupportedRecentVoiceFetchForDevice(EditorDeviceSelection)

    var description: String {
        switch self {
        case .unsupportedRecentVoiceFetchForDevice(let device):
            return "\(device.displayName) does not yet support that stored-voice fetch path."
        }
    }
}

struct EditorFetchedVoiceDocument: Sendable {
    var neutralVoice: FourOperatorVoiceData
    var voice: FB01VoiceData
    var systemChannel: Int
    var title: String
    var sourceDevice: EditorDeviceSelection
}

enum EditorVoiceDocumentService {
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
                voice: result.voice,
                systemChannel: result.systemChannel,
                title: recentTitle ?? resolvedSource.title(),
                sourceDevice: .fb01
            )
        case .dx100:
            switch source {
            case nil, .some(.currentVoice), .some(.instrument):
                let request = try DX100ModuleServices.shared.voiceService.singleVoiceDumpRequest(channel: systemChannel)
                let messages = try FB01MIDI.sendAndReceive(
                    [request],
                    sourceIndex: sourceIndex,
                    destinationIndex: destinationIndex,
                    timeout: 8,
                    maxMessages: 1,
                    delayBetweenMessages: 0.05
                )
                let fetched = try DX100ModuleServices.shared.voiceService.currentVoice(from: messages)
                return EditorFetchedVoiceDocument(
                    neutralVoice: fetched.voice.fourOperatorVoice,
                    voice: try fetched.voice.fb01EditableVoice(),
                    systemChannel: fetched.channel,
                    title: recentTitle ?? fetched.title,
                    sourceDevice: .dx100
                )
            case .some(.dx100Bank(_, let voiceNumber)):
                let request = try DX100ModuleServices.shared.voiceService.voiceBankDumpRequest(channel: systemChannel)
                let messages = try FB01MIDI.sendAndReceive(
                    [request],
                    sourceIndex: sourceIndex,
                    destinationIndex: destinationIndex,
                    timeout: 8,
                    maxMessages: 1,
                    delayBetweenMessages: 0.05
                )
                guard let bankBytes = messages.first else {
                    throw FB01MIDIError.timedOut("DX100/27 voice bank")
                }
                let bank = try DX100ModuleServices.shared.voiceService.voiceBank(fromThirtyTwoVoiceBulkSysEx: bankBytes)
                let dxVoice = try bank.voice(atPackedVoiceIndex: voiceNumber)
                let voiceName = dxVoice.name.isEmpty ? "Untitled" : dxVoice.name
                return EditorFetchedVoiceDocument(
                    neutralVoice: dxVoice.fourOperatorVoice,
                    voice: try dxVoice.fb01EditableVoice(),
                    systemChannel: bank.channel,
                    title: recentTitle ?? "DX100/27 Bank 1 Voice \(voiceNumber + 1): \(voiceName)",
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
}

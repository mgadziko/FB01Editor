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
                voice: result.voice,
                systemChannel: result.systemChannel,
                title: recentTitle ?? resolvedSource.title(),
                sourceDevice: .fb01
            )
        case .dx100:
            guard source == nil || source?.isDX100CurrentVoiceCompatible == true else {
                throw EditorVoiceDocumentServiceError.unsupportedRecentVoiceFetchForDevice(.dx100)
            }
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
                voice: try fetched.voice.fb01EditableVoice(),
                systemChannel: fetched.channel,
                title: recentTitle ?? fetched.title,
                sourceDevice: .dx100
            )
        }
    }

    static func storeVoiceDocument(
        _ voice: FB01VoiceData,
        to device: EditorDeviceSelection,
        sourceIndex: Int,
        destinationIndex: Int,
        systemChannel: Int
    ) throws {
        switch device {
        case .fb01:
            preconditionFailure("FB-01 voice bank store remains in VoiceDocumentModel for now.")
        case .dx100:
            let translated = try voice.dx100EditableVoice()
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

private extension VoiceDocumentFetchSource {
    var isDX100CurrentVoiceCompatible: Bool {
        if case .instrument = self {
            return true
        }
        return false
    }
}

private extension FB01VoiceData {
    func dx100EditableVoice() throws -> DX100VoiceData {
        var neutral = fourOperatorVoice
        neutral.sourceModelName = "DX100"
        neutral.name = String(name.prefix(DX100VoiceData.nameLength))
        neutral.operators = neutral.operators.map { op in
            FourOperatorVoiceOperatorData(
                operatorNumber: op.operatorNumber,
                isCarrier: op.isCarrier,
                totalLevel: min(op.totalLevel, 99),
                frequencyValue: min(op.frequencyValue, 63),
                detune: min(max(op.detune - 3, -3), 3),
                keyboardLevelScalingDepth: min(op.keyboardLevelScalingDepth, 99),
                keyboardRateScalingDepth: min(op.keyboardRateScalingDepth, 3),
                velocityToTotalLevel: op.velocityToTotalLevel,
                velocityToAttack: op.velocityToAttack,
                amplitudeModulationEnabled: op.amplitudeModulationEnabled,
                attack: op.attack,
                decay1: op.decay1,
                decay2: op.decay2,
                sustain: op.sustain,
                release: op.release
            )
        }
        return try neutral.dx100Voice()
    }
}

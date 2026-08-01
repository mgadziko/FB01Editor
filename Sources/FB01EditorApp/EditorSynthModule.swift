import FB01Editor
import Foundation

enum ActiveSynthModule {
    case fb01

    static let current = ActiveSynthModule.fb01

    var adapter: FB01ModuleAdapter {
        switch self {
        case .fb01:
            return .shared
        }
    }
}

enum EditorSynthModule {
    static var adapter: FB01ModuleAdapter {
        ActiveSynthModule.current.adapter
    }

    static var module: FB01SynthModule {
        adapter.module
    }

    static var identity: SynthModuleIdentity {
        adapter.identity
    }

    static var capabilities: SynthModuleCapabilities {
        adapter.capabilities
    }

    static var vocabulary: SynthModuleVocabulary {
        module.vocabulary
    }

    static var supportedDocumentDescriptors: [SynthDocumentDescriptor] {
        module.supportedDocumentDescriptors
    }

    static var commandDescriptors: [SynthModuleCommandDescriptor] {
        module.commandDescriptors
    }

    static var fileProfile: SynthFileProfile {
        module.fileProfile
    }

    static var documentService: FB01DocumentService {
        adapter.services.documentService
    }

    static func documentDescriptor(for kind: SynthDocumentKind) -> SynthDocumentDescriptor? {
        supportedDocumentDescriptors.first { $0.kind == kind }
    }

    static func commandDescriptor(for kind: SynthModuleCommandKind) -> SynthModuleCommandDescriptor? {
        commandDescriptors.first { $0.kind == kind }
    }
}

enum EditorFeatureAvailability {
    static func supportsCommand(_ kind: SynthModuleCommandKind) -> Bool {
        EditorSynthModule.commandDescriptor(for: kind) != nil
    }

    static func commandTitle(_ kind: SynthModuleCommandKind, fallback: String) -> String {
        EditorSynthModule.commandDescriptor(for: kind)?.displayName ?? fallback
    }
}

@MainActor
enum EditorModuleCommandRunner {
    static func run(_ kind: SynthModuleCommandKind, document: DocumentModel) {
        switch kind {
        case .resetInstructions:
            document.resetDeviceToFactorySettings()
        case .copyVoiceToSlot:
            document.copySelectedVoiceToLocalSlot()
        case .swapVoiceWithSlot:
            document.swapSelectedVoiceWithLocalSlot()
        case .resetSelectedVoice:
            document.resetSelectedVoiceEdit()
        case .resetAllVoiceEdits:
            document.resetAllSelectedVoiceEdits()
        case .saveEditedVoiceBank:
            document.saveSelectedEditedVoiceBankAs()
        case .storeGeneralMIDIVoices:
            document.storeGeneralMIDIVoicesToDevice()
        case .copyConfigurationToSlot:
            document.copyConfigurationSlotOnDevice()
        case .refreshDeviceCache:
            document.refreshDeviceCache(reason: "Refreshing device cache")
        case .sendSelectedConfigurationToEditBuffer:
            document.sendSelectedConfigurationToCurrentEditBuffer()
        case .sendAndConfirmSelectedConfiguration:
            document.sendAndConfirmSelectedConfigurationToCurrentEditBuffer()
        case .storeSelectedConfigurationToSlot:
            document.storeSelectedConfigurationToDeviceSlot()
        case .storeAndConfirmSelectedConfiguration:
            document.storeAndConfirmSelectedConfigurationToDeviceSlot()
        }
    }
}

enum EditorModuleDocumentFiles {
    static func voiceCandidates(from url: URL) throws -> [VoiceDocumentCandidate] {
        try EditorSynthModule.documentService.readVoiceCandidates(from: url).map { candidate in
            VoiceDocumentCandidate(
                title: candidate.title,
                payload: SynthVoiceDocumentPayload(
                    moduleIdentity: EditorSynthModule.identity,
                    voice: candidate.voice,
                    systemChannel: candidate.systemChannel
                )
            )
        }
    }

    static func configurationCandidates(from url: URL) throws -> [ConfigurationDocumentCandidate] {
        try EditorSynthModule.documentService.readConfigurationCandidates(from: url).map { candidate in
            ConfigurationDocumentCandidate(
                title: candidate.title,
                payload: SynthConfigurationDocumentPayload(
                    moduleIdentity: EditorSynthModule.identity,
                    configuration: candidate.configuration,
                    systemChannel: candidate.systemChannel
                )
            )
        }
    }

    static func writeVoice(_ voice: FB01VoiceData, systemChannel: Int, to url: URL) throws {
        try EditorSynthModule.documentService.writeVoice(voice, systemChannel: systemChannel, to: url)
    }

    static func writeConfiguration(_ configuration: FB01ConfigurationData, systemChannel: Int, to url: URL) throws {
        try EditorSynthModule.documentService.writeConfiguration(configuration, systemChannel: systemChannel, to: url)
    }
}

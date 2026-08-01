import FB01Editor
import Foundation

struct SynthVoiceDocumentPayload<Voice: Sendable>: SynthVoiceDocumentPayloadProtocol {
    var moduleIdentity: SynthModuleIdentity
    var voice: Voice
    var systemChannel: Int
}

struct SynthConfigurationDocumentPayload<Configuration: Sendable>: SynthConfigurationDocumentPayloadProtocol {
    var moduleIdentity: SynthModuleIdentity
    var configuration: Configuration
    var systemChannel: Int
}

struct VoiceDocumentCandidate: Sendable {
    var title: String
    var payload: SynthVoiceDocumentPayload<FB01VoiceData>

    var voice: FB01VoiceData { payload.voice }
    var systemChannel: Int { payload.systemChannel }
}

struct ConfigurationDocumentCandidate: Sendable {
    var title: String
    var payload: SynthConfigurationDocumentPayload<FB01ConfigurationData>

    var configuration: FB01ConfigurationData { payload.configuration }
    var systemChannel: Int { payload.systemChannel }
}

enum EditorDocumentExtraction {
    static func voiceCandidates(from artifact: FB01Artifact) throws -> [VoiceDocumentCandidate] {
        try FB01ModuleServices.shared.documentService.voiceCandidates(from: artifact).map { candidate in
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

    static func configurationCandidates(from artifact: FB01Artifact) throws -> [ConfigurationDocumentCandidate] {
        try FB01ModuleServices.shared.documentService.configurationCandidates(from: artifact).map { candidate in
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
}

import FB01Editor
import Foundation

struct VoiceDocumentCandidate: Sendable {
    var title: String
    var voice: FB01VoiceData
    var systemChannel: Int
}

struct ConfigurationDocumentCandidate: Sendable {
    var title: String
    var configuration: FB01ConfigurationData
    var systemChannel: Int
}

enum EditorDocumentExtraction {
    static func voiceCandidates(from artifact: FB01Artifact) throws -> [VoiceDocumentCandidate] {
        var candidates: [VoiceDocumentCandidate] = []
        for message in artifact.messages {
            switch message {
            case let .instrumentVoiceDump(systemChannel, instrument, packet):
                let voice = try FB01VoiceData(bytes: FB01.nibbleDecode(packet.payload))
                candidates.append(VoiceDocumentCandidate(
                    title: "Instrument \(instrument + 1): \(voice.name.isEmpty ? "Untitled" : voice.name)",
                    voice: voice,
                    systemChannel: systemChannel
                ))
            case let .voiceRAMDumpData(systemChannel, _, data, _):
                let bank = try FB01VoiceBankData(bank: 0, data: data)
                for summary in bank.voices {
                    candidates.append(VoiceDocumentCandidate(
                        title: "Voice RAM 1 Voice \(summary.number): \(summary.voice.name.isEmpty ? "Untitled" : summary.voice.name)",
                        voice: summary.voice,
                        systemChannel: systemChannel
                    ))
                }
            case let .voiceBankDumpData(systemChannel, bankNumber, _, data, _):
                let bank = try FB01VoiceBankData(bank: bankNumber, data: data)
                for summary in bank.voices {
                    candidates.append(VoiceDocumentCandidate(
                        title: "Bank \(bankNumber + 1) Voice \(summary.number): \(summary.voice.name.isEmpty ? "Untitled" : summary.voice.name)",
                        voice: summary.voice,
                        systemChannel: systemChannel
                    ))
                }
            default:
                break
            }
        }
        return candidates
    }

    static func configurationCandidates(from artifact: FB01Artifact) throws -> [ConfigurationDocumentCandidate] {
        var candidates: [ConfigurationDocumentCandidate] = []
        for message in artifact.messages {
            switch message {
            case let .currentConfigurationDump(systemChannel, packet):
                let configuration = try FB01ConfigurationData(bytes: packet.payload)
                candidates.append(ConfigurationDocumentCandidate(
                    title: "Current Configuration: \(configuration.name.isEmpty ? "Untitled" : configuration.name)",
                    configuration: configuration,
                    systemChannel: systemChannel
                ))
            case let .configurationDump(systemChannel, number, packet):
                let configuration = try FB01ConfigurationData(bytes: packet.payload)
                candidates.append(ConfigurationDocumentCandidate(
                    title: "Configuration \(number + 1): \(configuration.name.isEmpty ? "Untitled" : configuration.name)\(number >= 16 ? " Read Only" : "")",
                    configuration: configuration,
                    systemChannel: systemChannel
                ))
            default:
                break
            }
        }
        return candidates
    }
}

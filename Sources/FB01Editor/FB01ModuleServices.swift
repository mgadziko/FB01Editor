public struct FB01ModuleServices: SynthModuleServiceProviding {
    public typealias Module = FB01SynthModule

    public static let shared = FB01ModuleServices()

    public let module = FB01SynthModule.shared
    public let deviceService = FB01DeviceService.shared
    public let voiceService = FB01VoiceService.shared
    public let configurationService = FB01ConfigurationService.shared
    public let cacheService = FB01DeviceCacheService.shared
    public let documentService = FB01DocumentService.shared

    private init() {}
}

public struct FB01VoiceDocumentCandidate: Sendable {
    public var title: String
    public var voice: FB01VoiceData
    public var systemChannel: Int

    public init(title: String, voice: FB01VoiceData, systemChannel: Int) {
        self.title = title
        self.voice = voice
        self.systemChannel = systemChannel
    }
}

public struct FB01ConfigurationDocumentCandidate: Sendable {
    public var title: String
    public var configuration: FB01ConfigurationData
    public var systemChannel: Int

    public init(title: String, configuration: FB01ConfigurationData, systemChannel: Int) {
        self.title = title
        self.configuration = configuration
        self.systemChannel = systemChannel
    }
}

public struct FB01DocumentService: SynthDocumentTemplating, SynthDocumentExtracting {
    public typealias Voice = FB01VoiceData
    public typealias Configuration = FB01ConfigurationData
    public typealias Artifact = FB01Artifact
    public typealias VoiceCandidate = FB01VoiceDocumentCandidate
    public typealias ConfigurationCandidate = FB01ConfigurationDocumentCandidate

    public static let shared = FB01DocumentService()

    private init() {}

    public func templateVoice() throws -> FB01VoiceData {
        var voice = try FB01VoiceData(bytes: Array(repeating: 0, count: FB01VoiceData.byteCount))
        voice = try voice.settingName("Init")
        voice = try voice.settingLeftOutputEnabled(true)
        voice = try voice.settingRightOutputEnabled(true)
        return voice
    }

    public func templateConfiguration() throws -> FB01ConfigurationData {
        var configuration = try FB01ConfigurationData(bytes: Array(repeating: 0, count: FB01ConfigurationData.byteCount))
        configuration = try configuration.settingName("Init")
        return configuration
    }

    public func voiceCandidates(from artifact: FB01Artifact) throws -> [FB01VoiceDocumentCandidate] {
        var candidates: [FB01VoiceDocumentCandidate] = []
        for message in artifact.messages {
            switch message {
            case let .instrumentVoiceDump(systemChannel, instrument, packet):
                let voice = try FB01VoiceData(bytes: FB01.nibbleDecode(packet.payload))
                candidates.append(FB01VoiceDocumentCandidate(
                    title: "Instrument \(instrument + 1): \(voice.name.isEmpty ? "Untitled" : voice.name)",
                    voice: voice,
                    systemChannel: systemChannel
                ))
            case let .voiceRAMDumpData(systemChannel, _, data, _):
                let bank = try FB01VoiceBankData(bank: 0, data: data)
                for summary in bank.voices {
                    candidates.append(FB01VoiceDocumentCandidate(
                        title: "Voice RAM 1 Voice \(summary.number): \(summary.voice.name.isEmpty ? "Untitled" : summary.voice.name)",
                        voice: summary.voice,
                        systemChannel: systemChannel
                    ))
                }
            case let .voiceBankDumpData(systemChannel, bankNumber, _, data, _):
                let bank = try FB01VoiceBankData(bank: bankNumber, data: data)
                for summary in bank.voices {
                    candidates.append(FB01VoiceDocumentCandidate(
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

    public func configurationCandidates(from artifact: FB01Artifact) throws -> [FB01ConfigurationDocumentCandidate] {
        var candidates: [FB01ConfigurationDocumentCandidate] = []
        for message in artifact.messages {
            switch message {
            case let .currentConfigurationDump(systemChannel, packet):
                let configuration = try FB01ConfigurationData(bytes: packet.payload)
                candidates.append(FB01ConfigurationDocumentCandidate(
                    title: "Current Configuration: \(configuration.name.isEmpty ? "Untitled" : configuration.name)",
                    configuration: configuration,
                    systemChannel: systemChannel
                ))
            case let .configurationDump(systemChannel, number, packet):
                let configuration = try FB01ConfigurationData(bytes: packet.payload)
                let slot = number + 1
                let readOnly = FB01SynthModule.shared.isWritableConfigurationSlot(slot) ? "" : " Read Only"
                candidates.append(FB01ConfigurationDocumentCandidate(
                    title: "Configuration \(slot): \(configuration.name.isEmpty ? "Untitled" : configuration.name)\(readOnly)",
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

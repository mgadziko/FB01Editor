import Foundation

public enum FB01DeviceCacheEvent: Equatable, Sendable {
    case currentConfiguration
    case voiceBank(Int)
    case configuration(Int)
    case finishing
}

public struct FB01DeviceCacheResult: Sendable {
    public var voiceBanks: [Int: FB01VoiceBankData]
    public var configurations: [Int: FB01ConfigurationData]
    public var currentConfiguration: FB01ConfigurationData?
    public var failures: [String]

    public init(
        voiceBanks: [Int: FB01VoiceBankData] = [:],
        configurations: [Int: FB01ConfigurationData] = [:],
        currentConfiguration: FB01ConfigurationData? = nil,
        failures: [String] = []
    ) {
        self.voiceBanks = voiceBanks
        self.configurations = configurations
        self.currentConfiguration = currentConfiguration
        self.failures = failures
    }

    public var loadedCount: Int {
        voiceBanks.count + configurations.count + (currentConfiguration == nil ? 0 : 1)
    }
}

public struct FB01DeviceCacheFetchProfile: Sendable {
    public var voiceBankTimeout: TimeInterval
    public var configurationTimeout: TimeInterval
    public var currentConfigurationTimeout: TimeInterval
    public var otherTimeout: TimeInterval
    public var delayBetweenRequests: TimeInterval

    public init(
        voiceBankTimeout: TimeInterval,
        configurationTimeout: TimeInterval,
        currentConfigurationTimeout: TimeInterval,
        otherTimeout: TimeInterval,
        delayBetweenRequests: TimeInterval
    ) {
        self.voiceBankTimeout = voiceBankTimeout
        self.configurationTimeout = configurationTimeout
        self.currentConfigurationTimeout = currentConfigurationTimeout
        self.otherTimeout = otherTimeout
        self.delayBetweenRequests = delayBetweenRequests
    }

    public static let launch = FB01DeviceCacheFetchProfile(
        voiceBankTimeout: 4.0,
        configurationTimeout: 2.5,
        currentConfigurationTimeout: 2.5,
        otherTimeout: 2.0,
        delayBetweenRequests: 0.03
    )

    public static let selector = FB01DeviceCacheFetchProfile(
        voiceBankTimeout: 12.0,
        configurationTimeout: 4.0,
        currentConfigurationTimeout: 4.0,
        otherTimeout: 3.0,
        delayBetweenRequests: 0.05
    )

    public func timeout(for kind: FB01MIDIRequestKind) -> TimeInterval {
        switch kind {
        case .voiceBank:
            return voiceBankTimeout
        case .configuration:
            return configurationTimeout
        case .currentConfiguration:
            return currentConfigurationTimeout
        case .unitID, .instrumentVoice, .voiceRAM1:
            return otherTimeout
        }
    }
}

public struct FB01DeviceCacheService: SynthDeviceCacheServicing {
    public typealias CacheResult = FB01DeviceCacheResult
    public typealias CacheEvent = FB01DeviceCacheEvent

    public static let shared = FB01DeviceCacheService(
        module: .shared,
        voiceService: .shared,
        configurationService: .shared
    )

    public var module: FB01SynthModule
    public var voiceService: FB01VoiceService
    public var configurationService: FB01ConfigurationService

    public init(
        module: FB01SynthModule,
        voiceService: FB01VoiceService,
        configurationService: FB01ConfigurationService
    ) {
        self.module = module
        self.voiceService = voiceService
        self.configurationService = configurationService
    }

    public func totalRequestCount(voiceBanks: [Int], fetchConfigurations: Bool) -> Int {
        let configurationCount = module.fullDeviceCacheScope.configurationSlots?.count ?? 0
        let currentConfigurationCount = module.fullDeviceCacheScope.includesCurrentConfiguration ? 1 : 0
        return voiceBanks.count + (fetchConfigurations ? configurationCount + currentConfigurationCount : 0)
    }

    public func normalizedVoiceBanks(_ requestedVoiceBanks: [Int]) -> [Int] {
        Array(Set(requestedVoiceBanks))
            .filter { module.isValidVoiceBank($0) }
            .sorted()
    }

    public func fetch(
        voiceBanks requestedVoiceBanks: [Int],
        fetchConfigurations: Bool,
        sourceIndex: Int,
        destinationIndex: Int,
        systemChannel: Int,
        profile: FB01DeviceCacheFetchProfile = .launch,
        progress: (@Sendable (FB01DeviceCacheEvent, Double, Double) async -> Void)? = nil
    ) async -> FB01DeviceCacheResult {
        let voiceBanks = normalizedVoiceBanks(requestedVoiceBanks)
        let totalRequests = Double(totalRequestCount(voiceBanks: voiceBanks, fetchConfigurations: fetchConfigurations))
        var result = FB01DeviceCacheResult()
        var requestKinds: [FB01MIDIRequestKind] = []

        if fetchConfigurations {
            if module.fullDeviceCacheScope.includesCurrentConfiguration {
                requestKinds.append(.currentConfiguration)
            }
        }

        for bank in voiceBanks {
            requestKinds.append(.voiceBank(bank))
        }

        if fetchConfigurations {
            for slot in module.fullDeviceCacheScope.configurationSlots?.closedRange ?? module.allConfigurationSlots.closedRange {
                requestKinds.append(.configuration(slot))
            }
        }

        let batchResults = await Task.detached(priority: .userInitiated) {
            do {
                return try FB01MIDI.requestBatchAllowingFailures(
                    requestKinds,
                    sourceIndex: sourceIndex,
                    destinationIndex: destinationIndex,
                    systemChannel: systemChannel,
                    timeoutPerRequest: 3.0,
                    timeoutForRequest: profile.timeout(for:),
                    delayBetweenRequests: profile.delayBetweenRequests
                ) { kind, completed, total in
                    Task {
                        await progress?(Self.cacheEvent(for: kind), Double(completed), Double(total))
                    }
                }
            } catch {
                return requestKinds.map {
                    FB01MIDIRequestBatchResult(kind: $0, errorDescription: String(describing: error))
                }
            }
        }.value

        for batchResult in batchResults {
            guard let bytes = batchResult.bytes else {
                result.failures.append(batchResult.kind.displayName)
                continue
            }

            switch batchResult.kind {
            case .currentConfiguration:
                if let currentConfiguration = try? configurationService.currentConfiguration(fromDump: bytes) {
                    result.currentConfiguration = currentConfiguration
                } else {
                    result.failures.append("current configuration")
                }
            case .voiceBank(let bank):
                if let voiceBank = try? voiceService.voiceBankData(from: bytes, expectedDisplayBank: bank) {
                    result.voiceBanks[bank] = voiceBank
                } else {
                    result.failures.append("Voice Bank \(bank)")
                }
            case .configuration(let slot):
                if let configuration = try? configurationService.storedConfiguration(fromDump: bytes, zeroBasedSlot: slot - 1) {
                    result.configurations[slot] = configuration
                } else {
                    result.failures.append("Configuration \(slot)")
                }
            case .unitID, .instrumentVoice, .voiceRAM1:
                result.failures.append(batchResult.kind.displayName)
            }
        }

        await progress?(.finishing, totalRequests, totalRequests)
        return result
    }

    public func progressDetail(for event: FB01DeviceCacheEvent) -> String {
        switch event {
        case .currentConfiguration:
            return "Fetching current configuration..."
        case .voiceBank(let bank):
            return "Fetching Voice Bank \(bank)..."
        case .configuration(let slot):
            let upperBound = module.fullDeviceCacheScope.configurationSlots?.upperBound ?? slot
            return "Fetching Configuration \(slot) of \(upperBound)..."
        case .finishing:
            return "Finishing cache update..."
        }
    }

    private static func cacheEvent(for kind: FB01MIDIRequestKind) -> FB01DeviceCacheEvent {
        switch kind {
        case .currentConfiguration:
            return .currentConfiguration
        case .voiceBank(let bank):
            return .voiceBank(bank)
        case .configuration(let slot):
            return .configuration(slot)
        case .unitID, .instrumentVoice, .voiceRAM1:
            return .finishing
        }
    }

    private func fetchVoiceBank(
        bank: Int,
        sourceIndex: Int,
        destinationIndex: Int,
        systemChannel: Int
    ) async -> FB01VoiceBankData? {
        await Task.detached(priority: .userInitiated) {
            guard let bytes = try? FB01MIDI.request(
                .voiceBank(bank),
                sourceIndex: sourceIndex,
                destinationIndex: destinationIndex,
                systemChannel: systemChannel,
                timeout: 20
            ) else {
                return nil
            }
            return try? voiceService.voiceBankData(from: bytes, expectedDisplayBank: bank)
        }.value
    }

    private func fetchConfiguration(
        slot: Int,
        sourceIndex: Int,
        destinationIndex: Int,
        systemChannel: Int
    ) async -> FB01ConfigurationData? {
        await Task.detached(priority: .userInitiated) {
            try? configurationService.fetchStoredConfiguration(
                zeroBasedSlot: slot - 1,
                sourceIndex: sourceIndex,
                destinationIndex: destinationIndex,
                systemChannel: systemChannel,
                timeout: 15
            )
        }.value
    }

    private func fetchCurrentConfiguration(
        sourceIndex: Int,
        destinationIndex: Int,
        systemChannel: Int
    ) async -> FB01ConfigurationData? {
        await Task.detached(priority: .userInitiated) {
            try? configurationService.fetchCurrentConfiguration(
                sourceIndex: sourceIndex,
                destinationIndex: destinationIndex,
                systemChannel: systemChannel,
                timeout: 8
            )
        }.value
    }
}

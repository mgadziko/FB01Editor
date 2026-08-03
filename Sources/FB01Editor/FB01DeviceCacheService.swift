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
        progress: (@Sendable (FB01DeviceCacheEvent, Double, Double) async -> Void)? = nil
    ) async -> FB01DeviceCacheResult {
        let voiceBanks = normalizedVoiceBanks(requestedVoiceBanks)
        let totalRequests = Double(totalRequestCount(voiceBanks: voiceBanks, fetchConfigurations: fetchConfigurations))
        var completedRequests = 0.0
        var result = FB01DeviceCacheResult()

        if fetchConfigurations {
            if module.fullDeviceCacheScope.includesCurrentConfiguration {
                await progress?(.currentConfiguration, completedRequests, totalRequests)
                if let currentConfiguration = await fetchCurrentConfiguration(
                    sourceIndex: sourceIndex,
                    destinationIndex: destinationIndex,
                    systemChannel: systemChannel
                ) {
                    result.currentConfiguration = currentConfiguration
                } else {
                    result.failures.append("current configuration")
                }
                completedRequests += 1
            }
        }

        for bank in voiceBanks {
            await progress?(.voiceBank(bank), completedRequests, totalRequests)
            if let voiceBank = await fetchVoiceBank(
                bank: bank,
                sourceIndex: sourceIndex,
                destinationIndex: destinationIndex,
                systemChannel: systemChannel
            ) {
                result.voiceBanks[bank] = voiceBank
            } else {
                result.failures.append("Voice Bank \(bank)")
            }
            completedRequests += 1
        }

        if fetchConfigurations {
            for slot in module.fullDeviceCacheScope.configurationSlots?.closedRange ?? module.allConfigurationSlots.closedRange {
                await progress?(.configuration(slot), completedRequests, totalRequests)
                if let configuration = await fetchConfiguration(
                    slot: slot,
                    sourceIndex: sourceIndex,
                    destinationIndex: destinationIndex,
                    systemChannel: systemChannel
                ) {
                    result.configurations[slot] = configuration
                } else {
                    result.failures.append("Configuration \(slot)")
                }
                completedRequests += 1
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

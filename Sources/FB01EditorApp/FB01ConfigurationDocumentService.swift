import FB01Editor

enum FB01ConfigurationDocumentService {
    nonisolated static func fetchConfiguration(
        options: ConfigurationFetchOptions,
        sourceIndex: Int,
        destinationIndex: Int,
        systemChannel: Int
    ) throws -> (configuration: FB01ConfigurationData, systemChannel: Int) {
        let service = FB01ModuleServices.shared.configurationService
        if options.isCurrent {
            return (
                try service.fetchCurrentConfiguration(
                    sourceIndex: sourceIndex,
                    destinationIndex: destinationIndex,
                    systemChannel: systemChannel,
                    timeout: 8
                ),
                systemChannel
            )
        }
        return (
            try service.fetchStoredConfiguration(
                zeroBasedSlot: options.slot,
                sourceIndex: sourceIndex,
                destinationIndex: destinationIndex,
                systemChannel: systemChannel,
                timeout: 8
            ),
            systemChannel
        )
    }

    nonisolated static func fetchConfigurationNames(
        sourceIndex: Int,
        destinationIndex: Int,
        systemChannel: Int
    ) -> ConfigurationFetchNameLookup {
        let names = FB01ModuleServices.shared.configurationService.fetchWritableConfigurationNames(
            sourceIndex: sourceIndex,
            destinationIndex: destinationIndex,
            systemChannel: systemChannel,
            timeout: 1.25
        )
        return ConfigurationFetchNameLookup(storedNames: names)
    }
}

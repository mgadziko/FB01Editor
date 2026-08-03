public struct FB01ConfigurationService: SynthConfigurationServicing {
    public typealias Configuration = FB01ConfigurationData

    public static let shared = FB01ConfigurationService(module: .shared)

    public var module: FB01SynthModule

    public init(module: FB01SynthModule) {
        self.module = module
    }

    public enum StoreEvent: Equatable, Sendable {
        case turningProtectOff
        case sendingConfigurationData
        case storingSlot
        case verifyingSlot
    }

    public func currentConfiguration(fromDump bytes: [UInt8]) throws -> FB01ConfigurationData? {
        let artifact = try FB01Artifact(sysexBytes: bytes)
        for message in artifact.messages {
            if case let .currentConfigurationDump(_, packet) = message {
                return try FB01ConfigurationData(bytes: packet.payload)
            }
        }
        return nil
    }

    public func storedConfiguration(fromDump bytes: [UInt8], zeroBasedSlot: Int) throws -> FB01ConfigurationData? {
        let artifact = try FB01Artifact(sysexBytes: bytes)
        for message in artifact.messages {
            if case let .configurationDump(_, number, packet) = message,
               number == zeroBasedSlot {
                return try FB01ConfigurationData(bytes: packet.payload)
            }
        }
        return nil
    }

    public func configurationName(fromDump bytes: [UInt8]) throws -> String? {
        let artifact = try FB01Artifact(sysexBytes: bytes)
        for message in artifact.messages {
            switch message {
            case let .configurationDump(_, _, packet),
                 let .currentConfigurationDump(_, packet):
                let configuration = try FB01ConfigurationData(bytes: packet.payload)
                return configuration.name.isEmpty ? "Untitled" : configuration.name
            default:
                break
            }
        }
        return nil
    }

    public func fetchCurrentConfiguration(
        sourceIndex: Int,
        destinationIndex: Int,
        systemChannel: Int,
        timeout: Double = 8
    ) throws -> FB01ConfigurationData {
        let bytes = try FB01MIDI.request(
            .currentConfiguration,
            sourceIndex: sourceIndex,
            destinationIndex: destinationIndex,
            systemChannel: systemChannel,
            timeout: timeout
        )
        guard let configuration = try currentConfiguration(fromDump: bytes) else {
            throw FB01SysExError.unsupportedSysEx
        }
        return configuration
    }

    public func fetchStoredConfiguration(
        zeroBasedSlot: Int,
        sourceIndex: Int,
        destinationIndex: Int,
        systemChannel: Int,
        timeout: Double = 8
    ) throws -> FB01ConfigurationData {
        let displaySlot = zeroBasedSlot + 1
        let bytes = try FB01MIDI.request(
            .configuration(displaySlot),
            sourceIndex: sourceIndex,
            destinationIndex: destinationIndex,
            systemChannel: systemChannel,
            timeout: timeout
        )
        guard let configuration = try storedConfiguration(fromDump: bytes, zeroBasedSlot: zeroBasedSlot) else {
            throw FB01SysExError.unsupportedSysEx
        }
        return configuration
    }

    public func fetchWritableConfigurationNames(
        sourceIndex: Int,
        destinationIndex: Int,
        systemChannel: Int,
        timeout: Double = 1.25
    ) -> [Int: String] {
        var names: [Int: String] = [:]
        for slot in module.writableConfigurationSlots.closedRange {
            guard let bytes = try? FB01MIDI.request(
                .configuration(slot),
                sourceIndex: sourceIndex,
                destinationIndex: destinationIndex,
                systemChannel: systemChannel,
                timeout: timeout
            ),
                  let name = try? configurationName(fromDump: bytes),
                  !name.isEmpty else {
                continue
            }
            names[slot] = name
        }
        return names
    }

    public func storeMessages(configuration: FB01ConfigurationData, systemChannel: Int, zeroBasedSlot: Int) throws -> [[UInt8]] {
        guard module.isWritableConfigurationSlot(zeroBasedSlot + 1) else {
            throw FB01SysExError.valueOutOfRange(
                name: "configurationSlot",
                value: zeroBasedSlot,
                range: (module.writableConfigurationSlots.lowerBound - 1)...(module.writableConfigurationSlots.upperBound - 1)
            )
        }

        let protectOffCommand = FB01SysExMessage.command(.setMemoryProtect(systemChannel: systemChannel, .off))
        let currentMessage = FB01SysExMessage.currentConfigurationDump(
            systemChannel: systemChannel,
            packet: try FB01SysExPacket(payload: configuration.bytes)
        )
        let storeCommand = FB01SysExMessage.command(.storeCurrentConfiguration(
            systemChannel: systemChannel,
            number: zeroBasedSlot
        ))
        return try [protectOffCommand.bytes, currentMessage.bytes, storeCommand.bytes]
    }

    public func storeConfiguration(
        _ configuration: FB01ConfigurationData,
        zeroBasedSlot: Int,
        sourceIndex: Int,
        destinationIndex: Int,
        systemChannel: Int,
        confirmAfterStore: Bool,
        progress: (@Sendable (StoreEvent) async -> Void)? = nil
    ) async throws -> FB01ConfigurationData? {
        let messages = try storeMessages(
            configuration: configuration,
            systemChannel: systemChannel,
            zeroBasedSlot: zeroBasedSlot
        )

        await progress?(.turningProtectOff)
        try await Task.detached(priority: .userInitiated) {
            try FB01MIDI.sendSysEx([messages[0]], destinationIndex: destinationIndex, delayBetweenMessages: 0)
            try await Task.sleep(for: .milliseconds(300))
        }.value
        try Task.checkCancellation()

        await progress?(.sendingConfigurationData)
        try await Task.detached(priority: .userInitiated) {
            try FB01MIDI.sendSysEx([messages[1]], destinationIndex: destinationIndex, delayBetweenMessages: 0)
            try await Task.sleep(for: .milliseconds(1000))
        }.value
        try Task.checkCancellation()

        await progress?(.storingSlot)
        try await Task.detached(priority: .userInitiated) {
            try FB01MIDI.sendSysEx([messages[2]], destinationIndex: destinationIndex, delayBetweenMessages: 0)
        }.value
        try Task.checkCancellation()

        guard confirmAfterStore else {
            return nil
        }

        await progress?(.verifyingSlot)
        let readback = try await Task.detached(priority: .userInitiated) {
            try await Task.sleep(for: .milliseconds(800))
            return try FB01MIDI.request(
                .configuration(zeroBasedSlot + 1),
                sourceIndex: sourceIndex,
                destinationIndex: destinationIndex,
                systemChannel: systemChannel,
                timeout: 8
            )
        }.value
        try Task.checkCancellation()

        return try storedConfiguration(fromDump: readback, zeroBasedSlot: zeroBasedSlot)
    }
}

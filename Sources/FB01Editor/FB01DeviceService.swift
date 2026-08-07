public struct FB01DeviceService: Sendable {
    public static let shared = FB01DeviceService(module: .shared)

    public var module: FB01SynthModule

    public init(module: FB01SynthModule) {
        self.module = module
    }

    public var allBankRequestKinds: [FB01MIDIRequestKind] {
        let currentConfigurationRequest: [FB01MIDIRequestKind] = module.fullDeviceCacheScope.includesCurrentConfiguration
            ? [.currentConfiguration]
            : []
        return currentConfigurationRequest + module.fullDeviceCacheScope.voiceBanks.map { .voiceBank($0) } + [.voiceRAM1]
    }

    public var storedConfigurationRequestKinds: [FB01MIDIRequestKind] {
        (module.fullDeviceCacheScope.configurationSlots ?? module.allConfigurationSlots).closedRange.map { .configuration($0) }
    }

    public func requestKind(forDisplayBank displayBank: Int) throws -> FB01MIDIRequestKind {
        guard module.isValidVoiceBank(displayBank) else {
            let validRange = (module.allVoiceBanks.first ?? 1)...(module.allVoiceBanks.last ?? 7)
            throw FB01SysExError.valueOutOfRange(
                name: "displayBank",
                value: displayBank,
                range: validRange
            )
        }
        if displayBank == module.writableVoiceBanks.first {
            return .voiceRAM1
        }
        return .voiceBank(displayBank)
    }

    public func writableVoiceBankRequestKind(forVoiceSlot voiceSlot: Int) throws -> FB01MIDIRequestKind {
        guard (0..<module.writableVoiceSlotCount).contains(voiceSlot) else {
            throw FB01SysExError.valueOutOfRange(
                name: "voiceSlot",
                value: voiceSlot,
                range: 0...(module.writableVoiceSlotCount - 1)
            )
        }
        return try requestKind(forDisplayBank: voiceSlot / module.voicesPerBank + module.writableVoiceBanks[0])
    }
}

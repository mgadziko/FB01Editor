public struct FB01SynthModule: SynthModule {
    public static let shared = FB01SynthModule()

    public let identity = SynthModuleIdentity(
        manufacturer: "Yamaha",
        modelName: "FB-01",
        editorDisplayName: "Forest FB-01 Editor"
    )

    public let capabilities = SynthModuleCapabilities(
        supportsVoices: true,
        supportsConfigurations: true,
        supportsMultiInstrumentConfigurations: true,
        supportsWritableVoiceBanks: true,
        supportsReadOnlyVoiceBanks: true,
        supportsMemoryProtect: true,
        supportsLiveAuditionBuffer: true,
        supportsGeneralMIDIInstall: true
    )

    public let supportedDocumentKinds: [SynthDocumentKind] = [
        .voice,
        .configuration,
        .voiceBank,
        .configurationBank
    ]

    public let writableVoiceBanks = [1, 2]
    public let readOnlyVoiceBanks = [3, 4, 5, 6, 7]
    public let voicesPerBank = 48
    public let writableConfigurationSlots = SynthSlotRange(1...16)
    public let readOnlyConfigurationSlots = SynthSlotRange(17...20)

    private init() {}

    public var allVoiceBanks: [Int] {
        writableVoiceBanks + readOnlyVoiceBanks
    }

    public var voiceBankRange: SynthSlotRange {
        SynthSlotRange(allVoiceBanks.first!...allVoiceBanks.last!)
    }

    public var writableVoiceBankRange: SynthSlotRange {
        SynthSlotRange(writableVoiceBanks.first!...writableVoiceBanks.last!)
    }

    public var allConfigurationSlots: SynthSlotRange {
        SynthSlotRange(writableConfigurationSlots.lowerBound...readOnlyConfigurationSlots.upperBound)
    }

    public var writableVoiceSlotCount: Int {
        writableVoiceBanks.count * voicesPerBank
    }

    public func isWritableVoiceBank(_ bank: Int) -> Bool {
        writableVoiceBanks.contains(bank)
    }

    public func isReadOnlyVoiceBank(_ bank: Int) -> Bool {
        readOnlyVoiceBanks.contains(bank)
    }

    public func isValidVoiceBank(_ bank: Int) -> Bool {
        allVoiceBanks.contains(bank)
    }

    public func isWritableConfigurationSlot(_ slot: Int) -> Bool {
        writableConfigurationSlots.contains(slot)
    }

    public func isValidConfigurationSlot(_ slot: Int) -> Bool {
        allConfigurationSlots.contains(slot)
    }

    public func displayVoiceBank(forStorageBank storageBank: Int) -> Int {
        storageBank + 1
    }

    public func storageVoiceBank(forDisplayBank displayBank: Int) -> Int {
        displayBank - 1
    }
}

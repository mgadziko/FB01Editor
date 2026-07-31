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

    public let vocabulary = SynthModuleVocabulary(deviceDisplayName: "FB-01")

    public let supportedDocumentKinds: [SynthDocumentKind] = [
        .voice,
        .configuration,
        .voiceBank,
        .configurationBank
    ]

    public let supportedDocumentDescriptors: [SynthDocumentDescriptor] = [
        SynthDocumentDescriptor(
            kind: .voice,
            displayName: "Voice",
            supportsLoadFromFile: true,
            supportsSaveToFile: true,
            supportsFetchFromDevice: true,
            supportsStoreToDevice: true
        ),
        SynthDocumentDescriptor(
            kind: .configuration,
            displayName: "Configuration",
            supportsLoadFromFile: true,
            supportsSaveToFile: true,
            supportsFetchFromDevice: true,
            supportsStoreToDevice: true
        ),
        SynthDocumentDescriptor(
            kind: .voiceBank,
            displayName: "Voice Bank",
            supportsLoadFromFile: true,
            supportsSaveToFile: true,
            supportsFetchFromDevice: true,
            supportsStoreToDevice: true
        ),
        SynthDocumentDescriptor(
            kind: .configurationBank,
            displayName: "Configuration Bank",
            supportsLoadFromFile: true,
            supportsSaveToFile: true,
            supportsFetchFromDevice: true,
            supportsStoreToDevice: true
        ),
    ]

    public let parameterDescriptors: [SynthParameterDescriptor] = [
        SynthParameterDescriptor(id: "voice.name", displayName: "Name", valueKind: .text(maxLength: 7), group: "Voice"),
        SynthParameterDescriptor(id: "voice.algorithm", displayName: "Algorithm", valueKind: .integer, range: SynthSlotRange(1...8), defaultValue: 1, group: "Voice"),
        SynthParameterDescriptor(id: "voice.feedback", displayName: "Feedback", valueKind: .integer, range: SynthSlotRange(0...7), defaultValue: 0, group: "Voice"),
        SynthParameterDescriptor(id: "voice.transpose", displayName: "Transpose", valueKind: .signedInteger, range: SynthSlotRange(-24...24), defaultValue: 0, group: "Voice"),
        SynthParameterDescriptor(id: "voice.lfoSpeed", displayName: "LFO Speed", valueKind: .integer, range: SynthSlotRange(0...255), defaultValue: 0, group: "LFO"),
        SynthParameterDescriptor(id: "voice.amd", displayName: "Amplitude MOD Depth", valueKind: .integer, range: SynthSlotRange(0...127), defaultValue: 0, group: "LFO"),
        SynthParameterDescriptor(id: "voice.pmd", displayName: "Pitch MOD Depth", valueKind: .integer, range: SynthSlotRange(0...127), defaultValue: 0, group: "LFO"),
        SynthParameterDescriptor(id: "voice.ams", displayName: "Amplitude MOD Sensitivity", valueKind: .integer, range: SynthSlotRange(0...3), defaultValue: 0, group: "LFO"),
        SynthParameterDescriptor(id: "voice.pms", displayName: "Pitch MOD Sensitivity", valueKind: .integer, range: SynthSlotRange(0...7), defaultValue: 0, group: "LFO"),
        SynthParameterDescriptor(id: "voice.operator.totalLevel", displayName: "Total Level", valueKind: .integer, range: SynthSlotRange(0...127), defaultValue: 0, group: "Operator"),
        SynthParameterDescriptor(id: "voice.operator.frequencyMultiplier", displayName: "OSC FRQ Multiplier", valueKind: .integer, range: SynthSlotRange(0...15), defaultValue: 1, group: "Operator"),
        SynthParameterDescriptor(id: "voice.operator.attack", displayName: "Attack", valueKind: .integer, range: SynthSlotRange(0...31), defaultValue: 0, group: "Operator Envelope"),
        SynthParameterDescriptor(id: "voice.operator.decay1", displayName: "Decay 1", valueKind: .integer, range: SynthSlotRange(0...31), defaultValue: 0, group: "Operator Envelope"),
        SynthParameterDescriptor(id: "voice.operator.decay2", displayName: "Decay 2", valueKind: .integer, range: SynthSlotRange(0...31), defaultValue: 0, group: "Operator Envelope"),
        SynthParameterDescriptor(id: "voice.operator.sustain", displayName: "Sustain", valueKind: .integer, range: SynthSlotRange(0...15), defaultValue: 0, group: "Operator Envelope"),
        SynthParameterDescriptor(id: "voice.operator.release", displayName: "Release", valueKind: .integer, range: SynthSlotRange(0...15), defaultValue: 0, group: "Operator Envelope"),
        SynthParameterDescriptor(id: "configuration.name", displayName: "Name", valueKind: .text(maxLength: 8), group: "Configuration"),
        SynthParameterDescriptor(id: "configuration.combine", displayName: "Combine", valueKind: .toggle, defaultValue: 0, group: "Configuration"),
        SynthParameterDescriptor(id: "configuration.instrument.noteCount", displayName: "Active Notes", valueKind: .integer, range: SynthSlotRange(0...8), defaultValue: 0, group: "Instrument"),
        SynthParameterDescriptor(id: "configuration.instrument.midiChannel", displayName: "MIDI Channel", valueKind: .integer, range: SynthSlotRange(1...16), defaultValue: 1, group: "Instrument"),
        SynthParameterDescriptor(id: "configuration.instrument.outputLevel", displayName: "Level", valueKind: .integer, range: SynthSlotRange(0...127), defaultValue: 127, group: "Instrument"),
        SynthParameterDescriptor(id: "configuration.instrument.stereoPan", displayName: "Stereo Pan", valueKind: .signedInteger, range: SynthSlotRange(-63...63), defaultValue: 0, group: "Instrument"),
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

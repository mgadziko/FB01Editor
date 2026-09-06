import Foundation

/// TX81Z support includes writable Bank I plus assisted capture of the four
/// read-only factory banks.
public struct TX81ZSynthModule: SynthModule {
    public static let shared = TX81ZSynthModule()

    public let identity = SynthModuleIdentity(
        manufacturer: "Yamaha",
        modelName: "TX81Z",
        editorDisplayName: "Forest Editor"
    )

    public let capabilities = SynthModuleCapabilities(
        supportsVoices: true,
        supportsConfigurations: true,
        supportsMultiInstrumentConfigurations: true,
        supportsWritableVoiceBanks: true,
        supportsReadOnlyVoiceBanks: true,
        supportsMemoryProtect: true,
        supportsLiveAuditionBuffer: true,
        supportsGeneralMIDIInstall: false
    )

    public let vocabulary = SynthModuleVocabulary(
        deviceDisplayName: "TX81Z",
        configurationDisplayName: "Performance",
        configurationBankDisplayName: "Performance Bank",
        writableVoiceBankSuffix: "Internal",
        readOnlyVoiceBankSuffixPrefix: "Preset"
    )

    public let fileProfile = SynthFileProfile(
        singleVoiceExtension: "txv",
        singleConfigurationExtension: "txp",
        voiceBankExtension: "txvb",
        configurationBankExtension: "txpb",
        genericSysExExtension: "txx",
        importExtensions: ["txv", "txx", "syx"]
    )

    public let supportedDocumentKinds: [SynthDocumentKind] = [.voice, .configuration, .voiceBank, .configurationBank]

    public let supportedDocumentDescriptors: [SynthDocumentDescriptor] = [
        SynthDocumentDescriptor(
            kind: .voice,
            displayName: "Voice",
            supportsLoadFromFile: false,
            supportsSaveToFile: true,
            supportsFetchFromDevice: true,
            supportsStoreToDevice: true
        ),
        SynthDocumentDescriptor(
            kind: .voiceBank,
            displayName: "Voice Bank I",
            supportsLoadFromFile: true,
            supportsSaveToFile: true,
            supportsFetchFromDevice: true,
            supportsStoreToDevice: true
        ),
        SynthDocumentDescriptor(
            kind: .configuration,
            displayName: "Performance",
            supportsLoadFromFile: false,
            supportsSaveToFile: false,
            supportsFetchFromDevice: true,
            supportsStoreToDevice: false
        ),
        SynthDocumentDescriptor(
            kind: .configurationBank,
            displayName: "Performance Bank",
            supportsLoadFromFile: false,
            supportsSaveToFile: false,
            supportsFetchFromDevice: true,
            supportsStoreToDevice: false
        ),
    ]

    public let commandDescriptors: [SynthModuleCommandDescriptor] = [
        SynthModuleCommandDescriptor(
            kind: .showVoiceBank,
            menu: .voice,
            displayName: "Show Voice Bank"
        ),
        SynthModuleCommandDescriptor(
            kind: .showConfigurationBank,
            menu: .configuration,
            displayName: "Show Performance Bank"
        ),
    ]

    public let parameterDescriptors: [SynthParameterDescriptor] = [
        SynthParameterDescriptor(id: "voice.name", displayName: "Name", valueKind: .text(maxLength: 10), group: "Voice"),
        SynthParameterDescriptor(id: "voice.algorithm", displayName: "Algorithm", valueKind: .integer, range: SynthSlotRange(1...8), defaultValue: 1, group: "Voice"),
        SynthParameterDescriptor(id: "voice.operator.waveform", displayName: "Oscillator Waveform", valueKind: .option(["W1", "W2", "W3", "W4", "W5", "W6", "W7", "W8"]), range: SynthSlotRange(0...7), defaultValue: 0, group: "TX81Z Operator"),
        SynthParameterDescriptor(id: "voice.operator.fixedFrequency", displayName: "Fixed Frequency", valueKind: .toggle, defaultValue: 0, group: "TX81Z Operator"),
        SynthParameterDescriptor(id: "voice.operator.fixedFrequencyRange", displayName: "Fixed Frequency Range", valueKind: .integer, range: SynthSlotRange(1...7), defaultValue: 1, group: "TX81Z Operator"),
        SynthParameterDescriptor(id: "voice.operator.fineFrequency", displayName: "Fine Frequency", valueKind: .integer, range: SynthSlotRange(0...15), defaultValue: 0, group: "TX81Z Operator"),
        SynthParameterDescriptor(id: "voice.operator.envelopeShift", displayName: "EG Shift", valueKind: .option(["0 dB", "48 dB", "24 dB", "12 dB"]), range: SynthSlotRange(0...3), defaultValue: 0, group: "TX81Z Operator"),
        SynthParameterDescriptor(id: "voice.reverbRate", displayName: "Reverb Rate", valueKind: .integer, range: SynthSlotRange(0...7), defaultValue: 0, group: "TX81Z Voice"),
    ]

    public let parameterBindingDescriptors: [SynthParameterBindingDescriptor] = [
        SynthParameterBindingDescriptor(id: "tx81z.voice.name", parameterID: "voice.name", scope: .voice, fieldName: "voiceEdit.name"),
        SynthParameterBindingDescriptor(id: "tx81z.voice.algorithm", parameterID: "voice.algorithm", scope: .voice, fieldName: "voiceEdit.algorithm"),
        SynthParameterBindingDescriptor(id: "tx81z.voice.operator.waveform", parameterID: "voice.operator.waveform", scope: .voiceOperator, fieldName: "additionalVoice.waveform"),
        SynthParameterBindingDescriptor(id: "tx81z.voice.operator.fixedFrequency", parameterID: "voice.operator.fixedFrequency", scope: .voiceOperator, fieldName: "additionalVoice.fixedFrequencyEnabled"),
        SynthParameterBindingDescriptor(id: "tx81z.voice.operator.fixedFrequencyRange", parameterID: "voice.operator.fixedFrequencyRange", scope: .voiceOperator, fieldName: "additionalVoice.fixedFrequencyRange"),
        SynthParameterBindingDescriptor(id: "tx81z.voice.operator.fineFrequency", parameterID: "voice.operator.fineFrequency", scope: .voiceOperator, fieldName: "additionalVoice.fineFrequency"),
        SynthParameterBindingDescriptor(id: "tx81z.voice.operator.envelopeShift", parameterID: "voice.operator.envelopeShift", scope: .voiceOperator, fieldName: "additionalVoice.envelopeShift"),
        SynthParameterBindingDescriptor(id: "tx81z.voice.reverbRate", parameterID: "voice.reverbRate", scope: .voice, fieldName: "additionalVoice.reverbRate"),
    ]

    public let writableVoiceBanks: [Int] = [1]
    public let readOnlyVoiceBanks: [Int] = [2, 3, 4, 5]
    public let voicesPerBank = 32
    public let voiceBankSelectorLayout = SynthSelectorGridLayout(
        columns: 4,
        rowsPerColumn: 8,
        buttonWidth: 136,
        minimumWindowHeight: 390
    )
    public let configurationBankSelectorLayout: SynthSelectorGridLayout? = SynthSelectorGridLayout(
        columns: 4,
        rowsPerColumn: 8,
        buttonWidth: 136,
        minimumWindowHeight: 390
    )
    public let fullDeviceCacheScope = SynthDeviceCacheScope(voiceBanks: [1])
    public let writableConfigurationSlots = SynthSlotRange(1...24)
    public let readOnlyConfigurationSlots = SynthSlotRange(25...32)

    private init() {}
}

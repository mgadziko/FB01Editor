public enum DX100VoiceBankKind: Equatable, Sendable {
    case internalRAM
    case bankMemory(Int)
    case preset(normalMode: Bool, group: Int)

    public init?(displayBank: Int) {
        switch displayBank {
        case 1:
            self = .internalRAM
        case 2...5:
            self = .bankMemory(displayBank - 1)
        case 6...9:
            self = .preset(normalMode: true, group: displayBank - 5)
        case 10...13:
            self = .preset(normalMode: false, group: displayBank - 9)
        default:
            return nil
        }
    }

    public var displayBank: Int {
        switch self {
        case .internalRAM:
            1
        case .bankMemory(let bank):
            bank + 1
        case let .preset(normalMode, group):
            normalMode ? group + 5 : group + 9
        }
    }

    public var displayName: String {
        switch self {
        case .internalRAM:
            "Internal"
        case .bankMemory(let bank):
            "Bank \(Self.bankLetter(bank))"
        case let .preset(normalMode, group):
            "\(normalMode ? "Preset Normal" : "Preset Shift") \(group)"
        }
    }

    public var isFetchableFromConnectedDevice: Bool {
        switch self {
        case .internalRAM:
            true
        case .bankMemory:
            false
        case .preset:
            false
        }
    }

    public func programNumber(forVoiceIndex voiceIndex: Int) -> Int? {
        guard (0..<24).contains(voiceIndex) else {
            return nil
        }

        switch self {
        case .internalRAM:
            return voiceIndex
        case .bankMemory(let bank):
            guard (1...4).contains(bank) else {
                return nil
            }
            return 24 + ((bank - 1) * 24) + voiceIndex
        case .preset:
            return nil
        }
    }

    public func bankVoiceNumber(forVoiceIndex voiceIndex: Int) -> Int? {
        guard (0..<24).contains(voiceIndex) else {
            return nil
        }

        switch self {
        case .bankMemory(let bank):
            guard (1...4).contains(bank) else {
                return nil
            }
            return ((bank - 1) * 24) + voiceIndex
        default:
            return nil
        }
    }

    private static func bankLetter(_ bank: Int) -> String {
        guard (1...4).contains(bank) else {
            return "\(bank)"
        }
        let scalar = UnicodeScalar(UInt8(ascii: "A") + UInt8(bank - 1))
        return String(Character(scalar))
    }
}

public struct DX100SynthModule: SynthModule {
    public static let shared = DX100SynthModule()

    public let identity = SynthModuleIdentity(
        manufacturer: "Yamaha",
        modelName: "DX100",
        editorDisplayName: "Forest Editor"
    )

    public let capabilities = SynthModuleCapabilities(
        supportsVoices: true,
        supportsConfigurations: false,
        supportsMultiInstrumentConfigurations: false,
        supportsWritableVoiceBanks: true,
        supportsReadOnlyVoiceBanks: true,
        supportsMemoryProtect: true,
        supportsLiveAuditionBuffer: true,
        supportsGeneralMIDIInstall: false
    )

    public let vocabulary = SynthModuleVocabulary(
        deviceDisplayName: "DX100",
        configurationDisplayName: "Function Settings",
        configurationBankDisplayName: "Function Settings Bank",
        writableVoiceBankSuffix: "RAM/Bank",
        readOnlyVoiceBankSuffixPrefix: "Preset"
    )

    public let fileProfile = SynthFileProfile(
        singleVoiceExtension: "dxv",
        singleConfigurationExtension: "dxc",
        voiceBankExtension: "dxvb",
        configurationBankExtension: "dxcb",
        genericSysExExtension: "dxx",
        importExtensions: ["dxv", "dxvb", "dxx", "syx"]
    )

    public let supportedDocumentKinds: [SynthDocumentKind] = [
        .voice,
        .voiceBank
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
            kind: .voiceBank,
            displayName: "Voice Bank",
            supportsLoadFromFile: true,
            supportsSaveToFile: true,
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
            kind: .refreshDeviceCache,
            menu: .voice,
            displayName: "Refresh Device Cache"
        ),
    ]

    public let parameterDescriptors: [SynthParameterDescriptor] = [
        SynthParameterDescriptor(id: "voice.name", displayName: "Name", valueKind: .text(maxLength: 10), group: "Voice"),
        SynthParameterDescriptor(id: "voice.algorithm", displayName: "Algorithm", valueKind: .integer, range: SynthSlotRange(1...8), defaultValue: 1, group: "Voice"),
        SynthParameterDescriptor(id: "voice.feedback", displayName: "Feedback", valueKind: .integer, range: SynthSlotRange(0...7), defaultValue: 0, group: "Voice"),
        SynthParameterDescriptor(id: "voice.transpose", displayName: "Transpose", valueKind: .signedInteger, range: SynthSlotRange(-24...24), defaultValue: 0, group: "Voice"),
        SynthParameterDescriptor(id: "voice.lfoSpeed", displayName: "LFO Speed", valueKind: .integer, range: SynthSlotRange(0...99), defaultValue: 0, group: "LFO"),
        SynthParameterDescriptor(id: "voice.lfoDelay", displayName: "LFO Delay", valueKind: .integer, range: SynthSlotRange(0...99), defaultValue: 0, group: "LFO"),
        SynthParameterDescriptor(id: "voice.amd", displayName: "Amplitude MOD Depth", valueKind: .integer, range: SynthSlotRange(0...99), defaultValue: 0, group: "LFO"),
        SynthParameterDescriptor(id: "voice.pmd", displayName: "Pitch MOD Depth", valueKind: .integer, range: SynthSlotRange(0...99), defaultValue: 0, group: "LFO"),
        SynthParameterDescriptor(id: "voice.ams", displayName: "Amplitude MOD Sensitivity", valueKind: .integer, range: SynthSlotRange(0...7), defaultValue: 0, group: "LFO"),
        SynthParameterDescriptor(id: "voice.pms", displayName: "Pitch MOD Sensitivity", valueKind: .integer, range: SynthSlotRange(0...7), defaultValue: 0, group: "LFO"),
        SynthParameterDescriptor(id: "voice.lfoWaveform", displayName: "Waveform", valueKind: .option(["Sawtooth", "Square", "Triangle", "Sample and Hold"]), range: SynthSlotRange(0...3), defaultValue: 2, group: "LFO"),
        SynthParameterDescriptor(id: "voice.lfoSyncEnabled", displayName: "LFO Sync", valueKind: .toggle, defaultValue: 0, group: "LFO"),
        SynthParameterDescriptor(id: "voice.operator.carrier", displayName: "Carrier", valueKind: .toggle, defaultValue: 0, isEditable: false, group: "Operator"),
        SynthParameterDescriptor(id: "voice.operator.totalLevel", displayName: "Total Level", valueKind: .integer, range: SynthSlotRange(0...99), defaultValue: 0, group: "Operator"),
        SynthParameterDescriptor(id: "voice.operator.frequency", displayName: "Frequency Ratio", valueKind: .integer, range: SynthSlotRange(0...63), defaultValue: 1, group: "Operator"),
        SynthParameterDescriptor(id: "voice.operator.detune", displayName: "Detune", valueKind: .signedInteger, range: SynthSlotRange(-3...3), defaultValue: 0, group: "Operator"),
        SynthParameterDescriptor(id: "voice.operator.keyboardLevelDepth", displayName: "Keyboard Level Depth", valueKind: .integer, range: SynthSlotRange(0...99), defaultValue: 0, group: "Operator"),
        SynthParameterDescriptor(id: "voice.operator.keyboardRateScalingDepth", displayName: "Keyboard Rate Scaling Depth", valueKind: .integer, range: SynthSlotRange(0...3), defaultValue: 0, group: "Operator"),
        SynthParameterDescriptor(id: "voice.operator.velocityToTotalLevel", displayName: "Key Velocity to Level", valueKind: .integer, range: SynthSlotRange(0...7), defaultValue: 0, group: "Operator"),
        SynthParameterDescriptor(id: "voice.operator.attack", displayName: "Attack", valueKind: .integer, range: SynthSlotRange(0...31), defaultValue: 0, group: "Operator Envelope"),
        SynthParameterDescriptor(id: "voice.operator.decay1", displayName: "Decay 1", valueKind: .integer, range: SynthSlotRange(0...31), defaultValue: 0, group: "Operator Envelope"),
        SynthParameterDescriptor(id: "voice.operator.decay2", displayName: "Decay 2", valueKind: .integer, range: SynthSlotRange(0...31), defaultValue: 0, group: "Operator Envelope"),
        SynthParameterDescriptor(id: "voice.operator.sustain", displayName: "Sustain", valueKind: .integer, range: SynthSlotRange(0...15), defaultValue: 0, group: "Operator Envelope"),
        SynthParameterDescriptor(id: "voice.operator.release", displayName: "Release", valueKind: .integer, range: SynthSlotRange(0...15), defaultValue: 0, group: "Operator Envelope"),
    ]

    public let parameterBindingDescriptors: [SynthParameterBindingDescriptor] = [
        SynthParameterBindingDescriptor(id: "dx100.voice.name", parameterID: "voice.name", scope: .voice, fieldName: "name"),
        SynthParameterBindingDescriptor(id: "dx100.voice.algorithm", parameterID: "voice.algorithm", scope: .voice, fieldName: "algorithm"),
        SynthParameterBindingDescriptor(id: "dx100.voice.feedback", parameterID: "voice.feedback", scope: .voice, fieldName: "feedback"),
        SynthParameterBindingDescriptor(id: "dx100.voice.transpose", parameterID: "voice.transpose", scope: .voice, fieldName: "transpose"),
        SynthParameterBindingDescriptor(id: "dx100.voice.lfoSpeed", parameterID: "voice.lfoSpeed", scope: .voice, fieldName: "lfoSpeed"),
        SynthParameterBindingDescriptor(id: "dx100.voice.lfoDelay", parameterID: "voice.lfoDelay", scope: .voice, fieldName: "lfoDelay"),
        SynthParameterBindingDescriptor(id: "dx100.voice.amd", parameterID: "voice.amd", scope: .voice, fieldName: "amplitudeModulationDepth"),
        SynthParameterBindingDescriptor(id: "dx100.voice.pmd", parameterID: "voice.pmd", scope: .voice, fieldName: "pitchModulationDepth"),
        SynthParameterBindingDescriptor(id: "dx100.voice.ams", parameterID: "voice.ams", scope: .voice, fieldName: "amplitudeModulationSensitivity"),
        SynthParameterBindingDescriptor(id: "dx100.voice.pms", parameterID: "voice.pms", scope: .voice, fieldName: "pitchModulationSensitivity"),
        SynthParameterBindingDescriptor(id: "dx100.voice.lfoWaveform", parameterID: "voice.lfoWaveform", scope: .voice, fieldName: "lfoWaveform"),
        SynthParameterBindingDescriptor(id: "dx100.voice.lfoSyncEnabled", parameterID: "voice.lfoSyncEnabled", scope: .voice, fieldName: "lfoSyncEnabled"),
        SynthParameterBindingDescriptor(id: "dx100.voice.operator.carrier", parameterID: "voice.operator.carrier", scope: .voiceOperator, fieldName: "carrier"),
        SynthParameterBindingDescriptor(id: "dx100.voice.operator.totalLevel", parameterID: "voice.operator.totalLevel", scope: .voiceOperator, fieldName: "outputLevel"),
        SynthParameterBindingDescriptor(id: "dx100.voice.operator.frequency", parameterID: "voice.operator.frequency", scope: .voiceOperator, fieldName: "oscillatorFrequency"),
        SynthParameterBindingDescriptor(id: "dx100.voice.operator.detune", parameterID: "voice.operator.detune", scope: .voiceOperator, fieldName: "detune"),
        SynthParameterBindingDescriptor(id: "dx100.voice.operator.keyboardLevelDepth", parameterID: "voice.operator.keyboardLevelDepth", scope: .voiceOperator, fieldName: "keyboardScalingLevel"),
        SynthParameterBindingDescriptor(id: "dx100.voice.operator.keyboardRateScalingDepth", parameterID: "voice.operator.keyboardRateScalingDepth", scope: .voiceOperator, fieldName: "keyboardScalingRate"),
        SynthParameterBindingDescriptor(id: "dx100.voice.operator.velocityToTotalLevel", parameterID: "voice.operator.velocityToTotalLevel", scope: .voiceOperator, fieldName: "keyVelocitySensitivity"),
        SynthParameterBindingDescriptor(id: "dx100.voice.operator.attack", parameterID: "voice.operator.attack", scope: .voiceOperator, fieldName: "attackRate"),
        SynthParameterBindingDescriptor(id: "dx100.voice.operator.decay1", parameterID: "voice.operator.decay1", scope: .voiceOperator, fieldName: "decay1Rate"),
        SynthParameterBindingDescriptor(id: "dx100.voice.operator.decay2", parameterID: "voice.operator.decay2", scope: .voiceOperator, fieldName: "decay2Rate"),
        SynthParameterBindingDescriptor(id: "dx100.voice.operator.sustain", parameterID: "voice.operator.sustain", scope: .voiceOperator, fieldName: "decay1Level"),
        SynthParameterBindingDescriptor(id: "dx100.voice.operator.release", parameterID: "voice.operator.release", scope: .voiceOperator, fieldName: "releaseRate"),
    ]

    public let writableVoiceBanks = [1, 2, 3, 4, 5]
    public let readOnlyVoiceBanks = [6, 7, 8, 9, 10, 11, 12, 13]
    public let voicesPerBank = 24
    public let voiceBankSelectorLayout = SynthSelectorGridLayout(
        columns: 4,
        rowsPerColumn: 6,
        buttonWidth: 136,
        minimumWindowHeight: 390
    )
    public let configurationBankSelectorLayout: SynthSelectorGridLayout? = nil
    public let fullDeviceCacheScope = SynthDeviceCacheScope(
        voiceBanks: Array(1...13),
        configurationSlots: nil,
        includesCurrentConfiguration: false
    )
    public let writableConfigurationSlots = SynthSlotRange(1...1)
    public let readOnlyConfigurationSlots = SynthSlotRange(1...1)

    private init() {}

    public var allVoiceBanks: [Int] {
        writableVoiceBanks + readOnlyVoiceBanks
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

    public func voiceBankKind(displayBank: Int) -> DX100VoiceBankKind? {
        DX100VoiceBankKind(displayBank: displayBank)
    }
}

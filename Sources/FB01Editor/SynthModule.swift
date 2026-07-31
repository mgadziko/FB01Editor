import Foundation

public struct SynthModuleIdentity: Equatable, Sendable {
    public var manufacturer: String
    public var modelName: String
    public var editorDisplayName: String

    public init(manufacturer: String, modelName: String, editorDisplayName: String) {
        self.manufacturer = manufacturer
        self.modelName = modelName
        self.editorDisplayName = editorDisplayName
    }
}

public enum SynthDocumentKind: String, CaseIterable, Sendable {
    case voice
    case configuration
    case voiceBank
    case configurationBank
}

public struct SynthModuleCapabilities: Equatable, Sendable {
    public var supportsVoices: Bool
    public var supportsConfigurations: Bool
    public var supportsMultiInstrumentConfigurations: Bool
    public var supportsWritableVoiceBanks: Bool
    public var supportsReadOnlyVoiceBanks: Bool
    public var supportsMemoryProtect: Bool
    public var supportsLiveAuditionBuffer: Bool
    public var supportsGeneralMIDIInstall: Bool

    public init(
        supportsVoices: Bool,
        supportsConfigurations: Bool,
        supportsMultiInstrumentConfigurations: Bool,
        supportsWritableVoiceBanks: Bool,
        supportsReadOnlyVoiceBanks: Bool,
        supportsMemoryProtect: Bool,
        supportsLiveAuditionBuffer: Bool,
        supportsGeneralMIDIInstall: Bool
    ) {
        self.supportsVoices = supportsVoices
        self.supportsConfigurations = supportsConfigurations
        self.supportsMultiInstrumentConfigurations = supportsMultiInstrumentConfigurations
        self.supportsWritableVoiceBanks = supportsWritableVoiceBanks
        self.supportsReadOnlyVoiceBanks = supportsReadOnlyVoiceBanks
        self.supportsMemoryProtect = supportsMemoryProtect
        self.supportsLiveAuditionBuffer = supportsLiveAuditionBuffer
        self.supportsGeneralMIDIInstall = supportsGeneralMIDIInstall
    }
}

public struct SynthModuleVocabulary: Equatable, Sendable {
    public var deviceDisplayName: String
    public var voiceDisplayName: String
    public var configurationDisplayName: String
    public var voiceBankDisplayName: String
    public var configurationBankDisplayName: String
    public var memoryProtectDisplayName: String
    public var writableVoiceBankSuffix: String
    public var readOnlyVoiceBankSuffixPrefix: String
    public var currentConfigurationDisplayName: String
    public var liveAuditionBufferDisplayName: String

    public init(
        deviceDisplayName: String,
        voiceDisplayName: String = "Voice",
        configurationDisplayName: String = "Configuration",
        voiceBankDisplayName: String = "Voice Bank",
        configurationBankDisplayName: String = "Configuration Bank",
        memoryProtectDisplayName: String = "Memory Protect",
        writableVoiceBankSuffix: String = "RAM",
        readOnlyVoiceBankSuffixPrefix: String = "ROM",
        currentConfigurationDisplayName: String = "Current Configuration",
        liveAuditionBufferDisplayName: String = "Current Voice Buffer"
    ) {
        self.deviceDisplayName = deviceDisplayName
        self.voiceDisplayName = voiceDisplayName
        self.configurationDisplayName = configurationDisplayName
        self.voiceBankDisplayName = voiceBankDisplayName
        self.configurationBankDisplayName = configurationBankDisplayName
        self.memoryProtectDisplayName = memoryProtectDisplayName
        self.writableVoiceBankSuffix = writableVoiceBankSuffix
        self.readOnlyVoiceBankSuffixPrefix = readOnlyVoiceBankSuffixPrefix
        self.currentConfigurationDisplayName = currentConfigurationDisplayName
        self.liveAuditionBufferDisplayName = liveAuditionBufferDisplayName
    }
}

public struct SynthSlotRange: Equatable, Sendable {
    public var lowerBound: Int
    public var upperBound: Int

    public init(_ range: ClosedRange<Int>) {
        self.lowerBound = range.lowerBound
        self.upperBound = range.upperBound
    }

    public var closedRange: ClosedRange<Int> {
        lowerBound...upperBound
    }

    public var count: Int {
        upperBound - lowerBound + 1
    }

    public func contains(_ value: Int) -> Bool {
        closedRange.contains(value)
    }
}

public enum SynthParameterValueKind: Equatable, Sendable {
    case integer
    case signedInteger
    case toggle
    case option([String])
    case text(maxLength: Int)
}

public struct SynthParameterDescriptor: Equatable, Identifiable, Sendable {
    public var id: String
    public var displayName: String
    public var valueKind: SynthParameterValueKind
    public var range: SynthSlotRange?
    public var defaultValue: Int?
    public var isEditable: Bool
    public var group: String

    public init(
        id: String,
        displayName: String,
        valueKind: SynthParameterValueKind,
        range: SynthSlotRange? = nil,
        defaultValue: Int? = nil,
        isEditable: Bool = true,
        group: String
    ) {
        self.id = id
        self.displayName = displayName
        self.valueKind = valueKind
        self.range = range
        self.defaultValue = defaultValue
        self.isEditable = isEditable
        self.group = group
    }
}

public struct SynthDocumentDescriptor: Equatable, Identifiable, Sendable {
    public var id: SynthDocumentKind { kind }
    public var kind: SynthDocumentKind
    public var displayName: String
    public var supportsLoadFromFile: Bool
    public var supportsSaveToFile: Bool
    public var supportsFetchFromDevice: Bool
    public var supportsStoreToDevice: Bool

    public init(
        kind: SynthDocumentKind,
        displayName: String,
        supportsLoadFromFile: Bool,
        supportsSaveToFile: Bool,
        supportsFetchFromDevice: Bool,
        supportsStoreToDevice: Bool
    ) {
        self.kind = kind
        self.displayName = displayName
        self.supportsLoadFromFile = supportsLoadFromFile
        self.supportsSaveToFile = supportsSaveToFile
        self.supportsFetchFromDevice = supportsFetchFromDevice
        self.supportsStoreToDevice = supportsStoreToDevice
    }
}

public struct SynthFileProfile: Equatable, Sendable {
    public var singleVoiceExtension: String
    public var singleConfigurationExtension: String
    public var voiceBankExtension: String
    public var configurationBankExtension: String
    public var genericSysExExtension: String
    public var importExtensions: [String]

    public init(
        singleVoiceExtension: String,
        singleConfigurationExtension: String,
        voiceBankExtension: String,
        configurationBankExtension: String,
        genericSysExExtension: String,
        importExtensions: [String]
    ) {
        self.singleVoiceExtension = singleVoiceExtension
        self.singleConfigurationExtension = singleConfigurationExtension
        self.voiceBankExtension = voiceBankExtension
        self.configurationBankExtension = configurationBankExtension
        self.genericSysExExtension = genericSysExExtension
        self.importExtensions = importExtensions
    }

    public func preferredExtension(for kind: SynthDocumentKind) -> String {
        switch kind {
        case .voice:
            singleVoiceExtension
        case .configuration:
            singleConfigurationExtension
        case .voiceBank:
            voiceBankExtension
        case .configurationBank:
            configurationBankExtension
        }
    }
}

public protocol SynthModule: Sendable {
    var identity: SynthModuleIdentity { get }
    var capabilities: SynthModuleCapabilities { get }
    var vocabulary: SynthModuleVocabulary { get }
    var supportedDocumentKinds: [SynthDocumentKind] { get }
    var supportedDocumentDescriptors: [SynthDocumentDescriptor] { get }
    var fileProfile: SynthFileProfile { get }
    var parameterDescriptors: [SynthParameterDescriptor] { get }
    var writableVoiceBanks: [Int] { get }
    var readOnlyVoiceBanks: [Int] { get }
    var voicesPerBank: Int { get }
    var writableConfigurationSlots: SynthSlotRange { get }
    var readOnlyConfigurationSlots: SynthSlotRange { get }
}

public protocol SynthModuleServiceProviding: Sendable {
    associatedtype Module: SynthModule

    var module: Module { get }
}

public protocol SynthDeviceCacheServicing: Sendable {
    associatedtype CacheResult: Sendable
    associatedtype CacheEvent: Sendable

    func totalRequestCount(voiceBanks: [Int], fetchConfigurations: Bool) -> Int
    func normalizedVoiceBanks(_ requestedVoiceBanks: [Int]) -> [Int]
}

public protocol SynthVoiceServicing: Sendable {
    associatedtype Voice: Sendable
    associatedtype VoiceBank: Sendable
}

public protocol SynthConfigurationServicing: Sendable {
    associatedtype Configuration: Sendable
}

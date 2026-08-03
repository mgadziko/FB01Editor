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

public struct SynthSelectorGridLayout: Equatable, Sendable {
    public var columns: Int
    public var rowsPerColumn: Int
    public var buttonWidth: Double
    public var columnSpacing: Double
    public var horizontalPadding: Double
    public var minimumWindowHeight: Double

    public init(
        columns: Int,
        rowsPerColumn: Int,
        buttonWidth: Double,
        columnSpacing: Double = 14,
        horizontalPadding: Double = 36,
        minimumWindowHeight: Double
    ) {
        self.columns = max(1, columns)
        self.rowsPerColumn = max(1, rowsPerColumn)
        self.buttonWidth = buttonWidth
        self.columnSpacing = columnSpacing
        self.horizontalPadding = horizontalPadding
        self.minimumWindowHeight = minimumWindowHeight
    }

    public var windowWidth: Double {
        buttonWidth * Double(columns) + columnSpacing * Double(max(columns - 1, 0)) + horizontalPadding
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

public protocol SynthVoiceDocumentPayloadProtocol: Sendable {
    associatedtype Voice: Sendable

    var moduleIdentity: SynthModuleIdentity { get }
    var voice: Voice { get }
    var systemChannel: Int { get }
}

public protocol SynthConfigurationDocumentPayloadProtocol: Sendable {
    associatedtype Configuration: Sendable

    var moduleIdentity: SynthModuleIdentity { get }
    var configuration: Configuration { get }
    var systemChannel: Int { get }
}

public protocol SynthDocumentTemplating: Sendable {
    associatedtype Voice: Sendable
    associatedtype Configuration: Sendable

    func templateVoice() throws -> Voice
    func templateConfiguration() throws -> Configuration
}

public protocol SynthDocumentExtracting: Sendable {
    associatedtype Artifact: Sendable
    associatedtype VoiceCandidate: Sendable
    associatedtype ConfigurationCandidate: Sendable

    func voiceCandidates(from artifact: Artifact) throws -> [VoiceCandidate]
    func configurationCandidates(from artifact: Artifact) throws -> [ConfigurationCandidate]
}

public protocol SynthDocumentFileServicing: Sendable {
    associatedtype Voice: Sendable
    associatedtype Configuration: Sendable
    associatedtype VoiceCandidate: Sendable
    associatedtype ConfigurationCandidate: Sendable

    func readVoiceCandidates(from url: URL) throws -> [VoiceCandidate]
    func readConfigurationCandidates(from url: URL) throws -> [ConfigurationCandidate]
    func writeVoice(_ voice: Voice, systemChannel: Int, to url: URL) throws
    func writeConfiguration(_ configuration: Configuration, systemChannel: Int, to url: URL) throws
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

public enum SynthModuleMenu: String, CaseIterable, Sendable {
    case app
    case voice
    case configuration
}

public enum SynthModuleCommandKind: String, CaseIterable, Sendable {
    case resetInstructions
    case copyVoiceToSlot
    case swapVoiceWithSlot
    case resetSelectedVoice
    case resetAllVoiceEdits
    case saveEditedVoiceBank
    case storeGeneralMIDIVoices
    case copyConfigurationToSlot
    case refreshDeviceCache
    case sendSelectedConfigurationToEditBuffer
    case sendAndConfirmSelectedConfiguration
    case storeSelectedConfigurationToSlot
    case storeAndConfirmSelectedConfiguration
}

public struct SynthModuleCommandDescriptor: Equatable, Identifiable, Sendable {
    public var id: SynthModuleCommandKind { kind }
    public var kind: SynthModuleCommandKind
    public var menu: SynthModuleMenu
    public var displayName: String
    public var requiresConsoleSections: Bool

    public init(
        kind: SynthModuleCommandKind,
        menu: SynthModuleMenu,
        displayName: String,
        requiresConsoleSections: Bool = false
    ) {
        self.kind = kind
        self.menu = menu
        self.displayName = displayName
        self.requiresConsoleSections = requiresConsoleSections
    }
}

public enum SynthParameterBindingScope: Equatable, Sendable {
    case voice
    case voiceOperator
    case configuration
    case configurationInstrument
}

public struct SynthParameterBindingDescriptor: Equatable, Identifiable, Sendable {
    public var id: String
    public var parameterID: SynthParameterDescriptor.ID
    public var scope: SynthParameterBindingScope
    public var fieldName: String

    public init(
        id: String,
        parameterID: SynthParameterDescriptor.ID,
        scope: SynthParameterBindingScope,
        fieldName: String
    ) {
        self.id = id
        self.parameterID = parameterID
        self.scope = scope
        self.fieldName = fieldName
    }
}

public protocol SynthModule: Sendable {
    var identity: SynthModuleIdentity { get }
    var capabilities: SynthModuleCapabilities { get }
    var vocabulary: SynthModuleVocabulary { get }
    var supportedDocumentKinds: [SynthDocumentKind] { get }
    var supportedDocumentDescriptors: [SynthDocumentDescriptor] { get }
    var fileProfile: SynthFileProfile { get }
    var commandDescriptors: [SynthModuleCommandDescriptor] { get }
    var parameterDescriptors: [SynthParameterDescriptor] { get }
    var parameterBindingDescriptors: [SynthParameterBindingDescriptor] { get }
    var writableVoiceBanks: [Int] { get }
    var readOnlyVoiceBanks: [Int] { get }
    var voicesPerBank: Int { get }
    var voiceBankSelectorLayout: SynthSelectorGridLayout { get }
    var configurationBankSelectorLayout: SynthSelectorGridLayout? { get }
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

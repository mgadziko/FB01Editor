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

public protocol SynthModule: Sendable {
    var identity: SynthModuleIdentity { get }
    var capabilities: SynthModuleCapabilities { get }
    var supportedDocumentKinds: [SynthDocumentKind] { get }
    var writableVoiceBanks: [Int] { get }
    var readOnlyVoiceBanks: [Int] { get }
    var voicesPerBank: Int { get }
    var writableConfigurationSlots: SynthSlotRange { get }
    var readOnlyConfigurationSlots: SynthSlotRange { get }
}

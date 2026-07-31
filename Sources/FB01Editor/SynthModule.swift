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
    var supportedDocumentKinds: [SynthDocumentKind] { get }
    var writableVoiceBanks: [Int] { get }
    var readOnlyVoiceBanks: [Int] { get }
    var voicesPerBank: Int { get }
    var writableConfigurationSlots: SynthSlotRange { get }
    var readOnlyConfigurationSlots: SynthSlotRange { get }
}

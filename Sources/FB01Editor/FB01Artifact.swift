import Foundation

public enum FB01ArtifactKind: String, Equatable, Sendable {
    case singleVoice
    case voiceBank
    case currentConfiguration
    case storedConfiguration
    case configurationSet
    case unitID
    case rawSysEx
}

public struct FB01Artifact: Equatable, Sendable {
    public var kind: FB01ArtifactKind
    public var messages: [FB01SysExMessage]

    public init(kind: FB01ArtifactKind, messages: [FB01SysExMessage]) {
        self.kind = kind
        self.messages = messages
    }

    public init(message: FB01SysExMessage) {
        self.kind = Self.kind(for: message)
        self.messages = [message]
    }

    public init(sysexBytes bytes: [UInt8]) throws {
        let messages = try FB01SysExMessage.splitMessages(from: bytes)
        self.messages = messages
        self.kind = Self.kind(for: messages)
    }

    public var sysexBytes: [UInt8] {
        get throws {
            try messages.flatMap { try $0.bytes }
        }
    }

    public func writeSysEx(to url: URL) throws {
        let data = try Data(sysexBytes)
        try data.write(to: url)
    }

    public static func readSysEx(from url: URL) throws -> FB01Artifact {
        let data = try Data(contentsOf: url)
        return try FB01Artifact(sysexBytes: Array(data))
    }

    private static func kind(for messages: [FB01SysExMessage]) -> FB01ArtifactKind {
        guard messages.count == 1, let message = messages.first else {
            if messages.allSatisfy({ kind(for: $0) == .storedConfiguration || kind(for: $0) == .currentConfiguration }) {
                return .configurationSet
            }
            return .rawSysEx
        }

        return kind(for: message)
    }

    private static func kind(for message: FB01SysExMessage) -> FB01ArtifactKind {
        switch message {
        case .instrumentVoiceDump:
            return .singleVoice
        case .voiceBankDump:
            return .voiceBank
        case .currentConfigurationDump:
            return .currentConfiguration
        case .configurationDump:
            return .storedConfiguration
        case .allConfigurationsDump:
            return .configurationSet
        case .unitIDDump:
            return .unitID
        case .command, .raw:
            return .rawSysEx
        }
    }
}

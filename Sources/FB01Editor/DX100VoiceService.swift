import Foundation

public struct DX100FetchedVoice: Sendable {
    public var voice: DX100VoiceData
    public var channel: Int
    public var title: String

    public init(voice: DX100VoiceData, channel: Int, title: String) {
        self.voice = voice
        self.channel = channel
        self.title = title
    }
}

public enum DX100VoiceServiceError: Error, Equatable, CustomStringConvertible {
    case unsupportedSysEx

    public var description: String {
        switch self {
        case .unsupportedSysEx:
            "The SysEx data does not contain a DX100 single-voice bulk dump."
        }
    }
}

public struct DX100VoiceService: SynthVoiceServicing {
    public typealias Voice = DX100VoiceData
    public typealias VoiceBank = Never

    public static let shared = DX100VoiceService(module: .shared)

    public var module: DX100SynthModule

    public init(module: DX100SynthModule) {
        self.module = module
    }

    public func singleVoiceDumpRequest(channel: Int = 0) throws -> [UInt8] {
        try DX100.requestSingleVoiceBulk(channel: channel)
    }

    public func currentVoice(fromSingleVoiceBulkSysEx bytes: [UInt8]) throws -> DX100FetchedVoice {
        let voice = try DX100VoiceData(singleVoiceBulkSysEx: bytes)
        let channel = Int(bytes[2] & 0x0F)
        return DX100FetchedVoice(
            voice: voice,
            channel: channel,
            title: "Current Voice: \(voice.name.isEmpty ? "Untitled" : voice.name)"
        )
    }

    public func currentVoice(from messages: [[UInt8]]) throws -> DX100FetchedVoice {
        for message in messages {
            if let voice = try? currentVoice(fromSingleVoiceBulkSysEx: message) {
                return voice
            }
        }
        throw DX100VoiceServiceError.unsupportedSysEx
    }

    public func editBufferMessages(for voice: DX100VoiceData, channel: Int = 0) throws -> [[UInt8]] {
        [try voice.singleVoiceBulkSysEx(channel: channel)]
    }

    public func neutralVoice(fromSingleVoiceBulkSysEx bytes: [UInt8]) throws -> FourOperatorVoiceData {
        try currentVoice(fromSingleVoiceBulkSysEx: bytes).voice.fourOperatorVoice
    }
}

public struct DX100ModuleServices: SynthModuleServiceProviding {
    public typealias Module = DX100SynthModule

    public static let shared = DX100ModuleServices()

    public let module = DX100SynthModule.shared
    public let voiceService = DX100VoiceService.shared
    public let documentService = DX100DocumentService.shared

    private init() {}
}

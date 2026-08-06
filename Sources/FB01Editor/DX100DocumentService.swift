import Foundation

public struct DX100VoiceDocumentCandidate: Sendable {
    public var title: String
    public var voice: DX100VoiceData
    public var channel: Int

    public init(title: String, voice: DX100VoiceData, channel: Int) {
        self.title = title
        self.voice = voice
        self.channel = channel
    }
}

public enum DX100DocumentServiceError: Error, Equatable, CustomStringConvertible {
    case noVoiceCandidates
    case configurationsUnsupported
    case invalidDisplayedVoiceCount(expected: Int, actual: Int)

    public var description: String {
        switch self {
        case .noVoiceCandidates:
            "The file does not contain a DX100 single-voice dump."
        case .configurationsUnsupported:
            "DX100 configurations are not supported; use voice documents and voice banks."
        case let .invalidDisplayedVoiceCount(expected, actual):
            "Expected \(expected) displayed DX100 voices, received \(actual)."
        }
    }
}

public struct DX100DocumentService: Sendable {
    public static let shared = DX100DocumentService()

    private init() {}

    public func templateVoice() throws -> DX100VoiceData {
        var voice = try DX100VoiceData(bytes: Array(repeating: 0, count: DX100VoiceData.byteCount))
        voice = try voice.settingName("Init")
        return voice
    }

    public func voiceCandidates(fromSysExBytes bytes: [UInt8]) throws -> [DX100VoiceDocumentCandidate] {
        let candidates = DX100.splitSysExMessages(from: bytes).flatMap { message -> [DX100VoiceDocumentCandidate] in
            guard let voice = try? DX100VoiceData(singleVoiceBulkSysEx: message) else {
                if let bank = try? DX100VoiceBankData(thirtyTwoVoiceBulkSysEx: message) {
                    return (0..<DX100VoiceBankData.dx100DisplayedVoiceCount).compactMap { index in
                        guard let voice = try? bank.voice(atPackedVoiceIndex: index) else {
                            return nil
                        }
                        return DX100VoiceDocumentCandidate(
                            title: "Voice \(index + 1): \(voice.name.isEmpty ? "Untitled" : voice.name)",
                            voice: voice,
                            channel: bank.channel
                        )
                    }
                }
                return []
            }
            let channel = Int(message[2] & 0x0F)
            return [DX100VoiceDocumentCandidate(
                title: "Current Voice: \(voice.name.isEmpty ? "Untitled" : voice.name)",
                voice: voice,
                channel: channel
            )]
        }

        guard !candidates.isEmpty else {
            throw DX100DocumentServiceError.noVoiceCandidates
        }
        return candidates
    }

    public func readVoiceCandidates(from url: URL) throws -> [DX100VoiceDocumentCandidate] {
        try voiceCandidates(fromSysExBytes: Array(Data(contentsOf: url)))
    }

    public func writeVoice(_ voice: DX100VoiceData, channel: Int, to url: URL) throws {
        let data = Data(try voice.singleVoiceBulkSysEx(channel: channel))
        try data.write(to: url)
    }

    public func writeVoiceBank(_ bank: DX100VoiceBankData, channel: Int? = nil, to url: URL) throws {
        let data = Data(try bank.thirtyTwoVoiceBulkSysEx(channel: channel))
        try data.write(to: url)
    }

    public func voiceBank(fromDisplayedVoices voices: [DX100VoiceData], channel: Int = 0) throws -> DX100VoiceBankData {
        guard voices.count == DX100VoiceBankData.dx100DisplayedVoiceCount else {
            throw DX100DocumentServiceError.invalidDisplayedVoiceCount(
                expected: DX100VoiceBankData.dx100DisplayedVoiceCount,
                actual: voices.count
            )
        }

        let template = try templateVoice()
        let packedTemplate = DX100VoiceBankData.packedVoiceRecord(from: template)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(DX100.thirtyTwoVoiceDataByteCount)
        for _ in 0..<DX100VoiceBankData.packedVoiceCount {
            bytes.append(contentsOf: packedTemplate)
        }

        var bank = try DX100VoiceBankData(bytes: bytes, channel: channel)
        for (index, voice) in voices.enumerated() {
            bank = try bank.replacingVoice(atPackedVoiceIndex: index, with: voice)
        }
        return bank
    }
}

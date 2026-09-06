import Foundation

public struct TX81ZFetchedVoice: Sendable {
    public var voice: TX81ZVoiceData
    public var channel: Int
    public var title: String

    public init(voice: TX81ZVoiceData, channel: Int, title: String) {
        self.voice = voice
        self.channel = channel
        self.title = title
    }
}

public struct TX81ZVoiceService: SynthVoiceServicing {
    public typealias Voice = TX81ZVoiceData
    public typealias VoiceBank = TX81ZVoiceBankData

    public static let shared = TX81ZVoiceService(module: .shared)

    public var module: TX81ZSynthModule

    public init(module: TX81ZSynthModule) {
        self.module = module
    }

    /// Remote-switch parameter numbers documented by Yamaha for front-panel
    /// emulation. Factory capture uses only DATA ENTRY + to walk Voice 1...32.
    public enum RemoteSwitch: Int, Sendable {
        case dataEntryPlus = 72
    }

    public func remoteSwitchMessages(
        _ remoteSwitch: RemoteSwitch,
        channel: Int = 0
    ) throws -> [[UInt8]] {
        guard (0...15).contains(channel) else {
            throw TX81ZSysExError.invalidChannel(channel)
        }
        let prefix: [UInt8] = [TX81Z.start, TX81Z.yamahaID, 0x10 | UInt8(channel), 0x13, UInt8(remoteSwitch.rawValue)]
        return [prefix + [0x7F, TX81Z.end], prefix + [0x00, TX81Z.end]]
    }

    public func currentVoiceDumpRequest(channel: Int = 0) throws -> [UInt8] {
        try TX81Z.requestAdditionalAndVoiceEditData(channel: channel)
    }

    public func currentVoice(from messages: [[UInt8]]) throws -> TX81ZFetchedVoice {
        let voice = try TX81ZVoiceData(messages: messages)
        return TX81ZFetchedVoice(
            voice: voice,
            channel: voice.channel,
            title: "Current Voice: \(voice.name.isEmpty ? "Untitled" : voice.name)"
        )
    }

    public func voiceMemoryBankDumpRequest(channel: Int = 0) throws -> [UInt8] {
        try TX81Z.requestVoiceMemoryBank(channel: channel)
    }

    public func voiceMemoryBank(from bytes: [UInt8]) throws -> TX81ZVoiceBankData {
        try TX81ZVoiceBankData(voiceMemoryBulkSysEx: bytes)
    }

    public func currentPerformanceDumpRequest(channel: Int = 0) throws -> [UInt8] {
        try TX81Z.requestPerformanceEditData(channel: channel)
    }

    public func performanceMemoryBankDumpRequest(channel: Int = 0) throws -> [UInt8] {
        try TX81Z.requestPerformanceMemoryBank(channel: channel)
    }

    public func currentPerformance(from bytes: [UInt8]) throws -> TX81ZPerformanceData {
        let identifier = TX81Z.performanceEditIdentifier
        let expectedLength = 6 + identifier.count + TX81ZPerformanceData.editDataLength + 2
        guard bytes.count == expectedLength,
              bytes[0] == TX81Z.start,
              bytes[1] == TX81Z.yamahaID,
              (bytes[2] & 0xF0) == 0x00,
              bytes[3] == TX81Z.additionalVoiceFormat,
              bytes[4] == 0x00,
              bytes[5] == 0x78,
              Array(bytes[6..<(6 + identifier.count)]) == identifier,
              bytes.last == TX81Z.end else {
            throw TX81ZSysExError.invalidPerformanceBulkHeader
        }
        let dataStart = 6 + identifier.count
        let data = Array(bytes[dataStart..<(dataStart + TX81ZPerformanceData.editDataLength)])
        let checksum = bytes[dataStart + TX81ZPerformanceData.editDataLength]
        guard TX81Z.performanceChecksum(identifier: identifier, data: data) == checksum else {
            throw TX81ZSysExError.checksumMismatch(expected: TX81Z.performanceChecksum(identifier: identifier, data: data), actual: checksum)
        }
        return try TX81ZPerformanceData(editBytes: data)
    }

    public func performanceMemoryBank(from bytes: [UInt8]) throws -> TX81ZPerformanceBankData {
        try TX81ZPerformanceBankData(performanceMemoryBulkSysEx: bytes)
    }

    public func fetchCurrentVoice(
        sourceIndex: Int,
        destinationIndex: Int,
        channel: Int = 0,
        timeout: TimeInterval = 8
    ) throws -> TX81ZFetchedVoice {
        let request = try currentVoiceDumpRequest(channel: channel)
        let messages = try FB01MIDI.sendAndReceiveIsolated(
            [request],
            sourceIndex: sourceIndex,
            destinationIndex: destinationIndex,
            timeout: timeout,
            maxMessages: 2
        )
        return try currentVoice(from: messages)
    }

    public func fetchVoiceMemoryBank(
        sourceIndex: Int,
        destinationIndex: Int,
        channel: Int = 0,
        timeout: TimeInterval = 12
    ) throws -> TX81ZVoiceBankData {
        let request = try voiceMemoryBankDumpRequest(channel: channel)
        let messages = try FB01MIDI.sendAndReceiveIsolated(
            [request],
            sourceIndex: sourceIndex,
            destinationIndex: destinationIndex,
            timeout: timeout
        )
        guard let message = messages.first else {
            throw FB01MIDIError.timedOut("TX81Z Voice Bank I")
        }
        return try voiceMemoryBank(from: message)
    }

    public func fetchCurrentPerformance(
        sourceIndex: Int,
        destinationIndex: Int,
        channel: Int = 0,
        timeout: TimeInterval = 8
    ) throws -> TX81ZPerformanceData {
        let request = try currentPerformanceDumpRequest(channel: channel)
        let messages = try FB01MIDI.sendAndReceiveIsolated(
            [request], sourceIndex: sourceIndex, destinationIndex: destinationIndex, timeout: timeout
        )
        guard let message = messages.first else { throw FB01MIDIError.timedOut("TX81Z current Performance") }
        return try currentPerformance(from: message)
    }

    public func fetchPerformanceMemoryBank(
        sourceIndex: Int,
        destinationIndex: Int,
        channel: Int = 0,
        timeout: TimeInterval = 12
    ) throws -> TX81ZPerformanceBankData {
        let request = try performanceMemoryBankDumpRequest(channel: channel)
        let messages = try FB01MIDI.sendAndReceiveIsolated(
            [request], sourceIndex: sourceIndex, destinationIndex: destinationIndex, timeout: timeout
        )
        guard let message = messages.first else { throw FB01MIDIError.timedOut("TX81Z Performance Bank") }
        return try performanceMemoryBank(from: message)
    }

    /// Selects a VMEM program, then reads the complete TX81Z ACED + VCED pair.
    public func fetchVoiceMemoryVoice(
        at index: Int,
        sourceIndex: Int,
        destinationIndex: Int,
        channel: Int = 0,
        timeout: TimeInterval = 8
    ) throws -> TX81ZFetchedVoice {
        guard (0..<TX81ZVoiceBankData.voiceCount).contains(index) else {
            throw DX100SysExError.voiceIndexOutOfRange(index)
        }
        let request = try currentVoiceDumpRequest(channel: channel)
        let messages = try FB01MIDI.sendAndReceive(
            [[0xC0 | UInt8(channel), UInt8(index)], request],
            sourceIndex: sourceIndex,
            destinationIndex: destinationIndex,
            timeout: timeout,
            maxMessages: 2,
            delayBetweenMessages: 0.25
        )
        return try currentVoice(from: messages)
    }

    /// Captures the selected factory bank one voice at a time. The caller must
    /// put the hardware in PLAY SINGLE at the requested factory bank's Voice 1
    /// before calling this method. Forest then presses DATA ENTRY + remotely
    /// between each complete ACED + VCED capture.
    public func captureSelectedFactoryVoiceBank(
        sourceIndex: Int,
        destinationIndex: Int,
        channel: Int = 0,
        timeout: TimeInterval = 8,
        shouldCancel: @escaping @Sendable () -> Bool = { false }
    ) throws -> TX81ZVoiceBankData {
        var voices: [TX81ZVoiceData] = []
        voices.reserveCapacity(TX81ZVoiceBankData.voiceCount)

        for index in 0..<TX81ZVoiceBankData.voiceCount {
            if shouldCancel() {
                throw CancellationError()
            }
            let fetched = try fetchCurrentVoice(
                sourceIndex: sourceIndex,
                destinationIndex: destinationIndex,
                channel: channel,
                timeout: timeout
            )
            voices.append(fetched.voice)

            if index < TX81ZVoiceBankData.voiceCount - 1 {
                try FB01MIDI.sendSysEx(
                    remoteSwitchMessages(.dataEntryPlus, channel: channel),
                    destinationIndex: destinationIndex,
                    delayBetweenMessages: 0.06
                )
                Thread.sleep(forTimeInterval: 0.12)
            }
        }

        return try TX81ZVoiceBankData(voices: voices, channel: channel)
    }

    /// Replaces the TX81Z edit buffer with a complete ACED + VCED pair.
    /// This does not store the voice to nonvolatile memory.
    public func editBufferMessages(
        for voice: TX81ZVoiceData,
        channel: Int
    ) throws -> [[UInt8]] {
        try voice.bulkMessages(channel: channel)
    }

    /// Replaces the complete writable Bank I VMEM image. Callers must first
    /// fetch the current bank and replace only the intended slot.
    public func voiceMemoryBankStoreMessages(
        for bank: TX81ZVoiceBankData,
        channel: Int
    ) throws -> [[UInt8]] {
        [try bank.voiceMemoryBulkSysEx(channel: channel)]
    }
}

public struct TX81ZModuleServices: SynthModuleServiceProviding {
    public typealias Module = TX81ZSynthModule

    public static let shared = TX81ZModuleServices()

    public let module = TX81ZSynthModule.shared
    public let voiceService = TX81ZVoiceService.shared

    private init() {}
}

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
    /// emulation.
    public enum RemoteSwitch: Int, Sendable {
        case store = 65
        case play = 68
        case dataEntryMinus = 71
        case dataEntryPlus = 72
    }

    public func remoteSwitchMessage(
        _ remoteSwitch: RemoteSwitch,
        pressed: Bool,
        channel: Int = 0
    ) throws -> [UInt8] {
        guard (0...15).contains(channel) else {
            throw TX81ZSysExError.invalidChannel(channel)
        }
        return [
            TX81Z.start, TX81Z.yamahaID, 0x10 | UInt8(channel), 0x13,
            UInt8(remoteSwitch.rawValue), pressed ? 0x7F : 0x00, TX81Z.end,
        ]
    }

    public func remoteSwitchMessages(
        _ remoteSwitch: RemoteSwitch,
        channel: Int = 0
    ) throws -> [[UInt8]] {
        [
            try remoteSwitchMessage(remoteSwitch, pressed: true, channel: channel),
            try remoteSwitchMessage(remoteSwitch, pressed: false, channel: channel),
        ]
    }

    /// Enters PLAY PERFORMANCE by following Yamaha's documented remote-control
    /// route: a harmless VCED poly-mode parameter change enters SINGLE EDIT,
    /// then two PLAY/PERFORM presses reach PLAY PERFORMANCE. The VCED write
    /// affects only the volatile edit buffer; the Performance store sequence
    /// replaces PCED immediately after.
    public func performanceModePreparationMessages(channel: Int = 0) throws -> [[UInt8]] {
        guard (0...15).contains(channel) else {
            throw TX81ZSysExError.invalidChannel(channel)
        }
        let enterSingleEdit: [UInt8] = [
            TX81Z.start, TX81Z.yamahaID, 0x10 | UInt8(channel), 0x12, 63, 0, TX81Z.end,
        ]
        return [enterSingleEdit]
            + (try remoteSwitchMessages(.play, channel: channel))
            + (try remoteSwitchMessages(.play, channel: channel))
    }

    private func enterPerformanceMode(destinationIndex: Int, channel: Int) throws {
        try FB01MIDI.sendSysEx(
            try performanceModePreparationMessages(channel: channel),
            destinationIndex: destinationIndex,
            delayBetweenMessages: 0.1
        )
        Thread.sleep(forTimeInterval: 0.2)
    }

    private func performanceNamesMatch(_ lhs: String, _ rhs: String) -> Bool {
        func normalizedName(_ name: String) -> String {
            String(name.unicodeScalars.filter {
                CharacterSet.alphanumerics.contains($0)
            }).uppercased()
        }
        return normalizedName(lhs) == normalizedName(rhs)
    }

    private func pressRemote(
        _ remoteSwitch: RemoteSwitch,
        destinationIndex: Int,
        channel: Int
    ) throws {
        try FB01MIDI.sendSysEx(
            try remoteSwitchMessages(remoteSwitch, channel: channel),
            destinationIndex: destinationIndex,
            delayBetweenMessages: 0.15
        )
        Thread.sleep(forTimeInterval: 0.2)
    }

    /// PMEM may contain duplicate Performance names, so a PCED name alone is
    /// not always enough to identify the selected slot. Walk backwards until
    /// a uniquely named neighbor appears, then restore the original position.
    private func resolvedPerformanceIndex(
        for current: TX81ZPerformanceData,
        performances: [TX81ZPerformanceData],
        sourceIndex: Int,
        destinationIndex: Int,
        channel: Int,
        timeout: TimeInterval,
        progress: @escaping @Sendable (String) -> Void
    ) throws -> Int {
        func matchingIndices(for name: String) -> [Int] {
            performances.prefix(24).indices.filter { performanceNamesMatch(performances[$0].name, name) }
        }

        let directMatches = matchingIndices(for: current.name)
        if directMatches.count == 1 { return directMatches[0] }

        progress("PCED name '\(current.name)' is ambiguous; locating a unique neighboring slot.")
        for distance in 1..<24 {
            try pressRemote(.dataEntryMinus, destinationIndex: destinationIndex, channel: channel)
            let neighboring = try fetchCurrentPerformance(
                sourceIndex: sourceIndex,
                destinationIndex: destinationIndex,
                channel: channel,
                timeout: timeout
            )
            let matches = matchingIndices(for: neighboring.name)
            progress("Reverse probe \(distance) returned '\(neighboring.name)'.")
            if matches.count == 1 {
                progress("Neighbor '\(neighboring.name)' maps to PMEM slot \(matches[0] + 1) after \(distance) reverse step(s).")
                for _ in 0..<distance {
                    try pressRemote(.dataEntryPlus, destinationIndex: destinationIndex, channel: channel)
                }
                let resolved = (matches[0] + distance) % 24
                progress("Unique neighbor '\(neighboring.name)' resolved the current slot as Performance \(resolved + 1).")
                return resolved
            }
        }
        throw TX81ZSysExError.performanceSelectionFailed(expected: "a uniquely identifiable Performance", actual: current.name)
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

    private func programChangeTable(from bytes: [UInt8]) throws -> [UInt8] {
        let identifier = TX81Z.programChangeTableIdentifier
        let dataLength = 256
        let expectedLength = 6 + identifier.count + dataLength + 2
        guard bytes.count == expectedLength,
              bytes[0] == TX81Z.start,
              bytes[1] == TX81Z.yamahaID,
              (bytes[2] & 0xF0) == 0x00,
              bytes[3] == TX81Z.additionalVoiceFormat,
              bytes[4] == 0x02,
              bytes[5] == 0x0A,
              Array(bytes[6..<(6 + identifier.count)]) == identifier,
              bytes.last == TX81Z.end else {
            throw TX81ZSysExError.invalidPerformanceBulkHeader
        }
        let dataStart = 6 + identifier.count
        let data = Array(bytes[dataStart..<(dataStart + dataLength)])
        let checksum = bytes[dataStart + dataLength]
        guard TX81Z.performanceChecksum(identifier: identifier, data: data) == checksum else {
            throw TX81ZSysExError.checksumMismatch(
                expected: TX81Z.performanceChecksum(identifier: identifier, data: data),
                actual: checksum
            )
        }
        return data
    }

    private func fetchProgramChangeTable(
        sourceIndex: Int,
        destinationIndex: Int,
        channel: Int,
        timeout: TimeInterval
    ) throws -> [UInt8] {
        let request = try TX81Z.requestProgramChangeTable(channel: channel)
        let messages = try FB01MIDI.sendAndReceiveIsolated(
            [request], sourceIndex: sourceIndex, destinationIndex: destinationIndex, timeout: timeout
        )
        guard let message = messages.first else { throw FB01MIDIError.timedOut("TX81Z Program Change Table") }
        return try programChangeTable(from: message)
    }

    public func fetchMemoryProtectEnabled(
        sourceIndex: Int,
        destinationIndex: Int,
        channel: Int = 0,
        timeout: TimeInterval = 8
    ) throws -> Bool {
        let identifier = TX81Z.systemSetupIdentifier
        let dataLength = 27
        let request = try TX81Z.requestSystemSetup(channel: channel)
        let messages = try FB01MIDI.sendAndReceiveIsolated(
            [request], sourceIndex: sourceIndex, destinationIndex: destinationIndex, timeout: timeout
        )
        guard let bytes = messages.first,
              bytes.count == 6 + identifier.count + dataLength + 2,
              bytes[0] == TX81Z.start,
              bytes[1] == TX81Z.yamahaID,
              (bytes[2] & 0xF0) == 0x00,
              bytes[3] == TX81Z.additionalVoiceFormat,
              bytes[4] == 0x00,
              bytes[5] == 0x25,
              Array(bytes[6..<(6 + identifier.count)]) == identifier,
              bytes.last == TX81Z.end else {
            throw TX81ZSysExError.invalidPerformanceBulkHeader
        }
        let dataStart = 6 + identifier.count
        let data = Array(bytes[dataStart..<(dataStart + dataLength)])
        let checksum = bytes[dataStart + dataLength]
        guard TX81Z.performanceChecksum(identifier: identifier, data: data) == checksum else {
            throw TX81ZSysExError.checksumMismatch(
                expected: TX81Z.performanceChecksum(identifier: identifier, data: data), actual: checksum
            )
        }
        return data[8] != 0
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
        for message in messages {
            if let bank = try? voiceMemoryBank(from: message) {
                return bank
            }
        }
        throw FB01MIDIError.timedOut("TX81Z Voice Bank I")
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

    /// Selects a stored Performance using the same DATA ENTRY controls as the
    /// TX81Z front panel. This avoids mutating the user's Program Change map.
    private func selectStoredPerformance(
        at index: Int,
        sourceIndex: Int,
        destinationIndex: Int,
        channel: Int,
        timeout: TimeInterval,
        progress: @escaping @Sendable (String) -> Void = { _ in }
    ) throws {
        progress("Reading PMEM to resolve Performance \(index + 1).")
        let bank = try fetchPerformanceMemoryBank(
            sourceIndex: sourceIndex,
            destinationIndex: destinationIndex,
            channel: channel,
            timeout: timeout
        )
        let performances = bank.performances
        let targetName = performances[index].name

        progress("Entering PLAY PERFORMANCE for '\(targetName)'.")
        try enterPerformanceMode(destinationIndex: destinationIndex, channel: channel)

        if let table = try? fetchProgramChangeTable(
            sourceIndex: sourceIndex,
            destinationIndex: destinationIndex,
            channel: channel,
            timeout: timeout
        ) {
            let targetMemory = 5 * 32 + index
            if let program = (0..<128).first(where: { program in
                let offset = program * 2
                return ((Int(table[offset]) << 7) | Int(table[offset + 1])) == targetMemory
            }) {
                progress("Program Change \(program) maps directly to Performance \(index + 1).")
            } else {
                progress("No Program Change entry maps directly to Performance \(index + 1).")
            }
        } else {
            progress("Program Change table could not be read; using remote selection.")
        }

        let current = try fetchCurrentPerformance(
            sourceIndex: sourceIndex,
            destinationIndex: destinationIndex,
            channel: channel,
            timeout: timeout
        )
        progress("Current PCED is '\(current.name)'.")
        let currentIndex = try resolvedPerformanceIndex(
            for: current,
            performances: performances,
            sourceIndex: sourceIndex,
            destinationIndex: destinationIndex,
            channel: channel,
            timeout: timeout,
            progress: progress
        )

        var selectedIndex = currentIndex
        for attempt in 1...3 {
            let forward = (index - selectedIndex + 24) % 24
            let backward = (selectedIndex - index + 24) % 24
            guard forward != 0 || backward != 0 else {
                progress("Confirmed Performance \(index + 1) is selected.")
                return
            }

            let step = forward <= backward ? RemoteSwitch.dataEntryPlus : .dataEntryMinus
            let steps = min(forward, backward)
            progress("Selection pass \(attempt): sending \(steps) remote DATA \(step == .dataEntryPlus ? "+" : "-") press(es).")
            for _ in 0..<steps {
                try pressRemote(step, destinationIndex: destinationIndex, channel: channel)
            }

            let selected = try fetchCurrentPerformance(
                sourceIndex: sourceIndex,
                destinationIndex: destinationIndex,
                channel: channel,
                timeout: timeout
            )
            progress("Selection pass \(attempt) returned PCED '\(selected.name)'.")
            let observedIndex = try resolvedPerformanceIndex(
                for: selected,
                performances: performances,
                sourceIndex: sourceIndex,
                destinationIndex: destinationIndex,
                channel: channel,
                timeout: timeout,
                progress: progress
            )
            if observedIndex == index { return }
            selectedIndex = observedIndex
        }

        let selected = try fetchCurrentPerformance(
            sourceIndex: sourceIndex,
            destinationIndex: destinationIndex,
            channel: channel,
            timeout: timeout
        )
        throw TX81ZSysExError.performanceSelectionFailed(expected: targetName, actual: selected.name)
    }

    /// Selects Performance 1...24 and reads the resulting PCED edit buffer.
    public func fetchStoredPerformance(
        at index: Int,
        sourceIndex: Int,
        destinationIndex: Int,
        channel: Int = 0,
        timeout: TimeInterval = 8,
        progress: @escaping @Sendable (String) -> Void = { _ in }
    ) throws -> TX81ZPerformanceData {
        guard (0..<24).contains(index) else { throw TX81ZSysExError.invalidPerformanceParameter }
        try selectStoredPerformance(
            at: index,
            sourceIndex: sourceIndex,
            destinationIndex: destinationIndex,
            channel: channel,
            timeout: timeout,
            progress: progress
        )
        let request = try currentPerformanceDumpRequest(channel: channel)
        let messages = try FB01MIDI.sendAndReceiveIsolated(
            [request],
            sourceIndex: sourceIndex,
            destinationIndex: destinationIndex,
            timeout: timeout,
            maxMessages: 1
        )
        guard let message = messages.first else { throw FB01MIDIError.timedOut("TX81Z Performance \(index + 1)") }
        return try currentPerformance(from: message)
    }

    public func performanceEditBufferMessages(for performance: TX81ZPerformanceData, channel: Int) throws -> [[UInt8]] {
        [try performance.performanceEditBulkSysEx(channel: channel)]
    }

    /// Permanently stores a PCED Performance into one of the TX81Z's 24
    /// writable Performance memories. This mirrors the documented panel
    /// sequence: select the destination, send PCED, STORE, then DATA ENTRY +.
    public func storePerformance(
        _ performance: TX81ZPerformanceData,
        at index: Int,
        sourceIndex: Int,
        destinationIndex: Int,
        channel: Int = 0,
        progress: @escaping @Sendable (String) -> Void = { _ in }
    ) throws {
        guard (0..<24).contains(index) else { throw TX81ZSysExError.invalidPerformanceParameter }

        // MLOCK is a System Setup parameter, so this deliberately enters
        // Utility. Leave Utility before the normal Performance Play sequence
        // below selects the destination slot.
        progress("Turning TX81Z Memory Protect OFF.")
        try FB01MIDI.sendSysEx(
            [try TX81Z.memoryProtectMessage(channel: channel, enabled: false)],
            destinationIndex: destinationIndex,
            delayBetweenMessages: 0
        )
        Thread.sleep(forTimeInterval: 0.2)
        progress("Leaving System Setup and preparing PLAY PERFORMANCE.")
        try pressRemote(.play, destinationIndex: destinationIndex, channel: channel)

        try selectStoredPerformance(
            at: index,
            sourceIndex: sourceIndex,
            destinationIndex: destinationIndex,
            channel: channel,
            timeout: 12,
            progress: progress
        )

        progress("Sending PCED '\(performance.name)' to the Performance edit buffer.")
        try FB01MIDI.sendSysEx(
            try performanceEditBufferMessages(for: performance, channel: channel),
            destinationIndex: destinationIndex,
            delayBetweenMessages: 0.12
        )
        Thread.sleep(forTimeInterval: 0.15)

        let storeDown = try remoteSwitchMessage(.store, pressed: true, channel: channel)
        let dataPlus = try remoteSwitchMessages(.dataEntryPlus, channel: channel)
        let storeUp = try remoteSwitchMessage(.store, pressed: false, channel: channel)
        progress("Sending STORE down, destination confirm, STORE up, and final confirm.")
        try FB01MIDI.sendSysEx(
            [storeDown] + dataPlus + [storeUp] + dataPlus,
            destinationIndex: destinationIndex,
            delayBetweenMessages: 0.15
        )
        Thread.sleep(forTimeInterval: 0.35)
        progress("Store gesture complete; caller must verify PCED and PMEM.")
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
        let messages = try FB01MIDI.sendAndReceiveIsolated(
            [[0xC0 | UInt8(channel), UInt8(index)], request],
            sourceIndex: sourceIndex,
            destinationIndex: destinationIndex,
            timeout: timeout,
            maxMessages: 2
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
        shouldCancel: @escaping @Sendable () -> Bool = { false },
        progress: @escaping @Sendable (Int, String) -> Void = { _, _ in }
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
            if let previous = voices.last, previous == fetched.voice {
                throw TX81ZSysExError.factoryVoiceCaptureDidNotAdvance(slot: index)
            }
            voices.append(fetched.voice)
            progress(index + 1, fetched.voice.name)

            if index < TX81ZVoiceBankData.voiceCount - 1 {
                try pressRemote(.dataEntryPlus, destinationIndex: destinationIndex, channel: channel)
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

    /// Writes the complete Bank I VMEM image after explicitly disabling Memory
    /// Protect. The TX81Z leaves Memory Protect OFF after the bulk write, so
    /// callers should keep their UI state in sync and verify with a fresh dump.
    public func writeVoiceMemoryBank(
        _ bank: TX81ZVoiceBankData,
        destinationIndex: Int,
        channel: Int,
        progress: @escaping @Sendable (String) -> Void = { _ in }
    ) throws {
        progress("Turning TX81Z Memory Protect OFF.")
        try FB01MIDI.sendSysEx(
            [try TX81Z.memoryProtectMessage(channel: channel, enabled: false)],
            destinationIndex: destinationIndex,
            delayBetweenMessages: 0
        )
        Thread.sleep(forTimeInterval: 0.2)

        progress("Writing the complete TX81Z Bank I VMEM image.")
        guard let message = try voiceMemoryBankStoreMessages(for: bank, channel: channel).first else {
            throw TX81ZSysExError.invalidAdditionalVoiceBulkHeader
        }
        try FB01MIDI.sendLongSysEx(message, destinationIndex: destinationIndex, timeout: 45)
        Thread.sleep(forTimeInterval: 0.75)
    }
}

public struct TX81ZModuleServices: SynthModuleServiceProviding {
    public typealias Module = TX81ZSynthModule

    public static let shared = TX81ZModuleServices()

    public let module = TX81ZSynthModule.shared
    public let voiceService = TX81ZVoiceService.shared

    private init() {}
}

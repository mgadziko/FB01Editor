import FB01Editor
import Foundation

enum ForestCLIError: Error, CustomStringConvertible {
    case usage(String)
    case stateMissing(String)
    case unsupported(String)
    case invalidValue(String)

    var description: String {
        switch self {
        case .usage(let message), .stateMissing(let message), .unsupported(let message), .invalidValue(let message):
            message
        }
    }
}

private enum ForestCLIDX100Log {
    static func write(_ message: String) {
        fputs("[forest-cli] \(message)\n", stderr)
    }
}

enum ForestCLIDevice: String, Codable {
    case dx100
    case fb01
    case tx81z

    var displayName: String {
        switch self {
        case .dx100:
            "DX100"
        case .fb01:
            "FB-01"
        case .tx81z:
            "TX81Z"
        }
    }
}

struct ForestCLICachedVoice: Codable {
    var device: ForestCLIDevice
    var title: String
    var sysExBytes: [UInt8]
}

struct ForestCLIState: Codable {
    var selectedDevice: ForestCLIDevice
    var sourceIndex: Int
    var destinationIndex: Int
    var systemChannel: Int
    var cachedVoice: ForestCLICachedVoice?
}

enum ForestCLIStateStore {
    static let url = URL(fileURLWithPath: "/Users/ricercar/Documents/GitHub/FB01Editor/tmp/forest-cli-state.json")

    static func load() throws -> ForestCLIState {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ForestCLIState.self, from: data)
    }

    static func save(_ state: ForestCLIState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(state)
        try data.write(to: url, options: .atomic)
    }
}

struct ForestCLIEndpoint {
    var index: Int
    var displayName: String
}

enum ForestCLIEndpointResolver {
    static func source(matching query: String?) throws -> ForestCLIEndpoint {
        try resolve(query: query, endpoints: FB01MIDI.availableSources().map { .init(index: $0.index, displayName: $0.displayName) }, kind: "source")
    }

    static func destination(matching query: String?) throws -> ForestCLIEndpoint {
        try resolve(query: query, endpoints: FB01MIDI.availableDestinations().map { .init(index: $0.index, displayName: $0.displayName) }, kind: "destination")
    }

    private static func resolve(query: String?, endpoints: [ForestCLIEndpoint], kind: String) throws -> ForestCLIEndpoint {
        guard !endpoints.isEmpty else {
            throw ForestCLIError.stateMissing("No MIDI \(kind)s are visible to CoreMIDI.")
        }

        guard let query, !query.isEmpty else {
            return endpoints[0]
        }

        if let index = Int(query), let endpoint = endpoints.first(where: { $0.index == index }) {
            return endpoint
        }

        if let endpoint = endpoints.first(where: { $0.displayName.localizedCaseInsensitiveContains(query) }) {
            return endpoint
        }

        let available = endpoints.map { "[\($0.index)] \($0.displayName)" }.joined(separator: ", ")
        throw ForestCLIError.invalidValue("No MIDI \(kind) matches '\(query)'. Available: \(available)")
    }
}

struct ForestCLI {
    func run(arguments: [String]) throws {
        guard let command = arguments.first else {
            printHelp()
            return
        }

        switch command {
        case "help", "--help", "-h":
            printHelp()
        case "list-midi":
            listMIDI()
        case "select-device":
            try selectDevice(arguments: Array(arguments.dropFirst()))
        case "status":
            try printStatus()
        case "show-bank":
            try showBank(arguments: Array(arguments.dropFirst()))
        case "fetch-current-voice":
            try fetchCurrentVoice()
        case "store-internal-slot":
            try storeInternalSlot(arguments: Array(arguments.dropFirst()))
        case "store-bank-i":
            try storeTX81ZBankI(arguments: Array(arguments.dropFirst()))
        case "store-bank-i-slot":
            try storeTX81ZBankISlot(arguments: Array(arguments.dropFirst()))
        case "fetch-bank-i-slot":
            try fetchTX81ZBankISlot(arguments: Array(arguments.dropFirst()))
        case "tx81z-data-plus":
            try tx81zDataEntryPlus(arguments: Array(arguments.dropFirst()))
        case "tx81z-copy-performance":
            try copyTX81ZPerformance(arguments: Array(arguments.dropFirst()))
        case "tx81z-memory-protect":
            try printTX81ZMemoryProtect(arguments: Array(arguments.dropFirst()))
        case "tx81z-list-performances":
            try listTX81ZPerformances(arguments: Array(arguments.dropFirst()))
        default:
            throw ForestCLIError.usage("Unknown command '\(command)'. Run `forest-cli help`.")
        }
    }

    private func printHelp() {
        print(
            """
            Forest control CLI

            Commands:
              forest-cli list-midi
              forest-cli select-device <dx100|fb01|tx81z> [--source <index-or-name>] [--destination <index-or-name>] [--channel <1-16>]
              forest-cli status
              forest-cli show-bank <internal|a|b|c|d|1-7|i>
              forest-cli fetch-current-voice
              forest-cli store-internal-slot <1-24>
              forest-cli store-bank-i
              forest-cli store-bank-i-slot <1-32>
              forest-cli fetch-bank-i-slot <1-32>
              forest-cli tx81z-data-plus
              forest-cli tx81z-copy-performance <source-1-24> <destination-1-24>
              forest-cli tx81z-memory-protect
              forest-cli tx81z-list-performances

            Notes:
              - This first CLI slice is optimized for high-value current-voice, DX100 Internal-bank, and TX81Z Bank I workflows.
              - `fetch-current-voice` caches the fetched voice in tmp/forest-cli-state.json.
              - `store-internal-slot` stores the cached DX100 voice into the selected Internal slot.
              - `store-bank-i` saves a timestamped backup, turns TX81Z Memory Protect OFF, rewrites Bank I, and verifies it by refetching.
              - `store-bank-i-slot` saves a timestamped backup, turns TX81Z Memory Protect OFF, stores the cached voice in Bank I, and verifies that slot.
              - `fetch-bank-i-slot` selects one Bank I voice, fetches its complete ACED + VCED data, and caches it for a later slot store.
              - `tx81z-data-plus` presses the TX81Z's documented remote DATA ENTRY + switch once.
              - `tx81z-copy-performance` copies one stored TX81Z Performance into another slot and verifies the result.
              - `tx81z-memory-protect` reads the TX81Z System Setup MLOCK state.
              - `tx81z-list-performances` reads and lists all 32 PMEM Performance names.
            """
        )
    }

    private func listMIDI() {
        print("Sources")
        let sources = FB01MIDI.availableSources()
        if sources.isEmpty {
            print("  none")
        } else {
            for source in sources {
                print("  [\(source.index)] \(source.displayName)")
            }
        }

        print("Destinations")
        let destinations = FB01MIDI.availableDestinations()
        if destinations.isEmpty {
            print("  none")
        } else {
            for destination in destinations {
                print("  [\(destination.index)] \(destination.displayName)")
            }
        }
    }

    private func selectDevice(arguments: [String]) throws {
        guard let deviceToken = arguments.first,
              let device = ForestCLIDevice(rawValue: deviceToken.lowercased()) else {
            throw ForestCLIError.usage("Usage: forest-cli select-device <dx100|fb01|tx81z> [--source <index-or-name>] [--destination <index-or-name>] [--channel <1-16>]")
        }

        var sourceQuery: String?
        var destinationQuery: String?
        var channel = 1

        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--source":
                index += 1
                guard index < arguments.count else { throw ForestCLIError.usage("Missing value for --source") }
                sourceQuery = arguments[index]
            case "--destination":
                index += 1
                guard index < arguments.count else { throw ForestCLIError.usage("Missing value for --destination") }
                destinationQuery = arguments[index]
            case "--channel":
                index += 1
                guard index < arguments.count else { throw ForestCLIError.usage("Missing value for --channel") }
                guard let parsed = Int(arguments[index]), (1...16).contains(parsed) else {
                    throw ForestCLIError.invalidValue("Channel must be 1...16.")
                }
                channel = parsed
            default:
                throw ForestCLIError.usage("Unknown option '\(argument)' for select-device.")
            }
            index += 1
        }

        let source = try ForestCLIEndpointResolver.source(matching: sourceQuery)
        let destination = try ForestCLIEndpointResolver.destination(matching: destinationQuery)
        let state = ForestCLIState(
            selectedDevice: device,
            sourceIndex: source.index,
            destinationIndex: destination.index,
            systemChannel: channel - 1,
            cachedVoice: nil
        )
        try ForestCLIStateStore.save(state)

        print("Selected \(device.displayName)")
        print("  MIDI In : [\(source.index)] \(source.displayName)")
        print("  MIDI Out: [\(destination.index)] \(destination.displayName)")
        print("  Channel : \(channel)")
    }

    private func printStatus() throws {
        let state = try ForestCLIStateStore.load()
        print("Device    : \(state.selectedDevice.displayName)")
        print("MIDI In   : \(describeSource(index: state.sourceIndex))")
        print("MIDI Out  : \(describeDestination(index: state.destinationIndex))")
        print("Channel   : \(state.systemChannel + 1)")
        if let cachedVoice = state.cachedVoice {
            print("Cached    : \(cachedVoice.device.displayName) \(cachedVoice.title)")
        } else {
            print("Cached    : none")
        }
    }

    private func showBank(arguments: [String]) throws {
        guard let bankToken = arguments.first else {
            throw ForestCLIError.usage("Usage: forest-cli show-bank <internal|a|b|c|d|1-7>")
        }

        let state = try ForestCLIStateStore.load()
        switch state.selectedDevice {
        case .dx100:
            try showDXBank(bankToken: bankToken, state: state)
        case .fb01:
            try showFBBank(bankToken: bankToken, state: state)
        case .tx81z:
            try showTX81ZBank(bankToken: bankToken, state: state)
        }
    }

    private func fetchCurrentVoice() throws {
        var state = try ForestCLIStateStore.load()

        switch state.selectedDevice {
        case .dx100:
            let fetched = try fetchDX100CurrentVoice(
                state: state,
                timeout: 8,
                attempts: 3,
                preflightDelay: 0.35
            )
            let bytes = try fetched.voice.singleVoiceBulkSysEx(channel: fetched.channel)
            state.cachedVoice = ForestCLICachedVoice(device: .dx100, title: fetched.voice.name.isEmpty ? "Untitled" : fetched.voice.name, sysExBytes: bytes)
            try ForestCLIStateStore.save(state)
            print("Fetched DX100 current voice: \(state.cachedVoice?.title ?? "Untitled")")
        case .fb01:
            let fetched = try FB01VoiceService.shared.fetchInstrumentVoice(
                instrument: 0,
                sourceIndex: state.sourceIndex,
                destinationIndex: state.destinationIndex,
                systemChannel: state.systemChannel,
                timeout: 8
            )
            let bytes = try fetched.voice.instrumentVoiceArtifact(systemChannel: fetched.systemChannel, instrument: 0).sysexBytes
            state.cachedVoice = ForestCLICachedVoice(device: .fb01, title: fetched.voice.name.isEmpty ? "Untitled" : fetched.voice.name, sysExBytes: bytes)
            try ForestCLIStateStore.save(state)
            print("Fetched FB-01 current Instrument 1 voice: \(state.cachedVoice?.title ?? "Untitled")")
        case .tx81z:
            let fetched = try TX81ZModuleServices.shared.voiceService.fetchCurrentVoice(
                sourceIndex: state.sourceIndex,
                destinationIndex: state.destinationIndex,
                channel: state.systemChannel,
                timeout: 8
            )
            let bytes = try fetched.voice.bulkMessages(channel: fetched.channel).flatMap { $0 }
            state.cachedVoice = ForestCLICachedVoice(device: .tx81z, title: fetched.voice.name.isEmpty ? "Untitled" : fetched.voice.name, sysExBytes: bytes)
            try ForestCLIStateStore.save(state)
            print("Fetched TX81Z current voice: \(state.cachedVoice?.title ?? "Untitled")")
        }
    }

    private func storeInternalSlot(arguments: [String]) throws {
        guard let slotToken = arguments.first,
              let slotNumber = Int(slotToken),
              (1...24).contains(slotNumber) else {
            throw ForestCLIError.usage("Usage: forest-cli store-internal-slot <1-24>")
        }

        let state = try ForestCLIStateStore.load()
        guard state.selectedDevice == .dx100 else {
            throw ForestCLIError.unsupported("store-internal-slot currently supports DX100 only.")
        }
        guard let cachedVoice = state.cachedVoice, cachedVoice.device == .dx100 else {
            throw ForestCLIError.stateMissing("No cached DX100 voice. Run `forest-cli fetch-current-voice` first.")
        }

        let voice = try DX100VoiceData(singleVoiceBulkSysEx: cachedVoice.sysExBytes)
        ForestCLIDX100Log.write("Fetching DX100 Internal before store...")
        var bank = try fetchDX100InternalBank(state: state, timeout: 10, attempts: 3, preflightDelay: 0.45)
        bank = try bank.replacingVoice(atPackedVoiceIndex: slotNumber - 1, with: voice)

        let writeMessages = try DX100ModuleServices.shared.voiceService.voiceBankMessages(for: bank, channel: state.systemChannel)
        guard let loadMessage = writeMessages.first else {
            throw ForestCLIError.stateMissing("Forest could not build a DX100 Internal bank store message.")
        }
        ForestCLIDX100Log.write("Sending DX100 Internal bank write for slot \(slotNumber)...")
        try recoverDX100PlayMode(state: state, settleDelay: 0.35)
        try FB01MIDI.sendLongSysEx(loadMessage, destinationIndex: state.destinationIndex, timeout: 45)
        Thread.sleep(forTimeInterval: 0.75)
        try? recoverDX100PlayMode(state: state, settleDelay: 0.45)
        Thread.sleep(forTimeInterval: 0.55)

        ForestCLIDX100Log.write("Verifying DX100 Internal after store...")
        do {
            let verified = try fetchDX100InternalBank(state: state, timeout: 6, attempts: 2, preflightDelay: 0.3)
            let verifiedVoice = try verified.voice(atPackedVoiceIndex: slotNumber - 1)
            guard verifiedVoice == voice else {
                throw ForestCLIError.stateMissing("Verification mismatch after storing DX100 Internal slot \(slotNumber).")
            }
            print("Stored \(cachedVoice.title) in DX100 Internal slot \(slotNumber).")
        } catch {
            ForestCLIDX100Log.write("DX100 verify incomplete after store: \(error)")
            print("Stored \(cachedVoice.title) in DX100 Internal slot \(slotNumber). Verification incomplete: \(error)")
        }
    }

    private func storeTX81ZBankI(arguments: [String]) throws {
        guard arguments.isEmpty else {
            throw ForestCLIError.usage("Usage: forest-cli store-bank-i")
        }

        let state = try ForestCLIStateStore.load()
        guard state.selectedDevice == .tx81z else {
            throw ForestCLIError.unsupported("store-bank-i currently supports TX81Z only.")
        }

        print("Fetching TX81Z Bank I...")
        let bank = try TX81ZModuleServices.shared.voiceService.fetchVoiceMemoryBank(
            sourceIndex: state.sourceIndex,
            destinationIndex: state.destinationIndex,
            channel: state.systemChannel,
            timeout: 12
        )
        let backupURL = try saveTX81ZBankIBackup(bank, channel: state.systemChannel)
        print("Backup saved to \(backupURL.path).")

        print("Turning TX81Z Memory Protect OFF and writing the unchanged Bank I image...")
        try TX81ZModuleServices.shared.voiceService.writeVoiceMemoryBank(
            bank,
            destinationIndex: state.destinationIndex,
            channel: state.systemChannel
        )

        print("Refetching TX81Z Bank I for verification...")
        let verified = try TX81ZModuleServices.shared.voiceService.fetchVoiceMemoryBank(
            sourceIndex: state.sourceIndex,
            destinationIndex: state.destinationIndex,
            channel: state.systemChannel,
            timeout: 12
        )
        guard verified == bank else {
            throw ForestCLIError.stateMissing("TX81Z Bank I verification mismatch after store.")
        }
        print("Stored and verified TX81Z Bank I (unchanged image). Memory Protect remains OFF after the bulk write.")
    }

    private func storeTX81ZBankISlot(arguments: [String]) throws {
        guard let slotToken = arguments.first,
              let slotNumber = Int(slotToken),
              (1...TX81ZVoiceBankData.voiceCount).contains(slotNumber) else {
            throw ForestCLIError.usage("Usage: forest-cli store-bank-i-slot <1-32>")
        }

        let state = try ForestCLIStateStore.load()
        guard state.selectedDevice == .tx81z else {
            throw ForestCLIError.unsupported("store-bank-i-slot currently supports TX81Z only.")
        }
        guard let cachedVoice = state.cachedVoice, cachedVoice.device == .tx81z else {
            throw ForestCLIError.stateMissing("No cached TX81Z voice. Run `forest-cli fetch-current-voice` first.")
        }

        let voice = try TX81ZVoiceData(messages: TX81Z.splitSysExMessages(from: cachedVoice.sysExBytes))
        print("Fetching TX81Z Bank I before storing " + cachedVoice.title + " in slot " + String(slotNumber) + "...")
        let bank = try TX81ZModuleServices.shared.voiceService.fetchVoiceMemoryBank(
            sourceIndex: state.sourceIndex,
            destinationIndex: state.destinationIndex,
            channel: state.systemChannel,
            timeout: 12
        )
        let updatedBank = try bank.replacingVoice(at: slotNumber - 1, with: voice)
        let backupURL = try saveTX81ZBankIBackup(bank, channel: state.systemChannel)
        print("Backup saved to \(backupURL.path).")

        print("Turning TX81Z Memory Protect OFF and writing Bank I slot " + String(slotNumber) + "...")
        try TX81ZModuleServices.shared.voiceService.writeVoiceMemoryBank(
            updatedBank,
            destinationIndex: state.destinationIndex,
            channel: state.systemChannel
        )

        print("Verifying TX81Z Bank I slot " + String(slotNumber) + "...")
        let verified = try TX81ZModuleServices.shared.voiceService.fetchVoiceMemoryBank(
            sourceIndex: state.sourceIndex,
            destinationIndex: state.destinationIndex,
            channel: state.systemChannel,
            timeout: 12
        )
        guard try verified.voice(at: slotNumber - 1) == voice else {
            throw ForestCLIError.stateMissing("TX81Z Bank I slot " + String(slotNumber) + " did not match the stored voice after verification.")
        }
        print("Stored and verified " + cachedVoice.title + " in TX81Z Bank I slot " + String(slotNumber) + ". Memory Protect remains OFF after the bulk write.")
    }

    private func fetchTX81ZBankISlot(arguments: [String]) throws {
        guard arguments.count == 1,
              let slotNumber = Int(arguments[0]),
              (1...TX81ZVoiceBankData.voiceCount).contains(slotNumber) else {
            throw ForestCLIError.usage("Usage: forest-cli fetch-bank-i-slot <1-32>")
        }
        var state = try ForestCLIStateStore.load()
        guard state.selectedDevice == .tx81z else {
            throw ForestCLIError.unsupported("fetch-bank-i-slot currently supports TX81Z only.")
        }
        let fetched = try TX81ZModuleServices.shared.voiceService.fetchVoiceMemoryVoice(
            at: slotNumber - 1,
            sourceIndex: state.sourceIndex,
            destinationIndex: state.destinationIndex,
            channel: state.systemChannel
        )
        let title = fetched.voice.name.isEmpty ? "Untitled" : fetched.voice.name
        state.cachedVoice = ForestCLICachedVoice(
            device: .tx81z,
            title: title,
            sysExBytes: try fetched.voice.bulkMessages(channel: fetched.channel).flatMap { $0 }
        )
        try ForestCLIStateStore.save(state)
        print("Fetched and cached TX81Z Bank I slot \(slotNumber): \(title)")
    }

    private func tx81zDataEntryPlus(arguments: [String]) throws {
        guard arguments.isEmpty else {
            throw ForestCLIError.usage("Usage: forest-cli tx81z-data-plus")
        }
        let state = try ForestCLIStateStore.load()
        guard state.selectedDevice == .tx81z else {
            throw ForestCLIError.unsupported("tx81z-data-plus currently supports TX81Z only.")
        }
        let messages = try TX81ZModuleServices.shared.voiceService.remoteSwitchMessages(
            .dataEntryPlus,
            channel: state.systemChannel
        )
        try FB01MIDI.sendSysEx(messages, destinationIndex: state.destinationIndex, delayBetweenMessages: 0.1)
        print("Sent TX81Z remote DATA ENTRY +.")
    }

    private func copyTX81ZPerformance(arguments: [String]) throws {
        guard arguments.count == 2,
              let sourceNumber = Int(arguments[0]),
              let destinationNumber = Int(arguments[1]),
              (1...24).contains(sourceNumber),
              (1...24).contains(destinationNumber) else {
            throw ForestCLIError.usage("Usage: forest-cli tx81z-copy-performance <source-1-24> <destination-1-24>")
        }
        let state = try ForestCLIStateStore.load()
        guard state.selectedDevice == .tx81z else {
            throw ForestCLIError.unsupported("tx81z-copy-performance currently supports TX81Z only.")
        }

        let service = TX81ZModuleServices.shared.voiceService
        let source = try service.fetchStoredPerformance(
            at: sourceNumber - 1,
            sourceIndex: state.sourceIndex,
            destinationIndex: state.destinationIndex,
            channel: state.systemChannel,
            progress: { fputs("[TX81Z source] \($0)\n", stderr) }
        )
        try service.storePerformance(
            source,
            at: destinationNumber - 1,
            sourceIndex: state.sourceIndex,
            destinationIndex: state.destinationIndex,
            channel: state.systemChannel,
            progress: { fputs("[TX81Z store] \($0)\n", stderr) }
        )
        let verified = try service.fetchStoredPerformance(
            at: destinationNumber - 1,
            sourceIndex: state.sourceIndex,
            destinationIndex: state.destinationIndex,
            channel: state.systemChannel
        )
        guard verified == source else {
            throw ForestCLIError.stateMissing(
                "TX81Z Performance \(destinationNumber) did not match Performance \(sourceNumber) after storage. "
                    + "Expected '\(source.name)', edit buffer returned '\(verified.name)'."
            )
        }
        let bank = try service.fetchPerformanceMemoryBank(
            sourceIndex: state.sourceIndex,
            destinationIndex: state.destinationIndex,
            channel: state.systemChannel
        )
        let bankEntry = bank.performances[destinationNumber - 1]
        guard bankEntry.name.caseInsensitiveCompare(source.name) == .orderedSame else {
            throw ForestCLIError.stateMissing("TX81Z PMEM slot \(destinationNumber) contains '\(bankEntry.name)' after storing '\(source.name)'.")
        }
        print("Copied and verified TX81Z Performance \(sourceNumber) as Performance \(destinationNumber): \(source.name)")
    }

    private func printTX81ZMemoryProtect(arguments: [String]) throws {
        guard arguments.isEmpty else {
            throw ForestCLIError.usage("Usage: forest-cli tx81z-memory-protect")
        }
        let state = try ForestCLIStateStore.load()
        guard state.selectedDevice == .tx81z else {
            throw ForestCLIError.unsupported("tx81z-memory-protect currently supports TX81Z only.")
        }
        let enabled = try TX81ZModuleServices.shared.voiceService.fetchMemoryProtectEnabled(
            sourceIndex: state.sourceIndex,
            destinationIndex: state.destinationIndex,
            channel: state.systemChannel
        )
        print("TX81Z Memory Protect is \(enabled ? "ON" : "OFF").")
    }

    private func listTX81ZPerformances(arguments: [String]) throws {
        guard arguments.isEmpty else {
            throw ForestCLIError.usage("Usage: forest-cli tx81z-list-performances")
        }
        let state = try ForestCLIStateStore.load()
        guard state.selectedDevice == .tx81z else {
            throw ForestCLIError.unsupported("tx81z-list-performances currently supports TX81Z only.")
        }
        let bank = try TX81ZModuleServices.shared.voiceService.fetchPerformanceMemoryBank(
            sourceIndex: state.sourceIndex,
            destinationIndex: state.destinationIndex,
            channel: state.systemChannel
        )
        for (offset, performance) in bank.performances.enumerated() {
            print(String(format: "%2d  %@", offset + 1, performance.name))
        }
    }

    private func saveTX81ZBankIBackup(_ bank: TX81ZVoiceBankData, channel: Int) throws -> URL {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Forest Editor", isDirectory: true)
            .appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = directory.appendingPathComponent("TX81Z-Bank-I-before-store-\(formatter.string(from: Date())).txvb")
        try Data(try bank.voiceMemoryBulkSysEx(channel: channel)).write(to: url, options: .atomic)
        return url
    }

    private func fetchDX100InternalBank(
        state: ForestCLIState,
        timeout: TimeInterval,
        attempts: Int,
        preflightDelay: TimeInterval
    ) throws -> DX100VoiceBankData {
        let bankRequest = try DX100ModuleServices.shared.voiceService.voiceBankDumpRequest(channel: state.systemChannel)
        var lastError: Error?
        let preflightDelays: [TimeInterval] = [0, preflightDelay, max(preflightDelay, 0.6)]

        for attemptIndex in 0..<max(1, attempts) {
            do {
                ForestCLIDX100Log.write("DX100 Internal fetch attempt \(attemptIndex + 1)...")
                let attemptDelay = attemptIndex < preflightDelays.count ? preflightDelays[attemptIndex] : (preflightDelays.last ?? preflightDelay)
                if attemptDelay > 0 {
                    Thread.sleep(forTimeInterval: attemptDelay)
                }
                let response = try FB01MIDI.sendAndReceiveIsolated(
                    [bankRequest],
                    sourceIndex: state.sourceIndex,
                    destinationIndex: state.destinationIndex,
                    timeout: timeout,
                    maxMessages: 1
                )
                guard let bankBytes = response.first else {
                    throw FB01MIDIError.timedOut("DX100 Internal bank")
                }
                return try DX100ModuleServices.shared.voiceService.voiceBank(fromThirtyTwoVoiceBulkSysEx: bankBytes)
            } catch {
                lastError = error
                ForestCLIDX100Log.write("DX100 Internal fetch attempt \(attemptIndex + 1) failed: \(error)")
                Thread.sleep(forTimeInterval: 0.25)
            }
        }

        throw lastError ?? FB01MIDIError.timedOut("DX100 Internal bank")
    }

    private func fetchDX100CurrentVoice(
        state: ForestCLIState,
        timeout: TimeInterval,
        attempts: Int,
        preflightDelay: TimeInterval
    ) throws -> DX100FetchedVoice {
        let request = try DX100ModuleServices.shared.voiceService.singleVoiceDumpRequest(channel: state.systemChannel)
        var lastError: Error?

        for attemptIndex in 0..<max(1, attempts) {
            do {
                ForestCLIDX100Log.write("DX100 current voice fetch attempt \(attemptIndex + 1)...")
                if attemptIndex > 0 {
                    Thread.sleep(forTimeInterval: preflightDelay + (Double(attemptIndex) * 0.15))
                }
                let messages = try FB01MIDI.sendAndReceiveIsolated(
                    [request],
                    sourceIndex: state.sourceIndex,
                    destinationIndex: state.destinationIndex,
                    timeout: timeout,
                    maxMessages: 1
                )
                return try DX100ModuleServices.shared.voiceService.currentVoice(from: messages)
            } catch {
                lastError = error
                ForestCLIDX100Log.write("DX100 current voice fetch attempt \(attemptIndex + 1) failed: \(error)")
                Thread.sleep(forTimeInterval: 0.2)
            }
        }

        throw lastError ?? FB01MIDIError.timedOut("DX100 current voice")
    }

    private func recoverDX100PlayMode(
        state: ForestCLIState,
        settleDelay: TimeInterval
    ) throws {
        let pressBytes = try DX100.switchModeMessage(channel: state.systemChannel, switchNumber: 27, value: 127)
        let releaseBytes = try DX100.switchModeMessage(channel: state.systemChannel, switchNumber: 27, value: 0)
        try FB01MIDI.sendImmediate(pressBytes, destinationIndex: state.destinationIndex)
        Thread.sleep(forTimeInterval: 0.1)
        try FB01MIDI.sendImmediate(releaseBytes, destinationIndex: state.destinationIndex)
        if settleDelay > 0 {
            Thread.sleep(forTimeInterval: settleDelay)
        }
    }

    private func showDXBank(bankToken: String, state: ForestCLIState) throws {
        let normalized = bankToken.lowercased()
        guard normalized == "internal" else {
            throw ForestCLIError.unsupported("This first forest-cli pass supports DX100 `show-bank internal`. Assisted/manual A-D capture stays in the app for now.")
        }

        let bank = try fetchDX100InternalBank(state: state, timeout: 12, attempts: 3, preflightDelay: 0.45)

        print("DX100 Internal")
        for (index, name) in bank.dx100DisplayedVoiceNames.enumerated() {
            let title = name.isEmpty ? "Untitled" : name
            print(String(format: "%2d  %@", index + 1, title))
        }
    }

    private func showTX81ZBank(bankToken: String, state: ForestCLIState) throws {
        let normalized = bankToken.lowercased()
        guard ["1", "i", "voice-bank-i", "voicebanki"].contains(normalized) else {
            throw ForestCLIError.invalidValue("TX81Z currently exposes Voice Bank I. Use `forest-cli show-bank i`.")
        }

        let bank = try TX81ZModuleServices.shared.voiceService.fetchVoiceMemoryBank(
            sourceIndex: state.sourceIndex,
            destinationIndex: state.destinationIndex,
            channel: state.systemChannel,
            timeout: 12
        )
        print("TX81Z Voice Bank I")
        for (index, name) in bank.voiceNames.enumerated() {
            print(String(format: "%2d  %@", index + 1, name.isEmpty ? "Untitled" : name))
        }
    }

    private func showFBBank(bankToken: String, state: ForestCLIState) throws {
        guard let bank = Int(bankToken), (1...7).contains(bank) else {
            throw ForestCLIError.invalidValue("FB-01 banks must be 1...7.")
        }
        let bytes = try FB01MIDI.request(
            .voiceBank(bank),
            sourceIndex: state.sourceIndex,
            destinationIndex: state.destinationIndex,
            systemChannel: state.systemChannel,
            timeout: 15
        )
        let names = try FB01VoiceService.shared.voiceNames(fromVoiceBankDump: bytes, expectedDisplayBank: bank)

        print("FB-01 Bank \(bank)")
        for (index, name) in names.enumerated() {
            let title = name.isEmpty ? "Untitled" : name
            print(String(format: "%2d  %@", index + 1, title))
        }
    }

    private func describeSource(index: Int) -> String {
        FB01MIDI.availableSources().first(where: { $0.index == index }).map { "[\($0.index)] \($0.displayName)" } ?? "[\(index)] unavailable"
    }

    private func describeDestination(index: Int) -> String {
        FB01MIDI.availableDestinations().first(where: { $0.index == index }).map { "[\($0.index)] \($0.displayName)" } ?? "[\(index)] unavailable"
    }
}

do {
    try ForestCLI().run(arguments: Array(CommandLine.arguments.dropFirst()))
} catch {
    fputs("forest-cli: \(error)\n", stderr)
    exit(1)
}

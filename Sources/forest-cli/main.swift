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

    var displayName: String {
        switch self {
        case .dx100:
            "DX100"
        case .fb01:
            "FB-01"
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
              forest-cli select-device <dx100|fb01> [--source <index-or-name>] [--destination <index-or-name>] [--channel <1-16>]
              forest-cli status
              forest-cli show-bank <internal|a|b|c|d|1-7>
              forest-cli fetch-current-voice
              forest-cli store-internal-slot <1-24>

            Notes:
              - This first CLI slice is optimized for high-value current-voice and DX100 Internal-bank workflows.
              - `fetch-current-voice` caches the fetched voice in tmp/forest-cli-state.json.
              - `store-internal-slot` stores the cached DX100 voice into the selected Internal slot.
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
            throw ForestCLIError.usage("Usage: forest-cli select-device <dx100|fb01> [--source <index-or-name>] [--destination <index-or-name>] [--channel <1-16>]")
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

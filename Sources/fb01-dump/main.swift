import CoreMIDI
import FB01Editor
import Foundation

enum FB01DumpError: Error, CustomStringConvertible {
    case commandFailed(String, OSStatus)
    case missingValue(String)
    case noSources
    case noDestinations
    case sourceNotFound(String)
    case destinationNotFound(String)
    case unknownArgument(String)

    var description: String {
        switch self {
        case let .commandFailed(operation, status):
            "\(operation) failed with OSStatus \(status)"
        case .missingValue(let option):
            "Missing value for \(option)"
        case .noSources:
            "No MIDI sources are visible to CoreMIDI."
        case .noDestinations:
            "No MIDI destinations are visible to CoreMIDI."
        case .sourceNotFound(let query):
            "No MIDI source matches \(query). Run `fb01-dump list` to inspect available sources."
        case .destinationNotFound(let query):
            "No MIDI destination matches \(query). Run `fb01-dump list` to inspect available destinations."
        case .unknownArgument(let argument):
            "Unknown argument: \(argument)"
        }
    }
}

struct MIDISourceInfo {
    var index: Int
    var endpoint: MIDIEndpointRef
    var displayName: String
    var uniqueID: Int32?
}

struct MIDIDestinationInfo {
    var index: Int
    var endpoint: MIDIEndpointRef
    var displayName: String
    var uniqueID: Int32?
}

struct CaptureOptions {
    var sourceQuery: String?
    var outputURL: URL?
    var timeoutSeconds: TimeInterval?
    var maxMessages: Int?
}

struct RequestOptions {
    var capture = CaptureOptions()
    var destinationQuery: String?
    var systemChannel = 0
    var bank = 0
}

enum DumpRequestKind {
    case unitID
    case currentConfiguration
    case voiceRAM1
    case voiceBank(Int)

    func bytes(systemChannel: Int) throws -> [UInt8] {
        switch self {
        case .unitID:
            try FB01Command.requestUnitID(systemChannel: systemChannel).bytes
        case .currentConfiguration:
            try FB01Command.requestCurrentConfiguration(systemChannel: systemChannel).bytes
        case .voiceRAM1:
            try FB01Command.requestVoiceRAM1(systemChannel: systemChannel).bytes
        case .voiceBank(let bank):
            try FB01Command.requestVoiceBank(systemChannel: systemChannel, bank: bank).bytes
        }
    }

    var displayName: String {
        switch self {
        case .unitID:
            "unit ID"
        case .currentConfiguration:
            "current configuration"
        case .voiceRAM1:
            "voice RAM 1"
        case .voiceBank(let bank):
            "voice bank \(bank)"
        }
    }
}

final class SysExCaptureState: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: [UInt8] = []
    private(set) var messages: [[UInt8]] = []

    func append(packetList: UnsafePointer<MIDIPacketList>) {
        var packet = packetList.pointee.packet

        for _ in 0..<packetList.pointee.numPackets {
            withUnsafeBytes(of: packet.data) { rawData in
                let bytes = Array(rawData.prefix(Int(packet.length)))
                append(bytes: bytes)
            }
            packet = MIDIPacketNext(&packet).pointee
        }
    }

    func snapshot() -> [[UInt8]] {
        lock.lock()
        defer { lock.unlock() }
        return messages
    }

    private func append(bytes: [UInt8]) {
        lock.lock()
        defer { lock.unlock() }

        for byte in bytes {
            if byte == FB01.start {
                buffer = [byte]
                continue
            }

            guard !buffer.isEmpty else {
                continue
            }

            buffer.append(byte)
            if byte == FB01.end {
                messages.append(buffer)
                buffer.removeAll(keepingCapacity: true)
            }
        }
    }
}

func check(_ status: OSStatus, _ operation: String) throws {
    guard status == noErr else {
        throw FB01DumpError.commandFailed(operation, status)
    }
}

func midiStringProperty(_ object: MIDIObjectRef, _ property: CFString) -> String? {
    var unmanaged: Unmanaged<CFString>?
    guard MIDIObjectGetStringProperty(object, property, &unmanaged) == noErr else {
        return nil
    }
    return unmanaged?.takeRetainedValue() as String?
}

func midiIntegerProperty(_ object: MIDIObjectRef, _ property: CFString) -> Int32? {
    var value: Int32 = 0
    guard MIDIObjectGetIntegerProperty(object, property, &value) == noErr else {
        return nil
    }
    return value
}

func availableSources() -> [MIDISourceInfo] {
    (0..<MIDIGetNumberOfSources()).map { index in
        let endpoint = MIDIGetSource(index)
        return MIDISourceInfo(
            index: index,
            endpoint: endpoint,
            displayName: midiStringProperty(endpoint, kMIDIPropertyDisplayName)
                ?? midiStringProperty(endpoint, kMIDIPropertyName)
                ?? "Source \(index)",
            uniqueID: midiIntegerProperty(endpoint, kMIDIPropertyUniqueID)
        )
    }
}

func availableDestinations() -> [MIDIDestinationInfo] {
    (0..<MIDIGetNumberOfDestinations()).map { index in
        let endpoint = MIDIGetDestination(index)
        return MIDIDestinationInfo(
            index: index,
            endpoint: endpoint,
            displayName: midiStringProperty(endpoint, kMIDIPropertyDisplayName)
                ?? midiStringProperty(endpoint, kMIDIPropertyName)
                ?? "Destination \(index)",
            uniqueID: midiIntegerProperty(endpoint, kMIDIPropertyUniqueID)
        )
    }
}

func selectedSource(matching query: String?, in sources: [MIDISourceInfo]) throws -> MIDISourceInfo {
    guard !sources.isEmpty else {
        throw FB01DumpError.noSources
    }

    guard let query, !query.isEmpty else {
        return sources[0]
    }

    if let index = Int(query), let source = sources.first(where: { $0.index == index }) {
        return source
    }

    if let source = sources.first(where: { $0.displayName.localizedCaseInsensitiveContains(query) }) {
        return source
    }

    throw FB01DumpError.sourceNotFound(query)
}

func selectedDestination(matching query: String?, in destinations: [MIDIDestinationInfo]) throws -> MIDIDestinationInfo {
    guard !destinations.isEmpty else {
        throw FB01DumpError.noDestinations
    }

    guard let query, !query.isEmpty else {
        return destinations[0]
    }

    if let index = Int(query), let destination = destinations.first(where: { $0.index == index }) {
        return destination
    }

    if let destination = destinations.first(where: { $0.displayName.localizedCaseInsensitiveContains(query) }) {
        return destination
    }

    throw FB01DumpError.destinationNotFound(query)
}

func printSources() {
    let sources = availableSources()
    let destinations = availableDestinations()

    print("Sources")
    if sources.isEmpty {
        print("  none")
    } else {
        for source in sources {
            let unique = source.uniqueID.map { " id=\($0)" } ?? ""
            print("  [\(source.index)] \(source.displayName)\(unique)")
        }
    }

    print("Destinations")
    if destinations.isEmpty {
        print("  none")
    } else {
        for destination in destinations {
            let unique = destination.uniqueID.map { " id=\($0)" } ?? ""
            print("  [\(destination.index)] \(destination.displayName)\(unique)")
        }
    }
}

func parseCaptureOptions(_ arguments: ArraySlice<String>) throws -> CaptureOptions {
    var options = CaptureOptions()
    var index = arguments.startIndex

    while index < arguments.endIndex {
        let argument = arguments[index]
        switch argument {
        case "--source", "-s":
            let valueIndex = arguments.index(after: index)
            guard valueIndex < arguments.endIndex else { throw FB01DumpError.missingValue(argument) }
            options.sourceQuery = arguments[valueIndex]
            index = arguments.index(after: valueIndex)
        case "--output", "-o":
            let valueIndex = arguments.index(after: index)
            guard valueIndex < arguments.endIndex else { throw FB01DumpError.missingValue(argument) }
            options.outputURL = URL(fileURLWithPath: arguments[valueIndex])
            index = arguments.index(after: valueIndex)
        case "--timeout":
            let valueIndex = arguments.index(after: index)
            guard valueIndex < arguments.endIndex else { throw FB01DumpError.missingValue(argument) }
            options.timeoutSeconds = TimeInterval(arguments[valueIndex])
            index = arguments.index(after: valueIndex)
        case "--count":
            let valueIndex = arguments.index(after: index)
            guard valueIndex < arguments.endIndex else { throw FB01DumpError.missingValue(argument) }
            options.maxMessages = Int(arguments[valueIndex])
            index = arguments.index(after: valueIndex)
        default:
            throw FB01DumpError.unknownArgument(argument)
        }
    }

    return options
}

func parseRequestOptions(_ arguments: ArraySlice<String>) throws -> RequestOptions {
    var options = RequestOptions()
    var index = arguments.startIndex

    while index < arguments.endIndex {
        let argument = arguments[index]
        switch argument {
        case "--source", "-s":
            let valueIndex = arguments.index(after: index)
            guard valueIndex < arguments.endIndex else { throw FB01DumpError.missingValue(argument) }
            options.capture.sourceQuery = arguments[valueIndex]
            index = arguments.index(after: valueIndex)
        case "--destination", "-d":
            let valueIndex = arguments.index(after: index)
            guard valueIndex < arguments.endIndex else { throw FB01DumpError.missingValue(argument) }
            options.destinationQuery = arguments[valueIndex]
            index = arguments.index(after: valueIndex)
        case "--output", "-o":
            let valueIndex = arguments.index(after: index)
            guard valueIndex < arguments.endIndex else { throw FB01DumpError.missingValue(argument) }
            options.capture.outputURL = URL(fileURLWithPath: arguments[valueIndex])
            index = arguments.index(after: valueIndex)
        case "--timeout":
            let valueIndex = arguments.index(after: index)
            guard valueIndex < arguments.endIndex else { throw FB01DumpError.missingValue(argument) }
            options.capture.timeoutSeconds = TimeInterval(arguments[valueIndex])
            index = arguments.index(after: valueIndex)
        case "--count":
            let valueIndex = arguments.index(after: index)
            guard valueIndex < arguments.endIndex else { throw FB01DumpError.missingValue(argument) }
            options.capture.maxMessages = Int(arguments[valueIndex])
            index = arguments.index(after: valueIndex)
        case "--system-channel":
            let valueIndex = arguments.index(after: index)
            guard valueIndex < arguments.endIndex else { throw FB01DumpError.missingValue(argument) }
            options.systemChannel = Int(arguments[valueIndex]) ?? options.systemChannel
            index = arguments.index(after: valueIndex)
        case "--bank":
            let valueIndex = arguments.index(after: index)
            guard valueIndex < arguments.endIndex else { throw FB01DumpError.missingValue(argument) }
            options.bank = Int(arguments[valueIndex]) ?? options.bank
            index = arguments.index(after: valueIndex)
        default:
            throw FB01DumpError.unknownArgument(argument)
        }
    }

    return options
}

func classify(_ bytes: [UInt8]) -> String {
    do {
        let artifact = try FB01Artifact(sysexBytes: bytes)
        return artifact.kind.rawValue
    } catch {
        return "unclassified (\(error))"
    }
}

func writeMessages(_ messages: [[UInt8]], to outputURL: URL?) throws {
    guard let outputURL else { return }
    let data = Data(messages.flatMap { $0 })
    try data.write(to: outputURL)
    print("Wrote \(messages.count) SysEx message(s) to \(outputURL.path)")
}

func capture(options: CaptureOptions) throws {
    let sources = availableSources()
    let source = try selectedSource(matching: options.sourceQuery, in: sources)
    let state = SysExCaptureState()

    var client = MIDIClientRef()
    try check(MIDIClientCreateWithBlock("FB01Dump" as CFString, &client) { notification in
        let messageID = notification.pointee.messageID.rawValue
        fputs("CoreMIDI notification: \(messageID)\n", stderr)
    }, "MIDIClientCreateWithBlock")
    defer { MIDIClientDispose(client) }

    var inputPort = MIDIPortRef()
    try check(MIDIInputPortCreateWithBlock(client, "FB01DumpInput" as CFString, &inputPort) { packetList, _ in
        state.append(packetList: packetList)
    }, "MIDIInputPortCreateWithBlock")
    defer { MIDIPortDispose(inputPort) }

    try check(MIDIPortConnectSource(inputPort, source.endpoint, nil), "MIDIPortConnectSource")

    print("Listening to [\(source.index)] \(source.displayName)")
    print("Use the FB-01 front panel to send a bulk dump. Press Ctrl-C to stop.")

    let start = Date()
    var lastCount = 0

    while true {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))

        let messages = state.snapshot()
        if messages.count > lastCount {
            for (offset, message) in messages[lastCount...].enumerated() {
                let number = lastCount + offset + 1
                print("Received #\(number): \(message.count) bytes, \(classify(message))")
            }
            lastCount = messages.count
            try writeMessages(messages, to: options.outputURL)
        }

        if let maxMessages = options.maxMessages, messages.count >= maxMessages {
            return
        }

        if let timeout = options.timeoutSeconds, Date().timeIntervalSince(start) >= timeout {
            if messages.isEmpty {
                print("Timed out with no complete SysEx messages.")
            }
            return
        }
    }
}

func send(bytes: [UInt8], to destination: MIDIDestinationInfo, outputPort: MIDIPortRef) throws {
    try bytes.forEach { _ = try FB01.validateByte($0) }

    let packetListByteCount = MemoryLayout<MIDIPacketList>.size + bytes.count + 256
    let rawPacketListPointer = UnsafeMutableRawPointer.allocate(
        byteCount: packetListByteCount,
        alignment: MemoryLayout<MIDIPacketList>.alignment
    )
    defer { rawPacketListPointer.deallocate() }

    let packetListPointer = rawPacketListPointer.bindMemory(to: MIDIPacketList.self, capacity: 1)
    var packet = MIDIPacketListInit(packetListPointer)
    bytes.withUnsafeBufferPointer { buffer in
        packet = MIDIPacketListAdd(
            packetListPointer,
            packetListByteCount,
            packet,
            0,
            bytes.count,
            buffer.baseAddress!
        )
    }

    try check(MIDISend(outputPort, destination.endpoint, packetListPointer), "MIDISend")
}

func requestDump(kind: DumpRequestKind, options: RequestOptions) throws {
    let sources = availableSources()
    let destinations = availableDestinations()
    let source = try selectedSource(matching: options.capture.sourceQuery, in: sources)
    let destination = try selectedDestination(matching: options.destinationQuery, in: destinations)
    let requestBytes = try kind.bytes(systemChannel: options.systemChannel)
    let state = SysExCaptureState()

    var client = MIDIClientRef()
    try check(MIDIClientCreateWithBlock("FB01DumpRequest" as CFString, &client) { notification in
        let messageID = notification.pointee.messageID.rawValue
        fputs("CoreMIDI notification: \(messageID)\n", stderr)
    }, "MIDIClientCreateWithBlock")
    defer { MIDIClientDispose(client) }

    var inputPort = MIDIPortRef()
    try check(MIDIInputPortCreateWithBlock(client, "FB01DumpRequestInput" as CFString, &inputPort) { packetList, _ in
        state.append(packetList: packetList)
    }, "MIDIInputPortCreateWithBlock")
    defer { MIDIPortDispose(inputPort) }

    var outputPort = MIDIPortRef()
    try check(MIDIOutputPortCreate(client, "FB01DumpRequestOutput" as CFString, &outputPort), "MIDIOutputPortCreate")
    defer { MIDIPortDispose(outputPort) }

    try check(MIDIPortConnectSource(inputPort, source.endpoint, nil), "MIDIPortConnectSource")

    print("Listening to [\(source.index)] \(source.displayName)")
    print("Sending \(kind.displayName) request to [\(destination.index)] \(destination.displayName)")
    try send(bytes: requestBytes, to: destination, outputPort: outputPort)

    let start = Date()
    let timeout = options.capture.timeoutSeconds ?? 15
    var lastCount = 0

    while true {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))

        let messages = state.snapshot()
        if messages.count > lastCount {
            for (offset, message) in messages[lastCount...].enumerated() {
                let number = lastCount + offset + 1
                print("Received #\(number): \(message.count) bytes, \(classify(message))")
            }
            lastCount = messages.count
            try writeMessages(messages, to: options.capture.outputURL)
        }

        if let maxMessages = options.capture.maxMessages, messages.count >= maxMessages {
            return
        }

        if Date().timeIntervalSince(start) >= timeout {
            if messages.isEmpty {
                print("Timed out with no complete SysEx messages.")
            }
            return
        }
    }
}

func printUsage() {
    print("""
    fb01-dump list
    fb01-dump listen [--source <index-or-name>] [--output <file.syx>] [--count <n>] [--timeout <seconds>]
    fb01-dump request voice-bank --bank <0-6> [--system-channel <0-15>] [--source <index-or-name>] [--destination <index-or-name>] [--output <file.syx>] [--timeout <seconds>]
    fb01-dump request voice-ram1 [--system-channel <0-15>] [--source <index-or-name>] [--destination <index-or-name>] [--output <file.syx>] [--timeout <seconds>]
    fb01-dump request current-configuration [--system-channel <0-15>] [--source <index-or-name>] [--destination <index-or-name>] [--output <file.syx>] [--timeout <seconds>]
    fb01-dump request unit-id [--system-channel <0-15>] [--source <index-or-name>] [--destination <index-or-name>] [--output <file.syx>] [--timeout <seconds>]

    FB-01 SysEx helper. `listen` is receive-only. `request` sends only documented dump requests and does not store or write data to the device.
    """)
}

do {
    let arguments = CommandLine.arguments.dropFirst()
    guard let command = arguments.first else {
        printUsage()
        exit(EXIT_SUCCESS)
    }

    switch command {
    case "list":
        printSources()
    case "listen", "capture":
        try capture(options: try parseCaptureOptions(arguments.dropFirst()))
    case "request":
        let requestArguments = arguments.dropFirst()
        guard let requestCommand = requestArguments.first else {
            throw FB01DumpError.unknownArgument("")
        }

        let options = try parseRequestOptions(requestArguments.dropFirst())
        switch requestCommand {
        case "voice-bank":
            try requestDump(kind: .voiceBank(options.bank), options: options)
        case "voice-ram1":
            try requestDump(kind: .voiceRAM1, options: options)
        case "current-configuration":
            try requestDump(kind: .currentConfiguration, options: options)
        case "unit-id":
            try requestDump(kind: .unitID, options: options)
        default:
            throw FB01DumpError.unknownArgument(requestArguments.first ?? "")
        }
    case "--help", "-h", "help":
        printUsage()
    default:
        throw FB01DumpError.unknownArgument(command)
    }
} catch {
    fputs("fb01-dump: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}

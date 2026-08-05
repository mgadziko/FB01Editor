import CoreMIDI
import FB01Editor
import Foundation

enum DX100DumpError: Error, CustomStringConvertible {
    case commandFailed(String, OSStatus)
    case missingValue(String)
    case noSources
    case noDestinations
    case sourceNotFound(String)
    case destinationNotFound(String)
    case unknownArgument(String)
    case timeout

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
            "No MIDI source matches \(query). Run `dx100-dump list` to inspect available sources."
        case .destinationNotFound(let query):
            "No MIDI destination matches \(query). Run `dx100-dump list` to inspect available destinations."
        case .unknownArgument(let argument):
            "Unknown argument: \(argument)"
        case .timeout:
            "Timed out with no DX100 single-voice bulk dump."
        }
    }
}

struct MIDIEndpointInfo {
    var index: Int
    var endpoint: MIDIEndpointRef
    var displayName: String
    var uniqueID: Int32?
}

struct RequestOptions {
    var sourceQuery: String?
    var destinationQuery: String?
    var outputURL: URL?
    var channel = 0
    var timeoutSeconds: TimeInterval = 4
}

enum DX100DumpRequestKind {
    case currentVoice
    case voiceBank

    var displayName: String {
        switch self {
        case .currentVoice:
            "current voice"
        case .voiceBank:
            "32-voice bulk"
        }
    }

    func bytes(channel: Int) throws -> [UInt8] {
        switch self {
        case .currentVoice:
            try DX100.requestSingleVoiceBulk(channel: channel)
        case .voiceBank:
            try DX100.requestThirtyTwoVoiceBulk(channel: channel)
        }
    }
}

final class SysExCaptureState: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: [UInt8] = []
    private var messages: [[UInt8]] = []

    func append(packetList: UnsafePointer<MIDIPacketList>) {
        var packet = packetList.pointee.packet

        for _ in 0..<packetList.pointee.numPackets {
            withUnsafeBytes(of: packet.data) { rawData in
                append(bytes: Array(rawData.prefix(Int(packet.length))))
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
            if byte == DX100.start {
                buffer = [byte]
                continue
            }

            guard !buffer.isEmpty else {
                continue
            }

            buffer.append(byte)
            if byte == DX100.end {
                messages.append(buffer)
                buffer.removeAll(keepingCapacity: true)
            }
        }
    }
}

func check(_ status: OSStatus, _ operation: String) throws {
    guard status == noErr else {
        throw DX100DumpError.commandFailed(operation, status)
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

func availableSources() -> [MIDIEndpointInfo] {
    (0..<MIDIGetNumberOfSources()).map { index in
        let endpoint = MIDIGetSource(index)
        return MIDIEndpointInfo(
            index: index,
            endpoint: endpoint,
            displayName: midiStringProperty(endpoint, kMIDIPropertyDisplayName)
                ?? midiStringProperty(endpoint, kMIDIPropertyName)
                ?? "Source \(index)",
            uniqueID: midiIntegerProperty(endpoint, kMIDIPropertyUniqueID)
        )
    }
}

func availableDestinations() -> [MIDIEndpointInfo] {
    (0..<MIDIGetNumberOfDestinations()).map { index in
        let endpoint = MIDIGetDestination(index)
        return MIDIEndpointInfo(
            index: index,
            endpoint: endpoint,
            displayName: midiStringProperty(endpoint, kMIDIPropertyDisplayName)
                ?? midiStringProperty(endpoint, kMIDIPropertyName)
                ?? "Destination \(index)",
            uniqueID: midiIntegerProperty(endpoint, kMIDIPropertyUniqueID)
        )
    }
}

func selectedEndpoint(matching query: String?, in endpoints: [MIDIEndpointInfo], missing: (String) -> DX100DumpError) throws -> MIDIEndpointInfo {
    guard let query, !query.isEmpty else {
        return endpoints[0]
    }

    if let index = Int(query), let endpoint = endpoints.first(where: { $0.index == index }) {
        return endpoint
    }

    if let endpoint = endpoints.first(where: { $0.displayName.localizedCaseInsensitiveContains(query) }) {
        return endpoint
    }

    throw missing(query)
}

func selectedSource(matching query: String?) throws -> MIDIEndpointInfo {
    let sources = availableSources()
    guard !sources.isEmpty else { throw DX100DumpError.noSources }
    return try selectedEndpoint(matching: query, in: sources, missing: DX100DumpError.sourceNotFound)
}

func selectedDestination(matching query: String?) throws -> MIDIEndpointInfo {
    let destinations = availableDestinations()
    guard !destinations.isEmpty else { throw DX100DumpError.noDestinations }
    return try selectedEndpoint(matching: query, in: destinations, missing: DX100DumpError.destinationNotFound)
}

func printEndpoints() {
    print("Sources")
    let sources = availableSources()
    if sources.isEmpty {
        print("  none")
    } else {
        for source in sources {
            let unique = source.uniqueID.map { " id=\($0)" } ?? ""
            print("  [\(source.index)] \(source.displayName)\(unique)")
        }
    }

    print("Destinations")
    let destinations = availableDestinations()
    if destinations.isEmpty {
        print("  none")
    } else {
        for destination in destinations {
            let unique = destination.uniqueID.map { " id=\($0)" } ?? ""
            print("  [\(destination.index)] \(destination.displayName)\(unique)")
        }
    }
}

func parseRequestOptions(_ arguments: ArraySlice<String>) throws -> RequestOptions {
    var options = RequestOptions()
    var index = arguments.startIndex

    while index < arguments.endIndex {
        let argument = arguments[index]
        switch argument {
        case "--source", "-s":
            let valueIndex = arguments.index(after: index)
            guard valueIndex < arguments.endIndex else { throw DX100DumpError.missingValue(argument) }
            options.sourceQuery = arguments[valueIndex]
            index = arguments.index(after: valueIndex)
        case "--destination", "-d":
            let valueIndex = arguments.index(after: index)
            guard valueIndex < arguments.endIndex else { throw DX100DumpError.missingValue(argument) }
            options.destinationQuery = arguments[valueIndex]
            index = arguments.index(after: valueIndex)
        case "--output", "-o":
            let valueIndex = arguments.index(after: index)
            guard valueIndex < arguments.endIndex else { throw DX100DumpError.missingValue(argument) }
            options.outputURL = URL(fileURLWithPath: arguments[valueIndex])
            index = arguments.index(after: valueIndex)
        case "--channel":
            let valueIndex = arguments.index(after: index)
            guard valueIndex < arguments.endIndex else { throw DX100DumpError.missingValue(argument) }
            options.channel = Int(arguments[valueIndex]) ?? options.channel
            index = arguments.index(after: valueIndex)
        case "--timeout":
            let valueIndex = arguments.index(after: index)
            guard valueIndex < arguments.endIndex else { throw DX100DumpError.missingValue(argument) }
            options.timeoutSeconds = TimeInterval(arguments[valueIndex]) ?? options.timeoutSeconds
            index = arguments.index(after: valueIndex)
        default:
            throw DX100DumpError.unknownArgument(argument)
        }
    }

    return options
}

func send(bytes: [UInt8], to destination: MIDIEndpointInfo, outputPort: MIDIPortRef) throws {
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

func requestDump(kind: DX100DumpRequestKind, options: RequestOptions) throws {
    let source = try selectedSource(matching: options.sourceQuery)
    let destination = try selectedDestination(matching: options.destinationQuery)
    let requestBytes = try kind.bytes(channel: options.channel)
    let state = SysExCaptureState()

    var client = MIDIClientRef()
    try check(MIDIClientCreateWithBlock("DX100Dump" as CFString, &client) { notification in
        let messageID = notification.pointee.messageID.rawValue
        fputs("CoreMIDI notification: \(messageID)\n", stderr)
    }, "MIDIClientCreateWithBlock")
    defer { MIDIClientDispose(client) }

    var inputPort = MIDIPortRef()
    try check(MIDIInputPortCreateWithBlock(client, "DX100DumpInput" as CFString, &inputPort) { packetList, _ in
        state.append(packetList: packetList)
    }, "MIDIInputPortCreateWithBlock")
    defer { MIDIPortDispose(inputPort) }

    var outputPort = MIDIPortRef()
    try check(MIDIOutputPortCreate(client, "DX100DumpOutput" as CFString, &outputPort), "MIDIOutputPortCreate")
    defer { MIDIPortDispose(outputPort) }

    try check(MIDIPortConnectSource(inputPort, source.endpoint, nil), "MIDIPortConnectSource")

    print("Listening to [\(source.index)] \(source.displayName)")
    print("Requesting DX100 \(kind.displayName) from [\(destination.index)] \(destination.displayName)")
    try send(bytes: requestBytes, to: destination, outputPort: outputPort)

    let start = Date()
    var inspectedCount = 0
    while Date().timeIntervalSince(start) < options.timeoutSeconds {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))

        let messages = state.snapshot()
        guard messages.count > inspectedCount else {
            continue
        }

        for message in messages[inspectedCount...] {
            if kind == .currentVoice, let fetched = try? DX100VoiceService.shared.currentVoice(fromSingleVoiceBulkSysEx: message) {
                print("Received DX100 current voice: \(fetched.voice.name)")
                print("Channel: \(fetched.channel)")
                print("Bytes: \(message.count)")
                print("Checksum: valid")
                if let outputURL = options.outputURL {
                    try Data(message).write(to: outputURL)
                    print("Wrote \(outputURL.path)")
                }
                return
            }

            if kind == .voiceBank, DX100.isThirtyTwoVoiceBulkSysEx(message) {
                let voiceBank = try DX100VoiceBankData(thirtyTwoVoiceBulkSysEx: message)
                print("Received DX100 32-voice bulk dump")
                print("Channel: \(voiceBank.channel)")
                print("Bytes: \(message.count)")
                print("Data bytes: \(DX100.thirtyTwoVoiceDataByteCount)")
                print("Checksum: valid")
                print("Voice names:")
                for (index, name) in voiceBank.voiceNames.enumerated() {
                    print("  \(String(format: "%02d", index + 1)) \(name.isEmpty ? "Untitled" : name)")
                }
                if let outputURL = options.outputURL {
                    try Data(message).write(to: outputURL)
                    print("Wrote \(outputURL.path)")
                }
                return
            }

            print("Received \(message.count)-byte SysEx message that is not a DX100 \(kind.displayName) dump.")
        }
        inspectedCount = messages.count
    }

    throw DX100DumpError.timeout
}

func printUsage() {
    print("""
    dx100-dump list
    dx100-dump current-voice [--channel <0-15>] [--source <index-or-name>] [--destination <index-or-name>] [--output <file.dxv>] [--timeout <seconds>]
    dx100-dump voice-bank [--channel <0-15>] [--source <index-or-name>] [--destination <index-or-name>] [--output <file.dxvb>] [--timeout <seconds>]

    DX100 SysEx helper. Requests send only documented bulk dump requests and do not store or write data to the device.
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
        printEndpoints()
    case "current-voice":
        try requestDump(kind: .currentVoice, options: try parseRequestOptions(arguments.dropFirst()))
    case "voice-bank":
        var options = try parseRequestOptions(arguments.dropFirst())
        if options.timeoutSeconds == 4 {
            options.timeoutSeconds = 12
        }
        try requestDump(kind: .voiceBank, options: options)
    case "--help", "-h", "help":
        printUsage()
    default:
        throw DX100DumpError.unknownArgument(command)
    }
} catch {
    fputs("dx100-dump: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}

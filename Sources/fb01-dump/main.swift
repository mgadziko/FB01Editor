import CoreMIDI
import FB01Editor
import Foundation

enum FB01DumpError: Error, CustomStringConvertible {
    case commandFailed(String, OSStatus)
    case missingValue(String)
    case noSources
    case sourceNotFound(String)
    case unknownArgument(String)

    var description: String {
        switch self {
        case let .commandFailed(operation, status):
            "\(operation) failed with OSStatus \(status)"
        case .missingValue(let option):
            "Missing value for \(option)"
        case .noSources:
            "No MIDI sources are visible to CoreMIDI."
        case .sourceNotFound(let query):
            "No MIDI source matches \(query). Run `fb01-dump list` to inspect available sources."
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

struct CaptureOptions {
    var sourceQuery: String?
    var outputURL: URL?
    var timeoutSeconds: TimeInterval?
    var maxMessages: Int?
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

func printSources() {
    let sources = availableSources()
    if sources.isEmpty {
        print("No MIDI sources found.")
        return
    }

    for source in sources {
        let unique = source.uniqueID.map { " id=\($0)" } ?? ""
        print("[\(source.index)] \(source.displayName)\(unique)")
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

func printUsage() {
    print("""
    fb01-dump list
    fb01-dump listen [--source <index-or-name>] [--output <file.syx>] [--count <n>] [--timeout <seconds>]

    Receive-only FB-01 SysEx helper. It does not send requests or write to the device.
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
    case "--help", "-h", "help":
        printUsage()
    default:
        throw FB01DumpError.unknownArgument(command)
    }
} catch {
    fputs("fb01-dump: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}

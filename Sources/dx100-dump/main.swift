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
    case timeout(String)
    case invalidBank(String)
    case invalidVoiceNumber(String)
    case invalidMethod(String)
    case invalidParameter(String)

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
        case .timeout(let details):
            "Timed out waiting for \(details)."
        case .invalidBank(let value):
            "Invalid bank value: \(value). Use A-D or 1-4."
        case .invalidVoiceNumber(let value):
            "Invalid voice number: \(value). Use 1-24."
        case .invalidMethod(let value):
            "Invalid method: \(value). Use program, param126, or param127."
        case .invalidParameter(let value):
            "Invalid parameter specification: \(value). Use <parameter>:<data> with values 0...127."
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
    var noRequest = false
}

enum DX100BankProbeMethod: String {
    case program
    case param126
    case param127
    case panel
}

struct BankVoiceProbeOptions {
    var request = RequestOptions()
    var bank = 1
    var voiceNumber = 1
    var method = DX100BankProbeMethod.program
    var selectionDelaySeconds: TimeInterval = 0.6
    var recallEdit = false
    var noRequest = false
    var playFirst = false
}

struct SwitchProbeOptions {
    var request = RequestOptions()
    var switchNumber = 0
    var switchValue = 127
    var selectionDelaySeconds: TimeInterval = 0.6
    var noRequest = false
    var releaseAfterPress = true
    var releaseDelaySeconds: TimeInterval = 0.1
}

struct ParameterSequenceProbeOptions {
    var request = RequestOptions()
    var parameterPairs: [(Int, Int)] = []
    var selectionDelaySeconds: TimeInterval = 0.6
    var requestKind: DX100DumpRequestKind = .currentVoice
    var noRequest = false
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
        case "--no-request", "--manual":
            options.noRequest = true
            index = arguments.index(after: index)
        default:
            throw DX100DumpError.unknownArgument(argument)
        }
    }

    return options
}

func parseBank(_ value: String) throws -> Int {
    let upper = value.uppercased()
    switch upper {
    case "A", "1": return 1
    case "B", "2": return 2
    case "C", "3": return 3
    case "D", "4": return 4
    default: throw DX100DumpError.invalidBank(value)
    }
}

func parseBankVoiceProbeOptions(_ arguments: ArraySlice<String>) throws -> BankVoiceProbeOptions {
    var options = BankVoiceProbeOptions()
    var index = arguments.startIndex

    while index < arguments.endIndex {
        let argument = arguments[index]
        switch argument {
        case "--source", "-s", "--destination", "-d", "--output", "-o", "--channel", "--timeout":
            let next = arguments.index(after: index)
            guard next < arguments.endIndex else { throw DX100DumpError.missingValue(argument) }
            let slice = arguments[index...next]
            let request = try parseRequestOptions(slice)
            if argument == "--source" || argument == "-s" { options.request.sourceQuery = request.sourceQuery }
            if argument == "--destination" || argument == "-d" { options.request.destinationQuery = request.destinationQuery }
            if argument == "--output" || argument == "-o" { options.request.outputURL = request.outputURL }
            if argument == "--channel" { options.request.channel = request.channel }
            if argument == "--timeout" { options.request.timeoutSeconds = request.timeoutSeconds }
            index = arguments.index(after: next)
        case "--bank":
            let next = arguments.index(after: index)
            guard next < arguments.endIndex else { throw DX100DumpError.missingValue(argument) }
            options.bank = try parseBank(arguments[next])
            index = arguments.index(after: next)
        case "--voice":
            let next = arguments.index(after: index)
            guard next < arguments.endIndex else { throw DX100DumpError.missingValue(argument) }
            guard let voice = Int(arguments[next]), (1...24).contains(voice) else {
                throw DX100DumpError.invalidVoiceNumber(arguments[next])
            }
            options.voiceNumber = voice
            index = arguments.index(after: next)
        case "--method":
            let next = arguments.index(after: index)
            guard next < arguments.endIndex else { throw DX100DumpError.missingValue(argument) }
            guard let method = DX100BankProbeMethod(rawValue: arguments[next]) else {
                throw DX100DumpError.invalidMethod(arguments[next])
            }
            options.method = method
            index = arguments.index(after: next)
        case "--selection-delay":
            let next = arguments.index(after: index)
            guard next < arguments.endIndex else { throw DX100DumpError.missingValue(argument) }
            options.selectionDelaySeconds = TimeInterval(arguments[next]) ?? options.selectionDelaySeconds
            index = arguments.index(after: next)
        case "--recall-edit":
            options.recallEdit = true
            index = arguments.index(after: index)
        case "--no-request":
            options.noRequest = true
            index = arguments.index(after: index)
        case "--play-first":
            options.playFirst = true
            index = arguments.index(after: index)
        default:
            throw DX100DumpError.unknownArgument(argument)
        }
    }

    return options
}

func parseSwitchProbeOptions(_ arguments: ArraySlice<String>) throws -> SwitchProbeOptions {
    var options = SwitchProbeOptions()
    var index = arguments.startIndex

    while index < arguments.endIndex {
        let argument = arguments[index]
        switch argument {
        case "--source", "-s", "--destination", "-d", "--output", "-o", "--channel", "--timeout":
            let next = arguments.index(after: index)
            guard next < arguments.endIndex else { throw DX100DumpError.missingValue(argument) }
            let slice = arguments[index...next]
            let request = try parseRequestOptions(slice)
            if argument == "--source" || argument == "-s" { options.request.sourceQuery = request.sourceQuery }
            if argument == "--destination" || argument == "-d" { options.request.destinationQuery = request.destinationQuery }
            if argument == "--output" || argument == "-o" { options.request.outputURL = request.outputURL }
            if argument == "--channel" { options.request.channel = request.channel }
            if argument == "--timeout" { options.request.timeoutSeconds = request.timeoutSeconds }
            index = arguments.index(after: next)
        case "--switch":
            let next = arguments.index(after: index)
            guard next < arguments.endIndex else { throw DX100DumpError.missingValue(argument) }
            options.switchNumber = Int(arguments[next]) ?? options.switchNumber
            index = arguments.index(after: next)
        case "--value":
            let next = arguments.index(after: index)
            guard next < arguments.endIndex else { throw DX100DumpError.missingValue(argument) }
            options.switchValue = Int(arguments[next]) ?? options.switchValue
            index = arguments.index(after: next)
        case "--selection-delay":
            let next = arguments.index(after: index)
            guard next < arguments.endIndex else { throw DX100DumpError.missingValue(argument) }
            options.selectionDelaySeconds = TimeInterval(arguments[next]) ?? options.selectionDelaySeconds
            index = arguments.index(after: next)
        case "--release-delay":
            let next = arguments.index(after: index)
            guard next < arguments.endIndex else { throw DX100DumpError.missingValue(argument) }
            options.releaseDelaySeconds = TimeInterval(arguments[next]) ?? options.releaseDelaySeconds
            index = arguments.index(after: next)
        case "--no-release":
            options.releaseAfterPress = false
            index = arguments.index(after: index)
        case "--no-request":
            options.noRequest = true
            index = arguments.index(after: index)
        default:
            throw DX100DumpError.unknownArgument(argument)
        }
    }

    return options
}

func parseRequestKind(_ value: String) throws -> DX100DumpRequestKind {
    switch value.lowercased() {
    case "current", "current-voice", "voice":
        return .currentVoice
    case "bank", "voice-bank", "32-bank", "32voice":
        return .voiceBank
    default:
        throw DX100DumpError.unknownArgument(value)
    }
}

func parseParameterPair(_ value: String) throws -> (Int, Int) {
    let pieces = value.split(separator: ":", omittingEmptySubsequences: false)
    guard pieces.count == 2,
          let parameter = Int(pieces[0]),
          let data = Int(pieces[1]),
          (0...127).contains(parameter),
          (0...127).contains(data) else {
        throw DX100DumpError.invalidParameter(value)
    }
    return (parameter, data)
}

func parseParameterSequenceProbeOptions(_ arguments: ArraySlice<String>) throws -> ParameterSequenceProbeOptions {
    var options = ParameterSequenceProbeOptions()
    var index = arguments.startIndex

    while index < arguments.endIndex {
        let argument = arguments[index]
        switch argument {
        case "--source", "-s", "--destination", "-d", "--output", "-o", "--channel", "--timeout":
            let next = arguments.index(after: index)
            guard next < arguments.endIndex else { throw DX100DumpError.missingValue(argument) }
            let slice = arguments[index...next]
            let request = try parseRequestOptions(slice)
            if argument == "--source" || argument == "-s" { options.request.sourceQuery = request.sourceQuery }
            if argument == "--destination" || argument == "-d" { options.request.destinationQuery = request.destinationQuery }
            if argument == "--output" || argument == "-o" { options.request.outputURL = request.outputURL }
            if argument == "--channel" { options.request.channel = request.channel }
            if argument == "--timeout" { options.request.timeoutSeconds = request.timeoutSeconds }
            index = arguments.index(after: next)
        case "--param":
            let next = arguments.index(after: index)
            guard next < arguments.endIndex else { throw DX100DumpError.missingValue(argument) }
            options.parameterPairs.append(try parseParameterPair(arguments[next]))
            index = arguments.index(after: next)
        case "--selection-delay":
            let next = arguments.index(after: index)
            guard next < arguments.endIndex else { throw DX100DumpError.missingValue(argument) }
            options.selectionDelaySeconds = TimeInterval(arguments[next]) ?? options.selectionDelaySeconds
            index = arguments.index(after: next)
        case "--request":
            let next = arguments.index(after: index)
            guard next < arguments.endIndex else { throw DX100DumpError.missingValue(argument) }
            options.requestKind = try parseRequestKind(arguments[next])
            index = arguments.index(after: next)
        case "--no-request":
            options.noRequest = true
            index = arguments.index(after: index)
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

func sendSwitchPress(
    channel: Int,
    switchNumber: Int,
    value: Int = 127,
    releaseValue: Int = 0,
    releaseDelaySeconds: TimeInterval = 0.1,
    to destination: MIDIEndpointInfo,
    outputPort: MIDIPortRef
) throws {
    let pressBytes = try dx100SwitchModeMessage(channel: channel, switchNumber: switchNumber, value: value)
    let releaseBytes = try dx100SwitchModeMessage(channel: channel, switchNumber: switchNumber, value: releaseValue)
    try send(bytes: pressBytes, to: destination, outputPort: outputPort)
    RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: releaseDelaySeconds))
    try send(bytes: releaseBytes, to: destination, outputPort: outputPort)
}

func requestDump(kind: DX100DumpRequestKind, options: RequestOptions) throws {
    let source = try selectedSource(matching: options.sourceQuery)
    let destination = try selectedDestination(matching: options.destinationQuery)
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
    if options.noRequest {
        print("Waiting for manual DX100 \(kind.displayName) dump from [\(destination.index)] \(destination.displayName)")
    } else {
        let requestBytes = try kind.bytes(channel: options.channel)
        print("Requesting DX100 \(kind.displayName) from [\(destination.index)] \(destination.displayName)")
        try send(bytes: requestBytes, to: destination, outputPort: outputPort)
    }

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

    let timeoutDetails: String
    if options.noRequest {
        timeoutDetails = "a manual DX100 \(kind.displayName) dump on \(source.displayName)"
    } else {
        timeoutDetails = "a DX100 \(kind.displayName) dump response on \(source.displayName)"
    }
    throw DX100DumpError.timeout(timeoutDetails)
}

func requestBankVoice(options: BankVoiceProbeOptions) throws {
    let source = try selectedSource(matching: options.request.sourceQuery)
    let destination = try selectedDestination(matching: options.request.destinationQuery)
    let voiceIndex = options.voiceNumber - 1
    let bankVoiceNumber = ((options.bank - 1) * 24) + voiceIndex

    let selectionBytes: [UInt8]
    switch options.method {
    case .program:
        selectionBytes = [0xC0 | UInt8(options.request.channel), UInt8(24 + bankVoiceNumber)]
    case .param126:
        selectionBytes = try DX100.parameterChange(channel: options.request.channel, parameter: 126, data: bankVoiceNumber)
    case .param127:
        selectionBytes = try DX100.parameterChange(channel: options.request.channel, parameter: 127, data: bankVoiceNumber)
    case .panel:
        throw DX100DumpError.invalidMethod("panel requires panel-bank-voice")
    }

    let requestBytes = try DX100.requestSingleVoiceBulk(channel: options.request.channel)
    let recallEditBytes = try DX100.parameterChange(channel: options.request.channel, parameter: 111, data: 1)
    let state = SysExCaptureState()

    var client = MIDIClientRef()
    try check(MIDIClientCreateWithBlock("DX100BankVoiceProbe" as CFString, &client) { _ in }, "MIDIClientCreateWithBlock")
    defer { MIDIClientDispose(client) }

    var inputPort = MIDIPortRef()
    try check(MIDIInputPortCreateWithBlock(client, "DX100BankVoiceProbeInput" as CFString, &inputPort) { packetList, _ in
        state.append(packetList: packetList)
    }, "MIDIInputPortCreateWithBlock")
    defer { MIDIPortDispose(inputPort) }

    var outputPort = MIDIPortRef()
    try check(MIDIOutputPortCreate(client, "DX100BankVoiceProbeOutput" as CFString, &outputPort), "MIDIOutputPortCreate")
    defer { MIDIPortDispose(outputPort) }

    try check(MIDIPortConnectSource(inputPort, source.endpoint, nil), "MIDIPortConnectSource")

    print("Listening to [\(source.index)] \(source.displayName)")
    print("Selecting DX100 bank \(options.bank) voice \(options.voiceNumber) using \(options.method.rawValue)")
    try send(bytes: selectionBytes, to: destination, outputPort: outputPort)
    RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: options.selectionDelaySeconds))
    if options.recallEdit {
        print("Sending DX100 Recall Edit")
        try send(bytes: recallEditBytes, to: destination, outputPort: outputPort)
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: options.selectionDelaySeconds))
    }
    if options.noRequest {
        print("Selection sent without requesting a dump.")
        return
    }
    try send(bytes: requestBytes, to: destination, outputPort: outputPort)

    let start = Date()
    var inspectedCount = 0
    while Date().timeIntervalSince(start) < options.request.timeoutSeconds {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))

        let messages = state.snapshot()
        guard messages.count > inspectedCount else { continue }

        for message in messages[inspectedCount...] {
            if let fetched = try? DX100VoiceService.shared.currentVoice(fromSingleVoiceBulkSysEx: message) {
                print("Received DX100 current voice after bank selection: \(fetched.voice.name)")
                print("Channel: \(fetched.channel)")
                if let outputURL = options.request.outputURL {
                    try Data(message).write(to: outputURL)
                    print("Wrote \(outputURL.path)")
                }
                return
            }
            print("Received \(message.count)-byte SysEx message that is not a DX100 current-voice dump.")
        }
        inspectedCount = messages.count
    }

    throw DX100DumpError.timeout("a DX100 current-voice dump after bank selection")
}

func dx100SwitchModeMessage(channel: Int, switchNumber: Int, value: Int) throws -> [UInt8] {
    guard (0...15).contains(channel) else {
        throw DX100SysExError.invalidChannel(channel)
    }
    guard (0...35).contains(switchNumber) else {
        throw DX100DumpError.unknownArgument("switch \(switchNumber)")
    }
    guard (0...127).contains(value) else {
        throw DX100DumpError.unknownArgument("value \(value)")
    }
    return [0xF0, 0x43, 0x10 | UInt8(channel), 0x08, UInt8(switchNumber), UInt8(value), 0xF7]
}

func requestPanelBankVoice(options: BankVoiceProbeOptions) throws {
    let source = try selectedSource(matching: options.request.sourceQuery)
    let destination = try selectedDestination(matching: options.request.destinationQuery)
    let voiceSwitch = (options.voiceNumber - 1)
    let bankSwitchMap = [1: 28, 2: 29, 3: 30, 4: 31]
    guard let bankSwitch = bankSwitchMap[options.bank] else {
        throw DX100DumpError.invalidBank("\(options.bank)")
    }
    let playSwitch = 27

    let requestBytes = try DX100.requestSingleVoiceBulk(channel: options.request.channel)
    let state = SysExCaptureState()

    var client = MIDIClientRef()
    try check(MIDIClientCreateWithBlock("DX100PanelBankVoiceProbe" as CFString, &client) { _ in }, "MIDIClientCreateWithBlock")
    defer { MIDIClientDispose(client) }

    var inputPort = MIDIPortRef()
    try check(MIDIInputPortCreateWithBlock(client, "DX100PanelBankVoiceProbeInput" as CFString, &inputPort) { packetList, _ in
        state.append(packetList: packetList)
    }, "MIDIInputPortCreateWithBlock")
    defer { MIDIPortDispose(inputPort) }

    var outputPort = MIDIPortRef()
    try check(MIDIOutputPortCreate(client, "DX100PanelBankVoiceProbeOutput" as CFString, &outputPort), "MIDIOutputPortCreate")
    defer { MIDIPortDispose(outputPort) }

    try check(MIDIPortConnectSource(inputPort, source.endpoint, nil), "MIDIPortConnectSource")

    print("Listening to [\(source.index)] \(source.displayName)")
    print("Selecting DX100 bank \(options.bank) voice \(options.voiceNumber) using panel switches bank=\(bankSwitch) voice=\(voiceSwitch)\(options.playFirst ? " with PLAY first" : "")")
    if options.playFirst {
        try sendSwitchPress(
            channel: options.request.channel,
            switchNumber: playSwitch,
            to: destination,
            outputPort: outputPort
        )
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: options.selectionDelaySeconds))
    }
    try sendSwitchPress(
        channel: options.request.channel,
        switchNumber: bankSwitch,
        to: destination,
        outputPort: outputPort
    )
    RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: options.selectionDelaySeconds))
    try sendSwitchPress(
        channel: options.request.channel,
        switchNumber: voiceSwitch,
        to: destination,
        outputPort: outputPort
    )
    RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: options.selectionDelaySeconds))
    if options.noRequest {
        print("Panel selection sent without requesting a dump.")
        return
    }
    try send(bytes: requestBytes, to: destination, outputPort: outputPort)

    let start = Date()
    var inspectedCount = 0
    while Date().timeIntervalSince(start) < options.request.timeoutSeconds {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        let messages = state.snapshot()
        guard messages.count > inspectedCount else { continue }
        for message in messages[inspectedCount...] {
            if let fetched = try? DX100VoiceService.shared.currentVoice(fromSingleVoiceBulkSysEx: message) {
                print("Received DX100 current voice after panel bank selection: \(fetched.voice.name)")
                print("Channel: \(fetched.channel)")
                if let outputURL = options.request.outputURL {
                    try Data(message).write(to: options.request.outputURL!)
                    print("Wrote \(outputURL.path)")
                }
                return
            }
            print("Received \(message.count)-byte SysEx message that is not a DX100 current-voice dump.")
        }
        inspectedCount = messages.count
    }
    throw DX100DumpError.timeout("a DX100 current-voice dump after panel bank selection")
}

func requestRawSwitch(options: SwitchProbeOptions) throws {
    let source = try selectedSource(matching: options.request.sourceQuery)
    let destination = try selectedDestination(matching: options.request.destinationQuery)
    let requestBytes = try DX100.requestSingleVoiceBulk(channel: options.request.channel)
    let switchBytes = try dx100SwitchModeMessage(channel: options.request.channel, switchNumber: options.switchNumber, value: options.switchValue)
    let releaseBytes = try dx100SwitchModeMessage(channel: options.request.channel, switchNumber: options.switchNumber, value: 0)
    let state = SysExCaptureState()

    var client = MIDIClientRef()
    try check(MIDIClientCreateWithBlock("DX100RawSwitchProbe" as CFString, &client) { _ in }, "MIDIClientCreateWithBlock")
    defer { MIDIClientDispose(client) }
    var inputPort = MIDIPortRef()
    try check(MIDIInputPortCreateWithBlock(client, "DX100RawSwitchProbeInput" as CFString, &inputPort) { packetList, _ in
        state.append(packetList: packetList)
    }, "MIDIInputPortCreateWithBlock")
    defer { MIDIPortDispose(inputPort) }
    var outputPort = MIDIPortRef()
    try check(MIDIOutputPortCreate(client, "DX100RawSwitchProbeOutput" as CFString, &outputPort), "MIDIOutputPortCreate")
    defer { MIDIPortDispose(outputPort) }
    try check(MIDIPortConnectSource(inputPort, source.endpoint, nil), "MIDIPortConnectSource")

    print("Listening to [\(source.index)] \(source.displayName)")
    print("Sending DX100 switch \(options.switchNumber) value \(options.switchValue)")
    try send(bytes: switchBytes, to: destination, outputPort: outputPort)
    if options.releaseAfterPress {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: options.releaseDelaySeconds))
        print("Releasing DX100 switch \(options.switchNumber)")
        try send(bytes: releaseBytes, to: destination, outputPort: outputPort)
    }
    RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: options.selectionDelaySeconds))
    if options.noRequest {
        print("Switch message sent without requesting a dump.")
        return
    }
    try send(bytes: requestBytes, to: destination, outputPort: outputPort)

    let start = Date()
    var inspectedCount = 0
    while Date().timeIntervalSince(start) < options.request.timeoutSeconds {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        let messages = state.snapshot()
        guard messages.count > inspectedCount else { continue }
        for message in messages[inspectedCount...] {
            if let fetched = try? DX100VoiceService.shared.currentVoice(fromSingleVoiceBulkSysEx: message) {
                print("Received DX100 current voice after switch \(options.switchNumber): \(fetched.voice.name)")
                return
            }
            print("Received \(message.count)-byte SysEx message that is not a DX100 current-voice dump.")
        }
        inspectedCount = messages.count
    }
    throw DX100DumpError.timeout("a DX100 current-voice dump after raw switch \(options.switchNumber)")
}

func requestParameterSequence(options: ParameterSequenceProbeOptions) throws {
    guard !options.parameterPairs.isEmpty else {
        throw DX100DumpError.missingValue("--param")
    }

    let source = try selectedSource(matching: options.request.sourceQuery)
    let destination = try selectedDestination(matching: options.request.destinationQuery)
    let requestBytes = try options.requestKind.bytes(channel: options.request.channel)
    let parameterMessages = try options.parameterPairs.map { parameter, data in
        try DX100.parameterChange(channel: options.request.channel, parameter: parameter, data: data)
    }
    let state = SysExCaptureState()

    var client = MIDIClientRef()
    try check(MIDIClientCreateWithBlock("DX100ParameterSequenceProbe" as CFString, &client) { _ in }, "MIDIClientCreateWithBlock")
    defer { MIDIClientDispose(client) }
    var inputPort = MIDIPortRef()
    try check(MIDIInputPortCreateWithBlock(client, "DX100ParameterSequenceProbeInput" as CFString, &inputPort) { packetList, _ in
        state.append(packetList: packetList)
    }, "MIDIInputPortCreateWithBlock")
    defer { MIDIPortDispose(inputPort) }
    var outputPort = MIDIPortRef()
    try check(MIDIOutputPortCreate(client, "DX100ParameterSequenceProbeOutput" as CFString, &outputPort), "MIDIOutputPortCreate")
    defer { MIDIPortDispose(outputPort) }
    try check(MIDIPortConnectSource(inputPort, source.endpoint, nil), "MIDIPortConnectSource")

    print("Listening to [\(source.index)] \(source.displayName)")
    print("Sending DX100 parameter sequence:")
    for (parameter, data) in options.parameterPairs {
        print("  parameter \(parameter) = \(data)")
    }

    for message in parameterMessages {
        try send(bytes: message, to: destination, outputPort: outputPort)
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: options.selectionDelaySeconds))
    }
    if options.noRequest {
        print("Parameter sequence sent without requesting a dump.")
        return
    }
    print("Requesting DX100 \(options.requestKind.displayName) from [\(destination.index)] \(destination.displayName)")
    try send(bytes: requestBytes, to: destination, outputPort: outputPort)

    let start = Date()
    var inspectedCount = 0
    while Date().timeIntervalSince(start) < options.request.timeoutSeconds {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        let messages = state.snapshot()
        guard messages.count > inspectedCount else { continue }
        for message in messages[inspectedCount...] {
            switch options.requestKind {
            case .currentVoice:
                if let fetched = try? DX100VoiceService.shared.currentVoice(fromSingleVoiceBulkSysEx: message) {
                    print("Received DX100 current voice after parameter sequence: \(fetched.voice.name)")
                    print("Channel: \(fetched.channel)")
                    if let outputURL = options.request.outputURL {
                        try Data(message).write(to: outputURL)
                        print("Wrote \(outputURL.path)")
                    }
                    return
                }
            case .voiceBank:
                if DX100.isThirtyTwoVoiceBulkSysEx(message) {
                    let voiceBank = try DX100VoiceBankData(thirtyTwoVoiceBulkSysEx: message)
                    print("Received DX100 32-voice bulk dump after parameter sequence")
                    print("Channel: \(voiceBank.channel)")
                    if let outputURL = options.request.outputURL {
                        try Data(message).write(to: outputURL)
                        print("Wrote \(outputURL.path)")
                    }
                    return
                }
            }
            print("Received \(message.count)-byte SysEx message that is not the requested DX100 dump.")
        }
        inspectedCount = messages.count
    }

    switch options.requestKind {
    case .currentVoice:
        throw DX100DumpError.timeout("a DX100 current-voice dump after parameter sequence")
    case .voiceBank:
        throw DX100DumpError.timeout("a DX100 32-voice bulk dump after parameter sequence")
    }
}

func printUsage() {
    print("""
    dx100-dump list
    dx100-dump current-voice [--channel <0-15>] [--source <index-or-name>] [--destination <index-or-name>] [--output <file.dxv>] [--timeout <seconds>] [--no-request|--manual]
    dx100-dump voice-bank [--channel <0-15>] [--source <index-or-name>] [--destination <index-or-name>] [--output <file.dxvb>] [--timeout <seconds>] [--no-request|--manual]
    dx100-dump bank-voice --bank <A-D|1-4> --voice <1-24> [--method <program|param126|param127>] [--selection-delay <seconds>] [--recall-edit] [--no-request] [--channel <0-15>] [--source <index-or-name>] [--destination <index-or-name>] [--output <file.dxv>] [--timeout <seconds>]
    dx100-dump panel-bank-voice --bank <A-D|1-4> --voice <1-24> [--play-first] [--selection-delay <seconds>] [--no-request] [--channel <0-15>] [--source <index-or-name>] [--destination <index-or-name>] [--output <file.dxv>] [--timeout <seconds>]
    dx100-dump raw-switch --switch <0-31> [--value <0-127>] [--selection-delay <seconds>] [--no-request] [--channel <0-15>] [--source <index-or-name>] [--destination <index-or-name>] [--timeout <seconds>]
    dx100-dump param-seq --param <parameter:data> [--param <parameter:data> ...] [--request <current|bank>] [--selection-delay <seconds>] [--no-request] [--channel <0-15>] [--source <index-or-name>] [--destination <index-or-name>] [--output <file>] [--timeout <seconds>]

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
    case "bank-voice":
        var options = try parseBankVoiceProbeOptions(arguments.dropFirst())
        if options.request.timeoutSeconds == 4 {
            options.request.timeoutSeconds = 8
        }
        try requestBankVoice(options: options)
    case "panel-bank-voice":
        var options = try parseBankVoiceProbeOptions(arguments.dropFirst())
        if options.request.timeoutSeconds == 4 {
            options.request.timeoutSeconds = 8
        }
        try requestPanelBankVoice(options: options)
    case "raw-switch":
        var options = try parseSwitchProbeOptions(arguments.dropFirst())
        if options.request.timeoutSeconds == 4 {
            options.request.timeoutSeconds = 8
        }
        try requestRawSwitch(options: options)
    case "param-seq":
        var options = try parseParameterSequenceProbeOptions(arguments.dropFirst())
        if options.request.timeoutSeconds == 4 {
            options.request.timeoutSeconds = 8
        }
        try requestParameterSequence(options: options)
    case "--help", "-h", "help":
        printUsage()
    default:
        throw DX100DumpError.unknownArgument(command)
    }
} catch {
    fputs("dx100-dump: \(error)\n", stderr)
    exit(EXIT_FAILURE)
}

import CoreMIDI
import Foundation

public enum FB01MIDIError: Error, CustomStringConvertible, Sendable {
    case commandFailed(String, OSStatus)
    case noSources
    case noDestinations
    case sourceNotFound(Int)
    case destinationNotFound(Int)
    case timedOut(String)

    public var description: String {
        switch self {
        case let .commandFailed(operation, status):
            "\(operation) failed with OSStatus \(status)"
        case .noSources:
            "No MIDI sources are visible to CoreMIDI."
        case .noDestinations:
            "No MIDI destinations are visible to CoreMIDI."
        case .sourceNotFound(let index):
            "No MIDI source exists at index \(index)."
        case .destinationNotFound(let index):
            "No MIDI destination exists at index \(index)."
        case .timedOut(let request):
            "Timed out waiting for \(request)."
        }
    }
}

public struct FB01MIDIEndpoint: Equatable, Sendable {
    public var index: Int
    public var displayName: String
    public var uniqueID: Int32?

    public init(index: Int, displayName: String, uniqueID: Int32?) {
        self.index = index
        self.displayName = displayName
        self.uniqueID = uniqueID
    }
}

public enum FB01MIDIRequestKind: Equatable, Sendable {
    case unitID
    case currentConfiguration
    case configuration(Int)
    case voiceRAM1
    case voiceBank(Int)

    public func bytes(systemChannel: Int) throws -> [UInt8] {
        switch self {
        case .unitID:
            try FB01Command.requestUnitID(systemChannel: systemChannel).bytes
        case .currentConfiguration:
            try FB01Command.requestCurrentConfiguration(systemChannel: systemChannel).bytes
        case .configuration(let number):
            try FB01Command.requestConfiguration(systemChannel: systemChannel, number: number - 1).bytes
        case .voiceRAM1:
            try FB01Command.requestVoiceRAM1(systemChannel: systemChannel).bytes
        case .voiceBank(let bank):
            try FB01Command.requestVoiceBank(systemChannel: systemChannel, bank: bank).bytes
        }
    }

    public var displayName: String {
        switch self {
        case .unitID:
            "unit ID"
        case .currentConfiguration:
            "current configuration"
        case .configuration(let number):
            "configuration \(number)"
        case .voiceRAM1:
            "voice RAM 1"
        case .voiceBank(let bank):
            "voice bank \(bank)"
        }
    }
}

public enum FB01MIDI {
    public static func availableSources() -> [FB01MIDIEndpoint] {
        (0..<MIDIGetNumberOfSources()).map { index in
            let endpoint = MIDIGetSource(index)
            return FB01MIDIEndpoint(
                index: index,
                displayName: midiStringProperty(endpoint, kMIDIPropertyDisplayName)
                    ?? midiStringProperty(endpoint, kMIDIPropertyName)
                    ?? "Source \(index)",
                uniqueID: midiIntegerProperty(endpoint, kMIDIPropertyUniqueID)
            )
        }
    }

    public static func availableDestinations() -> [FB01MIDIEndpoint] {
        (0..<MIDIGetNumberOfDestinations()).map { index in
            let endpoint = MIDIGetDestination(index)
            return FB01MIDIEndpoint(
                index: index,
                displayName: midiStringProperty(endpoint, kMIDIPropertyDisplayName)
                    ?? midiStringProperty(endpoint, kMIDIPropertyName)
                    ?? "Destination \(index)",
                uniqueID: midiIntegerProperty(endpoint, kMIDIPropertyUniqueID)
            )
        }
    }

    public static func request(
        _ kind: FB01MIDIRequestKind,
        sourceIndex: Int = 0,
        destinationIndex: Int = 0,
        systemChannel: Int = 0,
        timeout: TimeInterval = 15
    ) throws -> [UInt8] {
        let messages = try requestMessages(
            kind,
            sourceIndex: sourceIndex,
            destinationIndex: destinationIndex,
            systemChannel: systemChannel,
            timeout: timeout,
            maxMessages: 1
        )
        guard let message = messages.first else {
            throw FB01MIDIError.timedOut(kind.displayName)
        }
        return message
    }

    public static func requestAllBanks(
        sourceIndex: Int = 0,
        destinationIndex: Int = 0,
        systemChannel: Int = 0,
        timeoutPerRequest: TimeInterval = 20
    ) throws -> [[UInt8]] {
        var messages: [[UInt8]] = []
        messages.append(try request(
            .currentConfiguration,
            sourceIndex: sourceIndex,
            destinationIndex: destinationIndex,
            systemChannel: systemChannel,
            timeout: timeoutPerRequest
        ))

        for bank in 1...7 {
            messages.append(try request(
                .voiceBank(bank),
                sourceIndex: sourceIndex,
                destinationIndex: destinationIndex,
                systemChannel: systemChannel,
                timeout: timeoutPerRequest
            ))
        }

        messages.append(try request(
            .voiceRAM1,
            sourceIndex: sourceIndex,
            destinationIndex: destinationIndex,
            systemChannel: systemChannel,
            timeout: timeoutPerRequest
        ))
        return messages
    }

    public static func requestStoredConfigurations(
        sourceIndex: Int = 0,
        destinationIndex: Int = 0,
        systemChannel: Int = 0,
        timeoutPerRequest: TimeInterval = 15
    ) throws -> [[UInt8]] {
        var messages: [[UInt8]] = []

        for number in 1...20 {
            messages.append(try request(
                .configuration(number),
                sourceIndex: sourceIndex,
                destinationIndex: destinationIndex,
                systemChannel: systemChannel,
                timeout: timeoutPerRequest
            ))
        }

        return messages
    }

    public static func requestMessages(
        _ kind: FB01MIDIRequestKind,
        sourceIndex: Int,
        destinationIndex: Int,
        systemChannel: Int,
        timeout: TimeInterval,
        maxMessages: Int
    ) throws -> [[UInt8]] {
        let source = try sourceEndpoint(at: sourceIndex)
        let destination = try destinationEndpoint(at: destinationIndex)
        let requestBytes = try kind.bytes(systemChannel: systemChannel)
        let state = FB01SysExCaptureState()

        var client = MIDIClientRef()
        try check(MIDIClientCreateWithBlock("FB01EditorMIDI" as CFString, &client) { _ in }, "MIDIClientCreateWithBlock")
        defer { MIDIClientDispose(client) }

        var inputPort = MIDIPortRef()
        try check(MIDIInputPortCreateWithBlock(client, "FB01EditorMIDIInput" as CFString, &inputPort) { packetList, _ in
            state.append(packetList: packetList)
        }, "MIDIInputPortCreateWithBlock")
        defer { MIDIPortDispose(inputPort) }

        var outputPort = MIDIPortRef()
        try check(MIDIOutputPortCreate(client, "FB01EditorMIDIOutput" as CFString, &outputPort), "MIDIOutputPortCreate")
        defer { MIDIPortDispose(outputPort) }

        try check(MIDIPortConnectSource(inputPort, source, nil), "MIDIPortConnectSource")
        try send(bytes: requestBytes, to: destination, outputPort: outputPort)

        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
            let messages = state.snapshot()
            if messages.count >= maxMessages {
                return Array(messages.prefix(maxMessages))
            }
        }

        throw FB01MIDIError.timedOut(kind.displayName)
    }

    private static func sourceEndpoint(at index: Int) throws -> MIDIEndpointRef {
        guard MIDIGetNumberOfSources() > 0 else { throw FB01MIDIError.noSources }
        guard index >= 0, index < MIDIGetNumberOfSources() else { throw FB01MIDIError.sourceNotFound(index) }
        return MIDIGetSource(index)
    }

    private static func destinationEndpoint(at index: Int) throws -> MIDIEndpointRef {
        guard MIDIGetNumberOfDestinations() > 0 else { throw FB01MIDIError.noDestinations }
        guard index >= 0, index < MIDIGetNumberOfDestinations() else { throw FB01MIDIError.destinationNotFound(index) }
        return MIDIGetDestination(index)
    }

    private static func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else {
            throw FB01MIDIError.commandFailed(operation, status)
        }
    }

    private static func midiStringProperty(_ object: MIDIObjectRef, _ property: CFString) -> String? {
        var unmanaged: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(object, property, &unmanaged) == noErr else {
            return nil
        }
        return unmanaged?.takeRetainedValue() as String?
    }

    private static func midiIntegerProperty(_ object: MIDIObjectRef, _ property: CFString) -> Int32? {
        var value: Int32 = 0
        guard MIDIObjectGetIntegerProperty(object, property, &value) == noErr else {
            return nil
        }
        return value
    }

    private static func send(bytes: [UInt8], to destination: MIDIEndpointRef, outputPort: MIDIPortRef) throws {
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

        try check(MIDISend(outputPort, destination, packetListPointer), "MIDISend")
    }
}

private final class FB01SysExCaptureState: @unchecked Sendable {
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

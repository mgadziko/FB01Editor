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
    case instrumentVoice(Int)
    case currentConfiguration
    case configuration(Int)
    case voiceRAM1
    case voiceBank(Int)

    public func bytes(systemChannel: Int) throws -> [UInt8] {
        switch self {
        case .unitID:
            try FB01Command.requestUnitID(systemChannel: systemChannel).bytes
        case .instrumentVoice(let instrument):
            try FB01Command.requestInstrumentVoice(systemChannel: systemChannel, instrument: instrument - 1).bytes
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
        case .instrumentVoice(let instrument):
            "instrument \(instrument) voice"
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
    private static let requestLock = NSLock()
    private static let clientStore = FB01MIDIClientStore()
    private static let immediateSender = FB01MIDIImmediateSender(clientStore: clientStore)

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
        try requestBatch(
            [.currentConfiguration] + (1...7).map { .voiceBank($0) } + [.voiceRAM1],
            sourceIndex: sourceIndex,
            destinationIndex: destinationIndex,
            systemChannel: systemChannel,
            timeoutPerRequest: timeoutPerRequest
        )
    }

    public static func requestStoredConfigurations(
        sourceIndex: Int = 0,
        destinationIndex: Int = 0,
        systemChannel: Int = 0,
        timeoutPerRequest: TimeInterval = 15
    ) throws -> [[UInt8]] {
        try requestBatch(
            (1...20).map { .configuration($0) },
            sourceIndex: sourceIndex,
            destinationIndex: destinationIndex,
            systemChannel: systemChannel,
            timeoutPerRequest: timeoutPerRequest
        )
    }

    public static func sendSysEx(
        _ messages: [[UInt8]],
        destinationIndex: Int = 0,
        delayBetweenMessages: TimeInterval = 0.2
    ) throws {
        requestLock.lock()
        defer { requestLock.unlock() }

        let destination = try destinationEndpoint(at: destinationIndex)
        let client = try clientStore.client()

        var outputPort = MIDIPortRef()
        try check(MIDIOutputPortCreate(client, "FB01EditorMIDISendOutput" as CFString, &outputPort), "MIDIOutputPortCreate")
        defer { MIDIPortDispose(outputPort) }

        for (index, bytes) in messages.enumerated() {
            try send(bytes: bytes, to: destination, outputPort: outputPort)
            if index < messages.index(before: messages.endIndex), delayBetweenMessages > 0 {
                Thread.sleep(forTimeInterval: delayBetweenMessages)
            }
        }
    }

    public static func sendLongSysEx(
        _ bytes: [UInt8],
        destinationIndex: Int = 0,
        timeout: TimeInterval = 30
    ) throws {
        requestLock.lock()
        defer { requestLock.unlock() }

        try bytes.forEach { _ = try FB01.validateByte($0) }

        let destination = try destinationEndpoint(at: destinationIndex)
        let completion = FB01MIDISysexSendCompletion()
        let retainedCompletion = Unmanaged.passRetained(completion)

        var mutableBytes = bytes
        try mutableBytes.withUnsafeMutableBufferPointer { buffer in
            guard let baseAddress = buffer.baseAddress else {
                throw FB01SysExError.invalidPayloadLength(expected: 1, actual: 0)
            }

            var request = MIDISysexSendRequest(
                destination: destination,
                data: baseAddress,
                bytesToSend: UInt32(buffer.count),
                complete: false,
                reserved: (0, 0, 0),
                completionProc: { requestPointer in
                    guard let refCon = requestPointer.pointee.completionRefCon else {
                        return
                    }
                    Unmanaged<FB01MIDISysexSendCompletion>
                        .fromOpaque(refCon)
                        .takeUnretainedValue()
                        .signal()
                },
                completionRefCon: retainedCompletion.toOpaque()
            )

            try check(MIDISendSysex(&request), "MIDISendSysex")

            let waitResult = completion.semaphore.wait(timeout: .now() + timeout)
            guard waitResult == .success else {
                throw FB01MIDIError.timedOut("long SysEx send")
            }
        }

        retainedCompletion.release()
    }

    public static func sendImmediate(_ bytes: [UInt8], destinationIndex: Int = 0) throws {
        try immediateSender.send(bytes: bytes, destinationIndex: destinationIndex)
    }

    public static func sendAndReceive(
        _ messages: [[UInt8]],
        sourceIndex: Int,
        destinationIndex: Int,
        timeout: TimeInterval = 8,
        maxMessages: Int = 1,
        delayBetweenMessages: TimeInterval = 0.2
    ) throws -> [[UInt8]] {
        requestLock.lock()
        defer { requestLock.unlock() }

        let source = try sourceEndpoint(at: sourceIndex)
        let destination = try destinationEndpoint(at: destinationIndex)
        let state = FB01SysExCaptureState()
        let client = try clientStore.client()

        var inputPort = MIDIPortRef()
        try check(MIDIInputPortCreateWithBlock(client, "FB01EditorMIDISendReceiveInput" as CFString, &inputPort) { packetList, _ in
            state.append(packetList: packetList)
        }, "MIDIInputPortCreateWithBlock")
        defer { MIDIPortDispose(inputPort) }

        var outputPort = MIDIPortRef()
        try check(MIDIOutputPortCreate(client, "FB01EditorMIDISendReceiveOutput" as CFString, &outputPort), "MIDIOutputPortCreate")
        defer { MIDIPortDispose(outputPort) }

        try check(MIDIPortConnectSource(inputPort, source, nil), "MIDIPortConnectSource")

        for (index, bytes) in messages.enumerated() {
            try send(bytes: bytes, to: destination, outputPort: outputPort)
            if index < messages.index(before: messages.endIndex), delayBetweenMessages > 0 {
                Thread.sleep(forTimeInterval: delayBetweenMessages)
            }
        }

        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
            let received = state.snapshot()
            if received.count >= maxMessages {
                return Array(received.prefix(maxMessages))
            }
        }

        let received = state.snapshot()
        if !received.isEmpty {
            return Array(received.prefix(maxMessages))
        }

        throw FB01MIDIError.timedOut("MIDI response")
    }

    private static func requestBatch(
        _ kinds: [FB01MIDIRequestKind],
        sourceIndex: Int,
        destinationIndex: Int,
        systemChannel: Int,
        timeoutPerRequest: TimeInterval
    ) throws -> [[UInt8]] {
        requestLock.lock()
        defer { requestLock.unlock() }

        let source = try sourceEndpoint(at: sourceIndex)
        let destination = try destinationEndpoint(at: destinationIndex)
        let state = FB01SysExCaptureState()
        let client = try clientStore.client()

        var inputPort = MIDIPortRef()
        try check(MIDIInputPortCreateWithBlock(client, "FB01EditorMIDIBatchInput" as CFString, &inputPort) { packetList, _ in
            state.append(packetList: packetList)
        }, "MIDIInputPortCreateWithBlock")
        defer { MIDIPortDispose(inputPort) }

        var outputPort = MIDIPortRef()
        try check(MIDIOutputPortCreate(client, "FB01EditorMIDIBatchOutput" as CFString, &outputPort), "MIDIOutputPortCreate")
        defer { MIDIPortDispose(outputPort) }

        try check(MIDIPortConnectSource(inputPort, source, nil), "MIDIPortConnectSource")

        var messages: [[UInt8]] = []
        messages.reserveCapacity(kinds.count)

        for kind in kinds {
            _ = state.drain()
            try send(bytes: kind.bytes(systemChannel: systemChannel), to: destination, outputPort: outputPort)

            let start = Date()
            var received: [UInt8]?
            while Date().timeIntervalSince(start) < timeoutPerRequest {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
                if let message = state.drain().first {
                    received = message
                    break
                }
            }

            guard let received else {
                throw FB01MIDIError.timedOut(kind.displayName)
            }
            messages.append(received)
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
        requestLock.lock()
        defer { requestLock.unlock() }

        let source = try sourceEndpoint(at: sourceIndex)
        let destination = try destinationEndpoint(at: destinationIndex)
        let requestBytes = try kind.bytes(systemChannel: systemChannel)
        let state = FB01SysExCaptureState()
        let client = try clientStore.client()

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

    fileprivate static func destinationEndpoint(at index: Int) throws -> MIDIEndpointRef {
        guard MIDIGetNumberOfDestinations() > 0 else { throw FB01MIDIError.noDestinations }
        guard index >= 0, index < MIDIGetNumberOfDestinations() else { throw FB01MIDIError.destinationNotFound(index) }
        return MIDIGetDestination(index)
    }

    fileprivate static func check(_ status: OSStatus, _ operation: String) throws {
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

    fileprivate static func send(bytes: [UInt8], to destination: MIDIEndpointRef, outputPort: MIDIPortRef) throws {
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

private final class FB01MIDISysexSendCompletion: @unchecked Sendable {
    let semaphore = DispatchSemaphore(value: 0)

    func signal() {
        semaphore.signal()
    }
}

private final class FB01MIDIClientStore: @unchecked Sendable {
    private let lock = NSLock()
    private var sharedClient: MIDIClientRef?

    func client() throws -> MIDIClientRef {
        lock.lock()
        defer { lock.unlock() }

        if let sharedClient {
            return sharedClient
        }

        var client = MIDIClientRef()
        try FB01MIDI.check(MIDIClientCreateWithBlock("FB01EditorMIDI" as CFString, &client) { _ in }, "MIDIClientCreateWithBlock")
        sharedClient = client
        return client
    }
}

private final class FB01MIDIImmediateSender: @unchecked Sendable {
    private let lock = NSLock()
    private let clientStore: FB01MIDIClientStore
    private var outputPort = MIDIPortRef()
    private var hasOutputPort = false

    init(clientStore: FB01MIDIClientStore) {
        self.clientStore = clientStore
    }

    deinit {
        if hasOutputPort {
            MIDIPortDispose(outputPort)
        }
    }

    func send(bytes: [UInt8], destinationIndex: Int) throws {
        lock.lock()
        defer { lock.unlock() }

        let destination = try FB01MIDI.destinationEndpoint(at: destinationIndex)
        let outputPort = try reusableOutputPort()
        try FB01MIDI.send(bytes: bytes, to: destination, outputPort: outputPort)
    }

    private func reusableOutputPort() throws -> MIDIPortRef {
        if hasOutputPort {
            return outputPort
        }

        let client = try clientStore.client()
        try FB01MIDI.check(MIDIOutputPortCreate(client, "FB01EditorImmediateOutput" as CFString, &outputPort), "MIDIOutputPortCreate")
        hasOutputPort = true
        return outputPort
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

    func drain() -> [[UInt8]] {
        lock.lock()
        defer { lock.unlock() }
        let snapshot = messages
        messages.removeAll(keepingCapacity: true)
        return snapshot
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

import Foundation

public struct FB01SysExPacket: Equatable, Sendable {
    public var payload: [UInt8]
    public var checksum: UInt8

    public init(payload: [UInt8]) throws {
        self.payload = try payload.map { try FB01.validateSevenBit($0) }
        self.checksum = FB01.checksum(for: self.payload)
    }

    public init(encoded bytes: ArraySlice<UInt8>) throws {
        guard bytes.count >= 3 else {
            throw FB01SysExError.invalidPayloadLength(expected: 3, actual: bytes.count)
        }

        let high = bytes[bytes.startIndex]
        let low = bytes[bytes.index(after: bytes.startIndex)]
        let count = try FB01.packetByteCount(high: high, low: low)
        let payloadStart = bytes.index(bytes.startIndex, offsetBy: 2)
        let checksumIndex = bytes.index(payloadStart, offsetBy: count, limitedBy: bytes.endIndex)

        guard let checksumIndex, checksumIndex < bytes.endIndex else {
            throw FB01SysExError.invalidPayloadLength(expected: count + 3, actual: bytes.count)
        }

        let payload = Array(bytes[payloadStart..<checksumIndex])
        let checksum = bytes[checksumIndex]
        guard bytes.index(after: checksumIndex) == bytes.endIndex else {
            throw FB01SysExError.invalidPayloadLength(expected: count + 3, actual: bytes.count)
        }

        try self.init(payload: payload, checksum: checksum)
    }

    public init(payload: [UInt8], checksum: UInt8) throws {
        self.payload = try payload.map { try FB01.validateSevenBit($0) }
        self.checksum = try FB01.validateSevenBit(checksum)
        let expected = FB01.checksum(for: self.payload)
        guard expected == self.checksum else {
            throw FB01SysExError.checksumMismatch(expected: expected, actual: self.checksum)
        }
    }

    public var encodedBytes: [UInt8] {
        get throws {
            let count = try FB01.byteCountPair(for: payload.count)
            return [count.high, count.low] + payload + [checksum]
        }
    }
}

public enum FB01SysExMessage: Equatable, Sendable {
    case command(FB01Command)
    case instrumentVoiceDump(systemChannel: Int, instrument: Int, packet: FB01SysExPacket)
    case currentConfigurationDump(systemChannel: Int, packet: FB01SysExPacket)
    case configurationDump(systemChannel: Int, number: Int, packet: FB01SysExPacket)
    case allConfigurationsDump(systemChannel: Int, packets: [FB01SysExPacket])
    case voiceBankDump(systemChannel: Int, bank: Int?, packets: [FB01SysExPacket])
    case voiceRAMDumpData(systemChannel: Int, byteCount: Int, data: [UInt8], checksum: UInt8)
    case voiceBankDumpData(systemChannel: Int, bank: Int, byteCount: Int, data: [UInt8], checksum: UInt8)
    case unitIDDump(systemChannel: Int, packet: FB01SysExPacket)
    case deviceStatus(code: UInt8)
    case raw([UInt8])

    public init(bytes: [UInt8]) throws {
        try FB01.validateSysExEnvelope(bytes)

        let body = Array(bytes.dropFirst(2).dropLast())

        if let command = try Self.parseCommand(body: body) {
            self = .command(command)
            return
        }

        if let dump = try Self.parseDump(body: body) {
            self = dump
            return
        }

        self = .raw(bytes)
    }

    public var bytes: [UInt8] {
        get throws {
            switch self {
            case .command(let command):
                return try command.bytes
            case let .instrumentVoiceDump(systemChannel, instrument, packet):
                return try envelope([FB01.fb01Substatus, UInt8(systemChannel), 0x08 | UInt8(instrument), 0x00, 0x00] + packet.encodedBytes)
            case let .currentConfigurationDump(systemChannel, packet):
                return try envelope([FB01.fb01Substatus, UInt8(systemChannel), 0x00, 0x01, 0x00] + packet.encodedBytes)
            case let .configurationDump(systemChannel, number, packet):
                return try envelope([FB01.fb01Substatus, UInt8(systemChannel), 0x00, 0x02, UInt8(number)] + packet.encodedBytes)
            case let .allConfigurationsDump(systemChannel, packets):
                let packetBytes = try packets.flatMap { try $0.encodedBytes }
                return envelope([FB01.fb01Substatus, UInt8(systemChannel), 0x00, 0x03, 0x00] + packetBytes)
            case let .voiceBankDump(systemChannel, bank, packets):
                let bankByte = bank.map(UInt8.init) ?? 0x00
                let packetBytes = try packets.flatMap { try $0.encodedBytes }
                return envelope([FB01.fb01Substatus, UInt8(systemChannel), 0x0C, 0x00, 0x00, bankByte] + packetBytes)
            case let .voiceRAMDumpData(systemChannel, byteCount, data, checksum):
                let count = try FB01.byteCountPair(for: byteCount)
                let data = try data.map { try FB01.validateSevenBit($0) }
                let checksum = try FB01.validateSevenBit(checksum)
                return envelope([UInt8(systemChannel), 0x0C, count.high, count.low] + data + [checksum])
            case let .voiceBankDumpData(systemChannel, bank, byteCount, data, checksum):
                let count = try FB01.byteCountPair(for: byteCount)
                let data = try data.map { try FB01.validateSevenBit($0) }
                let checksum = try FB01.validateSevenBit(checksum)
                return envelope([FB01.fb01Substatus, UInt8(systemChannel), 0x00, 0x00, UInt8(bank), count.high, count.low] + data + [checksum])
            case let .unitIDDump(systemChannel, packet):
                return try envelope([FB01.fb01Substatus, UInt8(systemChannel), 0x00, 0x04, 0x00] + packet.encodedBytes)
            case .deviceStatus(let code):
                return try envelope([0x60, FB01.validateSevenBit(code)])
            case .raw(let bytes):
                return bytes
            }
        }
    }

    public static func splitMessages(from bytes: [UInt8]) throws -> [FB01SysExMessage] {
        var messages: [FB01SysExMessage] = []
        var current: [UInt8]?

        for byte in bytes {
            if byte == FB01.start {
                current = [byte]
                continue
            }

            guard current != nil else {
                if byte == 0 { continue }
                throw FB01SysExError.invalidSysEx
            }

            current?.append(byte)

            if byte == FB01.end {
                if let messageBytes = current {
                    messages.append(try FB01SysExMessage(bytes: messageBytes))
                }
                current = nil
            }
        }

        if current != nil {
            throw FB01SysExError.invalidSysEx
        }

        return messages
    }

    private static func parseCommand(body: [UInt8]) throws -> FB01Command? {
        guard !body.isEmpty else { return nil }

        if body.count == 2, (0x20...0x2F).contains(body[0]), body[1] == 0x0C {
            return .requestVoiceRAM1(systemChannel: Int(body[0] & 0x0F))
        }

        guard body[0] == FB01.fb01Substatus else { return nil }

        if body.count == 5, body[2] == 0x20 {
            let systemChannel = Int(body[1] & 0x0F)
            switch body[3] {
            case 0x00:
                guard body[4] <= 0x06 else { return nil }
                return .requestVoiceBank(systemChannel: systemChannel, bank: Int(body[4]) + 1)
            case 0x01 where body[4] == 0x00:
                return .requestCurrentConfiguration(systemChannel: systemChannel)
            case 0x02:
                return .requestConfiguration(systemChannel: systemChannel, number: Int(body[4]))
            case 0x03 where body[4] == 0x00:
                return .requestAllConfigurations(systemChannel: systemChannel)
            case 0x04 where body[4] == 0x00:
                return .requestUnitID(systemChannel: systemChannel)
            case 0x40:
                return .storeCurrentConfiguration(systemChannel: systemChannel, number: Int(body[4]))
            default:
                return nil
            }
        }

        if body.count == 5, body[2] == 0x10, body[3] == 0x21 {
            let systemChannel = Int(body[1] & 0x0F)
            switch body[4] {
            case FB01MemoryProtect.off.rawValue:
                return .setMemoryProtect(systemChannel: systemChannel, .off)
            case FB01MemoryProtect.on.rawValue:
                return .setMemoryProtect(systemChannel: systemChannel, .on)
            default:
                return nil
            }
        }

        if body.count == 5, (0x28...0x2F).contains(body[2]), body[3] == 0x00 {
            return .storeCurrentInstrumentVoice(
                systemChannel: Int(body[1] & 0x0F),
                instrument: Int(body[2] & 0x07),
                voiceNumber: Int(body[4])
            )
        }

        if body.count == 5, (0x28...0x2F).contains(body[2]), body[3] == 0x40, body[4] == 0x00 {
            return .requestInstrumentVoice(systemChannel: Int(body[1] & 0x0F), instrument: Int(body[2] & 0x07))
        }

        return nil
    }

    private static func parseDump(body: [UInt8]) throws -> FB01SysExMessage? {
        if body.count == 2, body[0] == 0x60 {
            return .deviceStatus(code: try FB01.validateSevenBit(body[1]))
        }

        if body.count >= 7, (0x00...0x0F).contains(body[0]), body[1] == 0x0C {
            let systemChannel = Int(body[0] & 0x0F)
            let count = try FB01.packetByteCount(high: body[2], low: body[3])
            let data = try body[4..<body.index(before: body.endIndex)].map { try FB01.validateSevenBit($0) }
            let checksum = try FB01.validateSevenBit(body[body.index(before: body.endIndex)])
            return .voiceRAMDumpData(systemChannel: systemChannel, byteCount: count, data: data, checksum: checksum)
        }

        guard body.count >= 8, body[0] == FB01.fb01Substatus else { return nil }

        let systemChannel = Int(body[1] & 0x0F)
        let messageNumber = body[2]

        if messageNumber == 0x0C, body.count >= 9, body[3] == 0x00, body[4] == 0x00 {
            return .voiceBankDump(systemChannel: systemChannel, bank: Int(body[5]), packets: try parsePackets(body[6...]))
        }

        if messageNumber == 0x00 {
            if body[3] == 0x00, body.count >= 9 {
                guard body[4] <= 0x06 else { return nil }
                let bank = Int(body[4])
                let count = try FB01.packetByteCount(high: body[5], low: body[6])
                let data = try body[7..<body.index(before: body.endIndex)].map { try FB01.validateSevenBit($0) }
                let checksum = try FB01.validateSevenBit(body[body.index(before: body.endIndex)])
                return .voiceBankDumpData(systemChannel: systemChannel, bank: bank, byteCount: count, data: data, checksum: checksum)
            }

            switch body[3] {
            case 0x01 where body[4] == 0x00:
                return .currentConfigurationDump(systemChannel: systemChannel, packet: try FB01SysExPacket(encoded: body[5...]))
            case 0x02:
                return .configurationDump(systemChannel: systemChannel, number: Int(body[4]), packet: try FB01SysExPacket(encoded: body[5...]))
            case 0x03 where body[4] == 0x00:
                return .allConfigurationsDump(systemChannel: systemChannel, packets: try parsePackets(body[5...]))
            case 0x04 where body[4] == 0x00:
                return .unitIDDump(systemChannel: systemChannel, packet: try FB01SysExPacket(encoded: body[5...]))
            default:
                return nil
            }
        }

        if (0x08...0x0F).contains(messageNumber), body[3] == 0x00, body[4] == 0x00 {
            let packet = try FB01SysExPacket(encoded: body[5...])
            return .instrumentVoiceDump(systemChannel: systemChannel, instrument: Int(messageNumber & 0x07), packet: packet)
        }

        return nil
    }

    private static func parsePackets(_ bytes: ArraySlice<UInt8>) throws -> [FB01SysExPacket] {
        var packets: [FB01SysExPacket] = []
        var index = bytes.startIndex

        while index < bytes.endIndex {
            guard bytes.distance(from: index, to: bytes.endIndex) >= 3 else {
                throw FB01SysExError.invalidPayloadLength(expected: 3, actual: bytes.distance(from: index, to: bytes.endIndex))
            }

            let count = try FB01.packetByteCount(high: bytes[index], low: bytes[bytes.index(after: index)])
            let packetEnd = bytes.index(index, offsetBy: count + 3, limitedBy: bytes.endIndex)
            guard let packetEnd else {
                throw FB01SysExError.invalidPayloadLength(expected: count + 3, actual: bytes.distance(from: index, to: bytes.endIndex))
            }

            packets.append(try FB01SysExPacket(encoded: bytes[index..<packetEnd]))
            index = packetEnd
        }

        return packets
    }

    private func envelope(_ body: [UInt8]) -> [UInt8] {
        [FB01.start, FB01.yamahaID] + body + [FB01.end]
    }
}

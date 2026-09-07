import Foundation

/// TX81Z Performance data. PCED's declared 120-byte data block includes the
/// ten-byte Yamaha identifier, leaving 110 editable parameter bytes. PMEM is
/// a bank of 32 compact 76-byte Performance records.
public struct TX81ZPerformanceData: Equatable, Sendable {
    public static let editDataLength = 110
    public static let memoryDataLength = 76
    public static let nameLength = 10
    public static let editNameOffset = 100
    public static let memoryNameOffset = 66

    public let bytes: [UInt8]
    public let isEditBuffer: Bool

    public init(editBytes: [UInt8]) throws {
        guard editBytes.count == Self.editDataLength else {
            throw TX81ZSysExError.invalidPerformanceDataLength(expected: Self.editDataLength, actual: editBytes.count)
        }
        self.bytes = editBytes
        self.isEditBuffer = true
    }

    public init(memoryBytes: [UInt8]) throws {
        guard memoryBytes.count == Self.memoryDataLength else {
            throw TX81ZSysExError.invalidPerformanceDataLength(expected: Self.memoryDataLength, actual: memoryBytes.count)
        }
        self.bytes = memoryBytes
        self.isEditBuffer = false
    }

    public var name: String {
        let offset = isEditBuffer ? Self.editNameOffset : Self.memoryNameOffset
        return String(bytes: bytes[offset..<(offset + Self.nameLength)], encoding: .ascii)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    public func settingName(_ name: String) throws -> TX81ZPerformanceData {
        guard isEditBuffer else { throw TX81ZSysExError.performanceRequiresEditBuffer }
        var updated = bytes
        let encoded = Array(name.uppercased().utf8.prefix(Self.nameLength)).map { min(max($0, 32), 127) }
        updated.replaceSubrange(
            Self.editNameOffset..<(Self.editNameOffset + Self.nameLength),
            with: encoded + Array(repeating: UInt8(ascii: " "), count: Self.nameLength - encoded.count)
        )
        return try TX81ZPerformanceData(editBytes: updated)
    }

    public func settingInstrument(_ number: Int, parameter: Int, value: Int) throws -> TX81ZPerformanceData {
        guard isEditBuffer else { throw TX81ZSysExError.performanceRequiresEditBuffer }
        guard (1...8).contains(number), (0...11).contains(parameter), (0...127).contains(value) else {
            throw TX81ZSysExError.invalidPerformanceParameter
        }
        var updated = bytes
        updated[(number - 1) * 12 + parameter] = UInt8(value)
        return try TX81ZPerformanceData(editBytes: updated)
    }

    public func performanceEditBulkSysEx(channel: Int = 0) throws -> [UInt8] {
        guard isEditBuffer else { throw TX81ZSysExError.performanceRequiresEditBuffer }
        guard (0...15).contains(channel) else { throw TX81ZSysExError.invalidChannel(channel) }
        let identifier = TX81Z.performanceEditIdentifier
        return [TX81Z.start, TX81Z.yamahaID, UInt8(channel), TX81Z.additionalVoiceFormat, 0, 0x78]
            + identifier
            + bytes
            + [TX81Z.performanceChecksum(identifier: identifier, data: bytes), TX81Z.end]
    }

    public var instruments: [TX81ZPerformanceInstrument] {
        let recordLength = isEditBuffer ? 12 : 8
        return (0..<8).map {
            TX81ZPerformanceInstrument(
                bytes: Array(bytes[($0 * recordLength)..<($0 * recordLength + recordLength)]),
                isCompactMemoryRecord: !isEditBuffer
            )
        }
    }
}

public struct TX81ZPerformanceInstrument: Equatable, Sendable {
    public let bytes: [UInt8]
    public let isCompactMemoryRecord: Bool

    public init(bytes: [UInt8], isCompactMemoryRecord: Bool) {
        self.bytes = bytes
        self.isCompactMemoryRecord = isCompactMemoryRecord
    }

    public var maximumNotes: Int? { isCompactMemoryRecord ? nil : Int(bytes[0]) }
    public var voiceBank: Int? { isCompactMemoryRecord ? nil : Int(bytes[1]) }
    public var voiceNumber: Int? { isCompactMemoryRecord ? nil : Int(bytes[2]) + 1 }
    public var receiveChannel: Int? { isCompactMemoryRecord || bytes[3] == 16 ? nil : Int(bytes[3]) + 1 }
    public var volume: Int? { isCompactMemoryRecord ? nil : Int(bytes[8]) }
    public var outputAssignment: Int? { isCompactMemoryRecord ? nil : Int(bytes[9]) }

    public var voiceLocation: String? {
        guard let voiceBank, let voiceNumber else { return nil }
        let bankNames = ["I", "A", "B", "C", "D"]
        let bank = bankNames.indices.contains(voiceBank) ? bankNames[voiceBank] : "?"
        return "\(bank)\(String(format: "%02d", voiceNumber))"
    }
}

public struct TX81ZPerformanceBankData: Equatable, Sendable {
    public static let performanceCount = 32
    public static let dataLength = TX81ZPerformanceData.memoryDataLength * performanceCount

    public let channel: Int
    public let rawData: [UInt8]

    public init(performanceMemoryBulkSysEx bytes: [UInt8]) throws {
        let identifier = TX81Z.performanceMemoryIdentifier
        let expectedLength = 6 + identifier.count + Self.dataLength + 2
        guard bytes.count == expectedLength,
              bytes[0] == TX81Z.start,
              bytes[1] == TX81Z.yamahaID,
              (bytes[2] & 0xF0) == 0x00,
              bytes[3] == TX81Z.additionalVoiceFormat,
              bytes[4] == 0x13,
              bytes[5] == 0x0A,
              Array(bytes[6..<(6 + identifier.count)]) == identifier,
              bytes.last == TX81Z.end else {
            throw TX81ZSysExError.invalidPerformanceBulkHeader
        }

        let dataStart = 6 + identifier.count
        let data = Array(bytes[dataStart..<(dataStart + Self.dataLength)])
        let checksum = bytes[dataStart + Self.dataLength]
        guard TX81Z.performanceChecksum(identifier: identifier, data: data) == checksum else {
            throw TX81ZSysExError.checksumMismatch(
                expected: TX81Z.performanceChecksum(identifier: identifier, data: data),
                actual: checksum
            )
        }

        channel = Int(bytes[2] & 0x0F)
        rawData = data
    }

    public var performances: [TX81ZPerformanceData] {
        (0..<Self.performanceCount).compactMap { index in
            try? TX81ZPerformanceData(memoryBytes: Array(rawData[(index * TX81ZPerformanceData.memoryDataLength)..<((index + 1) * TX81ZPerformanceData.memoryDataLength)]))
        }
    }
}

public extension TX81Z {
    static let performanceEditIdentifier = Array("LM  8976PE".utf8)
    static let performanceMemoryIdentifier = Array("LM  8976PM".utf8)
    static let programChangeTableIdentifier = Array("LM  8976S1".utf8)
    static let systemSetupIdentifier = Array("LM  8976S0".utf8)

    static func requestPerformanceEditData(channel: Int = 0) throws -> [UInt8] {
        guard (0...15).contains(channel) else { throw TX81ZSysExError.invalidChannel(channel) }
        return [start, yamahaID, dumpRequestStatusBase | UInt8(channel), additionalVoiceFormat]
            + performanceEditIdentifier + [end]
    }

    static func requestPerformanceMemoryBank(channel: Int = 0) throws -> [UInt8] {
        guard (0...15).contains(channel) else { throw TX81ZSysExError.invalidChannel(channel) }
        return [start, yamahaID, dumpRequestStatusBase | UInt8(channel), additionalVoiceFormat]
            + performanceMemoryIdentifier + [end]
    }

    static func requestProgramChangeTable(channel: Int = 0) throws -> [UInt8] {
        guard (0...15).contains(channel) else { throw TX81ZSysExError.invalidChannel(channel) }
        return [start, yamahaID, dumpRequestStatusBase | UInt8(channel), additionalVoiceFormat]
            + programChangeTableIdentifier + [end]
    }

    static func requestSystemSetup(channel: Int = 0) throws -> [UInt8] {
        guard (0...15).contains(channel) else { throw TX81ZSysExError.invalidChannel(channel) }
        return [start, yamahaID, dumpRequestStatusBase | UInt8(channel), additionalVoiceFormat]
            + systemSetupIdentifier + [end]
    }

    static func performanceChecksum(identifier: [UInt8], data: [UInt8]) -> UInt8 {
        UInt8((128 - (identifier + data).reduce(0) { ($0 + Int($1)) & 0x7F }) & 0x7F)
    }
}

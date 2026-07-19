import FB01Editor
import Foundation

let mappings = FB01GeneralMIDI.mappings

func argumentValue(_ name: String, default defaultValue: Int) -> Int {
    let args = CommandLine.arguments
    guard let index = args.firstIndex(of: name),
          args.indices.contains(args.index(after: index)),
          let value = Int(args[args.index(after: index)]) else {
        return defaultValue
    }
    return value
}

func hasFlag(_ name: String) -> Bool {
    CommandLine.arguments.contains(name)
}

func log(_ message: String) {
    print(message)
    fflush(stdout)
}

func artifactVoiceBank(from bytes: [UInt8], expectedBank: Int) throws -> FB01VoiceBankData {
    let artifact = try FB01Artifact(sysexBytes: bytes)
    for message in artifact.messages {
        if case let .voiceBankDumpData(_, bank, _, data, _) = message, bank == expectedBank - 1 {
            return try FB01VoiceBankData(bank: bank, data: data)
        }
    }
    throw StringError("Response did not contain Bank \(expectedBank)")
}

func instrumentVoice(from bytes: [UInt8]) throws -> FB01VoiceData {
    let artifact = try FB01Artifact(sysexBytes: bytes)
    for message in artifact.messages {
        if case let .instrumentVoiceDump(_, _, packet) = message {
            return try FB01VoiceData(bytes: FB01.nibbleDecode(packet.payload))
        }
    }
    throw StringError("Response did not contain an instrument voice")
}

func voiceBankLoadMessage(bank: FB01VoiceBankData, systemChannel: Int) throws -> [UInt8] {
    try FB01SysExMessage.voiceBankDumpData(
        systemChannel: systemChannel,
        bank: bank.bank,
        byteCount: FB01VoiceBankData.bankHeaderByteCount,
        data: bank.data,
        checksum: FB01.checksum(for: bank.data)
    ).bytes
}

func chunks(_ bytes: [UInt8], size: Int) -> [[UInt8]] {
    stride(from: 0, to: bytes.count, by: size).map { start in
        Array(bytes[start..<min(start + size, bytes.count)])
    }
}

func sendBankLoad(_ bytes: [UInt8], destinationIndex: Int) throws {
    try FB01MIDI.sendLongSysEx(bytes, destinationIndex: destinationIndex, timeout: 45)
    Thread.sleep(forTimeInterval: 1.5)
}

func statusDescription(from messages: [[UInt8]]) -> String {
    for bytes in messages {
        if let message = try? FB01SysExMessage(bytes: bytes),
           case let .deviceStatus(code) = message {
            return String(format: "status 0x%02X", code)
        }
    }
    return "no parsed status"
}

func voiceParameterMessages(voice: FB01VoiceData, systemChannel: Int, instrument: Int) throws -> [[UInt8]] {
    try voice.bytes.enumerated().map { offset, byte in
        let parameter = byte <= 0x7F ? offset : 0x40 + offset
        let value: FB01ParameterValue = byte <= 0x7F ? .oneByte(byte) : .twoByte(byte)
        return try FB01SysExMessage.command(.midiChannelParameterChange(
            midiChannel: instrument,
            parameter: parameter,
            value: value
        )).bytes
    }
}

func mismatchDescriptions(readback: FB01VoiceBankData, targetBank: Int, selectedVoices: [Int: FB01VoiceData]) -> [String] {
    mappings.compactMap { mapping -> String? in
        guard let expected = selectedVoices[mapping.gmNumber],
              let actual = readback.voices.first(where: { $0.number == mapping.gmNumber })?.voice else {
            return "Bank \(targetBank) Voice \(mapping.gmNumber): missing readback"
        }
        guard actual.bytes == expected.bytes else {
            return "Bank \(targetBank) Voice \(mapping.gmNumber): expected \(expected.name), got \(actual.name)"
        }
        return nil
    }
}

struct StringError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}

let sourceIndex = argumentValue("--source", default: 0)
let destinationIndex = argumentValue("--destination", default: 0)
let systemChannel = argumentValue("--system-channel", default: 0)
let instrument = argumentValue("--instrument", default: 0)
let diagnoseOnly = hasFlag("--diagnose-only")
let verifyOnly = hasFlag("--verify-only")
let storeOneGMNumber = argumentValue("--store-one", default: 0)
let storeOneTargetBank = argumentValue("--target-bank", default: 1)
let parameterTest = argumentValue("--param-test", default: -1)
let parameterTestValue = argumentValue("--value", default: 0)
var sourceNameMismatchCount = 0

log("Loading 48 GM-mapped voices into FB-01 Bank 1 and Bank 2")
log("Source \(sourceIndex), destination \(destinationIndex), system channel \(systemChannel), edit buffer instrument \(instrument + 1)")

let sourceBanks = Set(mappings.map(\.sourceBank)).sorted()
var banks: [Int: FB01VoiceBankData] = [:]
for bank in sourceBanks {
    log("Fetching source Bank \(bank)...")
    let bytes = try FB01MIDI.request(
        .voiceBank(bank),
        sourceIndex: sourceIndex,
        destinationIndex: destinationIndex,
        systemChannel: systemChannel,
        timeout: 15
    )
    banks[bank] = try artifactVoiceBank(from: bytes, expectedBank: bank)
}

var selectedVoices: [Int: FB01VoiceData] = [:]
for mapping in mappings {
    guard let voice = banks[mapping.sourceBank]?.voices.first(where: { $0.number == mapping.sourceVoice })?.voice else {
        throw StringError("Missing source Bank \(mapping.sourceBank) Voice \(mapping.sourceVoice)")
    }
    let actual = voice.name
    if actual.caseInsensitiveCompare(mapping.expectedName) != .orderedSame {
        sourceNameMismatchCount += 1
        if !verifyOnly {
            print("Note: GM \(mapping.gmNumber) \(mapping.gmName) maps to Bank \(mapping.sourceBank) Voice \(mapping.sourceVoice); spreadsheet name '\(mapping.expectedName)' differs from fetched name '\(actual)'")
            fflush(stdout)
        }
    }
    selectedVoices[mapping.gmNumber] = voice
}
if verifyOnly, sourceNameMismatchCount > 0 {
    log("Note: \(sourceNameMismatchCount) spreadsheet source names differ from the fetched device names; comparing by Bank/Voice and byte data.")
}

if diagnoseOnly {
    log("Diagnostic: reading current Bank 1 as bank-load base.")
    let targetBytes = try FB01MIDI.request(
        .voiceBank(1),
        sourceIndex: sourceIndex,
        destinationIndex: destinationIndex,
        systemChannel: systemChannel,
        timeout: 15
    )
    let targetBank = try artifactVoiceBank(from: targetBytes, expectedBank: 1)
    let edits = Dictionary(uniqueKeysWithValues: try mappings.map { mapping -> (Int, FB01VoiceData) in
        guard let voice = selectedVoices[mapping.gmNumber] else {
            throw StringError("No selected voice for GM \(mapping.gmNumber)")
        }
        return (mapping.gmNumber, voice)
    })
    let editedBank = try targetBank.replacingVoices(edits)
    let loadMessage = try voiceBankLoadMessage(bank: editedBank, systemChannel: systemChannel)
    let protectOff = try FB01SysExMessage.command(.setMemoryProtect(systemChannel: systemChannel, .off)).bytes

    log("Diagnostic: setting Protect OFF before Bank 1 bulk load.")
    do {
        let response = try FB01MIDI.sendAndReceive(
            [protectOff],
            sourceIndex: sourceIndex,
            destinationIndex: destinationIndex,
            timeout: 2,
            maxMessages: 1,
            delayBetweenMessages: 0
        )
        log("Diagnostic: Protect OFF response \(statusDescription(from: response)).")
    } catch {
        log("Diagnostic: Protect OFF did not return a status within 2 seconds: \(error)")
    }

    log("Diagnostic: sending Bank 1 bulk load with all 48 GM-mapped voices.")
    try sendBankLoad(loadMessage, destinationIndex: destinationIndex)

    log("Diagnostic: reading back Bank 1.")
    let bankBytes = try FB01MIDI.request(
        .voiceBank(1),
        sourceIndex: sourceIndex,
        destinationIndex: destinationIndex,
        systemChannel: systemChannel,
        timeout: 15
    )
    let bank = try artifactVoiceBank(from: bankBytes, expectedBank: 1)
    let mismatches = mappings.compactMap { mapping -> String? in
        guard let expected = selectedVoices[mapping.gmNumber],
              let actual = bank.voices.first(where: { $0.number == mapping.gmNumber })?.voice else {
            return "Bank 1 Voice \(mapping.gmNumber): missing readback"
        }
        guard actual.bytes == expected.bytes else {
            return "Bank 1 Voice \(mapping.gmNumber): expected \(expected.name), got \(actual.name)"
        }
        return nil
    }
    if mismatches.isEmpty {
        log("Diagnostic success: Bank 1 matches all 48 GM-mapped voices.")
        exit(0)
    }
    log("Diagnostic found \(mismatches.count) mismatches:\n  \(mismatches.prefix(12).joined(separator: "\n  "))")
    exit(2)
}

if storeOneGMNumber > 0 {
    guard (1...48).contains(storeOneGMNumber),
          (1...2).contains(storeOneTargetBank),
          let voice = selectedVoices[storeOneGMNumber] else {
        throw StringError("--store-one requires a GM number 1...48 and --target-bank 1 or 2")
    }

    let slot = (storeOneTargetBank - 1) * FB01VoiceBankData.voiceCount + (storeOneGMNumber - 1)
    let protectOff = try FB01SysExMessage.command(.setMemoryProtect(systemChannel: systemChannel, .off)).bytes
    let storeCommand = try FB01SysExMessage.command(.storeCurrentInstrumentVoice(
        systemChannel: systemChannel,
        instrument: instrument,
        voiceNumber: slot
    )).bytes

    log("Store-one: setting Protect OFF.")
    try FB01MIDI.sendSysEx([protectOff], destinationIndex: destinationIndex, delayBetweenMessages: 0)
    Thread.sleep(forTimeInterval: 0.3)

    let selectTargetMessages = try [
        FB01SysExMessage.command(.instrumentParameterChange(
            systemChannel: systemChannel,
            instrument: instrument,
            parameter: 0x04,
            value: .oneByte(UInt8(storeOneTargetBank))
        )).bytes,
        FB01SysExMessage.command(.instrumentParameterChange(
            systemChannel: systemChannel,
            instrument: instrument,
            parameter: 0x05,
            value: .oneByte(UInt8(storeOneGMNumber - 1))
        )).bytes,
    ]
    log("Store-one: selecting instrument \(instrument + 1) target Bank \(storeOneTargetBank) Voice \(storeOneGMNumber).")
    try FB01MIDI.sendSysEx(selectTargetMessages, destinationIndex: destinationIndex, delayBetweenMessages: 0.05)
    Thread.sleep(forTimeInterval: 0.5)

    let programNumber = (storeOneTargetBank - 1) * FB01VoiceBankData.voiceCount + (storeOneGMNumber - 1)
    log("Store-one: sending MIDI program change \(programNumber + 1) on channel \(instrument + 1).")
    try FB01MIDI.sendSysEx([[0xC0 | UInt8(instrument), UInt8(programNumber)]], destinationIndex: destinationIndex, delayBetweenMessages: 0)
    Thread.sleep(forTimeInterval: 0.3)

    log("Store-one: writing \(voice.name) to instrument \(instrument + 1) edit buffer as 64 parameter changes.")
    try FB01MIDI.sendSysEx(
        voiceParameterMessages(voice: voice, systemChannel: systemChannel, instrument: instrument),
        destinationIndex: destinationIndex,
        delayBetweenMessages: 0.02
    )
    Thread.sleep(forTimeInterval: 0.8)

    log("Store-one: storing instrument \(instrument + 1) to Bank \(storeOneTargetBank) Voice \(storeOneGMNumber).")
    try FB01MIDI.sendSysEx([storeCommand], destinationIndex: destinationIndex, delayBetweenMessages: 0)
    Thread.sleep(forTimeInterval: 1.2)

    log("Store-one: reading back Bank \(storeOneTargetBank).")
    let bankBytes = try FB01MIDI.request(
        .voiceBank(storeOneTargetBank),
        sourceIndex: sourceIndex,
        destinationIndex: destinationIndex,
        systemChannel: systemChannel,
        timeout: 15
    )
    let bank = try artifactVoiceBank(from: bankBytes, expectedBank: storeOneTargetBank)
    let actual = bank.voices[storeOneGMNumber - 1].voice
    if actual.bytes == voice.bytes {
        log("Store-one success: Bank \(storeOneTargetBank) Voice \(storeOneGMNumber) is \(actual.name).")
        exit(0)
    }
    log("Store-one failed: Bank \(storeOneTargetBank) Voice \(storeOneGMNumber) expected \(voice.name), got \(actual.name).")
    exit(2)
}

if parameterTest >= 0 {
    log("Parameter-test: reading instrument \(instrument + 1) before change.")
    let beforeBytes = try FB01MIDI.request(
        .instrumentVoice(instrument + 1),
        sourceIndex: sourceIndex,
        destinationIndex: destinationIndex,
        systemChannel: systemChannel,
        timeout: 8
    )
    let beforeVoice = try instrumentVoice(from: beforeBytes)
    log("Parameter-test: before name \(beforeVoice.name), first bytes \(beforeVoice.bytes.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " "))")

    let command = try FB01SysExMessage.command(.instrumentParameterChange(
        systemChannel: systemChannel,
        instrument: instrument,
        parameter: parameterTest,
        value: .oneByte(UInt8(parameterTestValue))
    )).bytes
    log("Parameter-test: sending parameter \(parameterTest) value \(parameterTestValue).")
    try FB01MIDI.sendSysEx([command], destinationIndex: destinationIndex, delayBetweenMessages: 0)
    Thread.sleep(forTimeInterval: 0.4)

    log("Parameter-test: reading instrument \(instrument + 1) after change.")
    let afterBytes = try FB01MIDI.request(
        .instrumentVoice(instrument + 1),
        sourceIndex: sourceIndex,
        destinationIndex: destinationIndex,
        systemChannel: systemChannel,
        timeout: 8
    )
    let afterVoice = try instrumentVoice(from: afterBytes)
    log("Parameter-test: after name \(afterVoice.name), first bytes \(afterVoice.bytes.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " "))")
    log("Parameter-test: changed byte offsets \(zip(beforeVoice.bytes.indices, zip(beforeVoice.bytes, afterVoice.bytes)).compactMap { index, pair in pair.0 == pair.1 ? nil : String(index) }.joined(separator: ", "))")
    exit(beforeVoice.bytes == afterVoice.bytes ? 2 : 0)
}

if !verifyOnly {
let protectOff = try FB01SysExMessage.command(.setMemoryProtect(systemChannel: systemChannel, .off)).bytes
log("Setting Protect OFF before bank bulk loads...")
do {
    let response = try FB01MIDI.sendAndReceive(
        [protectOff],
        sourceIndex: sourceIndex,
        destinationIndex: destinationIndex,
        timeout: 2,
        maxMessages: 1,
        delayBetweenMessages: 0
    )
    log("Protect OFF response \(statusDescription(from: response)).")
} catch {
    log("Protect OFF did not return a status within 2 seconds: \(error)")
}

let edits = Dictionary(uniqueKeysWithValues: try mappings.map { mapping -> (Int, FB01VoiceData) in
    guard let voice = selectedVoices[mapping.gmNumber] else {
        throw StringError("No selected voice for GM \(mapping.gmNumber)")
    }
    return (mapping.gmNumber, voice)
})

for targetBank in 1...2 {
    log("Programming Bank \(targetBank)...")
    var bankBytes = try FB01MIDI.request(
        .voiceBank(targetBank),
        sourceIndex: sourceIndex,
        destinationIndex: destinationIndex,
        systemChannel: systemChannel,
        timeout: 15
    )
    var readback = try artifactVoiceBank(from: bankBytes, expectedBank: targetBank)
    var mismatches = mismatchDescriptions(readback: readback, targetBank: targetBank, selectedVoices: selectedVoices)
    var previousMismatchCount = mismatches.count + 1
    var pass = 0

    while !mismatches.isEmpty {
        pass += 1
        guard pass <= 60 else {
            throw StringError("Bank \(targetBank) still has \(mismatches.count) mismatches after 60 passes.")
        }
        guard mismatches.count < previousMismatchCount else {
            throw StringError("Bank \(targetBank) made no progress; still has \(mismatches.count) mismatches. First mismatch: \(mismatches[0])")
        }

        previousMismatchCount = mismatches.count
        let editedBank = try readback.replacingVoices(edits)
        log("Bank \(targetBank) pass \(pass): \(mismatches.count) mismatches remain; sending bank image.")
        try sendBankLoad(try voiceBankLoadMessage(bank: editedBank, systemChannel: systemChannel), destinationIndex: destinationIndex)

        bankBytes = try FB01MIDI.request(
            .voiceBank(targetBank),
            sourceIndex: sourceIndex,
            destinationIndex: destinationIndex,
            systemChannel: systemChannel,
            timeout: 15
        )
        readback = try artifactVoiceBank(from: bankBytes, expectedBank: targetBank)
        mismatches = mismatchDescriptions(readback: readback, targetBank: targetBank, selectedVoices: selectedVoices)
    }
    log("Bank \(targetBank) verified.")
}
}

var mismatches: [String] = []
for targetBank in 1...2 {
    log("Reading back Bank \(targetBank) for verification...")
    let bytes = try FB01MIDI.request(
        .voiceBank(targetBank),
        sourceIndex: sourceIndex,
        destinationIndex: destinationIndex,
        systemChannel: systemChannel,
        timeout: 15
    )
    let readback = try artifactVoiceBank(from: bytes, expectedBank: targetBank)
    mismatches.append(contentsOf: mismatchDescriptions(readback: readback, targetBank: targetBank, selectedVoices: selectedVoices))
}

if !mismatches.isEmpty {
    let sample = mismatches.prefix(12).joined(separator: "\n  ")
    throw StringError("Readback found \(mismatches.count) mismatches:\n  \(sample)")
}

log("Success: Bank 1 and Bank 2 both match the 48-voice General MIDI mapping.")

import Foundation
import FB01Editor

actor LiveMIDIPlaybackController {
    static let shared = LiveMIDIPlaybackController()

    func sendImmediate(_ message: [UInt8], destinationIndex: Int) throws {
        try FB01MIDI.sendImmediate(message, destinationIndex: destinationIndex)
    }

    func sendPreparedMessages(_ messages: [[UInt8]], destinationIndex: Int, settleDelay: TimeInterval) async throws {
        for message in messages {
            try FB01MIDI.sendImmediate(message, destinationIndex: destinationIndex)
        }
        if !messages.isEmpty {
            try await sleep(seconds: settleDelay)
        }
    }

    func sendPreparedNote(
        preparationMessages: [[UInt8]],
        noteMessage: [UInt8],
        destinationIndex: Int,
        settleDelay: TimeInterval
    ) async throws {
        try await sendPreparedMessages(preparationMessages, destinationIndex: destinationIndex, settleDelay: settleDelay)
        try FB01MIDI.sendImmediate(noteMessage, destinationIndex: destinationIndex)
    }

    private func sleep(seconds: TimeInterval) async throws {
        guard seconds > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}

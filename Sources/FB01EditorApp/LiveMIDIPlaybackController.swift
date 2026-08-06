import Foundation
import FB01Editor

struct ExternalKeyboardFastPathResult: Sendable {
    enum Outcome: Sendable {
        case forwarded(status: String)
        case suppressed(status: String)
        case failed(status: String, errorMessage: String)
    }

    let outcome: Outcome
}

actor ExternalKeyboardRealtimeState {
    struct Snapshot: Sendable {
        let enabled: Bool
        let channel: UInt8
        let destinationIndex: Int
        let destinationName: String
        let suppressEcho: Bool
    }

    private var snapshot = Snapshot(
        enabled: false,
        channel: 0,
        destinationIndex: 0,
        destinationName: "MIDI destination",
        suppressEcho: false
    )

    func update(_ snapshot: Snapshot) {
        self.snapshot = snapshot
    }

    func fastForwardIfPossible(_ message: [UInt8]) async -> ExternalKeyboardFastPathResult? {
        let snapshot = self.snapshot
        guard snapshot.enabled,
              let status = message.first,
              (0x80...0xEF).contains(status),
              message.count > 2
        else {
            return nil
        }

        let event = status & 0xF0
        let isNoteOn = event == 0x90 && message[2] > 0
        let isNoteOff = event == 0x80 || (event == 0x90 && message[2] == 0)
        guard isNoteOn || isNoteOff else {
            return nil
        }

        if snapshot.suppressEcho {
            return ExternalKeyboardFastPathResult(
                outcome: .suppressed(status: "DX100/27 local keyboard direct; not echoed back.")
            )
        }

        let rewritten = [event | snapshot.channel] + message.dropFirst()
        let statusText: String
        if isNoteOn {
            statusText = "Input sent note \(message[1]) on channel \(Int(snapshot.channel) + 1)"
        } else {
            statusText = "Input forwarding to \(snapshot.destinationName)"
        }

        do {
            try await LiveMIDIPlaybackController.shared.sendImmediate(rewritten, destinationIndex: snapshot.destinationIndex)
            return ExternalKeyboardFastPathResult(outcome: .forwarded(status: statusText))
        } catch {
            return ExternalKeyboardFastPathResult(
                outcome: .failed(
                    status: "Input error",
                    errorMessage: "MIDI input failed: \(error)"
                )
            )
        }
    }
}

actor LiveMIDIPlaybackController {
    static let shared = LiveMIDIPlaybackController()

    func sendImmediate(_ message: [UInt8], destinationIndex: Int) throws {
        try FB01MIDI.sendImmediate(message, destinationIndex: destinationIndex)
    }

    func sendPreparedMessages(_ messages: [[UInt8]], destinationIndex: Int, settleDelay: TimeInterval) async throws {
        for message in messages {
            try Task.checkCancellation()
            try FB01MIDI.sendImmediate(message, destinationIndex: destinationIndex)
            await Task.yield()
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

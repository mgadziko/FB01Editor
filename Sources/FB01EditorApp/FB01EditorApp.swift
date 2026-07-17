import AppKit
import FB01Editor
import SwiftUI
import UniformTypeIdentifiers

@main
struct FB01EditorApplication: App {
    var body: some Scene {
        WindowGroup("FB01 Editor") {
            ContentView()
                .frame(minWidth: 840, minHeight: 540)
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

@MainActor
final class DocumentModel: ObservableObject {
    @Published var loadedFileName: String?
    @Published var artifact: FB01Artifact?
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    @Published var isFetchingFromDevice = false

    var hasDocument: Bool {
        artifact != nil
    }

    func openSysEx() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.sysex, .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        load(url: url)
    }

    func fetchAllBanksFromDevice() {
        guard !isFetchingFromDevice else { return }

        isFetchingFromDevice = true
        statusMessage = "Fetching FB-01 banks..."
        errorMessage = nil

        Task {
            do {
                let bytes = try await Task.detached(priority: .userInitiated) {
                    try FB01MIDI.requestAllBanks(
                        sourceIndex: 0,
                        destinationIndex: 0,
                        systemChannel: 0,
                        timeoutPerRequest: 20
                    ).flatMap { $0 }
                }.value

                artifact = try FB01Artifact(sysexBytes: bytes)
                loadedFileName = "FB-01 Live Fetch"
                statusMessage = "Fetched current configuration, Banks 1-7, and Voice RAM 1."
                errorMessage = nil
            } catch {
                errorMessage = "Fetch failed: \(error)"
                statusMessage = nil
            }

            isFetchingFromDevice = false
        }
    }

    func exportSysEx() {
        guard let artifact else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.sysex]
        panel.nameFieldStringValue = loadedFileName ?? "fb01-export.syx"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try artifact.writeSysEx(to: url)
            errorMessage = nil
        } catch {
            errorMessage = "Export failed: \(error)"
        }
    }

    private func load(url: URL) {
        do {
            artifact = try FB01Artifact.readSysEx(from: url)
            loadedFileName = url.lastPathComponent
            errorMessage = nil
        } catch {
            artifact = nil
            loadedFileName = nil
            errorMessage = "Open failed: \(error)"
        }
    }
}

private extension UTType {
    static let sysex = UTType(filenameExtension: "syx")!
}

struct ContentView: View {
    @StateObject private var document = DocumentModel()

    var body: some View {
        VStack(spacing: 0) {
            ToolbarView(document: document)

            Divider()

            Group {
                if let artifact = document.artifact {
                    ArtifactView(artifact: artifact)
                } else {
                    EmptyStateView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let errorMessage = document.errorMessage {
                Divider()
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }

            if let statusMessage = document.statusMessage {
                Divider()
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
        }
    }
}

struct ToolbarView: View {
    @ObservedObject var document: DocumentModel

    var body: some View {
        HStack(spacing: 10) {
            Button {
                document.openSysEx()
            } label: {
                Label("Open", systemImage: "folder")
            }

            Button {
                document.exportSysEx()
            } label: {
                Label("Export", systemImage: "square.and.arrow.down")
            }
            .disabled(!document.hasDocument)

            Button {
                document.fetchAllBanksFromDevice()
            } label: {
                Label(document.isFetchingFromDevice ? "Fetching" : "Fetch Banks", systemImage: "pianokeys")
            }
            .disabled(document.isFetchingFromDevice)

            Divider()
                .frame(height: 20)

            Text(document.loadedFileName ?? "No File")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Text("Read Only")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Open a SysEx File")
                .font(.title2.weight(.semibold))
            Text("Current configuration dumps display decoded FB-01 fields.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ArtifactView: View {
    var artifact: FB01Artifact
    @State private var selectedMessageIndex = 0

    var body: some View {
        if artifact.messages.count > 1 {
            VStack(alignment: .leading, spacing: 0) {
                SummaryPanel(rows: summaryRows)
                    .padding(18)

                Divider()

                MessageBrowser(
                    messages: artifact.messages,
                    selectedMessageIndex: $selectedMessageIndex
                )
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SummaryPanel(rows: summaryRows)

                    ForEach(Array(artifact.messages.enumerated()), id: \.offset) { index, message in
                        MessageView(index: index + 1, message: message)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var summaryRows: [KeyValueRow] {
        [
            KeyValueRow("Artifact", artifact.kind.displayName),
            KeyValueRow("Messages", "\(artifact.messages.count)"),
            KeyValueRow("Bytes", ((try? artifact.sysexBytes.count).map(String.init)) ?? "Unknown"),
        ]
    }
}

struct MessageBrowser: View {
    var messages: [FB01SysExMessage]
    @Binding var selectedMessageIndex: Int

    private var selectedIndex: Int {
        min(max(selectedMessageIndex, 0), max(messages.count - 1, 0))
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                    Button {
                        selectedMessageIndex = index
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(message.sourceTitle(index: index + 1))
                                .font(.body.weight(.medium))
                                .lineLimit(1)
                            Text(message.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            selectedIndex == index
                                ? Color.accentColor.opacity(0.18)
                                : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .frame(minWidth: 220, idealWidth: 220, maxWidth: 220, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            ScrollView {
                MessageView(index: selectedIndex + 1, message: messages[selectedIndex])
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct MessageView: View {
    var index: Int
    var message: FB01SysExMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Message \(index)")
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(message.displayName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            switch message {
            case let .currentConfigurationDump(systemChannel, packet):
                ConfigurationView(systemChannel: systemChannel, packet: packet)
            case let .configurationDump(systemChannel, number, packet):
                ConfigurationView(systemChannel: systemChannel, packet: packet, label: "Stored Configuration \(number)")
            case let .voiceRAMDumpData(systemChannel, byteCount, data, checksum):
                VoiceBankView(systemChannel: systemChannel, bank: 0, byteCount: byteCount, data: data, checksum: checksum, label: "Voice RAM 1")
            case let .voiceBankDumpData(systemChannel, bank, byteCount, data, checksum):
                VoiceBankView(systemChannel: systemChannel, bank: bank, byteCount: byteCount, data: data, checksum: checksum)
            default:
                SummaryPanel(rows: messageRows)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var messageRows: [KeyValueRow] {
        [
            KeyValueRow("Type", message.displayName),
            KeyValueRow("Bytes", ((try? message.bytes.count).map(String.init)) ?? "Unknown"),
        ]
    }
}

struct ConfigurationView: View {
    var systemChannel: Int
    var packet: FB01SysExPacket
    var label: String = "Current Configuration"

    var body: some View {
        Group {
            if let configuration = try? FB01ConfigurationData(bytes: packet.payload) {
                configurationBody(configuration)
            } else {
                SummaryPanel(rows: [
                    KeyValueRow("Type", label),
                    KeyValueRow("Error", "Invalid configuration payload"),
                ])
            }
        }
    }

    private func configurationBody(_ configuration: FB01ConfigurationData) -> some View {
            VStack(alignment: .leading, spacing: 14) {
                SummaryPanel(rows: [
                    KeyValueRow("Type", label),
                    KeyValueRow("Name", configuration.name),
                    KeyValueRow("System Channel", "\(systemChannel + 1)"),
                    KeyValueRow("Checksum", String(format: "0x%02X", packet.checksum)),
                    KeyValueRow("Payload Bytes", "\(packet.payload.count)"),
                    KeyValueRow("Combine", configuration.combineModeEnabled ? "On" : "Off"),
                    KeyValueRow("Key-Code Mode", configuration.keyCodeReceiveMode.displayName),
                    KeyValueRow("LFO", "Speed \(configuration.lfoSpeed), AMD \(configuration.amplitudeModulationDepth), PMD \(configuration.pitchModulationDepth), Wave \(configuration.lfoWaveform)"),
                ])

                InstrumentTable(instruments: configuration.instruments)
            }
    }
}

struct VoiceBankView: View {
    var systemChannel: Int
    var bank: Int
    var byteCount: Int
    var data: [UInt8]
    var checksum: UInt8
    var label: String = "Voice Bank"
    @State private var selectedVoiceNumber = 1

    var body: some View {
        Group {
            if let voiceBank = try? FB01VoiceBankData(bank: bank, data: data) {
                VStack(alignment: .leading, spacing: 14) {
                    SummaryPanel(rows: [
                        KeyValueRow("Type", label),
                        KeyValueRow("Bank", label == "Voice Bank" ? "\(voiceBank.bank + 1)" : label),
                        KeyValueRow("System Channel", "\(systemChannel + 1)"),
                        KeyValueRow("Byte Count", "\(byteCount)"),
                        KeyValueRow("Data Bytes", "\(data.count)"),
                        KeyValueRow("Checksum", String(format: "0x%02X", checksum)),
                    ])

                    VoiceBankBrowser(
                        systemChannel: systemChannel,
                        voices: voiceBank.voices,
                        selectedVoiceNumber: $selectedVoiceNumber
                    )
                }
            } else {
                SummaryPanel(rows: [
                    KeyValueRow("Type", label),
                    KeyValueRow("Error", "Invalid voice bank payload"),
                ])
            }
        }
    }
}

struct VoiceBankBrowser: View {
    var systemChannel: Int
    var voices: [FB01VoiceSummary]
    @Binding var selectedVoiceNumber: Int

    private var selectedVoice: FB01VoiceSummary? {
        voices.first { $0.number == selectedVoiceNumber } ?? voices.first
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Voices")
                    .font(.headline)

                VStack(spacing: 2) {
                    ForEach(voices) { voice in
                        Button {
                            selectedVoiceNumber = voice.number
                        } label: {
                            HStack(spacing: 8) {
                                Text("\(voice.number)")
                                    .frame(width: 28, alignment: .trailing)
                                    .foregroundStyle(.secondary)
                                Text(voice.name.isEmpty ? "Untitled" : voice.name)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                selectedVoiceNumber == voice.number
                                    ? Color.accentColor.opacity(0.18)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(width: 220, alignment: .topLeading)

            Divider()

            if let selectedVoice {
                VoiceDetailView(systemChannel: systemChannel, summary: selectedVoice)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }
}

struct VoiceDetailView: View {
    var systemChannel: Int
    var summary: FB01VoiceSummary
    @State private var exportError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(summary.name.isEmpty ? "Untitled" : summary.name)
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("Voice \(summary.number)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Button {
                    exportVoice()
                } label: {
                    Label("Export Voice", systemImage: "square.and.arrow.down")
                }
            }

            SummaryPanel(rows: [
                KeyValueRow("Name", summary.voice.name),
                KeyValueRow("Algorithm", "\(summary.voice.algorithm + 1)"),
                KeyValueRow("Feedback", "\(summary.voice.feedbackLevel)"),
                KeyValueRow("Transpose", "\(summary.voice.transpose)"),
                KeyValueRow("LFO", "Speed \(summary.voice.lfoSpeed), Wave \(summary.voice.lfoWaveform + 1), Sync \(summary.voice.lfoSyncEnabled ? "On" : "Off")"),
                KeyValueRow("Modulation", "AMD \(summary.voice.amplitudeModulationDepth), PMD \(summary.voice.pitchModulationDepth), AMS \(summary.voice.amplitudeModulationSensitivity), PMS \(summary.voice.pitchModulationSensitivity)"),
                KeyValueRow("Operators", enabledOperatorsText),
                KeyValueRow("Output", outputText),
                KeyValueRow("User Code", "\(summary.voice.userCode)"),
            ])

            OperatorTable(operators: summary.voice.operators)

            if let exportError {
                Text(exportError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var enabledOperatorsText: String {
        summary.voice.operatorEnabled.enumerated()
            .filter(\.element)
            .map { "\($0.offset + 1)" }
            .joined(separator: ", ")
    }

    private var outputText: String {
        "Left \(summary.voice.leftOutputEnabled ? "On" : "Off"), Right \(summary.voice.rightOutputEnabled ? "On" : "Off")"
    }

    private func exportVoice() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.sysex]
        panel.nameFieldStringValue = "voice-\(summary.number)-\(safeFileName(summary.name)).syx"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let artifact = try summary.voice.instrumentVoiceArtifact(systemChannel: systemChannel, instrument: 0)
            try artifact.writeSysEx(to: url)
            exportError = nil
        } catch {
            exportError = "Export failed: \(error)"
        }
    }

    private func safeFileName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmed.isEmpty ? "untitled" : trimmed
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return fallback
            .unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
            .reduce("") { $0 + String($1) }
    }
}

struct OperatorTable: View {
    var operators: [FB01VoiceOperatorData]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Operators")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
                GridRow {
                    header("#")
                    header("TL")
                    header("Mul")
                    header("AR")
                    header("D1R")
                    header("D2R")
                    header("SL")
                    header("RR")
                    header("Carrier")
                }

                Divider()
                    .gridCellColumns(9)

                ForEach(operators, id: \.index) { op in
                    GridRow {
                        cell("\(op.index + 1)")
                        cell("\(op.totalLevel)")
                        cell("\(op.multiple)")
                        cell("\(op.attackRate)")
                        cell("\(op.decay1Rate)")
                        cell("\(op.decay2Rate)")
                        cell("\(op.sustainLevel)")
                        cell("\(op.releaseRate)")
                        cell(op.carrier ? "Yes" : "No")
                    }
                }
            }
            .font(.system(.body, design: .monospaced))
        }
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private func cell(_ title: String) -> some View {
        Text(title)
            .lineLimit(1)
    }
}

struct InstrumentTable: View {
    var instruments: [FB01InstrumentConfiguration]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Instruments")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
                GridRow {
                    header("#")
                    header("Notes")
                    header("MIDI")
                    header("Key")
                    header("Voice")
                    header("Level")
                    header("Pan")
                    header("Mode")
                    header("PMD")
                }

                Divider()
                    .gridCellColumns(9)

                ForEach(instruments, id: \.index) { instrument in
                    GridRow {
                        cell("\(instrument.index + 1)")
                        cell("\(instrument.noteCount)")
                        cell("\(instrument.midiChannel + 1)")
                        cell("\(instrument.lowKeyLimit)-\(instrument.highKeyLimit)")
                        cell("\(instrument.voiceBank)/\(instrument.voiceNumber)")
                        cell("\(instrument.outputLevel)")
                        cell("\(instrument.pan)")
                        cell(instrument.monoPolyMode.displayName)
                        cell(instrument.pmdControllerAssignment.displayName)
                    }
                }
            }
            .font(.system(.body, design: .monospaced))
        }
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private func cell(_ title: String) -> some View {
        Text(title)
            .lineLimit(1)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SummaryPanel: View {
    var rows: [KeyValueRow]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
            ForEach(rows) { row in
                GridRow {
                    Text(row.key)
                        .foregroundStyle(.secondary)
                    Text(row.value)
                        .textSelection(.enabled)
                }
            }
        }
        .font(.body)
    }
}

struct KeyValueRow: Identifiable {
    var id: String { key }
    var key: String
    var value: String

    init(_ key: String, _ value: String) {
        self.key = key
        self.value = value
    }
}

private extension FB01ArtifactKind {
    var displayName: String {
        switch self {
        case .singleVoice: "Single Voice"
        case .voiceBank: "Voice Bank"
        case .currentConfiguration: "Current Configuration"
        case .storedConfiguration: "Stored Configuration"
        case .configurationSet: "Configuration Set"
        case .unitID: "Unit ID"
        case .rawSysEx: "Raw SysEx"
        }
    }
}

private extension FB01SysExMessage {
    func sourceTitle(index: Int) -> String {
        switch self {
        case .currentConfigurationDump:
            return "Current Configuration"
        case let .configurationDump(_, number, _):
            return "Configuration \(number)"
        case .voiceRAMDumpData:
            return "Voice RAM 1"
        case let .voiceBankDumpData(_, bank, _, _, _):
            return "Bank \(bank + 1)"
        case .instrumentVoiceDump:
            return "Single Voice"
        case .unitIDDump:
            return "Unit ID"
        default:
            return "Message \(index)"
        }
    }

    var displayName: String {
        switch self {
        case .command: "Command"
        case .instrumentVoiceDump: "Instrument Voice Dump"
        case .currentConfigurationDump: "Current Configuration Dump"
        case .configurationDump: "Stored Configuration Dump"
        case .allConfigurationsDump: "All Configurations Dump"
        case .voiceBankDump, .voiceRAMDumpData, .voiceBankDumpData: "Voice Bank Dump"
        case .unitIDDump: "Unit ID Dump"
        case .raw: "Raw SysEx"
        }
    }
}

private extension FB01KeyCodeReceiveMode {
    var displayName: String {
        switch self {
        case .all: "All"
        case .even: "Even"
        case .odd: "Odd"
        case .unknown: "Unknown"
        }
    }
}

private extension FB01MonoPolyMode {
    var displayName: String {
        switch self {
        case .poly: "Poly"
        case .mono: "Mono"
        case .unknown: "Unknown"
        }
    }
}

private extension FB01PMDControllerAssignment {
    var displayName: String {
        switch self {
        case .notAssigned: "None"
        case .afterTouch: "Aftertouch"
        case .modulationWheel: "Mod Wheel"
        case .breathController: "Breath"
        case .footController: "Foot"
        case .unknown: "Unknown"
        }
    }
}

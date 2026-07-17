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

    var body: some View {
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

    private var summaryRows: [KeyValueRow] {
        [
            KeyValueRow("Artifact", artifact.kind.displayName),
            KeyValueRow("Messages", "\(artifact.messages.count)"),
            KeyValueRow("Bytes", ((try? artifact.sysexBytes.count).map(String.init)) ?? "Unknown"),
        ]
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

    var body: some View {
        Group {
            if let voiceBank = try? FB01VoiceBankData(bank: bank, data: data) {
                VStack(alignment: .leading, spacing: 14) {
                    SummaryPanel(rows: [
                        KeyValueRow("Type", "Voice Bank"),
                        KeyValueRow("Bank", label == "Voice Bank" ? "\(voiceBank.bank)" : label),
                        KeyValueRow("System Channel", "\(systemChannel + 1)"),
                        KeyValueRow("Byte Count", "\(byteCount)"),
                        KeyValueRow("Data Bytes", "\(data.count)"),
                        KeyValueRow("Checksum", String(format: "0x%02X", checksum)),
                    ])

                    VoiceTable(voices: voiceBank.voices)
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

struct VoiceTable: View {
    var voices: [FB01VoiceSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Voices")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.fixed(48), alignment: .leading),
                GridItem(.adaptive(minimum: 112), alignment: .leading),
            ], alignment: .leading, spacing: 8) {
                ForEach(voices) { voice in
                    Text("\(voice.number)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(voice.name)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                }
            }
        }
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

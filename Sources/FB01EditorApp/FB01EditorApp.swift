import AppKit
import FB01Editor
import SwiftUI
import UniformTypeIdentifiers

@main
struct FB01EditorApplication: App {
    @StateObject private var document = DocumentModel()

    var body: some Scene {
        WindowGroup("FB01 Editor") {
            ContentView(document: document)
                .frame(minWidth: 840, minHeight: 540)
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .newItem) {
                Button("Open SysEx...") {
                    document.openSysEx()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Save SysEx...") {
                    document.saveSysEx()
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!document.hasDocument)
            }
        }
    }
}

@MainActor
final class DocumentModel: ObservableObject {
    @Published var sources: [LibrarySource] = []
    @Published var selectedSourceID: LibrarySource.ID?
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    @Published var isFetchingFromDevice = false
    @Published var midiSources: [FB01MIDIEndpoint] = []
    @Published var midiDestinations: [FB01MIDIEndpoint] = []
    @Published var selectedSourceIndex = 0
    @Published var selectedDestinationIndex = 0

    private enum DefaultsKey {
        static let sourceIndex = "FB01Editor.selectedMIDISourceIndex"
        static let sourceUniqueID = "FB01Editor.selectedMIDISourceUniqueID"
        static let destinationIndex = "FB01Editor.selectedMIDIDestinationIndex"
        static let destinationUniqueID = "FB01Editor.selectedMIDIDestinationUniqueID"
    }

    init() {
        selectedSourceIndex = UserDefaults.standard.integer(forKey: DefaultsKey.sourceIndex)
        selectedDestinationIndex = UserDefaults.standard.integer(forKey: DefaultsKey.destinationIndex)
        refreshMIDIEndpoints()
    }

    var hasDocument: Bool {
        selectedSource != nil
    }

    var selectedSource: LibrarySource? {
        guard let selectedSourceID else {
            return sources.first
        }
        return sources.first { $0.id == selectedSourceID } ?? sources.first
    }

    var selectedArtifact: FB01Artifact? {
        selectedSource?.artifact
    }

    var selectedTitle: String? {
        selectedSource?.title
    }

    var canManageSource: Bool {
        selectedSource != nil && !isFetchingFromDevice
    }

    var selectedSourceName: String {
        midiSources.first { $0.index == selectedSourceIndex }?.displayName ?? "Source \(selectedSourceIndex)"
    }

    var selectedDestinationName: String {
        midiDestinations.first { $0.index == selectedDestinationIndex }?.displayName ?? "Destination \(selectedDestinationIndex)"
    }

    func refreshMIDIEndpoints() {
        midiSources = FB01MIDI.availableSources()
        midiDestinations = FB01MIDI.availableDestinations()

        if let storedSource = storedUniqueID(for: DefaultsKey.sourceUniqueID),
           let source = midiSources.first(where: { $0.uniqueID == storedSource }) {
            selectedSourceIndex = source.index
        } else if !midiSources.contains(where: { $0.index == selectedSourceIndex }) {
            selectedSourceIndex = midiSources.first?.index ?? 0
        }

        if let storedDestination = storedUniqueID(for: DefaultsKey.destinationUniqueID),
           let destination = midiDestinations.first(where: { $0.uniqueID == storedDestination }) {
            selectedDestinationIndex = destination.index
        } else if !midiDestinations.contains(where: { $0.index == selectedDestinationIndex }) {
            selectedDestinationIndex = midiDestinations.first?.index ?? 0
        }

        persistSelectedEndpoints()
    }

    func selectSource(_ source: FB01MIDIEndpoint) {
        selectedSourceIndex = source.index
        persistSelectedEndpoints()
    }

    func selectDestination(_ destination: FB01MIDIEndpoint) {
        selectedDestinationIndex = destination.index
        persistSelectedEndpoints()
    }

    func openSysEx() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.sysex, .data]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK else {
            return
        }

        load(urls: panel.urls)
    }

    func fetchAllBanksFromDevice() {
        guard !isFetchingFromDevice else { return }
        guard let insertionMode = fetchInsertionMode() else { return }

        isFetchingFromDevice = true
        statusMessage = "Fetching FB-01 banks..."
        errorMessage = nil

        Task {
            let sourceIndex = selectedSourceIndex
            let destinationIndex = selectedDestinationIndex
            let sourceName = selectedSourceName
            let destinationName = selectedDestinationName

            do {
                let bytes = try await Task.detached(priority: .userInitiated) {
                    try FB01MIDI.requestAllBanks(
                        sourceIndex: sourceIndex,
                        destinationIndex: destinationIndex,
                        systemChannel: 0,
                        timeoutPerRequest: 20
                    ).flatMap { $0 }
                }.value

                let artifact = try FB01Artifact(sysexBytes: bytes)
                let fetchedSources = artifact.messages.enumerated().map { index, message in
                    LibrarySource(
                        title: message.sourceTitle(index: index + 1),
                        subtitle: "FB-01 Live Fetch",
                        artifact: FB01Artifact(message: message)
                    )
                }
                applyFetchedSources(fetchedSources, insertionMode: insertionMode)
                statusMessage = "Fetched \(fetchedSources.count) sources from \(sourceName) -> \(destinationName)."
                errorMessage = nil
            } catch {
                errorMessage = "Fetch failed: \(error)"
                statusMessage = nil
            }

            isFetchingFromDevice = false
        }
    }

    func saveSysEx() {
        guard let selectedSource else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.sysex]
        panel.nameFieldStringValue = "\(safeFileName(selectedSource.title)).syx"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try selectedSource.artifact.writeSysEx(to: url)
            errorMessage = nil
        } catch {
            errorMessage = "Save failed: \(error)"
        }
    }

    func selectSource(_ source: LibrarySource) {
        selectedSourceID = source.id
    }

    func removeSelectedSource() {
        guard let selectedSource,
              let index = sources.firstIndex(where: { $0.id == selectedSource.id }) else {
            return
        }

        sources.remove(at: index)

        if sources.isEmpty {
            selectedSourceID = nil
        } else {
            selectedSourceID = sources[min(index, sources.count - 1)].id
        }

        statusMessage = "Removed \(selectedSource.title)."
        errorMessage = nil
    }

    func renameSelectedSource() {
        guard let selectedSource,
              let index = sources.firstIndex(where: { $0.id == selectedSource.id }) else {
            return
        }

        let alert = NSAlert()
        alert.messageText = "Rename Source"
        alert.informativeText = "Choose a local display name for this source."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(string: selectedSource.title)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let title = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return
        }

        sources[index].title = title
        selectedSourceID = sources[index].id
        statusMessage = "Renamed source to \(title)."
        errorMessage = nil
    }

    func clearSources() {
        guard !sources.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "Clear Source Library?"
        alert.informativeText = "This removes the sources from the app window. It does not delete files from disk or change the FB-01."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let count = sources.count
        sources.removeAll()
        selectedSourceID = nil
        statusMessage = "Cleared \(count) source\(count == 1 ? "" : "s")."
        errorMessage = nil
    }

    private func load(urls: [URL]) {
        var loadedSources: [LibrarySource] = []
        var failures: [String] = []

        for url in urls {
            do {
                let artifact = try FB01Artifact.readSysEx(from: url)
                loadedSources.append(contentsOf: LibrarySource.sources(from: artifact, fileName: url.lastPathComponent))
            } catch {
                failures.append("\(url.lastPathComponent): \(error)")
            }
        }

        if !loadedSources.isEmpty {
            sources.append(contentsOf: loadedSources)
            selectedSourceID = loadedSources.first?.id
            statusMessage = "Opened \(loadedSources.count) source\(loadedSources.count == 1 ? "" : "s")."
        }

        if failures.isEmpty {
            errorMessage = nil
        } else {
            errorMessage = "Open failed for \(failures.joined(separator: ", "))"
        }
    }

    private func persistSelectedEndpoints() {
        UserDefaults.standard.set(selectedSourceIndex, forKey: DefaultsKey.sourceIndex)
        UserDefaults.standard.set(selectedDestinationIndex, forKey: DefaultsKey.destinationIndex)

        if let source = midiSources.first(where: { $0.index == selectedSourceIndex }),
           let uniqueID = source.uniqueID {
            UserDefaults.standard.set(Int(uniqueID), forKey: DefaultsKey.sourceUniqueID)
        } else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.sourceUniqueID)
        }

        if let destination = midiDestinations.first(where: { $0.index == selectedDestinationIndex }),
           let uniqueID = destination.uniqueID {
            UserDefaults.standard.set(Int(uniqueID), forKey: DefaultsKey.destinationUniqueID)
        } else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.destinationUniqueID)
        }
    }

    private func storedUniqueID(for key: String) -> Int32? {
        guard UserDefaults.standard.object(forKey: key) != nil else {
            return nil
        }
        return Int32(UserDefaults.standard.integer(forKey: key))
    }

    private func safeFileName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitized = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
            .reduce("") { $0 + String($1) }
        return sanitized.isEmpty ? "fb01-export" : sanitized
    }

    private func applyFetchedSources(_ fetchedSources: [LibrarySource], insertionMode: SourceInsertionMode) {
        switch insertionMode {
        case .replace:
            sources = fetchedSources
        case .append:
            sources.append(contentsOf: fetchedSources)
        }
        selectedSourceID = fetchedSources.first?.id ?? sources.first?.id
    }

    private func fetchInsertionMode() -> SourceInsertionMode? {
        guard !sources.isEmpty else {
            return .replace
        }

        let alert = NSAlert()
        alert.messageText = "Fetch FB-01 Banks"
        alert.informativeText = "The source library already contains \(sources.count) source\(sources.count == 1 ? "" : "s"). Replace them or append the fetched banks?"
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Append")
        alert.addButton(withTitle: "Cancel")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .replace
        case .alertSecondButtonReturn:
            return .append
        default:
            return nil
        }
    }
}

enum SourceInsertionMode {
    case replace
    case append
}

struct LibrarySource: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var subtitle: String
    var artifact: FB01Artifact

    static func sources(from artifact: FB01Artifact, fileName: String) -> [LibrarySource] {
        guard artifact.messages.count > 1 else {
            return [
                LibrarySource(
                    title: artifact.messages.first?.sourceTitle(index: 1) ?? fileName,
                    subtitle: fileName,
                    artifact: artifact
                ),
            ]
        }

        return artifact.messages.enumerated().map { index, message in
            LibrarySource(
                title: message.sourceTitle(index: index + 1),
                subtitle: fileName,
                artifact: FB01Artifact(message: message)
            )
        }
    }
}

private extension UTType {
    static let sysex = UTType(filenameExtension: "syx")!
}

struct ContentView: View {
    @ObservedObject var document: DocumentModel

    var body: some View {
        VStack(spacing: 0) {
            ToolbarView(document: document)

            Divider()

            Group {
                if !document.sources.isEmpty {
                    LibraryView(document: document)
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
                document.fetchAllBanksFromDevice()
            } label: {
                Label(document.isFetchingFromDevice ? "Fetching" : "Fetch Banks", systemImage: "pianokeys")
            }
            .disabled(document.isFetchingFromDevice)

            Menu {
                ForEach(document.midiSources, id: \.index) { source in
                    Button {
                        document.selectSource(source)
                    } label: {
                        endpointLabel(source, selected: source.index == document.selectedSourceIndex)
                    }
                }
            } label: {
                Label(document.selectedSourceName, systemImage: "arrow.down.circle")
            }
            .disabled(document.midiSources.isEmpty || document.isFetchingFromDevice)

            Menu {
                ForEach(document.midiDestinations, id: \.index) { destination in
                    Button {
                        document.selectDestination(destination)
                    } label: {
                        endpointLabel(destination, selected: destination.index == document.selectedDestinationIndex)
                    }
                }
            } label: {
                Label(document.selectedDestinationName, systemImage: "arrow.up.circle")
            }
            .disabled(document.midiDestinations.isEmpty || document.isFetchingFromDevice)

            Button {
                document.refreshMIDIEndpoints()
            } label: {
                Label("Refresh MIDI", systemImage: "arrow.clockwise")
            }
            .disabled(document.isFetchingFromDevice)

            Divider()
                .frame(height: 20)

            Text(document.selectedTitle ?? "No Source")
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

    private func endpointLabel(_ endpoint: FB01MIDIEndpoint, selected: Bool) -> some View {
        let unique = endpoint.uniqueID.map { " id=\($0)" } ?? ""
        return Label("[\(endpoint.index)] \(endpoint.displayName)\(unique)", systemImage: selected ? "checkmark" : "circle")
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

struct LibraryView: View {
    @ObservedObject var document: DocumentModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("Sources")
                        .font(.headline)

                    Spacer()

                    Button {
                        document.renameSelectedSource()
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .help("Rename selected source")
                    .disabled(!document.canManageSource)

                    Button {
                        document.removeSelectedSource()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .help("Remove selected source")
                    .disabled(!document.canManageSource)

                    Button {
                        document.clearSources()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Clear source library")
                    .disabled(document.sources.isEmpty || document.isFetchingFromDevice)
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 10)
                .padding(.top, 6)

                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(document.sources) { source in
                            Button {
                                document.selectSource(source)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(source.title)
                                        .font(.body.weight(.medium))
                                        .lineLimit(1)
                                    Text(source.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(
                                    document.selectedSource?.id == source.id
                                        ? Color.accentColor.opacity(0.18)
                                        : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(12)
            .frame(minWidth: 220, idealWidth: 220, maxWidth: 220, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            if let artifact = document.selectedArtifact {
                ArtifactView(artifact: artifact)
            }
        }
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
            case let .instrumentVoiceDump(systemChannel, instrument, packet):
                SingleVoiceView(systemChannel: systemChannel, instrument: instrument, packet: packet)
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

struct SingleVoiceView: View {
    var systemChannel: Int
    var instrument: Int
    var packet: FB01SysExPacket

    var body: some View {
        Group {
            if let voice = try? FB01VoiceData(bytes: FB01.nibbleDecode(packet.payload)) {
                VStack(alignment: .leading, spacing: 14) {
                    SummaryPanel(rows: [
                        KeyValueRow("Type", "Single Voice"),
                        KeyValueRow("Name", voice.name),
                        KeyValueRow("System Channel", "\(systemChannel + 1)"),
                        KeyValueRow("Instrument", "\(instrument + 1)"),
                        KeyValueRow("Checksum", String(format: "0x%02X", packet.checksum)),
                    ])

                    VoiceDetailView(
                        systemChannel: systemChannel,
                        summary: FB01VoiceSummary(number: instrument + 1, voice: voice, encodedRecordBytes: [])
                    )
                }
            } else {
                SummaryPanel(rows: [
                    KeyValueRow("Type", "Single Voice"),
                    KeyValueRow("Error", "Invalid voice payload"),
                ])
            }
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
    @State private var editableVoice: FB01VoiceData
    @State private var nameText: String
    @State private var editError: String?
    @State private var exportError: String?

    init(systemChannel: Int, summary: FB01VoiceSummary) {
        self.systemChannel = systemChannel
        self.summary = summary
        _editableVoice = State(initialValue: summary.voice)
        _nameText = State(initialValue: summary.voice.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(editableVoice.name.isEmpty ? "Untitled" : editableVoice.name)
                    .font(.title3.weight(.semibold))
                Spacer()
                Text("Voice \(summary.number)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                if editableVoice != summary.voice {
                    Button {
                        resetVoice()
                    } label: {
                        Label("Reset", systemImage: "arrow.uturn.backward")
                    }
                }
                Button {
                    exportVoice()
                } label: {
                    Label("Export Voice", systemImage: "square.and.arrow.down")
                }
            }

            SummaryPanel(rows: [
                KeyValueRow("Name", editableVoice.name),
                KeyValueRow("Algorithm", "\(editableVoice.algorithm + 1)"),
                KeyValueRow("Feedback", "\(editableVoice.feedbackLevel)"),
                KeyValueRow("Transpose", "\(editableVoice.transpose)"),
                KeyValueRow("LFO", "Speed \(editableVoice.lfoSpeed), Wave \(editableVoice.lfoWaveform + 1), Sync \(editableVoice.lfoSyncEnabled ? "On" : "Off")"),
                KeyValueRow("Modulation", "AMD \(editableVoice.amplitudeModulationDepth), PMD \(editableVoice.pitchModulationDepth), AMS \(editableVoice.amplitudeModulationSensitivity), PMS \(editableVoice.pitchModulationSensitivity)"),
                KeyValueRow("Operators", enabledOperatorsText),
                KeyValueRow("Output", outputText),
                KeyValueRow("User Code", "\(editableVoice.userCode)"),
            ])

            VoiceEditorControls(
                name: Binding(
                    get: { nameText },
                    set: { setName($0) }
                ),
                algorithm: Binding(
                    get: { editableVoice.algorithm + 1 },
                    set: { setAlgorithm($0 - 1) }
                ),
                feedback: Binding(
                    get: { editableVoice.feedbackLevel },
                    set: { setFeedback($0) }
                ),
                lfoSpeed: Binding(
                    get: { editableVoice.lfoSpeed },
                    set: { setLFOSpeed($0) }
                )
            )

            OperatorTable(operators: editableVoice.operators)

            if let editError {
                Text(editError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let exportError {
                Text(exportError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onChange(of: summary.voice.bytes) { _, _ in
            resetVoice()
        }
    }

    private var enabledOperatorsText: String {
        editableVoice.operatorEnabled.enumerated()
            .filter(\.element)
            .map { "\($0.offset + 1)" }
            .joined(separator: ", ")
    }

    private var outputText: String {
        "Left \(editableVoice.leftOutputEnabled ? "On" : "Off"), Right \(editableVoice.rightOutputEnabled ? "On" : "Off")"
    }

    private func resetVoice() {
        editableVoice = summary.voice
        nameText = summary.voice.name
        editError = nil
        exportError = nil
    }

    private func setName(_ value: String) {
        let limited = String(value.prefix(FB01VoiceData.nameLength))
        nameText = limited
        updateVoice { try $0.settingName(limited) }
    }

    private func setAlgorithm(_ value: Int) {
        updateVoice { try $0.settingAlgorithm(value) }
    }

    private func setFeedback(_ value: Int) {
        updateVoice { try $0.settingFeedbackLevel(value) }
    }

    private func setLFOSpeed(_ value: Int) {
        updateVoice { try $0.settingLFOSpeed(value) }
    }

    private func updateVoice(_ edit: (FB01VoiceData) throws -> FB01VoiceData) {
        do {
            editableVoice = try edit(editableVoice)
            editError = nil
            exportError = nil
        } catch {
            editError = "Edit failed: \(error)"
        }
    }

    private func exportVoice() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.sysex]
        panel.nameFieldStringValue = "voice-\(summary.number)-\(safeFileName(editableVoice.name)).syx"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let artifact = try editableVoice.instrumentVoiceArtifact(systemChannel: systemChannel, instrument: 0)
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

struct VoiceEditorControls: View {
    @Binding var name: String
    @Binding var algorithm: Int
    @Binding var feedback: Int
    @Binding var lfoSpeed: Int

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
            GridRow {
                label("Name")
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
            }

            GridRow {
                label("Algorithm")
                Stepper(value: $algorithm, in: 1...8) {
                    Text("\(algorithm)")
                        .monospacedDigit()
                }
            }

            GridRow {
                label("Feedback")
                Stepper(value: $feedback, in: 0...7) {
                    Text("\(feedback)")
                        .monospacedDigit()
                }
            }

            GridRow {
                label("LFO Speed")
                Stepper(value: $lfoSpeed, in: 0...255) {
                    Text("\(lfoSpeed)")
                        .monospacedDigit()
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
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
        case let .instrumentVoiceDump(_, instrument, packet):
            if let voice = try? FB01VoiceData(bytes: FB01.nibbleDecode(packet.payload)),
               !voice.name.isEmpty {
                return voice.name
            }
            return "Single Voice \(instrument + 1)"
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

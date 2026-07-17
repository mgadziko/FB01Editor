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

                Button("Save Configuration Set...") {
                    document.saveConfigurationSet()
                }
                .disabled(!document.canSaveConfigurationSet)
            }

            CommandMenu("Device") {
                Button("Send Selected Configuration to Current Edit Buffer...") {
                    document.sendSelectedConfigurationToCurrentEditBuffer()
                }
                .disabled(!document.canSendSelectedConfiguration)

                Button("Store Selected Configuration to Slot...") {
                    document.storeSelectedConfigurationToDeviceSlot()
                }
                .disabled(!document.canStoreSelectedConfiguration)
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
    @Published var isFetchingConfigurations = false
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

    var canSaveConfigurationSet: Bool {
        sources.contains { $0.storedConfigurationNumber != nil }
    }

    var canSendSelectedConfiguration: Bool {
        selectedSource?.editableConfigurationPayload != nil && !isBusy
    }

    var canStoreSelectedConfiguration: Bool {
        canSendSelectedConfiguration
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

    var editingStatusText: String {
        sources.contains { $0.isEdited } ? "Local Edits" : "Local Edit Only"
    }

    var canManageSource: Bool {
        selectedSource != nil && !isBusy
    }

    var isBusy: Bool {
        isFetchingFromDevice || isFetchingConfigurations
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
        guard !isBusy else { return }
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

    func fetchStoredConfigurationsFromDevice() {
        guard !isBusy else { return }
        guard let insertionMode = fetchInsertionMode(title: "Fetch FB-01 Configurations", noun: "configurations") else { return }

        isFetchingConfigurations = true
        statusMessage = "Fetching FB-01 configurations..."
        errorMessage = nil

        Task {
            let sourceIndex = selectedSourceIndex
            let destinationIndex = selectedDestinationIndex
            let sourceName = selectedSourceName
            let destinationName = selectedDestinationName

            do {
                let bytes = try await Task.detached(priority: .userInitiated) {
                    try FB01MIDI.requestStoredConfigurations(
                        sourceIndex: sourceIndex,
                        destinationIndex: destinationIndex,
                        systemChannel: 0,
                        timeoutPerRequest: 15
                    ).flatMap { $0 }
                }.value

                let artifact = try FB01Artifact(sysexBytes: bytes)
                let fetchedSources = artifact.messages.enumerated().map { index, message in
                    LibrarySource(
                        title: message.sourceTitle(index: index + 1),
                        subtitle: message.configurationSubtitle ?? "FB-01 Configuration Fetch",
                        artifact: FB01Artifact(message: message)
                    )
                }
                applyFetchedSources(fetchedSources, insertionMode: insertionMode)
                statusMessage = "Fetched \(fetchedSources.count) configurations from \(sourceName) -> \(destinationName)."
                errorMessage = nil
            } catch {
                errorMessage = "Configuration fetch failed: \(error)"
                statusMessage = nil
            }

            isFetchingConfigurations = false
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
            try selectedSource.artifactForSaving().writeSysEx(to: url)
            errorMessage = nil
        } catch {
            errorMessage = "Save failed: \(error)"
        }
    }

    func saveConfigurationSet() {
        let configurationSources = sources
            .filter { $0.storedConfigurationNumber != nil }
            .sorted { ($0.storedConfigurationNumber ?? 0) < ($1.storedConfigurationNumber ?? 0) }

        guard !configurationSources.isEmpty else {
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.sysex]
        panel.nameFieldStringValue = configurationSources.count == 20
            ? "fb01-configurations-1-20.syx"
            : "fb01-configurations.syx"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let messages = try configurationSources.flatMap { source in
                try source.artifactForSaving().messages
            }
            let artifact = FB01Artifact(kind: .configurationSet, messages: messages)
            try artifact.writeSysEx(to: url)
            statusMessage = "Saved \(configurationSources.count) configuration\(configurationSources.count == 1 ? "" : "s")."
            errorMessage = nil
        } catch {
            errorMessage = "Save configuration set failed: \(error)"
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

    func voice(sourceID: LibrarySource.ID, number: Int, fallback: FB01VoiceData) -> FB01VoiceData {
        sources.first { $0.id == sourceID }?.editedVoices[number] ?? fallback
    }

    func updateVoice(sourceID: LibrarySource.ID, number: Int, voice: FB01VoiceData) {
        guard let index = sources.firstIndex(where: { $0.id == sourceID }) else {
            return
        }

        sources[index].editedVoices[number] = voice
        if sources[index].isSingleVoiceSource {
            sources[index].title = voice.name.isEmpty ? "Single Voice \(number)" : voice.name
        }
        selectedSourceID = sources[index].id
        statusMessage = "Edited \(sources[index].title) locally."
        errorMessage = nil
    }

    func resetVoice(sourceID: LibrarySource.ID, number: Int) {
        guard let index = sources.firstIndex(where: { $0.id == sourceID }) else {
            return
        }

        sources[index].editedVoices.removeValue(forKey: number)
        if sources[index].isSingleVoiceSource {
            sources[index].title = sources[index].artifact.messages.first?.sourceTitle(index: 1) ?? sources[index].title
        }
        selectedSourceID = sources[index].id
        statusMessage = "Reset local edit."
        errorMessage = nil
    }

    func configuration(sourceID: LibrarySource.ID, fallback: FB01ConfigurationData) -> FB01ConfigurationData {
        sources.first { $0.id == sourceID }?.editedConfiguration ?? fallback
    }

    func updateConfiguration(sourceID: LibrarySource.ID, configuration: FB01ConfigurationData) {
        guard let index = sources.firstIndex(where: { $0.id == sourceID }),
              !sources[index].isReadOnlyStoredConfiguration else {
            return
        }

        sources[index].editedConfiguration = configuration
        if sources[index].isConfigurationSource, !configuration.name.isEmpty {
            sources[index].title = sources[index].configurationDisplayTitle(withName: configuration.name)
        }
        selectedSourceID = sources[index].id
        statusMessage = "Edited \(sources[index].title) locally."
        errorMessage = nil
    }

    func resetConfiguration(sourceID: LibrarySource.ID) {
        guard let index = sources.firstIndex(where: { $0.id == sourceID }) else {
            return
        }

        sources[index].editedConfiguration = nil
        sources[index].title = sources[index].artifact.messages.first?.sourceTitle(index: 1) ?? sources[index].title
        selectedSourceID = sources[index].id
        statusMessage = "Reset local configuration edit."
        errorMessage = nil
    }

    func sendSelectedConfigurationToCurrentEditBuffer() {
        guard let selectedSource,
              let payload = selectedSource.editableConfigurationPayload else {
            return
        }

        let alert = NSAlert()
        alert.messageText = "Send Configuration to FB-01?"
        alert.informativeText = "This sends the selected configuration to the FB-01 current edit buffer through \(selectedDestinationName). It does not store it in a numbered slot."
        alert.addButton(withTitle: "Send")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        sendConfigurationPayload(
            payload,
            systemChannel: selectedSource.configurationSystemChannel ?? 0,
            statusPrefix: "Sent configuration to current edit buffer"
        )
    }

    func storeSelectedConfigurationToDeviceSlot() {
        guard let selectedSource,
              let payload = selectedSource.editableConfigurationPayload else {
            return
        }

        let alert = NSAlert()
        alert.messageText = "Store Configuration to FB-01 Slot"
        alert.informativeText = "Choose a writable configuration slot. The app will send the selected configuration to the current edit buffer, then store it to that slot."
        alert.addButton(withTitle: "Store")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 220, height: 26), pullsDown: false)
        for number in 1...16 {
            popup.addItem(withTitle: "Configuration \(number)")
        }
        if let storedNumber = selectedSource.storedConfigurationNumber, storedNumber < 16 {
            popup.selectItem(at: storedNumber)
        }
        alert.accessoryView = popup

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let slot = popup.indexOfSelectedItem
        do {
            let currentMessage = FB01SysExMessage.currentConfigurationDump(
                systemChannel: selectedSource.configurationSystemChannel ?? 0,
                packet: try FB01SysExPacket(payload: payload.bytes)
            )
            let storeCommand = FB01SysExMessage.command(.storeCurrentConfiguration(
                systemChannel: selectedSource.configurationSystemChannel ?? 0,
                number: slot
            ))
            let messages = try [currentMessage.bytes, storeCommand.bytes]
            sendMIDI(messages, statusMessage: "Stored configuration to slot \(slot + 1) on \(selectedDestinationName).")
        } catch {
            errorMessage = "Store configuration failed: \(error)"
            statusMessage = nil
        }
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

    private func fetchInsertionMode(title: String = "Fetch FB-01 Banks", noun: String = "banks") -> SourceInsertionMode? {
        guard !sources.isEmpty else {
            return .replace
        }

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "The source library already contains \(sources.count) source\(sources.count == 1 ? "" : "s"). Replace Library removes those sources before fetching. Add to Library keeps them and adds the fetched \(noun) after them."
        alert.addButton(withTitle: "Replace Library")
        alert.addButton(withTitle: "Add to Library")
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

    private func sendConfigurationPayload(_ payload: FB01ConfigurationData, systemChannel: Int, statusPrefix: String) {
        do {
            let message = FB01SysExMessage.currentConfigurationDump(
                systemChannel: systemChannel,
                packet: try FB01SysExPacket(payload: payload.bytes)
            )
            sendMIDI([try message.bytes], statusMessage: "\(statusPrefix) on \(selectedDestinationName).")
        } catch {
            errorMessage = "Send configuration failed: \(error)"
            statusMessage = nil
        }
    }

    private func sendMIDI(_ messages: [[UInt8]], statusMessage successMessage: String) {
        guard !isBusy else { return }

        let destinationIndex = selectedDestinationIndex
        isFetchingFromDevice = true
        statusMessage = "Sending MIDI..."
        errorMessage = nil

        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try FB01MIDI.sendSysEx(messages, destinationIndex: destinationIndex)
                }.value
                statusMessage = successMessage
                errorMessage = nil
            } catch {
                errorMessage = "MIDI send failed: \(error)"
                statusMessage = nil
            }

            isFetchingFromDevice = false
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
    var editedVoices: [Int: FB01VoiceData] = [:]
    var editedConfiguration: FB01ConfigurationData?

    var isEdited: Bool {
        !editedVoices.isEmpty || editedConfiguration != nil
    }

    var isSingleVoiceSource: Bool {
        guard artifact.messages.count == 1,
              case .instrumentVoiceDump = artifact.messages[0] else {
            return false
        }
        return true
    }

    var storedConfigurationNumber: Int? {
        guard artifact.messages.count == 1,
              case let .configurationDump(_, number, _) = artifact.messages[0] else {
            return nil
        }
        return number
    }

    var isConfigurationSource: Bool {
        guard artifact.messages.count == 1 else {
            return false
        }

        switch artifact.messages[0] {
        case .currentConfigurationDump, .configurationDump:
            return true
        default:
            return false
        }
    }

    var isReadOnlyStoredConfiguration: Bool {
        guard let storedConfigurationNumber else {
            return false
        }
        return storedConfigurationNumber >= 16
    }

    var editableConfigurationPayload: FB01ConfigurationData? {
        if let editedConfiguration {
            return editedConfiguration
        }

        guard artifact.messages.count == 1 else {
            return nil
        }

        switch artifact.messages[0] {
        case let .currentConfigurationDump(_, packet),
             let .configurationDump(_, _, packet):
            return try? FB01ConfigurationData(bytes: packet.payload)
        default:
            return nil
        }
    }

    var configurationSystemChannel: Int? {
        guard artifact.messages.count == 1 else {
            return nil
        }

        switch artifact.messages[0] {
        case let .currentConfigurationDump(systemChannel, _),
             let .configurationDump(systemChannel, _, _):
            return systemChannel
        default:
            return nil
        }
    }

    func configurationDisplayTitle(withName name: String) -> String {
        if let storedConfigurationNumber {
            return "Configuration \(storedConfigurationNumber + 1): \(name)"
        }
        return name.isEmpty ? "Current Configuration" : name
    }

    func artifactForSaving() throws -> FB01Artifact {
        guard artifact.messages.count == 1, isEdited else {
            return artifact
        }

        switch artifact.messages[0] {
        case let .currentConfigurationDump(systemChannel, _):
            guard let editedConfiguration else {
                return artifact
            }
            return FB01Artifact(message: .currentConfigurationDump(
                systemChannel: systemChannel,
                packet: try FB01SysExPacket(payload: editedConfiguration.bytes)
            ))

        case let .configurationDump(systemChannel, number, _):
            guard let editedConfiguration else {
                return artifact
            }
            return FB01Artifact(message: .configurationDump(
                systemChannel: systemChannel,
                number: number,
                packet: try FB01SysExPacket(payload: editedConfiguration.bytes)
            ))

        case let .instrumentVoiceDump(systemChannel, instrument, _):
            guard let editedVoice = editedVoices[instrument + 1] else {
                return artifact
            }
            return try editedVoice.instrumentVoiceArtifact(systemChannel: systemChannel, instrument: instrument)

        case let .voiceBankDumpData(systemChannel, bank, byteCount, data, _):
            let voiceBank = try FB01VoiceBankData(bank: bank, data: data)
            let editedBank = try voiceBank.replacingVoices(editedVoices)
            return FB01Artifact(message: .voiceBankDumpData(
                systemChannel: systemChannel,
                bank: bank,
                byteCount: byteCount,
                data: editedBank.data,
                checksum: FB01.checksum(for: editedBank.data)
            ))

        case let .voiceRAMDumpData(systemChannel, byteCount, data, _):
            let voiceBank = try FB01VoiceBankData(bank: 0, data: data)
            let editedBank = try voiceBank.replacingVoices(editedVoices)
            return FB01Artifact(message: .voiceRAMDumpData(
                systemChannel: systemChannel,
                byteCount: byteCount,
                data: editedBank.data,
                checksum: FB01.checksum(for: editedBank.data)
            ))

        default:
            return artifact
        }
    }

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
            .disabled(document.isBusy)

            Button {
                document.fetchStoredConfigurationsFromDevice()
            } label: {
                Label(document.isFetchingConfigurations ? "Fetching" : "Fetch Configs", systemImage: "list.bullet.rectangle")
            }
            .disabled(document.isBusy)

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
            .disabled(document.midiSources.isEmpty || document.isBusy)

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
            .disabled(document.midiDestinations.isEmpty || document.isBusy)

            Button {
                document.refreshMIDIEndpoints()
            } label: {
                Label("Refresh MIDI", systemImage: "arrow.clockwise")
            }
            .disabled(document.isBusy)

            Divider()
                .frame(height: 20)

            Text(document.selectedTitle ?? "No Source")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Text(document.editingStatusText)
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
                    .disabled(document.sources.isEmpty || document.isBusy)
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
                                    if source.isEdited {
                                        Text("Edited")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.orange)
                                            .lineLimit(1)
                                    }
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

            if let source = document.selectedSource {
                ArtifactView(document: document, source: source)
            }
        }
    }
}

struct ArtifactView: View {
    @ObservedObject var document: DocumentModel
    var source: LibrarySource
    @State private var selectedMessageIndex = 0

    private var artifact: FB01Artifact {
        source.artifact
    }

    var body: some View {
        if artifact.messages.count > 1 {
            VStack(alignment: .leading, spacing: 0) {
                SummaryPanel(rows: summaryRows)
                    .padding(18)

                Divider()

                MessageBrowser(
                    document: document,
                    sourceID: source.id,
                    messages: artifact.messages,
                    selectedMessageIndex: $selectedMessageIndex
                )
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SummaryPanel(rows: summaryRows)

                    ForEach(Array(artifact.messages.enumerated()), id: \.offset) { index, message in
                        MessageView(document: document, sourceID: source.id, index: index + 1, message: message)
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
    @ObservedObject var document: DocumentModel
    var sourceID: LibrarySource.ID
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
                MessageView(document: document, sourceID: sourceID, index: selectedIndex + 1, message: messages[selectedIndex])
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct MessageView: View {
    @ObservedObject var document: DocumentModel
    var sourceID: LibrarySource.ID
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
                SingleVoiceView(document: document, sourceID: sourceID, systemChannel: systemChannel, instrument: instrument, packet: packet)
            case let .currentConfigurationDump(systemChannel, packet):
                ConfigurationView(document: document, sourceID: sourceID, systemChannel: systemChannel, packet: packet)
            case let .configurationDump(systemChannel, number, packet):
                ConfigurationView(document: document, sourceID: sourceID, systemChannel: systemChannel, packet: packet, number: number, label: "Stored Configuration \(number + 1)")
            case let .voiceRAMDumpData(systemChannel, byteCount, data, checksum):
                VoiceBankView(document: document, sourceID: sourceID, systemChannel: systemChannel, bank: 0, byteCount: byteCount, data: data, checksum: checksum, label: "Voice RAM 1")
            case let .voiceBankDumpData(systemChannel, bank, byteCount, data, checksum):
                VoiceBankView(document: document, sourceID: sourceID, systemChannel: systemChannel, bank: bank, byteCount: byteCount, data: data, checksum: checksum)
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
    @ObservedObject var document: DocumentModel
    var sourceID: LibrarySource.ID
    var systemChannel: Int
    var packet: FB01SysExPacket
    var number: Int?
    var label: String = "Current Configuration"

    private var isReadOnly: Bool {
        (number ?? -1) >= 16
    }

    var body: some View {
        Group {
            if let configuration = try? FB01ConfigurationData(bytes: packet.payload) {
                ConfigurationDetailView(
                    document: document,
                    sourceID: sourceID,
                    systemChannel: systemChannel,
                    packet: packet,
                    originalConfiguration: configuration,
                    label: label,
                    isReadOnly: isReadOnly
                )
            } else {
                SummaryPanel(rows: [
                    KeyValueRow("Type", label),
                    KeyValueRow("Error", "Invalid configuration payload"),
                ])
            }
        }
    }
}

struct ConfigurationDetailView: View {
    @ObservedObject var document: DocumentModel
    var sourceID: LibrarySource.ID
    var systemChannel: Int
    var packet: FB01SysExPacket
    var originalConfiguration: FB01ConfigurationData
    var label: String
    var isReadOnly: Bool
    @State private var nameText: String
    @State private var editError: String?

    init(
        document: DocumentModel,
        sourceID: LibrarySource.ID,
        systemChannel: Int,
        packet: FB01SysExPacket,
        originalConfiguration: FB01ConfigurationData,
        label: String,
        isReadOnly: Bool
    ) {
        self.document = document
        self.sourceID = sourceID
        self.systemChannel = systemChannel
        self.packet = packet
        self.originalConfiguration = originalConfiguration
        self.label = label
        self.isReadOnly = isReadOnly
        _nameText = State(initialValue: document.configuration(sourceID: sourceID, fallback: originalConfiguration).name)
    }

    private var editableConfiguration: FB01ConfigurationData {
        document.configuration(sourceID: sourceID, fallback: originalConfiguration)
    }

    private var isEdited: Bool {
        editableConfiguration != originalConfiguration
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(editableConfiguration.name.isEmpty ? label : editableConfiguration.name)
                    .font(.title3.weight(.semibold))
                Spacer()
                Text(isReadOnly ? "Read Only" : "Local Edit Only")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                if isEdited && !isReadOnly {
                    Button {
                        resetConfiguration()
                    } label: {
                        Label("Reset", systemImage: "arrow.uturn.backward")
                    }
                }
            }

            SummaryPanel(rows: [
                KeyValueRow("Type", label),
                KeyValueRow("Name", editableConfiguration.name),
                KeyValueRow("System Channel", "\(systemChannel + 1)"),
                KeyValueRow("Checksum", String(format: "0x%02X", (try? FB01SysExPacket(payload: editableConfiguration.bytes).checksum) ?? packet.checksum)),
                KeyValueRow("Payload Bytes", "\(packet.payload.count)"),
                KeyValueRow("Combine", editableConfiguration.combineModeEnabled ? "On" : "Off"),
                KeyValueRow("Key-Code Mode", editableConfiguration.keyCodeReceiveMode.displayName),
                KeyValueRow("LFO", "Speed \(editableConfiguration.lfoSpeed), AMD \(editableConfiguration.amplitudeModulationDepth), PMD \(editableConfiguration.pitchModulationDepth), Wave \(editableConfiguration.lfoWaveform + 1)"),
            ])

            if isReadOnly {
                InstrumentTable(instruments: editableConfiguration.instruments)
            } else {
                ConfigurationEditorControls(
                    name: Binding(get: { nameText }, set: { setName($0) }),
                    combineModeEnabled: Binding(get: { editableConfiguration.combineModeEnabled }, set: { setCombineMode($0) }),
                    keyCodeReceiveMode: Binding(get: { editableConfiguration.keyCodeReceiveMode }, set: { setKeyCodeReceiveMode($0) }),
                    lfoSpeed: Binding(get: { editableConfiguration.lfoSpeed }, set: { setLFOSpeed($0) }),
                    amplitudeModulationDepth: Binding(get: { editableConfiguration.amplitudeModulationDepth }, set: { setAmplitudeModulationDepth($0) }),
                    pitchModulationDepth: Binding(get: { editableConfiguration.pitchModulationDepth }, set: { setPitchModulationDepth($0) }),
                    lfoWaveform: Binding(get: { editableConfiguration.lfoWaveform }, set: { setLFOWaveform($0) })
                )

                ConfigurationInstrumentEditor(
                    instruments: editableConfiguration.instruments,
                    updateInstrument: updateInstrument
                )
            }

            if let editError {
                Text(editError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onChange(of: sourceID) { _, _ in
            nameText = editableConfiguration.name
            editError = nil
        }
        .onChange(of: editableConfiguration.name) { _, newName in
            nameText = newName
        }
    }

    private func resetConfiguration() {
        document.resetConfiguration(sourceID: sourceID)
        nameText = originalConfiguration.name
        editError = nil
    }

    private func setName(_ value: String) {
        let limited = String(value.prefix(FB01ConfigurationData.nameLength))
        nameText = limited
        updateConfiguration { try $0.settingName(limited) }
    }

    private func setCombineMode(_ value: Bool) {
        updateConfiguration { try $0.settingCombineModeEnabled(value) }
    }

    private func setKeyCodeReceiveMode(_ value: FB01KeyCodeReceiveMode) {
        updateConfiguration { try $0.settingKeyCodeReceiveMode(value) }
    }

    private func setLFOSpeed(_ value: Int) {
        updateConfiguration { try $0.settingLFOSpeed(value) }
    }

    private func setAmplitudeModulationDepth(_ value: Int) {
        updateConfiguration { try $0.settingAmplitudeModulationDepth(value) }
    }

    private func setPitchModulationDepth(_ value: Int) {
        updateConfiguration { try $0.settingPitchModulationDepth(value) }
    }

    private func setLFOWaveform(_ value: Int) {
        updateConfiguration { try $0.settingLFOWaveform(value) }
    }

    private func updateInstrument(_ instrument: FB01InstrumentConfiguration) {
        updateConfiguration { try $0.replacingInstrument(instrument) }
    }

    private func updateConfiguration(_ edit: (FB01ConfigurationData) throws -> FB01ConfigurationData) {
        do {
            let editedConfiguration = try edit(editableConfiguration)
            document.updateConfiguration(sourceID: sourceID, configuration: editedConfiguration)
            editError = nil
        } catch {
            editError = "Edit failed: \(error)"
        }
    }
}

struct ConfigurationEditorControls: View {
    @Binding var name: String
    @Binding var combineModeEnabled: Bool
    @Binding var keyCodeReceiveMode: FB01KeyCodeReceiveMode
    @Binding var lfoSpeed: Int
    @Binding var amplitudeModulationDepth: Int
    @Binding var pitchModulationDepth: Int
    @Binding var lfoWaveform: Int

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
            GridRow {
                label("Name")
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)
            }

            GridRow {
                label("Combine")
                Toggle("", isOn: $combineModeEnabled)
                    .labelsHidden()
            }

            GridRow {
                label("Key-Code")
                Picker("", selection: $keyCodeReceiveMode) {
                    Text("All").tag(FB01KeyCodeReceiveMode.all)
                    Text("Even").tag(FB01KeyCodeReceiveMode.even)
                    Text("Odd").tag(FB01KeyCodeReceiveMode.odd)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 180)
            }

            GridRow {
                label("LFO Speed")
                Stepper(value: $lfoSpeed, in: 0...127) {
                    Text("\(lfoSpeed)")
                        .monospacedDigit()
                }
            }

            GridRow {
                label("AMD")
                Stepper(value: $amplitudeModulationDepth, in: 0...127) {
                    Text("\(amplitudeModulationDepth)")
                        .monospacedDigit()
                }
            }

            GridRow {
                label("PMD")
                Stepper(value: $pitchModulationDepth, in: 0...127) {
                    Text("\(pitchModulationDepth)")
                        .monospacedDigit()
                }
            }

            GridRow {
                label("Wave")
                Picker("", selection: $lfoWaveform) {
                    Text("1").tag(0)
                    Text("2").tag(1)
                    Text("3").tag(2)
                    Text("4").tag(3)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 180)
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

struct ConfigurationInstrumentEditor: View {
    var instruments: [FB01InstrumentConfiguration]
    var updateInstrument: (FB01InstrumentConfiguration) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Instruments")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    header("#")
                    header("Notes")
                    header("MIDI")
                    header("Voice")
                    header("Level")
                    header("Pan")
                    header("Mode")
                    header("PMD")
                }

                Divider()
                    .gridCellColumns(8)

                ForEach(instruments, id: \.index) { instrument in
                    ConfigurationInstrumentRow(instrument: instrument, updateInstrument: updateInstrument)
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
}

struct ConfigurationInstrumentRow: View {
    var instrument: FB01InstrumentConfiguration
    var updateInstrument: (FB01InstrumentConfiguration) -> Void

    var body: some View {
        GridRow {
            Text("\(instrument.index + 1)")
            Text("\(instrument.noteCount)")
            smallStepper(value: instrument.midiChannel + 1, range: 1...16) { try instrument.settingMIDIChannel($0 - 1) }
            HStack(spacing: 4) {
                smallStepper(value: instrument.voiceBank, range: 1...7) { try instrument.settingVoiceBank($0) }
                Text("/")
                    .foregroundStyle(.secondary)
                smallStepper(value: instrument.voiceNumber, range: 0...95) { try instrument.settingVoiceNumber($0) }
            }
            smallStepper(value: instrument.outputLevel, range: 0...127) { try instrument.settingOutputLevel($0) }
            smallStepper(value: instrument.pan, range: 0...127) { try instrument.settingPan($0) }
            Picker("", selection: modeBinding) {
                Text("Poly").tag(FB01MonoPolyMode.poly)
                Text("Mono").tag(FB01MonoPolyMode.mono)
            }
            .labelsHidden()
            .frame(width: 74)
            Picker("", selection: pmdBinding) {
                Text("Off").tag(FB01PMDControllerAssignment.notAssigned)
                Text("AT").tag(FB01PMDControllerAssignment.afterTouch)
                Text("MW").tag(FB01PMDControllerAssignment.modulationWheel)
                Text("BC").tag(FB01PMDControllerAssignment.breathController)
                Text("FC").tag(FB01PMDControllerAssignment.footController)
            }
            .labelsHidden()
            .frame(width: 82)
        }
    }

    private var modeBinding: Binding<FB01MonoPolyMode> {
        Binding(
            get: { instrument.monoPolyMode == .unknown ? .poly : instrument.monoPolyMode },
            set: { mode in
                if let updated = try? instrument.settingMonoPolyMode(mode) {
                    updateInstrument(updated)
                }
            }
        )
    }

    private var pmdBinding: Binding<FB01PMDControllerAssignment> {
        Binding(
            get: { instrument.pmdControllerAssignment == .unknown ? .notAssigned : instrument.pmdControllerAssignment },
            set: { assignment in
                if let updated = try? instrument.settingPMDControllerAssignment(assignment) {
                    updateInstrument(updated)
                }
            }
        )
    }

    private func smallStepper(
        value: Int,
        range: ClosedRange<Int>,
        update: @escaping (Int) throws -> FB01InstrumentConfiguration
    ) -> some View {
        Stepper(value: Binding(
            get: { value },
            set: { newValue in
                if let updated = try? update(newValue) {
                    updateInstrument(updated)
                }
            }
        ), in: range) {
            Text("\(value)")
                .frame(minWidth: 28, alignment: .trailing)
                .monospacedDigit()
        }
        .frame(width: 78)
    }
}

struct SingleVoiceView: View {
    @ObservedObject var document: DocumentModel
    var sourceID: LibrarySource.ID
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
                        document: document,
                        sourceID: sourceID,
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
    @ObservedObject var document: DocumentModel
    var sourceID: LibrarySource.ID
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
                        document: document,
                        sourceID: sourceID,
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
    @ObservedObject var document: DocumentModel
    var sourceID: LibrarySource.ID
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
                VoiceDetailView(document: document, sourceID: sourceID, systemChannel: systemChannel, summary: selectedVoice)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }
}

struct VoiceDetailView: View {
    @ObservedObject var document: DocumentModel
    var sourceID: LibrarySource.ID
    var systemChannel: Int
    var summary: FB01VoiceSummary
    @State private var nameText: String
    @State private var editError: String?
    @State private var exportError: String?

    init(document: DocumentModel, sourceID: LibrarySource.ID, systemChannel: Int, summary: FB01VoiceSummary) {
        self.document = document
        self.sourceID = sourceID
        self.systemChannel = systemChannel
        self.summary = summary
        _nameText = State(initialValue: document.voice(sourceID: sourceID, number: summary.number, fallback: summary.voice).name)
    }

    private var editableVoice: FB01VoiceData {
        document.voice(sourceID: sourceID, number: summary.number, fallback: summary.voice)
    }

    private var isEdited: Bool {
        editableVoice != summary.voice
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
                if isEdited {
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
        .onChange(of: summary.number) { _, _ in
            nameText = editableVoice.name
            editError = nil
            exportError = nil
        }
        .onChange(of: editableVoice.name) { _, newName in
            nameText = newName
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
        document.resetVoice(sourceID: sourceID, number: summary.number)
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
            let editedVoice = try edit(editableVoice)
            document.updateVoice(sourceID: sourceID, number: summary.number, voice: editedVoice)
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
            let userNumber = number + 1
            return userNumber >= 17 ? "Configuration \(userNumber) Read Only" : "Configuration \(userNumber)"
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

    var configurationSubtitle: String? {
        guard case let .configurationDump(_, number, _) = self else {
            return nil
        }

        let userNumber = number + 1
        return userNumber >= 17 ? "FB-01 Preset Configuration" : "FB-01 Stored Configuration"
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

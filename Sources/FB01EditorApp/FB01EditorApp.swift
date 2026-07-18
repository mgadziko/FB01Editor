import AppKit
import FB01Editor
import SwiftUI
import UniformTypeIdentifiers

enum VoiceSlotOperation {
    case copy
    case swap
}

@main
struct FB01EditorApplication: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var document = DocumentModel()

    var body: some Scene {
        WindowGroup("Forest FB01 Editor") {
            ContentView(document: document)
                .frame(minWidth: 840, minHeight: 540)
                .onAppear {
                    appDelegate.document = document
                }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Forest FB01 Editor") {
                    AboutBoxController.shared.show()
                }
            }

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

                Divider()

                Button("New Configuration Document from Selected") {
                    document.createConfigurationDocumentFromSelected()
                }
                .disabled(!document.canSendSelectedConfiguration)

                Button("Duplicate Selected Configuration...") {
                    document.duplicateSelectedConfigurationDocument()
                }
                .disabled(!document.canSendSelectedConfiguration)

                Button("Save Selected Configuration As...") {
                    document.saveSelectedConfigurationAs()
                }
                .disabled(!document.canSendSelectedConfiguration)
            }

            CommandMenu("Voice") {
                Button("Copy Voice to Slot...") {
                    document.copySelectedVoiceToLocalSlot()
                }
                .disabled(!document.canUseSelectedVoiceLibrarianActions)

                Button("Swap Voice with Slot...") {
                    document.swapSelectedVoiceWithLocalSlot()
                }
                .disabled(!document.canUseSelectedVoiceLibrarianActions)

                Divider()

                Button("Reset Selected Voice") {
                    document.resetSelectedVoiceEdit()
                }
                .disabled(!document.canResetSelectedVoice)

                Button("Reset All Voice Edits") {
                    document.resetAllSelectedVoiceEdits()
                }
                .disabled(!document.canResetAllSelectedVoiceEdits)

                Divider()

                Button("Save Edited Bank As...") {
                    document.saveSelectedEditedVoiceBankAs()
                }
                .disabled(!document.canResetAllSelectedVoiceEdits)
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
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var document: DocumentModel?

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        document?.confirmApplicationTermination() ?? .terminateNow
    }
}

@MainActor
final class AboutBoxController {
    static let shared = AboutBoxController()

    private var panel: NSPanel?

    func show() {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 552, height: 270),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.center()
        panel.contentView = NSHostingView(rootView: AboutBoxView())
        self.panel = panel

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct AboutBoxView: View {
    private var versionText: String {
        if let buildTimestamp = Bundle.main.object(forInfoDictionaryKey: "FB01EditorBuildTimestamp") as? String,
           !buildTimestamp.isEmpty {
            return "Version: \(buildTimestamp)"
        }

        return "Version: Development"
    }

    var body: some View {
        ZStack {
            VisualEffectBackground()

            VStack(alignment: .leading, spacing: 0) {
                AboutAppIcon()
                    .padding(.bottom, 22)

                Text("Forest FB01 Editor")
                    .font(.headline.weight(.semibold))
                    .padding(.bottom, 4)

                Text(versionText)
                    .font(.body)
                    .padding(.bottom, 14)

                Text("©2026 Mark Gadzikowski. All Rights Reserved Worldwide.")
                    .font(.body.weight(.semibold))
                    .padding(.bottom, 2)

                Text("Contact: fb01editor@quantumpenguin.com")
                    .font(.body)
                    .padding(.top, 18)

                Spacer()

                HStack {
                    Spacer()
                    Button("OK") {
                        NSApp.keyWindow?.close()
                    }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .frame(width: 228)
                    Spacer()
                }
            }
            .foregroundStyle(.primary)
            .padding(.top, 24)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .frame(width: 552, height: 270)
    }
}

struct AboutAppIcon: View {
    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 52, height: 52)
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context _: Context) {
        nsView.material = .hudWindow
        nsView.blendingMode = .behindWindow
        nsView.state = .active
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
    @Published var selectedVoiceNumbers: [LibrarySource.ID: Int] = [:]

    private enum DefaultsKey {
        static let sourceIndex = "FB01Editor.selectedMIDISourceIndex"
        static let sourceUniqueID = "FB01Editor.selectedMIDISourceUniqueID"
        static let destinationIndex = "FB01Editor.selectedMIDIDestinationIndex"
        static let destinationUniqueID = "FB01Editor.selectedMIDIDestinationUniqueID"
        static let lastLoadDirectory = "FB01Editor.lastLoadDirectory"
        static let lastSaveDirectory = "FB01Editor.lastSaveDirectory"
    }

    init() {
        ensureDefaultFileDirectory()
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

    var canUseSelectedVoiceLibrarianActions: Bool {
        selectedVoiceContext != nil
    }

    var canResetSelectedVoice: Bool {
        guard let context = selectedVoiceContext,
              let source = sources.first(where: { $0.id == context.sourceID }) else {
            return false
        }
        return source.isVoiceEdited(number: context.number)
    }

    var canResetAllSelectedVoiceEdits: Bool {
        (selectedSource?.editedVoiceCount ?? 0) > 0
    }

    var selectedEditedSourceCount: Int {
        sources.filter(\.isEdited).count
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

    private var selectedVoiceContext: (sourceID: LibrarySource.ID, number: Int, voice: FB01VoiceData, voices: [FB01VoiceSummary])? {
        guard let source = selectedSource,
              let voiceBank = source.voiceBankData else {
            return nil
        }

        let number = selectedVoiceNumbers[source.id] ?? voiceBank.voices.first?.number ?? 1
        guard let summary = voiceBank.voices.first(where: { $0.number == number }) ?? voiceBank.voices.first else {
            return nil
        }
        let voice = self.voice(sourceID: source.id, number: summary.number, fallback: summary.voice)
        return (source.id, summary.number, voice, voiceBank.voices)
    }

    var editingStatusText: String {
        sources.contains { $0.isEdited } ? "Local Edits" : "Local Edit Only"
    }

    var canManageSource: Bool {
        selectedSource != nil && !isBusy
    }

    var hasUnsavedEdits: Bool {
        sources.contains { $0.isEdited }
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
        panel.directoryURL = preferredLoadDirectoryURL()

        guard panel.runModal() == .OK else {
            return
        }

        rememberLoadDirectory(for: panel.urls)
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
                        artifact: FB01Artifact(message: message),
                        origin: .liveFetch
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
                        artifact: FB01Artifact(message: message),
                        origin: .liveFetch
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

    func createConfigurationDocumentFromSelected() {
        guard let source = selectedSource,
              let payload = source.editableConfigurationPayload else {
            return
        }

        let title = payload.name.isEmpty ? "Configuration Document" : "\(payload.name) Document"
        do {
            _ = try createConfigurationDocument(
                sourceID: source.id,
                configuration: payload,
                title: title,
                origin: .localDocument
            )
            statusMessage = "Created local configuration document."
            errorMessage = nil
        } catch {
            statusMessage = nil
            errorMessage = "Create configuration document failed: \(error)"
        }
    }

    func duplicateSelectedConfigurationDocument() {
        guard let source = selectedSource,
              let payload = source.editableConfigurationPayload else {
            return
        }

        duplicateConfigurationDocument(sourceID: source.id, configuration: payload)
    }

    func duplicateConfigurationDocument(sourceID: LibrarySource.ID, configuration: FB01ConfigurationData) {
        guard let source = sources.first(where: { $0.id == sourceID }) else {
            return
        }

        let defaultTitle = source.title.hasSuffix(" Copy") ? source.title : "\(source.title) Copy"
        let alert = NSAlert()
        alert.messageText = "Duplicate Configuration Document"
        alert.informativeText = "Create a new local configuration document. This does not write to disk or change the FB-01."
        alert.addButton(withTitle: "Duplicate")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(string: defaultTitle)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let title = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            return
        }

        do {
            _ = try createConfigurationDocument(
                sourceID: source.id,
                configuration: configuration,
                title: title,
                origin: .duplicatedConfiguration
            )
            statusMessage = "Duplicated configuration as \(title)."
            errorMessage = nil
        } catch {
            statusMessage = nil
            errorMessage = "Duplicate configuration failed: \(error)"
        }
    }

    func saveSelectedConfigurationAs() {
        guard let sourceID = selectedSource?.id else {
            return
        }
        saveConfigurationAs(sourceID: sourceID)
    }

    func saveConfigurationAs(sourceID: LibrarySource.ID) {
        guard let index = sources.firstIndex(where: { $0.id == sourceID }),
              sources[index].isConfigurationSource else {
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.sysex]
        panel.directoryURL = preferredSaveDirectoryURL()
        panel.nameFieldStringValue = "\(safeFileName(sources[index].title)).syx"
        panel.message = "Save this configuration as a SysEx file."
        panel.prompt = "Save Configuration"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        _ = saveEditedSource(at: index, to: url)
        selectedSourceID = sources[index].id
    }

    @discardableResult
    func createConfigurationDocument(
        sourceID: LibrarySource.ID,
        configuration: FB01ConfigurationData,
        title: String,
        origin: LibrarySourceOrigin = .localDocument
    ) throws -> LibrarySource.ID {
        let systemChannel = sources.first { $0.id == sourceID }?.configurationSystemChannel ?? 0
        let artifact = FB01Artifact(message: .currentConfigurationDump(
            systemChannel: systemChannel,
            packet: try FB01SysExPacket(payload: configuration.bytes)
        ))
        let documentSource = LibrarySource(
            title: title,
            subtitle: "Local Configuration Document",
            artifact: artifact,
            origin: origin
        )
        sources.append(documentSource)
        selectedSourceID = documentSource.id
        return documentSource.id
    }

    func configurationArtifactForSaving(sourceID: LibrarySource.ID) throws -> FB01Artifact {
        guard let source = sources.first(where: { $0.id == sourceID }),
              source.isConfigurationSource else {
            throw FB01AppError.noConfigurationSource
        }
        return try source.artifactForSaving()
    }

    func saveSysEx() {
        guard let selectedSource,
              let index = sources.firstIndex(where: { $0.id == selectedSource.id }) else { return }

        if selectedSource.isEdited, let url = selectedSource.fileURL {
            _ = saveEditedSource(at: index, to: url)
            selectedSourceID = sources[index].id
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.sysex]
        panel.directoryURL = preferredSaveDirectoryURL()
        panel.nameFieldStringValue = "\(safeFileName(selectedSource.title)).syx"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let artifact = try selectedSource.artifactForSaving()
            try artifact.writeSysEx(to: url)
            sources[index].markSaved(as: artifact, fileURL: url)
            selectedSourceID = sources[index].id
            rememberSaveDirectory(for: url)
            statusMessage = "Saved \(sources[index].title)."
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
        panel.directoryURL = preferredSaveDirectoryURL()
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
            for source in configurationSources {
                guard let index = sources.firstIndex(where: { $0.id == source.id }),
                      sources[index].editedConfiguration != nil else {
                    continue
                }
                sources[index].markSaved(as: try sources[index].artifactForSaving())
            }
            rememberSaveDirectory(for: url)
            statusMessage = "Saved \(configurationSources.count) configuration\(configurationSources.count == 1 ? "" : "s")."
            errorMessage = nil
        } catch {
            errorMessage = "Save configuration set failed: \(error)"
        }
    }

    func saveEditedVoiceBankAs(sourceID: LibrarySource.ID) {
        guard let index = sources.firstIndex(where: { $0.id == sourceID }) else {
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.sysex]
        panel.directoryURL = preferredSaveDirectoryURL()
        panel.nameFieldStringValue = "\(safeFileName(sources[index].title))-edited.syx"
        panel.message = "Save the edited voice bank as a SysEx file."
        panel.prompt = "Save Edited Bank"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        _ = saveEditedSource(at: index, to: url)
        selectedSourceID = sources[index].id
    }

    func confirmApplicationTermination() -> NSApplication.TerminateReply {
        guard hasUnsavedEdits else {
            return .terminateNow
        }

        let editedCount = sources.filter(\.isEdited).count
        let alert = NSAlert()
        alert.messageText = "Save Changes Before Quitting?"
        alert.informativeText = "The source library contains local edits in \(editedCount) source\(editedCount == 1 ? "" : "s"). Save them as SysEx files before quitting?"
        alert.addButton(withTitle: "Save...")
        alert.addButton(withTitle: "Discard Changes")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return saveEditedSourcesForQuit() ? .terminateNow : .terminateCancel
        case .alertSecondButtonReturn:
            return .terminateNow
        default:
            return .terminateCancel
        }
    }

    func selectSource(_ source: LibrarySource) {
        selectedSourceID = source.id
    }

    func selectVoice(sourceID: LibrarySource.ID, number: Int) {
        selectedVoiceNumbers[sourceID] = number
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

    func resetAllVoiceEdits(sourceID: LibrarySource.ID) {
        guard let index = sources.firstIndex(where: { $0.id == sourceID }) else {
            return
        }

        let count = sources[index].editedVoices.count
        guard count > 0 else {
            return
        }

        let alert = NSAlert()
        alert.messageText = "Reset All Voice Edits?"
        alert.informativeText = "This discards \(count) local voice edit\(count == 1 ? "" : "s") in \(sources[index].title). It does not delete files or change the FB-01."
        alert.addButton(withTitle: "Reset All")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        sources[index].editedVoices.removeAll()
        selectedSourceID = sources[index].id
        statusMessage = "Reset \(count) local voice edit\(count == 1 ? "" : "s")."
        errorMessage = nil
    }

    func copySelectedVoiceToLocalSlot() {
        guard let context = selectedVoiceContext else {
            return
        }
        copyVoiceToLocalSlot(sourceID: context.sourceID, number: context.number, voice: context.voice, voices: context.voices)
    }

    func swapSelectedVoiceWithLocalSlot() {
        guard let context = selectedVoiceContext else {
            return
        }
        swapVoiceWithLocalSlot(sourceID: context.sourceID, number: context.number, voice: context.voice, voices: context.voices)
    }

    func resetSelectedVoiceEdit() {
        guard let context = selectedVoiceContext else {
            return
        }
        resetVoice(sourceID: context.sourceID, number: context.number)
    }

    func resetAllSelectedVoiceEdits() {
        guard let sourceID = selectedSource?.id else {
            return
        }
        resetAllVoiceEdits(sourceID: sourceID)
    }

    func saveSelectedEditedVoiceBankAs() {
        guard let sourceID = selectedSource?.id else {
            return
        }
        saveEditedVoiceBankAs(sourceID: sourceID)
    }

    func copyVoiceToLocalSlot(sourceID: LibrarySource.ID, number: Int, voice: FB01VoiceData, voices: [FB01VoiceSummary]) {
        guard let targetNumber = chooseVoiceSlot(
                title: "Copy Voice to Slot",
                message: "This copies \(voice.name.isEmpty ? "the selected voice" : "\"\(voice.name)\"") to another local voice slot. It does not write to disk or change the FB-01.",
                actionTitle: "Copy",
                sourceID: sourceID,
                currentNumber: number,
                voices: voices
              ) else {
            return
        }

        applyVoiceSlotOperation(.copy, sourceID: sourceID, number: number, targetNumber: targetNumber, voice: voice, voices: voices)
    }

    func swapVoiceWithLocalSlot(sourceID: LibrarySource.ID, number: Int, voice: FB01VoiceData, voices: [FB01VoiceSummary]) {
        guard let targetNumber = chooseVoiceSlot(
                title: "Swap Voice with Slot",
                message: "This swaps the selected voice with another local voice slot. It does not write to disk or change the FB-01.",
                actionTitle: "Swap",
                sourceID: sourceID,
                currentNumber: number,
                voices: voices
              ) else {
            return
        }

        applyVoiceSlotOperation(.swap, sourceID: sourceID, number: number, targetNumber: targetNumber, voice: voice, voices: voices)
    }

    func applyVoiceSlotOperation(_ operation: VoiceSlotOperation, sourceID: LibrarySource.ID, number: Int, targetNumber: Int, voice: FB01VoiceData, voices: [FB01VoiceSummary]) {
        guard let index = sources.firstIndex(where: { $0.id == sourceID }),
              number != targetNumber else {
            return
        }

        if sources[index].isVoiceEdited(number: targetNumber),
           !confirmEditedVoiceSlotOverwrite(operation: operation, source: sources[index], targetNumber: targetNumber) {
            return
        }

        switch operation {
        case .copy:
            sources[index].editedVoices[targetNumber] = voice
            statusMessage = "Copied \(voice.name.isEmpty ? "selected voice" : voice.name) to Voice \(targetNumber) locally."
        case .swap:
            guard let targetSummary = voices.first(where: { $0.number == targetNumber }) else {
                return
            }
            let targetVoice = sources[index].editedVoices[targetNumber] ?? targetSummary.voice
            sources[index].editedVoices[number] = targetVoice
            sources[index].editedVoices[targetNumber] = voice
            statusMessage = "Swapped Voice \(number) with Voice \(targetNumber) locally."
        }

        selectedSourceID = sources[index].id
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

    func preferredSaveDirectoryURL() -> URL {
        preferredDirectory(defaultsKey: DefaultsKey.lastSaveDirectory)
    }

    func rememberSaveDirectory(for url: URL) {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            rememberDirectory(url, defaultsKey: DefaultsKey.lastSaveDirectory)
        } else {
            rememberDirectory(url.deletingLastPathComponent(), defaultsKey: DefaultsKey.lastSaveDirectory)
        }
    }

    func sendSelectedConfigurationToCurrentEditBuffer() {
        guard let selectedSource,
              let payload = selectedSource.editableConfigurationPayload else {
            return
        }

        sendConfigurationToCurrentEditBuffer(sourceID: selectedSource.id, payload: payload)
    }

    func sendConfigurationToCurrentEditBuffer(sourceID: LibrarySource.ID, payload: FB01ConfigurationData) {
        guard let source = sources.first(where: { $0.id == sourceID }) else {
            return
        }

        let alert = NSAlert()
        alert.messageText = "Send Configuration to Current Edit Buffer?"
        alert.informativeText = "This sends \(source.title) to the FB-01 current configuration edit buffer through \(selectedDestinationName). It does not store it in a numbered slot."
        alert.addButton(withTitle: "Send to Edit Buffer")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        sendConfigurationPayload(
            payload,
            systemChannel: source.configurationSystemChannel ?? 0,
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

    func sendVoiceToInstrument(sourceID: LibrarySource.ID, number: Int, voice: FB01VoiceData, systemChannel: Int) {
        guard let source = sources.first(where: { $0.id == sourceID }) else {
            return
        }

        let alert = NSAlert()
        alert.messageText = "Send Voice to FB-01 Instrument?"
        alert.informativeText = "This sends \(voice.name.isEmpty ? "the selected voice" : voice.name) from \(source.title) to a current instrument edit buffer through \(selectedDestinationName). It does not store the voice in a bank slot."
        alert.addButton(withTitle: "Send")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 180, height: 26), pullsDown: false)
        for instrument in 1...8 {
            popup.addItem(withTitle: "Instrument \(instrument)")
        }
        popup.selectItem(at: min(max(number - 1, 0), 7))
        alert.accessoryView = popup

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let instrument = popup.indexOfSelectedItem
        sendVoicePayload(
            voice,
            systemChannel: systemChannel,
            instrument: instrument,
            statusMessage: "Sent voice to instrument \(instrument + 1) on \(selectedDestinationName)."
        )
    }

    func sendAndConfirmVoiceToInstrument(sourceID: LibrarySource.ID, number: Int, voice: FB01VoiceData, systemChannel: Int) {
        guard let source = sources.first(where: { $0.id == sourceID }) else {
            return
        }

        let alert = NSAlert()
        alert.messageText = "Send and Confirm Voice?"
        alert.informativeText = "This sends \(voice.name.isEmpty ? "the selected voice" : voice.name) from \(source.title) to a current instrument edit buffer and waits for the FB-01 status response. It does not store the voice in a bank slot."
        alert.addButton(withTitle: "Send and Confirm")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 180, height: 26), pullsDown: false)
        for instrument in 1...8 {
            popup.addItem(withTitle: "Instrument \(instrument)")
        }
        popup.selectItem(at: min(max(number - 1, 0), 7))
        alert.accessoryView = popup

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let instrument = popup.indexOfSelectedItem
        sendAndConfirmVoicePayload(voice, systemChannel: systemChannel, instrument: instrument)
    }

    func storeVoiceToDeviceSlot(sourceID: LibrarySource.ID, number: Int, voice: FB01VoiceData, systemChannel: Int) {
        guard let source = sources.first(where: { $0.id == sourceID }) else {
            return
        }

        let alert = NSAlert()
        alert.messageText = "Store Voice to FB-01 Slot"
        alert.informativeText = storeVoicePromptText(
            action: "This sends \(voiceDisplayName(voice)) from \(source.title) to a current instrument edit buffer, then permanently stores that instrument voice to a voice slot on the FB-01.",
            voiceSlot: min(max(number - 1, 0), 95)
        )
        alert.addButton(withTitle: "Store and Overwrite")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .leading

        let instrumentPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 180, height: 26), pullsDown: false)
        for instrument in 1...8 {
            instrumentPopup.addItem(withTitle: "Instrument \(instrument)")
        }
        instrumentPopup.selectItem(at: min(max(number - 1, 0), 7))

        let voicePopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 180, height: 26), pullsDown: false)
        for voiceNumber in 1...96 {
            voicePopup.addItem(withTitle: voiceSlotMenuTitle(slot: voiceNumber - 1))
        }
        voicePopup.selectItem(at: min(max(number - 1, 0), 95))

        stack.addArrangedSubview(labelledPopup(label: "Edit buffer:", popup: instrumentPopup))
        stack.addArrangedSubview(labelledPopup(label: "Overwrite slot:", popup: voicePopup))
        alert.accessoryView = stack

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let instrument = instrumentPopup.indexOfSelectedItem
        let voiceSlot = voicePopup.indexOfSelectedItem
        do {
            let voiceMessage = try voice.instrumentVoiceArtifact(systemChannel: systemChannel, instrument: instrument).messages[0]
            let storeCommand = FB01SysExMessage.command(.storeCurrentInstrumentVoice(
                systemChannel: systemChannel,
                instrument: instrument,
                voiceNumber: voiceSlot
            ))
            sendMIDI(
                [try voiceMessage.bytes, try storeCommand.bytes],
                statusMessage: "Stored voice to slot \(voiceSlot + 1) on \(selectedDestinationName)."
            )
        } catch {
            errorMessage = "Store voice failed: \(error)"
            statusMessage = nil
        }
    }

    func storeAndConfirmVoiceToDeviceSlot(sourceID: LibrarySource.ID, number: Int, voice: FB01VoiceData, systemChannel: Int) {
        guard let source = sources.first(where: { $0.id == sourceID }) else {
            return
        }

        let alert = NSAlert()
        alert.messageText = "Store and Confirm Voice"
        alert.informativeText = storeVoicePromptText(
            action: "This sends \(voiceDisplayName(voice)) from \(source.title) to a current instrument edit buffer, permanently stores that instrument voice to a selected FB-01 voice slot, and waits for the FB-01 status response.",
            voiceSlot: min(max(number - 1, 0), 95)
        )
        alert.addButton(withTitle: "Store, Overwrite, and Confirm")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .leading

        let instrumentPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 180, height: 26), pullsDown: false)
        for instrument in 1...8 {
            instrumentPopup.addItem(withTitle: "Instrument \(instrument)")
        }
        instrumentPopup.selectItem(at: min(max(number - 1, 0), 7))

        let voicePopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 180, height: 26), pullsDown: false)
        for voiceNumber in 1...96 {
            voicePopup.addItem(withTitle: voiceSlotMenuTitle(slot: voiceNumber - 1))
        }
        voicePopup.selectItem(at: min(max(number - 1, 0), 95))

        stack.addArrangedSubview(labelledPopup(label: "Edit buffer:", popup: instrumentPopup))
        stack.addArrangedSubview(labelledPopup(label: "Overwrite slot:", popup: voicePopup))
        alert.accessoryView = stack

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        storeAndConfirmVoicePayload(
            voice,
            systemChannel: systemChannel,
            instrument: instrumentPopup.indexOfSelectedItem,
            voiceSlot: voicePopup.indexOfSelectedItem
        )
    }

    func playVoiceTestNotes(voice: FB01VoiceData, systemChannel: Int) {
        playVoiceTestNotes(voice: voice, systemChannel: systemChannel, instrument: 0)
    }

    private func load(urls: [URL]) {
        var loadedSources: [LibrarySource] = []
        var failures: [String] = []

        for url in urls {
            do {
                let artifact = try FB01Artifact.readSysEx(from: url)
                var sources = LibrarySource.sources(from: artifact, fileName: url.lastPathComponent)
                if sources.count == 1 {
                    sources[0].fileURL = url
                }
                loadedSources.append(contentsOf: sources)
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

    private func preferredLoadDirectoryURL() -> URL {
        preferredDirectory(defaultsKey: DefaultsKey.lastLoadDirectory)
    }

    private func rememberLoadDirectory(for urls: [URL]) {
        guard let firstURL = urls.first else {
            return
        }
        rememberDirectory(firstURL.deletingLastPathComponent(), defaultsKey: DefaultsKey.lastLoadDirectory)
    }

    private func preferredDirectory(defaultsKey: String) -> URL {
        ensureDefaultFileDirectory()

        if let path = UserDefaults.standard.string(forKey: defaultsKey) {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            if directoryExists(at: url) {
                return url
            }
        }

        return defaultFileDirectoryURL
    }

    private func rememberDirectory(_ url: URL, defaultsKey: String) {
        let directoryURL = url.standardizedFileURL
        guard directoryExists(at: directoryURL) else {
            return
        }
        UserDefaults.standard.set(directoryURL.path, forKey: defaultsKey)
    }

    private func ensureDefaultFileDirectory() {
        try? FileManager.default.createDirectory(
            at: defaultFileDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    private func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private var defaultFileDirectoryURL: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Forest FB01 Editor", isDirectory: true)
    }

    private func saveEditedSourcesForQuit() -> Bool {
        let editedIDs = sources.filter(\.isEdited).map(\.id)
        guard !editedIDs.isEmpty else {
            return true
        }

        if editedIDs.count == 1 {
            guard let id = editedIDs.first,
                  let index = sources.firstIndex(where: { $0.id == id }) else {
                return true
            }

            let panel = NSSavePanel()
            panel.allowedContentTypes = [.sysex]
            panel.directoryURL = preferredSaveDirectoryURL()
            panel.nameFieldStringValue = "\(safeFileName(sources[index].title)).syx"
            panel.message = "Save edited source before quitting."

            guard panel.runModal() == .OK, let url = panel.url else {
                return false
            }

            return saveEditedSource(at: index, to: url)
        }

        let panel = NSOpenPanel()
        panel.message = "Choose a folder for the edited SysEx sources."
        panel.prompt = "Save"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = preferredSaveDirectoryURL()

        guard panel.runModal() == .OK, let directory = panel.url else {
            return false
        }

        var usedNames = Set<String>()
        for id in editedIDs {
            guard let index = sources.firstIndex(where: { $0.id == id }) else {
                continue
            }

            let fileName = uniqueFileName(for: sources[index].title, usedNames: &usedNames)
            guard saveEditedSource(at: index, to: directory.appendingPathComponent(fileName)) else {
                return false
            }
        }

        rememberSaveDirectory(for: directory)
        return true
    }

    private func saveEditedSource(at index: Int, to url: URL) -> Bool {
        do {
            let artifact = try sources[index].artifactForSaving()
            try artifact.writeSysEx(to: url)
            sources[index].markSaved(as: artifact, fileURL: url)
            rememberSaveDirectory(for: url)
            statusMessage = "Saved \(sources[index].title)."
            errorMessage = nil
            return true
        } catch {
            errorMessage = "Save failed: \(error)"
            statusMessage = nil
            return false
        }
    }

    private func uniqueFileName(for title: String, usedNames: inout Set<String>) -> String {
        let base = safeFileName(title)
        var candidate = "\(base).syx"
        var suffix = 2
        while usedNames.contains(candidate) {
            candidate = "\(base)-\(suffix).syx"
            suffix += 1
        }
        usedNames.insert(candidate)
        return candidate
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

    func currentConfigurationMessageBytes(payload: FB01ConfigurationData, systemChannel: Int) throws -> [UInt8] {
        let message = FB01SysExMessage.currentConfigurationDump(
            systemChannel: systemChannel,
            packet: try FB01SysExPacket(payload: payload.bytes)
        )
        return try message.bytes
    }

    private func sendConfigurationPayload(_ payload: FB01ConfigurationData, systemChannel: Int, statusPrefix: String) {
        do {
            sendMIDI([try currentConfigurationMessageBytes(payload: payload, systemChannel: systemChannel)], statusMessage: "\(statusPrefix) on \(selectedDestinationName).")
        } catch {
            errorMessage = "Send configuration failed: \(error)"
            statusMessage = nil
        }
    }

    private func sendVoicePayload(_ voice: FB01VoiceData, systemChannel: Int, instrument: Int, statusMessage successMessage: String) {
        do {
            let artifact = try voice.instrumentVoiceArtifact(systemChannel: systemChannel, instrument: instrument)
            sendMIDI([try artifact.sysexBytes], statusMessage: successMessage)
        } catch {
            errorMessage = "Send voice failed: \(error)"
            statusMessage = nil
        }
    }

    private func sendAndConfirmVoicePayload(_ voice: FB01VoiceData, systemChannel: Int, instrument: Int) {
        guard !isBusy else { return }

        let sourceIndex = selectedSourceIndex
        let destinationIndex = selectedDestinationIndex
        let destinationName = selectedDestinationName
        isFetchingFromDevice = true
        statusMessage = "Sending voice and waiting for FB-01 status..."
        errorMessage = nil

        Task {
            do {
                let status = try await Task.detached(priority: .userInitiated) {
                    let artifact = try voice.instrumentVoiceArtifact(systemChannel: systemChannel, instrument: instrument)
                    let request = try FB01MIDIRequestKind.instrumentVoice(instrument + 1).bytes(systemChannel: systemChannel)
                    return try FB01MIDI.sendAndReceive(
                        [try artifact.sysexBytes, request],
                        sourceIndex: sourceIndex,
                        destinationIndex: destinationIndex,
                        timeout: 8,
                        maxMessages: 1,
                        delayBetweenMessages: 0.35
                    )
                }.value

                if let code = try deviceStatusCode(from: status) {
                    statusMessage = "FB-01 confirmed voice in instrument \(instrument + 1) on \(destinationName) (status \(String(format: "0x%02X", code)))."
                } else {
                    statusMessage = "Sent voice to instrument \(instrument + 1); FB-01 returned an unrecognized response."
                }
                errorMessage = nil
            } catch {
                statusMessage = nil
                errorMessage = "Voice confirm failed: \(error)"
            }

            isFetchingFromDevice = false
        }
    }

    private func storeAndConfirmVoicePayload(_ voice: FB01VoiceData, systemChannel: Int, instrument: Int, voiceSlot: Int) {
        guard !isBusy else { return }

        let sourceIndex = selectedSourceIndex
        let destinationIndex = selectedDestinationIndex
        let destinationName = selectedDestinationName
        isFetchingFromDevice = true
        statusMessage = "Storing voice and waiting for FB-01 status..."
        errorMessage = nil

        Task {
            do {
                let status = try await Task.detached(priority: .userInitiated) {
                    let voiceMessage = try voice.instrumentVoiceArtifact(systemChannel: systemChannel, instrument: instrument).messages[0]
                    let storeCommand = FB01SysExMessage.command(.storeCurrentInstrumentVoice(
                        systemChannel: systemChannel,
                        instrument: instrument,
                        voiceNumber: voiceSlot
                    ))
                    return try FB01MIDI.sendAndReceive(
                        [try voiceMessage.bytes, try storeCommand.bytes],
                        sourceIndex: sourceIndex,
                        destinationIndex: destinationIndex,
                        timeout: 8,
                        maxMessages: 1,
                        delayBetweenMessages: 0.35
                    )
                }.value

                if let code = try deviceStatusCode(from: status) {
                    statusMessage = "FB-01 confirmed store to voice \(voiceSlot + 1) on \(destinationName) (status \(String(format: "0x%02X", code)))."
                } else {
                    statusMessage = "Stored voice \(voiceSlot + 1); FB-01 returned an unrecognized response."
                }
                errorMessage = nil
            } catch {
                statusMessage = nil
                errorMessage = "Store confirm failed: \(error)"
            }

            isFetchingFromDevice = false
        }
    }

    private func playVoiceTestNotes(voice: FB01VoiceData, systemChannel: Int, instrument: Int) {
        guard !isBusy else { return }

        let destinationIndex = selectedDestinationIndex
        let destinationName = selectedDestinationName
        isFetchingFromDevice = true
        statusMessage = "Sending voice and playing test notes..."
        errorMessage = nil

        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    let artifact = try voice.instrumentVoiceArtifact(systemChannel: systemChannel, instrument: instrument)
                    let noteMessages: [[UInt8]] = [60, 64, 67].flatMap { note in
                        [
                            [0x90, UInt8(note), 100],
                            [0x80, UInt8(note), 0],
                        ]
                    }
                    try FB01MIDI.sendSysEx(
                        [try artifact.sysexBytes] + noteMessages,
                        destinationIndex: destinationIndex,
                        delayBetweenMessages: 0.35
                    )
                }.value

                statusMessage = "Played \(voice.name.isEmpty ? "selected voice" : voice.name) on \(destinationName)."
                errorMessage = nil
            } catch {
                statusMessage = nil
                errorMessage = "Play test failed: \(error)"
            }

            isFetchingFromDevice = false
        }
    }

    private func labelledPopup(label: String, popup: NSPopUpButton) -> NSView {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY

        let text = NSTextField(labelWithString: label)
        text.frame = NSRect(x: 0, y: 0, width: 82, height: 18)
        stack.addArrangedSubview(text)
        stack.addArrangedSubview(popup)
        return stack
    }

    private func chooseVoiceSlot(
        title: String,
        message: String,
        actionTitle: String,
        sourceID: LibrarySource.ID,
        currentNumber: Int,
        voices: [FB01VoiceSummary]
    ) -> Int? {
        let candidates = voices.filter { $0.number != currentNumber }
        guard !candidates.isEmpty else {
            return nil
        }

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: actionTitle)
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 26), pullsDown: false)
        for summary in candidates {
            popup.addItem(withTitle: localVoiceSlotTitle(sourceID: sourceID, summary: summary))
            popup.lastItem?.representedObject = summary.number
        }

        if let currentIndex = candidates.firstIndex(where: { $0.number > currentNumber }) {
            popup.selectItem(at: currentIndex)
        }

        alert.accessoryView = labelledPopup(label: "Target slot:", popup: popup)
        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }

        return popup.selectedItem?.representedObject as? Int
    }

    private func confirmEditedVoiceSlotOverwrite(operation: VoiceSlotOperation, source: LibrarySource, targetNumber: Int) -> Bool {
        let action = switch operation {
        case .copy: "Copy"
        case .swap: "Swap"
        }

        let alert = NSAlert()
        alert.messageText = "\(action) Over Edited Voice?"
        alert.informativeText = "Voice \(targetNumber) in \(source.title) already has a local edit. Continuing will replace that local edited slot state. It will not write to disk or change the FB-01."
        alert.addButton(withTitle: action)
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func localVoiceSlotTitle(sourceID: LibrarySource.ID, summary: FB01VoiceSummary) -> String {
        let voice = self.voice(sourceID: sourceID, number: summary.number, fallback: summary.voice)
        let name = voice.name.isEmpty ? "Untitled" : voice.name
        let edited = sources.first { $0.id == sourceID }?.isVoiceEdited(number: summary.number) ?? false
        return "Voice \(summary.number) - \(name)\(edited ? " (LOCAL EDIT)" : "")"
    }

    private func voiceDisplayName(_ voice: FB01VoiceData) -> String {
        voice.name.isEmpty ? "the selected voice" : "\"\(voice.name)\""
    }

    private func storeVoicePromptText(action: String, voiceSlot: Int) -> String {
        let destination = knownVoiceSlotDescription(slot: voiceSlot)
            ?? "Voice \(voiceSlot + 1), current contents unknown because RAM bank data is not loaded"
        return "\(action)\n\nThis overwrites \(destination). The overwrite slot menu shows the loaded destination voice name when the app knows it."
    }

    private func voiceSlotMenuTitle(slot: Int) -> String {
        if let destination = knownVoiceSlotDescription(slot: slot) {
            return destination
        }
        return "Voice \(slot + 1) - unknown current contents"
    }

    private func knownVoiceSlotDescription(slot: Int) -> String? {
        guard (0..<FB01VoiceBankData.voiceCount * 2).contains(slot) else {
            return nil
        }

        let bank = slot / FB01VoiceBankData.voiceCount
        let number = slot % FB01VoiceBankData.voiceCount + 1

        guard let voice = knownVoice(bank: bank, number: number) else {
            return nil
        }

        let name = voice.name.isEmpty ? "Untitled" : voice.name
        return "Voice \(slot + 1) - Bank \(bank + 1) #\(number): \(name)"
    }

    private func knownVoice(bank: Int, number: Int) -> FB01VoiceData? {
        for source in sources.reversed() {
            switch source.artifact.messages.first {
            case let .voiceBankDumpData(_, sourceBank, _, data, _) where sourceBank == bank:
                if let voiceBank = try? FB01VoiceBankData(bank: sourceBank, data: data) {
                    return source.voice(number: number, in: voiceBank)
                }
            case let .voiceRAMDumpData(_, _, data, _) where bank == 0:
                if let voiceBank = try? FB01VoiceBankData(bank: 0, data: data) {
                    return source.voice(number: number, in: voiceBank)
                }
            default:
                break
            }
        }
        return nil
    }

    private func deviceStatusCode(from messages: [[UInt8]]) throws -> UInt8? {
        for bytes in messages {
            let artifact = try FB01Artifact(sysexBytes: bytes)
            for message in artifact.messages {
                if case .deviceStatus(let code) = message {
                    return code
                }
            }
        }
        return nil
    }

    private func sendMIDI(
        _ messages: [[UInt8]],
        delayBetweenMessages: TimeInterval = 0.2,
        statusMessage successMessage: String
    ) {
        guard !isBusy else { return }

        let destinationIndex = selectedDestinationIndex
        isFetchingFromDevice = true
        statusMessage = "Sending MIDI..."
        errorMessage = nil

        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try FB01MIDI.sendSysEx(
                        messages,
                        destinationIndex: destinationIndex,
                        delayBetweenMessages: delayBetweenMessages
                    )
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

enum LibrarySourceOrigin: String, Equatable {
    case loadedFromDisk
    case liveFetch
    case localDocument
    case duplicatedConfiguration

    var displayName: String {
        switch self {
        case .loadedFromDisk:
            "Loaded from Disk"
        case .liveFetch:
            "Fetched from FB-01"
        case .localDocument:
            "Local Document"
        case .duplicatedConfiguration:
            "Duplicated Document"
        }
    }
}

enum FB01AppError: Error {
    case noConfigurationSource
}

struct LibrarySource: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var subtitle: String
    var artifact: FB01Artifact
    var fileURL: URL?
    var origin: LibrarySourceOrigin = .loadedFromDisk
    var editedVoices: [Int: FB01VoiceData] = [:]
    var editedConfiguration: FB01ConfigurationData?

    var isEdited: Bool {
        !editedVoices.isEmpty || editedConfiguration != nil
    }

    func isVoiceEdited(number: Int) -> Bool {
        editedVoices[number] != nil
    }

    var editedVoiceCount: Int {
        editedVoices.count
    }

    func voice(number: Int, in voiceBank: FB01VoiceBankData) -> FB01VoiceData? {
        if let editedVoice = editedVoices[number] {
            return editedVoice
        }
        return voiceBank.voices.first { $0.number == number }?.voice
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

    var isLocalConfigurationDocument: Bool {
        isConfigurationSource && subtitle == "Local Configuration Document"
    }

    var isReadOnlyStoredConfiguration: Bool {
        guard let storedConfigurationNumber else {
            return false
        }
        return storedConfigurationNumber >= 16
    }

    var displaySubtitle: String {
        let state = if isEdited {
            "Edited"
        } else if fileURL != nil {
            "Saved"
        } else if origin == .localDocument || origin == .duplicatedConfiguration {
            "Unsaved"
        } else {
            origin.displayName
        }

        if isLocalConfigurationDocument {
            return "\(origin.displayName) - \(state)"
        }

        if isConfigurationSource, isEdited {
            return "\(subtitle) - Edited"
        }

        if fileURL != nil, origin == .loadedFromDisk {
            return "\(subtitle) - Loaded from Disk"
        }

        return subtitle
    }

    var voiceBankData: FB01VoiceBankData? {
        guard artifact.messages.count == 1 else {
            return nil
        }

        switch artifact.messages[0] {
        case let .voiceBankDumpData(_, bank, _, data, _):
            return try? FB01VoiceBankData(bank: bank, data: data)
        case let .voiceRAMDumpData(_, _, data, _):
            return try? FB01VoiceBankData(bank: 0, data: data)
        default:
            return nil
        }
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

    mutating func markSaved(as savedArtifact: FB01Artifact, fileURL: URL? = nil) {
        artifact = savedArtifact
        if let fileURL {
            self.fileURL = fileURL
        }
        editedVoices.removeAll()
        editedConfiguration = nil
    }

    static func sources(from artifact: FB01Artifact, fileName: String) -> [LibrarySource] {
        guard artifact.messages.count > 1 else {
            return [
                LibrarySource(
                    title: artifact.messages.first?.sourceTitle(index: 1) ?? fileName,
                    subtitle: fileName,
                    artifact: artifact,
                    origin: .loadedFromDisk
                ),
            ]
        }

        return artifact.messages.enumerated().map { index, message in
            LibrarySource(
                title: message.sourceTitle(index: index + 1),
                subtitle: fileName,
                artifact: FB01Artifact(message: message),
                origin: .loadedFromDisk
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
                .help(document.selectedEditedSourceCount == 0 ? "No local edits" : "\(document.selectedEditedSourceCount) source\(document.selectedEditedSourceCount == 1 ? "" : "s") with unsaved local edits")
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
                                HStack(alignment: .top, spacing: 7) {
                                    Image(systemName: source.isEdited ? "circle.fill" : "circle")
                                        .font(.system(size: 7, weight: .semibold))
                                        .foregroundStyle(source.isEdited ? .orange : .clear)
                                        .frame(width: 8, height: 16)
                                        .padding(.top, 2)

                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 5) {
                                            if source.isLocalConfigurationDocument {
                                                Image(systemName: "doc.text")
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(.blue)
                                            }
                                            Text(source.title)
                                                .font(.body.weight(.medium))
                                                .lineLimit(1)
                                        }
                                        Text(source.displaySubtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
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
                if !isReadOnly {
                    Button {
                        document.duplicateConfigurationDocument(sourceID: sourceID, configuration: editableConfiguration)
                    } label: {
                        Label("Duplicate", systemImage: "doc.on.doc")
                    }
                    Button {
                        document.saveConfigurationAs(sourceID: sourceID)
                    } label: {
                        Label("Save As", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        document.sendConfigurationToCurrentEditBuffer(sourceID: sourceID, payload: editableConfiguration)
                    } label: {
                        Label("Send Edit Buffer", systemImage: "arrow.up.circle")
                    }
                    .disabled(document.isBusy)
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
                KeyValueRow("LFO", "Speed \(editableConfiguration.lfoSpeed), AMD \(editableConfiguration.amplitudeModulationDepth), PMD \(editableConfiguration.pitchModulationDepth), Waveform \(editableConfiguration.lfoWaveform.lfoWaveformDisplayName)"),
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
        HStack(alignment: .top, spacing: 12) {
            GroupBox {
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
                }
                .padding(.top, 4)
            } label: {
                SectionTitle("Identity")
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            GroupBox {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
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
                        label("Waveform")
                        Picker("", selection: $lfoWaveform) {
                            Text("Saw").tag(0)
                            Text("Square").tag(1)
                            Text("Triangle").tag(2)
                            Text("Random").tag(3)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 260)
                    }
                }
                .padding(.top, 4)
            } label: {
                SectionTitle("Receive and Waveform")
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            GroupBox {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                    GridRow {
                        label("LFO Speed")
                        Stepper(value: $lfoSpeed, in: 0...127) {
                            Text("\(lfoSpeed)")
                                .monospacedDigit()
                        }
                    }

                    GridRow {
                        label("Depth")
                        HStack(spacing: 16) {
                            Stepper(value: $amplitudeModulationDepth, in: 0...127) {
                                Text("AMD \(amplitudeModulationDepth)")
                                    .monospacedDigit()
                            }
                            Stepper(value: $pitchModulationDepth, in: 0...127) {
                                Text("PMD \(pitchModulationDepth)")
                                    .monospacedDigit()
                            }
                        }
                    }
                }
                .padding(.top, 4)
            } label: {
                SectionTitle("LFO and Modulation")
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
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
    @State private var selectedInstrumentIndex = 0

    private var selectedInstrument: FB01InstrumentConfiguration? {
        instruments.first { $0.index == selectedInstrumentIndex } ?? instruments.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Instruments")

            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 8) {
                    ForEach(instruments, id: \.index) { instrument in
                        ConfigurationInstrumentSelectorButton(
                            instrument: instrument,
                            isSelected: instrument.index == selectedInstrumentIndex
                        ) {
                            selectedInstrumentIndex = instrument.index
                        }
                    }
                }
                .frame(width: 150)

                VStack(alignment: .leading, spacing: 10) {
                    if let selectedInstrument {
                        ConfigurationInstrumentInspector(
                            instrument: selectedInstrument,
                            updateInstrument: updateInstrument
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .onChange(of: instruments) { _, newInstruments in
            guard !newInstruments.contains(where: { $0.index == selectedInstrumentIndex }) else {
                return
            }
            selectedInstrumentIndex = newInstruments.first?.index ?? 0
        }
    }
}

struct ConfigurationInstrumentSelectorButton: View {
    var instrument: FB01InstrumentConfiguration
    var isSelected: Bool
    var select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Instrument \(instrument.index + 1)")
                        .font(.body.weight(.semibold))
                    Spacer()
                    Text(instrument.monoPolyMode.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("MIDI \(instrument.midiChannel + 1), Voice \(instrument.voiceBank)/\(instrument.voiceNumber)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.18))
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: proxy.size.width * CGFloat(instrument.outputLevel) / 127)
                    }
                }
                .frame(height: 5)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.22), lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct ConfigurationInstrumentInspector: View {
    var instrument: FB01InstrumentConfiguration
    var updateInstrument: (FB01InstrumentConfiguration) -> Void

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(minimum: 220), spacing: 12),
            GridItem(.flexible(minimum: 220), spacing: 12),
        ], alignment: .leading, spacing: 12) {
            OperatorControlGroup(title: "MIDI and Voice") {
                instrumentStepper("MIDI Channel", value: instrument.midiChannel + 1, range: 1...16) { try instrument.settingMIDIChannel($0 - 1) }
                instrumentStepper("Voice Bank", value: instrument.voiceBank, range: 1...7) { try instrument.settingVoiceBank($0) }
                instrumentStepper("Voice Number", value: instrument.voiceNumber, range: 0...95) { try instrument.settingVoiceNumber($0) }
                Picker("Mode", selection: modeBinding) {
                    Text("Poly").tag(FB01MonoPolyMode.poly)
                    Text("Mono").tag(FB01MonoPolyMode.mono)
                }
            }

            OperatorControlGroup(title: "Key Range") {
                readOnlyValue("Active Notes", value: "\(instrument.noteCount)")
                instrumentStepper("Low Key", value: instrument.lowKeyLimit, range: 0...127) { try instrument.settingLowKeyLimit($0) }
                instrumentStepper("High Key", value: instrument.highKeyLimit, range: 0...127) { try instrument.settingHighKeyLimit($0) }
            }

            OperatorControlGroup(title: "Output") {
                instrumentStepper("Level", value: instrument.outputLevel, range: 0...127) { try instrument.settingOutputLevel($0) }
                instrumentStepper("Pan", value: instrument.pan, range: 0...127) { try instrument.settingPan($0) }
                Toggle("LFO Enabled", isOn: lfoEnabledBinding)
                    .toggleStyle(.checkbox)
                Picker("PMD", selection: pmdBinding) {
                    Text(FB01PMDControllerAssignment.notAssigned.displayName).tag(FB01PMDControllerAssignment.notAssigned)
                    Text(FB01PMDControllerAssignment.afterTouch.displayName).tag(FB01PMDControllerAssignment.afterTouch)
                    Text(FB01PMDControllerAssignment.modulationWheel.displayName).tag(FB01PMDControllerAssignment.modulationWheel)
                    Text(FB01PMDControllerAssignment.breathController.displayName).tag(FB01PMDControllerAssignment.breathController)
                    Text(FB01PMDControllerAssignment.footController.displayName).tag(FB01PMDControllerAssignment.footController)
                }
            }

            OperatorControlGroup(title: "Performance") {
                instrumentStepper("Octave", value: instrument.octaveTranspose, range: -2...2) { try instrument.settingOctaveTranspose($0) }
                instrumentStepper("Portamento", value: instrument.portamentoTime, range: 0...127) { try instrument.settingPortamentoTime($0) }
                instrumentStepper("Bend Range", value: instrument.pitchBendRange, range: 0...12) { try instrument.settingPitchBendRange($0) }
            }
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

    private var lfoEnabledBinding: Binding<Bool> {
        Binding(
            get: { instrument.lfoEnabled },
            set: { enabled in
                if let updated = try? instrument.settingLFOEnabled(enabled) {
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

    private func instrumentStepper(
        _ label: String,
        value: Int,
        range: ClosedRange<Int>,
        update: @escaping (Int) throws -> FB01InstrumentConfiguration
    ) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Stepper(value: Binding(
                get: { value },
                set: { newValue in
                    if let updated = try? update(newValue) {
                        updateInstrument(updated)
                    }
                }
            ), in: range) {
                Text("\(value)")
                    .frame(minWidth: 34, alignment: .trailing)
                    .monospacedDigit()
            }
        }
    }

    private func readOnlyValue(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
    }
}

struct SectionTitle: View {
    var title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.headline)
            .foregroundStyle(.blue)
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
    private let voiceDragType = UTType.plainText

    private var selectedVoice: FB01VoiceSummary? {
        voices.first { $0.number == selectedVoiceNumber } ?? voices.first
    }

    private var editedVoiceCount: Int {
        document.sources.first { $0.id == sourceID }?.editedVoiceCount ?? 0
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("Voices")
                        .font(.headline)

                    if editedVoiceCount > 0 {
                        Text("\(editedVoiceCount) edited")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.orange)
                    }

                    Spacer()

                    Button {
                        document.saveEditedVoiceBankAs(sourceID: sourceID)
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .help("Save edited bank as a SysEx file")
                    .disabled(editedVoiceCount == 0)

                    Button {
                        document.resetAllVoiceEdits(sourceID: sourceID)
                    } label: {
                        Image(systemName: "arrow.uturn.backward.circle")
                    }
                    .help("Reset all local voice edits in this bank")
                    .disabled(editedVoiceCount == 0)
                }

                VStack(spacing: 2) {
                    ForEach(voices) { voice in
                        Button {
                            selectedVoiceNumber = voice.number
                            document.selectVoice(sourceID: sourceID, number: voice.number)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: isVoiceEdited(voice.number) ? "circle.fill" : "circle")
                                    .font(.system(size: 6, weight: .semibold))
                                    .foregroundStyle(isVoiceEdited(voice.number) ? .orange : .clear)
                                    .frame(width: 8)
                                Text("\(voice.number)")
                                    .frame(width: 28, alignment: .trailing)
                                    .foregroundStyle(.secondary)
                                Text(displayName(for: voice))
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
                        .onDrag {
                            NSItemProvider(object: "\(voice.number)" as NSString)
                        }
                        .onDrop(of: [voiceDragType], isTargeted: nil) { providers in
                            handleVoiceDrop(providers: providers, targetVoice: voice)
                        }
                    }
                }
            }
            .frame(width: 220, alignment: .topLeading)

            Divider()

            if let selectedVoice {
                VoiceDetailView(document: document, sourceID: sourceID, systemChannel: systemChannel, summary: selectedVoice, bankVoices: voices)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .onAppear {
            document.selectVoice(sourceID: sourceID, number: selectedVoice?.number ?? selectedVoiceNumber)
        }
        .onChange(of: selectedVoiceNumber) { _, newValue in
            document.selectVoice(sourceID: sourceID, number: newValue)
        }
    }

    private func isVoiceEdited(_ number: Int) -> Bool {
        document.sources.first { $0.id == sourceID }?.isVoiceEdited(number: number) ?? false
    }

    private func displayName(for summary: FB01VoiceSummary) -> String {
        let voice = document.voice(sourceID: sourceID, number: summary.number, fallback: summary.voice)
        return voice.name.isEmpty ? "Untitled" : voice.name
    }

    private func handleVoiceDrop(providers: [NSItemProvider], targetVoice: FB01VoiceSummary) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else {
            return false
        }

        provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let string = object as? String,
                  let sourceNumber = Int(string),
                  sourceNumber != targetVoice.number,
                  let sourceSummary = voices.first(where: { $0.number == sourceNumber }) else {
                return
            }

            DispatchQueue.main.async {
                let sourceVoice = document.voice(sourceID: sourceID, number: sourceSummary.number, fallback: sourceSummary.voice)
                guard let operation = chooseDropOperation(sourceNumber: sourceNumber, targetNumber: targetVoice.number) else {
                    return
                }
                document.applyVoiceSlotOperation(
                    operation,
                    sourceID: sourceID,
                    number: sourceNumber,
                    targetNumber: targetVoice.number,
                    voice: sourceVoice,
                    voices: voices
                )
                selectedVoiceNumber = targetVoice.number
            }
        }

        return true
    }

    private func chooseDropOperation(sourceNumber: Int, targetNumber: Int) -> VoiceSlotOperation? {
        let alert = NSAlert()
        alert.messageText = "Drop Voice \(sourceNumber) on Voice \(targetNumber)"
        alert.informativeText = "Choose a local librarian action. This does not write to disk or change the FB-01."
        alert.addButton(withTitle: "Copy")
        alert.addButton(withTitle: "Swap")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .informational

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .copy
        case .alertSecondButtonReturn:
            return .swap
        default:
            return nil
        }
    }
}

struct VoiceDetailView: View {
    @ObservedObject var document: DocumentModel
    var sourceID: LibrarySource.ID
    var systemChannel: Int
    var summary: FB01VoiceSummary
    var bankVoices: [FB01VoiceSummary]
    @State private var nameText: String
    @State private var editError: String?
    @State private var exportError: String?

    init(document: DocumentModel, sourceID: LibrarySource.ID, systemChannel: Int, summary: FB01VoiceSummary, bankVoices: [FB01VoiceSummary] = []) {
        self.document = document
        self.sourceID = sourceID
        self.systemChannel = systemChannel
        self.summary = summary
        self.bankVoices = bankVoices
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
                if bankVoices.count > 1 {
                    Button {
                        copyVoice()
                    } label: {
                        Label("Copy To", systemImage: "doc.on.doc")
                    }
                    Button {
                        swapVoice()
                    } label: {
                        Label("Swap With", systemImage: "arrow.left.arrow.right")
                    }
                }
                Button {
                    document.sendVoiceToInstrument(sourceID: sourceID, number: summary.number, voice: editableVoice, systemChannel: systemChannel)
                } label: {
                    Label("Send", systemImage: "arrow.up.circle")
                }
                .disabled(document.isBusy)
                Button {
                    document.sendAndConfirmVoiceToInstrument(sourceID: sourceID, number: summary.number, voice: editableVoice, systemChannel: systemChannel)
                } label: {
                    Label("Send & Confirm", systemImage: "checkmark.seal")
                }
                .disabled(document.isBusy)
                Button {
                    document.storeVoiceToDeviceSlot(sourceID: sourceID, number: summary.number, voice: editableVoice, systemChannel: systemChannel)
                } label: {
                    Label("Store", systemImage: "externaldrive.badge.plus")
                }
                .disabled(document.isBusy)
                Button {
                    document.storeAndConfirmVoiceToDeviceSlot(sourceID: sourceID, number: summary.number, voice: editableVoice, systemChannel: systemChannel)
                } label: {
                    Label("Store & Confirm", systemImage: "externaldrive.badge.checkmark")
                }
                .disabled(document.isBusy)
                Button {
                    document.playVoiceTestNotes(voice: editableVoice, systemChannel: systemChannel)
                } label: {
                    Label("Play Test", systemImage: "speaker.wave.2")
                }
                .disabled(document.isBusy)
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
                KeyValueRow("LFO", "Speed \(editableVoice.lfoSpeed), Waveform \(editableVoice.lfoWaveform.lfoWaveformDisplayName), Sync \(editableVoice.lfoSyncEnabled ? "On" : "Off")"),
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
                ),
                lfoWaveform: Binding(
                    get: { editableVoice.lfoWaveform },
                    set: { setLFOWaveform($0) }
                ),
                lfoSyncEnabled: Binding(
                    get: { editableVoice.lfoSyncEnabled },
                    set: { setLFOSyncEnabled($0) }
                ),
                amplitudeModulationDepth: Binding(
                    get: { editableVoice.amplitudeModulationDepth },
                    set: { setAmplitudeModulationDepth($0) }
                ),
                pitchModulationDepth: Binding(
                    get: { editableVoice.pitchModulationDepth },
                    set: { setPitchModulationDepth($0) }
                ),
                amplitudeModulationSensitivity: Binding(
                    get: { editableVoice.amplitudeModulationSensitivity },
                    set: { setAmplitudeModulationSensitivity($0) }
                ),
                pitchModulationSensitivity: Binding(
                    get: { editableVoice.pitchModulationSensitivity },
                    set: { setPitchModulationSensitivity($0) }
                ),
                transpose: Binding(
                    get: { editableVoice.transpose },
                    set: { setTranspose($0) }
                ),
                leftOutputEnabled: Binding(
                    get: { editableVoice.leftOutputEnabled },
                    set: { setLeftOutputEnabled($0) }
                ),
                rightOutputEnabled: Binding(
                    get: { editableVoice.rightOutputEnabled },
                    set: { setRightOutputEnabled($0) }
                ),
                operatorEnabled: (0..<FB01VoiceData.operatorCount).map { index in
                    Binding(
                        get: { editableVoice.operatorEnabled[index] },
                        set: { setOperatorEnabled(index: index, enabled: $0) }
                    )
                }
            )

            OperatorEditor(
                operators: editableVoice.operators,
                updateOperator: updateOperator
            )

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

    private func copyVoice() {
        document.copyVoiceToLocalSlot(sourceID: sourceID, number: summary.number, voice: editableVoice, voices: bankVoices)
        editError = nil
        exportError = nil
    }

    private func swapVoice() {
        document.swapVoiceWithLocalSlot(sourceID: sourceID, number: summary.number, voice: editableVoice, voices: bankVoices)
        nameText = document.voice(sourceID: sourceID, number: summary.number, fallback: summary.voice).name
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

    private func setLFOWaveform(_ value: Int) {
        updateVoice { try $0.settingLFOWaveform(value) }
    }

    private func setLFOSyncEnabled(_ value: Bool) {
        updateVoice { try $0.settingLFOSyncEnabled(value) }
    }

    private func setAmplitudeModulationDepth(_ value: Int) {
        updateVoice { try $0.settingAmplitudeModulationDepth(value) }
    }

    private func setPitchModulationDepth(_ value: Int) {
        updateVoice { try $0.settingPitchModulationDepth(value) }
    }

    private func setAmplitudeModulationSensitivity(_ value: Int) {
        updateVoice { try $0.settingAmplitudeModulationSensitivity(value) }
    }

    private func setPitchModulationSensitivity(_ value: Int) {
        updateVoice { try $0.settingPitchModulationSensitivity(value) }
    }

    private func setTranspose(_ value: Int) {
        updateVoice { try $0.settingTranspose(value) }
    }

    private func setLeftOutputEnabled(_ value: Bool) {
        updateVoice { try $0.settingLeftOutputEnabled(value) }
    }

    private func setRightOutputEnabled(_ value: Bool) {
        updateVoice { try $0.settingRightOutputEnabled(value) }
    }

    private func setOperatorEnabled(index: Int, enabled: Bool) {
        updateVoice { try $0.settingOperatorEnabled(index: index, enabled: enabled) }
    }

    private func updateOperator(_ operatorData: FB01VoiceOperatorData) {
        updateVoice { try $0.replacingOperator(operatorData) }
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
        panel.directoryURL = document.preferredSaveDirectoryURL()
        panel.nameFieldStringValue = "voice-\(summary.number)-\(safeFileName(editableVoice.name)).syx"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let artifact = try editableVoice.instrumentVoiceArtifact(systemChannel: systemChannel, instrument: 0)
            try artifact.writeSysEx(to: url)
            document.rememberSaveDirectory(for: url)
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
    @Binding var lfoWaveform: Int
    @Binding var lfoSyncEnabled: Bool
    @Binding var amplitudeModulationDepth: Int
    @Binding var pitchModulationDepth: Int
    @Binding var amplitudeModulationSensitivity: Int
    @Binding var pitchModulationSensitivity: Int
    @Binding var transpose: Int
    @Binding var leftOutputEnabled: Bool
    @Binding var rightOutputEnabled: Bool
    var operatorEnabled: [Binding<Bool>]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            GroupBox {
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
                        label("Transpose")
                        Stepper(value: $transpose, in: -128...127) {
                            Text("\(transpose)")
                                .monospacedDigit()
                        }
                    }
                }
                .padding(.top, 4)
            } label: {
                sectionTitle("Identity")
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            GroupBox {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                    GridRow {
                        label("LFO Speed")
                        Stepper(value: $lfoSpeed, in: 0...255) {
                            Text("\(lfoSpeed)")
                                .monospacedDigit()
                        }
                    }

                    GridRow {
                        label("Waveform")
                        Picker("", selection: $lfoWaveform) {
                            Text("Saw").tag(0)
                            Text("Square").tag(1)
                            Text("Triangle").tag(2)
                            Text("Random").tag(3)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 260)
                    }

                    GridRow {
                        label("LFO Sync")
                        Toggle("", isOn: $lfoSyncEnabled)
                            .labelsHidden()
                    }

                    GridRow {
                        label("Depth")
                        HStack(spacing: 16) {
                            Stepper(value: $amplitudeModulationDepth, in: 0...127) {
                                Text("AMD \(amplitudeModulationDepth)")
                                    .monospacedDigit()
                            }
                            Stepper(value: $pitchModulationDepth, in: 0...127) {
                                Text("PMD \(pitchModulationDepth)")
                                    .monospacedDigit()
                            }
                        }
                    }

                    GridRow {
                        label("Sensitivity")
                        HStack(spacing: 16) {
                            Stepper(value: $amplitudeModulationSensitivity, in: 0...3) {
                                Text("AMS \(amplitudeModulationSensitivity)")
                                    .monospacedDigit()
                            }
                            Stepper(value: $pitchModulationSensitivity, in: 0...7) {
                                Text("PMS \(pitchModulationSensitivity)")
                                    .monospacedDigit()
                            }
                        }
                    }
                }
                .padding(.top, 4)
            } label: {
                sectionTitle("LFO and Modulation")
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            GroupBox {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                    GridRow {
                        label("Output")
                        HStack(spacing: 12) {
                            Toggle("Left", isOn: $leftOutputEnabled)
                            Toggle("Right", isOn: $rightOutputEnabled)
                        }
                    }

                    GridRow {
                        label("Operators")
                        HStack(spacing: 12) {
                            ForEach(Array(operatorEnabled.enumerated()), id: \.offset) { index, binding in
                                Toggle("\(index + 1)", isOn: binding)
                            }
                        }
                    }
                }
                .padding(.top, 4)
            } label: {
                sectionTitle("Output and Operators")
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func sectionTitle(_ text: String) -> some View {
        SectionTitle(text)
    }
}

struct OperatorEditor: View {
    var operators: [FB01VoiceOperatorData]
    var updateOperator: (FB01VoiceOperatorData) -> Void
    @State private var selectedOperatorIndex = 0

    private var selectedOperator: FB01VoiceOperatorData? {
        operators.first { $0.index == selectedOperatorIndex } ?? operators.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Operators")

            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 8) {
                    ForEach(operators, id: \.index) { op in
                        OperatorSelectorButton(
                            operatorData: op,
                            isSelected: op.index == selectedOperatorIndex
                        ) {
                            selectedOperatorIndex = op.index
                        }
                    }
                }
                .frame(width: 150)

                VStack(alignment: .leading, spacing: 10) {
                    if let selectedOperator {
                        OperatorInspector(
                            operatorData: selectedOperator,
                            updateOperator: updateOperator
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .onChange(of: operators) { _, newOperators in
            guard !newOperators.contains(where: { $0.index == selectedOperatorIndex }) else {
                return
            }
            selectedOperatorIndex = newOperators.first?.index ?? 0
        }
    }
}

struct OperatorSelectorButton: View {
    var operatorData: FB01VoiceOperatorData
    var isSelected: Bool
    var select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Operator \(operatorData.index + 1)")
                        .font(.body.weight(.semibold))
                    Spacer()
                    Text(operatorData.carrier ? "Carrier" : "Mod")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("TL \(operatorData.totalLevel), Mul \(operatorData.multiple)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.18))
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: proxy.size.width * CGFloat(operatorData.totalLevel) / 127)
                    }
                }
                .frame(height: 5)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.22), lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct OperatorInspector: View {
    var operatorData: FB01VoiceOperatorData
    var updateOperator: (FB01VoiceOperatorData) -> Void

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(minimum: 220), spacing: 12),
            GridItem(.flexible(minimum: 220), spacing: 12),
        ], alignment: .leading, spacing: 12) {
            OperatorControlGroup(title: "Level") {
                operatorToggle("Carrier", binding: carrierBinding)
                operatorStepper("Total Level", value: operatorData.totalLevel, range: 0...127) { try operatorData.settingTotalLevel($0) }
                operatorStepper("Velocity to TL", value: operatorData.velocitySensitivityForTotalLevel, range: 0...7) { try operatorData.settingVelocitySensitivityForTotalLevel($0) }
                operatorStepper("TL Adjust", value: operatorData.totalLevelAdjust, range: 0...15) { try operatorData.settingTotalLevelAdjust($0) }
            }

            OperatorControlGroup(title: "Tuning") {
                operatorStepper("Multiple", value: operatorData.multiple, range: 0...15) { try operatorData.settingMultiple($0) }
                operatorStepper("Detune 1", value: operatorData.detune1, range: 0...7) { try operatorData.settingDetune1($0) }
                operatorStepper("Detune 2", value: operatorData.detune2, range: 0...3) { try operatorData.settingDetune2($0) }
            }

            OperatorControlGroup(title: "Envelope") {
                operatorStepper("Attack Rate", value: operatorData.attackRate, range: 0...31) { try operatorData.settingAttackRate($0) }
                operatorStepper("Velocity to Attack", value: operatorData.velocitySensitivityForAttackRate, range: 0...7) { try operatorData.settingVelocitySensitivityForAttackRate($0) }
                operatorStepper("Decay 1 Rate", value: operatorData.decay1Rate, range: 0...15) { try operatorData.settingDecay1Rate($0) }
                operatorStepper("Decay 2 Rate", value: operatorData.decay2Rate, range: 0...31) { try operatorData.settingDecay2Rate($0) }
                operatorStepper("Sustain Level", value: operatorData.sustainLevel, range: 0...15) { try operatorData.settingSustainLevel($0) }
                operatorStepper("Release Rate", value: operatorData.releaseRate, range: 0...15) { try operatorData.settingReleaseRate($0) }
            }

            OperatorControlGroup(title: "Keyboard Scaling") {
                operatorStepper("Level Scaling", value: operatorData.keyboardLevelScalingDepth, range: 0...15) { try operatorData.settingKeyboardLevelScalingDepth($0) }
                operatorToggle("Level Type A", binding: keyboardLevelScalingTypeBit0Binding)
                operatorToggle("Level Type B", binding: keyboardLevelScalingTypeBit1Binding)
                operatorStepper("Rate Scaling", value: operatorData.keyboardRateScalingDepth, range: 0...7) { try operatorData.settingKeyboardRateScalingDepth($0) }
            }
        }
    }

    private var carrierBinding: Binding<Bool> {
        Binding(
            get: { operatorData.carrier },
            set: { value in
                if let updated = try? operatorData.settingCarrier(value) {
                    updateOperator(updated)
                }
            }
        )
    }

    private var keyboardLevelScalingTypeBit0Binding: Binding<Bool> {
        Binding(
            get: { operatorData.keyboardLevelScalingTypeBit0 },
            set: { value in
                if let updated = try? operatorData.settingKeyboardLevelScalingTypeBit0(value) {
                    updateOperator(updated)
                }
            }
        )
    }

    private var keyboardLevelScalingTypeBit1Binding: Binding<Bool> {
        Binding(
            get: { operatorData.keyboardLevelScalingTypeBit1 },
            set: { value in
                if let updated = try? operatorData.settingKeyboardLevelScalingTypeBit1(value) {
                    updateOperator(updated)
                }
            }
        )
    }

    private func operatorStepper(
        _ label: String,
        value: Int,
        range: ClosedRange<Int>,
        update: @escaping (Int) throws -> FB01VoiceOperatorData
    ) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Stepper(value: Binding(
                get: { value },
                set: { newValue in
                    if let updated = try? update(newValue) {
                        updateOperator(updated)
                    }
                }
            ), in: range) {
                Text("\(value)")
                    .frame(minWidth: 34, alignment: .trailing)
                    .monospacedDigit()
            }
        }
    }

    private func operatorToggle(_ label: String, binding: Binding<Bool>) -> some View {
        Toggle(label, isOn: binding)
            .toggleStyle(.checkbox)
    }
}

struct OperatorControlGroup<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                content
            }
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            SectionTitle(title)
        }
    }
}

struct InstrumentTable: View {
    var instruments: [FB01InstrumentConfiguration]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Instruments")

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
        case .deviceStatus: "Device Status"
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

private extension Int {
    var lfoWaveformDisplayName: String {
        switch self {
        case 0: "Saw"
        case 1: "Square"
        case 2: "Triangle"
        case 3: "Random"
        default: "Unknown"
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

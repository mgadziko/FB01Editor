import AppKit
import Combine
import FB01Editor
import SwiftUI

enum SidebarSelection: Equatable {
    case system
    case source
}

enum ActiveEditorDocumentKind {
    case voice
    case configuration
}

struct ActiveEditorDocumentActions {
    var kind: ActiveEditorDocumentKind
    var save: () -> Void
    var saveTitle: String
    var saveAs: () -> Void
    var saveAsTitle: String
    var reset: () -> Void
    var importFromDisk: () -> Void
    var importFromDiskTitle: String
    var importFromLibrary: (DocumentModel) -> Void
    var canImportFromLibrary: (DocumentModel) -> Bool
    var importFromLibraryTitle: String
    var fetchFromDevice: (DocumentModel) -> Void
    var fetchFromDeviceTitle: String
    var storeToDevice: (DocumentModel) -> Void
    var storeToDeviceTitle: String
    var isEdited: Bool
    var isBusy: Bool
}

private struct ActiveEditorDocumentActionsKey: FocusedValueKey {
    typealias Value = ActiveEditorDocumentActions
}

private struct ActiveVoiceBankSelectorKey: FocusedValueKey {
    typealias Value = Int
}

extension FocusedValues {
    var activeEditorDocumentActions: ActiveEditorDocumentActions? {
        get { self[ActiveEditorDocumentActionsKey.self] }
        set { self[ActiveEditorDocumentActionsKey.self] = newValue }
    }

    var activeVoiceBankSelector: Int? {
        get { self[ActiveVoiceBankSelectorKey.self] }
        set { self[ActiveVoiceBankSelectorKey.self] = newValue }
    }
}

private func isDX100VoiceBankFile(_ url: URL) -> Bool {
    let ext = url.pathExtension.lowercased()
    return ext == DX100SynthModule.shared.fileProfile.voiceBankExtension
}

struct EditorDocumentCommands: View {
    @ObservedObject var document: DocumentModel
    @ObservedObject var workspace: EditorDocumentWorkspace
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.activeEditorDocumentActions) private var activeDocumentActions
    @FocusedValue(\.activeVoiceBankSelector) private var activeVoiceBankSelector

    private var canSaveFocusedDocumentOrLibrary: Bool {
        if let activeDocumentActions {
            return !activeDocumentActions.isBusy
        }
        return document.hasDocument && !document.isBusy
    }

    private var canSaveFocusedDocumentOrLibraryAs: Bool {
        canSaveFocusedDocumentOrLibrary
    }

    private var loadVoiceBankFromFileTitle: String {
        switch document.selectedEditorDevice {
        case .dx100:
            return "Load DX100/27 Voice Bank File..."
        default:
            return "Load Voice Bank from File..."
        }
    }

    private var selectedDeviceSupportsConfigurations: Bool {
        switch document.selectedEditorDevice {
        case .fb01:
            return FB01ModuleServices.shared.module.capabilities.supportsConfigurations
        case .dx100:
            return DX100ModuleServices.shared.module.capabilities.supportsConfigurations
        case nil:
            return true
        }
    }

    var body: some View {
        Button("New Voice Document") {
            let id = workspace.createVoiceDocument()
            openWindow(id: "voice-document", value: id)
        }
        .keyboardShortcut("n", modifiers: .command)

        if selectedDeviceSupportsConfigurations {
            Button("New Configuration Document") {
                let id = workspace.createConfigurationDocument()
                openWindow(id: "configuration-document", value: id)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }

        Divider()

        Button("New Voice Document from Selected Library Voice") {
            if let payload = document.selectedVoiceDocumentPayload() {
                let id = workspace.createVoiceDocument(
                    voice: payload.voice,
                    systemChannel: payload.systemChannel,
                    statusMessage: "Created from selected library voice."
                )
                openWindow(id: "voice-document", value: id)
            }
        }
        .disabled(!document.canOpenSelectedVoiceAsDocument)

        if selectedDeviceSupportsConfigurations {
            Button("New Configuration Document from Selected Library Configuration") {
                if let payload = document.selectedConfigurationDocumentPayload() {
                    let id = workspace.createConfigurationDocument(
                        configuration: payload.configuration,
                        systemChannel: payload.systemChannel,
                        statusMessage: "Created from selected library configuration."
                    )
                    openWindow(id: "configuration-document", value: id)
                }
            }
            .disabled(!document.canOpenSelectedConfigurationAsDocument)
        }

        Divider()

        Button("Load Voice from File...") {
            if let id = workspace.loadVoiceDocument(preferredDevice: document.selectedEditorDevice) {
                if let url = workspace.voiceDocument(id: id)?.fileURL {
                    document.rememberRecentLoadedVoiceFile(url)
                }
                openWindow(id: "voice-document", value: id)
            }
        }
        .keyboardShortcut("o", modifiers: [.command, .option])

        Button(loadVoiceBankFromFileTitle) {
            if document.selectedEditorDevice == .dx100 {
                if let id = workspace.loadDX100VoiceBankFileSelector() {
                    if let selector = workspace.dx100VoiceBankFileSelector(id: id) {
                        document.rememberRecentLoadedVoiceFile(selector.fileURL)
                    }
                    openWindow(id: "dx100-voice-bank-file-selector", value: id)
                }
            } else if let id = workspace.loadVoiceDocumentFromBankFile(preferredDevice: document.selectedEditorDevice) {
                if let url = workspace.voiceDocument(id: id)?.fileURL {
                    document.rememberRecentLoadedVoiceFile(url)
                }
                openWindow(id: "voice-document", value: id)
            }
        }

        Menu("Load Recent Voice") {
            if document.recentLoadedVoiceFiles.isEmpty {
                Text("No Recent Voices")
            } else {
                ForEach(document.recentLoadedVoiceFiles) { item in
                    Button(item.title) {
                        openRecentVoice(item)
                    }
                    .help(item.path)
                }
            }
        }

        if document.selectedEditorDevice == .dx100 {
            Button("Save Bank to File...") {
                if let sourceBank = activeVoiceBankSelector {
                    document.saveDX100VoiceBankFromSelector(bank: sourceBank)
                }
            }
            .disabled(document.isBusy || activeVoiceBankSelector == nil)
        }

        if selectedDeviceSupportsConfigurations {
            Divider()

            Button("Load Configuration from File...") {
                if let id = workspace.loadConfigurationDocument() {
                    if let configurationDocument = workspace.configurationDocument(id: id),
                       let url = configurationDocument.fileURL {
                        document.rememberRecentLoadedConfigurationFile(url)
                        Task { @MainActor in
                            await document.prefetchConfigurationVoiceNames(
                                for: configurationDocument.configuration,
                                configurationDocument: configurationDocument,
                                reason: "Loaded \(url.lastPathComponent)"
                            )
                        }
                    }
                    openWindow(id: "configuration-document", value: id)
                }
            }
            .keyboardShortcut("o", modifiers: [.command, .option, .shift])

            Menu("Load Recent Configuration") {
                if document.recentLoadedConfigurationFiles.isEmpty {
                    Text("No Recent Configurations")
                } else {
                    ForEach(document.recentLoadedConfigurationFiles) { item in
                        Button(item.title) {
                            openRecentConfiguration(item)
                        }
                        .help(item.path)
                    }
                }
            }
        }

        Divider()

        Button(activeDocumentActions?.importFromDiskTitle ?? "Import from File into Current Document...") {
            activeDocumentActions?.importFromDisk()
        }
        .disabled(activeDocumentActions == nil || activeDocumentActions?.isBusy == true)

        Button(activeDocumentActions?.importFromLibraryTitle ?? "Import Selected Library Item Into Current Document") {
            activeDocumentActions?.importFromLibrary(document)
        }
        .disabled(activeDocumentActions == nil || activeDocumentActions?.isBusy == true || activeDocumentActions?.canImportFromLibrary(document) != true)

        Divider()

        Button(activeDocumentActions?.saveTitle ?? "Save Library to File...") {
            if let activeDocumentActions {
                activeDocumentActions.save()
            } else {
                document.saveSysEx()
            }
        }
        .keyboardShortcut("s", modifiers: .command)
        .disabled(!canSaveFocusedDocumentOrLibrary)

        Button(activeDocumentActions?.saveAsTitle ?? "Save Library to File As...") {
            if let activeDocumentActions {
                activeDocumentActions.saveAs()
            } else {
                document.saveSysEx()
            }
        }
        .keyboardShortcut("s", modifiers: [.command, .shift])
        .disabled(!canSaveFocusedDocumentOrLibraryAs)

        Button("Revert Document") {
            activeDocumentActions?.reset()
        }
        .disabled(activeDocumentActions?.isEdited != true || activeDocumentActions?.isBusy == true)

        Divider()
    }

    private func openRecentVoice(_ item: RecentEditorFile) {
        if isDX100VoiceBankFile(item.url) {
            if let id = workspace.loadDX100VoiceBankFileSelector(from: item.url) {
                document.rememberRecentLoadedVoiceFile(item.url)
                openWindow(id: "dx100-voice-bank-file-selector", value: id)
            }
        } else if let id = workspace.loadVoiceDocument(from: item.url) {
            document.rememberRecentLoadedVoiceFile(item.url)
            openWindow(id: "voice-document", value: id)
        }
    }

    private func openRecentConfiguration(_ item: RecentEditorFile) {
        if let id = workspace.loadConfigurationDocument(from: item.url) {
            document.rememberRecentLoadedConfigurationFile(item.url)
            openWindow(id: "configuration-document", value: id)
            if let configurationDocument = workspace.configurationDocument(id: id) {
                Task { @MainActor in
                    await document.prefetchConfigurationVoiceNames(
                        for: configurationDocument.configuration,
                        configurationDocument: configurationDocument,
                        reason: "Loaded \(item.title)"
                    )
                }
            }
        }
    }
}

struct VoiceDocumentDeviceCommands: View {
    @ObservedObject var document: DocumentModel
    @ObservedObject var workspace: EditorDocumentWorkspace
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.activeEditorDocumentActions) private var activeDocumentActions

    var body: some View {
        if document.selectedDeviceHasConnectedVoiceDocumentCommands {
            Button(document.selectedDeviceVoiceFetchCommandTitle) {
                let id = workspace.createVoiceDocument()
                openWindow(id: "voice-document", value: id)
                Task { @MainActor in
                    await Task.yield()
                    workspace.voiceDocument(id: id)?.fetchFromDevice(device: document)
                }
            }
            .disabled(document.isBusy)

            Menu("Fetch Cached Voice") {
                let cachedItems = document.recentFetchedVoices.filter { document.canUseCachedVoiceFetch($0) }
                if cachedItems.isEmpty {
                    Text("No Cached Voice Fetches")
                } else {
                    ForEach(cachedItems) { item in
                        Button(item.title) {
                            fetchRecentVoice(item, mode: .cacheOnly)
                        }
                        .disabled(document.isBusy)
                    }
                }
            }

            if document.selectedEditorDevice == .dx100 {
                Menu("Fetch Voice Manually") {
                    let manualItems = document.recentFetchedVoices.filter { document.canUseDX100ManualVoiceFetch($0) }
                    if manualItems.isEmpty {
                        Text("No Manual DX Voice Fetches")
                    } else {
                        ForEach(manualItems) { item in
                            Button(item.title) {
                                fetchRecentVoice(item, mode: .manualAssist)
                            }
                            .disabled(document.isBusy)
                        }
                    }
                }
            }

            Button(activeDocumentActions?.fetchFromDeviceTitle ?? document.selectedDeviceVoiceFetchIntoDocumentTitle) {
                activeDocumentActions?.fetchFromDevice(document)
            }
            .disabled(activeDocumentActions?.kind != .voice || activeDocumentActions?.isBusy == true || document.isBusy)

            Button(activeDocumentActions?.storeToDeviceTitle ?? document.selectedDeviceVoiceStoreCommandTitle) {
                activeDocumentActions?.storeToDevice(document)
            }
            .disabled(activeDocumentActions?.kind != .voice || activeDocumentActions?.isBusy == true || document.isBusy)
        } else {
            Text(document.selectedEditorDevice == nil ? "Select a device first." : "\(document.selectedEditorDevice?.displayName ?? "This device") voice document commands are not connected yet.")
        }
    }

    private func fetchRecentVoice(_ item: RecentVoiceFetch, mode: VoiceFetchExecutionMode) {
        guard let source = item.source else {
            return
        }

        if mode == .cacheOnly,
           !document.canUseCachedVoiceFetch(item) {
            document.errorMessage = "Cached fetch unavailable for \(item.title). Show the bank first or fetch the voice manually."
            document.statusMessage = nil
            return
        }

        if mode == .manualAssist,
           !document.canUseDX100ManualVoiceFetch(item) {
            document.errorMessage = "Manual DX fetch is available only for Bank A-D voices that Forest can step through one voice at a time."
            document.statusMessage = nil
            return
        }

        let id = workspace.createVoiceDocument()
        openWindow(id: "voice-document", value: id)
        Task { @MainActor in
            await Task.yield()
            workspace.voiceDocument(id: id)?.fetchFromDevice(
                device: document,
                source: source,
                recentTitle: item.title,
                mode: mode
            )
        }
    }
}

struct ConfigurationDocumentDeviceCommands: View {
    @ObservedObject var document: DocumentModel
    @ObservedObject var workspace: EditorDocumentWorkspace
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.activeEditorDocumentActions) private var activeDocumentActions

    var body: some View {
        Button("Fetch Configuration from Device...") {
            let id = workspace.createConfigurationDocument()
            openWindow(id: "configuration-document", value: id)
            Task { @MainActor in
                await Task.yield()
                workspace.configurationDocument(id: id)?.fetchFromDevice(device: document)
            }
        }
        .disabled(document.isBusy)

        Menu("Fetch Recent Configuration") {
            if document.recentFetchedConfigurations.isEmpty {
                Text("No Recent Configuration Fetches")
            } else {
                ForEach(document.recentFetchedConfigurations) { item in
                    Button(item.title) {
                        fetchRecentConfiguration(item)
                    }
                    .disabled(document.isBusy)
                }
            }
        }

        Button(activeDocumentActions?.fetchFromDeviceTitle ?? "Fetch Configuration from Device into Current Document...") {
            activeDocumentActions?.fetchFromDevice(document)
        }
        .disabled(activeDocumentActions?.kind != .configuration || activeDocumentActions?.isBusy == true || document.isBusy)

        Button(activeDocumentActions?.storeToDeviceTitle ?? "Store Configuration to Device Slot...") {
            activeDocumentActions?.storeToDevice(document)
        }
        .disabled(activeDocumentActions?.kind != .configuration || activeDocumentActions?.isBusy == true || document.isBusy)
    }

    private func fetchRecentConfiguration(_ item: RecentConfigurationFetch) {
        let id = workspace.createConfigurationDocument()
        openWindow(id: "configuration-document", value: id)
        Task { @MainActor in
            await Task.yield()
            workspace.configurationDocument(id: id)?.fetchFromDevice(device: document, options: item.options, recentTitle: item.title)
        }
    }
}

@MainActor
final class EditorDocumentWorkspace: ObservableObject {
    struct DX100VoiceBankFileSelector: Identifiable {
        struct Item: Identifiable {
            let id = UUID()
            let displayNumber: Int
            let candidate: DX100VoiceDocumentCandidate

            var title: String {
                candidate.voice.name.isEmpty ? "Voice \(displayNumber)" : candidate.voice.name
            }
        }

        let id: UUID
        let fileURL: URL
        let title: String
        let items: [Item]
    }

    @Published private(set) var voiceDocuments: [UUID: VoiceDocumentModel] = [:]
    @Published private(set) var configurationDocuments: [UUID: ConfigurationDocumentModel] = [:]
    @Published private(set) var dx100VoiceBankFileSelectors: [UUID: DX100VoiceBankFileSelector] = [:]
    private var voiceDocumentObservers: [UUID: AnyCancellable] = [:]
    private var configurationDocumentObservers: [UUID: AnyCancellable] = [:]

    func createVoiceDocument(voice: FB01VoiceData = EditorDocumentTemplates.voice(), systemChannel: Int = 0, statusMessage: String? = nil) -> UUID {
        let document = VoiceDocumentModel(voice: voice, systemChannel: systemChannel)
        document.statusMessage = statusMessage
        insertVoiceDocument(document)
        return document.id
    }

    func createConfigurationDocument(configuration: FB01ConfigurationData = EditorDocumentTemplates.configuration(), systemChannel: Int = 0, statusMessage: String? = nil) -> UUID {
        let document = ConfigurationDocumentModel(configuration: configuration, systemChannel: systemChannel)
        document.statusMessage = statusMessage
        insertConfigurationDocument(document)
        return document.id
    }

    func loadVoiceDocument(preferredDevice: EditorDeviceSelection? = nil) -> UUID? {
        guard let loaded = VoiceDocumentModel.loadFromDisk(preferredDevice: preferredDevice) else {
            return nil
        }
        insertVoiceDocument(loaded)
        return loaded.id
    }

    func loadVoiceDocumentFromBankFile(preferredDevice: EditorDeviceSelection? = nil) -> UUID? {
        guard let loaded = VoiceDocumentModel.loadFromBankFile(preferredDevice: preferredDevice) else {
            return nil
        }
        insertVoiceDocument(loaded)
        return loaded.id
    }

    func loadDX100VoiceBankFileSelector() -> UUID? {
        guard let loaded = VoiceDocumentModel.loadDX100BankFile() else {
            return nil
        }
        return insertDX100VoiceBankFileSelector(loaded)
    }

    func loadVoiceDocument(from url: URL) -> UUID? {
        guard let loaded = VoiceDocumentModel.loadFromDisk(url: url) else {
            return nil
        }
        insertVoiceDocument(loaded)
        return loaded.id
    }

    func loadDX100VoiceBankFileSelector(from url: URL) -> UUID? {
        guard let loaded = VoiceDocumentModel.loadDX100BankFile(from: url) else {
            return nil
        }
        return insertDX100VoiceBankFileSelector(loaded)
    }

    func loadConfigurationDocument() -> UUID? {
        guard let loaded = ConfigurationDocumentModel.loadFromDisk() else {
            return nil
        }
        insertConfigurationDocument(loaded)
        return loaded.id
    }

    func loadConfigurationDocument(from url: URL) -> UUID? {
        guard let loaded = ConfigurationDocumentModel.loadFromDisk(url: url) else {
            return nil
        }
        insertConfigurationDocument(loaded)
        return loaded.id
    }

    func voiceDocument(id: UUID) -> VoiceDocumentModel? {
        voiceDocuments[id]
    }

    func configurationDocument(id: UUID) -> ConfigurationDocumentModel? {
        configurationDocuments[id]
    }

    func dx100VoiceBankFileSelector(id: UUID) -> DX100VoiceBankFileSelector? {
        dx100VoiceBankFileSelectors[id]
    }

    func closeVoiceDocument(id: UUID) {
        voiceDocuments[id] = nil
        voiceDocumentObservers[id] = nil
    }

    func closeConfigurationDocument(id: UUID) {
        configurationDocuments[id] = nil
        configurationDocumentObservers[id] = nil
    }

    func closeDX100VoiceBankFileSelector(id: UUID) {
        dx100VoiceBankFileSelectors[id] = nil
    }

    private func insertVoiceDocument(_ document: VoiceDocumentModel) {
        voiceDocumentObservers[document.id] = document.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        voiceDocuments[document.id] = document
    }

    func createVoiceDocument(fromDX100Candidate candidate: DX100VoiceDocumentCandidate) -> UUID? {
        do {
            let loaded = LoadedVoiceDocument(
                projection: try candidate.voice.fb01EditableVoice(),
                neutralVoice: candidate.voice.fourOperatorVoice,
                systemChannel: candidate.channel,
                sourceDevice: .dx100
            )
            let document = VoiceDocumentModel(loadedDocument: loaded, fileURL: nil)
            insertVoiceDocument(document)
            return document.id
        } catch {
            showEditorError(title: "Open DX100/27 Voice Failed", message: "\(error)")
            return nil
        }
    }

    private func insertConfigurationDocument(_ document: ConfigurationDocumentModel) {
        configurationDocumentObservers[document.id] = document.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        configurationDocuments[document.id] = document
    }

    private func insertDX100VoiceBankFileSelector(_ loaded: LoadedDX100VoiceBankFile) -> UUID {
        let id = UUID()
        let items = loaded.candidates.enumerated().map { index, candidate in
            DX100VoiceBankFileSelector.Item(displayNumber: index + 1, candidate: candidate)
        }
        dx100VoiceBankFileSelectors[id] = DX100VoiceBankFileSelector(
            id: id,
            fileURL: loaded.fileURL,
            title: loaded.title,
            items: items
        )
        return id
    }

    func confirmApplicationTermination() -> NSApplication.TerminateReply {
        let editedVoices = voiceDocuments
            .filter { $0.value.isEdited }
            .sorted { $0.value.title.localizedStandardCompare($1.value.title) == .orderedAscending }
        let editedConfigurations = configurationDocuments
            .filter { $0.value.isEdited }
            .sorted { $0.value.title.localizedStandardCompare($1.value.title) == .orderedAscending }

        for (id, document) in editedVoices {
            bringWindowToFront(identifier: Self.voiceWindowIdentifier(for: id))
            guard confirmTermination(for: document.title, save: { document.save() }, isEdited: { document.isEdited }) else {
                return .terminateCancel
            }
        }
        for (id, document) in editedConfigurations {
            bringWindowToFront(identifier: Self.configurationWindowIdentifier(for: id))
            guard confirmTermination(for: document.title, save: { document.save() }, isEdited: { document.isEdited }) else {
                return .terminateCancel
            }
        }
        return .terminateNow
    }

    private func confirmTermination(for title: String, save: () -> Void, isEdited: () -> Bool) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Save Changes to \(title.replacingOccurrences(of: " *", with: ""))?"
        alert.informativeText = "This document has unsaved changes."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Discard Changes")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            save()
            return !isEdited()
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    static func voiceWindowIdentifier(for id: UUID) -> String {
        "voice-document-\(id.uuidString)"
    }

    static func configurationWindowIdentifier(for id: UUID) -> String {
        "configuration-document-\(id.uuidString)"
    }

    static func voiceBankSelectorWindowIdentifier(for bank: Int) -> String {
        "voice-bank-selector-\(bank)"
    }

    static func dx100VoiceBankFileSelectorWindowIdentifier(for id: UUID) -> String {
        "dx100-voice-bank-file-selector-\(id.uuidString)"
    }

    static var configurationBankSelectorWindowIdentifier: String {
        "configuration-bank-selector"
    }

    @discardableResult
    func bringWindowToFront(identifier: String) -> Bool {
        guard let window = NSApp.windows.first(where: { $0.identifier?.rawValue == identifier }) else {
            return false
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        return true
    }
}

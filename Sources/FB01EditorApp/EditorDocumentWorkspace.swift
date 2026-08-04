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

struct EditorDocumentCommands: View {
    @ObservedObject var document: DocumentModel
    @ObservedObject var workspace: EditorDocumentWorkspace
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.activeEditorDocumentActions) private var activeDocumentActions

    private var canSaveFocusedDocumentOrLibrary: Bool {
        if let activeDocumentActions {
            return !activeDocumentActions.isBusy
        }
        return document.hasDocument && !document.isBusy
    }

    private var canSaveFocusedDocumentOrLibraryAs: Bool {
        canSaveFocusedDocumentOrLibrary
    }

    var body: some View {
        Button("New Voice Document") {
            let id = workspace.createVoiceDocument()
            openWindow(id: "voice-document", value: id)
        }
        .keyboardShortcut("n", modifiers: .command)

        Button("New Configuration Document") {
            let id = workspace.createConfigurationDocument()
            openWindow(id: "configuration-document", value: id)
        }
        .keyboardShortcut("n", modifiers: [.command, .shift])

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

        Divider()

        Button("Load Voice from File...") {
            if let id = workspace.loadVoiceDocument() {
                if let url = workspace.voiceDocument(id: id)?.fileURL {
                    document.rememberRecentLoadedVoiceFile(url)
                }
                openWindow(id: "voice-document", value: id)
            }
        }
        .keyboardShortcut("o", modifiers: [.command, .option])

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
        if let id = workspace.loadVoiceDocument(from: item.url) {
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
        Button("Fetch Voice from Device...") {
            let id = workspace.createVoiceDocument()
            openWindow(id: "voice-document", value: id)
            Task { @MainActor in
                await Task.yield()
                workspace.voiceDocument(id: id)?.fetchFromDevice(device: document)
            }
        }
        .disabled(document.isBusy)

        Menu("Fetch Recent Voice") {
            if document.recentFetchedVoices.isEmpty {
                Text("No Recent Voice Fetches")
            } else {
                ForEach(document.recentFetchedVoices) { item in
                    Button(item.title) {
                        fetchRecentVoice(item)
                    }
                    .disabled(document.isBusy || item.source == nil)
                }
            }
        }

        Button(activeDocumentActions?.fetchFromDeviceTitle ?? "Fetch Voice from Device into Current Document...") {
            activeDocumentActions?.fetchFromDevice(document)
        }
        .disabled(activeDocumentActions?.kind != .voice || activeDocumentActions?.isBusy == true || document.isBusy)

        Button(activeDocumentActions?.storeToDeviceTitle ?? "Store Voice to Device Slot...") {
            activeDocumentActions?.storeToDevice(document)
        }
        .disabled(activeDocumentActions?.kind != .voice || activeDocumentActions?.isBusy == true || document.isBusy)
    }

    private func fetchRecentVoice(_ item: RecentVoiceFetch) {
        guard let source = item.source else {
            return
        }
        let id = workspace.createVoiceDocument()
        openWindow(id: "voice-document", value: id)
        Task { @MainActor in
            await Task.yield()
            workspace.voiceDocument(id: id)?.fetchFromDevice(device: document, source: source, recentTitle: item.title)
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
    @Published private(set) var voiceDocuments: [UUID: VoiceDocumentModel] = [:]
    @Published private(set) var configurationDocuments: [UUID: ConfigurationDocumentModel] = [:]
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

    func loadVoiceDocument() -> UUID? {
        guard let loaded = VoiceDocumentModel.loadFromDisk() else {
            return nil
        }
        insertVoiceDocument(loaded)
        return loaded.id
    }

    func loadVoiceDocument(from url: URL) -> UUID? {
        guard let loaded = VoiceDocumentModel.loadFromDisk(url: url) else {
            return nil
        }
        insertVoiceDocument(loaded)
        return loaded.id
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

    func closeVoiceDocument(id: UUID) {
        voiceDocuments[id] = nil
        voiceDocumentObservers[id] = nil
    }

    func closeConfigurationDocument(id: UUID) {
        configurationDocuments[id] = nil
        configurationDocumentObservers[id] = nil
    }

    private func insertVoiceDocument(_ document: VoiceDocumentModel) {
        voiceDocumentObservers[document.id] = document.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        voiceDocuments[document.id] = document
    }

    private func insertConfigurationDocument(_ document: ConfigurationDocumentModel) {
        configurationDocumentObservers[document.id] = document.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        configurationDocuments[document.id] = document
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

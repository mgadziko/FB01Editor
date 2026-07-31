import AppKit
import Combine
import FB01Editor
import Foundation
import UniformTypeIdentifiers

@MainActor
final class ConfigurationDocumentModel: ObservableObject, Identifiable {
    let id = UUID()
    @Published var configuration: FB01ConfigurationData
    @Published var savedConfiguration: FB01ConfigurationData
    @Published var systemChannel: Int
    @Published var fileURL: URL?
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    @Published var isBusy = false

    init(configuration: FB01ConfigurationData, systemChannel: Int, fileURL: URL? = nil) {
        self.configuration = configuration
        self.savedConfiguration = configuration
        self.systemChannel = systemChannel
        self.fileURL = fileURL
    }

    var title: String {
        let name = configuration.name.isEmpty ? "Untitled Configuration" : configuration.name
        if isBusy {
            return "\(name) (Working)"
        }
        return isEdited ? "\(name) *" : name
    }

    var isEdited: Bool {
        configuration != savedConfiguration
    }

    func reset() {
        configuration = savedConfiguration
        errorMessage = nil
        statusMessage = "Reverted to last saved version."
    }

    func updateConfiguration(_ edit: (FB01ConfigurationData) throws -> FB01ConfigurationData) {
        do {
            let editedConfiguration = try edit(configuration)
            guard editedConfiguration != configuration else { return }
            configuration = editedConfiguration
            errorMessage = nil
            statusMessage = nil
        } catch {
            errorMessage = "Edit failed: \(error)"
        }
    }

    func setName(_ value: String) {
        let limited = String(value.prefix(FB01ConfigurationData.nameLength))
        guard limited != configuration.name else { return }
        updateConfiguration { try $0.settingName(limited) }
    }

    func save() {
        if let fileURL {
            save(to: fileURL)
        } else {
            saveAs()
        }
    }

    func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = UTType.fb01ConfigurationFileTypes
        panel.directoryURL = preferredEditorSaveDirectoryURL()
        panel.nameFieldStringValue = "\(safeEditorFileName(configuration.name, fallback: "configuration")).fb01config"
        panel.message = "Save this configuration document to a configuration file."
        panel.prompt = "Save Configuration to File"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        save(to: url)
    }

    static func loadFromDisk() -> ConfigurationDocumentModel? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = UTType.fb01ReadableConfigurationFileTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = preferredEditorLoadDirectoryURL()
        panel.message = "Load a configuration file into a new configuration document window."
        panel.prompt = "Load Configuration from File"

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        do {
            let (configuration, systemChannel) = try readConfiguration(from: url)
            rememberEditorLoadDirectory(for: url)
            return ConfigurationDocumentModel(configuration: configuration, systemChannel: systemChannel, fileURL: url)
        } catch {
            showEditorError(title: "Load Configuration Failed", message: "\(error)")
            return nil
        }
    }

    static func loadFromDisk(url: URL) -> ConfigurationDocumentModel? {
        do {
            let (configuration, systemChannel) = try readConfiguration(from: url)
            rememberEditorLoadDirectory(for: url)
            return ConfigurationDocumentModel(configuration: configuration, systemChannel: systemChannel, fileURL: url)
        } catch {
            showEditorError(title: "Load Configuration Failed", message: "\(error)")
            return nil
        }
    }

    func importFromDisk() {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = UTType.fb01ReadableConfigurationFileTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = preferredEditorLoadDirectoryURL()
        panel.message = "Import a configuration file into this configuration document, replacing its current contents."
        panel.prompt = "Import Configuration from File"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let (importedConfiguration, importedSystemChannel) = try Self.readConfiguration(from: url)
            configuration = importedConfiguration
            savedConfiguration = importedConfiguration
            systemChannel = importedSystemChannel
            fileURL = url
            rememberEditorLoadDirectory(for: url)
            statusMessage = "Imported \(url.lastPathComponent)."
            errorMessage = nil
        } catch {
            errorMessage = "Import failed: \(error)"
            statusMessage = nil
        }
    }

    func fetchFromDevice(device: DocumentModel, options preselectedOptions: ConfigurationFetchOptions? = nil, recentTitle: String? = nil) {
        guard !isBusy else { return }
        let sourceIndex = device.selectedSourceIndex
        let destinationIndex = device.selectedDestinationIndex
        let systemChannel = device.systemChannel

        isBusy = true
        errorMessage = nil
        statusMessage = preselectedOptions == nil
            ? "Reading configuration names from FB-01..."
            : "Fetching \(recentTitle ?? "recent configuration") from FB-01..."

        Task {
            let nameLookup: ConfigurationFetchNameLookup
            if preselectedOptions == nil {
                let cachedLookup = device.configurationNameLookupFromCache()
                if !cachedLookup.storedNames.isEmpty {
                    nameLookup = cachedLookup
                    statusMessage = "Configuration names loaded from device cache."
                } else {
                    let progressPanel = EditorProgressPanel(
                        title: "Reading Configuration Names",
                        message: "Reading writable configuration names from the FB-01 so the Fetch dialog can show current slot names."
                    )
                    progressPanel.show()
                    nameLookup = await Task.detached(priority: .userInitiated) {
                        Self.fetchConfigurationNames(
                            sourceIndex: sourceIndex,
                            destinationIndex: destinationIndex,
                            systemChannel: systemChannel
                        )
                    }.value
                    progressPanel.dismiss()
                }
            } else {
                nameLookup = device.configurationNameLookupFromCache()
            }

            let options: ConfigurationFetchOptions
            if let preselectedOptions {
                options = preselectedOptions
            } else {
                guard let chosenOptions = Self.chooseFetchOptions(
                    title: "Fetch Configuration from Device into Current Document",
                    actionTitle: "Fetch",
                    nameLookup: nameLookup
                ) else {
                    statusMessage = nil
                    isBusy = false
                    return
                }
                options = chosenOptions
            }

            statusMessage = "Fetching configuration from FB-01; waiting for device response..."
            let fetchTitle = recentTitle ?? (options.isCurrent ? "Current Configuration" : nameLookup.menuTitle(slot: options.slot + 1))
            if let cachedConfiguration = device.cachedConfigurationFetchResult(options: options) {
                configuration = cachedConfiguration
                savedConfiguration = cachedConfiguration
                self.systemChannel = systemChannel
                fileURL = nil
                let voiceNameStatus = await device.prefetchConfigurationVoiceNames(
                    for: cachedConfiguration,
                    configurationDocument: self,
                    reason: "Fetched cached \(fetchTitle)"
                )
                statusMessage = if let voiceNameStatus {
                    "Fetched cached \(fetchTitle) into this document. \(voiceNameStatus)"
                } else {
                    "Fetched cached \(fetchTitle) into this document."
                }
                device.rememberRecentFetchedConfiguration(options, title: fetchTitle)
                errorMessage = nil
                isBusy = false
                return
            }
            let fetchProgressPanel = EditorProgressPanel(
                title: "Fetching Configuration",
                message: "The configuration is being fetched. Please wait.\nReading \(fetchTitle) from the FB-01..."
            )
            fetchProgressPanel.show()
            do {
                let kind: FB01MIDIRequestKind = options.isCurrent ? .currentConfiguration : .configuration(options.slot + 1)
                let result = try await Task.detached(priority: .userInitiated) { () -> (FB01ConfigurationData, Int) in
                    let bytes = try FB01MIDI.request(
                        kind,
                        sourceIndex: sourceIndex,
                        destinationIndex: destinationIndex,
                        systemChannel: systemChannel,
                        timeout: 8
                    )
                    let artifact = try FB01Artifact(sysexBytes: bytes)
                    return try Self.extractConfiguration(from: artifact)
                }.value
                configuration = result.0
                savedConfiguration = result.0
                self.systemChannel = result.1
                fileURL = nil
                let voiceNameStatus = await device.prefetchConfigurationVoiceNames(
                    for: result.0,
                    configurationDocument: self,
                    reason: "Fetched \(fetchTitle)",
                    progressPanel: fetchProgressPanel
                )
                statusMessage = if let voiceNameStatus {
                    "Fetched \(fetchTitle) into this document. \(voiceNameStatus)"
                } else {
                    "Fetched \(fetchTitle) into this document."
                }
                device.rememberRecentFetchedConfiguration(options, title: fetchTitle)
                errorMessage = nil
            } catch {
                errorMessage = "Fetch failed: \(error)"
                statusMessage = nil
            }
            fetchProgressPanel.dismiss()
            isBusy = false
        }
    }

    func importFromLibrary(device: DocumentModel) {
        guard !isBusy else { return }
        guard let payload = device.selectedConfigurationDocumentPayload() else {
            errorMessage = "Import failed: no selected library configuration."
            statusMessage = nil
            return
        }
        configuration = payload.configuration
        savedConfiguration = payload.configuration
        systemChannel = payload.systemChannel
        fileURL = nil
        statusMessage = "Imported selected library configuration into this document."
        errorMessage = nil
    }

    func storeToDevice(device: DocumentModel) {
        guard !isBusy else { return }
        guard let options = Self.chooseStoreOptions(defaultConfigurationName: configuration.name) else {
            return
        }

        let configurationToStore = configuration
        let destinationIndex = device.selectedDestinationIndex
        let sourceIndex = device.selectedSourceIndex
        let systemChannel = device.systemChannel
        let destinationName = device.selectedDestinationName
        isBusy = true
        statusMessage = "Storing configuration to slot \(options.slot + 1)..."
        errorMessage = nil
        let progressPanel = EditorProgressPanel(
            title: "Store Configuration",
            message: "The configuration is being stored. Please wait.\nPreparing configuration \(options.slot + 1)...",
            showsCancelButton: true
        )
        progressPanel.show()

        var operationTask: Task<Void, Never>?
        progressPanel.onCancel = {
            operationTask?.cancel()
        }

        operationTask = Task {
            do {
                let messages = try Self.storeMessages(
                    configuration: configurationToStore,
                    systemChannel: systemChannel,
                    slot: options.slot
                )
                progressPanel.update(message: "The configuration is being stored. Please wait.\nTurning FB-01 Protect OFF...")
                try await Task.detached(priority: .userInitiated) {
                    try FB01MIDI.sendSysEx([messages[0]], destinationIndex: destinationIndex, delayBetweenMessages: 0)
                    try await Task.sleep(for: .milliseconds(300))
                }.value
                try Task.checkCancellation()

                progressPanel.update(message: "The configuration is being stored. Please wait.\nSending configuration data...")
                try await Task.detached(priority: .userInitiated) {
                    try FB01MIDI.sendSysEx([messages[1]], destinationIndex: destinationIndex, delayBetweenMessages: 0)
                    try await Task.sleep(for: .milliseconds(1000))
                }.value
                try Task.checkCancellation()

                progressPanel.update(message: "The configuration is being stored. Please wait.\nStoring configuration \(options.slot + 1) on the FB-01...")
                try await Task.detached(priority: .userInitiated) {
                    try FB01MIDI.sendSysEx([messages[2]], destinationIndex: destinationIndex, delayBetweenMessages: 0)
                }.value
                try Task.checkCancellation()

                if options.confirmAfterStore {
                    progressPanel.update(message: "The configuration is being stored. Please wait.\nVerifying configuration \(options.slot + 1) by readback...")
                    let readback = try await Task.detached(priority: .userInitiated) {
                        try await Task.sleep(for: .milliseconds(800))
                        return try FB01MIDI.request(
                            .configuration(options.slot + 1),
                            sourceIndex: sourceIndex,
                            destinationIndex: destinationIndex,
                            systemChannel: systemChannel,
                            timeout: 8
                        )
                    }.value
                    try Task.checkCancellation()
                    let readbackConfiguration = try Self.storedConfiguration(from: readback, slot: options.slot)
                    statusMessage = readbackConfiguration?.bytes == configurationToStore.bytes
                        ? "FB-01 confirmed store to configuration \(options.slot + 1) on \(destinationName)."
                        : "Stored configuration \(options.slot + 1), but readback did not match exactly."
                } else {
                    statusMessage = "Stored configuration \(options.slot + 1) on \(destinationName)."
                }
                device.cacheConfiguration(configurationToStore, slot: options.slot + 1)
                errorMessage = nil
            } catch is CancellationError {
                statusMessage = nil
                errorMessage = "Store configuration canceled."
            } catch {
                statusMessage = nil
                errorMessage = "Store failed: \(error)"
            }
            progressPanel.dismiss()
            isBusy = false
        }
    }

    private func save(to url: URL) {
        do {
            let artifact = FB01Artifact(message: .currentConfigurationDump(
                systemChannel: systemChannel,
                packet: try FB01SysExPacket(payload: configuration.bytes)
            ))
            try artifact.writeSysEx(to: url)
            savedConfiguration = configuration
            fileURL = url
            rememberEditorSaveDirectory(for: url)
            statusMessage = "Saved \(url.lastPathComponent)."
            errorMessage = nil
        } catch {
            errorMessage = "Save failed: \(error)"
            statusMessage = nil
        }
    }

    private static func readConfiguration(from url: URL) throws -> (configuration: FB01ConfigurationData, systemChannel: Int) {
        let artifact = try FB01Artifact.readSysEx(from: url)
        let candidates = try EditorDocumentExtraction.configurationCandidates(from: artifact)
        guard let candidate = chooseConfigurationCandidate(candidates, title: "Choose Configuration Document") else {
            throw FB01AppError.noConfigurationSource
        }
        return (candidate.configuration, candidate.systemChannel)
    }

    nonisolated private static func extractConfiguration(from artifact: FB01Artifact) throws -> (configuration: FB01ConfigurationData, systemChannel: Int) {
        let candidates = try EditorDocumentExtraction.configurationCandidates(from: artifact)
        guard let candidate = candidates.first else {
            throw FB01AppError.noConfigurationSource
        }
        return (candidate.configuration, candidate.systemChannel)
    }

    private static func chooseConfigurationCandidate(_ candidates: [ConfigurationDocumentCandidate], title: String) -> ConfigurationDocumentCandidate? {
        guard candidates.count > 1 else {
            return candidates.first
        }

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "This SysEx file contains multiple configurations. Choose the one to open in this document window."
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")

        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        for candidate in candidates {
            popup.addItem(withTitle: candidate.title)
        }
        alert.accessoryView = labelledEditorPopup(label: "Config:", popup: popup)

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }
        return candidates[popup.indexOfSelectedItem]
    }

    private static func chooseFetchOptions(title: String, actionTitle: String, nameLookup: ConfigurationFetchNameLookup = .empty) -> ConfigurationFetchOptions? {
        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.addItem(withTitle: "Current Configuration")
        popup.lastItem?.representedObject = ConfigurationFetchOptions(isCurrent: true, slot: 0)
        for slot in 0..<20 {
            popup.addItem(withTitle: nameLookup.menuTitle(slot: slot + 1))
            popup.lastItem?.representedObject = ConfigurationFetchOptions(isCurrent: false, slot: slot)
        }

        let controller = ConfigurationFetchDialogController()
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 235),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.isReleasedWhenClosed = false
        panel.center()

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 235))
        panel.contentView = content

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .boldSystemFont(ofSize: 16)
        titleLabel.frame = NSRect(x: 24, y: 190, width: 512, height: 22)
        content.addSubview(titleLabel)

        let infoLabel = NSTextField(wrappingLabelWithString: "Choose the current configuration edit buffer or one stored FB-01 configuration.")
        infoLabel.textColor = .secondaryLabelColor
        infoLabel.font = .systemFont(ofSize: 13)
        infoLabel.frame = NSRect(x: 24, y: 148, width: 512, height: 36)
        content.addSubview(infoLabel)

        let sourceLabel = NSTextField(labelWithString: "Source:")
        sourceLabel.alignment = .right
        sourceLabel.frame = NSRect(x: 48, y: 105, width: 132, height: 20)
        content.addSubview(sourceLabel)

        popup.controlSize = .regular
        popup.frame = NSRect(x: 196, y: 101, width: 300, height: 26)
        content.addSubview(popup)

        let noteLabel = NSTextField(wrappingLabelWithString: "Configurations 17-20 are read-only on the FB-01, but they can still be fetched into a local document.")
        noteLabel.textColor = .secondaryLabelColor
        noteLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        noteLabel.frame = NSRect(x: 24, y: 58, width: 512, height: 32)
        content.addSubview(noteLabel)

        let cancelButton = NSButton(title: "Cancel", target: controller, action: #selector(ConfigurationFetchDialogController.cancel))
        cancelButton.frame = NSRect(x: 316, y: 18, width: 96, height: 30)
        cancelButton.keyEquivalent = "\u{1b}"
        content.addSubview(cancelButton)

        let fetchButton = NSButton(title: actionTitle, target: controller, action: #selector(ConfigurationFetchDialogController.accept))
        fetchButton.frame = NSRect(x: 424, y: 18, width: 112, height: 30)
        fetchButton.keyEquivalent = "\r"
        content.addSubview(fetchButton)

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.runModal(for: panel)
        panel.orderOut(nil)

        guard controller.result == .OK else {
            return nil
        }
        return popup.selectedItem?.representedObject as? ConfigurationFetchOptions
    }

    nonisolated private static func fetchConfigurationNames(sourceIndex: Int, destinationIndex: Int, systemChannel: Int) -> ConfigurationFetchNameLookup {
        var names: [Int: String] = [:]
        for slot in FB01SynthModule.shared.writableConfigurationSlots.closedRange {
            guard let bytes = try? FB01MIDI.request(
                .configuration(slot),
                sourceIndex: sourceIndex,
                destinationIndex: destinationIndex,
                systemChannel: systemChannel,
                timeout: 1.25
            ),
                  let name = try? FB01ConfigurationService.shared.configurationName(fromDump: bytes),
                  !name.isEmpty else {
                continue
            }
            names[slot] = name
        }
        return ConfigurationFetchNameLookup(storedNames: names)
    }

    @MainActor
    private static func chooseStoreOptions(defaultConfigurationName: String) -> ConfigurationDocumentStoreOptions? {
        let alert = NSAlert()
        alert.messageText = "Store Configuration to FB-01"
        alert.informativeText = "This sets Protect OFF, sends \(defaultConfigurationName.isEmpty ? "this configuration" : defaultConfigurationName) to the current configuration edit buffer, then permanently overwrites one writable configuration slot."
        alert.addButton(withTitle: "Store and Overwrite")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        let stack = NSStackView()
        stack.frame = NSRect(x: 0, y: 0, width: 520, height: 132)
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .leading

        let slotPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for slot in FB01SynthModule.shared.writableConfigurationSlots.closedRange {
            slotPopup.addItem(withTitle: "Configuration \(slot)")
        }
        let confirmCheckbox = NSButton(checkboxWithTitle: "Fetch the stored slot after writing and compare it to this document", target: nil, action: nil)
        confirmCheckbox.state = .on

        stack.addArrangedSubview(labelledEditorPopup(label: "Slot:", popup: slotPopup))
        stack.addArrangedSubview(confirmCheckbox)
        stack.addArrangedSubview(makeWarningLabel("Configurations 1-16 are writable. Configurations 17-20 are read only and are intentionally unavailable here.", width: 500))
        alert.accessoryView = stack

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }

        return ConfigurationDocumentStoreOptions(
            slot: slotPopup.indexOfSelectedItem,
            confirmAfterStore: confirmCheckbox.state == .on
        )
    }

    private static func storeMessages(configuration: FB01ConfigurationData, systemChannel: Int, slot: Int) throws -> [[UInt8]] {
        do {
            return try FB01ConfigurationService.shared.storeMessages(
                configuration: configuration,
                systemChannel: systemChannel,
                zeroBasedSlot: slot
            )
        } catch is FB01SysExError {
            throw FB01AppError.readOnlyConfigurationSlot
        }
    }

    nonisolated private static func storedConfiguration(from bytes: [UInt8], slot: Int) throws -> FB01ConfigurationData? {
        try FB01ConfigurationService.shared.storedConfiguration(fromDump: bytes, zeroBasedSlot: slot)
    }
}

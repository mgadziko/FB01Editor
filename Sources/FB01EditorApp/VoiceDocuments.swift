import AppKit
import Combine
import FB01Editor
import Foundation
import UniformTypeIdentifiers

struct LoadedVoiceDocument: Sendable {
    var projection: FB01VoiceData
    var neutralVoice: FourOperatorVoiceData
    var systemChannel: Int
    var sourceDevice: EditorDeviceSelection
}

struct LoadedDX100VoiceBankFile: Sendable {
    var fileURL: URL
    var candidates: [DX100VoiceDocumentCandidate]

    var title: String {
        fileURL.deletingPathExtension().lastPathComponent
    }
}

struct LoadedFB01VoiceBankFile: Sendable {
    var fileURL: URL
    var title: String
    var systemChannel: Int
    var bankData: FB01VoiceBankData
    var isVoiceRAM: Bool
}

enum VoiceDocumentLoadContext {
    case singleOrGeneric
    case bankFile
}

enum VoiceFetchExecutionMode {
    case automatic
    case cacheOnly
    case manualAssist
}

struct DX100BankFileVoiceOrigin: Equatable {
    var selectorID: UUID
    var slotIndex: Int
    var bankTitle: String
}

struct FB01BankFileVoiceOrigin: Equatable {
    var selectorID: UUID
    var slotIndex: Int
    var bankTitle: String
}

struct FB01DeviceBankVoiceOrigin: Equatable {
    var bank: Int
    var slotIndex: Int
    var bankTitle: String
}

private final class DX100BankFileStoreAccessory: NSView {
    private let selectors: [EditorDocumentWorkspace.DX100VoiceBankFileSelector]
    private let preferredOrigin: DX100BankFileVoiceOrigin?
    private let bankPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let slotPopup = NSPopUpButton(frame: .zero, pullsDown: false)

    init(selectors: [EditorDocumentWorkspace.DX100VoiceBankFileSelector], preferredOrigin: DX100BankFileVoiceOrigin?) {
        self.selectors = selectors
        self.preferredOrigin = preferredOrigin
        super.init(frame: NSRect(x: 0, y: 0, width: 520, height: 112))

        let stack = NSStackView()
        stack.frame = bounds
        stack.autoresizingMask = [.width, .height]
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .leading

        selectors.forEach { selector in
            bankPopup.addItem(withTitle: selector.title)
        }

        if let preferredOrigin,
           let preferredSelectorIndex = selectors.firstIndex(where: { $0.id == preferredOrigin.selectorID }) {
            bankPopup.selectItem(at: preferredSelectorIndex)
        } else {
            bankPopup.selectItem(at: 0)
        }

        bankPopup.target = self
        bankPopup.action = #selector(bankChanged)
        reloadSlots()

        stack.addArrangedSubview(labelledEditorPopup(label: "Bank window:", popup: bankPopup))
        stack.addArrangedSubview(labelledEditorPopup(label: "Slot:", popup: slotPopup))

        let note = NSTextField(wrappingLabelWithString: "If this voice came from the selected bank window, the original slot is preselected.")
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        note.maximumNumberOfLines = 3
        note.preferredMaxLayoutWidth = 500
        note.frame = NSRect(x: 0, y: 0, width: 500, height: 40)
        stack.addArrangedSubview(note)

        addSubview(stack)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func bankChanged() {
        reloadSlots()
    }

    var selection: (selector: EditorDocumentWorkspace.DX100VoiceBankFileSelector, item: EditorDocumentWorkspace.DX100VoiceBankFileSelector.Item)? {
        guard selectors.indices.contains(bankPopup.indexOfSelectedItem) else { return nil }
        let selector = selectors[bankPopup.indexOfSelectedItem]
        guard selector.items.indices.contains(slotPopup.indexOfSelectedItem) else { return nil }
        let item = selector.items[slotPopup.indexOfSelectedItem]
        return (selector, item)
    }

    private func reloadSlots() {
        guard selectors.indices.contains(bankPopup.indexOfSelectedItem) else { return }
        let selector = selectors[bankPopup.indexOfSelectedItem]
        let priorIndex = slotPopup.indexOfSelectedItem
        slotPopup.removeAllItems()
        for item in selector.items {
            slotPopup.addItem(withTitle: "\(item.displayNumber)  \(item.title)")
        }

        if selector.id == preferredOrigin?.selectorID,
           let preferredSlotIndex = selector.items.firstIndex(where: { $0.slotIndex == preferredOrigin?.slotIndex }) {
            slotPopup.selectItem(at: preferredSlotIndex)
        } else if priorIndex >= 0, priorIndex < selector.items.count {
            slotPopup.selectItem(at: priorIndex)
        } else {
            slotPopup.selectItem(at: 0)
        }
    }
}

private final class FB01BankFileStoreAccessory: NSView {
    private let selectors: [EditorDocumentWorkspace.FB01VoiceBankFileSelector]
    private let preferredOrigin: FB01BankFileVoiceOrigin?
    private let bankPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let slotPopup = NSPopUpButton(frame: .zero, pullsDown: false)

    init(selectors: [EditorDocumentWorkspace.FB01VoiceBankFileSelector], preferredOrigin: FB01BankFileVoiceOrigin?) {
        self.selectors = selectors
        self.preferredOrigin = preferredOrigin
        super.init(frame: NSRect(x: 0, y: 0, width: 520, height: 112))

        let stack = NSStackView()
        stack.frame = bounds
        stack.autoresizingMask = [.width, .height]
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .leading

        selectors.forEach { selector in
            bankPopup.addItem(withTitle: selector.title)
        }

        if let preferredOrigin,
           let preferredSelectorIndex = selectors.firstIndex(where: { $0.id == preferredOrigin.selectorID }) {
            bankPopup.selectItem(at: preferredSelectorIndex)
        } else {
            bankPopup.selectItem(at: 0)
        }

        bankPopup.target = self
        bankPopup.action = #selector(bankChanged)
        reloadSlots()

        stack.addArrangedSubview(labelledEditorPopup(label: "Bank window:", popup: bankPopup))
        stack.addArrangedSubview(labelledEditorPopup(label: "Slot:", popup: slotPopup))

        let note = NSTextField(wrappingLabelWithString: "If this voice came from the selected bank window, the original slot is preselected.")
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        note.maximumNumberOfLines = 3
        note.preferredMaxLayoutWidth = 500
        note.frame = NSRect(x: 0, y: 0, width: 500, height: 40)
        stack.addArrangedSubview(note)

        addSubview(stack)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func bankChanged() {
        reloadSlots()
    }

    var selection: (selector: EditorDocumentWorkspace.FB01VoiceBankFileSelector, item: EditorDocumentWorkspace.FB01VoiceBankFileSelector.Item)? {
        guard selectors.indices.contains(bankPopup.indexOfSelectedItem) else { return nil }
        let selector = selectors[bankPopup.indexOfSelectedItem]
        guard selector.items.indices.contains(slotPopup.indexOfSelectedItem) else { return nil }
        let item = selector.items[slotPopup.indexOfSelectedItem]
        return (selector, item)
    }

    private func reloadSlots() {
        guard selectors.indices.contains(bankPopup.indexOfSelectedItem) else { return }
        let selector = selectors[bankPopup.indexOfSelectedItem]
        let priorIndex = slotPopup.indexOfSelectedItem
        slotPopup.removeAllItems()
        for item in selector.items {
            slotPopup.addItem(withTitle: "\(item.displayNumber)  \(item.title)")
        }

        if selector.id == preferredOrigin?.selectorID,
           let preferredSlotIndex = selector.items.firstIndex(where: { $0.slotIndex == preferredOrigin?.slotIndex }) {
            slotPopup.selectItem(at: preferredSlotIndex)
        } else if priorIndex >= 0, priorIndex < selector.items.count {
            slotPopup.selectItem(at: priorIndex)
        } else {
            slotPopup.selectItem(at: 0)
        }
    }
}

private final class FB01DeviceBankStoreAccessory: NSView {
    private let banks: [Int]
    private let preferredOrigin: FB01DeviceBankVoiceOrigin?
    private let voiceNameProvider: (Int, Int) -> String?
    private let bankPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let slotPopup = NSPopUpButton(frame: .zero, pullsDown: false)

    init(
        banks: [Int],
        preferredOrigin: FB01DeviceBankVoiceOrigin?,
        voiceNameProvider: @escaping (Int, Int) -> String?
    ) {
        self.banks = banks
        self.preferredOrigin = preferredOrigin
        self.voiceNameProvider = voiceNameProvider
        super.init(frame: NSRect(x: 0, y: 0, width: 520, height: 112))

        let stack = NSStackView()
        stack.frame = bounds
        stack.autoresizingMask = [.width, .height]
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .leading

        banks.forEach { bank in
            bankPopup.addItem(withTitle: "Voice Bank \(bank)")
        }

        if let preferredOrigin,
           let preferredBankIndex = banks.firstIndex(of: preferredOrigin.bank) {
            bankPopup.selectItem(at: preferredBankIndex)
        } else {
            bankPopup.selectItem(at: 0)
        }

        bankPopup.target = self
        bankPopup.action = #selector(bankChanged)
        reloadSlots()

        stack.addArrangedSubview(labelledEditorPopup(label: "Bank window:", popup: bankPopup))
        stack.addArrangedSubview(labelledEditorPopup(label: "Slot:", popup: slotPopup))

        let note = NSTextField(wrappingLabelWithString: "If this voice came from the selected bank window, the original slot is preselected.")
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        note.maximumNumberOfLines = 3
        note.preferredMaxLayoutWidth = 500
        note.frame = NSRect(x: 0, y: 0, width: 500, height: 40)
        stack.addArrangedSubview(note)

        addSubview(stack)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func bankChanged() {
        reloadSlots()
    }

    var selection: (bank: Int, slotIndex: Int)? {
        guard banks.indices.contains(bankPopup.indexOfSelectedItem) else { return nil }
        let bank = banks[bankPopup.indexOfSelectedItem]
        let slotIndex = slotPopup.indexOfSelectedItem
        guard (0..<FB01VoiceBankData.voiceCount).contains(slotIndex) else { return nil }
        return (bank, slotIndex)
    }

    private func reloadSlots() {
        guard banks.indices.contains(bankPopup.indexOfSelectedItem) else { return }
        let bank = banks[bankPopup.indexOfSelectedItem]
        let priorIndex = slotPopup.indexOfSelectedItem
        slotPopup.removeAllItems()
        for slotIndex in 0..<FB01VoiceBankData.voiceCount {
            let name = voiceNameProvider(bank, slotIndex) ?? "Voice \(slotIndex + 1)"
            slotPopup.addItem(withTitle: "\(slotIndex + 1) \(name)")
        }

        if bank == preferredOrigin?.bank,
           let preferredSlotIndex = preferredOrigin?.slotIndex,
           (0..<FB01VoiceBankData.voiceCount).contains(preferredSlotIndex) {
            slotPopup.selectItem(at: preferredSlotIndex)
        } else if priorIndex >= 0, priorIndex < FB01VoiceBankData.voiceCount {
            slotPopup.selectItem(at: priorIndex)
        } else {
            slotPopup.selectItem(at: 0)
        }
    }
}

@MainActor
final class VoiceDocumentModel: ObservableObject, Identifiable {
    let id = UUID()
    @Published var neutralVoice: FourOperatorVoiceData
    @Published var savedNeutralVoice: FourOperatorVoiceData
    @Published private var projectionOverlay: FB01VoiceProjectionOverlay
    @Published private var savedProjectionOverlay: FB01VoiceProjectionOverlay
    @Published var systemChannel: Int
    @Published var sourceDevice: EditorDeviceSelection = .fb01
    @Published var fileURL: URL?
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    @Published var isBusy = false
    @Published var selectedOperatorIndex = FB01VoiceData.dataIndex(forOperatorNumber: 1)
    @Published var voiceCharacterType: VoiceCharacterType = .other
    @Published var performanceMacroValues = PerformanceMacro.neutralValues
    @Published var layoutRevision = 0
    var fb01BankFileOrigin: FB01BankFileVoiceOrigin?
    var fb01DeviceBankOrigin: FB01DeviceBankVoiceOrigin?
    var dx100BankFileOrigin: DX100BankFileVoiceOrigin?
    private var preparedKeyboardVoiceSignature: String?
    private var preparedKeyboardVoiceDate: Date?
    private var keyboardPreparationTask: Task<Void, Never>?
    private var dx100LiveResendTask: Task<Void, Never>?
    private var lastDX100LiveSentSignature: String?
    private var projectedVoiceCache: FB01VoiceData
    private var savedProjectedVoiceCache: FB01VoiceData

    init(voice: FB01VoiceData, systemChannel: Int, fileURL: URL? = nil) {
        let neutralVoice = voice.fourOperatorVoice
        self.neutralVoice = neutralVoice
        self.savedNeutralVoice = neutralVoice
        let overlay = FB01VoiceProjectionOverlay(voice: voice)
        self.projectionOverlay = overlay
        self.savedProjectionOverlay = overlay
        self.projectedVoiceCache = voice
        self.savedProjectedVoiceCache = voice
        self.systemChannel = systemChannel
        self.fileURL = fileURL
    }

    convenience init(loadedDocument: LoadedVoiceDocument, fileURL: URL? = nil) {
        self.init(voice: loadedDocument.projection, systemChannel: loadedDocument.systemChannel, fileURL: fileURL)
        sourceDevice = loadedDocument.sourceDevice
        replaceDocument(with: loadedDocument)
    }

    var voice: FB01VoiceData { projectedVoiceCache }
    var savedVoice: FB01VoiceData { savedProjectedVoiceCache }

    var displayName: String {
        let rawName = neutralVoice.name
        return rawName.isEmpty ? "Untitled Voice" : rawName
    }

    var title: String {
        let name = displayName
        if isBusy {
            return "\(name) (Working)"
        }
        return isEdited ? "\(name) *" : name
    }

    var isEdited: Bool {
        neutralVoice != savedNeutralVoice
    }

    func reset() {
        applyDocumentVoices(
            workingNeutral: savedNeutralVoice,
            projection: savedVoice,
            savedNeutral: savedNeutralVoice,
            savedProjection: savedVoice
        )
        resetPerformanceMacros()
        noteVoiceReplacement()
        errorMessage = nil
        statusMessage = "Reverted to last saved version."
    }

    func replaceDocument(with loadedDocument: LoadedVoiceDocument) {
        sourceDevice = loadedDocument.sourceDevice
        systemChannel = loadedDocument.systemChannel
        applyDocumentVoices(
            workingNeutral: loadedDocument.neutralVoice,
            projection: loadedDocument.projection,
            savedNeutral: loadedDocument.neutralVoice,
            savedProjection: loadedDocument.projection
        )
        resetPerformanceMacros()
        noteVoiceReplacement()
        errorMessage = nil
        statusMessage = nil
    }

    var canStoreToLinkedBankWindow: Bool {
        sourceDevice == .dx100 || sourceDevice == .fb01
    }

    var linkedBankWindowStoreTitle: String? {
        "Store Voice to Open Bank Window..."
    }

    func updateVoice(_ edit: (FB01VoiceData) throws -> FB01VoiceData) {
        do {
            let editedVoice = try edit(voice)
            guard editedVoice != voice else { return }
            applyProjectedEdit(editedVoice)
        } catch {
            errorMessage = "Edit failed: \(error)"
        }
    }

    func updateVoiceRefreshingLayout(_ edit: (FB01VoiceData) throws -> FB01VoiceData) {
        let originalVoice = voice
        updateVoice(edit)
        if voice != originalVoice {
            layoutRevision &+= 1
        }
    }

    func setName(_ value: String) {
        if sourceDevice == .dx100 {
            let limited = String(value.prefix(DX100VoiceData.nameLength))
            guard limited != neutralVoice.name else { return }
            updateNeutral { voice in
                voice.name = limited
            }
            return
        }

        let limited = String(value.prefix(FB01VoiceData.nameLength))
        guard limited != neutralVoice.name else { return }
        updateNeutral { voice in
            voice.name = limited
        }
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
        panel.allowedContentTypes = UTType.voiceFileTypes(for: sourceDevice)
        panel.directoryURL = preferredEditorSaveDirectoryURL()
        panel.nameFieldStringValue = "\(safeEditorFileName(displayName, fallback: "voice")).\(defaultVoiceFileExtension)"
        panel.message = "Save this voice document to a voice file."
        panel.prompt = "Save Voice to File"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        save(to: url, voiceNameFromFile: editorDocumentName(
            fromFileURL: url,
            maxLength: sourceDevice == .dx100 ? DX100VoiceData.nameLength : FB01VoiceData.nameLength,
            fallback: "voice"
        ))
    }

    static func loadFromDisk(preferredDevice: EditorDeviceSelection? = nil) -> VoiceDocumentModel? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = UTType.readableVoiceFileTypes(for: preferredDevice)
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = preferredEditorLoadDirectoryURL()
        panel.message = "Load a voice file into a new voice document window."
        panel.prompt = "Load Voice from File"

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        do {
            let loaded = try readVoiceDocument(from: url, context: .singleOrGeneric)
            rememberEditorLoadDirectory(for: url)
            return VoiceDocumentModel(loadedDocument: loaded, fileURL: url)
        } catch {
            showEditorError(title: "Load Voice Failed", message: "\(error)")
            return nil
        }
    }

    static func loadFromDisk(url: URL) -> VoiceDocumentModel? {
        do {
            let loaded = try readVoiceDocument(from: url, context: .singleOrGeneric)
            rememberEditorLoadDirectory(for: url)
            return VoiceDocumentModel(loadedDocument: loaded, fileURL: url)
        } catch {
            showEditorError(title: "Load Voice Failed", message: "\(error)")
            return nil
        }
    }

    static func loadFromBankFile(preferredDevice: EditorDeviceSelection? = nil) -> VoiceDocumentModel? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = UTType.voiceBankFileTypes(for: preferredDevice)
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = preferredEditorLoadDirectoryURL()
        if preferredDevice == .dx100 {
            panel.message = "Load a DX100/27 voice bank file from disk, then choose one of its 24 displayed voices to open in a new voice document window."
            panel.prompt = "Load DX100/27 Voice Bank File"
        } else {
            panel.message = "Load a voice bank file and choose one voice to open in a new voice document window."
            panel.prompt = "Load Voice Bank from File"
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        do {
            let loaded = try readVoiceDocument(from: url, context: .bankFile)
            rememberEditorLoadDirectory(for: url)
            return VoiceDocumentModel(loadedDocument: loaded, fileURL: nil)
        } catch {
            showEditorError(title: "Load Voice Bank Failed", message: "\(error)")
            return nil
        }
    }

    static func loadDX100BankFile() -> LoadedDX100VoiceBankFile? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = UTType.dx100VoiceBankFileTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = preferredEditorLoadDirectoryURL()
        panel.message = "Load a DX100/27 voice bank file from disk and open it as a bank window."
        panel.prompt = "Load DX100/27 Voice Bank File"

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        return loadDX100BankFile(from: url)
    }

    static func loadDX100BankFile(from url: URL) -> LoadedDX100VoiceBankFile? {
        do {
            let candidates = try DX100DocumentService.shared.readVoiceCandidates(from: url)
            rememberEditorLoadDirectory(for: url)
            return LoadedDX100VoiceBankFile(fileURL: url, candidates: candidates)
        } catch {
            showEditorError(title: "Load DX100/27 Voice Bank Failed", message: "\(error)")
            return nil
        }
    }

    static func loadFB01BankFile() -> LoadedFB01VoiceBankFile? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = UTType.currentModuleVoiceBankFileTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = preferredEditorLoadDirectoryURL()
        panel.message = "Load an FB-01 voice bank file from disk and open it as a bank window."
        panel.prompt = "Load Voice Bank from File"

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        return loadFB01BankFile(from: url)
    }

    static func loadFB01BankFile(from url: URL) -> LoadedFB01VoiceBankFile? {
        do {
            let artifact = try FB01Artifact(sysexBytes: Array(Data(contentsOf: url)))
            guard artifact.messages.count == 1 else {
                throw FB01AppError.message("This file does not contain a single FB-01 voice bank.")
            }

            switch artifact.messages[0] {
            case let .voiceBankDumpData(systemChannel, bank, _, data, _):
                let bankData = try FB01VoiceBankData(bank: bank, data: data)
                rememberEditorLoadDirectory(for: url)
                return LoadedFB01VoiceBankFile(
                    fileURL: url,
                    title: url.deletingPathExtension().lastPathComponent,
                    systemChannel: systemChannel,
                    bankData: bankData,
                    isVoiceRAM: false
                )
            case let .voiceRAMDumpData(systemChannel, _, data, _):
                let bankData = try FB01VoiceBankData(bank: 0, data: data)
                rememberEditorLoadDirectory(for: url)
                return LoadedFB01VoiceBankFile(
                    fileURL: url,
                    title: url.deletingPathExtension().lastPathComponent,
                    systemChannel: systemChannel,
                    bankData: bankData,
                    isVoiceRAM: true
                )
            default:
                throw FB01AppError.message("This file does not contain an FB-01 voice bank.")
            }
        } catch {
            showEditorError(title: "Load Voice Bank Failed", message: "\(error)")
            return nil
        }
    }

    func importFromDisk() {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = UTType.readableVoiceFileTypes(for: sourceDevice)
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = preferredEditorLoadDirectoryURL()
        panel.message = "Import a voice file into this voice document, replacing its current contents."
        panel.prompt = "Import Voice from File"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let imported = try Self.readVoiceDocument(from: url, context: .singleOrGeneric)
            applyDocumentVoices(
                workingNeutral: imported.neutralVoice,
                projection: imported.projection,
                savedNeutral: imported.neutralVoice,
                savedProjection: imported.projection
            )
            resetPerformanceMacros()
            systemChannel = imported.systemChannel
            sourceDevice = imported.sourceDevice
            fileURL = url
            noteVoiceReplacement()
            rememberEditorLoadDirectory(for: url)
            statusMessage = "Imported \(url.lastPathComponent)."
            errorMessage = nil
        } catch {
            errorMessage = "Import failed: \(error)"
            statusMessage = nil
        }
    }

    func fetchFromDevice(
        device: DocumentModel,
        source preselectedSource: VoiceDocumentFetchSource? = nil,
        recentTitle: String? = nil,
        mode: VoiceFetchExecutionMode = .automatic
    ) {
        guard !isBusy else { return }
        guard let selectedDevice = device.selectedEditorDevice else {
            errorMessage = "Fetch failed: select a device first."
            statusMessage = nil
            return
        }
        let sourceIndex = device.selectedSourceIndex
        let destinationIndex = device.selectedDestinationIndex
        let systemChannel = device.systemChannel

        let systemChannelName = "System channel \(systemChannel + 1)"
        errorMessage = nil
        isBusy = true

        if selectedDevice == .dx100 {
            let source = preselectedSource ?? .currentVoice
            if mode != .manualAssist,
               let cachedResult = device.cachedVoiceFetchResult(source: source, systemChannel: systemChannel) {
                applyDocumentVoices(
                    workingNeutral: cachedResult.neutralVoice,
                    projection: cachedResult.voice,
                    savedNeutral: cachedResult.neutralVoice,
                    savedProjection: cachedResult.voice
                )
                resetPerformanceMacros()
                self.systemChannel = cachedResult.systemChannel
                self.sourceDevice = .dx100
                fileURL = nil
                noteVoiceReplacement()
                preparedKeyboardVoiceSignature = nil
                let fetchedName = cachedResult.neutralVoice.name.isEmpty ? "Untitled" : cachedResult.neutralVoice.name
                statusMessage = "Fetched \(fetchedName) from cached \(cachedResult.title) into this document."
                device.rememberRecentFetchedVoice(source, title: cachedResult.title)
                errorMessage = nil
                isBusy = false
                return
            }

            if mode == .cacheOnly {
                errorMessage = "Cached fetch unavailable for \(recentTitle ?? source.title()). Show the bank first or fetch the voice manually."
                statusMessage = nil
                isBusy = false
                return
            }

            if mode == .manualAssist {
                guard case let .dx100Bank(bank, voiceNumber) = source else {
                    errorMessage = "Manual fetch is available only for DX100/27 bank voices."
                    statusMessage = nil
                    isBusy = false
                    return
                }

                guard let bankKind = DX100ModuleServices.shared.module.voiceBankKind(displayBank: bank),
                      bankKind.requiresManualBulkCapture else {
                    errorMessage = "Manual fetch is available only for DX100/27 Bank A-D voices."
                    statusMessage = nil
                    isBusy = false
                    return
                }

                let bankTitle = DX100ModuleServices.shared.module.voiceBankKind(displayBank: bank)?.displayName ?? "Bank \(bank)"
                let fetchTitle = recentTitle ?? "DX100/27 \(bankTitle) Voice \(voiceNumber + 1)"
                statusMessage = "Preparing manual fetch for \(fetchTitle) on \(systemChannelName)..."
                let fetchProgressPanel = EditorProgressPanel(
                    title: "Fetching Voice",
                    message: "The voice is being fetched. Please wait.\nSelecting \(fetchTitle) on the DX100/27..."
                )
                fetchProgressPanel.show()

                Task {
                    do {
                        try await Task.detached(priority: .userInitiated) {
                            try EditorVoiceDocumentService.prepareDX100AssistedDeviceVoiceRecall(
                                bank: bank - 1,
                                voiceNumber: voiceNumber,
                                destinationIndex: destinationIndex,
                                systemChannel: systemChannel
                            )
                        }.value

                        fetchProgressPanel.update(
                            message: "The voice is being fetched. Please wait.\nPress the matching front-panel voice number for \(fetchTitle), then Continue."
                        )
                        let confirmed = confirmDX100AssistedVoiceRecall(
                            bankTitle: bankTitle,
                            voiceNumber: voiceNumber + 1
                        )
                        guard confirmed else {
                            throw CancellationError()
                        }

                        fetchProgressPanel.update(
                            message: "The voice is being fetched. Please wait.\nRequesting current voice dump for \(fetchTitle)..."
                        )
                        let fetched = try await Task.detached(priority: .userInitiated) {
                            try EditorVoiceDocumentService.fetchDX100CurrentVoice(
                                sourceIndex: sourceIndex,
                                destinationIndex: destinationIndex,
                                systemChannel: systemChannel
                            )
                        }.value

                        let dxVoice = fetched.voice
                        let projected = try dxVoice.fb01EditableVoice()
                        applyDocumentVoices(
                            workingNeutral: dxVoice.fourOperatorVoice,
                            projection: projected,
                            savedNeutral: dxVoice.fourOperatorVoice,
                            savedProjection: projected
                        )
                        resetPerformanceMacros()
                        self.systemChannel = fetched.channel
                        self.sourceDevice = .dx100
                        fileURL = nil
                        noteVoiceReplacement()
                        preparedKeyboardVoiceSignature = nil
                        let fetchedName = dxVoice.name.isEmpty ? "Untitled" : dxVoice.name
                        statusMessage = "Fetched \(fetchedName) from \(fetchTitle) into this document."
                        device.rememberRecentFetchedVoice(source, title: fetchTitle)
                        errorMessage = nil
                    } catch is CancellationError {
                        errorMessage = "Manual fetch canceled."
                        statusMessage = nil
                    } catch {
                        errorMessage = "Fetch failed on \(systemChannelName): \(error)"
                        statusMessage = nil
                    }
                    fetchProgressPanel.dismiss()
                    isBusy = false
                }
                return
            }

            let fetchTitle = recentTitle ?? "DX100/27 Current Edit Voice"
            statusMessage = "Fetching \(fetchTitle) on \(systemChannelName)..."
            let fetchProgressPanel = EditorProgressPanel(
                title: "Fetching Voice",
                message: "The voice is being fetched. Please wait.\nFetching \(fetchTitle)..."
            )
            fetchProgressPanel.show()
            Task {
                do {
                    let result = try await Task.detached(priority: .userInitiated) {
                        try EditorVoiceDocumentService.fetchVoiceDocument(
                            for: .dx100,
                            source: preselectedSource,
                            sourceIndex: sourceIndex,
                            destinationIndex: destinationIndex,
                            systemChannel: systemChannel,
                            documentModel: device,
                            recentTitle: recentTitle
                        )
                    }.value
                    applyDocumentVoices(
                        workingNeutral: result.neutralVoice,
                        projection: result.voice,
                        savedNeutral: result.neutralVoice,
                        savedProjection: result.voice
                    )
                    resetPerformanceMacros()
                    self.systemChannel = result.systemChannel
                    self.sourceDevice = result.sourceDevice
                    fileURL = nil
                    noteVoiceReplacement()
                    preparedKeyboardVoiceSignature = nil
                    let fetchedName = result.neutralVoice.name.isEmpty ? "Untitled" : result.neutralVoice.name
                    statusMessage = "Fetched \(fetchedName) from \(result.title) into this document."
                    device.rememberRecentFetchedVoice(source, title: result.title)
                    errorMessage = nil
                } catch {
                    errorMessage = "Fetch failed on \(systemChannelName): \(error)"
                    statusMessage = nil
                }
                fetchProgressPanel.dismiss()
                isBusy = false
            }
            return
        }

        if preselectedSource == nil {
            statusMessage = "Fetching Bank 1 and Bank 2 voice names from FB-01 on \(systemChannelName)..."
        } else {
            statusMessage = "Fetching \(recentTitle ?? "recent voice") from FB-01 on \(systemChannelName)..."
        }

        Task {
            let nameLookup: VoiceDocumentFetchNameLookup
            if preselectedSource == nil {
                let cachedLookup = device.voiceNameLookupFromCache()
                if !cachedLookup.ramBankNames.isEmpty {
                    nameLookup = cachedLookup
                    statusMessage = "Voice names loaded from device cache."
                } else {
                    let progressPanel = EditorProgressPanel(
                        title: "Fetching Voice Names",
                        message: "Fetching Bank 1 and Bank 2 from the FB-01 on \(systemChannelName) so the Fetch dialog can show current RAM voice names."
                    )
                    progressPanel.show()
                    nameLookup = await Task.detached(priority: .userInitiated) {
                        FB01VoiceDocumentService.fetchRAMVoiceNames(
                            sourceIndex: sourceIndex,
                            destinationIndex: destinationIndex,
                            systemChannel: systemChannel
                        )
                    }.value
                    progressPanel.dismiss()
                    statusMessage = "Voice name prefetch loaded \(nameLookup.loadedBankTitles) on \(systemChannelName)."
                }
            } else {
                nameLookup = device.voiceNameLookupFromCache()
            }

            let source: VoiceDocumentFetchSource
            if let preselectedSource {
                source = preselectedSource
            } else {
                guard let chosenSource = Self.chooseFetchSource(
                    title: "Fetch Voice from Device into Current Document",
                    actionTitle: "Fetch",
                    nameLookup: nameLookup,
                    systemChannel: systemChannel
                ) else {
                    statusMessage = nil
                    isBusy = false
                    return
                }
                source = chosenSource
            }

            if let cachedResult = device.cachedVoiceFetchResult(source: source, systemChannel: systemChannel, nameLookup: nameLookup) {
                applyDocumentVoices(
                    workingNeutral: cachedResult.neutralVoice,
                    projection: cachedResult.voice,
                    savedNeutral: cachedResult.neutralVoice,
                    savedProjection: cachedResult.voice
                )
                resetPerformanceMacros()
                self.systemChannel = cachedResult.systemChannel
                self.sourceDevice = selectedDevice
                self.updateOrigins(for: source, device: .fb01, bankTitleProvider: { bank in
                    device.selectedDeviceVoiceBankTitle(bank)
                })
                fileURL = nil
                noteVoiceReplacement()
                let fetchedName = cachedResult.neutralVoice.name.isEmpty ? "Untitled" : cachedResult.neutralVoice.name
                statusMessage = "Fetched \(fetchedName) from cached \(cachedResult.title) into this document."
                device.rememberRecentFetchedVoice(source, title: cachedResult.title)
                errorMessage = nil
                isBusy = false
                return
            }

            statusMessage = "Fetching voice from FB-01 on \(systemChannelName); waiting for device response..."
            let fetchTitle = recentTitle ?? source.title(nameLookup: nameLookup)
            let fetchProgressPanel = EditorProgressPanel(
                title: "Fetching Voice",
                message: "The voice is being fetched. Please wait.\nFetching \(fetchTitle) from the FB-01..."
            )
            fetchProgressPanel.show()
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try FB01VoiceDocumentService.fetchVoice(source: source, sourceIndex: sourceIndex, destinationIndex: destinationIndex, systemChannel: systemChannel)
                }.value
                applyDocumentVoices(
                    workingNeutral: result.voice.fourOperatorVoice,
                    projection: result.voice,
                    savedNeutral: result.voice.fourOperatorVoice,
                    savedProjection: result.voice
                )
                resetPerformanceMacros()
                self.systemChannel = result.systemChannel
                self.sourceDevice = .fb01
                self.updateOrigins(for: source, device: .fb01, bankTitleProvider: { bank in
                    device.selectedDeviceVoiceBankTitle(bank)
                })
                fileURL = nil
                noteVoiceReplacement()
                let fetchedName = result.voice.name.isEmpty ? "Untitled" : result.voice.name
                statusMessage = "Fetched \(fetchedName) from \(fetchTitle) into this document."
                device.rememberRecentFetchedVoice(source, title: fetchTitle)
                errorMessage = nil
                isBusy = false
            } catch {
                errorMessage = "Fetch failed on \(systemChannelName): \(error)"
                statusMessage = nil
                isBusy = false
            }
            fetchProgressPanel.dismiss()
        }
    }

    func importFromLibrary(device: DocumentModel) {
        guard !isBusy else { return }
        guard let payload = device.selectedVoiceDocumentPayload() else {
            errorMessage = "Import failed: no selected library voice."
            statusMessage = nil
            return
        }
        applyDocumentVoices(
            workingNeutral: payload.voice.fourOperatorVoice,
            projection: payload.voice,
            savedNeutral: payload.voice.fourOperatorVoice,
            savedProjection: payload.voice
        )
        resetPerformanceMacros()
        systemChannel = payload.systemChannel
        fileURL = nil
        noteVoiceReplacement()
        preparedKeyboardVoiceSignature = nil
        statusMessage = "Imported selected library voice into this document."
        errorMessage = nil
    }

    func updateNeutral(_ edit: (inout FourOperatorVoiceData) -> Void) {
        var updated = neutralVoice
        edit(&updated)
        guard updated != neutralVoice else { return }
        applyNeutralEdit(updated)
    }

    func setNeutralName(_ value: String) {
        setName(value)
    }

    func setNeutralAlgorithm(_ displayValue: Int) {
        let newAlgorithm = min(max(displayValue - 1, 0), 7)
        let carrierNumbers = FourOperatorVoiceData.carrierOperatorNumbers(forAlgorithm: newAlgorithm)
        updateNeutral { voice in
            voice.algorithm = newAlgorithm
            voice.operators = voice.operators.map { operatorData in
                var updatedOperator = operatorData
                updatedOperator.isCarrier = carrierNumbers.contains(operatorData.operatorNumber)
                return updatedOperator
            }
        }
    }

    func setNeutralFeedback(_ value: Int) {
        updateNeutral { $0.feedback = value }
    }

    func setNeutralTranspose(_ value: Int) {
        updateNeutral { $0.transpose = value }
    }

    func setNeutralLFOSpeed(_ value: Int) {
        updateNeutral { $0.lfoSpeed = value }
    }

    func setNeutralLFOWaveform(_ value: Int) {
        updateNeutral { $0.lfoWaveform = value }
    }

    func setNeutralLFOSyncEnabled(_ value: Bool) {
        updateNeutral { $0.lfoSyncEnabled = value }
    }

    func setNeutralAmplitudeModulationDepth(_ value: Int) {
        updateNeutral { $0.amplitudeModulationDepth = value }
    }

    func setNeutralPitchModulationDepth(_ value: Int) {
        updateNeutral { $0.pitchModulationDepth = value }
    }

    func setNeutralAmplitudeModulationSensitivity(_ value: Int) {
        updateNeutral { $0.amplitudeModulationSensitivity = value }
    }

    func setNeutralPitchModulationSensitivity(_ value: Int) {
        updateNeutral { $0.pitchModulationSensitivity = value }
    }

    func neutralOperator(forDataIndex dataIndex: Int) -> FourOperatorVoiceOperatorData? {
        let operatorNumber = FB01VoiceData.operatorNumber(forDataIndex: dataIndex)
        return neutralVoice.operators.first { $0.operatorNumber == operatorNumber }
    }

    func savedNeutralOperator(forDataIndex dataIndex: Int) -> FourOperatorVoiceOperatorData? {
        let operatorNumber = FB01VoiceData.operatorNumber(forDataIndex: dataIndex)
        return savedNeutralVoice.operators.first { $0.operatorNumber == operatorNumber }
    }

    func updateNeutralOperator(forDataIndex dataIndex: Int, edit: (inout FourOperatorVoiceOperatorData) -> Void) {
        let operatorNumber = FB01VoiceData.operatorNumber(forDataIndex: dataIndex)
        updateNeutral { voice in
            guard let index = voice.operators.firstIndex(where: { $0.operatorNumber == operatorNumber }) else {
                return
            }
            edit(&voice.operators[index])
        }
    }

    func storeToDevice(device: DocumentModel) {
        guard !isBusy else { return }
        guard let options = Self.chooseStoreOptions(defaultVoiceName: neutralVoice.name) else {
            return
        }

        let voiceToStore = voice
        let neutralVoiceToStore = neutralVoice
        let destinationIndex = device.selectedDestinationIndex
        let sourceIndex = device.selectedSourceIndex
        let systemChannel = device.systemChannel
        let destinationName = device.selectedDestinationName

        if device.selectedEditorDevice == .dx100 {
            isBusy = true
            statusMessage = "Sending voice to DX100/27 current buffer..."
            errorMessage = nil
            let progressPanel = EditorProgressPanel(
                title: "Send Voice",
                message: "The voice is being sent. Please wait.\nSending the current editable voice to the DX100/27 current buffer..."
            )
            progressPanel.show()
            Task {
                do {
                    try await Task.detached(priority: .userInitiated) {
                        try EditorVoiceDocumentService.storeVoiceDocument(
                            neutralVoiceToStore,
                            to: .dx100,
                            sourceIndex: sourceIndex,
                            destinationIndex: destinationIndex,
                            systemChannel: systemChannel
                        )
                    }.value
                    sourceDevice = .dx100
                    statusMessage = "DX100/27 current voice buffer updated on \(destinationName)."
                    errorMessage = nil
                } catch {
                    statusMessage = nil
                    errorMessage = "Store failed: \(error)"
                }
                progressPanel.dismiss()
                isBusy = false
            }
            return
        }

        isBusy = true
        statusMessage = "Backing up Bank \(options.bank + 1) before storing voice..."
        errorMessage = nil
        let progressPanel = EditorProgressPanel(
            title: "Store Voice",
            message: "The voice is being stored. Please wait.\nBacking up Bank \(options.bank + 1)...",
            showsCancelButton: true
        )
        progressPanel.show()

        var operationTask: Task<Void, Never>?
        progressPanel.onCancel = {
            operationTask?.cancel()
        }

        operationTask = Task {
            do {
                let bankNumber = options.bank + 1
                let backupDirectory = try ensureDefaultEditorBackupDirectory()
                let backupURL = backupDirectory.appendingPathComponent(
                    backupFileName(prefix: "bank-\(bankNumber)-before-voice-\(options.voiceNumber + 1)")
                )
                let requestKind = try FB01ModuleServices.shared.deviceService.requestKind(forDisplayBank: bankNumber)
                let originalBytes = try await Task.detached(priority: .userInitiated) {
                    try FB01MIDI.request(
                        requestKind,
                        sourceIndex: sourceIndex,
                        destinationIndex: destinationIndex,
                        systemChannel: systemChannel,
                        timeout: 15
                    )
                }.value
                let originalArtifact = try FB01Artifact(sysexBytes: originalBytes)
                try Task.checkCancellation()
                try await Task.detached(priority: .userInitiated) {
                    try originalArtifact.writeSysEx(to: backupURL)
                }.value
                try Task.checkCancellation()

                let readback = try await FB01ModuleServices.shared.voiceService.storeVoiceInBankImage(
                    voiceToStore,
                    displayBank: bankNumber,
                    zeroBasedVoiceNumber: options.voiceNumber,
                    initialBankDumpBytes: originalBytes,
                    sourceIndex: sourceIndex,
                    destinationIndex: destinationIndex,
                    systemChannel: systemChannel
                ) { [self] event in
                    await MainActor.run {
                        switch event {
                        case .turningProtectOff:
                            progressPanel.update(message: "The voice is being stored. Please wait.\nTurning FB-01 Protect OFF...")
                        case .storePass(let pass):
                            self.statusMessage = "Storing Bank \(bankNumber) Voice \(options.voiceNumber + 1), pass \(pass); verifying after send..."
                            progressPanel.update(message: "The voice is being stored. Please wait.\nStoring Bank \(bankNumber) Voice \(options.voiceNumber + 1), pass \(pass); verifying by readback...")
                        }
                    }
                }

                device.cacheVoiceBank(readback, userBankNumber: bankNumber)
                statusMessage = "FB-01 verified Bank \(options.bank + 1) Voice \(options.voiceNumber + 1) on \(destinationName). Backup saved to \(backupURL.lastPathComponent)."
                errorMessage = nil
            } catch is CancellationError {
                statusMessage = nil
                errorMessage = "Store voice canceled."
            } catch {
                statusMessage = nil
                errorMessage = "Store failed: \(error)"
            }
            progressPanel.dismiss()
            isBusy = false
        }
    }

    func storeToLinkedBankWindow(workspace: EditorDocumentWorkspace, device: DocumentModel) {
        guard !isBusy else { return }

        switch sourceDevice {
        case .dx100:
            let selectors = workspace.openDX100VoiceBankFileSelectors
            guard !selectors.isEmpty else {
                errorMessage = "Open a DX100/27 voice bank window before storing this voice into a bank file."
                statusMessage = nil
                return
            }

            if let origin = dx100BankFileOrigin,
               selectors.contains(where: { $0.id == origin.selectorID }) {
                do {
                    let dxVoice = try neutralVoice.dx100Voice()
                    try workspace.replaceVoice(inDX100VoiceBankFileSelector: origin.selectorID, slotIndex: origin.slotIndex, with: dxVoice)
                    markCurrentStateSaved()
                    _ = workspace.bringWindowToFront(identifier: EditorDocumentWorkspace.dx100VoiceBankFileSelectorWindowIdentifier(for: origin.selectorID))
                    statusMessage = "Stored \(displayName) into \(origin.bankTitle) slot \(origin.slotIndex + 1). Save the bank window to write the updated bank file."
                    errorMessage = nil
                } catch {
                    statusMessage = nil
                    errorMessage = "Store to bank window failed: \(error)"
                }
                return
            }

            guard let target = chooseDX100BankFileStoreTarget(selectors: selectors, preferredOrigin: dx100BankFileOrigin) else {
                return
            }

            do {
                let dxVoice = try neutralVoice.dx100Voice()
                try workspace.replaceVoice(inDX100VoiceBankFileSelector: target.selectorID, slotIndex: target.slotIndex, with: dxVoice)
                dx100BankFileOrigin = DX100BankFileVoiceOrigin(
                    selectorID: target.selectorID,
                    slotIndex: target.slotIndex,
                    bankTitle: target.selectorTitle
                )
                markCurrentStateSaved()
                _ = workspace.bringWindowToFront(identifier: EditorDocumentWorkspace.dx100VoiceBankFileSelectorWindowIdentifier(for: target.selectorID))
                statusMessage = "Stored \(displayName) into \(target.selectorTitle) slot \(target.slotIndex + 1). Save the bank window to write the updated bank file."
                errorMessage = nil
            } catch {
                statusMessage = nil
                errorMessage = "Store to bank window failed: \(error)"
            }
        case .fb01:
            let openDeviceBanks = openFB01DeviceBankWindows()
            if let origin = fb01DeviceBankOrigin {
                storeToFB01DeviceBank(
                    workspace: workspace,
                    device: device,
                    bank: origin.bank,
                    slotIndex: origin.slotIndex,
                    bankTitle: origin.bankTitle
                )
                return
            }

            if !openDeviceBanks.isEmpty {
                guard let target = chooseFB01DeviceBankStoreTarget(
                    banks: openDeviceBanks,
                    preferredOrigin: fb01DeviceBankOrigin,
                    voiceNameProvider: { bank, slotIndex in
                        workspace.voiceNameInFB01DeviceBank(bank: bank, slotIndex: slotIndex)
                    }
                ) else {
                    return
                }

                storeToFB01DeviceBank(
                    workspace: workspace,
                    device: device,
                    bank: target.bank,
                    slotIndex: target.slotIndex,
                    bankTitle: target.bankTitle
                )
                return
            }

            let selectors = workspace.openFB01VoiceBankFileSelectors
            guard !selectors.isEmpty else {
                errorMessage = "Open an FB-01 bank window before storing this voice into a bank window."
                statusMessage = nil
                return
            }

            if let origin = fb01BankFileOrigin,
               selectors.contains(where: { $0.id == origin.selectorID }) {
                do {
                    try workspace.replaceVoice(inFB01VoiceBankFileSelector: origin.selectorID, slotIndex: origin.slotIndex, with: voice)
                    markCurrentStateSaved()
                    _ = workspace.bringWindowToFront(identifier: EditorDocumentWorkspace.fb01VoiceBankFileSelectorWindowIdentifier(for: origin.selectorID))
                    statusMessage = "Stored \(displayName) into \(origin.bankTitle) slot \(origin.slotIndex + 1). Save the bank window to write the updated bank file."
                    errorMessage = nil
                } catch {
                    statusMessage = nil
                    errorMessage = "Store to bank window failed: \(error)"
                }
                return
            }

            guard let target = chooseFB01BankFileStoreTarget(selectors: selectors, preferredOrigin: fb01BankFileOrigin) else {
                return
            }

            do {
                try workspace.replaceVoice(inFB01VoiceBankFileSelector: target.selectorID, slotIndex: target.slotIndex, with: voice)
                fb01BankFileOrigin = FB01BankFileVoiceOrigin(
                    selectorID: target.selectorID,
                    slotIndex: target.slotIndex,
                    bankTitle: target.selectorTitle
                )
                markCurrentStateSaved()
                _ = workspace.bringWindowToFront(identifier: EditorDocumentWorkspace.fb01VoiceBankFileSelectorWindowIdentifier(for: target.selectorID))
                statusMessage = "Stored \(displayName) into \(target.selectorTitle) slot \(target.slotIndex + 1). Save the bank window to write the updated bank file."
                errorMessage = nil
            } catch {
                statusMessage = nil
                errorMessage = "Store to bank window failed: \(error)"
            }
        }
    }

    private func storeToFB01DeviceBank(
        workspace: EditorDocumentWorkspace,
        device: DocumentModel,
        bank: Int,
        slotIndex: Int,
        bankTitle: String
    ) {
        isBusy = true
        statusMessage = "Preparing \(bankTitle) slot \(slotIndex + 1) for update..."
        errorMessage = nil

        let progressPanel = EditorProgressPanel(
            title: "Store Voice to Open Bank Window",
            message: "The bank window is being updated. Please wait.\nPreparing \(bankTitle) slot \(slotIndex + 1)..."
        )
        progressPanel.show()

        Task {
            do {
                try await device.ensureFB01VoiceBankCachedForEditing(bank: bank)
                try device.replaceCachedVoice(inBank: bank, slotIndex: slotIndex, with: voice)
                guard let cachedVoice = device.cachedVoice(inBank: bank, slotIndex: slotIndex) else {
                    throw FB01AppError.message("Voice Bank \(bank) slot \(slotIndex + 1) did not remain available after the update.")
                }
                guard cachedVoice == voice else {
                    throw FB01AppError.message("Voice Bank \(bank) slot \(slotIndex + 1) did not accept the updated voice in cache.")
                }
                fb01DeviceBankOrigin = FB01DeviceBankVoiceOrigin(
                    bank: bank,
                    slotIndex: slotIndex,
                    bankTitle: bankTitle
                )
                markCurrentStateSaved()
                _ = workspace.bringWindowToFront(identifier: EditorDocumentWorkspace.voiceBankSelectorWindowIdentifier(for: bank))
                statusMessage = "Stored \(displayName) into \(bankTitle) slot \(slotIndex + 1). Save the bank window to write the updated bank file, or use Store Bank to write it to the FB-01."
                errorMessage = nil
            } catch {
                statusMessage = nil
                errorMessage = "Store to bank window failed: \(error)"
                showEditorError(title: "Store to Bank Window Failed", message: "\(error)")
            }
            progressPanel.dismiss()
            isBusy = false
        }
    }

    private struct DX100BankFileStoreTarget {
        var selectorID: UUID
        var selectorTitle: String
        var slotIndex: Int
    }

    private func chooseDX100BankFileStoreTarget(
        selectors: [EditorDocumentWorkspace.DX100VoiceBankFileSelector],
        preferredOrigin: DX100BankFileVoiceOrigin?
    ) -> DX100BankFileStoreTarget? {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Store Voice to Open Bank Window"
        alert.informativeText = "Choose which open DX100/27 bank window and which slot should receive this voice."
        alert.addButton(withTitle: "Store")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        let accessory = DX100BankFileStoreAccessory(selectors: selectors, preferredOrigin: preferredOrigin)
        alert.accessoryView = accessory

        guard alert.runModal() == .alertFirstButtonReturn,
              let selection = accessory.selection else {
            return nil
        }
        return DX100BankFileStoreTarget(
            selectorID: selection.selector.id,
            selectorTitle: selection.selector.title,
            slotIndex: selection.item.slotIndex
        )
    }

    private struct FB01BankFileStoreTarget {
        var selectorID: UUID
        var selectorTitle: String
        var slotIndex: Int
    }

    private struct FB01DeviceBankStoreTarget {
        var bank: Int
        var bankTitle: String
        var slotIndex: Int
    }

    private func chooseFB01BankFileStoreTarget(
        selectors: [EditorDocumentWorkspace.FB01VoiceBankFileSelector],
        preferredOrigin: FB01BankFileVoiceOrigin?
    ) -> FB01BankFileStoreTarget? {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Store Voice to Open Bank Window"
        alert.informativeText = "Choose which open FB-01 bank window and which slot should receive this voice."
        alert.addButton(withTitle: "Store")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        let accessory = FB01BankFileStoreAccessory(selectors: selectors, preferredOrigin: preferredOrigin)
        alert.accessoryView = accessory

        guard alert.runModal() == .alertFirstButtonReturn,
              let selection = accessory.selection else {
            return nil
        }
        return FB01BankFileStoreTarget(
            selectorID: selection.selector.id,
            selectorTitle: selection.selector.title,
            slotIndex: selection.item.slotIndex
        )
    }

    private func chooseFB01DeviceBankStoreTarget(
        banks: [Int],
        preferredOrigin: FB01DeviceBankVoiceOrigin?,
        voiceNameProvider: @escaping (Int, Int) -> String?
    ) -> FB01DeviceBankStoreTarget? {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Store Voice to Open Bank Window"
        alert.informativeText = "Choose which open FB-01 device bank window and which slot should receive this voice."
        alert.addButton(withTitle: "Store")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        let accessory = FB01DeviceBankStoreAccessory(
            banks: banks,
            preferredOrigin: preferredOrigin,
            voiceNameProvider: voiceNameProvider
        )
        alert.accessoryView = accessory

        guard alert.runModal() == .alertFirstButtonReturn,
              let selection = accessory.selection else {
            return nil
        }

        return FB01DeviceBankStoreTarget(
            bank: selection.bank,
            bankTitle: "Voice Bank \(selection.bank)",
            slotIndex: selection.slotIndex
        )
    }

    private func openFB01DeviceBankWindows() -> [Int] {
        NSApp.windows.compactMap { window in
            guard let raw = window.identifier?.rawValue,
                  raw.hasPrefix("voice-bank-selector-"),
                  let bank = Int(raw.replacingOccurrences(of: "voice-bank-selector-", with: ""))
            else {
                return nil
            }
            return bank
        }
        .sorted()
    }

    func sendKeyboardNote(_ note: Int, isOn: Bool, device: DocumentModel) {
        guard !device.isBusy else {
            device.statusMessage = "Keyboard paused while the FB-01 is busy with a device operation."
            return
        }

        let boundedNote = min(max(note, 0), 127)
        let destinationIndex = device.selectedDestinationIndex
        let destinationName = device.selectedDestinationName
        let channel = UInt8(min(max(device.keyboardChannel, 0), 15))
        let velocity = UInt8(min(max(device.keyboardVelocity, 1), 127))
        let noteMessage = [
            (isOn ? 0x90 : 0x80) | channel,
            UInt8(boundedNote),
            isOn ? velocity : 0,
        ]
        Task(priority: .high) { [weak self, weak device] in
            do {
                try await LiveMIDIPlaybackController.shared.sendImmediate(noteMessage, destinationIndex: destinationIndex)
                if isOn {
                    await MainActor.run {
                        device?.externalKeyboardStatus = "Sent note \(boundedNote) on channel \(Int(channel) + 1) to \(destinationName)."
                        self?.errorMessage = nil
                        if let device {
                            self?.scheduleKeyboardVoicePreparation(device: device)
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    self?.errorMessage = "Keyboard note failed: \(error)"
                    self?.statusMessage = nil
                }
            }
        }
    }

    func scheduleKeyboardVoicePreparation(device: DocumentModel, delayNanoseconds: UInt64 = 0) {
        keyboardPreparationTask?.cancel()

        let destinationIndex = device.selectedDestinationIndex
        let channel = min(max(device.keyboardChannel, 0), 15)

        do {
            let signature = keyboardPreparationSignature(midiChannel: channel, portamento: device.externalKeyboardPortamento)
            guard needsKeyboardPreparation(signature: signature) || !device.isAuditionBufferPrepared(signature: signature) else {
                return
            }

            let messages = try buildKeyboardPreparationMessages(midiChannel: channel, device: device)
            keyboardPreparationTask = Task(priority: .userInitiated) { [weak self] in
                do {
                    if delayNanoseconds > 0 {
                        try await Task.sleep(nanoseconds: delayNanoseconds)
                    }
                    try Task.checkCancellation()
                    try await LiveMIDIPlaybackController.shared.sendPreparedMessages(
                        messages,
                        destinationIndex: destinationIndex,
                        settleDelay: 0
                    )
                    try Task.checkCancellation()
                    await MainActor.run {
                        self?.markKeyboardPrepared(signature: signature)
                        device.markAuditionBufferPrepared(signature: signature)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    await MainActor.run {
                        self?.errorMessage = "Keyboard voice preparation failed: \(error)"
                        self?.statusMessage = nil
                    }
                }
            }
        } catch {
            errorMessage = "Keyboard voice preparation failed: \(error)"
            statusMessage = nil
        }
    }

    func cancelKeyboardVoicePreparation() {
        keyboardPreparationTask?.cancel()
        keyboardPreparationTask = nil
    }

    func scheduleDX100LiveResend(device: DocumentModel, delayNanoseconds: UInt64) {
        dx100LiveResendTask?.cancel()

        guard sourceDevice == .dx100,
              device.selectedEditorDevice == .dx100,
              !isBusy,
              !device.isBusy,
              isEdited
        else {
            return
        }

        let neutralVoiceToSend = neutralVoice
        let sourceIndex = device.selectedSourceIndex
        let destinationIndex = device.selectedDestinationIndex
        let systemChannel = self.systemChannel
        let destinationName = device.selectedDestinationName
        let signature = "\(systemChannel)-\(neutralVoiceToSend)"

        guard signature != lastDX100LiveSentSignature else {
            return
        }

        dx100LiveResendTask = Task(priority: .userInitiated) { [weak self] in
            do {
                if delayNanoseconds > 0 {
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                }
                try Task.checkCancellation()
                try await Task.detached(priority: .userInitiated) {
                    try EditorVoiceDocumentService.storeVoiceDocument(
                        neutralVoiceToSend,
                        to: .dx100,
                        sourceIndex: sourceIndex,
                        destinationIndex: destinationIndex,
                        systemChannel: systemChannel
                    )
                }.value
                try Task.checkCancellation()
                await MainActor.run {
                    self?.lastDX100LiveSentSignature = signature
                    self?.statusMessage = "Live DX100/27 edit sent to \(destinationName)."
                    self?.errorMessage = nil
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    self?.errorMessage = "DX100 live edit failed: \(error)"
                    self?.statusMessage = nil
                }
            }
        }
    }

    func cancelDX100LiveResend() {
        dx100LiveResendTask?.cancel()
        dx100LiveResendTask = nil
    }

    func value(for macro: PerformanceMacro) -> Int {
        performanceMacroValues[macro] ?? PerformanceMacro.neutralValue
    }

    func setPerformanceMacro(_ macro: PerformanceMacro, value proposedValue: Int) {
        let newValue = min(max(proposedValue, PerformanceMacro.range.lowerBound), PerformanceMacro.range.upperBound)
        let oldValue = value(for: macro)
        guard newValue != oldValue else { return }

        do {
            let updatedProjection = try macro.apply(
                previousValue: oldValue,
                newValue: newValue,
                characterType: voiceCharacterType,
                to: voice
            )
            applyProjectedEdit(updatedProjection)
            performanceMacroValues[macro] = newValue
            statusMessage = "\(macro.title) macro changed \(macro.touchedParametersDescription(for: voiceCharacterType))."
        } catch {
            errorMessage = "\(macro.title) macro failed: \(error)"
            statusMessage = nil
        }
    }

    private func resetPerformanceMacros() {
        performanceMacroValues = PerformanceMacro.neutralValues
    }

    func receiveExternalKeyboardMessage(_ message: [UInt8], device: DocumentModel) -> Bool {
        guard !device.isBusy else {
            device.externalKeyboardStatus = "Paused during device operation"
            return true
        }

        guard let status = message.first, (0x80...0xEF).contains(status) else {
            return false
        }

        let event = status & 0xF0
        let isVolumeControl = event == 0xB0 && message.count == 3 && message[1] == 7
        if isVolumeControl {
            return false
        }

        let channel = UInt8(min(max(device.keyboardChannel, 0), 15))
        let rewritten = [event | channel] + message.dropFirst()
        let isNoteOn = event == 0x90 && message.count > 2 && message[2] > 0

        let destinationIndex = device.selectedDestinationIndex
        let destinationName = device.selectedDestinationName

        let forwardingStatus: String
        if isNoteOn, message.count > 1 {
            forwardingStatus = "Keyboard input sent note \(message[1]) on channel \(Int(channel) + 1) to \(destinationName)."
        } else if event == 0xB0, message.count > 2 {
            forwardingStatus = "Keyboard input forwarded CC \(message[1]) value \(message[2]) to \(destinationName)."
        } else {
            forwardingStatus = "Keyboard input forwarding to \(destinationName)."
        }

        if device.shouldSuppressExternalKeyboardEchoBackToDevice(for: message) {
            if isNoteOn {
                device.externalKeyboardStatus = "DX100/27 local keyboard direct; not echoed back."
            }
            return true
        }

        Task(priority: .high) { [weak self, weak device] in
            do {
                try await LiveMIDIPlaybackController.shared.sendImmediate(rewritten, destinationIndex: destinationIndex)
                device?.externalKeyboardStatus = forwardingStatus
                self?.errorMessage = nil
            } catch {
                self?.errorMessage = "Keyboard input failed: \(error)"
                self?.statusMessage = nil
            }
        }
        return true
    }

    private func save(to url: URL, voiceNameFromFile: String? = nil) {
        do {
            let savedPayload: FB01VoiceData
            let savedNeutral: FourOperatorVoiceData

            if sourceDevice == .dx100 {
                var dxNeutralVoice = neutralVoice
                if let voiceNameFromFile {
                    dxNeutralVoice.name = voiceNameFromFile
                }
                let dxVoice = try dxNeutralVoice.dx100Voice()
                try DX100DocumentService.shared.writeVoice(dxVoice, channel: systemChannel, to: url)
                let projectedName = String(dxNeutralVoice.name.prefix(FB01VoiceData.nameLength))
                savedPayload = try voice.settingName(projectedName)
                savedNeutral = dxNeutralVoice
            } else {
                savedPayload = try voiceNameFromFile.map { try voice.settingName($0) } ?? voice
                try EditorModuleDocumentFiles.writeVoice(savedPayload, systemChannel: systemChannel, to: url)
                savedNeutral = savedPayload.fourOperatorVoice
            }

            if savedPayload != voice || savedNeutral != neutralVoice {
                applyDocumentVoices(
                    workingNeutral: savedNeutral,
                    projection: savedPayload
                )
                noteVoiceReplacement()
                preparedKeyboardVoiceSignature = nil
                preparedKeyboardVoiceDate = nil
            }
            savedNeutralVoice = savedNeutral
            savedProjectionOverlay = FB01VoiceProjectionOverlay(voice: savedPayload)
            savedProjectedVoiceCache = savedPayload
            fileURL = url
            rememberEditorSaveDirectory(for: url)
            statusMessage = "Saved \(url.lastPathComponent)."
            errorMessage = nil
        } catch {
            errorMessage = "Save failed: \(error)"
            statusMessage = nil
        }
    }

    private func keyboardPreparationMessages(midiChannel: Int, device: DocumentModel) throws -> [[UInt8]] {
        let signature = keyboardPreparationSignature(midiChannel: midiChannel, portamento: device.externalKeyboardPortamento)
        guard needsKeyboardPreparation(signature: signature) || !device.isAuditionBufferPrepared(signature: signature) else {
            return []
        }

        let messages = try buildKeyboardPreparationMessages(midiChannel: midiChannel, device: device)
        markKeyboardPrepared(signature: signature)
        device.markAuditionBufferPrepared(signature: signature)
        return messages
    }

    private func buildKeyboardPreparationMessages(midiChannel: Int, device: DocumentModel) throws -> [[UInt8]] {
        if sourceDevice == .dx100 {
            return try DX100ModuleServices.shared.voiceService.editBufferMessages(
                for: neutralVoice.dx100Voice(),
                channel: systemChannel
            ) + device.liveKeyboardPortamentoMessages(
                value: device.externalKeyboardPortamento,
                systemChannel: systemChannel,
                midiChannel: midiChannel
            )
        }

        return try FB01VoiceDocumentService.auditionPreparationMessages(
            voice: voice,
            systemChannel: systemChannel,
            midiChannel: midiChannel
        ) + device.liveKeyboardPortamentoMessages(
            value: device.externalKeyboardPortamento,
            systemChannel: systemChannel,
            midiChannel: midiChannel
        )
    }

    private func keyboardPreparationSignature(midiChannel: Int, portamento: Int) -> String {
        "\(systemChannel)-\(midiChannel)-\(voice.bytes)-portamento-\(portamento)"
    }

    private var defaultVoiceFileExtension: String {
        switch sourceDevice {
        case .dx100:
            return DX100SynthModule.shared.fileProfile.singleVoiceExtension
        case .fb01:
            return FB01SynthModule.shared.fileProfile.singleVoiceExtension
        }
    }

    private func needsKeyboardPreparation(signature: String) -> Bool {
        preparedKeyboardVoiceSignature != signature || isKeyboardPreparationStale
    }

    private func markKeyboardPrepared(signature: String) {
        preparedKeyboardVoiceSignature = signature
        preparedKeyboardVoiceDate = Date()
    }

    private func noteVoiceReplacement() {
        layoutRevision &+= 1
        preparedKeyboardVoiceSignature = nil
        preparedKeyboardVoiceDate = nil
        lastDX100LiveSentSignature = nil
    }

    private func markCurrentStateSaved() {
        savedNeutralVoice = neutralVoice
        savedProjectionOverlay = FB01VoiceProjectionOverlay(voice: voice)
        savedProjectedVoiceCache = voice
    }

    private func updateOrigins(
        for source: VoiceDocumentFetchSource,
        device: EditorDeviceSelection,
        bankTitleProvider: (Int) -> String
    ) {
        switch device {
        case .fb01:
            dx100BankFileOrigin = nil
            fb01BankFileOrigin = nil
            switch source {
            case let .storedSlot(location, voiceNumber):
                switch location {
                case .bank(let bank):
                    fb01DeviceBankOrigin = FB01DeviceBankVoiceOrigin(
                        bank: bank,
                        slotIndex: voiceNumber,
                        bankTitle: bankTitleProvider(bank)
                    )
                case .voiceRAM1:
                    fb01DeviceBankOrigin = nil
                }
            case .currentVoice, .instrument, .dx100Bank:
                fb01DeviceBankOrigin = nil
            }
        case .dx100:
            fb01DeviceBankOrigin = nil
            fb01BankFileOrigin = nil
        }
    }

    private var isKeyboardPreparationStale: Bool {
        guard let preparedKeyboardVoiceDate else {
            return true
        }
        return Date().timeIntervalSince(preparedKeyboardVoiceDate) > keyboardPreparationStaleAfter
    }

    static func readVoiceDocument(from url: URL, context: VoiceDocumentLoadContext = .singleOrGeneric) throws -> LoadedVoiceDocument {
        let extensionHint = url.pathExtension.lowercased()
        let dxExtensions = Set(DX100SynthModule.shared.fileProfile.importExtensions.map { $0.lowercased() })
        let fbExtensions = Set(FB01SynthModule.shared.fileProfile.importExtensions.map { $0.lowercased() })

        if dxExtensions.contains(extensionHint), extensionHint != "syx" {
            do {
                return try readDX100VoiceDocument(from: url, context: context, extensionHint: extensionHint)
            } catch {
                throw FB01AppError.message("This file appears to be a DX100/27 voice file, but it could not be read: \(error)")
            }
        }

        if fbExtensions.contains(extensionHint), extensionHint != "syx" {
            do {
                return try readFB01VoiceDocument(from: url)
            } catch {
                throw FB01AppError.message("This file appears to be an FB-01 voice file, but it could not be read: \(error)")
            }
        }

        if let loaded = try? readDX100VoiceDocument(from: url, context: context, extensionHint: extensionHint) {
            return loaded
        }

        if let loaded = try? readFB01VoiceDocument(from: url) {
            return loaded
        }

        throw FB01AppError.message("The file does not contain a readable FB-01 or DX100/27 voice.")
    }

    private static func readFB01VoiceDocument(from url: URL) throws -> LoadedVoiceDocument {
        let candidates = try EditorModuleDocumentFiles.voiceCandidates(from: url)
        guard let candidate = chooseVoiceCandidate(candidates, title: "Choose Voice Document") else {
            throw FB01AppError.noVoiceSource
        }
        return LoadedVoiceDocument(
            projection: candidate.voice,
            neutralVoice: candidate.voice.fourOperatorVoice,
            systemChannel: candidate.systemChannel,
            sourceDevice: .fb01
        )
    }

    private static func readDX100VoiceDocument(from url: URL, context: VoiceDocumentLoadContext, extensionHint: String) throws -> LoadedVoiceDocument {
        let candidates = try DX100DocumentService.shared.readVoiceCandidates(from: url)
        let isBankFile = context == .bankFile || extensionHint == DX100SynthModule.shared.fileProfile.voiceBankExtension || (extensionHint == DX100SynthModule.shared.fileProfile.genericSysExExtension && candidates.count > 1)
        let title = isBankFile ? "Choose Voice from DX100/27 Voice Bank File" : "Choose DX100/27 Voice Document"
        let informativeText = isBankFile
            ? "This DX100/27 voice bank file contains the 24 displayed voices extracted from a 32-voice bulk dump. Choose one voice to open in this document window."
            : "This DX100/27 SysEx file contains multiple voices. Choose the one to open in this document window."
        guard let candidate = chooseDX100VoiceCandidate(candidates, title: title, informativeText: informativeText) else {
            throw FB01AppError.noVoiceSource
        }
        return LoadedVoiceDocument(
            projection: try candidate.voice.fb01EditableVoice(),
            neutralVoice: candidate.voice.fourOperatorVoice,
            systemChannel: candidate.channel,
            sourceDevice: .dx100
        )
    }

    nonisolated private static func extractVoice(from artifact: FB01Artifact) throws -> (voice: FB01VoiceData, systemChannel: Int) {
        let candidates = try EditorDocumentExtraction.voiceCandidates(from: artifact)
        guard let candidate = candidates.first else {
            throw FB01AppError.noVoiceSource
        }
        return (candidate.voice, candidate.systemChannel)
    }

    private static func chooseVoiceCandidate(_ candidates: [VoiceDocumentCandidate], title: String) -> VoiceDocumentCandidate? {
        guard candidates.count > 1 else {
            return candidates.first
        }

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "This SysEx file contains multiple voices. Choose the one to open in this document window."
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")

        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        for candidate in candidates {
            popup.addItem(withTitle: candidate.title)
            popup.lastItem?.representedObject = candidate.title
        }
        alert.accessoryView = labelledEditorPopup(label: "Voice:", popup: popup)

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }
        return candidates[popup.indexOfSelectedItem]
    }

    private static func chooseDX100VoiceCandidate(_ candidates: [DX100VoiceDocumentCandidate], title: String, informativeText: String) -> DX100VoiceDocumentCandidate? {
        guard candidates.count > 1 else {
            return candidates.first
        }

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = informativeText
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")

        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        for candidate in candidates {
            popup.addItem(withTitle: candidate.title)
            popup.lastItem?.representedObject = candidate.title
        }
        alert.accessoryView = labelledEditorPopup(label: "Voice:", popup: popup)

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }
        return candidates[popup.indexOfSelectedItem]
    }

    private func applyDocumentVoices(
        workingNeutral: FourOperatorVoiceData,
        projection: FB01VoiceData,
        savedNeutral: FourOperatorVoiceData? = nil,
        savedProjection: FB01VoiceData? = nil
    ) {
        neutralVoice = workingNeutral
        projectionOverlay = FB01VoiceProjectionOverlay(voice: projection)
        projectedVoiceCache = projection
        if let savedNeutral {
            savedNeutralVoice = savedNeutral
        }
        if let savedProjection {
            savedProjectionOverlay = FB01VoiceProjectionOverlay(voice: savedProjection)
            savedProjectedVoiceCache = savedProjection
        }
    }

    private func applyNeutralEdit(_ updatedNeutralVoice: FourOperatorVoiceData) {
        do {
            let updatedProjection = try projectionOverlay.apply(to: updatedNeutralVoice)
            neutralVoice = updatedNeutralVoice
            projectedVoiceCache = updatedProjection
            preparedKeyboardVoiceSignature = nil
            preparedKeyboardVoiceDate = nil
            errorMessage = nil
            statusMessage = nil
        } catch {
            errorMessage = "Edit failed: \(error)"
        }
    }

    private func applyProjectedEdit(_ editedVoice: FB01VoiceData) {
        var editedNeutralVoice = editedVoice.fourOperatorVoice
        if sourceDevice == .dx100 {
            editedNeutralVoice.name = neutralVoice.name
        }
        neutralVoice = editedNeutralVoice
        projectionOverlay = FB01VoiceProjectionOverlay(voice: editedVoice)
        projectedVoiceCache = editedVoice
        preparedKeyboardVoiceSignature = nil
        preparedKeyboardVoiceDate = nil
        errorMessage = nil
        statusMessage = nil
    }

    private static func chooseFetchSource(
        title: String,
        actionTitle: String,
        nameLookup: VoiceDocumentFetchNameLookup = .empty,
        systemChannel: Int? = nil
    ) -> VoiceDocumentFetchSource? {
        let sourcePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        sourcePopup.addItem(withTitle: "Current Instrument Voice")
        sourcePopup.addItem(withTitle: "Stored Voice Slot")
        sourcePopup.selectItem(at: 1)

        let instrumentPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for instrument in 1...8 {
            instrumentPopup.addItem(withTitle: "Instrument \(instrument)")
        }

        let bankPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        let module = FB01ModuleServices.shared.module
        let fetchLocations: [VoiceDocumentFetchLocation] = module.allVoiceBanks.map { .bank($0) } + [.voiceRAM1]
        for location in fetchLocations {
            bankPopup.addItem(withTitle: location.menuTitle)
        }

        let voicePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        let nameStatusLabel = NSTextField(labelWithString: "")
        nameStatusLabel.textColor = .secondaryLabelColor
        nameStatusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        let controller = VoiceFetchDialogController()
        controller.sourcePopup = sourcePopup
        controller.instrumentPopup = instrumentPopup
        controller.bankPopup = bankPopup
        controller.voicePopup = voicePopup
        controller.updateVoiceChoices = {
            let selectedIndex = max(0, min(bankPopup.indexOfSelectedItem, fetchLocations.count - 1))
            let location = fetchLocations[selectedIndex]
            let selectedVoice = max(0, voicePopup.indexOfSelectedItem)
            voicePopup.removeAllItems()
            for voiceNumber in 1...module.voicesPerBank {
                voicePopup.addItem(withTitle: nameLookup.voiceMenuTitle(location: location, voiceNumber: voiceNumber))
            }
            voicePopup.selectItem(at: min(selectedVoice, module.voicesPerBank - 1))
            if let selectedTitle = voicePopup.selectedItem?.title {
                voicePopup.setTitle(selectedTitle)
            }
            let channelSuffix = systemChannel.map { " - System channel \($0 + 1)" } ?? ""
            nameStatusLabel.stringValue = "\(nameLookup.statusTitle(for: location))\(channelSuffix)"
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 330),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.isReleasedWhenClosed = false
        panel.center()

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 330))
        panel.contentView = content

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .boldSystemFont(ofSize: 16)
        titleLabel.frame = NSRect(x: 24, y: 286, width: 512, height: 22)
        content.addSubview(titleLabel)

        let infoLabel = NSTextField(wrappingLabelWithString: "Choose a current instrument voice, or fetch one stored voice by reading Banks 1-7 or Voice RAM 1 and extracting the selected slot.")
        infoLabel.textColor = .secondaryLabelColor
        infoLabel.font = .systemFont(ofSize: 13)
        infoLabel.frame = NSRect(x: 24, y: 238, width: 512, height: 42)
        content.addSubview(infoLabel)

        func addRow(label: String, popup: NSPopUpButton, y: CGFloat) {
            let labelField = NSTextField(labelWithString: label)
            labelField.alignment = .right
            labelField.frame = NSRect(x: 48, y: y + 4, width: 132, height: 20)
            content.addSubview(labelField)

            popup.controlSize = .regular
            popup.frame = NSRect(x: 196, y: y, width: 300, height: 26)
            content.addSubview(popup)
        }

        addRow(label: "Fetch:", popup: sourcePopup, y: 198)
        addRow(label: "Instrument:", popup: instrumentPopup, y: 160)
        addRow(label: "Bank:", popup: bankPopup, y: 122)
        addRow(label: "Voice:", popup: voicePopup, y: 84)

        nameStatusLabel.frame = NSRect(x: 196, y: 66, width: 300, height: 16)
        content.addSubview(nameStatusLabel)

        let warningLabel = NSTextField(wrappingLabelWithString: "Stored voice fetch reads the whole selected bank internally, then opens only the chosen voice document. Store remains limited to writable Banks 1-2.")
        warningLabel.textColor = .secondaryLabelColor
        warningLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        warningLabel.frame = NSRect(x: 24, y: 46, width: 512, height: 32)
        content.addSubview(warningLabel)

        let cancelButton = NSButton(title: "Cancel", target: controller, action: #selector(VoiceFetchDialogController.cancel))
        cancelButton.frame = NSRect(x: 316, y: 14, width: 96, height: 30)
        cancelButton.keyEquivalent = "\u{1b}"
        content.addSubview(cancelButton)

        let fetchButton = NSButton(title: actionTitle, target: controller, action: #selector(VoiceFetchDialogController.accept))
        fetchButton.frame = NSRect(x: 424, y: 14, width: 112, height: 30)
        fetchButton.keyEquivalent = "\r"
        content.addSubview(fetchButton)

        sourcePopup.target = controller
        sourcePopup.action = #selector(VoiceFetchDialogController.updateControls)
        bankPopup.target = controller
        bankPopup.action = #selector(VoiceFetchDialogController.updateControls)
        controller.updateControls()

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.runModal(for: panel)
        panel.orderOut(nil)

        guard controller.result == .OK else {
            return nil
        }

        if sourcePopup.indexOfSelectedItem == 0 {
            return .instrument(instrumentPopup.indexOfSelectedItem)
        }
        return .storedSlot(location: fetchLocations[bankPopup.indexOfSelectedItem], voiceNumber: voicePopup.indexOfSelectedItem)
    }

    @MainActor
    private static func chooseStoreOptions(defaultVoiceName: String) -> VoiceDocumentStoreOptions? {
        let alert = NSAlert()
        alert.messageText = "Store Voice to FB-01"
        alert.informativeText = "This saves a backup of the destination RAM bank, writes \(defaultVoiceName.isEmpty ? "this voice" : defaultVoiceName) into a Bank 1 or Bank 2 slot, then reads the bank back until the destination voice verifies."
        alert.addButton(withTitle: "Store and Overwrite")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        let stack = NSStackView()
        stack.frame = NSRect(x: 0, y: 0, width: 520, height: 116)
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .leading

        let bankPopup = NSPopUpButton(frame: .zero, pullsDown: false)
        let module = FB01ModuleServices.shared.module
        for bank in module.writableVoiceBanks {
            bankPopup.addItem(withTitle: "Bank \(bank)")
        }

        let voicePopup = NSPopUpButton(frame: .zero, pullsDown: false)
        for voice in 1...module.voicesPerBank {
            voicePopup.addItem(withTitle: "Voice \(voice)")
        }

        stack.addArrangedSubview(labelledEditorPopup(label: "Bank:", popup: bankPopup))
        stack.addArrangedSubview(labelledEditorPopup(label: "Voice:", popup: voicePopup))
        stack.addArrangedSubview(makeWarningLabel("A timestamped backup is saved automatically before overwrite. Only Bank 1 and Bank 2 are writable."))
        alert.accessoryView = stack

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }

        let bank = bankPopup.indexOfSelectedItem
        let voiceNumber = voicePopup.indexOfSelectedItem
        return VoiceDocumentStoreOptions(
            bank: bank,
            voiceNumber: voiceNumber
        )
    }

}

import AppKit
import Combine
import FB01Editor
import Foundation
import UniformTypeIdentifiers

@MainActor
final class VoiceDocumentModel: ObservableObject, Identifiable {
    let id = UUID()
    @Published var voice: FB01VoiceData
    @Published var savedVoice: FB01VoiceData
    @Published var systemChannel: Int
    @Published var fileURL: URL?
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    @Published var isBusy = false
    @Published var selectedOperatorIndex = FB01VoiceData.dataIndex(forOperatorNumber: 1)
    @Published var voiceCharacterType: VoiceCharacterType = .other
    @Published var performanceMacroValues = PerformanceMacro.neutralValues
    @Published var layoutRevision = 0
    private var preparedKeyboardVoiceSignature: String?
    private var preparedKeyboardVoiceDate: Date?
    private var keyboardPreparationTask: Task<Void, Never>?

    init(voice: FB01VoiceData, systemChannel: Int, fileURL: URL? = nil) {
        self.voice = voice
        self.savedVoice = voice
        self.systemChannel = systemChannel
        self.fileURL = fileURL
    }

    var title: String {
        let name = voice.name.isEmpty ? "Untitled Voice" : voice.name
        if isBusy {
            return "\(name) (Working)"
        }
        return isEdited ? "\(name) *" : name
    }

    var isEdited: Bool {
        voice != savedVoice
    }

    func reset() {
        voice = savedVoice
        resetPerformanceMacros()
        noteVoiceReplacement()
        errorMessage = nil
        statusMessage = "Reverted to last saved version."
    }

    func updateVoice(_ edit: (FB01VoiceData) throws -> FB01VoiceData) {
        do {
            let editedVoice = try edit(voice)
            guard editedVoice != voice else { return }
            voice = editedVoice
            preparedKeyboardVoiceSignature = nil
            preparedKeyboardVoiceDate = nil
            errorMessage = nil
            statusMessage = nil
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
        let limited = String(value.prefix(FB01VoiceData.nameLength))
        guard limited != voice.name else { return }
        updateVoice { try $0.settingName(limited) }
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
        panel.allowedContentTypes = UTType.currentModuleVoiceFileTypes
        panel.directoryURL = preferredEditorSaveDirectoryURL()
        panel.nameFieldStringValue = "\(safeEditorFileName(voice.name, fallback: "voice")).\(EditorSynthModule.fileProfile.singleVoiceExtension)"
        panel.message = "Save this voice document to a voice file."
        panel.prompt = "Save Voice to File"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        save(to: url, voiceNameFromFile: editorDocumentName(
            fromFileURL: url,
            maxLength: FB01VoiceData.nameLength,
            fallback: "voice"
        ))
    }

    static func loadFromDisk() -> VoiceDocumentModel? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = UTType.currentModuleReadableVoiceFileTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = preferredEditorLoadDirectoryURL()
        panel.message = "Load a voice file into a new voice document window."
        panel.prompt = "Load Voice from File"

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        do {
            let (voice, systemChannel) = try readVoice(from: url)
            rememberEditorLoadDirectory(for: url)
            return VoiceDocumentModel(voice: voice, systemChannel: systemChannel, fileURL: url)
        } catch {
            showEditorError(title: "Load Voice Failed", message: "\(error)")
            return nil
        }
    }

    static func loadFromDisk(url: URL) -> VoiceDocumentModel? {
        do {
            let (voice, systemChannel) = try readVoice(from: url)
            rememberEditorLoadDirectory(for: url)
            return VoiceDocumentModel(voice: voice, systemChannel: systemChannel, fileURL: url)
        } catch {
            showEditorError(title: "Load Voice Failed", message: "\(error)")
            return nil
        }
    }

    func importFromDisk() {
        guard !isBusy else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = UTType.currentModuleReadableVoiceFileTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = preferredEditorLoadDirectoryURL()
        panel.message = "Import a voice file into this voice document, replacing its current contents."
        panel.prompt = "Import Voice from File"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let (importedVoice, importedSystemChannel) = try Self.readVoice(from: url)
            voice = importedVoice
            savedVoice = importedVoice
            resetPerformanceMacros()
            systemChannel = importedSystemChannel
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

    func fetchFromDevice(device: DocumentModel, source preselectedSource: VoiceDocumentFetchSource? = nil, recentTitle: String? = nil) {
        guard !isBusy else { return }
        let sourceIndex = device.selectedSourceIndex
        let destinationIndex = device.selectedDestinationIndex
        let systemChannel = device.systemChannel

        isBusy = true
        let systemChannelName = "System channel \(systemChannel + 1)"
        errorMessage = nil
        if preselectedSource == nil {
            statusMessage = "Reading Bank 1 and Bank 2 voice names from FB-01 on \(systemChannelName)..."
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
                        title: "Reading Voice Names",
                        message: "Reading Bank 1 and Bank 2 from the FB-01 on \(systemChannelName) so the Fetch dialog can show current RAM voice names."
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
                voice = cachedResult.voice
                savedVoice = cachedResult.voice
                resetPerformanceMacros()
                self.systemChannel = cachedResult.systemChannel
                fileURL = nil
                noteVoiceReplacement()
                let fetchedName = cachedResult.voice.name.isEmpty ? "Untitled" : cachedResult.voice.name
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
                message: "The voice is being fetched. Please wait.\nReading \(fetchTitle) from the FB-01..."
            )
            fetchProgressPanel.show()
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try FB01VoiceDocumentService.fetchVoice(source: source, sourceIndex: sourceIndex, destinationIndex: destinationIndex, systemChannel: systemChannel)
                }.value
                voice = result.voice
                savedVoice = result.voice
                resetPerformanceMacros()
                self.systemChannel = result.systemChannel
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
        voice = payload.voice
        savedVoice = payload.voice
        resetPerformanceMacros()
        systemChannel = payload.systemChannel
        fileURL = nil
        noteVoiceReplacement()
        preparedKeyboardVoiceSignature = nil
        statusMessage = "Imported selected library voice into this document."
        errorMessage = nil
    }

    func storeToDevice(device: DocumentModel) {
        guard !isBusy else { return }
        guard let options = Self.chooseStoreOptions(defaultVoiceName: voice.name) else {
            return
        }

        let voiceToStore = voice
        let destinationIndex = device.selectedDestinationIndex
        let sourceIndex = device.selectedSourceIndex
        let systemChannel = device.systemChannel
        let destinationName = device.selectedDestinationName
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
                let originalBytes = try await Task.detached(priority: .userInitiated) {
                    try FB01MIDI.request(
                        .voiceBank(bankNumber),
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

                var readback = try voiceBankData(from: originalBytes, expectedBankNumber: bankNumber)
                progressPanel.update(message: "The voice is being stored. Please wait.\nTurning FB-01 Protect OFF...")
                let protectOff = try FB01SysExMessage.command(.setMemoryProtect(systemChannel: systemChannel, .off)).bytes
                try await Task.detached(priority: .userInitiated) {
                    try FB01MIDI.sendSysEx([protectOff], destinationIndex: destinationIndex, delayBetweenMessages: 0)
                }.value
                try await Task.sleep(for: .milliseconds(300))
                try Task.checkCancellation()

                var pass = 0
                while readback.voices[options.voiceNumber].voice.bytes != voiceToStore.bytes {
                    try Task.checkCancellation()
                    pass += 1
                    guard pass <= 60 else {
                        throw FB01AppError.message("Bank \(bankNumber) Voice \(options.voiceNumber + 1) did not verify after 60 write passes.")
                    }

                    statusMessage = "Writing Bank \(bankNumber) Voice \(options.voiceNumber + 1), pass \(pass); verifying after send..."
                    progressPanel.update(message: "The voice is being stored. Please wait.\nWriting Bank \(bankNumber) Voice \(options.voiceNumber + 1), pass \(pass); verifying by readback...")
                    let editedBank = try readback.replacingVoices([options.voiceNumber + 1: voiceToStore])
                    let loadMessage = try voiceBankLoadMessage(bank: editedBank, systemChannel: systemChannel)
                    let nextReadbackBytes = try await Task.detached(priority: .userInitiated) {
                        try FB01MIDI.sendLongSysEx(loadMessage, destinationIndex: destinationIndex, timeout: 45)
                        try await Task.sleep(for: .milliseconds(1500))
                        return try FB01MIDI.request(
                            .voiceBank(bankNumber),
                            sourceIndex: sourceIndex,
                            destinationIndex: destinationIndex,
                            systemChannel: systemChannel,
                            timeout: 15
                        )
                    }.value
                    try Task.checkCancellation()
                    readback = try voiceBankData(from: nextReadbackBytes, expectedBankNumber: bankNumber)
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

    func sendKeyboardNote(_ note: Int, isOn: Bool, device: DocumentModel) {
        let boundedNote = min(max(note, 0), 127)
        let destinationIndex = device.selectedDestinationIndex
        let destinationName = device.selectedDestinationName
        let channel = UInt8(min(max(device.keyboardChannel, 0), 15))
        let velocity = UInt8(min(max(device.keyboardVelocity, 1), 127))

        do {
            if isOn {
                keyboardPreparationTask?.cancel()
                keyboardPreparationTask = nil
            }
            let preparationMessages = isOn ? try keyboardPreparationMessages(midiChannel: Int(channel), device: device) : []
            let noteMessage = [
                (isOn ? 0x90 : 0x80) | channel,
                UInt8(boundedNote),
                isOn ? velocity : 0,
            ]
            Task(priority: .high) { [weak self, weak device] in
                do {
                    try await LiveMIDIPlaybackController.shared.sendPreparedNote(
                        preparationMessages: preparationMessages,
                        noteMessage: noteMessage,
                        destinationIndex: destinationIndex,
                        settleDelay: keyboardPreparationSettleDelay
                    )
                    if isOn {
                        device?.externalKeyboardStatus = "Sent note \(boundedNote) on channel \(Int(channel) + 1) to \(destinationName)."
                        self?.errorMessage = nil
                    }
                } catch {
                    self?.errorMessage = "Keyboard note failed: \(error)"
                    self?.statusMessage = nil
                }
            }
        } catch {
            errorMessage = "Keyboard note failed: \(error)"
            statusMessage = nil
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

    func value(for macro: PerformanceMacro) -> Int {
        performanceMacroValues[macro] ?? PerformanceMacro.neutralValue
    }

    func setPerformanceMacro(_ macro: PerformanceMacro, value proposedValue: Int) {
        let newValue = min(max(proposedValue, PerformanceMacro.range.lowerBound), PerformanceMacro.range.upperBound)
        let oldValue = value(for: macro)
        guard newValue != oldValue else { return }

        do {
            voice = try macro.apply(
                previousValue: oldValue,
                newValue: newValue,
                characterType: voiceCharacterType,
                to: voice
            )
            performanceMacroValues[macro] = newValue
            preparedKeyboardVoiceSignature = nil
            preparedKeyboardVoiceDate = nil
            errorMessage = nil
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
            let savedPayload = try voiceNameFromFile.map { try voice.settingName($0) } ?? voice
            try EditorModuleDocumentFiles.writeVoice(savedPayload, systemChannel: systemChannel, to: url)
            if savedPayload != voice {
                voice = savedPayload
                noteVoiceReplacement()
                preparedKeyboardVoiceSignature = nil
                preparedKeyboardVoiceDate = nil
            }
            savedVoice = savedPayload
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
        try FB01VoiceDocumentService.auditionPreparationMessages(
            voice: voice,
            systemChannel: systemChannel,
            midiChannel: midiChannel
        ) + [try device.liveKeyboardPortamentoMessageBytes(value: device.externalKeyboardPortamento, systemChannel: systemChannel)]
    }

    private func keyboardPreparationSignature(midiChannel: Int, portamento: Int) -> String {
        "\(systemChannel)-\(midiChannel)-\(voice.bytes)-portamento-\(portamento)"
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
    }

    private var isKeyboardPreparationStale: Bool {
        guard let preparedKeyboardVoiceDate else {
            return true
        }
        return Date().timeIntervalSince(preparedKeyboardVoiceDate) > keyboardPreparationStaleAfter
    }

    private static func readVoice(from url: URL) throws -> (voice: FB01VoiceData, systemChannel: Int) {
        let candidates = try EditorModuleDocumentFiles.voiceCandidates(from: url)
        guard let candidate = chooseVoiceCandidate(candidates, title: "Choose Voice Document") else {
            throw FB01AppError.noVoiceSource
        }
        return (candidate.voice, candidate.systemChannel)
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

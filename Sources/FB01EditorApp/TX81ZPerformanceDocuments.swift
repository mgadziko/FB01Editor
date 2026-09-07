import AppKit
import FB01Editor
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class TX81ZPerformanceDocumentModel: ObservableObject, Identifiable {
    let id = UUID()
    @Published var performance: TX81ZPerformanceData
    private var savedPerformance: TX81ZPerformanceData
    let slotNumber: Int?
    @Published var systemChannel: Int
    @Published var fileURL: URL?
    @Published var statusMessage: String

    init(
        performance: TX81ZPerformanceData,
        slotNumber: Int?,
        systemChannel: Int,
        statusMessage: String,
        fileURL: URL? = nil
    ) {
        self.performance = performance
        self.savedPerformance = performance
        self.slotNumber = slotNumber
        self.systemChannel = systemChannel
        self.statusMessage = statusMessage
        self.fileURL = fileURL
    }

    var title: String {
        performance.name.isEmpty ? "Untitled Performance" : performance.name
    }

    var isEdited: Bool { performance != savedPerformance }

    func setName(_ name: String) {
        do { performance = try performance.settingName(name) } catch { }
    }

    func setInstrument(_ number: Int, parameter: Int, value: Int) {
        do { performance = try performance.settingInstrument(number, parameter: parameter, value: value) } catch { }
    }

    func markStored() {
        savedPerformance = performance
    }

    func reset() {
        performance = savedPerformance
        statusMessage = "Reverted to last saved version."
    }

    func save() {
        if let fileURL {
            save(to: fileURL)
        } else {
            saveAs()
        }
    }

    func saveAs() {
        guard performance.isEditBuffer else {
            showEditorError(
                title: "Save Performance Failed",
                message: "Initial TX81Z Performances are compact read-only records. Fetch a writable Performance into the edit buffer before saving it."
            )
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.tx81zPerformance, .tx81zGenericSysEx]
        panel.directoryURL = preferredEditorSaveDirectoryURL()
        panel.nameFieldStringValue = "\(safeEditorFileName(performance.name, fallback: "performance")).txp"
        panel.message = "Save this TX81Z Performance document to a Performance file."
        panel.prompt = "Save Performance to File"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        save(to: url)
    }

    func importFromDisk() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.tx81zPerformance, .tx81zGenericSysEx, .sysex, .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = preferredEditorLoadDirectoryURL()
        panel.message = "Import a TX81Z Performance file into this document, replacing its current contents."
        panel.prompt = "Import Performance from File"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let loaded = try Self.readPerformance(from: url)
            performance = loaded.performance
            savedPerformance = loaded.performance
            systemChannel = loaded.systemChannel
            fileURL = url
            rememberEditorLoadDirectory(for: url)
            statusMessage = "Imported \(url.lastPathComponent)."
        } catch {
            showEditorError(title: "Import Performance Failed", message: "\(error)")
        }
    }

    static func loadFromDisk() -> TX81ZPerformanceDocumentModel? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.tx81zPerformance, .tx81zGenericSysEx, .sysex, .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = preferredEditorLoadDirectoryURL()
        panel.message = "Load a TX81Z Performance file into a new Performance document window."
        panel.prompt = "Load Performance from File"

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return loadFromDisk(url: url)
    }

    static func loadFromDisk(url: URL) -> TX81ZPerformanceDocumentModel? {
        do {
            let loaded = try readPerformance(from: url)
            rememberEditorLoadDirectory(for: url)
            return TX81ZPerformanceDocumentModel(
                performance: loaded.performance,
                slotNumber: nil,
                systemChannel: loaded.systemChannel,
                statusMessage: "Loaded \(url.lastPathComponent).",
                fileURL: url
            )
        } catch {
            showEditorError(title: "Load Performance Failed", message: "\(error)")
            return nil
        }
    }

    private func save(to url: URL) {
        do {
            let message = try performance.performanceEditBulkSysEx(channel: systemChannel)
            try Data(message).write(to: url, options: .atomic)
            savedPerformance = performance
            fileURL = url
            rememberEditorSaveDirectory(for: url)
            statusMessage = "Saved \(url.lastPathComponent)."
        } catch {
            showEditorError(title: "Save Performance Failed", message: "\(error)")
        }
    }

    private static func readPerformance(from url: URL) throws -> (performance: TX81ZPerformanceData, systemChannel: Int) {
        let bytes = Array(try Data(contentsOf: url))
        let messages = TX81Z.splitSysExMessages(from: bytes)
        guard !messages.isEmpty else { throw TX81ZSysExError.invalidPerformanceBulkHeader }

        var lastError: Error = TX81ZSysExError.invalidPerformanceBulkHeader
        for message in messages {
            do {
                let performance = try TX81ZModuleServices.shared.voiceService.currentPerformance(from: message)
                return (performance, Int(message[2] & 0x0F))
            } catch {
                lastError = error
            }
        }
        throw lastError
    }
}

private struct TX81ZPerformanceSelectorItem: Identifiable {
    let number: Int
    let performance: TX81ZPerformanceData
    var id: Int { number }
}

struct TX81ZPerformanceDocumentWindow: View {
    @ObservedObject var document: TX81ZPerformanceDocumentModel
    @ObservedObject var device: DocumentModel
    var closeDocument: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(document.performance.isEditBuffer ? (document.isEdited ? "Edited" : "Edit Buffer") : "Stored Slot")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(document.isEdited ? .orange : .blue)
                    Spacer()
                    Text(document.performance.isEditBuffer ? "Current Edit Buffer" : "Performance Bank")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                DocumentMIDIContextView(device: device, editingDevice: .tx81z, documentSystemChannel: document.systemChannel)

                if document.performance.isEditBuffer {
                    GroupBox("Performance") {
                        TextField("Name", text: Binding(
                            get: { document.performance.name },
                            set: { document.setName($0) }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                }

                SummaryPanel(rows: [
                    KeyValueRow("Performance", document.title),
                    KeyValueRow("Slot", document.slotNumber.map { "\($0)" } ?? "Current Edit Buffer"),
                    KeyValueRow("Data", document.performance.isEditBuffer ? "PCED (110 parameter bytes)" : "PMEM (76 bytes)"),
                ])

                GroupBox("Instruments") {
                    VStack(spacing: 0) {
                        ForEach(Array(document.performance.instruments.enumerated()), id: \.offset) { index, instrument in
                            HStack {
                                Text("Instrument \(index + 1)")
                                    .frame(width: 96, alignment: .leading)
                                if let maximumNotes = instrument.maximumNotes {
                                    Text(maximumNotes == 0 ? "Inactive" : (instrument.voiceLocation ?? "Unknown"))
                                        .frame(width: 76, alignment: .leading)
                                    Text(instrument.receiveChannel.map { "Ch \($0)" } ?? "Omni")
                                        .frame(width: 72, alignment: .leading)
                                    Stepper("Notes \(maximumNotes)", value: Binding(
                                        get: { maximumNotes },
                                        set: { document.setInstrument(index + 1, parameter: 0, value: $0) }
                                    ), in: 0...8)
                                    .frame(width: 112, alignment: .leading)
                                } else {
                                    Text("Compact PMEM data")
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let volume = instrument.volume {
                                    Text("Vol \(volume)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.callout)
                            .padding(.vertical, 7)
                            if index < 7 { Divider() }
                        }
                    }
                    .padding(.horizontal, 8)
                }

                Text(document.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("TX81Z Performance - \(document.title)")
        .environment(\.forestHoverTextEnabled, device.hoverTextEnabled)
        .background(WindowActivationObserver(
            onBecomeKey: { device.selectDevice(.tx81z) },
            onResignKey: {}
        ))
        .onAppear { device.selectDevice(.tx81z) }
        .background(WindowIdentifierSetter(identifier: EditorDocumentWorkspace.tx81zPerformanceWindowIdentifier(for: document.id)))
        .background(DocumentWindowCloseGuard(
            windowIdentifier: EditorDocumentWorkspace.tx81zPerformanceWindowIdentifier(for: document.id),
            isEdited: { document.isEdited },
            title: { document.title },
            save: { document.save() },
            onClose: closeDocument
        ))
        .onDisappear(perform: closeDocument)
        .focusedSceneValue(\.activeTX81ZPerformanceActions, ActiveTX81ZPerformanceActions(
            save: { document.save() },
            saveTitle: "Save Current Performance Document to Performance File",
            reset: { document.reset() },
            importFromDisk: { document.importFromDisk() },
            importFromDiskTitle: "Import Performance from File into Current Document...",
            sendToEditBuffer: { sendToEditBuffer() },
            storeToDevice: { storePerformance() },
            isAvailable: document.performance.isEditBuffer,
            isEdited: document.isEdited,
            isBusy: device.isBusy
        ))
    }

    private func sendToEditBuffer() {
        let performance = document.performance
        let destinationIndex = device.selectedDestinationIndex(for: .tx81z)
        let channel = document.systemChannel
        device.statusMessage = "Sending TX81Z Performance edit buffer..."
        Task {
            do {
                let messages = try TX81ZModuleServices.shared.voiceService.performanceEditBufferMessages(for: performance, channel: channel)
                try await Task.detached(priority: .userInitiated) {
                    try FB01MIDI.sendSysEx(messages, destinationIndex: destinationIndex, delayBetweenMessages: 0.08)
                }.value
                device.statusMessage = "Sent TX81Z Performance edit buffer."
            } catch {
                device.errorMessage = "Send TX81Z Performance edit buffer failed: \(error)"
            }
        }
    }

    private func storePerformance() {
        guard let slot = chooseStoreSlot() else { return }
        let performance = document.performance
        let destinationIndex = device.selectedDestinationIndex(for: .tx81z)
        let sourceIndex = device.selectedSourceIndex(for: .tx81z)
        let channel = document.systemChannel
        device.statusMessage = "Storing TX81Z Performance \(slot)..."
        Task {
            do {
                let verified = try await Task.detached(priority: .userInitiated) {
                    try TX81ZModuleServices.shared.voiceService.storePerformance(
                        performance,
                        at: slot - 1,
                        sourceIndex: sourceIndex,
                        destinationIndex: destinationIndex,
                        channel: channel
                    )
                    return try TX81ZModuleServices.shared.voiceService.fetchStoredPerformance(
                        at: slot - 1,
                        sourceIndex: sourceIndex,
                        destinationIndex: destinationIndex,
                        channel: channel
                    )
                }.value
                guard verified == performance else {
                    let message = "TX81Z Performance \(slot) did not match this document after the store attempt. The hardware was not confirmed to have changed."
                    device.errorMessage = message
                    showEditorError(title: "TX81Z Performance Store Failed", message: message)
                    return
                }
                let bank = try await Task.detached(priority: .userInitiated) {
                    try TX81ZModuleServices.shared.voiceService.fetchPerformanceMemoryBank(
                        sourceIndex: sourceIndex,
                        destinationIndex: destinationIndex,
                        channel: channel
                    )
                }.value
                let storedName = bank.performances[slot - 1].name
                guard storedName == performance.name else {
                    let message = "TX81Z Performance \(slot) was written, but the Performance Bank readback reported '\(storedName)' instead of '\(performance.name)'. The hardware store was not confirmed."
                    device.errorMessage = message
                    showEditorError(title: "TX81Z Performance Store Failed", message: message)
                    return
                }
                device.cacheTX81ZPerformanceBank(bank)
                device.noteTX81ZMemoryProtectDisabledForStore()
                document.markStored()
                device.statusMessage = "Stored and verified TX81Z Performance \(slot). The Performance Bank has been refreshed."
            } catch {
                let message = "Store TX81Z Performance \(slot) failed: \(error)"
                device.errorMessage = message
                showEditorError(title: "TX81Z Performance Store Failed", message: message)
            }
        }
    }

    @MainActor
    private func chooseStoreSlot() -> Int? {
        let alert = NSAlert()
        alert.messageText = "Store TX81Z Performance"
        alert.informativeText = "This permanently overwrites one TX81Z Performance slot. Forest will turn Memory Protect OFF, select that slot, send this Performance to the edit buffer, then emulate STORE and confirmation."
        alert.addButton(withTitle: "Store and Overwrite")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 360, height: 26), pullsDown: false)
        for number in 1...24 {
            popup.addItem(withTitle: "Performance \(number)")
        }
        if let slot = document.slotNumber, (1...24).contains(slot) {
            popup.selectItem(at: slot - 1)
        }
        alert.accessoryView = labelledEditorPopup(label: "Destination:", popup: popup)

        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return popup.indexOfSelectedItem + 1
    }
}

struct TX81ZPerformanceSelectorWindow: View {
    @ObservedObject var document: DocumentModel
    @ObservedObject var workspace: EditorDocumentWorkspace
    @Environment(\.openWindow) private var openWindow
    @State private var performances: [TX81ZPerformanceData] = []
    @State private var isLoading = false
    @State private var activeFetchSlot: Int?
    @State private var errorMessage: String?

    var body: some View {
        let layout = TX81ZModuleServices.shared.module.configurationBankSelectorLayout
            ?? TX81ZModuleServices.shared.module.voiceBankSelectorLayout
        SelectorWindowLayout(
            title: "TX81Z Performance Bank",
            subtitle: "Select a stored Performance to fetch its editable Performance buffer.",
            isLoading: isLoading,
            errorMessage: errorMessage,
            layout: layout,
            statusBadgeText: "24 Writable / 8 Initial",
            statusBadgeColor: .blue
        ) {
            selectorGrid(items: performances.enumerated().map { TX81ZPerformanceSelectorItem(number: $0.offset + 1, performance: $0.element) }, layout: layout) { item in
                let number = item.number
                let performance = item.performance
                SelectorGridButton(
                    number: number,
                    title: performance.name.isEmpty ? "Performance \(number)" : performance.name,
                    buttonWidth: layout.buttonWidth
                ) {
                    openStoredPerformance(number: number, fallback: performance)
                }
                .disabled(document.isBusy || isLoading || activeFetchSlot != nil)
            }
        }
        .task(id: document.configurationSelectorRevision) {
            await synchronizePerformances()
        }
        .background(WindowIdentifierSetter(identifier: EditorDocumentWorkspace.configurationBankSelectorWindowIdentifier))
        .environment(\.forestHoverTextEnabled, document.hoverTextEnabled)
    }

    @MainActor
    private func synchronizePerformances() async {
        if let cached = document.tx81zCachedPerformanceBank() {
            errorMessage = nil
            performances = cached.performances
            return
        }
        isLoading = true
        errorMessage = nil
        performances = await document.ensureTX81ZPerformanceBank()?.performances ?? []
        if performances.isEmpty { errorMessage = document.errorMessage ?? "TX81Z Performances could not be fetched." }
        isLoading = false
    }

    @MainActor
    private func openStoredPerformance(number: Int, fallback: TX81ZPerformanceData) {
        guard activeFetchSlot == nil else { return }
        if number > 24 {
            let id = workspace.createTX81ZPerformanceDocument(
                performance: fallback, slotNumber: number, systemChannel: document.systemChannel,
                statusMessage: "Initial Performance \(number - 24) is read-only."
            )
            openWindow(id: "tx81z-performance-document", value: id)
            return
        }
        activeFetchSlot = number
        Task {
            defer { activeFetchSlot = nil }
            let sourceIndex = document.selectedSourceIndex(for: .tx81z)
            let destinationIndex = document.selectedDestinationIndex(for: .tx81z)
            let channel = document.systemChannel
            do {
                let selected = try await Task.detached(priority: .userInitiated) {
                    try TX81ZModuleServices.shared.voiceService.fetchStoredPerformance(
                        at: number - 1, sourceIndex: sourceIndex, destinationIndex: destinationIndex, channel: channel
                    )
                }.value
                let id = await MainActor.run {
                    workspace.createTX81ZPerformanceDocument(
                        performance: selected, slotNumber: number, systemChannel: channel,
                        statusMessage: "Selected TX81Z Performance \(number) and fetched its edit buffer."
                    )
                }
                await MainActor.run { openWindow(id: "tx81z-performance-document", value: id) }
            } catch {
                let retryManually = await MainActor.run { () -> Bool in
                    let alert = NSAlert()
                    alert.messageText = "Select TX81Z Performance \(number)"
                    alert.informativeText = "Forest could not select and fetch this Performance automatically. Put the TX81Z in PLAY PERFORMANCE, select Performance \(number) on the front panel, then click Continue."
                    alert.addButton(withTitle: "Continue")
                    alert.addButton(withTitle: "Cancel")
                    return alert.runModal() == .alertFirstButtonReturn
                }
                guard retryManually else { return }

                do {
                    let selected = try await Task.detached(priority: .userInitiated) {
                        try TX81ZModuleServices.shared.voiceService.fetchCurrentPerformance(
                            sourceIndex: sourceIndex, destinationIndex: destinationIndex, channel: channel
                        )
                    }.value
                    let id = await MainActor.run {
                        workspace.createTX81ZPerformanceDocument(
                            performance: selected, slotNumber: number, systemChannel: channel,
                            statusMessage: "Fetched TX81Z Performance \(number) from the selected edit buffer."
                        )
                    }
                    await MainActor.run { openWindow(id: "tx81z-performance-document", value: id) }
                } catch {
                    await MainActor.run {
                        errorMessage = "TX81Z Performance \(number) could not be fetched: \(error)"
                    }
                }
            }
        }
    }
}

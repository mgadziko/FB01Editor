import AppKit
import Combine
import FB01Editor
import SwiftUI
import UniformTypeIdentifiers

enum VoiceEditorParadigm: String, CaseIterable, Identifiable {
    case consoleSections
    case fmRoutingPatchBay

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .consoleSections:
            "Console Sections"
        case .fmRoutingPatchBay:
            "FM Routing Patch Bay"
        }
    }

    var description: String {
        switch self {
        case .consoleSections:
            "The existing grouped editor layout, organized by parameter families."
        case .fmRoutingPatchBay:
            "A routing-first voice editor that emphasizes operators, carriers, modulators, and algorithm signal flow."
        }
    }
}

struct FB01DevicePreference: Equatable, Identifiable {
    var id: Int { index }
    var index: Int
    var commandChannel: Int
    var memoryProtectEnabled: Bool
}

private enum FB01InstrumentParameter {
    static let noteCount = 0x00
    static let midiChannel = 0x01
    static let highKeyLimit = 0x02
    static let lowKeyLimit = 0x03
    static let outputLevel = 0x08
}

func voiceBankLoadMessage(bank: FB01VoiceBankData, systemChannel: Int) throws -> [UInt8] {
    try FB01VoiceService.shared.voiceBankLoadMessage(bank: bank, systemChannel: systemChannel)
}

func voiceBankData(from bytes: [UInt8], expectedBankNumber: Int) throws -> FB01VoiceBankData {
    try FB01VoiceService.shared.voiceBankData(from: bytes, expectedDisplayBank: expectedBankNumber)
}

func keyboardAuditionPreparationMessages(systemChannel: Int, midiChannel: Int) throws -> [[UInt8]] {
    var messages: [[UInt8]] = []

    for instrument in 1..<FB01ConfigurationData.instrumentCount {
        messages.append(try FB01SysExMessage.command(.instrumentParameterChange(
            systemChannel: systemChannel,
            instrument: instrument,
            parameter: FB01InstrumentParameter.noteCount,
            value: .oneByte(0)
        )).bytes)
    }

    messages += [
        try FB01SysExMessage.command(.instrumentParameterChange(
            systemChannel: systemChannel,
            instrument: 0,
            parameter: FB01InstrumentParameter.noteCount,
            value: .oneByte(8)
        )).bytes,
        try FB01SysExMessage.command(.instrumentParameterChange(
            systemChannel: systemChannel,
            instrument: 0,
            parameter: FB01InstrumentParameter.midiChannel,
            value: .oneByte(UInt8(min(max(midiChannel, 0), 15)))
        )).bytes,
        try FB01SysExMessage.command(.instrumentParameterChange(
            systemChannel: systemChannel,
            instrument: 0,
            parameter: FB01InstrumentParameter.highKeyLimit,
            value: .oneByte(127)
        )).bytes,
        try FB01SysExMessage.command(.instrumentParameterChange(
            systemChannel: systemChannel,
            instrument: 0,
            parameter: FB01InstrumentParameter.lowKeyLimit,
            value: .oneByte(0)
        )).bytes,
        try FB01SysExMessage.command(.instrumentParameterChange(
            systemChannel: systemChannel,
            instrument: 0,
            parameter: FB01InstrumentParameter.outputLevel,
            value: .oneByte(127)
        )).bytes,
    ]

    return messages
}

func backupFileName(prefix: String, timestamp: Date = Date()) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyMMdd-HHmmss"
    return "\(prefix)-backup-\(formatter.string(from: timestamp)).syx"
}

@main
struct FB01EditorApplication: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var document = DocumentModel()
    @StateObject private var documentWorkspace = EditorDocumentWorkspace()

    var body: some Scene {
        WindowGroup("Forest FB-01 Editor") {
            ContentView(document: document, workspace: documentWorkspace)
                .frame(minWidth: 1080, minHeight: 760)
                .onAppear {
                    appDelegate.document = document
                    appDelegate.documentWorkspace = documentWorkspace
                    LiveKeyboardPaletteController.shared.restoreIfNeeded(document: document)
                    document.startLaunchDeviceCacheRefreshIfNeeded()
                }
        }
        .defaultSize(width: 1080, height: 920)
        WindowGroup("Voice Document", id: "voice-document", for: UUID.self) { $id in
            if let id, let voiceDocument = documentWorkspace.voiceDocument(id: id) {
                VoiceDocumentWindow(document: voiceDocument, device: document) {
                    documentWorkspace.closeVoiceDocument(id: id)
                }
                    .frame(minWidth: 760, minHeight: 620)
            } else {
                MissingEditorDocumentView()
                    .frame(width: 420, height: 180)
            }
        }
        WindowGroup("Configuration Document", id: "configuration-document", for: UUID.self) { $id in
            if let id, let configurationDocument = documentWorkspace.configurationDocument(id: id) {
                ConfigurationDocumentWindow(document: configurationDocument, device: document) {
                    documentWorkspace.closeConfigurationDocument(id: id)
                }
                    .frame(minWidth: 820, minHeight: 620)
            } else {
                MissingEditorDocumentView()
                    .frame(width: 420, height: 180)
            }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Forest FB-01 Editor") {
                    AboutBoxController.shared.show()
                }

                Button("Preferences...") {
                    PreferencesWindowController.shared.show(document: document)
                }
                .keyboardShortcut(",", modifiers: .command)

                Button("Reset Instructions...") {
                    document.resetDeviceToFactorySettings()
                }
                .disabled(document.isBusy)
            }

            CommandGroup(replacing: .newItem) {
                EditorDocumentCommands(document: document, workspace: documentWorkspace)
            }
            CommandGroup(after: .newItem) {
                Button("Load SysEx into Library...") {
                    document.openSysEx()
                }
                .keyboardShortcut("o", modifiers: .command)

                Button("Save Library SysEx...") {
                    document.saveConfigurationSet()
                }
                .disabled(!document.canSaveConfigurationSet)

                Divider()

                Button("New Library Configuration from Selected...") {
                    document.createConfigurationDocumentFromSelected()
                }
                .disabled(!document.canCreateLibraryConfigurationFromSelected)

                Button("Duplicate Selected Library Configuration...") {
                    document.duplicateSelectedConfigurationDocument()
                }
                .disabled(!document.canDuplicateSelectedLibraryConfiguration)

                Button("Save Selected Library Configuration As...") {
                    document.saveSelectedConfigurationAs()
                }
                .disabled(!document.canSaveSelectedLibraryConfigurationAs)
            }

            CommandGroup(after: .windowArrangement) {
                Button("Live Keyboard") {
                    LiveKeyboardPaletteController.shared.show(document: document)
                }
                .keyboardShortcut("k", modifiers: [.command, .option])
            }

            CommandMenu("Voice") {
                Button("Copy Voice to Slot...") {
                    document.copySelectedVoiceToLocalSlot()
                }
                .disabled(document.isBusy)

                if document.voiceEditorParadigm == .consoleSections {
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

                    Divider()
                }

                Button("Store General MIDI voices...") {
                    document.storeGeneralMIDIVoicesToDevice()
                }
                .disabled(document.isBusy)
            }

            CommandMenu("Configuration") {
                Button("Copy Configuration to Slot ...") {
                    document.copyConfigurationSlotOnDevice()
                }
                .disabled(document.isBusy)

                Button("Refresh Device Cache") {
                    document.refreshDeviceCache(reason: "Refreshing device cache")
                }
                .disabled(document.isBusy)

                if document.voiceEditorParadigm == .consoleSections {
                    Divider()

                    Button("Send Selected Configuration to Current Edit Buffer...") {
                        document.sendSelectedConfigurationToCurrentEditBuffer()
                    }
                    .disabled(!document.canSendSelectedConfiguration)

                    Button("Send and Confirm Selected Configuration...") {
                        document.sendAndConfirmSelectedConfigurationToCurrentEditBuffer()
                    }
                    .disabled(!document.canSendSelectedConfiguration)

                    Button("Store Selected Configuration to Slot...") {
                        document.storeSelectedConfigurationToDeviceSlot()
                    }
                    .disabled(!document.canStoreSelectedConfiguration)

                    Button("Store and Confirm Selected Configuration...") {
                        document.storeAndConfirmSelectedConfigurationToDeviceSlot()
                    }
                    .disabled(!document.canStoreSelectedConfiguration)
                }
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var document: DocumentModel?
    weak var documentWorkspace: EditorDocumentWorkspace?

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        let libraryReply = document?.confirmApplicationTermination() ?? .terminateNow
        guard libraryReply == .terminateNow else {
            return libraryReply
        }
        return documentWorkspace?.confirmApplicationTermination() ?? .terminateNow
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

                Text("Forest FB-01 Editor")
                    .font(.headline.weight(.semibold))
                    .padding(.bottom, 4)

                Text(versionText)
                    .font(.body)
                    .padding(.bottom, 14)

                Text("Yamaha FB-01 programming is pretty complicated. Forest FB-01 Editor helps you see the forest through all the trees.")
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
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
        .frame(width: 552, height: 320)
    }
}

@MainActor
final class PreferencesWindowController {
    static let shared = PreferencesWindowController()
    private var window: NSWindow?
    private var delegate: PreferencesWindowDelegate?

    func show(document: DocumentModel) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingView = NSHostingView(rootView: PreferencesView(document: document) { [weak self] in
            self?.window?.close()
        })
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 640),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Preferences"
        panel.contentView = hostingView
        panel.isReleasedWhenClosed = false
        panel.center()
        let delegate = PreferencesWindowDelegate { [weak self] in
            self?.window = nil
            self?.delegate = nil
        }
        self.delegate = delegate
        panel.delegate = delegate
        window = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private final class PreferencesWindowDelegate: NSObject, NSWindowDelegate {
    private let closeHandler: () -> Void

    init(closeHandler: @escaping () -> Void) {
        self.closeHandler = closeHandler
    }

    func windowWillClose(_: Notification) {
        closeHandler()
    }
}

@MainActor
final class LiveKeyboardPaletteController {
    static let shared = LiveKeyboardPaletteController()

    private var panel: NSPanel?
    private var delegate: LiveKeyboardPaletteDelegate?
    private var restoredForLaunch = false

    private enum DefaultsKey {
        static let visible = "FB01Editor.liveKeyboardPalette.visible"
        static let frame = "FB01Editor.liveKeyboardPalette.frame"
    }

    func restoreIfNeeded(document: DocumentModel) {
        guard !restoredForLaunch else {
            return
        }
        restoredForLaunch = true
        if UserDefaults.standard.bool(forKey: DefaultsKey.visible) {
            show(document: document)
        }
    }

    func show(document: DocumentModel) {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            UserDefaults.standard.set(true, forKey: DefaultsKey.visible)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 848, height: 224),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Live Keyboard"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        panel.contentMinSize = NSSize(width: 760, height: 198)
        panel.contentView = NSHostingView(rootView: LiveKeyboardPaletteView(document: document))
        if let savedFrame = UserDefaults.standard.string(forKey: DefaultsKey.frame) {
            let frame = NSRectFromString(savedFrame)
            if !frame.isEmpty {
                panel.setFrame(frame, display: false)
            } else {
                panel.center()
            }
        } else {
            panel.center()
        }
        let delegate = LiveKeyboardPaletteDelegate(
            onFrameChange: { [weak self] window in
                self?.saveFrame(window)
            },
            onClose: { [weak self] window in
                self?.saveFrame(window)
                UserDefaults.standard.set(false, forKey: DefaultsKey.visible)
            }
        )
        self.delegate = delegate
        panel.delegate = delegate
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
        UserDefaults.standard.set(true, forKey: DefaultsKey.visible)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func saveFrame(_ window: NSWindow?) {
        guard let window else {
            return
        }
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: DefaultsKey.frame)
    }
}

private final class LiveKeyboardPaletteDelegate: NSObject, NSWindowDelegate {
    var onFrameChange: (NSWindow?) -> Void
    var onClose: (NSWindow?) -> Void

    init(onFrameChange: @escaping (NSWindow?) -> Void, onClose: @escaping (NSWindow?) -> Void) {
        self.onFrameChange = onFrameChange
        self.onClose = onClose
    }

    func windowDidMove(_ notification: Notification) {
        onFrameChange(notification.object as? NSWindow)
    }

    func windowDidResize(_ notification: Notification) {
        onFrameChange(notification.object as? NSWindow)
    }

    func windowWillClose(_ notification: Notification) {
        onClose(notification.object as? NSWindow)
    }
}

struct PreferencesView: View {
    @ObservedObject var document: DocumentModel
    var close: () -> Void

    @State private var voiceEditorParadigm: VoiceEditorParadigm
    @State private var preCacheRAMVoiceBanksOnLaunch: Bool
    @State private var preCacheROMVoiceBanksOnLaunch: Bool
    @State private var preCacheConfigurationsOnLaunch: Bool
    @State private var preferredDeviceCount: Int
    @State private var devicePreferences: [FB01DevicePreference]

    init(document: DocumentModel, close: @escaping () -> Void) {
        self.document = document
        self.close = close
        _voiceEditorParadigm = State(initialValue: document.voiceEditorParadigm)
        _preCacheRAMVoiceBanksOnLaunch = State(initialValue: document.preCacheRAMVoiceBanksOnLaunch)
        _preCacheROMVoiceBanksOnLaunch = State(initialValue: document.preCacheROMVoiceBanksOnLaunch)
        _preCacheConfigurationsOnLaunch = State(initialValue: document.preCacheConfigurationsOnLaunch)
        _preferredDeviceCount = State(initialValue: document.preferredDeviceCount)
        _devicePreferences = State(initialValue: document.devicePreferences)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Voice Editor Paradigm", selection: $voiceEditorParadigm) {
                                ForEach(VoiceEditorParadigm.allCases) { paradigm in
                                    Text(paradigm.displayName).tag(paradigm)
                                }
                            }
                            .pickerStyle(.radioGroup)

                            Text(voiceEditorParadigm.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 4)
                    } label: {
                        SectionTitle("Voice Editing")
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Pre-Cache RAM Banks 1-2 on launch", isOn: $preCacheRAMVoiceBanksOnLaunch)
                            Toggle("Pre-Cache ROM Banks 3-7 on launch", isOn: $preCacheROMVoiceBanksOnLaunch)
                            Toggle("Pre-Cache Configurations on launch", isOn: $preCacheConfigurationsOnLaunch)

                            Text("These settings affect the automatic launch cache. Manual cache refreshes still read the full FB-01 library.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 4)
                    } label: {
                        SectionTitle("Caching")
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 14) {
                            Stepper(value: Binding(
                                get: { preferredDeviceCount },
                                set: { setDraftDeviceCount($0) }
                            ), in: 1...4) {
                                Text("Number of FB-01 devices: \(preferredDeviceCount)")
                            }

                            Divider()

                            ForEach(Array(devicePreferences.enumerated()), id: \.element.id) { offset, preference in
                                HStack(alignment: .top, spacing: 14) {
                                    Text("Device \(offset + 1)")
                                        .font(.headline)
                                        .frame(width: 86, alignment: .leading)

                                    Picker("Command Channel", selection: Binding(
                                        get: { preference.commandChannel },
                                        set: { setDraftDeviceCommandChannel(index: offset, channel: $0) }
                                    )) {
                                        ForEach(0..<16, id: \.self) { channel in
                                            Text("\(channel + 1)").tag(channel)
                                        }
                                    }
                                    .frame(width: 190)

                                    RockerSwitch(label: "Memory Writable", isOn: Binding(
                                        get: { !preference.memoryProtectEnabled },
                                        set: { setDraftDeviceMemoryWritable(index: offset, writable: $0) }
                                    ), width: 84, height: 58)
                                }
                            }

                            Text("These multi-device settings are saved for the editor workflow. Current MIDI sends still use the selected FB-01 destination until multi-device routing is implemented.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 4)
                    } label: {
                        SectionTitle("FB-01 Devices")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            }

            HStack {
                Spacer()
                Button("Close without Saving") {
                    close()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save Changes") {
                    saveChanges()
                    close()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 4)
        }
        .padding(22)
        .frame(width: 620, height: 640, alignment: .topLeading)
    }

    private func setDraftDeviceCount(_ count: Int) {
        preferredDeviceCount = min(max(count, 1), 4)
        if devicePreferences.count < preferredDeviceCount {
            for index in devicePreferences.count..<preferredDeviceCount {
                devicePreferences.append(FB01DevicePreference(index: index, commandChannel: 0, memoryProtectEnabled: false))
            }
        } else if devicePreferences.count > preferredDeviceCount {
            devicePreferences.removeLast(devicePreferences.count - preferredDeviceCount)
        }
    }

    private func setDraftDeviceCommandChannel(index: Int, channel: Int) {
        guard devicePreferences.indices.contains(index) else { return }
        devicePreferences[index].commandChannel = min(max(channel, 0), 15)
    }

    private func setDraftDeviceMemoryWritable(index: Int, writable: Bool) {
        guard devicePreferences.indices.contains(index) else { return }
        devicePreferences[index].memoryProtectEnabled = !writable
    }

    private func saveChanges() {
        document.setVoiceEditorParadigm(voiceEditorParadigm)
        document.setPreCacheRAMVoiceBanksOnLaunch(preCacheRAMVoiceBanksOnLaunch)
        document.setPreCacheROMVoiceBanksOnLaunch(preCacheROMVoiceBanksOnLaunch)
        document.setPreCacheConfigurationsOnLaunch(preCacheConfigurationsOnLaunch)
        document.setPreferredDeviceCount(preferredDeviceCount)
        for preference in devicePreferences {
            document.setDeviceCommandChannel(index: preference.index, channel: preference.commandChannel)
            document.setDeviceMemoryProtect(index: preference.index, enabled: preference.memoryProtectEnabled)
        }
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

import AppKit
import FB01Editor
import SwiftUI
import UniformTypeIdentifiers

private let voiceDocumentEditPreparationDelayNanoseconds: UInt64 = 250_000_000

struct ContentView: View {
    @ObservedObject var document: DocumentModel
    @ObservedObject var workspace: EditorDocumentWorkspace

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ToolbarView(document: document)

                Divider()

                StatusWindowView(document: document, workspace: workspace)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                MainWindowStatusFooter(
                    errorMessage: document.errorMessage,
                    statusMessage: document.statusMessage
                )
            }
            .frame(minWidth: 1080, maxWidth: 1080, minHeight: 920, alignment: .topLeading)
        }
        .background(MainWindowSizeConfigurator(contentSize: CGSize(width: 1080, height: 920)))
        .environment(\.forestHoverTextEnabled, document.hoverTextEnabled)
    }
}

struct MainWindowStatusFooter: View {
    var errorMessage: String?
    var statusMessage: String?

    private var message: String {
        errorMessage ?? statusMessage ?? " "
    }

    var body: some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(errorMessage == nil ? Color.secondary : Color.red)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
            .padding(.horizontal, 14)
    }
}

struct ToolbarView: View {
    @ObservedObject var document: DocumentModel

    var body: some View {
        HStack(spacing: 10) {
            Text("MIDI In from \(EditorSynthModule.vocabulary.deviceDisplayName)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

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
            .forestHoverHelp("Selects the MIDI input that receives replies and dumps from the FB-01.")

            Text("MIDI Out to \(EditorSynthModule.vocabulary.deviceDisplayName)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

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
            .forestHoverHelp("Selects the MIDI output used to send notes, edits, fetch requests, and store commands to the FB-01.")

            Button {
                document.refreshMIDIEndpoints()
            } label: {
                Label("Refresh MIDI", systemImage: "arrow.clockwise")
            }
            .disabled(document.isBusy)
            .forestHoverHelp("Rescans MIDI devices after connecting, disconnecting, or resetting an interface.")

            Divider()
                .frame(height: 20)

            Text("Global Status")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Text(document.editingStatusText)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .forestHoverHelp(document.selectedEditedSourceCount == 0 ? "No local edits" : "\(document.selectedEditedSourceCount) source\(document.selectedEditedSourceCount == 1 ? "" : "s") with unsaved local edits")
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

struct VoiceSelectorCommands: View {
    @ObservedObject var document: DocumentModel
    @ObservedObject var workspace: EditorDocumentWorkspace
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.activeVoiceBankSelector) private var activeVoiceBankSelector

    var body: some View {
        Menu(EditorFeatureAvailability.commandTitle(.showVoiceBank, fallback: "Show Voice Bank")) {
            ForEach(EditorSynthModule.module.allVoiceBanks, id: \.self) { bank in
                Button("Bank \(bank)") {
                    let identifier = EditorDocumentWorkspace.voiceBankSelectorWindowIdentifier(for: bank)
                    if !workspace.bringWindowToFront(identifier: identifier) {
                        openWindow(id: "voice-bank-selector", value: bank)
                    }
                }
                .disabled(document.isBusy)
            }
        }
        .disabled(document.isBusy || !EditorFeatureAvailability.supportsCommand(.showVoiceBank))

        Menu(EditorFeatureAvailability.commandTitle(.storeVoiceBank, fallback: "Store Bank")) {
            ForEach(EditorSynthModule.module.writableVoiceBanks, id: \.self) { targetBank in
                Button("Bank \(targetBank)") {
                    if let sourceBank = activeVoiceBankSelector {
                        document.storeVoiceBankFromSelector(sourceBank: sourceBank, targetBank: targetBank)
                    }
                }
                .disabled(document.isBusy || activeVoiceBankSelector == nil)
            }
        }
        .disabled(document.isBusy || activeVoiceBankSelector == nil || !EditorFeatureAvailability.supportsCommand(.storeVoiceBank))
    }
}

struct ConfigurationSelectorCommands: View {
    @ObservedObject var document: DocumentModel
    @ObservedObject var workspace: EditorDocumentWorkspace
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(EditorFeatureAvailability.commandTitle(.showConfigurationBank, fallback: "Show Configuration Bank")) {
            if !workspace.bringWindowToFront(identifier: EditorDocumentWorkspace.configurationBankSelectorWindowIdentifier) {
                openWindow(id: "configuration-bank-selector")
            }
        }
        .disabled(document.isBusy || !EditorFeatureAvailability.supportsCommand(.showConfigurationBank))
    }
}

struct VoiceBankSelectorWindow: View {
    var bank: Int
    @ObservedObject var document: DocumentModel
    @ObservedObject var workspace: EditorDocumentWorkspace
    @Environment(\.openWindow) private var openWindow
    @State private var items: [VoiceBankSelectorItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        let layout = EditorSynthModule.module.voiceBankSelectorLayout
        SelectorWindowLayout(
            title: "Voice Bank \(bank)",
            subtitle: "Select a voice to fetch it into a new Voice Document.",
            isLoading: isLoading,
            errorMessage: errorMessage,
            layout: layout,
            showsTitle: false
        ) {
            selectorGrid(items: items, layout: layout) { item in
                SelectorGridButton(number: item.displayNumber, title: item.title, buttonWidth: layout.buttonWidth) {
                    openVoiceDocument(item)
                }
                .disabled(document.isBusy)
                .forestHoverHelp("Fetches \(item.fetchTitle) into a new Voice Document.")
            }
        }
        .task(id: bank) {
            await loadItems()
        }
        .background(WindowIdentifierSetter(
            identifier: EditorDocumentWorkspace.voiceBankSelectorWindowIdentifier(for: bank),
            title: "Voice Bank \(bank)"
        ))
        .focusedSceneValue(\.activeVoiceBankSelector, bank)
        .environment(\.forestHoverTextEnabled, document.hoverTextEnabled)
    }

    @MainActor
    private func loadItems() async {
        isLoading = true
        errorMessage = nil
        items = await document.ensureVoiceBankSelectorItems(bank: bank)
        if items.isEmpty {
            errorMessage = "Voice Bank \(bank) could not be loaded."
        }
        isLoading = false
    }

    @MainActor
    private func openVoiceDocument(_ item: VoiceBankSelectorItem) {
        let id = workspace.createVoiceDocument(statusMessage: "Fetching \(item.fetchTitle)...")
        openWindow(id: "voice-document", value: id)
        Task { @MainActor in
            await Task.yield()
            workspace.voiceDocument(id: id)?.fetchFromDevice(
                device: document,
                source: item.source,
                recentTitle: item.fetchTitle
            )
        }
    }
}

struct ConfigurationSelectorWindow: View {
    @ObservedObject var document: DocumentModel
    @ObservedObject var workspace: EditorDocumentWorkspace
    @Environment(\.openWindow) private var openWindow
    @State private var items: [ConfigurationSelectorItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        let layout = EditorSynthModule.module.configurationBankSelectorLayout ?? EditorSynthModule.module.voiceBankSelectorLayout
        SelectorWindowLayout(
            title: "Configuration Bank",
            subtitle: "Select a configuration to fetch it into a new Configuration Document.",
            isLoading: isLoading,
            errorMessage: errorMessage,
            layout: layout
        ) {
            selectorGrid(items: items, layout: layout) { item in
                SelectorGridButton(number: item.displayNumber, title: item.title, buttonWidth: layout.buttonWidth) {
                    openConfigurationDocument(item)
                }
                .disabled(document.isBusy)
                .forestHoverHelp("Fetches \(item.fetchTitle) into a new Configuration Document.")
            }
        }
        .task {
            await loadItems()
        }
        .onChange(of: document.configurationSelectorRevision) {
            items = document.configurationSelectorItems()
        }
        .background(WindowIdentifierSetter(identifier: EditorDocumentWorkspace.configurationBankSelectorWindowIdentifier))
        .environment(\.forestHoverTextEnabled, document.hoverTextEnabled)
    }

    @MainActor
    private func loadItems() async {
        isLoading = true
        errorMessage = nil
        items = await document.ensureConfigurationSelectorItems()
        if items.isEmpty {
            errorMessage = "Configurations could not be loaded."
        }
        isLoading = false
    }

    @MainActor
    private func openConfigurationDocument(_ item: ConfigurationSelectorItem) {
        if let cachedConfiguration = document.cachedConfigurationFetchResult(options: item.options) {
            let id = workspace.createConfigurationDocument(
                configuration: cachedConfiguration,
                systemChannel: document.systemChannel,
                statusMessage: "Opened cached \(item.fetchTitle)."
            )
            document.rememberRecentFetchedConfiguration(item.options, title: item.fetchTitle)
            openWindow(id: "configuration-document", value: id)
            Task { @MainActor in
                await Task.yield()
                if let configurationDocument = workspace.configurationDocument(id: id) {
                    let voiceNameStatus = await document.prefetchConfigurationVoiceNames(
                        for: cachedConfiguration,
                        configurationDocument: configurationDocument,
                        reason: "Opened cached \(item.fetchTitle)",
                        fetchMissingBanks: false
                    )
                    if let voiceNameStatus {
                        configurationDocument.statusMessage = "Opened cached \(item.fetchTitle). \(voiceNameStatus)"
                    }
                }
            }
            return
        }

        let id = workspace.createConfigurationDocument(statusMessage: "Fetching \(item.fetchTitle)...")
        openWindow(id: "configuration-document", value: id)
        Task { @MainActor in
            await Task.yield()
            workspace.configurationDocument(id: id)?.fetchFromDevice(
                device: document,
                options: item.options,
                recentTitle: item.fetchTitle
            )
        }
    }
}

private struct SelectorWindowLayout<Content: View>: View {
    var title: String
    var subtitle: String
    var isLoading: Bool
    var errorMessage: String?
    var layout: SynthSelectorGridLayout
    var showsTitle = true
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    if showsTitle {
                        Text(title)
                            .font(.title2.weight(.semibold))
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
            }

            content()
        }
        .padding(18)
        .frame(width: CGFloat(layout.windowWidth), alignment: .topLeading)
        .frame(minHeight: CGFloat(layout.minimumWindowHeight), alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct SelectorGridButton: View {
    var number: Int
    var title: String
    var buttonWidth: Double
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text("\(number)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .trailing)
                Text(title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(width: CGFloat(buttonWidth), alignment: .leading)
            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

private func selectorGrid<Item: Identifiable, ButtonView: View>(
    items: [Item],
    layout: SynthSelectorGridLayout,
    @ViewBuilder button: @escaping (Item) -> ButtonView
) -> some View {
    HStack(alignment: .top, spacing: CGFloat(layout.columnSpacing)) {
        ForEach(0..<layout.columns, id: \.self) { column in
            VStack(alignment: .leading, spacing: 8) {
                ForEach(columnItems(items, column: column, rowsPerColumn: layout.rowsPerColumn)) { item in
                    button(item)
                }
            }
        }
    }
}

private func columnItems<Item>(
    _ items: [Item],
    column: Int,
    rowsPerColumn: Int
) -> [Item] {
    let start = column * rowsPerColumn
    guard start < items.count else {
        return []
    }
    let end = min(start + rowsPerColumn, items.count)
    return Array(items[start..<end])
}

private struct WindowIdentifierSetter: NSViewRepresentable {
    var identifier: String
    var title: String?

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            if let window = view.window {
                window.identifier = NSUserInterfaceItemIdentifier(identifier)
                if let title {
                    window.title = title
                }
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                window.identifier = NSUserInterfaceItemIdentifier(identifier)
                if let title {
                    window.title = title
                }
            }
        }
    }
}

struct LiveKeyboardView: View {
    @ObservedObject var document: DocumentModel

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            LiveKeyboardMIDIControlsView(
                document: document,
                title: document.selectedVoiceDocumentPayload().map { "Live Keyboard - \($0.voice.name)" } ?? "Live Keyboard",
                subtitle: document.hasKeyboardVoiceContext ? "Current voice" : "MIDI notes only"
            )
            .frame(width: 460, alignment: .leading)

            PianoKeyboardRepresentable(
                startNote: document.keyboardStartNote,
                octaveCount: 5,
                highlightedNotes: document.externalKeyboardPressedNotes,
                noteOn: { document.sendKeyboardNote($0, isOn: true) },
                noteOff: { document.sendKeyboardNote($0, isOn: false) }
            )
            .frame(height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .background(WindowActivationObserver(
            onBecomeKey: {
                document.resetLiveKeyboardContext()
            },
            onResignKey: {}
        ))
        .onAppear {
            document.resetLiveKeyboardContext()
        }
    }
}

struct LiveKeyboardPaletteView: View {
    @ObservedObject var document: DocumentModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LiveKeyboardPaletteControlsView(document: document)

            PianoKeyboardRepresentable(
                startNote: document.keyboardStartNote,
                octaveCount: 5,
                highlightedNotes: document.externalKeyboardPressedNotes,
                noteOn: { document.sendLiveKeyboardPaletteNote($0, isOn: true) },
                noteOff: { document.sendLiveKeyboardPaletteNote($0, isOn: false) }
            )
            .frame(height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
        }
        .padding(14)
        .frame(width: 820)
        .environment(\.forestHoverTextEnabled, document.hoverTextEnabled)
    }
}

struct CustomizedControlsPaletteView: View {
    @ObservedObject var document: DocumentModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                SectionTitle("Controller")

                Picker("Controller", selection: Binding(
                    get: { document.customControlsControllerProfile },
                    set: { document.setCustomControlsControllerProfile($0) }
                )) {
                    ForEach(CustomControlsControllerProfile.allCases) { profile in
                        Text(profile.title).tag(profile)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
                .forestHoverHelp("Selects the external controller profile whose knobs you want to monitor.")

                Button("Reset to Defaults") {
                    document.resetCustomControlChangeNumbersToDefaults()
                }
                .forestHoverHelp("Restores the selected controller's default CC mappings.")
            }

            Text("These mappings identify incoming controller knobs. They do not drive Performance Macros yet.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(document.lastCustomControlMessage)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(Color(red: 0.37, green: 1.0, blue: 0.16))
                .lineLimit(1)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(document.customControlsControllerProfile.controlLabels.enumerated()), id: \.offset) { index, label in
                    HStack(spacing: 12) {
                        Text(label)
                            .font(.body.weight(.semibold))
                            .frame(width: 34, alignment: .trailing)

                        CustomControlLiveValueDisplay(value: document.liveValueForCustomControl(at: index))

                        Picker("\(label) CC", selection: Binding(
                            get: {
                                document.customControlChangeNumbers.indices.contains(index)
                                    ? document.customControlChangeNumbers[index]
                                    : 0
                            },
                            set: { document.setCustomControlChangeNumber($0, at: index) }
                        )) {
                            ForEach(MIDIControlChangeLabel.allControllers, id: \.self) { controller in
                                Text(MIDIControlChangeLabel.title(for: controller)).tag(controller)
                            }
                        }
                        .frame(width: 280, alignment: .leading)
                        .forestHoverHelp("Chooses which incoming MIDI Control Change number is tracked for \(label).")
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(width: 470, height: 430, alignment: .topLeading)
        .environment(\.forestHoverTextEnabled, document.hoverTextEnabled)
    }
}

struct CustomControlLiveValueDisplay: View {
    let value: Int?

    private var text: String {
        guard let value else { return "-----" }
        return String(format: "%05d", min(max(value, 0), 16_383))
    }

    var body: some View {
        Text(text)
            .font(.system(size: 15, weight: .bold, design: .monospaced))
            .foregroundStyle(Color(red: 0.37, green: 1.0, blue: 0.16))
            .frame(width: 66, height: 24)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.black.opacity(0.82))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color.green.opacity(0.35), lineWidth: 1)
            )
            .accessibilityLabel("Current controller value")
            .accessibilityValue(text)
    }
}

struct LiveKeyboardPaletteControlsView: View {
    @ObservedObject var document: DocumentModel

    private var paletteStatus: String {
        document.externalKeyboardStatus.hasPrefix("Listening to ") ? " " : document.externalKeyboardStatus
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    SectionTitle("MIDI Notes")

                    HStack(alignment: .top, spacing: 10) {
                        ParameterKnob(label: "Channel", value: Binding(
                            get: { document.keyboardChannel + 1 },
                            set: { document.setKeyboardChannel($0 - 1) }
                        ), range: 1...16, width: 70, knobSize: 42)

                        ParameterKnob(label: "Velocity", value: Binding(
                            get: { document.keyboardVelocity },
                            set: { document.setKeyboardVelocity($0) }
                        ), range: 1...127, width: 74, knobSize: 42)

                        ParameterKnob(label: "Octave", value: Binding(
                            get: { document.keyboardStartNote / 12 },
                            set: { document.setKeyboardStartNote($0 * 12) }
                        ), range: 0...5, width: 70, knobSize: 42)

                        ParameterKnob(label: "Portamento", value: Binding(
                            get: { document.externalKeyboardPortamento },
                            set: { document.setExternalKeyboardPortamento($0) }
                        ), range: 0...127, width: 86, knobSize: 42)

                        ParameterKnob(label: "Volume", value: Binding(
                            get: { document.externalKeyboardVolume },
                            set: { document.setExternalKeyboardVolume($0) }
                        ), range: 0...127, width: 74, knobSize: 42)
                    }
                }

                Divider()
                    .frame(height: 96)

                VStack(alignment: .leading, spacing: 7) {
                    SectionTitle("External Keyboard/MIDI Source")

                    HStack(alignment: .top, spacing: 10) {
                        RockerSwitch(label: "Enable", isOn: Binding(
                            get: { document.externalKeyboardEnabled },
                            set: { document.setExternalKeyboardEnabled($0) }
                        ), width: 62, height: 56)

                        Menu {
                            ForEach(document.midiSources, id: \.index) { source in
                                Button {
                                    document.selectKeyboardSource(source)
                                } label: {
                                    endpointLabel(source, selected: source.index == document.selectedKeyboardSourceIndex)
                                }
                            }
                        } label: {
                            Text(document.selectedKeyboardSourceName)
                                .lineLimit(1)
                        }
                        .frame(width: 180, alignment: .leading)
                        .disabled(document.midiSources.isEmpty || !document.externalKeyboardEnabled)
                        .padding(.top, 18)
                        .forestHoverHelp("Chooses the external MIDI source that can play the current Forest audition voice.")
                    }
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(document.liveKeyboardAuditionStatus)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(paletteStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(minHeight: 14, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func endpointLabel(_ endpoint: FB01MIDIEndpoint, selected: Bool) -> some View {
        let unique = endpoint.uniqueID.map { " id=\($0)" } ?? ""
        return Label("[\(endpoint.index)] \(endpoint.displayName)\(unique)", systemImage: selected ? "checkmark" : "circle")
    }
}

struct LiveKeyboardMIDIControlsView: View {
    @ObservedObject var document: DocumentModel
    var title = "Live Keyboard"
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            SectionTitle(title)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 10) {
                ParameterKnob(label: "Channel", value: Binding(
                    get: { document.keyboardChannel + 1 },
                    set: { document.setKeyboardChannel($0 - 1) }
                ), range: 1...16, width: 70, knobSize: 42)

                ParameterKnob(label: "Velocity", value: Binding(
                    get: { document.keyboardVelocity },
                    set: { document.setKeyboardVelocity($0) }
                ), range: 1...127, width: 74, knobSize: 42)

                ParameterKnob(label: "Octave", value: Binding(
                    get: { document.keyboardStartNote / 12 },
                    set: { document.setKeyboardStartNote($0 * 12) }
                ), range: 0...5, width: 70, knobSize: 42)

                ParameterKnob(label: "Portamento", value: Binding(
                    get: { document.externalKeyboardPortamento },
                    set: { document.setExternalKeyboardPortamento($0) }
                ), range: 0...127, width: 86, knobSize: 42)

                ParameterKnob(label: "Volume", value: Binding(
                    get: { document.externalKeyboardVolume },
                    set: { document.setExternalKeyboardVolume($0) }
                ), range: 0...127, width: 74, knobSize: 42)
            }
            .font(.caption)

            HStack(spacing: 8) {
                RockerSwitch(label: "Enable", isOn: Binding(
                    get: { document.externalKeyboardEnabled },
                    set: { document.setExternalKeyboardEnabled($0) }
                ), width: 72, height: 56)

                Menu {
                    ForEach(document.midiSources, id: \.index) { source in
                        Button {
                            document.selectKeyboardSource(source)
                        } label: {
                            endpointLabel(source, selected: source.index == document.selectedKeyboardSourceIndex)
                        }
                    }
                } label: {
                    Text(document.selectedKeyboardSourceName)
                        .lineLimit(1)
                }
                .frame(minWidth: 180, alignment: .leading)
                .disabled(document.midiSources.isEmpty || !document.externalKeyboardEnabled)
                .forestHoverHelp("Chooses the external MIDI source that can play the current Forest audition voice.")
            }
            .font(.caption)

            Text(document.externalKeyboardStatus)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func endpointLabel(_ endpoint: FB01MIDIEndpoint, selected: Bool) -> some View {
        let unique = endpoint.uniqueID.map { " id=\($0)" } ?? ""
        return Label("[\(endpoint.index)] \(endpoint.displayName)\(unique)", systemImage: selected ? "checkmark" : "circle")
    }
}

struct PianoKeyboardRepresentable: NSViewRepresentable {
    var startNote: Int
    var octaveCount: Int
    var highlightedNotes: Set<Int> = []
    var noteOn: (Int) -> Void
    var noteOff: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(noteOn: noteOn, noteOff: noteOff)
    }

    func makeNSView(context: Context) -> PianoKeyboardNSView {
        let view = PianoKeyboardNSView()
        view.startNote = startNote
        view.octaveCount = octaveCount
        view.highlightedNotes = highlightedNotes
        view.noteOn = context.coordinator.noteOn
        view.noteOff = context.coordinator.noteOff
        return view
    }

    func updateNSView(_ nsView: PianoKeyboardNSView, context: Context) {
        context.coordinator.noteOn = noteOn
        context.coordinator.noteOff = noteOff
        nsView.startNote = startNote
        nsView.octaveCount = octaveCount
        nsView.highlightedNotes = highlightedNotes
        nsView.noteOn = context.coordinator.noteOn
        nsView.noteOff = context.coordinator.noteOff
    }

    final class Coordinator {
        var noteOn: (Int) -> Void
        var noteOff: (Int) -> Void

        init(noteOn: @escaping (Int) -> Void, noteOff: @escaping (Int) -> Void) {
            self.noteOn = noteOn
            self.noteOff = noteOff
        }
    }
}

final class PianoKeyboardNSView: NSView {
    var noteOn: (Int) -> Void = { _ in }
    var noteOff: (Int) -> Void = { _ in }
    var highlightedNotes: Set<Int> = [] {
        didSet {
            needsDisplay = true
        }
    }
    var startNote = 36 {
        didSet {
            let clampedStartNote = min(max(startNote, 0), 127)
            guard clampedStartNote != oldValue else {
                startNote = clampedStartNote
                return
            }
            startNote = clampedStartNote
            stopActiveNote()
            needsDisplay = true
        }
    }
    var octaveCount = 5 {
        didSet {
            let clampedOctaveCount = min(max(octaveCount, 1), 8)
            guard clampedOctaveCount != oldValue else {
                octaveCount = clampedOctaveCount
                return
            }
            octaveCount = clampedOctaveCount
            stopActiveNote()
            needsDisplay = true
        }
    }
    private var activeNote: Int?
    private var tracking: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        if let tracking {
            removeTrackingArea(tracking)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        tracking = area
        super.updateTrackingAreas()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.controlBackgroundColor.setFill()
        bounds.fill()

        for key in whiteKeys {
            let rect = whiteKeyRect(index: key.whiteIndex)
            (isHighlighted(key.note) ? NSColor.systemGreen : NSColor.white).setFill()
            rect.fill()
            NSColor.separatorColor.setStroke()
            NSBezierPath(rect: rect).stroke()
        }

        for key in blackKeys {
            let rect = blackKeyRect(afterWhiteIndex: key.afterWhiteIndex)
            (isHighlighted(key.note) ? NSColor.systemGreen : NSColor.black).setFill()
            NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        updateActiveNote(from: event)
    }

    override func mouseDragged(with event: NSEvent) {
        updateActiveNote(from: event)
    }

    override func mouseUp(with event: NSEvent) {
        stopActiveNote()
    }

    override func mouseExited(with event: NSEvent) {
        stopActiveNote()
    }

    private var whiteKeyCount: Int {
        octaveCount * 7 + 1
    }

    private func isHighlighted(_ note: Int) -> Bool {
        activeNote == note || highlightedNotes.contains(note)
    }

    private var whiteKeyWidth: CGFloat {
        max(bounds.width / CGFloat(whiteKeyCount), 1)
    }

    private var whiteKeys: [(note: Int, whiteIndex: Int)] {
        var keys: [(Int, Int)] = []
        var whiteIndex = 0
        for note in startNote...(startNote + octaveCount * 12) where !isBlack(note) {
            keys.append((note, whiteIndex))
            whiteIndex += 1
        }
        return keys
    }

    private var blackKeys: [(note: Int, afterWhiteIndex: Int)] {
        var keys: [(Int, Int)] = []
        var whiteIndex = 0
        for note in startNote...(startNote + octaveCount * 12) {
            if isBlack(note) {
                keys.append((note, whiteIndex - 1))
            } else {
                whiteIndex += 1
            }
        }
        return keys
    }

    private func whiteKeyRect(index: Int) -> CGRect {
        CGRect(x: CGFloat(index) * whiteKeyWidth, y: 0, width: whiteKeyWidth, height: bounds.height)
    }

    private func blackKeyRect(afterWhiteIndex index: Int) -> CGRect {
        let width = whiteKeyWidth * 0.58
        return CGRect(
            x: CGFloat(index + 1) * whiteKeyWidth - width / 2,
            y: bounds.height * 0.38,
            width: width,
            height: bounds.height * 0.62
        )
    }

    private func updateActiveNote(from event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point), let note = note(at: point), note != activeNote else {
            return
        }

        stopActiveNote()
        activeNote = note
        needsDisplay = true
        displayIfNeeded()
        noteOn(note)
    }

    private func stopActiveNote() {
        guard let activeNote else {
            return
        }

        self.activeNote = nil
        needsDisplay = true
        displayIfNeeded()
        noteOff(activeNote)
    }

    private func note(at point: CGPoint) -> Int? {
        for key in blackKeys.reversed() where blackKeyRect(afterWhiteIndex: key.afterWhiteIndex).contains(point) {
            return key.note
        }

        let whiteIndex = min(max(Int(point.x / whiteKeyWidth), 0), whiteKeyCount - 1)
        return whiteKeys.first { $0.whiteIndex == whiteIndex }?.note
    }

    private func isBlack(_ note: Int) -> Bool {
        [1, 3, 6, 8, 10].contains(note % 12)
    }
}

struct StatusWindowView: View {
    @ObservedObject var document: DocumentModel
    @ObservedObject var workspace: EditorDocumentWorkspace
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    document.selectSystemPanel()
                } label: {
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.body.weight(.semibold))
                            .frame(width: 15, height: 16)
                            .padding(.top, 2)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Global Status")
                                .font(.body.weight(.medium))
                                .lineLimit(1)
                            Text("MIDI and document overview")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        document.sidebarSelection == .system
                            ? Color.accentColor.opacity(0.18)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                }
                .buttonStyle(.plain)

                HStack(spacing: 6) {
                    Text("Open Documents")
                        .font(.headline)
                    Spacer()
                    Text("\(workspace.voiceDocuments.count + workspace.configurationDocuments.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.top, 6)

                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(openVoiceDocuments, id: \.id) { item in
                            documentButton(
                                title: item.title,
                                subtitle: "Voice document",
                                systemImage: "waveform",
                                isEdited: item.isEdited
                            ) {
                                openWindow(id: "voice-document", value: item.id)
                            }
                        }

                        ForEach(openConfigurationDocuments, id: \.id) { item in
                            documentButton(
                                title: item.title,
                                subtitle: "Configuration document",
                                systemImage: "doc.text",
                                isEdited: item.isEdited
                            ) {
                                openWindow(id: "configuration-document", value: item.id)
                            }
                        }

                        if workspace.voiceDocuments.isEmpty && workspace.configurationDocuments.isEmpty {
                            Text("No voice or configuration documents are open.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxHeight: 240)

                HStack(spacing: 6) {
                    Text("Library Items")
                        .font(.headline)

                    Spacer()

                    Button {
                        document.renameSelectedSource()
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .forestHoverHelp("Rename selected library item")
                    .disabled(!document.canManageSource)

                    Button {
                        document.removeSelectedSource()
                    } label: {
                        Image(systemName: "minus")
                    }
                    .forestHoverHelp("Remove selected library item")
                    .disabled(!document.canManageSource)

                    Button {
                        document.clearSources()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .forestHoverHelp("Clear library workspace")
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
                            .forestHoverHelp("Selects \(source.title) in the library workspace.")
                        }
                    }
                }
            }
            .padding(12)
            .frame(minWidth: 220, idealWidth: 220, maxWidth: 220, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            GlobalStatusView(document: document, workspace: workspace)
        }
    }

    private var openVoiceDocuments: [VoiceDocumentModel] {
        workspace.voiceDocuments.values.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    private var openConfigurationDocuments: [ConfigurationDocumentModel] {
        workspace.configurationDocuments.values.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    private func documentButton(
        title: String,
        subtitle: String,
        systemImage: String,
        isEdited: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 14, height: 16)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(title.replacingOccurrences(of: " *", with: ""))
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        if isEdited {
                            Text("Edited")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.orange)
                        }
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .forestHoverHelp("Opens or brings forward this \(subtitle.lowercased()).")
    }
}

struct GlobalStatusView: View {
    @ObservedObject var document: DocumentModel
    @ObservedObject var workspace: EditorDocumentWorkspace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Status Window")
                    .font(.title2.weight(.semibold))

                HStack(alignment: .top, spacing: 14) {
                    statusCard(title: "\(EditorSynthModule.vocabulary.deviceDisplayName) Connection", rows: [
                        KeyValueRow("MIDI In", document.selectedSourceName),
                        KeyValueRow("MIDI Out", document.selectedDestinationName),
                        KeyValueRow("System Channel", "\(document.systemChannel + 1)"),
                        KeyValueRow("MIDI Sources", "\(document.midiSources.count)"),
                        KeyValueRow("MIDI Destinations", "\(document.midiDestinations.count)"),
                    ])

                    statusCard(title: "External Keyboard/MIDI Source", rows: [
                        KeyValueRow("Enabled", document.externalKeyboardEnabled ? "On" : "Off"),
                        KeyValueRow("MIDI In", document.selectedKeyboardSourceName),
                        KeyValueRow("Status", document.externalKeyboardStatus),
                        KeyValueRow("Channel", "\(document.keyboardChannel + 1)"),
                        KeyValueRow("Velocity", "\(document.keyboardVelocity)"),
                    ])
                }

                HStack(alignment: .top, spacing: 14) {
                    statusCard(title: "Open Documents", rows: [
                        KeyValueRow("Voice Documents", "\(workspace.voiceDocuments.count)"),
                        KeyValueRow("Configuration Documents", "\(workspace.configurationDocuments.count)"),
                        KeyValueRow("Edited Documents", "\(editedDocumentCount)"),
                    ])

                    statusCard(title: "Library Workspace", rows: [
                        KeyValueRow("Library Items", "\(document.sources.count)"),
                        KeyValueRow("Edited Library Items", "\(document.selectedEditedSourceCount)"),
                        KeyValueRow("Selected Item", document.selectedSource?.title ?? "None"),
                    ])
                }

                statusCard(title: "Device Cache", rows: document.deviceCacheSummaryRows)

                SystemSettingsView(document: document, showsSummary: false)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var editedDocumentCount: Int {
        workspace.voiceDocuments.values.filter(\.isEdited).count
            + workspace.configurationDocuments.values.filter(\.isEdited).count
    }

    private func statusCard(title: String, rows: [KeyValueRow]) -> some View {
        GroupBox {
            SummaryPanel(rows: rows)
                .padding(.top, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            SectionTitle(title)
        }
        .frame(minWidth: 300, maxWidth: .infinity, alignment: .topLeading)
    }
}

struct SystemSettingsView: View {
    @ObservedObject var document: DocumentModel
    var showsSummary = true

    var body: some View {
        Group {
            if showsSummary {
                ScrollView {
                    content
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                content
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            if showsSummary {
                SummaryPanel(rows: [
                    KeyValueRow("Destination", document.selectedDestinationName),
                    KeyValueRow("System Channel", "\(document.systemChannel + 1)"),
                    KeyValueRow("Protect", document.systemMemoryProtectEnabled ? "On" : "Off"),
                    KeyValueRow("Master Output", "\(document.systemMasterOutputLevel)"),
                ])
            }

            HStack(alignment: .top, spacing: 14) {
                GroupBox {
                    Picker("Channel", selection: Binding(
                        get: { document.systemChannel },
                        set: { document.setSystemChannel($0) }
                    )) {
                        ForEach(0..<16, id: \.self) { channel in
                            Text("\(channel + 1)").tag(channel)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 170)
                    .padding(.top, 4)
                    .forestHoverHelp("Chooses the FB-01 system channel used for device-level commands.")
                } label: {
                    SectionTitle("System Channel")
                }
                .frame(width: 220, alignment: .topLeading)

                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        RockerSwitch(label: EditorSynthModule.vocabulary.memoryProtectDisplayName, isOn: Binding(
                            get: { document.systemMemoryProtectEnabled },
                            set: { document.setMemoryProtect($0) }
                        ))

                        Text("Protect ON blocks stored voices and configurations. Store operations set Protect OFF before storing.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 4)
                } label: {
                    SectionTitle("Protect")
                }
                .frame(width: 300, alignment: .topLeading)

                GroupBox {
                    ParameterKnob(
                        label: "Level",
                        value: Binding(
                            get: { document.systemMasterOutputLevel },
                            set: { document.systemMasterOutputLevel = $0 }
                        ),
                        range: 0...127
                    )
                    .padding(.top, 4)

                    Button {
                        document.setMasterOutputLevel(document.systemMasterOutputLevel)
                    } label: {
                        Label("Send Output Level", systemImage: "speaker.wave.2")
                    }
                    .padding(.top, 10)
                    .disabled(document.isBusy)
                    .forestHoverHelp("Sends the current master output level to the FB-01.")
                } label: {
                    SectionTitle("Master Output")
                }
                .frame(width: 360, alignment: .topLeading)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    SummaryPanel(rows: [
                        KeyValueRow("Last Response", document.systemDeviceStatus),
                    ])

                    Button {
                        document.requestUnitID()
                    } label: {
                        Label("Request Unit ID", systemImage: "info.circle")
                    }
                    .disabled(document.isBusy)
                    .forestHoverHelp("Asks the connected FB-01 to identify itself and reports the last response.")
                }
                .padding(.top, 4)
            } label: {
                SectionTitle("Device Status")
            }
            .frame(minWidth: 420, maxWidth: 560, alignment: .topLeading)
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
                    ForEach(Array(artifact.messages.enumerated()), id: \.offset) { index, message in
                        MessageView(document: document, sourceID: source.id, index: index + 1, message: message, showsHeader: false)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
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
    var showsHeader = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsHeader {
                HStack {
                    Text(message.sourceTitle(index: index))
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text(message.displayName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
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

struct MissingEditorDocumentView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.badge.gearshape")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("Document Not Available")
                .font(.headline)
            Text("This editor document has already been closed. Use the File menu to load, fetch, or create another document.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }
}

struct DocumentWindowCloseGuard: NSViewRepresentable {
    var windowIdentifier: String
    var isEdited: () -> Bool
    var title: () -> String
    var save: () -> Void
    var onClose: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(windowIdentifier: windowIdentifier, isEdited: isEdited, title: title, save: save, onClose: onClose)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            if let window = view.window {
                context.coordinator.attach(to: window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.windowIdentifier = windowIdentifier
        context.coordinator.isEdited = isEdited
        context.coordinator.title = title
        context.coordinator.save = save
        context.coordinator.onClose = onClose
        DispatchQueue.main.async {
            if let window = nsView.window {
                context.coordinator.attach(to: window)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSWindowDelegate {
        var windowIdentifier: String
        var isEdited: () -> Bool
        var title: () -> String
        var save: () -> Void
        var onClose: () -> Void
        private weak var previousDelegate: NSWindowDelegate?
        private weak var window: NSWindow?

        init(windowIdentifier: String, isEdited: @escaping () -> Bool, title: @escaping () -> String, save: @escaping () -> Void, onClose: @escaping () -> Void) {
            self.windowIdentifier = windowIdentifier
            self.isEdited = isEdited
            self.title = title
            self.save = save
            self.onClose = onClose
        }

        func attach(to window: NSWindow) {
            window.identifier = NSUserInterfaceItemIdentifier(windowIdentifier)
            guard self.window !== window else {
                return
            }
            previousDelegate = window.delegate
            self.window = window
            window.delegate = self
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard isEdited() else {
                let shouldClose = previousDelegate?.windowShouldClose?(sender) ?? true
                if shouldClose {
                    onClose()
                }
                return shouldClose
            }

            let alert = NSAlert()
            alert.messageText = "Save Changes to \(title())?"
            alert.informativeText = "This document has unsaved changes."
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Discard Changes")
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .warning

            switch alert.runModal() {
            case .alertFirstButtonReturn:
                save()
                let shouldClose = !isEdited()
                if shouldClose {
                    onClose()
                }
                return shouldClose
            case .alertSecondButtonReturn:
                onClose()
                return true
            default:
                return false
            }
        }
    }
}

struct WindowActivationObserver: NSViewRepresentable {
    var onBecomeKey: () -> Void
    var onResignKey: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onBecomeKey: onBecomeKey, onResignKey: onResignKey)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            if let window = view.window {
                context.coordinator.attach(to: window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onBecomeKey = onBecomeKey
        context.coordinator.onResignKey = onResignKey
        DispatchQueue.main.async {
            if let window = nsView.window {
                context.coordinator.attach(to: window)
            }
        }
    }

    final class Coordinator: NSObject {
        var onBecomeKey: () -> Void
        var onResignKey: () -> Void
        private weak var window: NSWindow?

        init(onBecomeKey: @escaping () -> Void, onResignKey: @escaping () -> Void) {
            self.onBecomeKey = onBecomeKey
            self.onResignKey = onResignKey
            super.init()
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @MainActor
        func attach(to window: NSWindow) {
            guard self.window !== window else {
                return
            }
            NotificationCenter.default.removeObserver(self)
            self.window = window
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleBecomeKey),
                name: NSWindow.didBecomeKeyNotification,
                object: window
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleResignKey),
                name: NSWindow.didResignKeyNotification,
                object: window
            )
            if window.isKeyWindow {
                onBecomeKey()
            }
        }

        @objc private func handleBecomeKey() {
            onBecomeKey()
        }

        @objc private func handleResignKey() {
            onResignKey()
        }
    }
}

struct VoiceDocumentLayoutInvalidator: NSViewRepresentable {
    var token: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        PassthroughLayoutInvalidationView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard context.coordinator.lastToken != token else {
            return
        }
        context.coordinator.lastToken = token

        DispatchQueue.main.async {
            invalidateLayout(from: nsView)
        }
    }

    private func invalidateLayout(from nsView: NSView) {
        var current: NSView? = nsView
        while let view = current {
            view.needsLayout = true
            view.needsDisplay = true
            current = view.superview
        }

        if let scrollView = enclosingScrollView(for: nsView) {
            scrollView.needsLayout = true
            scrollView.documentView?.needsLayout = true
            scrollView.contentView.needsLayout = true
            scrollView.documentView?.layoutSubtreeIfNeeded()
            scrollView.contentView.layoutSubtreeIfNeeded()
            scrollView.reflectScrolledClipView(scrollView.contentView)
            scrollView.tile()
        }

        nsView.window?.contentView?.needsLayout = true
        nsView.window?.contentView?.layoutSubtreeIfNeeded()
        nsView.window?.contentView?.displayIfNeeded()
    }

    private func enclosingScrollView(for nsView: NSView) -> NSScrollView? {
        var current: NSView? = nsView
        while let view = current {
            if let scrollView = view as? NSScrollView {
                return scrollView
            }
            current = view.superview
        }
        return nil
    }

    final class Coordinator {
        var lastToken: Int?
    }
}

private final class PassthroughLayoutInvalidationView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

struct MainWindowSizeConfigurator: NSViewRepresentable {
    var contentSize: CGSize

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else {
            return
        }

        let screenVisibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame
        let visibleContentSize = screenVisibleFrame.map { CGSize(width: max(720, $0.width - 32), height: max(640, $0.height - 32)) } ?? contentSize
        let minimumWindowContentSize = CGSize(
            width: min(contentSize.width, visibleContentSize.width),
            height: min(contentSize.height, visibleContentSize.height)
        )

        window.contentMinSize = CGSize(width: 720, height: 640)

        let currentContentSize = window.contentView?.bounds.size ?? .zero
        guard currentContentSize.width < minimumWindowContentSize.width || currentContentSize.height < minimumWindowContentSize.height else {
            clamp(window: window)
            return
        }

        let frameSize = window.frameRect(forContentRect: CGRect(origin: .zero, size: minimumWindowContentSize)).size
        var frame = window.frame
        frame.size.width = max(frame.width, frameSize.width)
        frame.size.height = max(frame.height, frameSize.height)

        if let visibleFrame = screenVisibleFrame {
            let maxFrameWidth = max(720, visibleFrame.width - 16)
            let maxFrameHeight = max(640, visibleFrame.height - 16)
            frame.size.width = min(frame.width, maxFrameWidth)
            frame.size.height = min(frame.height, maxFrameHeight)
            frame.origin.x = visibleFrame.minX + max(0, (visibleFrame.width - frame.width) / 2)
            frame.origin.y = visibleFrame.minY + max(0, (visibleFrame.height - frame.height) / 2)
        }

        window.setFrame(frame, display: true)
    }

    private func clamp(window: NSWindow) {
        guard let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame else {
            return
        }

        var frame = window.frame
        let maxFrameWidth = max(720, visibleFrame.width - 16)
        let maxFrameHeight = max(640, visibleFrame.height - 16)
        frame.size.width = min(frame.width, maxFrameWidth)
        frame.size.height = min(frame.height, maxFrameHeight)
        frame.origin.x = min(max(frame.origin.x, visibleFrame.minX + 8), visibleFrame.maxX - frame.width - 8)
        frame.origin.y = min(max(frame.origin.y, visibleFrame.minY + 8), visibleFrame.maxY - frame.height - 8)
        window.setFrame(frame, display: true)
    }
}

struct DocumentMIDIContextView: View {
    @ObservedObject var device: DocumentModel
    var documentSystemChannel: Int

    var body: some View {
        HStack(spacing: 14) {
            Label(device.selectedSourceName, systemImage: "arrow.down.circle")
                .lineLimit(1)
            Label(device.selectedDestinationName, systemImage: "arrow.up.circle")
                .lineLimit(1)
            Label("System \(device.systemChannel + 1)", systemImage: "number.circle")
            Text("Document SysEx channel \(documentSystemChannel + 1)")
                .foregroundStyle(.secondary)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }
}

struct FB01TransferToolbarIcon: View {
    enum Direction {
        case fetch
        case store
    }

    var direction: Direction

    var body: some View {
        Canvas { context, size in
            let stroke = context.resolve(.foreground)
            let lineWidth = max(size.width * 0.075, 1.4)
            let deviceRect = CGRect(
                x: size.width * 0.18,
                y: size.height * 0.58,
                width: size.width * 0.64,
                height: size.height * 0.24
            )

            let device = Path(roundedRect: deviceRect, cornerRadius: size.width * 0.06)
            context.stroke(device, with: stroke, lineWidth: lineWidth)

            let display = Path(roundedRect: CGRect(
                x: deviceRect.minX + deviceRect.width * 0.12,
                y: deviceRect.minY + deviceRect.height * 0.28,
                width: deviceRect.width * 0.24,
                height: deviceRect.height * 0.28
            ), cornerRadius: size.width * 0.02)
            context.stroke(display, with: stroke, lineWidth: lineWidth * 0.75)

            var arrow = Path()
            switch direction {
            case .fetch:
                arrow.move(to: CGPoint(x: size.width * 0.50, y: deviceRect.minY - size.height * 0.04))
                arrow.addLine(to: CGPoint(x: size.width * 0.50, y: size.height * 0.18))
                arrow.move(to: CGPoint(x: size.width * 0.32, y: size.height * 0.34))
                arrow.addLine(to: CGPoint(x: size.width * 0.50, y: size.height * 0.16))
                arrow.addLine(to: CGPoint(x: size.width * 0.68, y: size.height * 0.34))
            case .store:
                arrow.move(to: CGPoint(x: size.width * 0.50, y: size.height * 0.16))
                arrow.addLine(to: CGPoint(x: size.width * 0.50, y: deviceRect.minY - size.height * 0.02))
                arrow.move(to: CGPoint(x: size.width * 0.32, y: deviceRect.minY - size.height * 0.18))
                arrow.addLine(to: CGPoint(x: size.width * 0.50, y: deviceRect.minY))
                arrow.addLine(to: CGPoint(x: size.width * 0.68, y: deviceRect.minY - size.height * 0.18))
            }
            context.stroke(arrow, with: stroke, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }
}

struct VoiceDocumentLiveKeyboardView: View {
    @ObservedObject var document: VoiceDocumentModel
    @ObservedObject var device: DocumentModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LiveKeyboardMIDIControlsView(
                document: device,
                title: document.voice.name.isEmpty ? "Live Keyboard" : "Live Keyboard - \(document.voice.name)",
                subtitle: "Document voice"
            )

            PianoKeyboardRepresentable(
                startNote: device.keyboardStartNote,
                octaveCount: 5,
                highlightedNotes: device.externalKeyboardPressedNotes,
                noteOn: { document.sendKeyboardNote($0, isOn: true, device: device) },
                noteOff: { document.sendKeyboardNote($0, isOn: false, device: device) }
            )
            .frame(height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
        }
        .background(WindowActivationObserver(
            onBecomeKey: {
                registerExternalKeyboardHandler()
                document.scheduleKeyboardVoicePreparation(device: device)
            },
            onResignKey: {
                document.cancelKeyboardVoicePreparation()
                // Keep the last active document handler until another document takes over or this window closes.
            }
        ))
        .onAppear {
            registerExternalKeyboardHandler()
            document.scheduleKeyboardVoicePreparation(device: device)
        }
        .onDisappear {
            document.cancelKeyboardVoicePreparation()
            device.setExternalKeyboardDocumentHandler(nil)
        }
        .onChange(of: document.voice) {
            document.scheduleKeyboardVoicePreparation(device: device, delayNanoseconds: voiceDocumentEditPreparationDelayNanoseconds)
        }
        .onChange(of: device.keyboardChannel) {
            document.scheduleKeyboardVoicePreparation(device: device)
        }
        .onChange(of: device.selectedDestinationIndex) {
            document.scheduleKeyboardVoicePreparation(device: device)
        }
    }

    private func registerExternalKeyboardHandler() {
        device.setLiveKeyboardContext(
            title: document.voice.name.isEmpty ? "Live Keyboard" : "Live Keyboard - \(document.voice.name)",
            subtitle: "Document voice",
            noteOn: { [weak document, weak device] note in
                guard let document, let device else { return }
                document.sendKeyboardNote(note, isOn: true, device: device)
            },
            noteOff: { [weak document, weak device] note in
                guard let document, let device else { return }
                document.sendKeyboardNote(note, isOn: false, device: device)
            }
        )
        device.setExternalKeyboardDocumentHandler { [weak document, weak device] message in
            guard let document, let device else {
                return false
            }
            return document.receiveExternalKeyboardMessage(message, device: device)
        }
    }
}

struct ConfigurationDocumentLiveKeyboardView: View {
    @ObservedObject var device: DocumentModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LiveKeyboardMIDIControlsView(
                document: device,
                title: "Live Keyboard",
                subtitle: "Configuration performance"
            )

            PianoKeyboardRepresentable(
                startNote: device.keyboardStartNote,
                octaveCount: 5,
                highlightedNotes: device.externalKeyboardPressedNotes,
                noteOn: { device.sendKeyboardNoteWithoutVoicePreparation($0, isOn: true) },
                noteOff: { device.sendKeyboardNoteWithoutVoicePreparation($0, isOn: false) }
            )
            .frame(height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
        }
        .background(WindowActivationObserver(
            onBecomeKey: {
                device.setLiveKeyboardContext(
                    title: "Live Keyboard",
                    subtitle: "Configuration performance",
                    noteOn: { [weak device] note in
                        device?.sendKeyboardNoteWithoutVoicePreparation(note, isOn: true)
                    },
                    noteOff: { [weak device] note in
                        device?.sendKeyboardNoteWithoutVoicePreparation(note, isOn: false)
                    }
                )
                device.setExternalKeyboardDocumentHandler { [weak device] message in
                    device?.receiveExternalKeyboardPerformanceMessage(message) ?? false
                }
            },
            onResignKey: {
                // Keep the last active document handler until another document takes over or this window closes.
            }
        ))
        .onAppear {
            device.setLiveKeyboardContext(
                title: "Live Keyboard",
                subtitle: "Configuration performance",
                noteOn: { [weak device] note in
                    device?.sendKeyboardNoteWithoutVoicePreparation(note, isOn: true)
                },
                noteOff: { [weak device] note in
                    device?.sendKeyboardNoteWithoutVoicePreparation(note, isOn: false)
                }
            )
        }
        .onDisappear {
            device.setExternalKeyboardDocumentHandler(nil)
        }
    }
}

struct VoiceDocumentWindow: View {
    @ObservedObject var document: VoiceDocumentModel
    @ObservedObject var device: DocumentModel
    var closeDocument: () -> Void

    private var voice: FB01VoiceData {
        document.voice
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(voice.name.isEmpty ? "Untitled Voice" : voice.name)
                            .font(.title2.weight(.semibold))
                        Text(document.fileURL?.path ?? "New voice document")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(document.isEdited ? "Edited" : "Saved")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(document.isEdited ? .orange : .secondary)
                }

                DocumentMIDIContextView(device: device, documentSystemChannel: document.systemChannel)

                SummaryPanel(rows: [
                    KeyValueRow("System Channel", "\(document.systemChannel + 1)"),
                    KeyValueRow("Feedback", "\(voice.feedbackLevel)"),
                ])

                if device.voiceEditorParadigm == .consoleSections {
                    VoiceEditorControls(
                        name: Binding(
                            get: { voice.name },
                            set: { setName($0) }
                        ),
                        feedback: Binding(
                            get: { voice.feedbackLevel },
                            set: { newValue in document.updateVoice { voice in try voice.settingFeedbackLevel(newValue) } }
                        ),
                        userCode: Binding(
                            get: { voice.userCode },
                            set: { newValue in document.updateVoice { voice in try voice.settingUserCode(newValue) } }
                        ),
                        lfoSpeed: Binding(
                            get: { voice.lfoSpeed },
                            set: { newValue in document.updateVoice { voice in try voice.settingLFOSpeed(newValue) } }
                        ),
                        lfoWaveform: Binding(
                            get: { voice.lfoWaveform },
                            set: { newValue in document.updateVoice { voice in try voice.settingLFOWaveform(newValue) } }
                        ),
                        loadLFODataEnabled: Binding(
                            get: { voice.loadLFODataEnabled },
                            set: { newValue in document.updateVoice { voice in try voice.settingLoadLFODataEnabled(newValue) } }
                        ),
                        lfoSyncEnabled: Binding(
                            get: { voice.lfoSyncEnabled },
                            set: { newValue in document.updateVoice { voice in try voice.settingLFOSyncEnabled(newValue) } }
                        ),
                        amplitudeModulationDepth: Binding(
                            get: { voice.amplitudeModulationDepth },
                            set: { newValue in document.updateVoice { voice in try voice.settingAmplitudeModulationDepth(newValue) } }
                        ),
                        pitchModulationDepth: Binding(
                            get: { voice.pitchModulationDepth },
                            set: { newValue in document.updateVoice { voice in try voice.settingPitchModulationDepth(newValue) } }
                        ),
                        amplitudeModulationSensitivity: Binding(
                            get: { voice.amplitudeModulationSensitivity },
                            set: { newValue in document.updateVoice { voice in try voice.settingAmplitudeModulationSensitivity(newValue) } }
                        ),
                        pitchModulationSensitivity: Binding(
                            get: { voice.pitchModulationSensitivity },
                            set: { newValue in document.updateVoice { voice in try voice.settingPitchModulationSensitivity(newValue) } }
                        ),
                        transpose: Binding(
                            get: { voice.transpose },
                            set: { newValue in document.updateVoice { voice in try voice.settingTranspose(newValue) } }
                        ),
                        leftOutputEnabled: Binding(
                            get: { voice.leftOutputEnabled },
                            set: { newValue in document.updateVoice { voice in try voice.settingLeftOutputEnabled(newValue) } }
                        ),
                        rightOutputEnabled: Binding(
                            get: { voice.rightOutputEnabled },
                            set: { newValue in document.updateVoice { voice in try voice.settingRightOutputEnabled(newValue) } }
                        )
                    )

                    AlgorithmSelectorView(selection: Binding(
                        get: { voice.algorithm + 1 },
                        set: { newValue in document.updateVoice { voice in try voice.settingAlgorithmAndOperatorRoles(newValue - 1) } }
                    ))

                    OperatorEditor(
                        operators: voice.operators,
                        operatorEnabled: (0..<FB01VoiceData.operatorCount).map { index in
                            Binding(
                                get: { voice.operatorEnabled[index] },
                                set: { enabled in
                                    document.updateVoiceRefreshingLayout { try $0.settingOperatorEnabled(index: index, enabled: enabled) }
                                }
                            )
                        },
                        selectedOperatorIndex: Binding(
                            get: { document.selectedOperatorIndex },
                            set: { document.selectedOperatorIndex = $0 }
                        ),
                        updateOperator: { operatorData in
                            document.updateVoice { try $0.replacingOperator(operatorData) }
                        }
                    )
                } else {
                    FMRoutingPatchBayView(
                        name: Binding(
                            get: { voice.name },
                            set: { setName($0) }
                        ),
                        algorithm: Binding(
                            get: { voice.algorithm + 1 },
                            set: { newValue in document.updateVoice { voice in try voice.settingAlgorithmAndOperatorRoles(newValue - 1) } }
                        ),
                        feedback: Binding(
                            get: { voice.feedbackLevel },
                            set: { newValue in document.updateVoice { voice in try voice.settingFeedbackLevel(newValue) } }
                        ),
                        userCode: Binding(
                            get: { voice.userCode },
                            set: { newValue in document.updateVoice { voice in try voice.settingUserCode(newValue) } }
                        ),
                        lfoSpeed: Binding(
                            get: { voice.lfoSpeed },
                            set: { newValue in document.updateVoice { voice in try voice.settingLFOSpeed(newValue) } }
                        ),
                        lfoWaveform: Binding(
                            get: { voice.lfoWaveform },
                            set: { newValue in document.updateVoice { voice in try voice.settingLFOWaveform(newValue) } }
                        ),
                        loadLFODataEnabled: Binding(
                            get: { voice.loadLFODataEnabled },
                            set: { newValue in document.updateVoice { voice in try voice.settingLoadLFODataEnabled(newValue) } }
                        ),
                        lfoSyncEnabled: Binding(
                            get: { voice.lfoSyncEnabled },
                            set: { newValue in document.updateVoice { voice in try voice.settingLFOSyncEnabled(newValue) } }
                        ),
                        amplitudeModulationDepth: Binding(
                            get: { voice.amplitudeModulationDepth },
                            set: { newValue in document.updateVoice { voice in try voice.settingAmplitudeModulationDepth(newValue) } }
                        ),
                        pitchModulationDepth: Binding(
                            get: { voice.pitchModulationDepth },
                            set: { newValue in document.updateVoice { voice in try voice.settingPitchModulationDepth(newValue) } }
                        ),
                        amplitudeModulationSensitivity: Binding(
                            get: { voice.amplitudeModulationSensitivity },
                            set: { newValue in document.updateVoice { voice in try voice.settingAmplitudeModulationSensitivity(newValue) } }
                        ),
                        pitchModulationSensitivity: Binding(
                            get: { voice.pitchModulationSensitivity },
                            set: { newValue in document.updateVoice { voice in try voice.settingPitchModulationSensitivity(newValue) } }
                        ),
                        transpose: Binding(
                            get: { voice.transpose },
                            set: { newValue in document.updateVoice { voice in try voice.settingTranspose(newValue) } }
                        ),
                        leftOutputEnabled: Binding(
                            get: { voice.leftOutputEnabled },
                            set: { newValue in document.updateVoice { voice in try voice.settingLeftOutputEnabled(newValue) } }
                        ),
                        rightOutputEnabled: Binding(
                            get: { voice.rightOutputEnabled },
                            set: { newValue in document.updateVoice { voice in try voice.settingRightOutputEnabled(newValue) } }
                        ),
                        voiceCharacterType: Binding(
                            get: { document.voiceCharacterType },
                            set: { document.voiceCharacterType = $0 }
                        ),
                        macroValue: { macro in
                            Binding(
                                get: { document.value(for: macro) },
                                set: { document.setPerformanceMacro(macro, value: $0) }
                            )
                        },
                        operators: voice.operators,
                        operatorEnabled: (0..<FB01VoiceData.operatorCount).map { index in
                            Binding(
                                get: { voice.operatorEnabled[index] },
                                set: { enabled in
                                    document.updateVoiceRefreshingLayout { try $0.settingOperatorEnabled(index: index, enabled: enabled) }
                                }
                            )
                        },
                        selectedOperatorIndex: Binding(
                            get: { document.selectedOperatorIndex },
                            set: { document.selectedOperatorIndex = $0 }
                        ),
                        updateOperator: { operatorData in
                            document.updateVoice { try $0.replacingOperator(operatorData) }
                        }
                    )
                }

                DocumentStatusFooter(errorMessage: document.errorMessage, statusMessage: document.statusMessage, isBusy: document.isBusy)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(document.layoutRevision)
        }
        .environment(\.forestHoverTextEnabled, device.hoverTextEnabled)
        .navigationTitle("Voice - \(document.title)")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    document.save()
                } label: {
                    Label("Save File", systemImage: "square.and.arrow.down")
                }
                .forestHoverHelp("Save voice to file")
                .disabled(document.isBusy)

                Button {
                    document.fetchFromDevice(device: device)
                } label: {
                    Label {
                        Text("Fetch Device")
                    } icon: {
                        FB01TransferToolbarIcon(direction: .fetch)
                    }
                }
                .forestHoverHelp("Fetch voice from device into this voice document")
                .disabled(device.isBusy || document.isBusy)

                Button {
                    document.storeToDevice(device: device)
                } label: {
                    Label {
                        Text("Store Slot")
                    } icon: {
                        FB01TransferToolbarIcon(direction: .store)
                    }
                }
                .forestHoverHelp("Store this voice to a device slot")
                .disabled(device.isBusy || document.isBusy)

                Button {
                    document.reset()
                } label: {
                    Label("Revert", systemImage: "arrow.uturn.backward")
                }
                .forestHoverHelp("Revert to last saved voice")
                .disabled(!document.isEdited || document.isBusy)
            }
        }
        .background(DocumentWindowCloseGuard(
            windowIdentifier: EditorDocumentWorkspace.voiceWindowIdentifier(for: document.id),
            isEdited: { document.isEdited },
            title: { document.title },
            save: { document.save() },
            onClose: closeDocument
        ))
        .background(WindowActivationObserver(
            onBecomeKey: {
                registerLiveKeyboardContext()
                document.scheduleKeyboardVoicePreparation(device: device)
            },
            onResignKey: {
                document.cancelKeyboardVoicePreparation()
            }
        ))
        .onAppear {
            registerLiveKeyboardContext()
            document.scheduleKeyboardVoicePreparation(device: device)
        }
        .onDisappear {
            document.cancelKeyboardVoicePreparation()
            device.setExternalKeyboardDocumentHandler(nil)
        }
        .onChange(of: document.voice) {
            registerLiveKeyboardContext()
            document.scheduleKeyboardVoicePreparation(device: device, delayNanoseconds: voiceDocumentEditPreparationDelayNanoseconds)
        }
        .onChange(of: device.keyboardChannel) {
            document.scheduleKeyboardVoicePreparation(device: device)
        }
        .onChange(of: device.selectedDestinationIndex) {
            document.scheduleKeyboardVoicePreparation(device: device)
        }
        .focusedSceneValue(\.activeEditorDocumentActions, ActiveEditorDocumentActions(
            kind: .voice,
            save: { document.save() },
            saveTitle: "Save Voice to File",
            saveAs: { document.saveAs() },
            saveAsTitle: "Save Voice to File As...",
            reset: { document.reset() },
            importFromDisk: { document.importFromDisk() },
            importFromDiskTitle: "Import Voice from File into Current Document...",
            importFromLibrary: { device in document.importFromLibrary(device: device) },
            canImportFromLibrary: { device in device.selectedVoiceDocumentPayload() != nil },
            importFromLibraryTitle: "Import Selected Library Voice Into Current Document",
            fetchFromDevice: { device in document.fetchFromDevice(device: device) },
            fetchFromDeviceTitle: "Fetch Voice from Device into Current Document...",
            storeToDevice: { device in document.storeToDevice(device: device) },
            storeToDeviceTitle: "Store Voice to Device Slot...",
            isEdited: document.isEdited,
            isBusy: document.isBusy
        ))
    }

    private func setName(_ value: String) {
        document.setName(value)
    }

    private func registerLiveKeyboardContext() {
        device.setLiveKeyboardContext(
            title: voice.name.isEmpty ? "Live Keyboard" : "Live Keyboard - \(voice.name)",
            subtitle: "Document voice",
            noteOn: { [weak document, weak device] note in
                guard let document, let device else { return }
                document.sendKeyboardNote(note, isOn: true, device: device)
            },
            noteOff: { [weak document, weak device] note in
                guard let document, let device else { return }
                document.sendKeyboardNote(note, isOn: false, device: device)
            }
        )
        device.setExternalKeyboardDocumentHandler { [weak document, weak device] message in
            guard let document, let device else {
                return false
            }
            return document.receiveExternalKeyboardMessage(message, device: device)
        }
    }
}

struct ConfigurationDocumentWindow: View {
    @ObservedObject var document: ConfigurationDocumentModel
    @ObservedObject var device: DocumentModel
    var closeDocument: () -> Void

    private var configuration: FB01ConfigurationData {
        document.configuration
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Spacer()
                    Text(document.isEdited ? "Edited" : "Saved")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(document.isEdited ? .orange : .secondary)
                }

                DocumentMIDIContextView(device: device, documentSystemChannel: document.systemChannel)

                ConfigurationEditorControls(
                    name: Binding(
                        get: { configuration.name },
                        set: { setName($0) }
                    ),
                    combineModeEnabled: Binding(
                        get: { configuration.combineModeEnabled },
                        set: { newValue in document.updateConfiguration { configuration in try configuration.settingCombineModeEnabled(newValue) } }
                    ),
                    keyCodeReceiveMode: Binding(
                        get: { configuration.keyCodeReceiveMode },
                        set: { newValue in document.updateConfiguration { configuration in try configuration.settingKeyCodeReceiveMode(newValue) } }
                    ),
                    lfoSpeed: Binding(
                        get: { configuration.lfoSpeed },
                        set: { newValue in document.updateConfiguration { configuration in try configuration.settingLFOSpeed(newValue) } }
                    ),
                    amplitudeModulationDepth: Binding(
                        get: { configuration.amplitudeModulationDepth },
                        set: { newValue in document.updateConfiguration { configuration in try configuration.settingAmplitudeModulationDepth(newValue) } }
                    ),
                    pitchModulationDepth: Binding(
                        get: { configuration.pitchModulationDepth },
                        set: { newValue in document.updateConfiguration { configuration in try configuration.settingPitchModulationDepth(newValue) } }
                    ),
                    lfoWaveform: Binding(
                        get: { configuration.lfoWaveform },
                        set: { newValue in document.updateConfiguration { configuration in try configuration.settingLFOWaveform(newValue) } }
                    )
                )

                ConfigurationInstrumentEditor(
                    instruments: configuration.instruments,
                    voiceName: { device.configurationInstrumentVoiceName($0) },
                    pitchModulationDepth: Binding(
                        get: { configuration.pitchModulationDepth },
                        set: { newValue in document.updateConfiguration { configuration in try configuration.settingPitchModulationDepth(newValue) } }
                    ),
                    updateInstrument: { instrument in
                        document.updateConfiguration { try $0.replacingInstrument(instrument) }
                    }
                )

                DocumentStatusFooter(errorMessage: document.errorMessage, statusMessage: document.statusMessage, isBusy: document.isBusy)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .environment(\.forestHoverTextEnabled, device.hoverTextEnabled)
        .navigationTitle("Configuration - \(document.title)")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    document.save()
                } label: {
                    Label("Save File", systemImage: "square.and.arrow.down")
                }
                .forestHoverHelp("Save configuration to file")
                .disabled(document.isBusy)

                Button {
                    document.fetchFromDevice(device: device)
                } label: {
                    Label {
                        Text("Fetch Device")
                    } icon: {
                        FB01TransferToolbarIcon(direction: .fetch)
                    }
                }
                .forestHoverHelp("Fetch configuration from device into this configuration document")
                .disabled(device.isBusy || document.isBusy)

                Button {
                    document.storeToDevice(device: device)
                } label: {
                    Label {
                        Text("Store Slot")
                    } icon: {
                        FB01TransferToolbarIcon(direction: .store)
                    }
                }
                .forestHoverHelp("Store this configuration to a device slot")
                .disabled(device.isBusy || document.isBusy)

                Button {
                    document.reset()
                } label: {
                    Label("Revert", systemImage: "arrow.uturn.backward")
                }
                .forestHoverHelp("Revert to last saved configuration")
                .disabled(!document.isEdited || document.isBusy)
            }
        }
        .background(DocumentWindowCloseGuard(
            windowIdentifier: EditorDocumentWorkspace.configurationWindowIdentifier(for: document.id),
            isEdited: { document.isEdited },
            title: { document.title },
            save: { document.save() },
            onClose: closeDocument
        ))
        .background(WindowActivationObserver(
            onBecomeKey: {
                registerLiveKeyboardContext()
            },
            onResignKey: {}
        ))
        .onAppear {
            registerLiveKeyboardContext()
        }
        .onDisappear {
            device.setExternalKeyboardDocumentHandler(nil)
        }
        .focusedSceneValue(\.activeEditorDocumentActions, ActiveEditorDocumentActions(
            kind: .configuration,
            save: { document.save() },
            saveTitle: "Save Configuration to File",
            saveAs: { document.saveAs() },
            saveAsTitle: "Save Configuration to File As...",
            reset: { document.reset() },
            importFromDisk: { document.importFromDisk() },
            importFromDiskTitle: "Import Configuration from File into Current Document...",
            importFromLibrary: { device in document.importFromLibrary(device: device) },
            canImportFromLibrary: { device in device.selectedConfigurationDocumentPayload() != nil },
            importFromLibraryTitle: "Import Selected Library Configuration Into Current Document",
            fetchFromDevice: { device in document.fetchFromDevice(device: device) },
            fetchFromDeviceTitle: "Fetch Configuration from Device into Current Document...",
            storeToDevice: { device in document.storeToDevice(device: device) },
            storeToDeviceTitle: "Store Configuration to Device Slot...",
            isEdited: document.isEdited,
            isBusy: document.isBusy
        ))
    }

    private func setName(_ value: String) {
        document.setName(value)
    }

    private func registerLiveKeyboardContext() {
        device.setLiveKeyboardContext(
            title: "Live Keyboard",
            subtitle: "Configuration performance",
            noteOn: { [weak device] note in
                device?.sendKeyboardNoteWithoutVoicePreparation(note, isOn: true)
            },
            noteOff: { [weak device] note in
                device?.sendKeyboardNoteWithoutVoicePreparation(note, isOn: false)
            }
        )
        device.setExternalKeyboardDocumentHandler { [weak device] message in
            device?.receiveExternalKeyboardPerformanceMessage(message) ?? false
        }
    }
}

struct DocumentStatusFooter: View {
    var errorMessage: String?
    var statusMessage: String?
    var isBusy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isBusy {
                Label("Working...", systemImage: "progress.indicator")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.10), in: RoundedRectangle(cornerRadius: 6))
            }

            if let statusMessage {
                Label(statusMessage, systemImage: statusMessage.localizedCaseInsensitiveContains("confirmed") ? "checkmark.seal.fill" : "info.circle")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(statusMessage.localizedCaseInsensitiveContains("confirmed") ? .green : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        (statusMessage.localizedCaseInsensitiveContains("confirmed") ? Color.green : Color.secondary).opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 6)
                    )
            }
        }
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
                    Button {
                        document.sendAndConfirmConfigurationToCurrentEditBuffer(sourceID: sourceID, payload: editableConfiguration)
                    } label: {
                        Label("Send & Confirm", systemImage: "checkmark.seal")
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
                    voiceName: { document.configurationInstrumentVoiceName($0) },
                    pitchModulationDepth: Binding(
                        get: { editableConfiguration.pitchModulationDepth },
                        set: { setPitchModulationDepth($0) }
                    ),
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
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                identityControls
                receiveAndWaveformControls
                lfoAndModulationControls
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 16) {
                    identityControls
                    receiveAndWaveformControls
                }
                lfoAndModulationControls
            }

            VStack(alignment: .leading, spacing: 14) {
                identityControls
                receiveAndWaveformControls
                lfoAndModulationControls
            }
        }
    }

    private var identityControls: some View {
        GroupBox {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                GridRow {
                    label("Name")
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 180)
                        .forestHoverHelp("Names the configuration as it will appear in Forest documents and saved configuration files.")
                }

                GridRow {
                    label("Combine")
                    RockerSwitch(label: "Layer Instruments", isOn: $combineModeEnabled, width: 92, height: 58)
                }
            }
            .padding(.top, 4)
        } label: {
            SectionTitle("Identity")
        }
        .frame(width: 220, height: 190, alignment: .topLeading)
    }

    private var receiveAndWaveformControls: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    label("Key-Code")
                    Picker("", selection: $keyCodeReceiveMode) {
                        Text("All").tag(FB01KeyCodeReceiveMode.all)
                        Text("Even").tag(FB01KeyCodeReceiveMode.even)
                        Text("Odd").tag(FB01KeyCodeReceiveMode.odd)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 190)
                    .forestHoverHelp("Chooses which incoming key-code numbers this configuration receives: all keys, even keys, or odd keys.")
                }

                VStack(alignment: .leading, spacing: 6) {
                    label("Waveform")
                    WaveformPicker(selection: $lfoWaveform)
                        .frame(width: 342)
                }
            }
            .padding(.top, 4)
        } label: {
            SectionTitle("Receive and Waveform")
        }
        .frame(width: 370, height: 190, alignment: .topLeading)
    }

    private var lfoAndModulationControls: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 12) {
                ParameterKnob(label: "LFO Speed", value: $lfoSpeed, range: 0...127)
                ParameterKnob(label: "Amplitude MOD\nDepth", value: $amplitudeModulationDepth, range: 0...127)
                ParameterKnob(label: "Pitch MOD\nDepth", value: $pitchModulationDepth, range: 0...127)
            }
            .padding(.top, 4)
        } label: {
            SectionTitle("LFO and Modulation")
        }
        .frame(width: 330, height: 190, alignment: .topLeading)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

struct ConfigurationInstrumentEditor: View {
    var instruments: [FB01InstrumentConfiguration]
    var voiceName: (FB01InstrumentConfiguration) -> String?
    @Binding var pitchModulationDepth: Int
    var updateInstrument: (FB01InstrumentConfiguration) -> Void
    @State private var selectedInstrumentIndex = 0
    @State private var showAllNotesAssignedAlert = false

    private var selectedInstrument: FB01InstrumentConfiguration? {
        instruments.first { $0.index == selectedInstrumentIndex } ?? instruments.first
    }

    private var assignedNoteCount: Int {
        instruments.reduce(0) { total, instrument in
            total + instrument.noteCount
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Instruments")

            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(columns: instrumentColumns, alignment: .leading, spacing: 10) {
                    ForEach(0..<min(instruments.count, 8), id: \.self) { index in
                        let instrument = instruments[index]
                        ConfigurationInstrumentSelectorButton(
                            instrument: instrument,
                            voiceName: voiceName(instrument),
                            isSelected: instrument.index == selectedInstrumentIndex
                        ) {
                            selectInstrument(instrument)
                        }
                        .frame(minWidth: 164, maxWidth: .infinity)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    if let selectedInstrument {
                        ConfigurationInstrumentInspector(
                            instrument: selectedInstrument,
                            assignedNoteCount: assignedNoteCount,
                            pitchModulationDepth: $pitchModulationDepth,
                            updateInstrument: updateInstrument,
                            showAllNotesAssignedAlert: {
                                showAllNotesAssignedAlert = true
                            }
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
            )
        }
        .padding(.top, 10)
        .onChange(of: instruments) { _, newInstruments in
            guard !newInstruments.contains(where: { $0.index == selectedInstrumentIndex }) else {
                return
            }
            selectedInstrumentIndex = newInstruments.first?.index ?? 0
        }
        .alert("Reduce Active Notes", isPresented: $showAllNotesAssignedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("All 8 notes are assigned. Reduce the number of active notes assigned to other Instruments before adding a new Instrument.")
        }
    }

    private var instrumentColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 164), spacing: 10), count: 4)
    }

    private func selectInstrument(_ instrument: FB01InstrumentConfiguration) {
        guard instrument.noteCount == 0, assignedNoteCount >= 8 else {
            selectedInstrumentIndex = instrument.index
            return
        }

        showAllNotesAssignedAlert = true
    }
}

struct ConfigurationInstrumentSelectorButton: View {
    var instrument: FB01InstrumentConfiguration
    var voiceName: String?
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

                Text("MIDI \(instrument.midiChannel + 1), Notes \(instrument.noteCount), Voice \(instrument.voiceBank)/\(instrument.voiceNumber)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let voiceName, !voiceName.isEmpty {
                    Text(voiceName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                } else {
                    Text("Voice name unavailable")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text("Lvl")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.secondary.opacity(0.18))
                            Capsule()
                                .fill(Color.green)
                                .frame(width: proxy.size.width * CGFloat(displayedOutputLevel) / 127)
                        }
                    }
                    .frame(height: 5)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.green.opacity(0.16) : Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isSelected ? Color.green : Color.secondary.opacity(0.22), lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .forestHoverHelp("Selects Instrument \(instrument.index + 1) for editing. Notes, MIDI channel, voice slot, and output controls below apply to this instrument.")
    }

    private var displayedOutputLevel: Int {
        instrument.noteCount == 0 ? 0 : instrument.outputLevel
    }
}

struct ConfigurationInstrumentInspector: View {
    var instrument: FB01InstrumentConfiguration
    var assignedNoteCount: Int
    @Binding var pitchModulationDepth: Int
    var updateInstrument: (FB01InstrumentConfiguration) -> Void
    var showAllNotesAssignedAlert: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            controlPairRow {
                assignMIDIAndVoiceControls
            } trailing: {
                keyRangeControls
            }

            controlPairRow {
                outputControls
            } trailing: {
                performanceControls
            }
        }
    }

    private func controlPairRow<Leading: View, Trailing: View>(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                leading()
                    .frame(minWidth: 220, maxWidth: .infinity, alignment: .topLeading)
                trailing()
                    .frame(minWidth: 220, maxWidth: .infinity, alignment: .topLeading)
            }

            VStack(alignment: .leading, spacing: 12) {
                leading()
                trailing()
            }
        }
    }

    private var assignMIDIAndVoiceControls: some View {
        OperatorControlGroup(title: "Assign MIDI Channel and Voice") {
            HStack(alignment: .top, spacing: 12) {
                instrumentKnob("MIDI Channel", value: instrument.midiChannel + 1, range: 1...16) { try instrument.settingMIDIChannel($0 - 1) }
                instrumentKnob("Voice Bank", value: instrument.voiceBank, range: 1...7) { try instrument.settingVoiceBank($0) }
                instrumentKnob("Voice Number", value: instrument.voiceNumber, range: 0...95) { try instrument.settingVoiceNumber($0) }
                menuControl(label: "Mode", width: 82) {
                    Picker("", selection: modeBinding) {
                        Text("Poly").tag(FB01MonoPolyMode.poly)
                        Text("Mono").tag(FB01MonoPolyMode.mono)
                    }
                    .labelsHidden()
                    .frame(width: 82)
                    .forestHoverHelp("Chooses whether this instrument plays polyphonically or as a monophonic line.")
                }
            }
        }
    }

    private var keyRangeControls: some View {
        OperatorControlGroup(title: "Key Range") {
            HStack(alignment: .top, spacing: 12) {
                instrumentKnob("Active Notes", value: instrument.noteCount, range: 0...8) { newValue in
                    guard canSetActiveNotes(newValue) else {
                        showAllNotesAssignedAlert()
                        return instrument
                    }
                    let updated = try instrument.settingNoteCount(newValue)
                    if instrument.noteCount == 0, newValue > 0, updated.outputLevel == 0 {
                        return try updated.settingOutputLevel(127)
                    }
                    return updated
                }
                instrumentKnob("Low Key", value: instrument.lowKeyLimit, range: 0...127) { try instrument.settingLowKeyLimit($0) }
                instrumentKnob("High Key", value: instrument.highKeyLimit, range: 0...127) { try instrument.settingHighKeyLimit($0) }
            }
        }
    }

    private var outputControls: some View {
        OperatorControlGroup(title: "Output") {
            HStack(alignment: .top, spacing: 12) {
                instrumentKnob("Level", value: displayedOutputLevel, range: 0...127) { try instrument.settingOutputLevel($0) }
                instrumentKnob(
                    "Stereo Pan",
                    value: centeredPanValue(forRawPan: instrument.pan),
                    range: -63...63,
                    displayText: stereoPanDisplayText
                ) { try instrument.settingPan(rawPanValue(forCenteredPan: $0)) }
                ParameterKnob(
                    label: "",
                    value: $pitchModulationDepth,
                    range: 0...127,
                    width: 82,
                    knobSize: 42,
                    helpText: "Sets pitch modulation depth for the selected instrument, usually heard as vibrato amount."
                )
                pmdAssignmentMenu {
                    Picker("", selection: pmdBinding) {
                        Text(FB01PMDControllerAssignment.notAssigned.displayName).tag(FB01PMDControllerAssignment.notAssigned)
                        Text(FB01PMDControllerAssignment.afterTouch.displayName).tag(FB01PMDControllerAssignment.afterTouch)
                        Text(FB01PMDControllerAssignment.modulationWheel.displayName).tag(FB01PMDControllerAssignment.modulationWheel)
                        Text(FB01PMDControllerAssignment.breathController.displayName).tag(FB01PMDControllerAssignment.breathController)
                        Text(FB01PMDControllerAssignment.footController.displayName).tag(FB01PMDControllerAssignment.footController)
                    }
                    .labelsHidden()
                    .frame(width: 150)
                    .forestHoverHelp("Chooses which performance controller drives pitch modulation depth for this instrument.")
                }
            }

            HStack(alignment: .top, spacing: 12) {
                Color.clear
                    .frame(width: 82)
                Color.clear
                    .frame(width: 82)
                RockerSwitch(label: "LFO Enabled", isOn: lfoEnabledBinding, width: 82, height: 58)
            }
        }
    }

    private var performanceControls: some View {
        OperatorControlGroup(title: "Performance") {
            HStack(alignment: .top, spacing: 12) {
                instrumentKnob("Detune", value: instrument.detune, range: -64...63) { try instrument.settingDetune($0) }
                instrumentKnob("Octave", value: instrument.octaveTranspose, range: -2...2) { try instrument.settingOctaveTranspose($0) }
                instrumentKnob("Portamento", value: instrument.portamentoTime, range: 0...127) { try instrument.settingPortamentoTime($0) }
                instrumentKnob("Bend Range", value: instrument.pitchBendRange, range: 0...12) { try instrument.settingPitchBendRange($0) }
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

    private func pmdAssignmentMenu<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack(alignment: .topLeading) {
            content()
                .frame(width: 150)
                .position(x: 75, y: 53)

            HStack(spacing: 6) {
                Rectangle()
                    .fill(Color.primary)
                    .opacity(0.85)
                    .frame(width: 41, height: 1)

                Text("PMD")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 34)

                Rectangle()
                    .fill(Color.primary)
                    .opacity(0.85)
                    .frame(width: 41, height: 1)
            }
            .frame(width: 128)
            .position(x: 11, y: 96)
        }
        .frame(width: 150, height: 110)
    }

    private func menuControl<Content: View>(
        label: String,
        width: CGFloat,
        pickerCenterY: CGFloat = 69,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack(alignment: .top) {
            content()
                .position(x: width / 2, y: pickerCenterY)

            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .frame(width: width, height: 28, alignment: .top)
                .position(x: width / 2, y: 96)
        }
        .frame(width: width, height: 110)
        .frame(width: width)
        .forestHoverHelp("\(label): choose an option from this menu.")
    }

    private var displayedOutputLevel: Int {
        instrument.noteCount == 0 ? 0 : instrument.outputLevel
    }

    private func canSetActiveNotes(_ newValue: Int) -> Bool {
        let proposedTotal = assignedNoteCount - instrument.noteCount + newValue
        return proposedTotal <= 8
    }

    private func instrumentKnob(
        _ label: String,
        value: Int,
        range: ClosedRange<Int>,
        displayText: ((Int) -> String)? = nil,
        update: @escaping (Int) throws -> FB01InstrumentConfiguration
    ) -> some View {
        ParameterKnob(
            label: label,
            value: Binding(
                get: { value },
                set: { newValue in
                    if let updated = try? update(newValue) {
                        updateInstrument(updated)
                    }
                }
            ),
            range: range,
            displayTextProvider: displayText
        )
    }

    private func centeredPanValue(forRawPan rawPan: Int) -> Int {
        min(max(rawPan - 64, -63), 63)
    }

    private func rawPanValue(forCenteredPan centeredPan: Int) -> Int {
        centeredPan <= -63 ? 0 : min(max(centeredPan + 64, 0), 127)
    }

    private func stereoPanDisplayText(_ centeredPan: Int) -> String {
        if centeredPan < 0 {
            return String(format: "L%02d", abs(centeredPan))
        }
        if centeredPan > 0 {
            return String(format: "R%02d", centeredPan)
        }
        return "C00"
    }

    private func readOnlyValue(_ label: String, value: String) -> some View {
        ReadOnlyLEDValue(label: label, value: value)
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
                    .forestHoverHelp("Save edited bank as a SysEx file")
                    .disabled(editedVoiceCount == 0)

                    Button {
                        document.resetAllVoiceEdits(sourceID: sourceID)
                    } label: {
                        Image(systemName: "arrow.uturn.backward.circle")
                    }
                    .forestHoverHelp("Reset all local voice edits in this bank")
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
                guard let source = document.sources.first(where: { $0.id == sourceID }),
                      let voiceBank = source.voiceBankData else {
                    return
                }
                document.applyVoiceSlotOperation(
                    operation,
                    sourceID: sourceID,
                    number: sourceNumber,
                    target: VoiceSlotTarget(
                        sourceID: sourceID,
                        sourceTitle: source.title,
                        bank: voiceBank.bank,
                        number: targetVoice.number
                    ),
                    voice: sourceVoice
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
    @State private var selectedOperatorIndex = FB01VoiceData.dataIndex(forOperatorNumber: 1)
    @State private var voiceCharacterType: VoiceCharacterType = .other
    @State private var performanceMacroValues = PerformanceMacro.neutralValues

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
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    if isEdited {
                        Button {
                            resetVoice()
                        } label: {
                            Label("Reset", systemImage: "arrow.uturn.backward")
                        }
                        .frame(width: 150)
                    }

                    if bankVoices.count > 1 {
                        Button {
                            copyVoice()
                        } label: {
                            Label("Copy To", systemImage: "doc.on.doc")
                        }
                        .frame(width: 150)

                        Button {
                            swapVoice()
                        } label: {
                            Label("Swap With", systemImage: "arrow.left.arrow.right")
                        }
                        .frame(width: 150)
                    }

                    Button {
                        exportVoice()
                    } label: {
                        Label("Export Voice", systemImage: "square.and.arrow.down")
                    }
                    .frame(width: 150)
                }

                HStack(spacing: 8) {
                    Button {
                        document.sendVoiceToInstrument(sourceID: sourceID, number: summary.number, voice: editableVoice, systemChannel: systemChannel)
                    } label: {
                        Label("Send", systemImage: "arrow.up.circle")
                    }
                    .disabled(document.isBusy)
                    .frame(width: 150)

                    Button {
                        document.sendAndConfirmVoiceToInstrument(sourceID: sourceID, number: summary.number, voice: editableVoice, systemChannel: systemChannel)
                    } label: {
                        Label("Send & Confirm", systemImage: "checkmark.seal")
                    }
                    .disabled(document.isBusy)
                    .frame(width: 150)

                    Button {
                        document.storeVoiceToDeviceSlot(sourceID: sourceID, number: summary.number, voice: editableVoice, systemChannel: systemChannel)
                    } label: {
                        Label("Store Slot", systemImage: "externaldrive.badge.plus")
                    }
                    .disabled(document.isBusy)
                    .frame(width: 150)

                    Button {
                        document.storeAndConfirmVoiceToDeviceSlot(sourceID: sourceID, number: summary.number, voice: editableVoice, systemChannel: systemChannel)
                    } label: {
                        Label("Store Slot & Confirm", systemImage: "externaldrive.badge.checkmark")
                    }
                    .disabled(document.isBusy)
                    .frame(width: 150)
                }
            }

            SummaryPanel(rows: [
                KeyValueRow("Feedback", "\(editableVoice.feedbackLevel)"),
            ])

            if document.voiceEditorParadigm == .consoleSections {
                VoiceEditorControls(
                    name: Binding(
                        get: { nameText },
                        set: { setName($0) }
                    ),
                    feedback: Binding(
                        get: { editableVoice.feedbackLevel },
                        set: { setFeedback($0) }
                    ),
                    userCode: Binding(
                        get: { editableVoice.userCode },
                        set: { setUserCode($0) }
                    ),
                    lfoSpeed: Binding(
                        get: { editableVoice.lfoSpeed },
                        set: { setLFOSpeed($0) }
                    ),
                    lfoWaveform: Binding(
                        get: { editableVoice.lfoWaveform },
                        set: { setLFOWaveform($0) }
                    ),
                    loadLFODataEnabled: Binding(
                        get: { editableVoice.loadLFODataEnabled },
                        set: { setLoadLFODataEnabled($0) }
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
                    )
                )

                AlgorithmSelectorView(selection: Binding(
                    get: { editableVoice.algorithm + 1 },
                    set: { setAlgorithm($0 - 1) }
                ))

                OperatorEditor(
                    operators: editableVoice.operators,
                    operatorEnabled: (0..<FB01VoiceData.operatorCount).map { index in
                        Binding(
                            get: { editableVoice.operatorEnabled[index] },
                            set: { setOperatorEnabled(index: index, enabled: $0) }
                        )
                    },
                    selectedOperatorIndex: $selectedOperatorIndex,
                    updateOperator: updateOperator
                )
            } else {
                FMRoutingPatchBayView(
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
                    userCode: Binding(
                        get: { editableVoice.userCode },
                        set: { setUserCode($0) }
                    ),
                    lfoSpeed: Binding(
                        get: { editableVoice.lfoSpeed },
                        set: { setLFOSpeed($0) }
                    ),
                    lfoWaveform: Binding(
                        get: { editableVoice.lfoWaveform },
                        set: { setLFOWaveform($0) }
                    ),
                    loadLFODataEnabled: Binding(
                        get: { editableVoice.loadLFODataEnabled },
                        set: { setLoadLFODataEnabled($0) }
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
                    voiceCharacterType: $voiceCharacterType,
                    macroValue: { macro in
                        Binding(
                            get: { performanceMacroValues[macro] ?? PerformanceMacro.neutralValue },
                            set: { setPerformanceMacro(macro, value: $0) }
                        )
                    },
                    operators: editableVoice.operators,
                    operatorEnabled: (0..<FB01VoiceData.operatorCount).map { index in
                        Binding(
                            get: { editableVoice.operatorEnabled[index] },
                            set: { setOperatorEnabled(index: index, enabled: $0) }
                        )
                    },
                    selectedOperatorIndex: $selectedOperatorIndex,
                    updateOperator: updateOperator
                )
            }

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
            performanceMacroValues = PerformanceMacro.neutralValues
            editError = nil
            exportError = nil
        }
        .onChange(of: editableVoice.name) { _, newName in
            nameText = newName
        }
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
        updateVoice { try $0.settingAlgorithmAndOperatorRoles(value) }
    }

    private func setFeedback(_ value: Int) {
        updateVoice { try $0.settingFeedbackLevel(value) }
    }

    private func setUserCode(_ value: Int) {
        updateVoice { try $0.settingUserCode(value) }
    }

    private func setLFOSpeed(_ value: Int) {
        updateVoice { try $0.settingLFOSpeed(value) }
    }

    private func setLoadLFODataEnabled(_ value: Bool) {
        updateVoice { try $0.settingLoadLFODataEnabled(value) }
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

    private func setPerformanceMacro(_ macro: PerformanceMacro, value proposedValue: Int) {
        let newValue = min(max(proposedValue, PerformanceMacro.range.lowerBound), PerformanceMacro.range.upperBound)
        let oldValue = performanceMacroValues[macro] ?? PerformanceMacro.neutralValue
        guard newValue != oldValue else { return }
        updateVoice { try macro.apply(previousValue: oldValue, newValue: newValue, characterType: voiceCharacterType, to: $0) }
        performanceMacroValues[macro] = newValue
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
        panel.allowedContentTypes = UTType.currentModuleVoiceFileTypes
        panel.directoryURL = document.preferredSaveDirectoryURL()
        panel.nameFieldStringValue = "voice-\(summary.number)-\(safeFileName(editableVoice.name)).\(EditorSynthModule.fileProfile.singleVoiceExtension)"

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
    @Binding var feedback: Int
    @Binding var userCode: Int
    @Binding var lfoSpeed: Int
    @Binding var lfoWaveform: Int
    @Binding var loadLFODataEnabled: Bool
    @Binding var lfoSyncEnabled: Bool
    @Binding var amplitudeModulationDepth: Int
    @Binding var pitchModulationDepth: Int
    @Binding var amplitudeModulationSensitivity: Int
    @Binding var pitchModulationSensitivity: Int
    @Binding var transpose: Int
    @Binding var leftOutputEnabled: Bool
    @Binding var rightOutputEnabled: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                        GridRow {
                            label("Name")
                            TextField("Name", text: $name)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 180)
                                .forestHoverHelp("Names the voice as it will appear in Forest documents and saved voice files.")
                        }
                    }

                    HStack(alignment: .top, spacing: 12) {
                        ParameterKnob(label: "Feedback", value: $feedback, range: 0...7)
                        ParameterKnob(label: "User Code", value: $userCode, range: 0...255)
                        ParameterKnob(label: "Transpose", value: $transpose, range: -128...127)
                    }
                }
                .padding(.top, 4)
            } label: {
                sectionTitle("Identity")
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        ParameterKnob(label: "LFO Speed", value: $lfoSpeed, range: 0...255)
                        ParameterKnob(label: "Amplitude MOD\nDepth", value: $amplitudeModulationDepth, range: 0...127)
                        ParameterKnob(label: "Pitch MOD\nDepth", value: $pitchModulationDepth, range: 0...127)
                        ParameterKnob(label: "Amplitude MOD\nSensitivity", value: $amplitudeModulationSensitivity, range: 0...3)
                        ParameterKnob(label: "Pitch MOD\nSensitivity", value: $pitchModulationSensitivity, range: 0...7)
                    }

                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                        GridRow {
                            label("Waveform")
                            WaveformPicker(selection: $lfoWaveform)
                                .frame(width: 342)
                        }

                        GridRow {
                            label("LFO Flags")
                            HStack(alignment: .top, spacing: 12) {
                                RockerSwitch(label: "Load LFO Data", isOn: $loadLFODataEnabled, width: 76, height: 58)
                                RockerSwitch(label: "LFO Sync", isOn: $lfoSyncEnabled, width: 62, height: 58)
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
                VStack(alignment: .leading, spacing: 8) {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                        GridRow {
                            label("Assignment")
                            HStack(alignment: .top, spacing: 12) {
                                RockerSwitch(label: "Left", isOn: $leftOutputEnabled, width: 58, height: 62)
                                RockerSwitch(label: "Right", isOn: $rightOutputEnabled, width: 58, height: 62)
                            }
                        }
                    }

                    Text("Stored with the voice; send or store the voice to hear assignment changes on the FB-01.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)
            } label: {
                sectionTitle("Stereo Output")
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

struct WaveformPicker: View {
    @Binding var selection: Int
    @Environment(\.colorScheme) private var colorScheme
    private let optionSize = CGSize(width: 84, height: 86)

    private let options: [(title: String, waveform: WaveformShape.Kind, tag: Int)] = [
        ("Sawtooth", .sawtooth, 0),
        ("Square", .square, 1),
        ("Triangle", .triangle, 2),
        ("Random", .random, 3)
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.tag) { option in
                waveformOption(option.title, waveform: option.waveform, tag: option.tag)
            }
        }
        .padding(3)
        .fixedSize()
        .background(Color.secondary.opacity(colorScheme == .light ? 0.16 : 0.12), in: RoundedRectangle(cornerRadius: 6))
        .contentShape(RoundedRectangle(cornerRadius: 6))
    }

    private func waveformOption(_ title: String, waveform: WaveformShape.Kind, tag: Int) -> some View {
        let isSelected = selection == tag
        return Button {
            selection = tag
        } label: {
            VStack(spacing: 3) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isSelected ? Color.black : Color.primary)
                WaveformShape(kind: waveform)
                    .stroke(isSelected ? Color(red: 0.0, green: 0.30, blue: 0.08) : Color.green, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                    .frame(width: 44, height: 16)
                    .padding(.bottom, 1)
            }
            .frame(width: optionSize.width, height: optionSize.height)
            .background(isSelected ? Color.green : Color.clear, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
        .frame(width: optionSize.width, height: optionSize.height)
        .contentShape(Rectangle())
        .forestHoverHelp(waveformHelp(title))
    }

    private func waveformHelp(_ title: String) -> String {
        switch title {
        case "Sawtooth":
            return "LFO sawtooth creates a repeating ramp for sharper, directional modulation."
        case "Square":
            return "LFO square alternates between two levels for pulsing or switching modulation."
        case "Triangle":
            return "LFO triangle moves smoothly up and down for classic vibrato or tremolo."
        case "Random":
            return "LFO random produces irregular movement for unstable or animated effects."
        default:
            return "Chooses the LFO waveform used for pitch or amplitude movement."
        }
    }
}

struct GreenNumberSegmentedPicker: View {
    @Binding var selection: Int
    var values: [Int]
    @Environment(\.colorScheme) private var colorScheme
    private let segmentSize = CGSize(width: 34, height: 32)

    var body: some View {
        HStack(spacing: 0) {
            ForEach(values, id: \.self) { value in
                Button {
                    selection = value
                } label: {
                    Text("\(value)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(selection == value ? Color.black : Color.primary)
                        .frame(width: segmentSize.width, height: segmentSize.height)
                        .background(selection == value ? Color.green : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                        .contentShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .frame(width: segmentSize.width, height: segmentSize.height)
                .contentShape(Rectangle())
                .forestHoverHelp("Chooses keyboard level scaling type \(value), changing how operator level responds across the keyboard.")
            }
        }
        .padding(3)
        .fixedSize()
        .background(Color.secondary.opacity(colorScheme == .light ? 0.16 : 0.12), in: RoundedRectangle(cornerRadius: 6))
        .contentShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct WaveformShape: Shape {
    enum Kind {
        case sawtooth
        case square
        case triangle
        case random
    }

    var kind: Kind

    func path(in rect: CGRect) -> Path {
        let inset = rect.insetBy(dx: 3, dy: 3)
        let top = inset.minY
        let mid = inset.midY
        let bottom = inset.maxY
        let left = inset.minX
        let right = inset.maxX
        let quarter = inset.width / 4
        let third = inset.width / 3
        var path = Path()

        switch kind {
        case .sawtooth:
            path.move(to: CGPoint(x: left, y: bottom))
            path.addLine(to: CGPoint(x: left + third, y: top))
            path.addLine(to: CGPoint(x: left + third, y: bottom))
            path.addLine(to: CGPoint(x: left + 2 * third, y: top))
            path.addLine(to: CGPoint(x: left + 2 * third, y: bottom))
            path.addLine(to: CGPoint(x: right, y: top))
        case .square:
            path.move(to: CGPoint(x: left, y: bottom))
            path.addLine(to: CGPoint(x: left, y: top))
            path.addLine(to: CGPoint(x: left + quarter, y: top))
            path.addLine(to: CGPoint(x: left + quarter, y: bottom))
            path.addLine(to: CGPoint(x: left + 2 * quarter, y: bottom))
            path.addLine(to: CGPoint(x: left + 2 * quarter, y: top))
            path.addLine(to: CGPoint(x: left + 3 * quarter, y: top))
            path.addLine(to: CGPoint(x: left + 3 * quarter, y: bottom))
            path.addLine(to: CGPoint(x: right, y: bottom))
        case .triangle:
            path.move(to: CGPoint(x: left, y: bottom))
            path.addLine(to: CGPoint(x: left + quarter, y: top))
            path.addLine(to: CGPoint(x: left + 2 * quarter, y: bottom))
            path.addLine(to: CGPoint(x: left + 3 * quarter, y: top))
            path.addLine(to: CGPoint(x: right, y: bottom))
        case .random:
            path.move(to: CGPoint(x: left, y: mid))
            path.addCurve(
                to: CGPoint(x: left + quarter, y: top + 1),
                control1: CGPoint(x: left + 5, y: bottom),
                control2: CGPoint(x: left + quarter - 8, y: top)
            )
            path.addCurve(
                to: CGPoint(x: left + 2 * quarter, y: bottom - 1),
                control1: CGPoint(x: left + quarter + 8, y: top + 2),
                control2: CGPoint(x: left + 2 * quarter - 8, y: bottom)
            )
            path.addCurve(
                to: CGPoint(x: left + 3 * quarter, y: mid - 2),
                control1: CGPoint(x: left + 2 * quarter + 8, y: bottom),
                control2: CGPoint(x: left + 3 * quarter - 8, y: top + 2)
            )
            path.addCurve(
                to: CGPoint(x: right, y: mid + 2),
                control1: CGPoint(x: left + 3 * quarter + 6, y: bottom - 2),
                control2: CGPoint(x: right - 7, y: top + 1)
            )
        }

        return path
    }
}

struct AlgorithmSelectorView: View {
    @Binding var selection: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Algorithms")

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(1...5, id: \.self) { algorithm in
                        algorithmButton(algorithm, cardWidth: 148, diagramWidth: 126)
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    ForEach(6...8, id: \.self) { algorithm in
                        algorithmButton(algorithm, cardWidth: 242, diagramWidth: 220)
                    }
                }
            }
        }
    }

    private func algorithmButton(_ algorithm: Int, cardWidth: CGFloat, diagramWidth: CGFloat) -> some View {
        Button {
            selection = algorithm
        } label: {
            VStack(spacing: 7) {
                AlgorithmDiagramView(algorithm: algorithm, isSelected: selection == algorithm)
                    .frame(width: diagramWidth, height: 156)

                HStack(spacing: 5) {
                    Image(systemName: selection == algorithm ? "largecircle.fill.circle" : "circle")
                        .imageScale(.small)
                    Text("\(algorithm)")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(selection == algorithm ? .green : .secondary)
            }
            .padding(9)
            .frame(width: cardWidth)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selection == algorithm ? Color.green.opacity(0.12) : Color.secondary.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(selection == algorithm ? Color.green : Color.secondary.opacity(0.18), lineWidth: selection == algorithm ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .forestHoverHelp("Algorithm \(algorithm): selects the FM operator routing, changing which operators shape harmonics and which are heard directly.")
    }
}

struct CompactAlgorithmSelectorView: View {
    @Binding var selection: Int

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(1...5, id: \.self) { algorithm in
                    algorithmButton(algorithm, cardWidth: 138, diagramWidth: 112, diagramHeight: 126)
                }
            }

            HStack(alignment: .top, spacing: 10) {
                ForEach(6...8, id: \.self) { algorithm in
                    algorithmButton(algorithm, cardWidth: 232, diagramWidth: 202, diagramHeight: 126)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func algorithmButton(_ algorithm: Int, cardWidth: CGFloat, diagramWidth: CGFloat, diagramHeight: CGFloat) -> some View {
        let isSelected = selection == algorithm
        return Button {
            selection = algorithm
        } label: {
            VStack(spacing: 7) {
                AlgorithmDiagramView(algorithm: algorithm, isSelected: isSelected)
                    .frame(width: diagramWidth, height: diagramHeight)

                HStack(spacing: 4) {
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                        .imageScale(.small)
                    Text("\(algorithm)")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(isSelected ? .green : .secondary)
            }
            .padding(10)
            .frame(width: cardWidth)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.green.opacity(0.12) : Color.secondary.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.green : Color.secondary.opacity(0.18), lineWidth: isSelected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .forestHoverHelp("Algorithm \(algorithm): selects the FM operator routing, changing which operators shape harmonics and which are heard directly.")
    }
}

struct AlgorithmDiagramView: View {
    var algorithm: Int
    var isSelected: Bool

    private struct Node: Identifiable {
        var id: String
        var operatorNumber: Int
        var isCarrier: Bool
        var hasFeedback: Bool
        var x: CGFloat
        var y: CGFloat
    }

    private struct Edge: Identifiable {
        var id: String
        var from: CGPoint
        var to: CGPoint
    }

    private struct SumNode: Identifiable {
        var id: String
        var x: CGFloat
        var y: CGFloat
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let nodes = Self.nodes(for: algorithm)
            let edges = Self.edges(for: algorithm)
            let sumNodes = Self.sumNodes(for: algorithm)
            let strokeColor = isSelected ? Color.green : Color.primary.opacity(0.82)
            let modulatorFill = isSelected ? Color.green.opacity(0.10) : Color(nsColor: .textBackgroundColor)
            let carrierFill = isSelected ? Color(red: 0.22, green: 0.98, blue: 0.34).opacity(0.42) : Color(red: 0.18, green: 0.92, blue: 0.26).opacity(0.34)

            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(nsColor: .controlBackgroundColor))

                ForEach(edges) { edge in
                    arrow(edge, in: size, color: strokeColor)
                }

                ForEach(sumNodes) { sum in
                    let center = point(CGPoint(x: sum.x, y: sum.y), in: size)
                    ZStack {
                        Circle()
                            .fill(modulatorFill)
                            .overlay(Circle().stroke(strokeColor.opacity(0.65), lineWidth: 1.2))
                        Text("+")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    .frame(width: 18, height: 18)
                    .position(center)
                }

                ForEach(nodes) { node in
                    operatorNode(
                        node,
                        size: size,
                        strokeColor: strokeColor,
                        fillColor: node.isCarrier ? carrierFill : modulatorFill
                    )
                }
            }
        }
    }

    private func operatorNode(_ node: Node, size: CGSize, strokeColor: Color, fillColor: Color) -> some View {
        let center = point(CGPoint(x: node.x, y: node.y), in: size)
        return Text("OP\(node.operatorNumber)\(node.hasFeedback ? "↻" : "")")
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .minimumScaleFactor(0.72)
            .lineLimit(1)
            .frame(width: nodeWidth(for: node), height: 24)
            .background(RoundedRectangle(cornerRadius: 4).fill(fillColor))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(strokeColor.opacity(0.7), lineWidth: 1.2))
            .position(center)
    }

    private func nodeWidth(for node: Node) -> CGFloat {
        node.hasFeedback ? 56 : 48
    }

    private func point(_ normalized: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: normalized.x * size.width, y: normalized.y * size.height)
    }

    private func arrow(_ edge: Edge, in size: CGSize, color: Color) -> some View {
        let start = point(edge.from, in: size)
        let end = point(edge.to, in: size)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let arrowLength: CGFloat = 7
        let arrowSpread: CGFloat = 0.55
        let left = CGPoint(
            x: end.x - arrowLength * cos(angle - arrowSpread),
            y: end.y - arrowLength * sin(angle - arrowSpread)
        )
        let right = CGPoint(
            x: end.x - arrowLength * cos(angle + arrowSpread),
            y: end.y - arrowLength * sin(angle + arrowSpread)
        )

        return Path { path in
            path.move(to: start)
            path.addLine(to: end)
            path.move(to: left)
            path.addLine(to: end)
            path.addLine(to: right)
        }
        .stroke(color.opacity(0.82), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
    }

    private static func nodes(for algorithm: Int) -> [Node] {
        switch algorithm {
        case 1:
            return [
                Node(id: "4", operatorNumber: 4, isCarrier: false, hasFeedback: true, x: 0.5, y: 0.22),
                Node(id: "3", operatorNumber: 3, isCarrier: false, hasFeedback: false, x: 0.5, y: 0.40),
                Node(id: "2", operatorNumber: 2, isCarrier: false, hasFeedback: false, x: 0.5, y: 0.58),
                Node(id: "1", operatorNumber: 1, isCarrier: true, hasFeedback: false, x: 0.5, y: 0.76),
            ]
        case 2:
            return [
                Node(id: "4", operatorNumber: 4, isCarrier: false, hasFeedback: true, x: 0.26, y: 0.24),
                Node(id: "3", operatorNumber: 3, isCarrier: false, hasFeedback: false, x: 0.74, y: 0.24),
                Node(id: "2", operatorNumber: 2, isCarrier: false, hasFeedback: false, x: 0.5, y: 0.50),
                Node(id: "1", operatorNumber: 1, isCarrier: true, hasFeedback: false, x: 0.5, y: 0.75),
            ]
        case 3:
            return [
                Node(id: "3", operatorNumber: 3, isCarrier: false, hasFeedback: false, x: 0.26, y: 0.23),
                Node(id: "2", operatorNumber: 2, isCarrier: false, hasFeedback: false, x: 0.26, y: 0.43),
                Node(id: "4", operatorNumber: 4, isCarrier: false, hasFeedback: true, x: 0.74, y: 0.43),
                Node(id: "1", operatorNumber: 1, isCarrier: true, hasFeedback: false, x: 0.5, y: 0.74),
            ]
        case 4:
            return [
                Node(id: "4", operatorNumber: 4, isCarrier: false, hasFeedback: true, x: 0.74, y: 0.23),
                Node(id: "2", operatorNumber: 2, isCarrier: false, hasFeedback: false, x: 0.26, y: 0.43),
                Node(id: "3", operatorNumber: 3, isCarrier: false, hasFeedback: false, x: 0.74, y: 0.43),
                Node(id: "1", operatorNumber: 1, isCarrier: true, hasFeedback: false, x: 0.5, y: 0.74),
            ]
        case 5:
            return [
                Node(id: "4", operatorNumber: 4, isCarrier: false, hasFeedback: true, x: 0.26, y: 0.33),
                Node(id: "3", operatorNumber: 3, isCarrier: true, hasFeedback: false, x: 0.26, y: 0.58),
                Node(id: "2", operatorNumber: 2, isCarrier: false, hasFeedback: false, x: 0.74, y: 0.33),
                Node(id: "1", operatorNumber: 1, isCarrier: true, hasFeedback: false, x: 0.74, y: 0.58),
            ]
        case 6:
            return [
                Node(id: "4", operatorNumber: 4, isCarrier: false, hasFeedback: true, x: 0.5, y: 0.30),
                Node(id: "1", operatorNumber: 1, isCarrier: true, hasFeedback: false, x: 0.16, y: 0.62),
                Node(id: "2", operatorNumber: 2, isCarrier: true, hasFeedback: false, x: 0.5, y: 0.62),
                Node(id: "3", operatorNumber: 3, isCarrier: true, hasFeedback: false, x: 0.84, y: 0.62),
            ]
        case 7:
            return [
                Node(id: "4", operatorNumber: 4, isCarrier: false, hasFeedback: true, x: 0.16, y: 0.33),
                Node(id: "3", operatorNumber: 3, isCarrier: true, hasFeedback: false, x: 0.16, y: 0.62),
                Node(id: "1", operatorNumber: 1, isCarrier: true, hasFeedback: false, x: 0.5, y: 0.62),
                Node(id: "2", operatorNumber: 2, isCarrier: true, hasFeedback: false, x: 0.84, y: 0.62),
            ]
        default:
            return [
                Node(id: "4", operatorNumber: 4, isCarrier: true, hasFeedback: false, x: 0.14, y: 0.58),
                Node(id: "3", operatorNumber: 3, isCarrier: true, hasFeedback: false, x: 0.38, y: 0.58),
                Node(id: "2", operatorNumber: 2, isCarrier: true, hasFeedback: false, x: 0.62, y: 0.58),
                Node(id: "1", operatorNumber: 1, isCarrier: true, hasFeedback: false, x: 0.86, y: 0.58),
            ]
        }
    }

    private static func edges(for algorithm: Int) -> [Edge] {
        switch algorithm {
        case 1:
            return [
                Edge(id: "4-3", from: CGPoint(x: 0.5, y: 0.30), to: CGPoint(x: 0.5, y: 0.34)),
                Edge(id: "3-2", from: CGPoint(x: 0.5, y: 0.48), to: CGPoint(x: 0.5, y: 0.52)),
                Edge(id: "2-1", from: CGPoint(x: 0.5, y: 0.66), to: CGPoint(x: 0.5, y: 0.70)),
            ]
        case 2:
            return [
                Edge(id: "4-sum", from: CGPoint(x: 0.26, y: 0.32), to: CGPoint(x: 0.43, y: 0.39)),
                Edge(id: "3-sum", from: CGPoint(x: 0.74, y: 0.32), to: CGPoint(x: 0.57, y: 0.39)),
                Edge(id: "sum-2", from: CGPoint(x: 0.5, y: 0.45), to: CGPoint(x: 0.5, y: 0.44)),
                Edge(id: "2-1", from: CGPoint(x: 0.5, y: 0.58), to: CGPoint(x: 0.5, y: 0.69)),
            ]
        case 3:
            return [
                Edge(id: "3-2", from: CGPoint(x: 0.26, y: 0.31), to: CGPoint(x: 0.26, y: 0.37)),
                Edge(id: "2-sum", from: CGPoint(x: 0.26, y: 0.51), to: CGPoint(x: 0.43, y: 0.58)),
                Edge(id: "4-sum", from: CGPoint(x: 0.74, y: 0.51), to: CGPoint(x: 0.57, y: 0.58)),
                Edge(id: "sum-1", from: CGPoint(x: 0.5, y: 0.64), to: CGPoint(x: 0.5, y: 0.68)),
            ]
        case 4:
            return [
                Edge(id: "4-3", from: CGPoint(x: 0.74, y: 0.31), to: CGPoint(x: 0.74, y: 0.37)),
                Edge(id: "2-sum", from: CGPoint(x: 0.26, y: 0.51), to: CGPoint(x: 0.43, y: 0.58)),
                Edge(id: "3-sum", from: CGPoint(x: 0.74, y: 0.51), to: CGPoint(x: 0.57, y: 0.58)),
                Edge(id: "sum-1", from: CGPoint(x: 0.5, y: 0.64), to: CGPoint(x: 0.5, y: 0.68)),
            ]
        case 5:
            return [
                Edge(id: "4-3", from: CGPoint(x: 0.26, y: 0.41), to: CGPoint(x: 0.26, y: 0.52)),
                Edge(id: "2-1", from: CGPoint(x: 0.74, y: 0.41), to: CGPoint(x: 0.74, y: 0.52)),
            ]
        case 6:
            return [
                Edge(id: "4-1", from: CGPoint(x: 0.38, y: 0.38), to: CGPoint(x: 0.16, y: 0.54)),
                Edge(id: "4-2", from: CGPoint(x: 0.5, y: 0.38), to: CGPoint(x: 0.5, y: 0.54)),
                Edge(id: "4-3", from: CGPoint(x: 0.62, y: 0.38), to: CGPoint(x: 0.84, y: 0.54)),
            ]
        case 7:
            return [
                Edge(id: "4-3", from: CGPoint(x: 0.16, y: 0.41), to: CGPoint(x: 0.16, y: 0.54)),
            ]
        default:
            return []
        }
    }

    private static func sumNodes(for algorithm: Int) -> [SumNode] {
        switch algorithm {
        case 2:
            return [SumNode(id: "sum", x: 0.5, y: 0.41)]
        case 3, 4:
            return [SumNode(id: "sum", x: 0.5, y: 0.60)]
        default:
            return []
        }
    }
}

struct OperatorEditor: View {
    var operators: [FB01VoiceOperatorData]
    var operatorEnabled: [Binding<Bool>]
    @Binding var selectedOperatorIndex: Int
    var updateOperator: (FB01VoiceOperatorData) -> Void

    private var selectedOperator: FB01VoiceOperatorData? {
        operators.first { $0.index == selectedOperatorIndex } ?? operators.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("Operators")

            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 8) {
                    ForEach(displayOrderedOperators, id: \.index) { op in
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
                            operatorEnabled: operatorEnabledBinding(for: selectedOperator.index),
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
            selectedOperatorIndex = displayOrderedOperators.first?.index ?? FB01VoiceData.dataIndex(forOperatorNumber: 1)
        }
    }

    private var displayOrderedOperators: [FB01VoiceOperatorData] {
        operators.sorted {
            FB01VoiceData.operatorNumber(forDataIndex: $0.index) < FB01VoiceData.operatorNumber(forDataIndex: $1.index)
        }
    }

    private func operatorEnabledBinding(for index: Int) -> Binding<Bool> {
        guard operatorEnabled.indices.contains(index) else {
            return .constant(true)
        }
        return operatorEnabled[index]
    }
}

struct OperatorSelectorButton: View {
    var operatorData: FB01VoiceOperatorData
    var isSelected: Bool
    var select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 7) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Operator \(FB01VoiceData.operatorNumber(forDataIndex: operatorData.index))")
                        .font(.body.weight(.semibold))
                    roleLabel
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
        .forestHoverHelp("Selects Operator \(FB01VoiceData.operatorNumber(forDataIndex: operatorData.index)) for editing in the console-style operator inspector.")
    }

    private var roleLabel: some View {
        Text(operatorData.carrier ? "Carrier" : "Modulator")
            .font(.caption.weight(.semibold))
            .foregroundStyle(operatorData.carrier ? Color.accentColor : .secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(operatorData.carrier ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.12))
            )
    }
}

struct OperatorInspector: View {
    var operatorData: FB01VoiceOperatorData
    @Binding var operatorEnabled: Bool
    var updateOperator: (FB01VoiceOperatorData) -> Void

    var body: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(minimum: 220), spacing: 12),
            GridItem(.flexible(minimum: 220), spacing: 12),
        ], alignment: .leading, spacing: 12) {
            OperatorControlGroup(title: "Level") {
                operatorRolePicker
                HStack(alignment: .top, spacing: 12) {
                    operatorLevelControl("Total Level", value: operatorData.totalLevel, range: 0...127) { try operatorData.settingTotalLevel($0) }
                    operatorKnob("Velocity to Total Level", value: operatorData.velocitySensitivityForTotalLevel, range: 0...7) { try operatorData.settingVelocitySensitivityForTotalLevel($0) }
                    operatorKnob("Total Level Adjust", value: operatorData.totalLevelAdjust, range: 0...15) { try operatorData.settingTotalLevelAdjust($0) }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                RockerSwitch(label: "Operator Enabled", isOn: $operatorEnabled)

                OperatorControlGroup(title: "Tuning") {
                    HStack(alignment: .top, spacing: 12) {
                        operatorKnob("OSC FRQ Multiplier", value: operatorData.multiple, range: 0...15) { try operatorData.settingMultiple($0) }
                        operatorKnob("Detune 1", value: operatorData.detune1, range: 0...7) { try operatorData.settingDetune1($0) }
                        operatorKnob("Detune 2", value: operatorData.detune2, range: 0...3) { try operatorData.settingDetune2($0) }
                    }
                }
            }

            OperatorControlGroup(title: "Envelope") {
                OperatorEnvelopeView(
                    operatorData: operatorData,
                    updateOperator: updateOperator
                )
                    .frame(height: 96)
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 82), spacing: 12),
                ], alignment: .leading, spacing: 10) {
                    operatorKnob("Attack Rate", value: operatorData.attackRate, range: 0...31) { try operatorData.settingAttackRate($0) }
                    operatorKnob("Velocity to Attack", value: operatorData.velocitySensitivityForAttackRate, range: 0...7) { try operatorData.settingVelocitySensitivityForAttackRate($0) }
                    operatorKnob("Decay 1 Rate", value: operatorData.decay1Rate, range: 0...15) { try operatorData.settingDecay1Rate($0) }
                    operatorKnob("Decay 2 Rate", value: operatorData.decay2Rate, range: 0...31) { try operatorData.settingDecay2Rate($0) }
                    operatorKnob("Sustain Level", value: operatorData.sustainLevel, range: 0...15) { try operatorData.settingSustainLevel($0) }
                    operatorKnob("Release Rate", value: operatorData.releaseRate, range: 0...15) { try operatorData.settingReleaseRate($0) }
                }
            }

            OperatorControlGroup(title: "Keyboard Scaling") {
                HStack(alignment: .top, spacing: 12) {
                    operatorKnob("Keyboard Level\nDepth", value: operatorData.keyboardLevelScalingDepth, range: 0...15) { try operatorData.settingKeyboardLevelScalingDepth($0) }
                    operatorKnob("Keyboard Rate\nScaling Depth", value: operatorData.keyboardRateScalingDepth, range: 0...7) { try operatorData.settingKeyboardRateScalingDepth($0) }
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("Keyboard Level\nScaling Type")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    GreenNumberSegmentedPicker(selection: keyboardLevelScalingTypeBinding, values: Array(0...3))
                        .frame(width: 148)
                }
            }
        }
    }

    private var operatorRolePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Role")
                .foregroundStyle(.secondary)
            Text(operatorData.carrier ? "Carrier" : "Modulator")
                .font(.body.weight(.semibold))
                .foregroundStyle(operatorData.carrier ? Color.accentColor : .primary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(operatorData.carrier ? Color.accentColor.opacity(0.14) : Color.secondary.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(operatorData.carrier ? Color.accentColor.opacity(0.55) : Color.secondary.opacity(0.20), lineWidth: 1)
                )
        }
    }

    private var keyboardLevelScalingTypeBinding: Binding<Int> {
        Binding(
            get: {
                (operatorData.keyboardLevelScalingTypeBit1 ? 2 : 0) +
                    (operatorData.keyboardLevelScalingTypeBit0 ? 1 : 0)
            },
            set: { value in
                if let updated = try? operatorData
                    .settingKeyboardLevelScalingTypeBit0(value & 0x01 == 0x01)
                    .settingKeyboardLevelScalingTypeBit1(value & 0x02 == 0x02) {
                    updateOperator(updated)
                }
            }
        )
    }

    private func operatorKnob(
        _ label: String,
        value: Int,
        range: ClosedRange<Int>,
        update: @escaping (Int) throws -> FB01VoiceOperatorData
    ) -> some View {
        ParameterKnob(
            label: label,
            value: Binding(
                get: { value },
                set: { newValue in
                    if let updated = try? update(newValue) {
                        updateOperator(updated)
                    }
                }
            ),
            range: range
        )
    }

    private func operatorLevelControl(
        _ label: String,
        value: Int,
        range: ClosedRange<Int>,
        update: @escaping (Int) throws -> FB01VoiceOperatorData
    ) -> some View {
        ParameterKnob(
            label: label,
            value: Binding(
                get: { value },
                set: { newValue in
                    if let updated = try? update(newValue) {
                        updateOperator(updated)
                    }
                }
            ),
            range: range
        )
    }

}

struct OperatorEnvelopeView: View {
    var operatorData: FB01VoiceOperatorData
    var updateOperator: (FB01VoiceOperatorData) -> Void
    @State private var activeHandle: EnvelopeHandle?
    @State private var draftOperatorData: FB01VoiceOperatorData?

    private var displayedOperatorData: FB01VoiceOperatorData {
        draftOperatorData ?? operatorData
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let geometry = envelopeGeometry(size: size, operatorData: displayedOperatorData)

            Canvas { context, _ in
                let rect = geometry.rect

                var grid = Path()
                grid.move(to: CGPoint(x: rect.minX, y: rect.minY))
                grid.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                grid.move(to: CGPoint(x: rect.minX, y: rect.midY))
                grid.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                grid.move(to: CGPoint(x: rect.minX, y: rect.maxY))
                grid.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                context.stroke(grid, with: .color(.secondary.opacity(0.18)), lineWidth: 1)

                var fill = Path()
                fill.move(to: geometry.start)
                fill.addLine(to: geometry.attack)
                fill.addLine(to: geometry.decay1)
                fill.addLine(to: geometry.sustain)
                fill.addLine(to: geometry.release)
                fill.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                fill.closeSubpath()
                context.fill(fill, with: .color(.green.opacity(0.14)))

                var line = Path()
                line.move(to: geometry.start)
                line.addLine(to: geometry.attack)
                line.addLine(to: geometry.decay1)
                line.addLine(to: geometry.sustain)
                line.addLine(to: geometry.release)
                context.stroke(line, with: .color(.green), lineWidth: 2)

                for handle in EnvelopeHandle.allCases {
                    let point = geometry.point(for: handle)
                    let marker = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
                    context.fill(Path(ellipseIn: marker), with: .color(handle == activeHandle ? .green : .primary))
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let handle = activeHandle ?? geometry.closestHandle(to: value.location)
                        activeHandle = handle
                        applyDrag(location: value.location, handle: handle, geometry: geometry)
                    }
                    .onEnded { _ in
                        if let draftOperatorData {
                            updateOperator(draftOperatorData)
                        }
                        draftOperatorData = nil
                        activeHandle = nil
                    }
            )
        }
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
        .forestHoverHelp("Drag envelope points to edit attack, decay, sustain, and release.")
    }

    private func segmentWidth(rate: Int, maxRate: Int, rect: CGRect) -> CGFloat {
        let normalized = CGFloat(min(max(rate, 0), maxRate)) / CGFloat(maxRate)
        return rect.width * (0.12 + (1 - normalized) * 0.22)
    }

    private func envelopeGeometry(size: CGSize, operatorData: FB01VoiceOperatorData) -> EnvelopeGeometry {
        let inset: CGFloat = 8
        let rect = CGRect(
            x: inset,
            y: inset,
            width: max(size.width - inset * 2, 1),
            height: max(size.height - inset * 2, 1)
        )
        let sustainY = rect.maxY - rect.height * CGFloat(operatorData.sustainLevel) / 15
        let attackWidth = segmentWidth(rate: operatorData.attackRate, maxRate: 31, rect: rect)
        let decay1Width = segmentWidth(rate: operatorData.decay1Rate, maxRate: 15, rect: rect)
        let decay2Width = segmentWidth(rate: operatorData.decay2Rate, maxRate: 31, rect: rect)
        let releaseWidth = segmentWidth(rate: operatorData.releaseRate, maxRate: 15, rect: rect)
        let scale = rect.width / max(attackWidth + decay1Width + decay2Width + releaseWidth, 1)

        let start = CGPoint(x: rect.minX, y: rect.maxY)
        let attack = CGPoint(x: rect.minX + attackWidth * scale, y: rect.minY)
        let decay1 = CGPoint(x: attack.x + decay1Width * scale, y: rect.minY + rect.height * 0.18)
        let sustain = CGPoint(x: decay1.x + decay2Width * scale, y: sustainY)
        let release = CGPoint(x: rect.maxX, y: rect.maxY)
        return EnvelopeGeometry(rect: rect, start: start, attack: attack, decay1: decay1, sustain: sustain, release: release)
    }

    private func applyDrag(location: CGPoint, handle: EnvelopeHandle, geometry: EnvelopeGeometry) {
        let rect = geometry.rect
        let clampedX = min(max(location.x, rect.minX), rect.maxX)
        let clampedY = min(max(location.y, rect.minY), rect.maxY)
        let relativeY = (clampedY - rect.minY) / max(rect.height, 1)

        do {
            let updated: FB01VoiceOperatorData
            let source = displayedOperatorData
            switch handle {
            case .attack:
                let segment = (clampedX - rect.minX) / max(rect.width, 1)
                updated = try source.settingAttackRate(rate(fromSegmentFraction: segment, maxRate: 31))
            case .decay1:
                let segment = (clampedX - geometry.attack.x) / max(rect.width, 1)
                updated = try source.settingDecay1Rate(rate(fromSegmentFraction: segment, maxRate: 15))
            case .sustain:
                let segment = (clampedX - geometry.decay1.x) / max(rect.width, 1)
                updated = try source
                    .settingDecay2Rate(rate(fromSegmentFraction: segment, maxRate: 31))
                    .settingSustainLevel(level(from: relativeY))
            case .release:
                let segment = (rect.maxX - clampedX) / max(rect.width, 1)
                updated = try source.settingReleaseRate(rate(fromSegmentFraction: segment, maxRate: 15))
            }
            draftOperatorData = updated
        } catch {
            return
        }
    }

    private func rate(fromSegmentFraction value: CGFloat, maxRate: Int) -> Int {
        let clamped = min(max(value, 0.02), 0.5)
        let normalized = 1 - ((clamped - 0.12) / 0.22)
        return min(max(Int((normalized * CGFloat(maxRate)).rounded()), 0), maxRate)
    }

    private func level(from value: CGFloat) -> Int {
        min(max(Int(((1 - min(max(value, 0), 1)) * 15).rounded()), 0), 15)
    }
}

private enum EnvelopeHandle: CaseIterable {
    case attack
    case decay1
    case sustain
    case release
}

private struct EnvelopeGeometry {
    var rect: CGRect
    var start: CGPoint
    var attack: CGPoint
    var decay1: CGPoint
    var sustain: CGPoint
    var release: CGPoint

    func point(for handle: EnvelopeHandle) -> CGPoint {
        switch handle {
        case .attack:
            attack
        case .decay1:
            decay1
        case .sustain:
            sustain
        case .release:
            release
        }
    }

    func closestHandle(to point: CGPoint) -> EnvelopeHandle {
        EnvelopeHandle.allCases.min { lhs, rhs in
            distanceSquared(from: point, to: self.point(for: lhs)) < distanceSquared(from: point, to: self.point(for: rhs))
        } ?? .sustain
    }

    private func distanceSquared(from a: CGPoint, to b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return dx * dx + dy * dy
    }
}

struct OperatorControlGroup<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var colorScheme

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
        .background(
            Color.secondary.opacity(colorScheme == .light ? 0.13 : 0.0),
            in: RoundedRectangle(cornerRadius: 8)
        )
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

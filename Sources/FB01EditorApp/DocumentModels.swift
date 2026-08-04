import AppKit
import Combine
import CoreMIDI
import FB01Editor
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum CustomControlsControllerProfile: String, CaseIterable, Identifiable {
    case oxygen25

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oxygen25:
            return "Oxygen 25"
        }
    }

    var controlLabels: [String] {
        switch self {
        case .oxygen25:
            return (1...8).map { "C\($0)" }
        }
    }

    var defaultControlChangeNumbers: [Int] {
        switch self {
        case .oxygen25:
            return [74, 71, 91, 93, 73, 72, 5, 84]
        }
    }
}

enum EditorDeviceSelection: String, CaseIterable, Identifiable {
    case fb01
    case dx100

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fb01:
            return "FB-01"
        case .dx100:
            return "DX100/27"
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
    @Published var selectedKeyboardSourceIndex = 0
    @Published var externalKeyboardEnabled = false
    @Published var externalKeyboardStatus = "Off"
    @Published var externalKeyboardVolume = 127
    @Published var externalKeyboardPortamento = 0
    @Published var selectedVoiceNumbers: [LibrarySource.ID: Int] = [:]
    @Published var sidebarSelection: SidebarSelection = .system
    @Published var systemChannel = 0
    @Published var systemMemoryProtectEnabled = false
    @Published var systemMasterOutputLevel = 127
    @Published var systemDeviceStatus = "Not requested"
    @Published var voiceEditorParadigm: VoiceEditorParadigm = .fmRoutingPatchBay
    @Published var hoverTextEnabled = true
    @Published var preCacheRAMVoiceBanksOnLaunch = true
    @Published var preCacheROMVoiceBanksOnLaunch = true
    @Published var preCacheConfigurationsOnLaunch = true
    @Published var preferredDeviceCount = 1
    @Published var devicePreferences: [FB01DevicePreference] = []
    @Published var keyboardVelocity = 100
    @Published var keyboardChannel = 0
    @Published var keyboardStartNote = 36
    @Published var customControlsControllerProfile: CustomControlsControllerProfile = .oxygen25
    @Published var customControlChangeNumbers: [Int] = CustomControlsControllerProfile.oxygen25.defaultControlChangeNumbers
    @Published var customControlLiveValues: [Int: Int] = [:]
    @Published var customControlLiveValuesByIndex: [Int?] = Array(repeating: nil, count: CustomControlsControllerProfile.oxygen25.defaultControlChangeNumbers.count)
    @Published var lastCustomControlMessage = "No controller input yet"
    @Published var externalKeyboardPressedNotes: Set<Int> = []
    @Published var liveKeyboardTitle = "Live Keyboard"
    @Published var liveKeyboardSubtitle = "MIDI notes only"
    @Published var recentLoadedVoiceFiles: [RecentEditorFile] = []
    @Published var recentFetchedVoices: [RecentVoiceFetch] = []
    @Published var recentLoadedConfigurationFiles: [RecentEditorFile] = []
    @Published var recentFetchedConfigurations: [RecentConfigurationFetch] = []
    @Published private var ramVoiceNameCache: [Int: [String]] = [:]
    @Published private var cachedVoiceBanks: [Int: FB01VoiceBankData] = [:]
    @Published private var cachedConfigurations: [Int: FB01ConfigurationData] = [:]
    @Published private var cachedCurrentConfiguration: FB01ConfigurationData?
    @Published private var cachedDX100VoiceBanks: [Int: DX100VoiceBankData] = [:]
    @Published var selectedEditorDevice: EditorDeviceSelection?
    @Published var deviceCacheStatus = "Not loaded"
    @Published private(set) var configurationSelectorRevision = 0

    private let generalMIDIStoreMaximumPasses = 5
    private var backgroundDeviceCacheTask: Task<Void, Never>?
    private var preparedKeyboardVoiceSignature: String?
    private var preparedKeyboardVoiceDate: Date?
    private var preparedAuditionBufferSignature: String?
    private var keyboardPreparationTask: Task<Void, Never>?
    private var externalKeyboardMonitor: FB01MIDILiveInputMonitor?
    private var externalKeyboardDocumentHandler: (([UInt8]) -> Bool)?
    private var liveKeyboardNoteOnHandler: ((Int) -> Void)?
    private var liveKeyboardNoteOffHandler: ((Int) -> Void)?
    private var externalVolumeTask: Task<Void, Never>?
    private var externalPortamentoTask: Task<Void, Never>?
    private var hasStartedLaunchDeviceCacheRefresh = false

    private enum DefaultsKey {
        static let sourceIndex = "FB01Editor.selectedMIDISourceIndex"
        static let sourceUniqueID = "FB01Editor.selectedMIDISourceUniqueID"
        static let destinationIndex = "FB01Editor.selectedMIDIDestinationIndex"
        static let destinationUniqueID = "FB01Editor.selectedMIDIDestinationUniqueID"
        static let keyboardSourceIndex = "FB01Editor.selectedKeyboardSourceIndex"
        static let keyboardSourceUniqueID = "FB01Editor.selectedKeyboardSourceUniqueID"
        static let externalKeyboardEnabled = "FB01Editor.externalKeyboardEnabled"
        static let lastLoadDirectory = "FB01Editor.lastLoadDirectory"
        static let lastSaveDirectory = "FB01Editor.lastSaveDirectory"
        static let systemChannel = "FB01Editor.systemChannel"
        static let keyboardChannel = "FB01Editor.keyboardChannel"
        static let keyboardVelocity = "FB01Editor.keyboardVelocity"
        static let keyboardStartNote = "FB01Editor.keyboardStartNote"
        static let externalKeyboardPortamento = "FB01Editor.externalKeyboardPortamento"
        static let customControlsControllerProfile = "FB01Editor.customControlsControllerProfile"
        static let customControlChangeNumbers = "FB01Editor.customControlChangeNumbers"
        static let voiceEditorParadigm = "FB01Editor.voiceEditorParadigm"
        static let hoverTextEnabled = "FB01Editor.hoverTextEnabled"
        static let preCacheRAMVoiceBanksOnLaunch = "FB01Editor.preCacheRAMVoiceBanksOnLaunch"
        static let preCacheROMVoiceBanksOnLaunch = "FB01Editor.preCacheROMVoiceBanksOnLaunch"
        static let preCacheConfigurationsOnLaunch = "FB01Editor.preCacheConfigurationsOnLaunch"
        static let preferredDeviceCount = "FB01Editor.preferredDeviceCount"
        static let recentLoadedVoiceFiles = "FB01Editor.recentLoadedVoiceFiles"
        static let recentFetchedVoices = "FB01Editor.recentFetchedVoices"
        static let recentLoadedConfigurationFiles = "FB01Editor.recentLoadedConfigurationFiles"
        static let recentFetchedConfigurations = "FB01Editor.recentFetchedConfigurations"

        static func deviceCommandChannel(_ index: Int) -> String {
            "FB01Editor.devicePreference.\(index).commandChannel"
        }

        static func deviceMemoryProtect(_ index: Int) -> String {
            "FB01Editor.devicePreference.\(index).memoryProtect"
        }
    }

    init() {
        ensureDefaultFileDirectory()
        selectedSourceIndex = UserDefaults.standard.integer(forKey: DefaultsKey.sourceIndex)
        selectedDestinationIndex = UserDefaults.standard.integer(forKey: DefaultsKey.destinationIndex)
        selectedKeyboardSourceIndex = UserDefaults.standard.integer(forKey: DefaultsKey.keyboardSourceIndex)
        externalKeyboardEnabled = UserDefaults.standard.bool(forKey: DefaultsKey.externalKeyboardEnabled)
        let savedSystemChannel = UserDefaults.standard.integer(forKey: DefaultsKey.systemChannel)
        systemChannel = (0...15).contains(savedSystemChannel) ? savedSystemChannel : 0
        let savedKeyboardChannel = UserDefaults.standard.integer(forKey: DefaultsKey.keyboardChannel)
        keyboardChannel = (0...15).contains(savedKeyboardChannel) ? savedKeyboardChannel : 0
        let savedKeyboardVelocity = UserDefaults.standard.integer(forKey: DefaultsKey.keyboardVelocity)
        keyboardVelocity = (1...127).contains(savedKeyboardVelocity) ? savedKeyboardVelocity : 100
        let savedKeyboardStartNote = UserDefaults.standard.integer(forKey: DefaultsKey.keyboardStartNote)
        keyboardStartNote = (0...67).contains(savedKeyboardStartNote) ? savedKeyboardStartNote : 36
        let savedExternalKeyboardPortamento = UserDefaults.standard.integer(forKey: DefaultsKey.externalKeyboardPortamento)
        externalKeyboardPortamento = (0...127).contains(savedExternalKeyboardPortamento) ? savedExternalKeyboardPortamento : 0
        if let rawProfile = UserDefaults.standard.string(forKey: DefaultsKey.customControlsControllerProfile),
           let profile = CustomControlsControllerProfile(rawValue: rawProfile) {
            customControlsControllerProfile = profile
        }
        if let savedControlChangeNumbers = UserDefaults.standard.array(forKey: DefaultsKey.customControlChangeNumbers) as? [Int],
           savedControlChangeNumbers.count == customControlsControllerProfile.controlLabels.count {
            customControlChangeNumbers = normalizedCustomControlChangeNumbers(savedControlChangeNumbers)
        } else {
            customControlChangeNumbers = customControlsControllerProfile.defaultControlChangeNumbers
        }
        customControlLiveValuesByIndex = Array(repeating: nil, count: customControlsControllerProfile.controlLabels.count)
        if let rawParadigm = UserDefaults.standard.string(forKey: DefaultsKey.voiceEditorParadigm),
           let paradigm = VoiceEditorParadigm(rawValue: rawParadigm) {
            voiceEditorParadigm = paradigm
        }
        hoverTextEnabled = UserDefaults.standard.object(forKey: DefaultsKey.hoverTextEnabled) == nil
            ? true
            : UserDefaults.standard.bool(forKey: DefaultsKey.hoverTextEnabled)
        preCacheRAMVoiceBanksOnLaunch = UserDefaults.standard.object(forKey: DefaultsKey.preCacheRAMVoiceBanksOnLaunch) == nil
            ? true
            : UserDefaults.standard.bool(forKey: DefaultsKey.preCacheRAMVoiceBanksOnLaunch)
        preCacheROMVoiceBanksOnLaunch = UserDefaults.standard.object(forKey: DefaultsKey.preCacheROMVoiceBanksOnLaunch) == nil
            ? true
            : UserDefaults.standard.bool(forKey: DefaultsKey.preCacheROMVoiceBanksOnLaunch)
        preCacheConfigurationsOnLaunch = UserDefaults.standard.object(forKey: DefaultsKey.preCacheConfigurationsOnLaunch) == nil
            ? false
            : UserDefaults.standard.bool(forKey: DefaultsKey.preCacheConfigurationsOnLaunch)
        recentLoadedVoiceFiles = recentEditorItems(forKey: DefaultsKey.recentLoadedVoiceFiles)
        recentFetchedVoices = recentEditorItems(forKey: DefaultsKey.recentFetchedVoices)
        recentLoadedConfigurationFiles = recentEditorItems(forKey: DefaultsKey.recentLoadedConfigurationFiles)
        recentFetchedConfigurations = recentEditorItems(forKey: DefaultsKey.recentFetchedConfigurations)
        let savedDeviceCount = UserDefaults.standard.integer(forKey: DefaultsKey.preferredDeviceCount)
        preferredDeviceCount = (1...4).contains(savedDeviceCount) ? savedDeviceCount : 1
        loadDevicePreferences()
        externalKeyboardVolume = systemMasterOutputLevel
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

    var canCreateLibraryConfigurationFromSelected: Bool {
        selectedSource?.editableConfigurationPayload != nil && !isBusy
    }

    var canDuplicateSelectedLibraryConfiguration: Bool {
        canCreateLibraryConfigurationFromSelected
    }

    var canSaveSelectedLibraryConfigurationAs: Bool {
        canCreateLibraryConfigurationFromSelected
    }

    var canUseSelectedVoiceLibrarianActions: Bool {
        selectedVoiceContext != nil
    }

    var canOpenSelectedVoiceAsDocument: Bool {
        selectedVoiceContext != nil && !isBusy
    }

    var canOpenSelectedConfigurationAsDocument: Bool {
        selectedSource?.editableConfigurationPayload != nil && !isBusy
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
        guard sidebarSelection == .source else {
            return "System"
        }
        return selectedSource?.title
    }

    func selectedVoiceDocumentPayload() -> (voice: FB01VoiceData, systemChannel: Int)? {
        guard let context = selectedVoiceContext else {
            return nil
        }
        return (context.voice, context.systemChannel)
    }

    func selectedConfigurationDocumentPayload() -> (configuration: FB01ConfigurationData, systemChannel: Int)? {
        guard let source = selectedSource,
              let configuration = source.editableConfigurationPayload else {
            return nil
        }
        return (configuration, source.configurationSystemChannel ?? systemChannel)
    }

    private var selectedVoiceContext: (sourceID: LibrarySource.ID, systemChannel: Int, number: Int, voice: FB01VoiceData, voices: [FB01VoiceSummary])? {
        guard let source = selectedSource,
              let voiceBank = source.voiceBankData else {
            return nil
        }

        let number = selectedVoiceNumbers[source.id] ?? voiceBank.voices.first?.number ?? 1
        guard let summary = voiceBank.voices.first(where: { $0.number == number }) ?? voiceBank.voices.first else {
            return nil
        }
        let voice = self.voice(sourceID: source.id, number: summary.number, fallback: summary.voice)
        return (source.id, source.voiceSystemChannel ?? 0, summary.number, voice, voiceBank.voices)
    }

    var hasKeyboardVoiceContext: Bool {
        selectedVoiceContext != nil
    }

    var liveKeyboardAuditionStatus: String {
        let titlePrefix = "Live Keyboard - "
        let voiceName: String?
        if liveKeyboardTitle.hasPrefix(titlePrefix) {
            voiceName = String(liveKeyboardTitle.dropFirst(titlePrefix.count))
        } else {
            voiceName = selectedVoiceDocumentPayload()?.voice.name
        }

        let source = liveKeyboardSubtitle.isEmpty ? "Unknown" : liveKeyboardSubtitle
        if let voiceName, !voiceName.isEmpty {
            return "Audition Voice: \(voiceName) | Source: \(source)"
        }
        return "Audition Voice: Not specified | Source: \(source)"
    }

    func isAuditionBufferPrepared(signature: String) -> Bool {
        preparedAuditionBufferSignature == signature
    }

    func markAuditionBufferPrepared(signature: String) {
        preparedAuditionBufferSignature = signature
    }

    func invalidateAuditionBufferPreparation() {
        preparedAuditionBufferSignature = nil
    }

    var editingStatusText: String {
        sources.contains { $0.isEdited } ? "Local Edits" : "Local Edit Only"
    }

    var canManageSource: Bool {
        sidebarSelection == .source && selectedSource != nil && !isBusy
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

    var selectedKeyboardSourceName: String {
        midiSources.first { $0.index == selectedKeyboardSourceIndex }?.displayName ?? "Input \(selectedKeyboardSourceIndex)"
    }

    var deviceCacheSummaryRows: [KeyValueRow] {
        guard let selectedEditorDevice else {
            return [
                KeyValueRow("Device", "None selected"),
                KeyValueRow("Status", "Waiting for device selection"),
                KeyValueRow("Coverage", "None"),
            ]
        }

        switch selectedEditorDevice {
        case .fb01:
            return fb01DeviceCacheSummaryRows
        case .dx100:
            return dx100DeviceCacheSummaryRows
        }
    }

    private var fb01DeviceCacheSummaryRows: [KeyValueRow] {
        let module = FB01ModuleServices.shared.module
        return [
            KeyValueRow("Device", EditorDeviceSelection.fb01.displayName),
            KeyValueRow("Status", deviceCacheStatus),
            KeyValueRow("Coverage", deviceCacheCoverageStatus),
            KeyValueRow("Voice Banks", "\(cachedVoiceBanks.count)/\(module.fullDeviceCacheScope.voiceBanks.count)"),
            KeyValueRow("Configurations", "\(cachedConfigurations.count)/\(module.fullDeviceCacheScope.configurationSlots?.upperBound ?? 0)"),
        ]
    }

    private var dx100DeviceCacheSummaryRows: [KeyValueRow] {
        let module = DX100ModuleServices.shared.module
        return [
            KeyValueRow("Device", EditorDeviceSelection.dx100.displayName),
            KeyValueRow("Status", deviceCacheStatus),
            KeyValueRow("Coverage", cachedDX100VoiceBanks.isEmpty ? "None" : "Partial"),
            KeyValueRow("Voice Banks", "\(cachedDX100VoiceBanks.count)/\(module.fullDeviceCacheScope.voiceBanks.count)"),
            KeyValueRow("Configurations", "Not supported"),
        ]
    }

    var deviceCacheCoverageStatus: String {
        let module = FB01ModuleServices.shared.module
        let cacheScope = module.fullDeviceCacheScope
        let hasAllVoiceBanks = cacheScope.voiceBanks.allSatisfy { cachedVoiceBanks[$0] != nil }
        let hasAllConfigurations = (cacheScope.includesCurrentConfiguration ? cachedCurrentConfiguration != nil : true)
            && (cacheScope.configurationSlots?.closedRange.allSatisfy { slot in
            cachedConfigurations[slot] != nil
        } ?? true)
        return hasAllVoiceBanks && hasAllConfigurations ? "Complete" : "Partial"
    }

    var selectedDeviceSupportsConfigurations: Bool {
        switch selectedEditorDevice {
        case .fb01:
            return FB01ModuleServices.shared.module.capabilities.supportsConfigurations
        case .dx100:
            return DX100ModuleServices.shared.module.capabilities.supportsConfigurations
        case nil:
            return false
        }
    }

    var selectedDeviceUsesFB01DocumentWorkflows: Bool {
        selectedEditorDevice == .fb01
    }

    var selectedDeviceHasConnectedVoiceDocumentCommands: Bool {
        switch selectedEditorDevice {
        case .fb01, .dx100:
            return true
        case nil:
            return false
        }
    }

    var selectedDeviceVoiceFetchCommandTitle: String {
        switch selectedEditorDevice {
        case .dx100:
            return "Fetch Current Voice from Device..."
        case .fb01, nil:
            return "Fetch Voice from Device..."
        }
    }

    var selectedDeviceVoiceFetchIntoDocumentTitle: String {
        switch selectedEditorDevice {
        case .dx100:
            return "Fetch Current Voice from Device into Current Document..."
        case .fb01, nil:
            return "Fetch Voice from Device into Current Document..."
        }
    }

    var selectedDeviceVoiceStoreCommandTitle: String {
        switch selectedEditorDevice {
        case .dx100:
            return "Send Voice to Current Buffer..."
        case .fb01, nil:
            return "Store Voice to Device Slot..."
        }
    }

    var selectedDeviceShowsConfigurationMenu: Bool {
        selectedEditorDevice != .dx100
    }

    var selectedDeviceVoiceBankSelectorLayout: SynthSelectorGridLayout {
        switch selectedEditorDevice {
        case .fb01, nil:
            return FB01ModuleServices.shared.module.voiceBankSelectorLayout
        case .dx100:
            return DX100ModuleServices.shared.module.voiceBankSelectorLayout
        }
    }

    var selectedDeviceConfigurationBankSelectorLayout: SynthSelectorGridLayout {
        switch selectedEditorDevice {
        case .fb01, .dx100, nil:
            return FB01ModuleServices.shared.module.configurationBankSelectorLayout
                ?? FB01ModuleServices.shared.module.voiceBankSelectorLayout
        }
    }

    func supportsSelectedDeviceCommand(_ kind: SynthModuleCommandKind) -> Bool {
        selectedDeviceCommandDescriptor(for: kind) != nil
    }

    func selectedDeviceCommandTitle(_ kind: SynthModuleCommandKind, fallback: String) -> String {
        selectedDeviceCommandDescriptor(for: kind)?.displayName ?? fallback
    }

    private func selectedDeviceCommandDescriptor(for kind: SynthModuleCommandKind) -> SynthModuleCommandDescriptor? {
        switch selectedEditorDevice {
        case .dx100 where [.showVoiceBank, .storeVoiceBank, .copyVoiceToSlot].contains(kind):
            return nil
        case .fb01:
            return FB01ModuleServices.shared.module.commandDescriptors.first { $0.kind == kind }
        case .dx100:
            return DX100ModuleServices.shared.module.commandDescriptors.first { $0.kind == kind }
        case nil:
            return nil
        }
    }

    var selectedDeviceVoiceBanks: [Int] {
        switch selectedEditorDevice {
        case .fb01:
            return FB01ModuleServices.shared.module.allVoiceBanks
        case .dx100:
            return [1]
        case nil:
            return []
        }
    }

    var selectedDeviceWritableVoiceBanks: [Int] {
        switch selectedEditorDevice {
        case .fb01:
            return FB01ModuleServices.shared.module.writableVoiceBanks
        case .dx100:
            return [1]
        case nil:
            return []
        }
    }

    func selectedDeviceVoiceBankTitle(_ bank: Int) -> String {
        switch selectedEditorDevice {
        case .dx100:
            return DX100ModuleServices.shared.module.voiceBankKind(displayBank: bank)?.displayName ?? "Bank \(bank)"
        case .fb01, nil:
            return "Bank \(bank)"
        }
    }

    func startLaunchDeviceCacheRefreshIfNeeded() {
        guard !hasStartedLaunchDeviceCacheRefresh else {
            return
        }
        hasStartedLaunchDeviceCacheRefresh = true
        selectedEditorDevice = .fb01
        refreshDeviceCache(
            reason: "Fetching FB-01 device cache",
            voiceBanksToFetch: voiceBanksToCacheOnLaunch(),
            fetchConfigurations: preCacheConfigurationsOnLaunch,
            showsDeviceNotFoundAlert: true
        )
    }

    func showDeviceSelectionDialog() {
        let alert = NSAlert()
        alert.messageText = "Select Device"
        alert.informativeText = "Choose the Yamaha FM device connected through the selected MIDI input and output."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "DX100/27")
        alert.addButton(withTitle: "FB-01")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            break
        case .alertSecondButtonReturn:
            selectDevice(.dx100)
        case .alertThirdButtonReturn:
            selectDevice(.fb01)
        default:
            break
        }
    }

    func selectDevice(_ device: EditorDeviceSelection) {
        guard !isBusy else {
            return
        }

        selectedEditorDevice = device
        switch device {
        case .fb01:
            refreshDeviceCache(
                reason: "Fetching FB-01 device cache",
                voiceBanksToFetch: FB01ModuleServices.shared.module.fullDeviceCacheScope.voiceBanks,
                fetchConfigurations: true,
                showsDeviceNotFoundAlert: true
            )
        case .dx100:
            refreshDX100DeviceCache()
        }
    }

    func refreshDeviceCache(
        reason: String = "Refreshing device cache",
        voiceBanksToFetch requestedVoiceBanks: [Int] = FB01ModuleServices.shared.module.fullDeviceCacheScope.voiceBanks,
        fetchConfigurations: Bool = true,
        showsProgressPanel: Bool = true,
        showsDeviceNotFoundAlert: Bool = false,
        completion: (() -> Void)? = nil
    ) {
        guard !isBusy else {
            return
        }

        let sourceIndex = selectedSourceIndex
        let destinationIndex = selectedDestinationIndex
        let systemChannel = systemChannel
        let sourceName = selectedSourceName
        let destinationName = selectedDestinationName
        let services = FB01ModuleServices.shared
        let voiceBanksToFetch = services.cacheService.normalizedVoiceBanks(requestedVoiceBanks)
        let cacheProgressText = cacheProgressText(
            voiceBanks: voiceBanksToFetch,
            fetchConfigurations: fetchConfigurations
        )
        guard !voiceBanksToFetch.isEmpty || fetchConfigurations else {
            deviceCacheStatus = "Launch cache disabled"
            statusMessage = "Launch device cache skipped by Preferences."
            errorMessage = nil
            completion?()
            return
        }
        isFetchingFromDevice = true
        deviceCacheStatus = "\(reason)..."
        statusMessage = "\(reason) from \(sourceName) -> \(destinationName)..."
        errorMessage = nil
        let progressPanel: EditorProgressPanel? = if showsProgressPanel {
            EditorProgressPanel(
                title: "Fetching FB-01 Device Cache",
                message: "The \(cacheProgressText.subject) \(cacheProgressText.verb) being cached. Please wait."
            )
        } else {
            nil
        }
        progressPanel?.show()

        Task {
            let cacheResult = await services.cacheService.fetch(
                voiceBanks: voiceBanksToFetch,
                fetchConfigurations: fetchConfigurations,
                sourceIndex: sourceIndex,
                destinationIndex: destinationIndex,
                systemChannel: systemChannel
            ) { event, completed, total in
                await MainActor.run {
                    let detail = services.cacheService.progressDetail(for: event)
                    self.statusMessage = "\(reason): \(detail)"
                    progressPanel?.update(
                        message: "The \(cacheProgressText.subject) \(cacheProgressText.verb) being cached. Please wait.\n\(detail)",
                        completed: completed,
                        total: total
                    )
                }
            }

            cachedVoiceBanks.merge(cacheResult.voiceBanks) { _, new in new }
            cachedConfigurations.merge(cacheResult.configurations) { _, new in new }
            if !cacheResult.configurations.isEmpty {
                configurationSelectorRevision += 1
            }
            if let currentConfiguration = cacheResult.currentConfiguration {
                cachedCurrentConfiguration = currentConfiguration
            }
            for (bank, bankData) in cacheResult.voiceBanks where services.module.isWritableVoiceBank(bank) {
                ramVoiceNameCache[bank] = bankData.voices.map { summary in
                    summary.voice.name.isEmpty ? "Untitled" : summary.voice.name
                }
            }

            deviceCacheStatus = cacheResult.failures.isEmpty
                ? "Loaded \(cacheResult.loadedCount) items"
                : "Loaded \(cacheResult.loadedCount) items; \(cacheResult.failures.count) failed"
            statusMessage = cacheResult.failures.isEmpty
                ? "Device cache loaded from \(sourceName) -> \(destinationName)."
                : "Device cache partially loaded from \(sourceName) -> \(destinationName); \(cacheResult.failures.count) item\(cacheResult.failures.count == 1 ? "" : "s") failed."
            errorMessage = nil
            progressPanel?.dismiss()
            isFetchingFromDevice = false
            if showsDeviceNotFoundAlert, cacheResult.loadedCount == 0 {
                showEditorError(title: "Device Not Found!", message: "")
            }
            completion?()
        }
    }

    func refreshDX100DeviceCache() {
        guard !isBusy else {
            return
        }

        let sourceIndex = selectedSourceIndex
        let destinationIndex = selectedDestinationIndex
        let sourceName = selectedSourceName
        let destinationName = selectedDestinationName
        let systemChannel = systemChannel
        isFetchingFromDevice = true
        deviceCacheStatus = "Fetching DX100/27 device cache..."
        statusMessage = "Fetching DX100/27 voice bank from \(sourceName) -> \(destinationName)..."
        errorMessage = nil
        let progressPanel = EditorProgressPanel(
            title: "Fetching DX100/27 Device Cache",
            message: "The DX100/27 voice bank is being cached. Please wait."
        )
        progressPanel.show()

        Task {
            do {
                progressPanel.update(
                    message: "The DX100/27 voice bank is being cached. Please wait.\nFetching 32-voice bulk data...",
                    completed: 0,
                    total: 1
                )
                let request = try DX100ModuleServices.shared.voiceService.voiceBankDumpRequest(channel: systemChannel)
                let responseMessages = try await Task.detached(priority: .userInitiated) {
                    try FB01MIDI.sendAndReceive(
                        [request],
                        sourceIndex: sourceIndex,
                        destinationIndex: destinationIndex,
                        timeout: 10,
                        maxMessages: 1,
                        delayBetweenMessages: 0
                    )
                }.value
                guard let response = responseMessages.first else {
                    throw FB01MIDIError.timedOut("DX100/27 voice bank")
                }
                let bank = try DX100ModuleServices.shared.voiceService.voiceBank(fromThirtyTwoVoiceBulkSysEx: response)
                cachedDX100VoiceBanks = [1: bank]
                deviceCacheStatus = "Loaded 1 item"
                statusMessage = "DX100/27 voice bank loaded from \(sourceName) -> \(destinationName)."
                errorMessage = nil
                progressPanel.update(
                    message: "The DX100/27 voice bank is being cached. Please wait.\nFinishing cache update...",
                    completed: 1,
                    total: 1
                )
            } catch {
                cachedDX100VoiceBanks = [:]
                deviceCacheStatus = "Not loaded"
                statusMessage = nil
                errorMessage = "DX100/27 device cache failed: \(error)"
                progressPanel.dismiss()
                isFetchingFromDevice = false
                showEditorError(title: "Device Not Found!", message: "")
                return
            }

            progressPanel.dismiss()
            isFetchingFromDevice = false
        }
    }

    func startBackgroundFullDeviceCacheRefreshIfNeeded(showsProgressPanel: Bool = false) {
        guard backgroundDeviceCacheTask == nil else {
            return
        }

        backgroundDeviceCacheTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            await MainActor.run {
                self?.refreshMissingFullDeviceCacheInBackground(showsProgressPanel: showsProgressPanel)
            }
        }
    }

    private func refreshMissingFullDeviceCacheInBackground(showsProgressPanel: Bool = false) {
        guard !isBusy else {
            backgroundDeviceCacheTask = nil
            startBackgroundFullDeviceCacheRefreshIfNeeded(showsProgressPanel: showsProgressPanel)
            return
        }

        let module = FB01ModuleServices.shared.module
        let cacheScope = module.fullDeviceCacheScope
        let missingVoiceBanks = cacheScope.voiceBanks.filter { cachedVoiceBanks[$0] == nil }
        let missingConfigurations = (cacheScope.includesCurrentConfiguration && cachedCurrentConfiguration == nil)
            || (cacheScope.configurationSlots?.closedRange.contains { slot in
            cachedConfigurations[slot] == nil
        } ?? false)

        guard !missingVoiceBanks.isEmpty || missingConfigurations else {
            backgroundDeviceCacheTask = nil
            deviceCacheStatus = "Complete"
            return
        }

        refreshDeviceCache(
            reason: "Fetching FB-01 contents in background",
            voiceBanksToFetch: missingVoiceBanks,
            fetchConfigurations: missingConfigurations,
            showsProgressPanel: showsProgressPanel
        ) { [weak self] in
            self?.backgroundDeviceCacheTask = nil
        }
    }

    private func voiceBanksToCacheOnLaunch() -> [Int] {
        var banks: [Int] = []
        let module = FB01ModuleServices.shared.module
        if preCacheRAMVoiceBanksOnLaunch {
            banks.append(contentsOf: module.writableVoiceBanks)
        }
        if preCacheROMVoiceBanksOnLaunch {
            banks.append(contentsOf: module.readOnlyVoiceBanks)
        }
        return banks
    }

    private func cacheProgressText(voiceBanks: [Int], fetchConfigurations: Bool) -> (subject: String, verb: String) {
        let text = FB01ModuleServices.shared.module.cacheProgressText(
            voiceBanks: voiceBanks,
            fetchConfigurations: fetchConfigurations
        )
        return (text.subject, text.verb)
    }

    nonisolated private static func fetchCachedConfiguration(
        slot: Int,
        sourceIndex: Int,
        destinationIndex: Int,
        systemChannel: Int
    ) async -> FB01ConfigurationData? {
        await Task.detached(priority: .userInitiated) {
            try? FB01ModuleServices.shared.configurationService.fetchStoredConfiguration(
                zeroBasedSlot: slot - 1,
                sourceIndex: sourceIndex,
                destinationIndex: destinationIndex,
                systemChannel: systemChannel,
                timeout: 15
            )
        }.value
    }

    nonisolated private static func fetchCachedCurrentConfiguration(
        sourceIndex: Int,
        destinationIndex: Int,
        systemChannel: Int
    ) async -> FB01ConfigurationData? {
        await Task.detached(priority: .userInitiated) {
            try? FB01ModuleServices.shared.configurationService.fetchCurrentConfiguration(
                sourceIndex: sourceIndex,
                destinationIndex: destinationIndex,
                systemChannel: systemChannel,
                timeout: 8
            )
        }.value
    }

    func prefetchConfigurationVoiceNames(
        for configuration: FB01ConfigurationData,
        configurationDocument: ConfigurationDocumentModel?,
        reason: String,
        progressPanel: EditorProgressPanel? = nil,
        fetchMissingBanks: Bool = true
    ) async -> String? {
        let referencedBanks = Array(Set(configuration.instruments.compactMap { instrument -> Int? in
            guard instrument.noteCount > 0,
                  FB01ModuleServices.shared.module.isWritableVoiceBank(instrument.voiceBank) else {
                return nil
            }
            return instrument.voiceBank
        })).sorted()
        let banks = referencedBanks.filter { cachedVoiceBanks[$0] == nil }

        guard !referencedBanks.isEmpty else {
            return nil
        }

        guard !banks.isEmpty else {
            return "Assigned RAM voice names are already cached."
        }

        guard fetchMissingBanks else {
            return "Assigned RAM voice names are not cached."
        }

        let sourceIndex = selectedSourceIndex
        let destinationIndex = selectedDestinationIndex
        let systemChannel = systemChannel
        let systemChannelName = "System channel \(systemChannel + 1)"
        let wasFetchingFromDevice = isFetchingFromDevice
        isFetchingFromDevice = true
        statusMessage = "\(reason). Fetching assigned RAM voice names from \(bankListTitle(banks)) on \(systemChannelName)..."
        configurationDocument?.statusMessage = "Fetching assigned RAM voice names from the FB-01..."

        var loadedBanks: [Int] = []
        for bank in banks {
            let detail = "Fetching Bank \(bank) voice names for assigned Instruments..."
            statusMessage = detail
            configurationDocument?.statusMessage = detail
            progressPanel?.update(message: "The configuration is being fetched. Please wait.\n\(detail)")

            do {
                let names = try await Task.detached(priority: .userInitiated) {
                    let bytes = try FB01MIDI.request(
                        .voiceBank(bank),
                        sourceIndex: sourceIndex,
                        destinationIndex: destinationIndex,
                        systemChannel: systemChannel,
                        timeout: voiceBankNameFetchTimeout
                    )
                    let bankData = try voiceBankData(from: bytes, expectedBankNumber: bank)
                    return bankData.voices.map { summary in
                        summary.voice.name.isEmpty ? "Untitled" : summary.voice.name
                    }
                }.value
                ramVoiceNameCache[bank] = names
                loadedBanks.append(bank)
            } catch {
                errorMessage = "Voice name fetch failed for Bank \(bank): \(error)"
            }
        }

        if !wasFetchingFromDevice {
            isFetchingFromDevice = false
        }

        guard !loadedBanks.isEmpty else {
            configurationDocument?.statusMessage = "\(reason). Voice names were not loaded."
            return "Voice names were not loaded."
        }

        let message = "Resolved assigned RAM voice names from \(bankListTitle(loadedBanks))."
        statusMessage = "\(reason). \(message)"
        configurationDocument?.statusMessage = "\(reason). \(message)"
        return message
    }

    private func bankListTitle(_ banks: [Int]) -> String {
        banks.map { "Bank \($0)" }.joined(separator: ", ")
    }

    func cachedVoiceFetchResult(
        source: VoiceDocumentFetchSource,
        systemChannel: Int,
        nameLookup: VoiceDocumentFetchNameLookup = .empty
    ) -> (voice: FB01VoiceData, systemChannel: Int, title: String)? {
        guard case let .storedSlot(location, voiceNumber) = source else {
            return nil
        }

        guard case let .bank(bank) = location,
              let voiceBank = cachedVoiceBanks[bank],
              voiceBank.voices.indices.contains(voiceNumber) else {
            return nil
        }

        return (
            voiceBank.voices[voiceNumber].voice,
            systemChannel,
            nameLookup.sourceTitle(location: location, voiceNumber: voiceNumber + 1)
        )
    }

    func cachedConfigurationFetchResult(options: ConfigurationFetchOptions) -> FB01ConfigurationData? {
        options.isCurrent ? cachedCurrentConfiguration : cachedConfigurations[options.slot + 1]
    }

    func ensureVoiceBankSelectorItems(bank: Int) async -> [VoiceBankSelectorItem] {
        let module = FB01ModuleServices.shared.module
        guard module.isValidVoiceBank(bank) else {
            return []
        }

        if module.isWritableVoiceBank(bank), cachedVoiceBanks[bank] == nil {
            await fetchSelectorCache(
                reason: "Fetching Voice Bank \(bank)",
                voiceBanks: [bank],
                fetchConfigurations: false
            )
        }

        if module.isWritableVoiceBank(bank), cachedVoiceBanks[bank] == nil {
            return []
        }

        return voiceBankSelectorItems(bank: bank)
    }

    func storeVoiceBankFromSelector(sourceBank: Int, targetBank: Int) {
        guard !isBusy else { return }
        let module = FB01ModuleServices.shared.module
        guard module.isValidVoiceBank(sourceBank),
              module.isWritableVoiceBank(targetBank) else {
            errorMessage = "Store Bank failed: invalid source or target bank."
            statusMessage = nil
            return
        }
        guard let sourceBankData = cachedVoiceBanks[sourceBank] else {
            errorMessage = "Store Bank failed: Voice Bank \(sourceBank) is not loaded. Show Voice Bank \(sourceBank) again before storing it."
            statusMessage = nil
            return
        }
        guard confirmStoreVoiceBank(sourceBank: sourceBank, targetBank: targetBank) else {
            return
        }

        let sourceIndex = selectedSourceIndex
        let destinationIndex = selectedDestinationIndex
        let systemChannel = systemChannel
        let destinationName = selectedDestinationName
        isFetchingFromDevice = true
        statusMessage = "Preparing to store Voice Bank \(sourceBank) in Bank \(targetBank)..."
        errorMessage = nil

        let progressPanel = EditorProgressPanel(
            title: "Store Voice Bank",
            message: "The voice bank is being stored. Please wait.\nPreparing Bank \(sourceBank) -> Bank \(targetBank)...",
            showsCancelButton: true
        )
        progressPanel.show()

        var operationTask: Task<Void, Never>?
        progressPanel.onCancel = {
            operationTask?.cancel()
        }

        operationTask = Task {
            do {
                let backupDirectory = try ensureDefaultBackupDirectory()
                let backupURL = backupDirectory.appendingPathComponent(
                    backupFileName(prefix: "bank-\(targetBank)-before-store-bank")
                )

                statusMessage = "Backing up Bank \(targetBank) before storing Voice Bank \(sourceBank)..."
                progressPanel.update(message: "The voice bank is being stored. Please wait.\nBacking up Bank \(targetBank)...")
                let originalBytes = try await Task.detached(priority: .userInitiated) {
                    try FB01MIDI.request(
                        .voiceBank(targetBank),
                        sourceIndex: sourceIndex,
                        destinationIndex: destinationIndex,
                        systemChannel: systemChannel,
                        timeout: 15
                    )
                }.value
                let originalArtifact = try FB01Artifact(sysexBytes: originalBytes)
                try await Task.detached(priority: .userInitiated) {
                    try originalArtifact.writeSysEx(to: backupURL)
                }.value
                try Task.checkCancellation()

                let readback = try await FB01ModuleServices.shared.voiceService.storeVoiceBank(
                    sourceBankData,
                    displayBank: targetBank,
                    sourceIndex: sourceIndex,
                    destinationIndex: destinationIndex,
                    systemChannel: systemChannel
                ) { [self] event in
                    await MainActor.run {
                        switch event {
                        case .turningProtectOff:
                            self.statusMessage = "Turning FB-01 Protect OFF before storing Bank \(targetBank)..."
                            progressPanel.update(message: "The voice bank is being stored. Please wait.\nTurning FB-01 Protect OFF...")
                        case .storingBank:
                            self.statusMessage = "Storing Voice Bank \(sourceBank) in Bank \(targetBank)..."
                            progressPanel.update(message: "The voice bank is being stored. Please wait.\nStoring Voice Bank \(sourceBank) in Bank \(targetBank)...")
                        case .verifyingBank:
                            self.statusMessage = "Fetching Bank \(targetBank) to verify store..."
                            progressPanel.update(message: "The voice bank is being stored. Please wait.\nFetching Bank \(targetBank) to verify store...")
                        }
                    }
                }

                cacheVoiceBank(readback, userBankNumber: targetBank)
                statusMessage = "FB-01 verified Voice Bank \(sourceBank) stored in Bank \(targetBank) on \(destinationName). Backup saved to \(backupURL.lastPathComponent)."
                errorMessage = nil
            } catch is CancellationError {
                statusMessage = nil
                errorMessage = "Store Bank canceled."
            } catch {
                statusMessage = nil
                errorMessage = "Store Bank failed: \(error)"
            }

            progressPanel.dismiss()
            isFetchingFromDevice = false
        }
    }

    private func confirmStoreVoiceBank(sourceBank: Int, targetBank: Int) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Store Voice Bank?"
        alert.informativeText = "This stores all 48 voices from Voice Bank \(sourceBank) into RAM Bank \(targetBank), overwriting the current contents of Bank \(targetBank) on the FB-01. A backup of Bank \(targetBank) will be saved before storing."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Store and Overwrite")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func ensureConfigurationSelectorItems() async -> [ConfigurationSelectorItem] {
        let module = FB01ModuleServices.shared.module
        let missingStoredConfigurations = module.writableConfigurationSlots.closedRange.contains { slot in
            cachedConfigurations[slot] == nil
        }
        if missingStoredConfigurations {
            await fetchSelectorCache(
                reason: "Fetching Configuration Bank",
                voiceBanks: [],
                fetchConfigurations: true
            )
        }

        return configurationSelectorItems()
    }

    func voiceBankSelectorItems(bank: Int) -> [VoiceBankSelectorItem] {
        let location = VoiceDocumentFetchLocation.bank(bank)
        return (0..<FB01VoiceBankData.voiceCount).map { index in
            let cachedVoices = cachedVoiceBanks[bank]?.voices ?? []
            let cachedName = cachedVoices.indices.contains(index) ? cachedVoices[index].voice.name : nil
            let lookupName = VoiceDocumentFetchNameLookup.empty.name(location: location, voiceNumber: index + 1)
            return VoiceBankSelectorItem(
                bank: bank,
                zeroBasedVoiceNumber: index,
                name: cachedName?.isEmpty == false ? cachedName! : (lookupName ?? "")
            )
        }
    }

    func configurationSelectorItems() -> [ConfigurationSelectorItem] {
        FB01ModuleServices.shared.module.allConfigurationSlots.closedRange.map { slot in
            let cachedName = cachedConfigurations[slot]?.name
            let factoryName = FB01FactoryConfigurationNames.name(slot: slot)
            return ConfigurationSelectorItem(
                slot: slot,
                name: cachedName?.isEmpty == false ? cachedName! : (factoryName ?? "")
            )
        }
    }

    func voiceNameLookupFromCache() -> VoiceDocumentFetchNameLookup {
        var namesByBank: [Int: [String]] = [:]
        for bank in FB01ModuleServices.shared.module.writableVoiceBanks {
            if let voiceBank = cachedVoiceBanks[bank] {
                namesByBank[bank] = voiceBank.voices.map { summary in
                    summary.voice.name.isEmpty ? "Untitled" : summary.voice.name
                }
            } else if let names = ramVoiceNameCache[bank] {
                namesByBank[bank] = names
            }
        }
        return VoiceDocumentFetchNameLookup(ramBankNames: namesByBank)
    }

    func configurationNameLookupFromCache() -> ConfigurationFetchNameLookup {
        let names = cachedConfigurations.reduce(into: [Int: String]()) { result, element in
            let (slot, configuration) = element
            result[slot] = configuration.name.isEmpty ? "Untitled" : configuration.name
        }
        return ConfigurationFetchNameLookup(storedNames: names)
    }

    private func fetchSelectorCache(
        reason: String,
        voiceBanks requestedVoiceBanks: [Int],
        fetchConfigurations: Bool
    ) async {
        guard !isBusy else {
            return
        }

        let sourceIndex = selectedSourceIndex
        let destinationIndex = selectedDestinationIndex
        let systemChannel = systemChannel
        let sourceName = selectedSourceName
        let destinationName = selectedDestinationName
        let services = FB01ModuleServices.shared
        let voiceBanks = services.cacheService.normalizedVoiceBanks(requestedVoiceBanks)
        let progressText = cacheProgressText(voiceBanks: voiceBanks, fetchConfigurations: fetchConfigurations)

        guard !voiceBanks.isEmpty || fetchConfigurations else {
            return
        }

        isFetchingFromDevice = true
        deviceCacheStatus = "\(reason)..."
        statusMessage = "\(reason) from \(sourceName) -> \(destinationName)..."
        errorMessage = nil
        let progressPanel = EditorProgressPanel(
            title: reason,
            message: "The \(progressText.subject) \(progressText.verb) being fetched. Please wait."
        )
        progressPanel.show()

        let cacheResult = await services.cacheService.fetch(
            voiceBanks: voiceBanks,
            fetchConfigurations: fetchConfigurations,
            sourceIndex: sourceIndex,
            destinationIndex: destinationIndex,
            systemChannel: systemChannel,
            profile: .selector
        ) { event, completed, total in
            await MainActor.run {
                let detail = services.cacheService.progressDetail(for: event)
                self.statusMessage = "\(reason): \(detail)"
                progressPanel.update(
                    message: "The \(progressText.subject) \(progressText.verb) being fetched. Please wait.\n\(detail)",
                    completed: completed,
                    total: total
                )
            }
        }

        cachedVoiceBanks.merge(cacheResult.voiceBanks) { _, new in new }
        cachedConfigurations.merge(cacheResult.configurations) { _, new in new }
        if !cacheResult.configurations.isEmpty {
            configurationSelectorRevision += 1
        }
        if let currentConfiguration = cacheResult.currentConfiguration {
            cachedCurrentConfiguration = currentConfiguration
        }
        for (bank, bankData) in cacheResult.voiceBanks where services.module.isWritableVoiceBank(bank) {
            ramVoiceNameCache[bank] = bankData.voices.map { summary in
                summary.voice.name.isEmpty ? "Untitled" : summary.voice.name
            }
        }

        deviceCacheStatus = cacheResult.failures.isEmpty
            ? "Loaded \(cacheResult.loadedCount) items"
            : "Loaded \(cacheResult.loadedCount) items; \(cacheResult.failures.count) failed"
        statusMessage = cacheResult.failures.isEmpty
            ? "\(reason) completed from \(sourceName) -> \(destinationName)."
            : "\(reason) partially completed from \(sourceName) -> \(destinationName); \(cacheResult.failures.count) item\(cacheResult.failures.count == 1 ? "" : "s") failed."
        errorMessage = cacheResult.failures.isEmpty
            ? nil
            : "\(reason) did not fetch: \(cacheResult.failures.joined(separator: ", "))."
        progressPanel.dismiss()
        isFetchingFromDevice = false
    }

    func cacheVoiceBank(_ voiceBank: FB01VoiceBankData, userBankNumber: Int) {
        cachedVoiceBanks[userBankNumber] = voiceBank
        if FB01ModuleServices.shared.module.isWritableVoiceBank(userBankNumber) {
            ramVoiceNameCache[userBankNumber] = voiceBank.voices.map { summary in
                summary.voice.name.isEmpty ? "Untitled" : summary.voice.name
            }
        }
        deviceCacheStatus = "Updated Voice Bank \(userBankNumber)"
    }

    func cacheConfiguration(_ configuration: FB01ConfigurationData, slot: Int) {
        cachedConfigurations[slot] = configuration
        configurationSelectorRevision += 1
        deviceCacheStatus = "Updated Configuration \(slot)"
    }

    func cacheCurrentConfiguration(_ configuration: FB01ConfigurationData) {
        cachedCurrentConfiguration = configuration
        deviceCacheStatus = "Updated current configuration"
    }

    func refreshMIDIEndpoints() {
        let previousDestinationIndex = selectedDestinationIndex
        midiSources = FB01MIDI.availableSources()
        midiDestinations = FB01MIDI.availableDestinations()

        if let storedSource = storedUniqueID(for: DefaultsKey.sourceUniqueID),
           let source = midiSources.first(where: { $0.uniqueID == storedSource }) {
            selectedSourceIndex = source.index
        } else if !midiSources.contains(where: { $0.index == selectedSourceIndex }) {
            selectedSourceIndex = midiSources.first?.index ?? 0
        }

        if let storedKeyboardSource = storedUniqueID(for: DefaultsKey.keyboardSourceUniqueID),
           let source = midiSources.first(where: { $0.uniqueID == storedKeyboardSource }) {
            selectedKeyboardSourceIndex = source.index
        } else if !midiSources.contains(where: { $0.index == selectedKeyboardSourceIndex }) {
            selectedKeyboardSourceIndex = midiSources.first?.index ?? 0
        }

        if let storedDestination = storedUniqueID(for: DefaultsKey.destinationUniqueID),
           let destination = midiDestinations.first(where: { $0.uniqueID == storedDestination }) {
            selectedDestinationIndex = destination.index
        } else if !midiDestinations.contains(where: { $0.index == selectedDestinationIndex }) {
            selectedDestinationIndex = midiDestinations.first?.index ?? 0
        }

        if selectedDestinationIndex != previousDestinationIndex {
            invalidateKeyboardPreparation()
        }
        persistSelectedEndpoints()
        restartExternalKeyboardMonitor()
    }

    func selectSource(_ source: FB01MIDIEndpoint) {
        selectedSourceIndex = source.index
        persistSelectedEndpoints()
    }

    func selectDestination(_ destination: FB01MIDIEndpoint) {
        selectedDestinationIndex = destination.index
        invalidateKeyboardPreparation()
        persistSelectedEndpoints()
    }

    func selectKeyboardSource(_ source: FB01MIDIEndpoint) {
        selectedKeyboardSourceIndex = source.index
        persistSelectedEndpoints()
        restartExternalKeyboardMonitor()
    }

    func setExternalKeyboardEnabled(_ enabled: Bool) {
        externalKeyboardEnabled = enabled
        if !enabled {
            externalKeyboardPressedNotes.removeAll()
        }
        UserDefaults.standard.set(enabled, forKey: DefaultsKey.externalKeyboardEnabled)
        restartExternalKeyboardMonitor()
    }

    func selectSystemPanel() {
        sidebarSelection = .system
    }

    func setSystemChannel(_ channel: Int) {
        systemChannel = min(max(channel, 0), 15)
        invalidateKeyboardPreparation()
        UserDefaults.standard.set(systemChannel, forKey: DefaultsKey.systemChannel)
    }

    func setKeyboardChannel(_ channel: Int) {
        keyboardChannel = min(max(channel, 0), 15)
        invalidateKeyboardPreparation()
        UserDefaults.standard.set(keyboardChannel, forKey: DefaultsKey.keyboardChannel)
    }

    func setKeyboardVelocity(_ velocity: Int) {
        keyboardVelocity = min(max(velocity, 1), 127)
        UserDefaults.standard.set(keyboardVelocity, forKey: DefaultsKey.keyboardVelocity)
    }

    func setExternalKeyboardVolume(_ volume: Int) {
        applyExternalKeyboardVolume(volume)
    }

    func setExternalKeyboardPortamento(_ portamento: Int) {
        applyExternalKeyboardPortamento(portamento)
    }

    func setKeyboardStartNote(_ note: Int) {
        keyboardStartNote = min(max(note, 0), 67)
        UserDefaults.standard.set(keyboardStartNote, forKey: DefaultsKey.keyboardStartNote)
    }

    func setCustomControlsControllerProfile(_ profile: CustomControlsControllerProfile) {
        guard profile != customControlsControllerProfile else { return }
        customControlsControllerProfile = profile
        customControlChangeNumbers = profile.defaultControlChangeNumbers
        customControlLiveValuesByIndex = profile.defaultControlChangeNumbers.map { customControlLiveValues[$0] }
        UserDefaults.standard.set(profile.rawValue, forKey: DefaultsKey.customControlsControllerProfile)
        UserDefaults.standard.set(customControlChangeNumbers, forKey: DefaultsKey.customControlChangeNumbers)
    }

    func setCustomControlChangeNumber(_ controller: Int, at index: Int) {
        guard customControlChangeNumbers.indices.contains(index) else { return }
        let boundedController = min(max(controller, 0), 127)
        var controlChangeNumbers = customControlChangeNumbers
        let previousController = controlChangeNumbers[index]
        if let duplicateIndex = controlChangeNumbers.firstIndex(of: boundedController),
           duplicateIndex != index {
            controlChangeNumbers[duplicateIndex] = previousController
        }
        controlChangeNumbers[index] = boundedController
        customControlChangeNumbers = controlChangeNumbers
        customControlLiveValuesByIndex = controlChangeNumbers.map { customControlLiveValues[$0] }
        UserDefaults.standard.set(customControlChangeNumbers, forKey: DefaultsKey.customControlChangeNumbers)
    }

    func resetCustomControlChangeNumbersToDefaults() {
        customControlChangeNumbers = customControlsControllerProfile.defaultControlChangeNumbers
        customControlLiveValuesByIndex = customControlChangeNumbers.map { customControlLiveValues[$0] }
        UserDefaults.standard.set(customControlChangeNumbers, forKey: DefaultsKey.customControlChangeNumbers)
    }

    func liveValueForCustomControl(at index: Int) -> Int? {
        guard customControlLiveValuesByIndex.indices.contains(index) else { return nil }
        return customControlLiveValuesByIndex[index]
    }

    func noteCustomControlMessage(_ message: [UInt8]) {
        guard message.count == 3,
              let status = message.first,
              status & 0xF0 == 0xB0 else {
            return
        }
        let controller = Int(message[1])
        let value = Int(message[2])
        lastCustomControlMessage = "Last incoming: \(MIDIControlChangeLabel.title(for: controller)) = \(value)"
        var liveValues = customControlLiveValues
        liveValues[controller] = value
        customControlLiveValues = liveValues

        var indexedValues = customControlLiveValuesByIndex
        if indexedValues.count != customControlsControllerProfile.controlLabels.count {
            indexedValues = Array(repeating: nil, count: customControlsControllerProfile.controlLabels.count)
        }
        for index in customControlChangeNumbers.indices where customControlChangeNumbers[index] == controller {
            if indexedValues.indices.contains(index) {
                indexedValues[index] = value
            }
        }
        customControlLiveValuesByIndex = indexedValues
    }

    private func normalizedCustomControlChangeNumbers(_ numbers: [Int]) -> [Int] {
        let bounded = numbers.map { min(max($0, 0), 127) }
        guard bounded.count == customControlsControllerProfile.controlLabels.count,
              Set(bounded).count == bounded.count else {
            return customControlsControllerProfile.defaultControlChangeNumbers
        }
        return bounded
    }

    private func customizedControlLabel(for controller: Int) -> String? {
        guard let index = customControlChangeNumbers.firstIndex(of: controller),
              customControlsControllerProfile.controlLabels.indices.contains(index) else {
            return nil
        }
        return customControlsControllerProfile.controlLabels[index]
    }

    func setVoiceEditorParadigm(_ paradigm: VoiceEditorParadigm) {
        voiceEditorParadigm = paradigm
        UserDefaults.standard.set(paradigm.rawValue, forKey: DefaultsKey.voiceEditorParadigm)
    }

    func setPreCacheRAMVoiceBanksOnLaunch(_ enabled: Bool) {
        preCacheRAMVoiceBanksOnLaunch = enabled
        UserDefaults.standard.set(enabled, forKey: DefaultsKey.preCacheRAMVoiceBanksOnLaunch)
    }

    func setPreCacheROMVoiceBanksOnLaunch(_ enabled: Bool) {
        preCacheROMVoiceBanksOnLaunch = enabled
        UserDefaults.standard.set(enabled, forKey: DefaultsKey.preCacheROMVoiceBanksOnLaunch)
    }

    func setHoverTextEnabled(_ enabled: Bool) {
        hoverTextEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: DefaultsKey.hoverTextEnabled)
    }

    func setPreCacheConfigurationsOnLaunch(_ enabled: Bool) {
        preCacheConfigurationsOnLaunch = enabled
        UserDefaults.standard.set(enabled, forKey: DefaultsKey.preCacheConfigurationsOnLaunch)
    }

    func rememberRecentLoadedVoiceFile(_ url: URL) {
        recentLoadedVoiceFiles = addingRecentEditorItem(RecentEditorFile(path: url.path), to: recentLoadedVoiceFiles)
        saveRecentEditorItems(recentLoadedVoiceFiles, forKey: DefaultsKey.recentLoadedVoiceFiles)
    }

    func rememberRecentLoadedConfigurationFile(_ url: URL) {
        recentLoadedConfigurationFiles = addingRecentEditorItem(RecentEditorFile(path: url.path), to: recentLoadedConfigurationFiles)
        saveRecentEditorItems(recentLoadedConfigurationFiles, forKey: DefaultsKey.recentLoadedConfigurationFiles)
    }

    func rememberRecentFetchedVoice(_ source: VoiceDocumentFetchSource, title: String) {
        let item: RecentVoiceFetch
        switch source {
        case .instrument(let instrument):
            item = RecentVoiceFetch(kind: .instrument, instrument: instrument, bank: nil, voiceNumber: nil, title: title)
        case .storedSlot(.bank(let bank), let voiceNumber):
            item = RecentVoiceFetch(kind: .bank, instrument: nil, bank: bank, voiceNumber: voiceNumber, title: title)
        case .storedSlot(.voiceRAM1, let voiceNumber):
            item = RecentVoiceFetch(kind: .voiceRAM1, instrument: nil, bank: nil, voiceNumber: voiceNumber, title: title)
        }
        recentFetchedVoices = addingRecentEditorItem(item, to: recentFetchedVoices)
        saveRecentEditorItems(recentFetchedVoices, forKey: DefaultsKey.recentFetchedVoices)
    }

    func rememberRecentFetchedConfiguration(_ options: ConfigurationFetchOptions, title: String) {
        let item = RecentConfigurationFetch(isCurrent: options.isCurrent, slot: options.slot, title: title)
        recentFetchedConfigurations = addingRecentEditorItem(item, to: recentFetchedConfigurations)
        saveRecentEditorItems(recentFetchedConfigurations, forKey: DefaultsKey.recentFetchedConfigurations)
    }

    func setPreferredDeviceCount(_ count: Int) {
        preferredDeviceCount = min(max(count, 1), 4)
        UserDefaults.standard.set(preferredDeviceCount, forKey: DefaultsKey.preferredDeviceCount)
        loadDevicePreferences()
    }

    func setDeviceCommandChannel(index: Int, channel: Int) {
        guard devicePreferences.indices.contains(index) else { return }
        let bounded = min(max(channel, 0), 15)
        devicePreferences[index].commandChannel = bounded
        UserDefaults.standard.set(bounded, forKey: DefaultsKey.deviceCommandChannel(index))
    }

    func setDeviceMemoryProtect(index: Int, enabled: Bool) {
        guard devicePreferences.indices.contains(index) else { return }
        devicePreferences[index].memoryProtectEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: DefaultsKey.deviceMemoryProtect(index))
    }

    private func loadDevicePreferences() {
        devicePreferences = (0..<preferredDeviceCount).map { index in
            let channel = UserDefaults.standard.object(forKey: DefaultsKey.deviceCommandChannel(index)) == nil
                ? min(index, 15)
                : UserDefaults.standard.integer(forKey: DefaultsKey.deviceCommandChannel(index))
            let memoryProtect = UserDefaults.standard.bool(forKey: DefaultsKey.deviceMemoryProtect(index))
            return FB01DevicePreference(
                index: index,
                commandChannel: min(max(channel, 0), 15),
                memoryProtectEnabled: memoryProtect
            )
        }
    }

    func setMemoryProtect(_ enabled: Bool) {
        systemMemoryProtectEnabled = enabled
        do {
            sendMIDI(
                [try systemMemoryProtectMessageBytes(enabled: enabled)],
                delayBetweenMessages: 0,
                statusMessage: "Set FB-01 Protect \(enabled ? "ON" : "OFF") on \(selectedDestinationName)."
            )
        } catch {
            errorMessage = "Set Protect failed: \(error)"
            statusMessage = nil
        }
    }

    func setMasterOutputLevel(_ level: Int) {
        let bounded = min(max(level, 0), 127)
        systemMasterOutputLevel = bounded
        do {
            sendMIDI(
                [try systemMasterOutputMessageBytes(level: bounded)],
                delayBetweenMessages: 0,
                statusMessage: "Set FB-01 master output level to \(bounded) on \(selectedDestinationName)."
            )
        } catch {
            errorMessage = "Set master output failed: \(error)"
            statusMessage = nil
        }
    }

    func requestUnitID() {
        guard !isBusy else { return }

        let sourceIndex = selectedSourceIndex
        let destinationIndex = selectedDestinationIndex
        let sourceName = selectedSourceName
        let destinationName = selectedDestinationName
        let systemChannel = systemChannel
        isFetchingFromDevice = true
        statusMessage = "Requesting FB-01 Unit ID..."
        errorMessage = nil

        Task {
            do {
                let bytes = try await Task.detached(priority: .userInitiated) {
                    try FB01MIDI.request(
                        .unitID,
                        sourceIndex: sourceIndex,
                        destinationIndex: destinationIndex,
                        systemChannel: systemChannel,
                        timeout: 8
                    )
                }.value
                let artifact = try FB01Artifact(sysexBytes: bytes)
                let detail = try Self.deviceStatusDescription(from: artifact)
                systemDeviceStatus = detail
                statusMessage = "Received FB-01 Unit ID from \(sourceName) after requesting \(destinationName)."
                errorMessage = nil
            } catch {
                systemDeviceStatus = "Request failed"
                errorMessage = "Unit ID request failed: \(error)"
                statusMessage = nil
            }

            isFetchingFromDevice = false
        }
    }

    private static func deviceStatusDescription(from artifact: FB01Artifact) throws -> String {
        for message in artifact.messages {
            switch message {
            case let .unitIDDump(systemChannel, packet):
                let payload = packet.payload.map { String(format: "%02X", $0) }.joined(separator: " ")
                return "Unit ID, System \(systemChannel + 1): \(payload)"
            case let .deviceStatus(code):
                return String(format: "Device Status: 0x%02X", code)
            default:
                continue
            }
        }
        let bytes = try artifact.sysexBytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        return "Raw response: \(bytes)"
    }

    func systemMemoryProtectMessageBytes(enabled: Bool) throws -> [UInt8] {
        let command = FB01SysExMessage.command(.setMemoryProtect(
            systemChannel: systemChannel,
            enabled ? .on : .off
        ))
        return try command.bytes
    }

    func systemMasterOutputMessageBytes(level: Int) throws -> [UInt8] {
        let bounded = min(max(level, 0), 127)
        let command = FB01SysExMessage.command(.setMasterOutputLevel(
            systemChannel: systemChannel,
            level: UInt8(bounded)
        ))
        return try command.bytes
    }

    func liveKeyboardPortamentoMessageBytes(value: Int, systemChannel: Int? = nil) throws -> [UInt8] {
        let bounded = UInt8(min(max(value, 0), 127))
        let command = FB01SysExMessage.command(.instrumentParameterChange(
            systemChannel: systemChannel ?? self.systemChannel,
            instrument: 0,
            parameter: FB01InstrumentParameter.portamentoTime,
            value: .oneByte(bounded)
        ))
        return try command.bytes
    }

    func openSysEx() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = UTType.currentModuleReadableFileTypes
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
        let progressPanel = EditorProgressPanel(
            title: "Fetch FB-01 Banks",
            message: "The voices are being fetched. Please wait.\nRequesting current configuration...",
            showsCancelButton: true
        )
        progressPanel.show()

        let sourceIndex = selectedSourceIndex
        let destinationIndex = selectedDestinationIndex
        let sourceName = selectedSourceName
        let destinationName = selectedDestinationName
        var operationTask: Task<Void, Never>?
        progressPanel.onCancel = {
            operationTask?.cancel()
        }

        operationTask = Task {
            do {
                var responses: [[UInt8]] = []
                let requests = FB01ModuleServices.shared.deviceService.allBankRequestKinds
                for (index, request) in requests.enumerated() {
                    try Task.checkCancellation()
                    let detail = "Requesting \(request.displayName) (\(index + 1) of \(requests.count))..."
                    statusMessage = detail
                    progressPanel.update(message: "The voices are being fetched. Please wait.\n\(detail)")
                    let response = try await Task.detached(priority: .userInitiated) {
                        try FB01MIDI.request(
                            request,
                            sourceIndex: sourceIndex,
                            destinationIndex: destinationIndex,
                            systemChannel: 0,
                            timeout: 20
                        )
                    }.value
                    responses.append(response)
                }
                try Task.checkCancellation()

                let artifact = try FB01Artifact(sysexBytes: responses.flatMap { $0 })
                let fetchedSources = artifact.messages.enumerated().map { index, message in
                    LibrarySource(
                        title: message.sourceTitle(index: index + 1),
                        subtitle: "FB-01 Live Fetch",
                        artifact: FB01Artifact(message: message),
                        origin: .liveFetch
                    )
                }
                applyFetchedSources(fetchedSources, insertionMode: insertionMode)
                statusMessage = "Fetched \(fetchedSources.count) library item\(fetchedSources.count == 1 ? "" : "s") from \(sourceName) -> \(destinationName)."
                errorMessage = nil
            } catch is CancellationError {
                statusMessage = nil
                errorMessage = "Fetch banks canceled."
            } catch {
                errorMessage = "Fetch failed: \(error)"
                statusMessage = nil
            }

            progressPanel.dismiss()
            isFetchingFromDevice = false
        }
    }

    func fetchStoredConfigurationsFromDevice() {
        guard !isBusy else { return }
        guard let insertionMode = fetchInsertionMode(title: "Fetch FB-01 Configurations", noun: "configurations") else { return }

        isFetchingConfigurations = true
        statusMessage = "Fetching FB-01 configurations..."
        errorMessage = nil
        let progressPanel = EditorProgressPanel(
            title: "Fetch FB-01 Configurations",
            message: "The configurations are being fetched. Please wait.\nRequesting configuration 1...",
            showsCancelButton: true
        )
        progressPanel.show()

        let sourceIndex = selectedSourceIndex
        let destinationIndex = selectedDestinationIndex
        let sourceName = selectedSourceName
        let destinationName = selectedDestinationName
        var operationTask: Task<Void, Never>?
        progressPanel.onCancel = {
            operationTask?.cancel()
        }

        operationTask = Task {
            do {
                var responses: [[UInt8]] = []
                let module = FB01ModuleServices.shared.module
                for number in module.allConfigurationSlots.closedRange {
                    try Task.checkCancellation()
                    let detail = "Requesting configuration \(number) of \(module.allConfigurationSlots.upperBound)..."
                    statusMessage = detail
                    progressPanel.update(message: "The configurations are being fetched. Please wait.\n\(detail)")
                    let response = try await Task.detached(priority: .userInitiated) {
                        try FB01MIDI.request(
                            .configuration(number),
                            sourceIndex: sourceIndex,
                            destinationIndex: destinationIndex,
                            systemChannel: 0,
                            timeout: 15
                        )
                    }.value
                    responses.append(response)
                }
                try Task.checkCancellation()

                let artifact = try FB01Artifact(sysexBytes: responses.flatMap { $0 })
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
            } catch is CancellationError {
                statusMessage = nil
                errorMessage = "Configuration fetch canceled."
            } catch {
                errorMessage = "Configuration fetch failed: \(error)"
                statusMessage = nil
            }

            progressPanel.dismiss()
            isFetchingConfigurations = false
        }
    }

    func storeGeneralMIDIVoicesToDevice() {
        guard !isBusy else { return }
        guard let targetBank = chooseGeneralMIDITargetBank() else { return }
        guard confirmGeneralMIDIOverwrite(targetBank: targetBank) else { return }

        let sourceIndex = selectedSourceIndex
        let destinationIndex = selectedDestinationIndex
        let systemChannel = systemChannel
        let destinationName = selectedDestinationName
        isFetchingFromDevice = true
        statusMessage = "Preparing General MIDI voices for Bank \(targetBank)..."
        errorMessage = nil
        let progressPanel = EditorProgressPanel(
            title: "Store General MIDI Voices",
            message: "The voices are being stored. Please wait.\nPreparing General MIDI voices for Bank \(targetBank)...",
            showsCancelButton: true
        )
        progressPanel.show()

        var operationTask: Task<Void, Never>?
        progressPanel.onCancel = {
            operationTask?.cancel()
        }

        operationTask = Task {
            do {
                let backupDirectory = try ensureDefaultEditorBackupDirectory()
                let backupURL = backupDirectory.appendingPathComponent(
                    backupFileName(prefix: "bank-\(targetBank)-before-general-midi")
                )

                let selectedVoices = try await fetchGeneralMIDISourceVoices(
                    sourceIndex: sourceIndex,
                    destinationIndex: destinationIndex,
                    systemChannel: systemChannel,
                    progressPanel: progressPanel
                )
                try Task.checkCancellation()

                statusMessage = "Backing up Bank \(targetBank) before General MIDI install..."
                progressPanel.update(message: "The voices are being stored. Please wait.\nBacking up Bank \(targetBank)...")
                let originalBytes = try await Task.detached(priority: .userInitiated) {
                    try FB01MIDI.request(
                        .voiceBank(targetBank),
                        sourceIndex: sourceIndex,
                        destinationIndex: destinationIndex,
                        systemChannel: systemChannel,
                        timeout: 15
                    )
                }.value
                let originalArtifact = try FB01Artifact(sysexBytes: originalBytes)
                try await Task.detached(priority: .userInitiated) {
                    try originalArtifact.writeSysEx(to: backupURL)
                }.value
                try Task.checkCancellation()

                progressPanel.update(message: "The voices are being stored. Please wait.\nTurning FB-01 Protect OFF...")
                let protectOff = try FB01SysExMessage.command(.setMemoryProtect(systemChannel: systemChannel, .off)).bytes
                try await Task.detached(priority: .userInitiated) {
                    try FB01MIDI.sendSysEx([protectOff], destinationIndex: destinationIndex, delayBetweenMessages: 0)
                }.value
                try await Task.sleep(for: .milliseconds(300))
                try Task.checkCancellation()

                var readback = try voiceBankData(from: originalBytes, expectedBankNumber: targetBank)
                var mismatches = generalMIDIMismatches(readback: readback, targetBank: targetBank, selectedVoices: selectedVoices)
                var previousMismatchCount = mismatches.count + 1
                var pass = 0

                while !mismatches.isEmpty {
                    pass += 1
                    guard pass <= generalMIDIStoreMaximumPasses else {
                        throw FB01AppError.message("Bank \(targetBank) still has \(mismatches.count) General MIDI mismatches after \(generalMIDIStoreMaximumPasses) store passes. The FB-01 may be rejecting the bulk dump; stop playing notes during store operations and check Protect/cabling before retrying.")
                    }
                    guard mismatches.count < previousMismatchCount else {
                        throw FB01AppError.message("Bank \(targetBank) made no store progress; first mismatch: \(mismatches[0])")
                    }

                    previousMismatchCount = mismatches.count
                    statusMessage = "Storing General MIDI voices in Bank \(targetBank), pass \(pass); \(mismatches.count) mismatch\(mismatches.count == 1 ? "" : "es") remain..."
                    progressPanel.update(message: "The voices are being stored. Please wait.\nStoring Bank \(targetBank), pass \(pass); verifying by readback...")
                    let editedBank = try readback.replacingVoices(selectedVoices)
                    let loadMessage = try voiceBankLoadMessage(bank: editedBank, systemChannel: systemChannel)
                    let nextReadbackBytes = try await Task.detached(priority: .userInitiated) {
                        try FB01MIDI.sendLongSysEx(loadMessage, destinationIndex: destinationIndex, timeout: 45)
                        try await Task.sleep(for: .milliseconds(1500))
                        return try FB01MIDI.request(
                            .voiceBank(targetBank),
                            sourceIndex: sourceIndex,
                            destinationIndex: destinationIndex,
                            systemChannel: systemChannel,
                            timeout: 15
                        )
                    }.value
                    try Task.checkCancellation()
                    readback = try voiceBankData(from: nextReadbackBytes, expectedBankNumber: targetBank)
                    mismatches = generalMIDIMismatches(readback: readback, targetBank: targetBank, selectedVoices: selectedVoices)
                }

                cacheVoiceBank(readback, userBankNumber: targetBank)
                statusMessage = "FB-01 verified General MIDI voices in Bank \(targetBank) on \(destinationName). Backup saved to \(backupURL.lastPathComponent)."
                errorMessage = nil
            } catch is CancellationError {
                statusMessage = nil
                errorMessage = "General MIDI install canceled."
            } catch {
                statusMessage = nil
                errorMessage = "General MIDI install failed: \(error)"
            }
            progressPanel.dismiss()
            isFetchingFromDevice = false
        }
    }

    func resetDeviceToFactorySettings() {
        showFactoryResetInstructions()
        statusMessage = "Factory reset instructions shown. Complete the FB-01 front-panel reset, wait for END, then power-cycle the unit."
        errorMessage = nil
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
        panel.allowedContentTypes = UTType.currentModuleConfigurationFileTypes
        panel.directoryURL = preferredSaveDirectoryURL()
        panel.nameFieldStringValue = "\(safeFileName(sources[index].title)).\(EditorSynthModule.fileProfile.singleConfigurationExtension)"
        panel.message = "Save this configuration to a configuration file."
        panel.prompt = "Save Configuration to File"

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
        panel.allowedContentTypes = allowedContentTypes(for: selectedSource.artifact.kind)
        panel.directoryURL = preferredSaveDirectoryURL()
        panel.nameFieldStringValue = "\(safeFileName(selectedSource.title)).\(preferredFileExtension(for: selectedSource.artifact.kind))"

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
        panel.allowedContentTypes = UTType.currentModuleConfigurationBankFileTypes
        panel.directoryURL = preferredSaveDirectoryURL()
        panel.nameFieldStringValue = configurationSources.count == 20
            ? "fb01-configurations-1-20.\(EditorSynthModule.fileProfile.configurationBankExtension)"
            : "fb01-configurations.\(EditorSynthModule.fileProfile.configurationBankExtension)"

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
        panel.allowedContentTypes = UTType.currentModuleVoiceBankFileTypes
        panel.directoryURL = preferredSaveDirectoryURL()
        panel.nameFieldStringValue = "\(safeFileName(sources[index].title))-edited.\(EditorSynthModule.fileProfile.voiceBankExtension)"
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
        alert.informativeText = "The library workspace contains local edits in \(editedCount) item\(editedCount == 1 ? "" : "s"). Save them as SysEx files before quitting?"
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
        sidebarSelection = .source
        preparedKeyboardVoiceSignature = nil
        scheduleKeyboardVoicePreparation()
    }

    func selectVoice(sourceID: LibrarySource.ID, number: Int) {
        selectedVoiceNumbers[sourceID] = number
        preparedKeyboardVoiceSignature = nil
        scheduleKeyboardVoicePreparation()
    }

    func removeSelectedSource() {
        guard let selectedSource,
              let index = sources.firstIndex(where: { $0.id == selectedSource.id }) else {
            return
        }

        sources.remove(at: index)

        if sources.isEmpty {
            selectedSourceID = nil
            sidebarSelection = .system
        } else {
            selectedSourceID = sources[min(index, sources.count - 1)].id
            sidebarSelection = .source
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
        alert.messageText = "Rename Library Item"
        alert.informativeText = "Choose a local display name for this library item."
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
        statusMessage = "Renamed library item to \(title)."
        errorMessage = nil
    }

    func clearSources() {
        guard !sources.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "Clear Library Workspace?"
        alert.informativeText = "This removes the library items from the app window. It does not delete files from disk or change the FB-01."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let count = sources.count
        sources.removeAll()
        selectedSourceID = nil
        sidebarSelection = .system
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
        preparedKeyboardVoiceSignature = nil
        scheduleKeyboardVoicePreparation()
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
        preparedKeyboardVoiceSignature = nil
        scheduleKeyboardVoicePreparation()
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
        preparedKeyboardVoiceSignature = nil
        scheduleKeyboardVoicePreparation()
        selectedSourceID = sources[index].id
        statusMessage = "Reset \(count) local voice edit\(count == 1 ? "" : "s")."
        errorMessage = nil
    }

    func copySelectedVoiceToLocalSlot() {
        copyVoiceSlotOnDevice()
    }

    func copyVoiceSlotOnDevice() {
        guard !isBusy else { return }

        let sourceIndex = selectedSourceIndex
        let destinationIndex = selectedDestinationIndex
        let systemChannel = systemChannel
        let destinationName = selectedDestinationName

        isFetchingFromDevice = true
        statusMessage = "Fetching Bank 1 and Bank 2 voice names from FB-01..."
        errorMessage = nil
        let progressPanel = EditorProgressPanel(
            title: "Fetching Voice Names",
            message: "Fetching Bank 1 and Bank 2 from the FB-01 so the Copy Voice to Slot dialog can show current RAM voice names."
        )
        progressPanel.show()

        Task {
            let nameLookup = await Task.detached(priority: .userInitiated) {
                Self.fetchRAMVoiceNamesForDeviceCopy(
                    sourceIndex: sourceIndex,
                    destinationIndex: destinationIndex,
                    systemChannel: systemChannel
                )
            }.value
            progressPanel.dismiss()

            guard let selection = Self.chooseDeviceVoiceCopySelection(nameLookup: nameLookup) else {
                statusMessage = nil
                isFetchingFromDevice = false
                return
            }

            let sourceTitle = nameLookup.sourceTitle(
                location: .bank(selection.sourceBank),
                voiceNumber: selection.sourceVoiceNumber + 1
            )
            let targetTitle = "Bank \(selection.targetBank) Voice \(selection.targetVoiceNumber + 1)"
            statusMessage = "Fetching \(sourceTitle) from FB-01..."
            let copyProgressPanel = EditorProgressPanel(
                title: "Copying Voice",
                message: "The voice is being copied. Please wait.\nFetching \(sourceTitle) from the FB-01..."
            )
            copyProgressPanel.show()

            do {
                let voice = try await Task.detached(priority: .userInitiated) {
                    try Self.fetchDeviceVoice(
                        bank: selection.sourceBank,
                        voiceNumber: selection.sourceVoiceNumber,
                        sourceIndex: sourceIndex,
                        destinationIndex: destinationIndex,
                        systemChannel: systemChannel
                    )
                }.value

                statusMessage = "Copying \(sourceTitle) to \(targetTitle)..."
                copyProgressPanel.update(message: "The voice is being copied. Please wait.\nStoring \(targetTitle) and verifying by readback...")
                let backupFileName = try await storeVoicePayloadByBankImage(
                    voice,
                    systemChannel: systemChannel,
                    options: VoiceDocumentStoreOptions(
                        bank: selection.targetBank - 1,
                        voiceNumber: selection.targetVoiceNumber
                    ),
                    sourceIndex: sourceIndex,
                    destinationIndex: destinationIndex,
                    destinationName: destinationName,
                    statusPrefix: "Copying \(sourceTitle) to \(targetTitle)"
                )
                statusMessage = "FB-01 copied \(sourceTitle) to \(targetTitle) on \(destinationName). Backup saved to \(backupFileName)."
                errorMessage = nil
                copyProgressPanel.dismiss()
                showCopyComplete(
                    itemKind: "Voice",
                    sourceTitle: sourceTitle,
                    targetTitle: targetTitle,
                    destinationName: destinationName,
                    backupFileName: backupFileName
                )
            } catch {
                copyProgressPanel.dismiss()
                statusMessage = nil
                errorMessage = "Copy voice to slot failed: \(error). Backup may not have completed, Protect may still be ON, or the FB-01 may not have accepted the bank write."
            }

            isFetchingFromDevice = false
        }
    }

    func copyConfigurationSlotOnDevice() {
        guard !isBusy else { return }

        let sourceIndex = selectedSourceIndex
        let destinationIndex = selectedDestinationIndex
        let systemChannel = systemChannel
        let destinationName = selectedDestinationName

        isFetchingConfigurations = true
        statusMessage = "Fetching configuration names from FB-01..."
        errorMessage = nil
        let progressPanel = EditorProgressPanel(
            title: "Fetching Configuration Names",
            message: "Fetching configurations 1-16 from the FB-01 so the Copy Configuration to Slot dialog can show current writable slot names."
        )
        progressPanel.show()

        Task {
            let nameLookup = await Task.detached(priority: .userInitiated) {
                Self.fetchConfigurationNamesForDeviceCopy(
                    sourceIndex: sourceIndex,
                    destinationIndex: destinationIndex,
                    systemChannel: systemChannel
                )
            }.value
            progressPanel.dismiss()

            guard let selection = Self.chooseDeviceConfigurationCopySelection(nameLookup: nameLookup) else {
                statusMessage = nil
                isFetchingConfigurations = false
                return
            }

            let sourceTitle = nameLookup.menuTitle(slot: selection.sourceSlot + 1)
            let targetTitle = "Configuration \(selection.targetSlot + 1)"
            statusMessage = "Fetching \(sourceTitle) from FB-01..."
            let copyProgressPanel = EditorProgressPanel(
                title: "Copying Configuration",
                message: "The configuration is being copied. Please wait.\nFetching \(sourceTitle) from the FB-01..."
            )
            copyProgressPanel.show()

            do {
                let configuration = try await Task.detached(priority: .userInitiated) {
                    try Self.fetchDeviceConfiguration(
                        slot: selection.sourceSlot,
                        sourceIndex: sourceIndex,
                        destinationIndex: destinationIndex,
                        systemChannel: systemChannel
                    )
                }.value

                statusMessage = "Copying \(sourceTitle) to \(targetTitle)..."
                copyProgressPanel.update(message: "The configuration is being copied. Please wait.\nStoring \(targetTitle) and verifying by readback...")
                let backupFileName = try await storeConfigurationPayloadForDeviceCopy(
                    configuration,
                    systemChannel: systemChannel,
                    slot: selection.targetSlot,
                    sourceIndex: sourceIndex,
                    destinationIndex: destinationIndex,
                    destinationName: destinationName,
                    statusPrefix: "Copying \(sourceTitle) to \(targetTitle)"
                )
                statusMessage = "FB-01 copied \(sourceTitle) to \(targetTitle) on \(destinationName). Backup saved to \(backupFileName)."
                errorMessage = nil
                copyProgressPanel.dismiss()
                showCopyComplete(
                    itemKind: "Configuration",
                    sourceTitle: sourceTitle,
                    targetTitle: targetTitle,
                    destinationName: destinationName,
                    backupFileName: backupFileName
                )
            } catch {
                copyProgressPanel.dismiss()
                statusMessage = nil
                errorMessage = "Copy configuration to slot failed: \(error). Backup may not have completed, Protect may still be ON, or the FB-01 may not have accepted the store."
            }

            isFetchingConfigurations = false
        }
    }

    private func showCopyComplete(
        itemKind: String,
        sourceTitle: String,
        targetTitle: String,
        destinationName: String,
        backupFileName: String
    ) {
        let alert = NSAlert()
        alert.messageText = "Copy Complete"
        alert.informativeText = "\(itemKind) copy verified.\n\n\(sourceTitle) was copied to \(targetTitle) on \(destinationName).\n\nBackup saved to \(backupFileName)."
        alert.addButton(withTitle: "OK")
        alert.alertStyle = .informational
        alert.runModal()
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
        guard let target = chooseVoiceSlot(
                title: "Copy Voice to Slot",
                message: "This copies \(voice.name.isEmpty ? "the selected voice" : "\"\(voice.name)\"") to a local Bank 1 or Bank 2 voice slot. It does not write to disk or change the FB-01.",
                actionTitle: "Copy",
                sourceID: sourceID,
                currentNumber: number
              ) else {
            return
        }

        applyVoiceSlotOperation(.copy, sourceID: sourceID, number: number, target: target, voice: voice)
    }

    func swapVoiceWithLocalSlot(sourceID: LibrarySource.ID, number: Int, voice: FB01VoiceData, voices: [FB01VoiceSummary]) {
        guard let target = chooseVoiceSlot(
                title: "Swap Voice with Slot",
                message: "This swaps the selected voice with a local Bank 1 or Bank 2 voice slot. It does not write to disk or change the FB-01.",
                actionTitle: "Swap",
                sourceID: sourceID,
                currentNumber: number
              ) else {
            return
        }

        applyVoiceSlotOperation(.swap, sourceID: sourceID, number: number, target: target, voice: voice)
    }

    func applyVoiceSlotOperation(_ operation: VoiceSlotOperation, sourceID: LibrarySource.ID, number: Int, target: VoiceSlotTarget, voice: FB01VoiceData) {
        guard let sourceIndex = sources.firstIndex(where: { $0.id == sourceID }),
              let targetIndex = sources.firstIndex(where: { $0.id == target.sourceID }),
              sourceID != target.sourceID || number != target.number else {
            return
        }

        if sources[targetIndex].isVoiceEdited(number: target.number),
           !confirmEditedVoiceSlotOverwrite(operation: operation, source: sources[targetIndex], target: target) {
            return
        }

        switch operation {
        case .copy:
            sources[targetIndex].editedVoices[target.number] = voice
            statusMessage = "Copied \(voice.name.isEmpty ? "selected voice" : voice.name) to Bank \(target.bank + 1) Voice \(target.number) locally."
        case .swap:
            guard let targetVoiceBank = sources[targetIndex].voiceBankData,
                  let targetVoice = sources[targetIndex].voice(number: target.number, in: targetVoiceBank) else {
                return
            }
            sources[sourceIndex].editedVoices[number] = targetVoice
            sources[targetIndex].editedVoices[target.number] = voice
            statusMessage = "Swapped Voice \(number) with Bank \(target.bank + 1) Voice \(target.number) locally."
        }

        selectedSourceID = sources[targetIndex].id
        preparedKeyboardVoiceSignature = nil
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

    func sendAndConfirmSelectedConfigurationToCurrentEditBuffer() {
        guard let selectedSource,
              let payload = selectedSource.editableConfigurationPayload else {
            return
        }

        sendAndConfirmConfigurationToCurrentEditBuffer(sourceID: selectedSource.id, payload: payload)
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

    func sendAndConfirmConfigurationToCurrentEditBuffer(sourceID: LibrarySource.ID, payload: FB01ConfigurationData) {
        guard let source = sources.first(where: { $0.id == sourceID }) else {
            return
        }

        let alert = NSAlert()
        alert.messageText = "Send and Confirm Configuration?"
        alert.informativeText = "This sends \(source.title) to the FB-01 current configuration edit buffer through \(selectedDestinationName), then asks the FB-01 for its current configuration. It does not store it in a numbered slot."
        alert.addButton(withTitle: "Send and Confirm")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        sendAndConfirmConfigurationPayload(
            payload,
            systemChannel: source.configurationSystemChannel ?? 0,
            sourceTitle: source.title
        )
    }

    func storeSelectedConfigurationToDeviceSlot() {
        guard let selectedSource,
              let payload = selectedSource.editableConfigurationPayload else {
            return
        }

        guard let options = chooseConfigurationStoreOptions(
            source: selectedSource,
            requiresConfirmation: false
        ) else {
            return
        }

        storeConfigurationPayload(
            payload,
            sourceTitle: selectedSource.title,
            systemChannel: selectedSource.configurationSystemChannel ?? 0,
            slot: options.slot,
            backupURL: options.backupURL,
            confirmAfterStore: options.confirmAfterStore
        )
    }

    func storeAndConfirmSelectedConfigurationToDeviceSlot() {
        guard let selectedSource,
              let payload = selectedSource.editableConfigurationPayload else {
            return
        }

        guard let options = chooseConfigurationStoreOptions(
            source: selectedSource,
            requiresConfirmation: true
        ) else {
            return
        }

        storeConfigurationPayload(
            payload,
            sourceTitle: selectedSource.title,
            systemChannel: selectedSource.configurationSystemChannel ?? 0,
            slot: options.slot,
            backupURL: options.backupURL,
            confirmAfterStore: true
        )
    }

    private func chooseConfigurationStoreOptions(source selectedSource: LibrarySource, requiresConfirmation: Bool) -> ConfigurationStoreOptions? {
        let alert = NSAlert()
        alert.messageText = requiresConfirmation ? "Store and Confirm Configuration to FB-01 Slot" : "Store Configuration to FB-01 Slot"
        alert.informativeText = "Choose a writable configuration slot. This sends Protect OFF, then permanently overwrites that slot on the FB-01 after first sending the selected configuration to the current edit buffer. Fetch and save a backup of the destination slot before continuing unless you are certain it can be replaced."
        alert.addButton(withTitle: requiresConfirmation ? "Store, Overwrite, and Confirm" : "Store and Overwrite")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        let stack = NSStackView()
        stack.frame = NSRect(x: 0, y: 0, width: 520, height: 148)
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .leading

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 26), pullsDown: false)
        let module = FB01ModuleServices.shared.module
        for number in module.writableConfigurationSlots.closedRange {
            popup.addItem(withTitle: configurationSlotMenuTitle(slot: number - 1))
        }
        if let storedNumber = selectedSource.storedConfigurationNumber,
           module.isWritableConfigurationSlot(storedNumber + 1) {
            popup.selectItem(at: storedNumber)
        }
        let backupCheckbox = NSButton(checkboxWithTitle: "Fetch and save a backup of the destination slot before overwriting", target: nil, action: nil)
        backupCheckbox.state = .on
        let confirmCheckbox = NSButton(checkboxWithTitle: "Fetch the stored slot after storing and compare it to the source", target: nil, action: nil)
        confirmCheckbox.state = requiresConfirmation ? .on : .off
        confirmCheckbox.isEnabled = !requiresConfirmation
        stack.addArrangedSubview(labelledPopup(label: "Overwrite slot:", popup: popup))
        stack.addArrangedSubview(backupCheckbox)
        stack.addArrangedSubview(confirmCheckbox)
        stack.addArrangedSubview(makeWarningLabel("Writable slots are 1-16. Configurations 17-20 are read only and are intentionally unavailable here. Protect is set OFF before storing.", width: 500))
        alert.accessoryView = stack

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }

        let slot = popup.indexOfSelectedItem
        var backupURL: URL?
        if backupCheckbox.state == .on {
            guard let url = chooseConfigurationBackupURL(slot: slot) else {
                return nil
            }
            backupURL = url
        }

        return ConfigurationStoreOptions(
            slot: slot,
            backupURL: backupURL,
            confirmAfterStore: confirmCheckbox.state == .on || requiresConfirmation
        )
    }

    private func chooseConfigurationBackupURL(slot: Int) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = UTType.currentModuleGenericSysExFileTypes
        panel.directoryURL = preferredSaveDirectoryURL()
        panel.nameFieldStringValue = "configuration-\(slot + 1)-backup.\(EditorSynthModule.fileProfile.genericSysExExtension)"
        panel.message = "Choose where to save the current contents of Configuration \(slot + 1) before overwriting it."
        panel.prompt = "Save Backup"

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        rememberSaveDirectory(for: url)
        return url
    }

    private func storeConfigurationPayload(
        _ payload: FB01ConfigurationData,
        sourceTitle: String,
        systemChannel: Int,
        slot: Int,
        backupURL: URL?,
        confirmAfterStore: Bool
    ) {
        guard !isBusy else { return }

        let sourceIndex = selectedSourceIndex
        let destinationIndex = selectedDestinationIndex
        let destinationName = selectedDestinationName
        isFetchingFromDevice = true
        statusMessage = backupURL == nil
            ? "Storing configuration to slot \(slot + 1)..."
            : "Backing up configuration \(slot + 1) before storing..."
        errorMessage = nil

        Task {
            do {
                let backupArtifact = try await Task.detached(priority: .userInitiated) { () -> FB01Artifact? in
                    if let backupURL {
                        let backupBytes = try FB01MIDI.request(
                            .configuration(slot + 1),
                            sourceIndex: sourceIndex,
                            destinationIndex: destinationIndex,
                            systemChannel: systemChannel,
                            timeout: 8
                        )
                        let artifact = try FB01Artifact(sysexBytes: backupBytes)
                        try artifact.writeSysEx(to: backupURL)
                        try await Task.sleep(for: .milliseconds(400))
                        return artifact
                    }
                    return nil
                }.value

                let confirmedConfiguration = try await FB01ModuleServices.shared.configurationService.storeConfiguration(
                    payload,
                    zeroBasedSlot: slot,
                    sourceIndex: sourceIndex,
                    destinationIndex: destinationIndex,
                    systemChannel: systemChannel,
                    confirmAfterStore: confirmAfterStore
                ) { [self] event in
                    await MainActor.run {
                        switch event {
                        case .turningProtectOff:
                            self.statusMessage = "Turning FB-01 Protect OFF before storing configuration \(slot + 1)..."
                        case .sendingConfigurationData:
                            self.statusMessage = "Sending \(sourceTitle) to the current configuration edit buffer..."
                        case .storingSlot:
                            self.statusMessage = "Storing \(sourceTitle) in configuration \(slot + 1)..."
                        case .verifyingSlot:
                            self.statusMessage = "Fetching configuration \(slot + 1) to verify store..."
                        }
                    }
                }

                let backupText = backupArtifact == nil ? "" : " Backup saved."
                if confirmAfterStore {
                    if confirmedConfiguration?.bytes == payload.bytes {
                        statusMessage = "FB-01 confirmed \(sourceTitle) stored to configuration \(slot + 1) on \(destinationName).\(backupText)"
                    } else {
                        statusMessage = "Stored \(sourceTitle) to configuration \(slot + 1), but fetched data did not match exactly. Protect may still be ON, the MIDI path may be wrong, or the FB-01 did not accept the store.\(backupText)"
                    }
                } else {
                    statusMessage = "Stored \(sourceTitle) to configuration \(slot + 1) on \(destinationName).\(backupText)"
                }
                errorMessage = nil
            } catch {
                statusMessage = nil
                errorMessage = "Store configuration failed: \(error). Protect may still be ON, the MIDI path may be wrong, or the FB-01 did not accept the store."
            }

            isFetchingFromDevice = false
        }
    }

    func storeConfigurationMessages(payload: FB01ConfigurationData, systemChannel: Int, slot: Int) throws -> [[UInt8]] {
        do {
            return try FB01ModuleServices.shared.configurationService.storeMessages(
                configuration: payload,
                systemChannel: systemChannel,
                zeroBasedSlot: slot
            )
        } catch is FB01SysExError {
            throw FB01AppError.readOnlyConfigurationSlot
        }
    }

    private func storeConfigurationPayloadForDeviceCopy(
        _ payload: FB01ConfigurationData,
        systemChannel: Int,
        slot: Int,
        sourceIndex: Int,
        destinationIndex: Int,
        destinationName: String,
        statusPrefix: String
    ) async throws -> String {
        let slotNumber = slot + 1
        let backupDirectory = try ensureDefaultBackupDirectory()
        let backupURL = backupDirectory.appendingPathComponent(
            backupFileName(prefix: "configuration-\(slotNumber)-before-copy")
        )

        statusMessage = "\(statusPrefix): backing up Configuration \(slotNumber) on \(destinationName)..."
        let originalBytes = try await Task.detached(priority: .userInitiated) {
            try FB01MIDI.request(
                .configuration(slotNumber),
                sourceIndex: sourceIndex,
                destinationIndex: destinationIndex,
                systemChannel: systemChannel,
                timeout: 8
            )
        }.value
        let originalArtifact = try FB01Artifact(sysexBytes: originalBytes)
        try await Task.detached(priority: .userInitiated) {
            try originalArtifact.writeSysEx(to: backupURL)
        }.value

        let confirmedConfiguration = try await FB01ModuleServices.shared.configurationService.storeConfiguration(
            payload,
            zeroBasedSlot: slot,
            sourceIndex: sourceIndex,
            destinationIndex: destinationIndex,
            systemChannel: systemChannel,
            confirmAfterStore: true
        ) { [self] event in
            await MainActor.run {
                switch event {
                case .turningProtectOff:
                    self.statusMessage = "\(statusPrefix): turning FB-01 Protect OFF..."
                case .sendingConfigurationData:
                    self.statusMessage = "\(statusPrefix): sending configuration data..."
                case .storingSlot:
                    self.statusMessage = "\(statusPrefix): storing Configuration \(slotNumber)..."
                case .verifyingSlot:
                    self.statusMessage = "\(statusPrefix): fetching Configuration \(slotNumber) to verify store..."
                }
            }
        }

        guard let confirmedConfiguration,
              confirmedConfiguration.bytes == payload.bytes else {
            throw FB01AppError.message("Configuration \(slotNumber) did not verify after storing.")
        }

        cacheConfiguration(confirmedConfiguration, slot: slotNumber)
        return backupURL.lastPathComponent
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

        guard let options = chooseDeviceVoiceStoreOptions(
            title: "Store Voice to FB-01 Slot",
            actionTitle: "Store and Overwrite",
            voiceDescription: voiceDisplayName(voice),
            sourceTitle: source.title,
            currentNumber: number
        ) else {
            return
        }

        storeVoicePayloadByBankImage(voice, systemChannel: systemChannel, options: options)
    }

    func storeAndConfirmVoiceToDeviceSlot(sourceID: LibrarySource.ID, number: Int, voice: FB01VoiceData, systemChannel: Int) {
        guard let source = sources.first(where: { $0.id == sourceID }) else {
            return
        }

        guard let options = chooseDeviceVoiceStoreOptions(
            title: "Store and Confirm Voice",
            actionTitle: "Store, Overwrite, and Confirm",
            voiceDescription: voiceDisplayName(voice),
            sourceTitle: source.title,
            currentNumber: number
        ) else {
            return
        }

        storeVoicePayloadByBankImage(voice, systemChannel: systemChannel, options: options)
    }

    private func chooseDeviceVoiceStoreOptions(
        title: String,
        actionTitle: String,
        voiceDescription: String,
        sourceTitle: String,
        currentNumber: Int
    ) -> VoiceDocumentStoreOptions? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "This saves a timestamped backup of the destination RAM bank, writes \(voiceDescription) from \(sourceTitle) into the selected Bank 1 or Bank 2 slot, then reads the bank back until that voice verifies."
        alert.addButton(withTitle: actionTitle)
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8
        stack.alignment = .leading

        let bankPopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 180, height: 26), pullsDown: false)
        let module = FB01ModuleServices.shared.module
        for bank in module.writableVoiceBanks {
            bankPopup.addItem(withTitle: "Bank \(bank)")
        }
        let preferredSlot = min(max(currentNumber - 1, 0), module.writableVoiceSlotCount - 1)
        bankPopup.selectItem(at: preferredSlot / module.voicesPerBank)

        let voicePopup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 180, height: 26), pullsDown: false)
        for voiceNumber in 1...module.voicesPerBank {
            voicePopup.addItem(withTitle: "Voice \(voiceNumber)")
        }
        voicePopup.selectItem(at: preferredSlot % module.voicesPerBank)

        stack.addArrangedSubview(labelledPopup(label: "Bank:", popup: bankPopup))
        stack.addArrangedSubview(labelledPopup(label: "Voice:", popup: voicePopup))
        stack.addArrangedSubview(makeWarningLabel("The backup is saved automatically in the Backups folder. The FB-01 may display dump/error during long writes; the app treats readback verification as the final result."))
        alert.accessoryView = stack

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }

        return VoiceDocumentStoreOptions(
            bank: bankPopup.indexOfSelectedItem,
            voiceNumber: voicePopup.indexOfSelectedItem
        )
    }

    private static func chooseDeviceConfigurationCopySelection(nameLookup: ConfigurationFetchNameLookup) -> DeviceConfigurationCopySelection? {
        let alert = NSAlert()
        alert.messageText = "Copy Configuration to Slot"
        alert.informativeText = "Fetch one configuration currently on the FB-01, then store it unchanged into a writable configuration slot. The destination slot will be overwritten."
        alert.addButton(withTitle: "Copy and Overwrite")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        alert.accessoryView = DeviceConfigurationCopyAccessory(nameLookup: nameLookup)

        guard alert.runModal() == .alertFirstButtonReturn,
              let accessory = alert.accessoryView as? DeviceConfigurationCopyAccessory else {
            return nil
        }
        return accessory.selection
    }

    nonisolated private static func fetchDeviceConfiguration(
        slot: Int,
        sourceIndex: Int,
        destinationIndex: Int,
        systemChannel: Int
    ) throws -> FB01ConfigurationData {
        do {
            return try FB01ModuleServices.shared.configurationService.fetchStoredConfiguration(
                zeroBasedSlot: slot,
                sourceIndex: sourceIndex,
                destinationIndex: destinationIndex,
                systemChannel: systemChannel,
                timeout: 8
            )
        } catch {
            throw FB01AppError.message("Response did not contain Configuration \(slot + 1)")
        }
    }

    nonisolated private static func fetchConfigurationNamesForDeviceCopy(
        sourceIndex: Int,
        destinationIndex: Int,
        systemChannel: Int
    ) -> ConfigurationFetchNameLookup {
        let names = FB01ModuleServices.shared.configurationService.fetchWritableConfigurationNames(
            sourceIndex: sourceIndex,
            destinationIndex: destinationIndex,
            systemChannel: systemChannel,
            timeout: 1.25
        )
        return ConfigurationFetchNameLookup(storedNames: names)
    }

    nonisolated private static func configurationName(fromDump bytes: [UInt8]) throws -> String? {
        try FB01ModuleServices.shared.configurationService.configurationName(fromDump: bytes)
    }

    private static func chooseDeviceVoiceCopySelection(nameLookup: VoiceDocumentFetchNameLookup) -> DeviceVoiceCopySelection? {
        let alert = NSAlert()
        alert.messageText = "Copy Voice to Slot"
        alert.informativeText = "Fetch one voice currently on the FB-01, then store it unchanged into a writable Bank 1 or Bank 2 slot. The destination slot will be overwritten."
        alert.addButton(withTitle: "Copy and Overwrite")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        alert.accessoryView = DeviceVoiceCopyAccessory(nameLookup: nameLookup)

        guard alert.runModal() == .alertFirstButtonReturn,
              let accessory = alert.accessoryView as? DeviceVoiceCopyAccessory else {
            return nil
        }
        return accessory.selection
    }

    nonisolated private static func fetchDeviceVoice(
        bank: Int,
        voiceNumber: Int,
        sourceIndex: Int,
        destinationIndex: Int,
        systemChannel: Int
    ) throws -> FB01VoiceData {
        try FB01ModuleServices.shared.voiceService.fetchStoredVoice(
            bank: bank,
            zeroBasedVoiceNumber: voiceNumber,
            sourceIndex: sourceIndex,
            destinationIndex: destinationIndex,
            systemChannel: systemChannel
        )
    }

    nonisolated private static func fetchRAMVoiceNamesForDeviceCopy(
        sourceIndex: Int,
        destinationIndex: Int,
        systemChannel: Int
    ) -> VoiceDocumentFetchNameLookup {
        let namesByBank = FB01ModuleServices.shared.voiceService.fetchWritableRAMVoiceNames(
            sourceIndex: sourceIndex,
            destinationIndex: destinationIndex,
            systemChannel: systemChannel,
            timeout: voiceBankNameFetchTimeout
        )
        return VoiceDocumentFetchNameLookup(ramBankNames: namesByBank)
    }

    private func storeVoicePayloadByBankImage(_ voice: FB01VoiceData, systemChannel: Int, options: VoiceDocumentStoreOptions) {
        guard !isBusy else { return }

        let sourceIndex = selectedSourceIndex
        let destinationIndex = selectedDestinationIndex
        let destinationName = selectedDestinationName
        let bankNumber = options.bank + 1
        let voiceNumber = options.voiceNumber + 1
        isFetchingFromDevice = true
        statusMessage = "Backing up Bank \(bankNumber) before storing Voice \(voiceNumber)..."
        errorMessage = nil

        Task {
            do {
                let backupFileName = try await storeVoicePayloadByBankImage(
                    voice,
                    systemChannel: systemChannel,
                    options: options,
                    sourceIndex: sourceIndex,
                    destinationIndex: destinationIndex,
                    destinationName: destinationName,
                    statusPrefix: "Storing Bank \(bankNumber) Voice \(voiceNumber)"
                )
                statusMessage = "FB-01 verified Bank \(bankNumber) Voice \(voiceNumber) on \(destinationName). Backup saved to \(backupFileName)."
                errorMessage = nil
            } catch {
                statusMessage = nil
                errorMessage = "Store voice failed: \(error). Backup may not have completed, Protect may still be ON, or the FB-01 may not have accepted the bank write."
            }

            isFetchingFromDevice = false
        }
    }

    private func storeVoicePayloadByBankImage(
        _ voice: FB01VoiceData,
        systemChannel: Int,
        options: VoiceDocumentStoreOptions,
        sourceIndex: Int,
        destinationIndex: Int,
        destinationName: String,
        statusPrefix: String
    ) async throws -> String {
        let bankNumber = options.bank + 1
        let voiceNumber = options.voiceNumber + 1
        let backupDirectory = try ensureDefaultBackupDirectory()
        let backupURL = backupDirectory.appendingPathComponent(
            backupFileName(prefix: "bank-\(bankNumber)-before-voice-\(voiceNumber)")
        )
        statusMessage = "\(statusPrefix): backing up Bank \(bankNumber) on \(destinationName)..."
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
        try await Task.detached(priority: .userInitiated) {
            try originalArtifact.writeSysEx(to: backupURL)
        }.value

        let readback = try await FB01ModuleServices.shared.voiceService.storeVoiceInBankImage(
            voice,
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
                    self.statusMessage = "\(statusPrefix): turning FB-01 Protect OFF..."
                case .storePass(let pass):
                    self.statusMessage = "\(statusPrefix): store pass \(pass), verifying after send..."
                }
            }
        }

        cacheVoiceBank(readback, userBankNumber: bankNumber)
        return backupURL.lastPathComponent
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
            sidebarSelection = .source
            statusMessage = "Opened \(loadedSources.count) library item\(loadedSources.count == 1 ? "" : "s")."
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
        UserDefaults.standard.set(selectedKeyboardSourceIndex, forKey: DefaultsKey.keyboardSourceIndex)

        if let source = midiSources.first(where: { $0.index == selectedSourceIndex }),
           let uniqueID = source.uniqueID {
            UserDefaults.standard.set(Int(uniqueID), forKey: DefaultsKey.sourceUniqueID)
        } else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.sourceUniqueID)
        }

        if let keyboardSource = midiSources.first(where: { $0.index == selectedKeyboardSourceIndex }),
           let uniqueID = keyboardSource.uniqueID {
            UserDefaults.standard.set(Int(uniqueID), forKey: DefaultsKey.keyboardSourceUniqueID)
        } else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.keyboardSourceUniqueID)
        }

        if let destination = midiDestinations.first(where: { $0.index == selectedDestinationIndex }),
           let uniqueID = destination.uniqueID {
            UserDefaults.standard.set(Int(uniqueID), forKey: DefaultsKey.destinationUniqueID)
        } else {
            UserDefaults.standard.removeObject(forKey: DefaultsKey.destinationUniqueID)
        }
    }

    private func invalidateKeyboardPreparation() {
        preparedKeyboardVoiceSignature = nil
        preparedKeyboardVoiceDate = nil
        invalidateAuditionBufferPreparation()
        keyboardPreparationTask?.cancel()
    }

    private func restartExternalKeyboardMonitor() {
        externalKeyboardMonitor?.stop()
        externalKeyboardMonitor = nil

        guard externalKeyboardEnabled else {
            externalKeyboardStatus = "Off"
            return
        }
        guard midiSources.contains(where: { $0.index == selectedKeyboardSourceIndex }) else {
            externalKeyboardStatus = "No input selected"
            return
        }

        do {
            let sourceName = selectedKeyboardSourceName
            externalKeyboardMonitor = try FB01MIDI.liveInputMonitor(sourceIndex: selectedKeyboardSourceIndex) { [weak self] message in
                Task(priority: .high) { @MainActor [weak self] in
                    self?.receiveExternalKeyboardMessage(message)
                }
            }
            externalKeyboardStatus = "Listening to \(sourceName)"
        } catch {
            externalKeyboardStatus = "Input unavailable"
            errorMessage = "MIDI input monitor failed: \(error)"
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

    private func ensureDefaultBackupDirectory() throws -> URL {
        let url = defaultBackupDirectoryURL
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private var defaultFileDirectoryURL: URL {
        FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Forest Editor", isDirectory: true)
    }

    private var defaultBackupDirectoryURL: URL {
        defaultFileDirectoryURL.appendingPathComponent("Backups", isDirectory: true)
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
            panel.allowedContentTypes = allowedContentTypes(for: sources[index].artifact.kind)
            panel.directoryURL = preferredSaveDirectoryURL()
            panel.nameFieldStringValue = "\(safeFileName(sources[index].title)).\(preferredFileExtension(for: sources[index].artifact.kind))"
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
        let fileExtension = EditorSynthModule.fileProfile.genericSysExExtension
        var candidate = "\(base).\(fileExtension)"
        var suffix = 2
        while usedNames.contains(candidate) {
            candidate = "\(base)-\(suffix).\(fileExtension)"
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
        sidebarSelection = selectedSourceID == nil ? .system : .source
    }

    private func fetchInsertionMode(title: String = "Fetch FB-01 Banks", noun: String = "banks") -> SourceInsertionMode? {
        guard !sources.isEmpty else {
            return .replace
        }

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "The library workspace already contains \(sources.count) item\(sources.count == 1 ? "" : "s"). Replace Library removes those items before fetching. Add to Library keeps them and adds the fetched \(noun) after them."
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
        try FB01ModuleServices.shared.configurationService.currentConfigurationMessageBytes(
            configuration: payload,
            systemChannel: systemChannel
        )
    }

    func currentConfigurationSendAndConfirmMessages(payload: FB01ConfigurationData, systemChannel: Int) throws -> [[UInt8]] {
        try FB01ModuleServices.shared.configurationService.currentConfigurationSendAndConfirmMessages(
            configuration: payload,
            systemChannel: systemChannel
        )
    }

    private func sendConfigurationPayload(_ payload: FB01ConfigurationData, systemChannel: Int, statusPrefix: String) {
        do {
            sendMIDI([try currentConfigurationMessageBytes(payload: payload, systemChannel: systemChannel)], statusMessage: "\(statusPrefix) on \(selectedDestinationName).")
        } catch {
            errorMessage = "Send configuration failed: \(error)"
            statusMessage = nil
        }
    }

    private func sendAndConfirmConfigurationPayload(_ payload: FB01ConfigurationData, systemChannel: Int, sourceTitle: String) {
        guard !isBusy else { return }

        let sourceIndex = selectedSourceIndex
        let destinationIndex = selectedDestinationIndex
        let destinationName = selectedDestinationName
        isFetchingFromDevice = true
        statusMessage = "Sending configuration and waiting for current edit buffer..."
        errorMessage = nil

        Task {
            do {
                let confirmedConfiguration = try await FB01ModuleServices.shared.configurationService.sendCurrentConfigurationAndConfirm(
                    payload,
                    sourceIndex: sourceIndex,
                    destinationIndex: destinationIndex,
                    systemChannel: systemChannel
                )
                if confirmedConfiguration?.bytes == payload.bytes {
                    statusMessage = "FB-01 confirmed current edit buffer matches \(sourceTitle) on \(destinationName)."
                } else {
                    statusMessage = "Sent \(sourceTitle); FB-01 returned a current configuration that did not match exactly."
                }
                errorMessage = nil
            } catch {
                statusMessage = nil
                errorMessage = "Configuration confirm failed: \(error)"
            }

            isFetchingFromDevice = false
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
                let confirmation = try await FB01ModuleServices.shared.voiceService.sendInstrumentVoiceAndConfirm(
                    voice,
                    instrument: instrument,
                    sourceIndex: sourceIndex,
                    destinationIndex: destinationIndex,
                    systemChannel: systemChannel
                )
                if let code = confirmation.statusCode {
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
                let storeMessages = try storeVoiceMessages(voice: voice, systemChannel: systemChannel, instrument: instrument, voiceSlot: voiceSlot)
                let status = try await Task.detached(priority: .userInitiated) {
                    return try FB01MIDI.sendAndReceive(
                        storeMessages,
                        sourceIndex: sourceIndex,
                        destinationIndex: destinationIndex,
                        timeout: 8,
                        maxMessages: 1,
                        delayBetweenMessages: 0.35
                    )
                }.value

                let requestKind = try voiceRAMBankRequestKind(forVoiceSlot: voiceSlot)
                let readback = try await Task.detached(priority: .userInitiated) {
                    try FB01MIDI.request(
                        requestKind,
                        sourceIndex: sourceIndex,
                        destinationIndex: destinationIndex,
                        systemChannel: systemChannel,
                        timeout: 15
                    )
                }.value

                let readbackVoice = try storedVoicePayload(from: [readback], voiceSlot: voiceSlot)
                let statusSuffix = try deviceStatusCode(from: status).map { " (status \(String(format: "0x%02X", $0)))" } ?? ""
                if readbackVoice?.bytes == voice.bytes {
                    statusMessage = "FB-01 confirmed store to voice \(voiceSlot + 1) on \(destinationName)\(statusSuffix); readback matches."
                } else if readbackVoice != nil {
                    statusMessage = "Stored voice \(voiceSlot + 1) on \(destinationName)\(statusSuffix), but readback did not match exactly."
                } else {
                    statusMessage = "Stored voice \(voiceSlot + 1) on \(destinationName)\(statusSuffix), but readback did not contain that slot."
                }
                errorMessage = nil
            } catch {
                statusMessage = nil
                errorMessage = "Store confirm failed: \(error). Protect may still be ON, the MIDI path may be wrong, or the FB-01 did not accept the store."
            }

            isFetchingFromDevice = false
        }
    }

    func storeVoiceMessages(voice: FB01VoiceData, systemChannel: Int, instrument: Int, voiceSlot: Int) throws -> [[UInt8]] {
        _ = try voiceRAMBankRequestKind(forVoiceSlot: voiceSlot)
        let protectOffCommand = FB01SysExMessage.command(.setMemoryProtect(
            systemChannel: systemChannel,
            .off
        ))
        let voiceMessage = try voice.instrumentVoiceArtifact(systemChannel: systemChannel, instrument: instrument).messages[0]
        let storeCommand = FB01SysExMessage.command(.storeCurrentInstrumentVoice(
            systemChannel: systemChannel,
            instrument: instrument,
            voiceNumber: voiceSlot
        ))
        return try [protectOffCommand.bytes, voiceMessage.bytes, storeCommand.bytes]
    }

    func voiceRAMBankRequestKind(forVoiceSlot voiceSlot: Int) throws -> FB01MIDIRequestKind {
        try FB01ModuleServices.shared.deviceService.writableVoiceBankRequestKind(forVoiceSlot: voiceSlot)
    }

    func storedVoicePayload(from messages: [[UInt8]], voiceSlot: Int) throws -> FB01VoiceData? {
        let requestKind = try voiceRAMBankRequestKind(forVoiceSlot: voiceSlot)
        guard case let .voiceBank(expectedBankNumber) = requestKind else {
            return nil
        }

        let expectedBank = expectedBankNumber - 1
        let expectedNumber = voiceSlot % FB01VoiceBankData.voiceCount + 1
        for bytes in messages {
            let artifact = try FB01Artifact(sysexBytes: bytes)
            for message in artifact.messages {
                switch message {
                case let .voiceBankDumpData(_, bank, _, data, _) where bank == expectedBank:
                    let bankData = try FB01VoiceBankData(bank: bank, data: data)
                    return bankData.voices.first { $0.number == expectedNumber }?.voice
                case let .voiceRAMDumpData(_, _, data, _) where expectedBank == 0:
                    let bankData = try FB01VoiceBankData(bank: 0, data: data)
                    return bankData.voices.first { $0.number == expectedNumber }?.voice
                default:
                    break
                }
            }
        }
        return nil
    }

    func sendKeyboardNote(_ note: Int, isOn: Bool) {
        guard !isBusy else {
            statusMessage = "Keyboard paused while the FB-01 is busy with a device operation."
            return
        }

        let boundedNote = min(max(note, 0), 127)
        let destinationIndex = selectedDestinationIndex
        let destinationName = selectedDestinationName
        let channel = UInt8(min(max(keyboardChannel, 0), 15))
        let velocity = UInt8(min(max(keyboardVelocity, 1), 127))

        let noteMessage = [
            (isOn ? 0x90 : 0x80) | channel,
            UInt8(boundedNote),
            isOn ? velocity : 0,
        ]
        Task(priority: .high) { [weak self] in
            do {
                try await LiveMIDIPlaybackController.shared.sendImmediate(noteMessage, destinationIndex: destinationIndex)
                if isOn {
                    self?.statusMessage = "Keyboard sent note \(boundedNote) on channel \(Int(channel) + 1) to \(destinationName)."
                    self?.errorMessage = nil
                }
            } catch {
                self?.errorMessage = "Keyboard note failed: \(error)"
                self?.statusMessage = nil
            }
        }
    }

    func receiveExternalKeyboardMessage(_ message: [UInt8]) {
        guard externalKeyboardEnabled else { return }
        guard !isBusy else {
            externalKeyboardStatus = "Paused during device operation"
            return
        }
        guard let status = message.first, (0x80...0xEF).contains(status) else {
            return
        }

        let event = status & 0xF0
        if event == 0xB0, message.count == 3 {
            let controller = Int(message[1])
            let value = Int(message[2])
            noteCustomControlMessage(message)
            if let label = customizedControlLabel(for: controller) {
                externalKeyboardStatus = "\(customControlsControllerProfile.title) \(label): \(MIDIControlChangeLabel.title(for: controller)) = \(value)"
                return
            }
        }

        if let externalKeyboardDocumentHandler, externalKeyboardDocumentHandler(message) {
            updateExternalKeyboardPressedNotes(from: message)
            return
        }

        let channel = UInt8(min(max(keyboardChannel, 0), 15))
        let rewritten = [event | channel] + message.dropFirst()
        let isNoteOn = event == 0x90 && message.count > 2 && message[2] > 0
        let isVolumeControl = event == 0xB0 && message.count == 3 && message[1] == 7

        if isVolumeControl {
            applyExternalKeyboardVolume(Int(message[2]))
        }
        let destinationIndex = selectedDestinationIndex
        let destinationName = selectedDestinationName

        let forwardingStatus: String
        if isNoteOn, message.count > 1 {
            forwardingStatus = "Input sent note \(message[1]) on channel \(Int(channel) + 1)"
        } else if isVolumeControl, message.count > 2 {
            forwardingStatus = "Volume \(message[2])"
        } else {
            forwardingStatus = "Input forwarding to \(destinationName)"
        }

        Task(priority: .high) { [weak self] in
            do {
                try await LiveMIDIPlaybackController.shared.sendImmediate(rewritten, destinationIndex: destinationIndex)
                self?.externalKeyboardStatus = forwardingStatus
                self?.errorMessage = nil
            } catch {
                self?.externalKeyboardStatus = "Input error"
                self?.errorMessage = "MIDI input failed: \(error)"
                self?.statusMessage = nil
            }
        }
        updateExternalKeyboardPressedNotes(from: message)
    }

    func sendKeyboardNoteWithoutVoicePreparation(_ note: Int, isOn: Bool) {
        guard !isBusy else {
            statusMessage = "Keyboard paused while the FB-01 is busy with a device operation."
            return
        }

        let boundedNote = min(max(note, 0), 127)
        let channel = UInt8(min(max(keyboardChannel, 0), 15))
        let velocity = UInt8(min(max(keyboardVelocity, 1), 127))
        let destinationIndex = selectedDestinationIndex
        let destinationName = selectedDestinationName
        let noteMessage = [
            (isOn ? 0x90 : 0x80) | channel,
            UInt8(boundedNote),
            isOn ? velocity : 0,
        ]

        Task(priority: .high) { [weak self] in
            do {
                try await LiveMIDIPlaybackController.shared.sendImmediate(noteMessage, destinationIndex: destinationIndex)
                if isOn {
                    self?.statusMessage = "Keyboard sent note \(boundedNote) on channel \(Int(channel) + 1) to \(destinationName)."
                    self?.errorMessage = nil
                }
            } catch {
                self?.errorMessage = "Keyboard note failed: \(error)"
                self?.statusMessage = nil
            }
        }
    }

    func receiveExternalKeyboardPerformanceMessage(_ message: [UInt8]) -> Bool {
        guard let status = message.first, (0x80...0xEF).contains(status) else {
            return false
        }
        let event = status & 0xF0
        let isVolumeControl = event == 0xB0 && message.count == 3 && message[1] == 7
        if isVolumeControl {
            return false
        }

        let channel = UInt8(min(max(keyboardChannel, 0), 15))
        let rewritten = [event | channel] + message.dropFirst()
        let destinationIndex = selectedDestinationIndex
        let destinationName = selectedDestinationName

        let forwardingStatus: String
        if event == 0x90, message.count > 2, message[2] > 0 {
            forwardingStatus = "Input sent note \(message[1]) on channel \(Int(channel) + 1)"
        } else if event == 0xB0, message.count > 2 {
            forwardingStatus = "Input forwarded CC \(message[1]) value \(message[2])"
        } else {
            forwardingStatus = "Input forwarding to \(destinationName)"
        }

        Task(priority: .high) { [weak self] in
            do {
                try await LiveMIDIPlaybackController.shared.sendImmediate(rewritten, destinationIndex: destinationIndex)
                self?.externalKeyboardStatus = forwardingStatus
                self?.errorMessage = nil
            } catch {
                self?.externalKeyboardStatus = "Input error"
                self?.errorMessage = "MIDI input failed: \(error)"
                self?.statusMessage = nil
            }
        }
        return true
    }

    func setExternalKeyboardDocumentHandler(_ handler: (([UInt8]) -> Bool)?) {
        externalKeyboardDocumentHandler = handler
    }

    func setLiveKeyboardContext(
        title: String,
        subtitle: String,
        noteOn: @escaping (Int) -> Void,
        noteOff: @escaping (Int) -> Void
    ) {
        liveKeyboardTitle = title
        liveKeyboardSubtitle = subtitle
        liveKeyboardNoteOnHandler = noteOn
        liveKeyboardNoteOffHandler = noteOff
    }

    func resetLiveKeyboardContext() {
        liveKeyboardTitle = selectedVoiceDocumentPayload().map { "Live Keyboard - \($0.voice.name)" } ?? "Live Keyboard"
        liveKeyboardSubtitle = hasKeyboardVoiceContext ? "Current voice" : "MIDI notes only"
        liveKeyboardNoteOnHandler = nil
        liveKeyboardNoteOffHandler = nil
    }

    func sendLiveKeyboardPaletteNote(_ note: Int, isOn: Bool) {
        if isOn, let liveKeyboardNoteOnHandler {
            liveKeyboardNoteOnHandler(note)
            return
        }

        if !isOn, let liveKeyboardNoteOffHandler {
            liveKeyboardNoteOffHandler(note)
            return
        }

        sendKeyboardNote(note, isOn: isOn)
    }

    private func updateExternalKeyboardPressedNotes(from message: [UInt8]) {
        guard message.count > 2, let status = message.first else {
            return
        }

        let event = status & 0xF0
        let note = Int(message[1])
        if event == 0x90, message[2] > 0 {
            externalKeyboardPressedNotes.insert(note)
        } else if event == 0x80 || (event == 0x90 && message[2] == 0) {
            externalKeyboardPressedNotes.remove(note)
        }
    }

    private func applyExternalKeyboardVolume(_ value: Int) {
        let bounded = min(max(value, 0), 127)
        externalKeyboardVolume = bounded
        systemMasterOutputLevel = bounded

        let destinationIndex = selectedDestinationIndex
        externalVolumeTask?.cancel()
        externalVolumeTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 80_000_000)
                try Task.checkCancellation()
                let message = try await MainActor.run {
                    try self?.systemMasterOutputMessageBytes(level: bounded)
                }
                guard let message else { return }
                try await LiveMIDIPlaybackController.shared.sendImmediate(message, destinationIndex: destinationIndex)
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    self?.externalKeyboardStatus = "Volume send failed"
                    self?.errorMessage = "Volume mapping failed: \(error)"
                    self?.statusMessage = nil
                }
            }
        }
    }

    private func applyExternalKeyboardPortamento(_ value: Int) {
        let bounded = min(max(value, 0), 127)
        externalKeyboardPortamento = bounded
        UserDefaults.standard.set(bounded, forKey: DefaultsKey.externalKeyboardPortamento)
        invalidateKeyboardPreparation()

        let destinationIndex = selectedDestinationIndex
        externalPortamentoTask?.cancel()
        externalPortamentoTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 80_000_000)
                try Task.checkCancellation()
                let message = try await MainActor.run {
                    try self?.liveKeyboardPortamentoMessageBytes(value: bounded)
                }
                guard let message else { return }
                try await LiveMIDIPlaybackController.shared.sendImmediate(message, destinationIndex: destinationIndex)
                await MainActor.run {
                    self?.externalKeyboardStatus = "Portamento \(bounded)"
                    self?.errorMessage = nil
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    self?.externalKeyboardStatus = "Portamento send failed"
                    self?.errorMessage = "Portamento mapping failed: \(error)"
                    self?.statusMessage = nil
                }
            }
        }
    }

    private func keyboardPreparationMessages(midiChannel: Int) throws -> [[UInt8]] {
        guard let context = selectedVoiceContext else {
            let signature = "\(systemChannel)-\(midiChannel)-audition-portamento-\(externalKeyboardPortamento)"
            guard preparedKeyboardVoiceSignature != signature || isKeyboardPreparationStale || !isAuditionBufferPrepared(signature: signature) else {
                return []
            }
            preparedKeyboardVoiceSignature = signature
            preparedKeyboardVoiceDate = Date()
            markAuditionBufferPrepared(signature: signature)
            return try keyboardAuditionPreparationMessages(systemChannel: systemChannel, midiChannel: midiChannel)
                + [try liveKeyboardPortamentoMessageBytes(value: externalKeyboardPortamento, systemChannel: systemChannel)]
        }

        let signature = "\(context.systemChannel)-\(midiChannel)-\(context.sourceID.uuidString)-\(context.number)-\(context.voice.bytes)-portamento-\(externalKeyboardPortamento)"
        guard preparedKeyboardVoiceSignature != signature || isKeyboardPreparationStale || !isAuditionBufferPrepared(signature: signature) else {
            return []
        }

        let artifact = try context.voice.instrumentVoiceArtifact(systemChannel: context.systemChannel, instrument: 0)
        preparedKeyboardVoiceSignature = signature
        preparedKeyboardVoiceDate = Date()
        markAuditionBufferPrepared(signature: signature)
        return [try artifact.sysexBytes]
            + (try keyboardAuditionPreparationMessages(systemChannel: context.systemChannel, midiChannel: midiChannel))
            + [try liveKeyboardPortamentoMessageBytes(value: externalKeyboardPortamento, systemChannel: context.systemChannel)]
    }

    private var isKeyboardPreparationStale: Bool {
        guard let preparedKeyboardVoiceDate else {
            return true
        }
        return Date().timeIntervalSince(preparedKeyboardVoiceDate) > keyboardPreparationStaleAfter
    }

    private func scheduleKeyboardVoicePreparation(delayNanoseconds: UInt64 = 0) {
        keyboardPreparationTask?.cancel()
        guard let context = selectedVoiceContext else {
            return
        }

        let midiChannel = min(max(keyboardChannel, 0), 15)
        let signature = "\(context.systemChannel)-\(midiChannel)-\(context.sourceID.uuidString)-\(context.number)-\(context.voice.bytes)-portamento-\(externalKeyboardPortamento)"
        guard preparedKeyboardVoiceSignature != signature || !isAuditionBufferPrepared(signature: signature) else {
            return
        }

        let destinationIndex = selectedDestinationIndex
        let systemChannel = context.systemChannel
        let voice = context.voice
        keyboardPreparationTask = Task(priority: .userInitiated) { [weak self] in
            do {
                if delayNanoseconds > 0 {
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                }
                try Task.checkCancellation()
                let artifact = try voice.instrumentVoiceArtifact(systemChannel: systemChannel, instrument: 0)
                let auditionMessages = try keyboardAuditionPreparationMessages(systemChannel: systemChannel, midiChannel: midiChannel)
                    + [try await MainActor.run {
                        try self?.liveKeyboardPortamentoMessageBytes(value: self?.externalKeyboardPortamento ?? 0, systemChannel: systemChannel)
                    }].compactMap { $0 }
                try await LiveMIDIPlaybackController.shared.sendPreparedMessages(
                    [try artifact.sysexBytes] + auditionMessages,
                    destinationIndex: destinationIndex,
                    settleDelay: 0
                )
                try Task.checkCancellation()
                await MainActor.run {
                    self?.preparedKeyboardVoiceSignature = signature
                    self?.preparedKeyboardVoiceDate = Date()
                    self?.markAuditionBufferPrepared(signature: signature)
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
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 430, height: 30))

        let text = NSTextField(labelWithString: label)
        text.frame = NSRect(x: 0, y: 6, width: 92, height: 18)
        text.alignment = .right

        popup.frame = NSRect(x: 104, y: 2, width: 326, height: 26)
        popup.autoresizingMask = [.width]

        container.addSubview(text)
        container.addSubview(popup)
        return container
    }

    private func makeWarningLabel(_ string: String, width: CGFloat = 330) -> NSTextField {
        let text = NSTextField(wrappingLabelWithString: string)
        text.textColor = .secondaryLabelColor
        text.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        text.maximumNumberOfLines = 3
        text.preferredMaxLayoutWidth = width
        text.frame = NSRect(x: 0, y: 0, width: width, height: 44)
        return text
    }

    private func chooseVoiceSlot(
        title: String,
        message: String,
        actionTitle: String,
        sourceID: LibrarySource.ID,
        currentNumber: Int
    ) -> VoiceSlotTarget? {
        let candidates = writableVoiceSlotTargets(sourceID: sourceID, currentNumber: currentNumber)
        guard !candidates.isEmpty else {
            let alert = NSAlert()
            alert.messageText = "No Writable Bank Targets Loaded"
            alert.informativeText = "Load or fetch Bank 1 or Bank 2 before copying voices into writable FB-01 bank slots."
            alert.addButton(withTitle: "OK")
            alert.alertStyle = .informational
            alert.runModal()
            return nil
        }

        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: actionTitle)
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        let preferredTarget = candidates.first { $0.sourceID == sourceID && $0.number > currentNumber } ?? candidates.first
        let picker = VoiceSlotPickerAccessory(
            targets: candidates,
            preferredTarget: preferredTarget,
            titleProvider: localVoiceSlotVoiceTitle
        )
        alert.accessoryView = picker
        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }

        return picker.selectedTarget
    }

    private func writableVoiceSlotTargets(sourceID: LibrarySource.ID, currentNumber: Int) -> [VoiceSlotTarget] {
        sources.flatMap { source -> [VoiceSlotTarget] in
            guard let voiceBank = source.voiceBankData,
                  FB01ModuleServices.shared.module.isWritableVoiceBank(FB01ModuleServices.shared.module.displayVoiceBank(forStorageBank: voiceBank.bank)) else {
                return []
            }

            return voiceBank.voices.compactMap { summary in
                guard source.id != sourceID || summary.number != currentNumber else {
                    return nil
                }
                return VoiceSlotTarget(
                    sourceID: source.id,
                    sourceTitle: source.title,
                    bank: voiceBank.bank,
                    number: summary.number
                )
            }
        }
        .sorted { lhs, rhs in
            if lhs.bank != rhs.bank {
                return lhs.bank < rhs.bank
            }
            return lhs.number < rhs.number
        }
    }

    func configurationInstrumentVoiceName(_ instrument: FB01InstrumentConfiguration) -> String? {
        voiceName(bank: instrument.voiceBank, voiceNumber: instrument.voiceNumber)
    }

    private func voiceName(bank: Int, voiceNumber: Int) -> String? {
        let candidateNumbers = candidateVoiceNumbers(fromStoredNumber: voiceNumber)

        if FB01ModuleServices.shared.module.isWritableVoiceBank(bank) {
            for number in candidateNumbers {
                if let names = ramVoiceNameCache[bank],
                   (1...names.count).contains(number) {
                    return names[number - 1]
                }
                if let voice = knownVoice(bank: bank - 1, number: number), !voice.name.isEmpty {
                    return voice.name
                }
            }
            return nil
        }

        for number in candidateNumbers {
            if let name = EditorSynthModule.module.factoryVoiceName(bank: bank, voiceNumber: number), !name.isEmpty {
                return name
            }
        }
        return nil
    }

    private func candidateVoiceNumbers(fromStoredNumber storedNumber: Int) -> [Int] {
        var candidates: [Int] = []
        for number in [storedNumber, storedNumber + 1] where (1...FB01VoiceBankData.voiceCount).contains(number) {
            if !candidates.contains(number) {
                candidates.append(number)
            }
        }
        return candidates
    }

    private func confirmEditedVoiceSlotOverwrite(operation: VoiceSlotOperation, source: LibrarySource, target: VoiceSlotTarget) -> Bool {
        let action = switch operation {
        case .copy: "Copy"
        case .swap: "Swap"
        }

        let alert = NSAlert()
        alert.messageText = "\(action) Over Edited Voice?"
        alert.informativeText = "Bank \(target.bank + 1) Voice \(target.number) in \(source.title) already has a local edit. Continuing will replace that local edited slot state. It will not write to disk or change the FB-01."
        alert.addButton(withTitle: action)
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func localVoiceSlotTitle(_ target: VoiceSlotTarget) -> String {
        guard let source = sources.first(where: { $0.id == target.sourceID }),
              let voiceBank = source.voiceBankData,
              let fallback = voiceBank.voices.first(where: { $0.number == target.number })?.voice else {
            return "Bank \(target.bank + 1) Voice \(target.number) - unknown"
        }

        let voice = self.voice(sourceID: target.sourceID, number: target.number, fallback: fallback)
        let name = voice.name.isEmpty ? "Untitled" : voice.name
        let edited = source.isVoiceEdited(number: target.number)
        return "Bank \(target.bank + 1) Voice \(target.number) - \(name)\(edited ? " (LOCAL EDIT)" : "")"
    }

    private func localVoiceSlotVoiceTitle(_ target: VoiceSlotTarget) -> String {
        guard let source = sources.first(where: { $0.id == target.sourceID }),
              let voiceBank = source.voiceBankData,
              let fallback = voiceBank.voices.first(where: { $0.number == target.number })?.voice else {
            return "Voice \(target.number) - unknown"
        }

        let voice = self.voice(sourceID: target.sourceID, number: target.number, fallback: fallback)
        let name = voice.name.isEmpty ? "Untitled" : voice.name
        let edited = source.isVoiceEdited(number: target.number)
        return "Voice \(target.number) - \(name)\(edited ? " (LOCAL EDIT)" : "")"
    }

    func configurationSlotMenuTitle(slot: Int) -> String {
        let userNumber = slot + 1
        guard let source = sources.first(where: { $0.storedConfigurationNumber == slot }),
              let configuration = source.editableConfigurationPayload else {
            return "Configuration \(userNumber) - unknown current contents"
        }
        let name = configuration.name.isEmpty ? "Untitled" : configuration.name
        let state = source.isEdited ? "LOCAL EDIT" : source.origin.displayName
        return "Configuration \(userNumber) - \(name) (\(state))"
    }

    private func voiceDisplayName(_ voice: FB01VoiceData) -> String {
        voice.name.isEmpty ? "the selected voice" : "\"\(voice.name)\""
    }

    private func chooseGeneralMIDITargetBank() -> Int? {
        let alert = NSAlert()
        alert.messageText = "Store General MIDI voices"
        alert.informativeText = "Choose the writable FB-01 bank that will receive the 48 General MIDI voice mappings."
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 220, height: 26), pullsDown: false)
        for bank in FB01ModuleServices.shared.module.writableVoiceBanks {
            popup.addItem(withTitle: "Bank \(bank)")
            popup.lastItem?.representedObject = bank
        }
        alert.accessoryView = labelledEditorPopup(label: "Bank:", popup: popup)

        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }
        return popup.selectedItem?.representedObject as? Int
    }

    private func confirmGeneralMIDIOverwrite(targetBank: Int) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Overwrite Bank \(targetBank) with General MIDI voices?"
        alert.informativeText = "This will destroy the current contents of FB-01 Bank \(targetBank). The app will first save a backup of the current bank, then write and verify all 48 General MIDI mapped voices."
        alert.addButton(withTitle: "Overwrite Bank \(targetBank)")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .critical
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func showFactoryResetInstructions() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let controller = DoneDialogController()
        panel.title = "Reset Instructions"
        panel.isReleasedWhenClosed = false
        panel.center()

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 300))
        panel.contentView = content

        let icon = NSImageView(frame: NSRect(x: 32, y: 118, width: 64, height: 64))
        icon.image = NSImage(named: NSImage.cautionName)
        icon.imageScaling = .scaleProportionallyUpOrDown
        content.addSubview(icon)

        let titleLabel = NSTextField(labelWithString: "Reset Instructions")
        titleLabel.font = .boldSystemFont(ofSize: 16)
        titleLabel.frame = NSRect(x: 120, y: 250, width: 480, height: 22)
        content.addSubview(titleLabel)

        let instructions = NSTextField(wrappingLabelWithString: """
        To restore the factory presets and clear user-defined sounds and possible SRAM corruption:

        1. Turn the FB-01 OFF.
        2. Hold System Setup + Inst Select + Data Entry No/-1.
        3. While holding all three buttons, turn the FB-01 ON.
        4. Keep holding until the display counter reaches FFFFFFFF and then shows END.
        5. Release the buttons, turn the FB-01 OFF, then turn it ON again.
        """)
        instructions.font = .systemFont(ofSize: 13)
        instructions.textColor = .labelColor
        instructions.frame = NSRect(x: 120, y: 74, width: 480, height: 168)
        content.addSubview(instructions)

        let doneButton = NSButton(title: "Done", target: nil, action: nil)
        doneButton.frame = NSRect(x: 520, y: 24, width: 86, height: 30)
        doneButton.bezelStyle = .rounded
        doneButton.keyEquivalent = "\r"
        doneButton.target = controller
        doneButton.action = #selector(DoneDialogController.done)
        content.addSubview(doneButton)

        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.runModal(for: panel)
        panel.orderOut(nil)
    }

    private func fetchGeneralMIDISourceVoices(
        sourceIndex: Int,
        destinationIndex: Int,
        systemChannel: Int,
        progressPanel: EditorProgressPanel
    ) async throws -> [Int: FB01VoiceData] {
        let mappings = FB01GeneralMIDI.mappings
        let sourceBanks = Set(mappings.map(\.sourceBank)).sorted()
        var banks: [Int: FB01VoiceBankData] = [:]

        for bank in sourceBanks {
            try Task.checkCancellation()
            if let cachedBank = cachedVoiceBanks[bank] {
                banks[bank] = cachedBank
                statusMessage = "Using cached source Bank \(bank) for General MIDI store..."
                progressPanel.update(message: "The voices are being stored. Please wait.\nUsing cached source Bank \(bank)...")
                continue
            }

            statusMessage = "Fetching source Bank \(bank) for General MIDI store..."
            progressPanel.update(message: "The voices are being stored. Please wait.\nFetching source Bank \(bank) from the FB-01...")
            let bytes = try await Task.detached(priority: .userInitiated) {
                try FB01MIDI.request(
                    .voiceBank(bank),
                    sourceIndex: sourceIndex,
                    destinationIndex: destinationIndex,
                    systemChannel: systemChannel,
                    timeout: 15
                )
            }.value
            let bankData = try voiceBankData(from: bytes, expectedBankNumber: bank)
            banks[bank] = bankData
            cachedVoiceBanks[bank] = bankData
        }
        try Task.checkCancellation()

        return try Dictionary(uniqueKeysWithValues: mappings.map { mapping -> (Int, FB01VoiceData) in
            guard let voice = banks[mapping.sourceBank]?.voices.first(where: { $0.number == mapping.sourceVoice })?.voice else {
                throw FB01AppError.message("Missing source Bank \(mapping.sourceBank) Voice \(mapping.sourceVoice) for GM \(mapping.gmNumber) \(mapping.gmName).")
            }
            return (mapping.gmNumber, voice)
        })
    }

    private func generalMIDIMismatches(readback: FB01VoiceBankData, targetBank: Int, selectedVoices: [Int: FB01VoiceData]) -> [String] {
        FB01GeneralMIDI.mappings.compactMap { mapping -> String? in
            guard let expected = selectedVoices[mapping.gmNumber],
                  let actual = readback.voices.first(where: { $0.number == mapping.gmNumber })?.voice else {
                return "Bank \(targetBank) Voice \(mapping.gmNumber): missing readback"
            }
            guard actual.bytes == expected.bytes else {
                return "Bank \(targetBank) Voice \(mapping.gmNumber): expected \(expected.name), got \(actual.name)"
            }
            return nil
        }
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
        let module = FB01ModuleServices.shared.module
        guard (0..<module.writableVoiceSlotCount).contains(slot) else {
            return nil
        }

        let bank = slot / module.voicesPerBank
        let number = slot % module.voicesPerBank + 1

        guard let voice = knownVoice(bank: bank, number: number) else {
            return nil
        }

        let name = voice.name.isEmpty ? "Untitled" : voice.name
        return "Voice \(slot + 1) - Bank \(bank + 1) #\(number): \(name)"
    }

    private func knownVoice(bank: Int, number: Int) -> FB01VoiceData? {
        if let cachedVoiceBank = cachedVoiceBanks[bank + 1],
           let cachedVoice = cachedVoiceBank.voices.first(where: { $0.number == number })?.voice {
            return cachedVoice
        }

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
    case noVoiceSource
    case noConfigurationSource
    case readOnlyConfigurationSlot
    case message(String)
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

struct ConfigurationStoreOptions {
    var slot: Int
    var backupURL: URL?
    var confirmAfterStore: Bool
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

    var voiceSystemChannel: Int? {
        guard artifact.messages.count == 1 else {
            return nil
        }

        switch artifact.messages[0] {
        case let .instrumentVoiceDump(systemChannel, _, _),
             let .voiceRAMDumpData(systemChannel, _, _, _),
             let .voiceBankDumpData(systemChannel, _, _, _, _):
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

extension UTType {
    private static var synthFileProfile: SynthFileProfile {
        EditorSynthModule.fileProfile
    }

    static let sysex = UTType(filenameExtension: "syx")!
    static var fb01GenericSysEx: UTType { UTType(filenameExtension: synthFileProfile.genericSysExExtension)! }
    static var fb01SingleVoice: UTType { UTType(filenameExtension: synthFileProfile.singleVoiceExtension)! }
    static var fb01SingleConfiguration: UTType { UTType(filenameExtension: synthFileProfile.singleConfigurationExtension)! }
    static var fb01VoiceBank: UTType { UTType(filenameExtension: synthFileProfile.voiceBankExtension)! }
    static var fb01ConfigurationBank: UTType { UTType(filenameExtension: synthFileProfile.configurationBankExtension)! }

    static var fb01VoiceFileTypes: [UTType] {
        [.fb01SingleVoice, .fb01GenericSysEx]
    }

    static var fb01ConfigurationFileTypes: [UTType] {
        [.fb01SingleConfiguration, .fb01GenericSysEx]
    }

    static var fb01ReadableVoiceFileTypes: [UTType] {
        [.fb01SingleVoice, .fb01VoiceBank, .fb01GenericSysEx, .sysex, .data]
    }

    static var fb01ReadableConfigurationFileTypes: [UTType] {
        [.fb01SingleConfiguration, .fb01ConfigurationBank, .fb01GenericSysEx, .sysex, .data]
    }

    static var fb01ReadableFileTypes: [UTType] {
        [
            .fb01SingleVoice,
            .fb01SingleConfiguration,
            .fb01VoiceBank,
            .fb01ConfigurationBank,
            .fb01GenericSysEx,
            .sysex,
            .data,
        ]
    }

    static var currentModuleVoiceFileTypes: [UTType] {
        fb01VoiceFileTypes
    }

    static var currentModuleConfigurationFileTypes: [UTType] {
        fb01ConfigurationFileTypes
    }

    static var currentModuleReadableVoiceFileTypes: [UTType] {
        fb01ReadableVoiceFileTypes
    }

    static var currentModuleReadableConfigurationFileTypes: [UTType] {
        fb01ReadableConfigurationFileTypes
    }

    static var currentModuleReadableFileTypes: [UTType] {
        fb01ReadableFileTypes
    }

    static var currentModuleVoiceBankFileTypes: [UTType] {
        [.fb01VoiceBank, .fb01GenericSysEx]
    }

    static var currentModuleConfigurationBankFileTypes: [UTType] {
        [.fb01ConfigurationBank, .fb01GenericSysEx]
    }

    static var currentModuleGenericSysExFileTypes: [UTType] {
        [.fb01GenericSysEx, .sysex, .data]
    }
}

private func preferredFileExtension(for kind: FB01ArtifactKind) -> String {
    let profile = EditorSynthModule.fileProfile
    switch kind {
    case .singleVoice:
        return profile.singleVoiceExtension
    case .voiceBank:
        return profile.voiceBankExtension
    case .currentConfiguration, .storedConfiguration:
        return profile.singleConfigurationExtension
    case .configurationSet:
        return profile.configurationBankExtension
    case .unitID, .rawSysEx:
        return profile.genericSysExExtension
    }
}

private func allowedContentTypes(for kind: FB01ArtifactKind) -> [UTType] {
    switch kind {
    case .singleVoice:
        return UTType.currentModuleVoiceFileTypes
    case .voiceBank:
        return UTType.currentModuleVoiceBankFileTypes
    case .currentConfiguration, .storedConfiguration:
        return UTType.currentModuleConfigurationFileTypes
    case .configurationSet:
        return UTType.currentModuleConfigurationBankFileTypes
    case .unitID, .rawSysEx:
        return UTType.currentModuleGenericSysExFileTypes
    }
}

extension FB01ArtifactKind {
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

extension FB01SysExMessage {
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

extension FB01KeyCodeReceiveMode {
    var displayName: String {
        switch self {
        case .all: "All"
        case .even: "Even"
        case .odd: "Odd"
        case .unknown: "Unknown"
        }
    }
}

extension Int {
    var lfoWaveformDisplayName: String {
        switch self {
        case 0: "Sawtooth"
        case 1: "Square"
        case 2: "Triangle"
        case 3: "Random"
        default: "Unknown"
        }
    }
}

extension FB01MonoPolyMode {
    var displayName: String {
        switch self {
        case .poly: "Poly"
        case .mono: "Mono"
        case .unknown: "Unknown"
        }
    }
}

extension FB01PMDControllerAssignment {
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

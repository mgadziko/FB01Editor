import Foundation
import Testing
@testable import FB01Editor
@testable import FB01EditorApp

@MainActor
@Test func documentExtractionBuildsVoiceCandidatesFromBankDump() throws {
    let fixtureURL = Bundle.module.url(
        forResource: "voice-bank-1",
        withExtension: "syx",
        subdirectory: "Fixtures"
    )!
    let artifact = try FB01Artifact.readSysEx(from: fixtureURL)
    let candidates = try EditorDocumentExtraction.voiceCandidates(from: artifact)

    #expect(candidates.count == 48)
    #expect(candidates[0].title == "Bank 1 Voice 1: Brass")
    #expect(candidates[0].voice.name == "Brass")
    #expect(candidates[1].voice.name == "Horn")
}

@MainActor
@Test func documentExtractionBuildsConfigurationCandidatesFromCurrentDump() throws {
    let fixtureURL = Bundle.module.url(
        forResource: "current-configuration-single",
        withExtension: "syx",
        subdirectory: "Fixtures"
    )!
    let artifact = try FB01Artifact.readSysEx(from: fixtureURL)
    let candidates = try EditorDocumentExtraction.configurationCandidates(from: artifact)

    #expect(candidates.count == 1)
    #expect(candidates[0].title == "Current Configuration: single")
    #expect(candidates[0].configuration.name == "single")
}

@MainActor
@Test func editorDocumentWorkspaceRemovesClosedDocuments() {
    let workspace = EditorDocumentWorkspace()
    let voiceID = workspace.createVoiceDocument()
    let configurationID = workspace.createConfigurationDocument()

    #expect(workspace.voiceDocument(id: voiceID) != nil)
    #expect(workspace.configurationDocument(id: configurationID) != nil)

    workspace.closeVoiceDocument(id: voiceID)
    workspace.closeConfigurationDocument(id: configurationID)

    #expect(workspace.voiceDocument(id: voiceID) == nil)
    #expect(workspace.configurationDocument(id: configurationID) == nil)
}

@MainActor
@Test func editorDocumentWorkspaceAppliesInitialStatusMessages() throws {
    let workspace = EditorDocumentWorkspace()
    let voiceID = workspace.createVoiceDocument(statusMessage: "Created from selected library voice.")
    let configurationID = workspace.createConfigurationDocument(statusMessage: "Created from selected library configuration.")

    let voice = try #require(workspace.voiceDocument(id: voiceID))
    let configuration = try #require(workspace.configurationDocument(id: configurationID))

    #expect(voice.statusMessage == "Created from selected library voice.")
    #expect(configuration.statusMessage == "Created from selected library configuration.")
}

@MainActor
@Test func editorDocumentTitlesShowBusyAndUnsavedState() throws {
    var voiceData = try FB01VoiceData(bytes: Array(repeating: 0x00, count: FB01VoiceData.byteCount))
    voiceData = try voiceData.settingName("TITLE")
    let voice = VoiceDocumentModel(voice: voiceData, systemChannel: 0)
    #expect(voice.title == "TITLE")

    voice.updateVoice { try $0.settingName("EDIT") }
    #expect(voice.title == "EDIT *")

    voice.isBusy = true
    #expect(voice.title == "EDIT (Working)")

    var configurationData = try FB01ConfigurationData(bytes: Array(repeating: 0x00, count: FB01ConfigurationData.byteCount))
    configurationData = try configurationData.settingName("CONFIG")
    let configuration = ConfigurationDocumentModel(configuration: configurationData, systemChannel: 0)
    #expect(configuration.title == "CONFIG")

    configuration.updateConfiguration { try $0.settingName("CHANGED") }
    #expect(configuration.title == "CHANGED *")

    configuration.isBusy = true
    #expect(configuration.title == "CHANGED (Working)")
}

@MainActor
@Test func voiceDocumentMapsOxygenC1ThroughC6ToCurrentOperatorEnvelope() throws {
    let voiceData = try FB01VoiceData(bytes: Array(repeating: 0x00, count: FB01VoiceData.byteCount))
    let voice = VoiceDocumentModel(voice: voiceData, systemChannel: 0)
    let device = DocumentModel()
    voice.selectedOperatorIndex = 2

    #expect(voice.receiveExternalKeyboardMessage([0xBF, 0x5B, 127], device: device))
    #expect(voice.receiveExternalKeyboardMessage([0xBF, 0x5D, 127], device: device))
    #expect(voice.receiveExternalKeyboardMessage([0xBF, 0x1A, 127], device: device))
    #expect(voice.receiveExternalKeyboardMessage([0xBF, 0x1E, 127], device: device))
    #expect(voice.receiveExternalKeyboardMessage([0xBF, 0x1B, 127], device: device))
    #expect(voice.receiveExternalKeyboardMessage([0xBF, 0x1D, 127], device: device))

    let operatorData = try #require(voice.voice.operators.first { $0.index == 2 })
    #expect(operatorData.attackRate == 31)
    #expect(operatorData.velocitySensitivityForAttackRate == 7)
    #expect(operatorData.decay1Rate == 15)
    #expect(operatorData.decay2Rate == 31)
    #expect(operatorData.sustainLevel == 15)
    #expect(operatorData.releaseRate == 15)

    let unaffectedOperator = try #require(voice.voice.operators.first { $0.index == 1 })
    #expect(unaffectedOperator.attackRate == 0)
    #expect(unaffectedOperator.releaseRate == 0)
}

@MainActor
@Test func voiceAndConfigurationDocumentReplacementResetsSavedBaseline() throws {
    var originalVoice = try FB01VoiceData(bytes: Array(repeating: 0x00, count: FB01VoiceData.byteCount))
    originalVoice = try originalVoice.settingName("ORIG")
    var replacementVoice = try originalVoice.settingName("NEW")
    replacementVoice = try replacementVoice.replacingOperator(replacementVoice.operators[0].settingAttackRate(12))

    let voice = VoiceDocumentModel(voice: originalVoice, systemChannel: 0)
    voice.voice = replacementVoice
    voice.savedVoice = replacementVoice
    #expect(!voice.isEdited)

    voice.updateVoice { try $0.settingName("EDIT") }
    #expect(voice.isEdited)

    var originalConfiguration = try FB01ConfigurationData(bytes: Array(repeating: 0x00, count: FB01ConfigurationData.byteCount))
    originalConfiguration = try originalConfiguration.settingName("ORIG")
    var replacementConfiguration = try originalConfiguration.settingName("NEW")
    replacementConfiguration = try replacementConfiguration.settingLFOSpeed(99)

    let configuration = ConfigurationDocumentModel(configuration: originalConfiguration, systemChannel: 0)
    configuration.configuration = replacementConfiguration
    configuration.savedConfiguration = replacementConfiguration
    #expect(!configuration.isEdited)

    configuration.updateConfiguration { try $0.settingName("EDIT") }
    #expect(configuration.isEdited)
}

@Test func factoryVoiceNameLookupUsesROMBankNames() {
    #expect(FB01FactoryVoiceNames.namesByBank.keys.sorted() == [3, 4, 5, 6, 7])
    #expect(FB01FactoryVoiceNames.namesByBank.values.allSatisfy { $0.count == FB01VoiceBankData.voiceCount })
    #expect(FB01FactoryVoiceNames.name(bank: 3, voiceNumber: 1) == "Brass")
    #expect(FB01FactoryVoiceNames.name(bank: 4, voiceNumber: 48) == "Squeeze")
    #expect(FB01FactoryVoiceNames.name(bank: 7, voiceNumber: 40) == "Wave")
    #expect(FB01FactoryVoiceNames.name(bank: 1, voiceNumber: 1) == nil)
}

@Test func generalMIDIMappingCoversFortyEightVoices() {
    let mappings = FB01GeneralMIDI.mappings
    #expect(mappings.map(\.gmNumber) == Array(1...48))
    #expect(Set(mappings.map(\.sourceBank)).isSubset(of: Set(3...7)))
    #expect(mappings.allSatisfy { (1...FB01VoiceBankData.voiceCount).contains($0.sourceVoice) })
}

@Test func voiceFetchLookupPrefersLiveRAMNamesAndUsesROMFallbacks() {
    let lookup = VoiceDocumentFetchNameLookup(ramBankNames: [
        1: ["RAMONE"] + Array(repeating: "Other", count: FB01VoiceBankData.voiceCount - 1),
    ])

    #expect(lookup.voiceMenuTitle(location: .bank(1), voiceNumber: 1) == "01 RAMONE")
    #expect(lookup.voiceMenuTitle(location: .bank(3), voiceNumber: 1) == "01 Brass")
    #expect(lookup.voiceMenuTitle(location: .voiceRAM1, voiceNumber: 1) == "Voice 1")
}

@Test func configurationFetchLookupUsesFactoryReadOnlyNames() {
    let lookup = ConfigurationFetchNameLookup(storedNames: [1: "USER 1"])

    #expect(lookup.menuTitle(slot: 1) == "Configuration 1 - USER 1")
    #expect(lookup.menuTitle(slot: 17) == "Configuration 17 - single Read Only")
    #expect(lookup.menuTitle(slot: 18) == "Configuration 18 - mono 8 Read Only")
    #expect(lookup.menuTitle(slot: 20) == "Configuration 20 - split Read Only")
    #expect(lookup.menuTitle(slot: 8) == "Configuration 8")
}

@MainActor
@Test func selectedLibraryVoicePayloadUsesCurrentVoiceSelection() throws {
    let model = DocumentModel()
    let source = try fixtureVoiceBankSource()
    model.sources = [source]
    model.selectedSourceID = source.id
    model.selectVoice(sourceID: source.id, number: 2)

    let payload = try #require(model.selectedVoiceDocumentPayload())

    #expect(payload.voice.name == "Horn")
    #expect(payload.systemChannel == 0)
}

@MainActor
@Test func selectedLibraryVoiceDocumentCreationIsDisabledWhileBusy() throws {
    let model = DocumentModel()
    let source = try fixtureVoiceBankSource()
    model.sources = [source]
    model.selectedSourceID = source.id

    #expect(model.canOpenSelectedVoiceAsDocument)

    model.isFetchingFromDevice = true
    #expect(!model.canOpenSelectedVoiceAsDocument)
}

@MainActor
@Test func selectedLibraryVoicePayloadIsNilWithoutVoiceSelection() throws {
    let model = DocumentModel()
    let source = try fixtureConfigurationSource(origin: .liveFetch)
    model.sources = [source]
    model.selectedSourceID = source.id

    #expect(model.selectedVoiceDocumentPayload() == nil)
}

@MainActor
@Test func selectedLibraryConfigurationPayloadUsesEditableConfiguration() throws {
    let model = DocumentModel()
    let source = try fixtureConfigurationSource(origin: .liveFetch)
    model.sources = [source]
    model.selectedSourceID = source.id

    let payload = try #require(model.selectedConfigurationDocumentPayload())

    #expect(payload.configuration.name == "single")
    #expect(payload.systemChannel == 0)
}

@MainActor
@Test func selectedLibraryConfigurationDocumentCreationIsDisabledWhileBusy() throws {
    let model = DocumentModel()
    let source = try fixtureConfigurationSource(origin: .liveFetch)
    model.sources = [source]
    model.selectedSourceID = source.id

    #expect(model.canOpenSelectedConfigurationAsDocument)

    model.isFetchingConfigurations = true
    #expect(!model.canOpenSelectedConfigurationAsDocument)
}

@MainActor
@Test func selectedLibraryConfigurationLocalActionsReflectSelectionAndBusyState() throws {
    let model = DocumentModel()
    let source = try fixtureConfigurationSource(origin: .liveFetch)
    model.sources = [source]
    model.selectedSourceID = source.id

    #expect(model.canCreateLibraryConfigurationFromSelected)
    #expect(model.canDuplicateSelectedLibraryConfiguration)
    #expect(model.canSaveSelectedLibraryConfigurationAs)

    model.isFetchingConfigurations = true
    #expect(!model.canCreateLibraryConfigurationFromSelected)
    #expect(!model.canDuplicateSelectedLibraryConfiguration)
    #expect(!model.canSaveSelectedLibraryConfigurationAs)
}

@MainActor
@Test func selectedLibraryConfigurationLocalActionsRejectVoiceBankSelection() throws {
    let model = DocumentModel()
    let source = try fixtureVoiceBankSource()
    model.sources = [source]
    model.selectedSourceID = source.id

    #expect(!model.canCreateLibraryConfigurationFromSelected)
    #expect(!model.canDuplicateSelectedLibraryConfiguration)
    #expect(!model.canSaveSelectedLibraryConfigurationAs)
}

@MainActor
@Test func createConfigurationDocumentFromSelectedAddsLocalLibraryItem() throws {
    let model = DocumentModel()
    let source = try fixtureConfigurationSource(origin: .liveFetch)
    model.sources = [source]
    model.selectedSourceID = source.id

    model.createConfigurationDocumentFromSelected()

    #expect(model.sources.count == 2)
    let created = try #require(model.sources.last)
    #expect(model.selectedSourceID == created.id)
    #expect(created.title == "single Document")
    #expect(created.isLocalConfigurationDocument)
    #expect(created.displaySubtitle == "Local Document - Unsaved")
    #expect(model.statusMessage == "Created local configuration document.")
}

@MainActor
@Test func selectedLibraryConfigurationPayloadIsNilForVoiceBankSelection() throws {
    let model = DocumentModel()
    let source = try fixtureVoiceBankSource()
    model.sources = [source]
    model.selectedSourceID = source.id

    #expect(model.selectedConfigurationDocumentPayload() == nil)
}

@MainActor
@Test func configurationDocumentDuplicateUsesCurrentPayloadAndStatus() throws {
    let model = DocumentModel()
    let source = try fixtureConfigurationSource(origin: .liveFetch)
    model.sources = [source]
    model.selectedSourceID = source.id

    let original = try #require(source.editableConfigurationPayload)
    let edited = try original
        .settingName("COPYCFG")
        .settingCombineModeEnabled(true)
    let duplicateID = try model.createConfigurationDocument(
        sourceID: source.id,
        configuration: edited,
        title: "Copy Config",
        origin: .duplicatedConfiguration
    )

    let duplicate = try #require(model.sources.first { $0.id == duplicateID })
    #expect(model.selectedSourceID == duplicateID)
    #expect(duplicate.title == "Copy Config")
    #expect(duplicate.isLocalConfigurationDocument)
    #expect(duplicate.displaySubtitle == "Duplicated Document - Unsaved")

    let duplicatePayload = try #require(duplicate.editableConfigurationPayload)
    #expect(duplicatePayload.name == "COPYCFG")
    #expect(duplicatePayload.combineModeEnabled)
}

@MainActor
@Test func editedConfigurationArtifactRoundTripsForSaving() throws {
    let model = DocumentModel()
    let source = try fixtureConfigurationSource(origin: .loadedFromDisk)
    model.sources = [source]

    let original = try #require(source.editableConfigurationPayload)
    let edited = try original
        .settingName("SAVEAS")
        .settingLFOSpeed(91)
        .replacingInstrument(
            original.instruments[0]
                .settingVoiceBank(6)
                .settingVoiceNumber(33)
        )

    model.updateConfiguration(sourceID: source.id, configuration: edited)
    let savedArtifact = try model.configurationArtifactForSaving(sourceID: source.id)

    guard case let .currentConfigurationDump(_, packet) = savedArtifact.messages.first else {
        Issue.record("Expected current configuration artifact")
        return
    }

    let reparsed = try FB01ConfigurationData(bytes: packet.payload)
    #expect(packet.checksum == FB01.checksum(for: edited.bytes))
    #expect(reparsed.name == "SAVEAS")
    #expect(reparsed.lfoSpeed == 91)
    #expect(reparsed.instruments[0].voiceBank == 6)
    #expect(reparsed.instruments[0].voiceNumber == 33)
}

@MainActor
@Test func configurationSourceStatusLabelsReflectOriginAndSaveState() throws {
    var local = try fixtureConfigurationSource(origin: .localDocument)
    local.subtitle = "Local Configuration Document"
    #expect(local.displaySubtitle == "Local Document - Unsaved")

    let configuration = try #require(local.editableConfigurationPayload)
    local.editedConfiguration = try configuration.settingName("EDITED")
    #expect(local.displaySubtitle == "Local Document - Edited")

    local.markSaved(
        as: try local.artifactForSaving(),
        fileURL: URL(fileURLWithPath: "/tmp/edited-config.syx")
    )
    #expect(local.displaySubtitle == "Local Document - Saved")

    var fetched = try fixtureConfigurationSource(origin: .liveFetch)
    fetched.editedConfiguration = try configuration.settingName("FETCHED")
    #expect(fetched.displaySubtitle == "FB-01 Live Fetch - Edited")
}

@MainActor
@Test func currentConfigurationSendBytesAreNonStoreDumpOnly() throws {
    let model = DocumentModel()
    let source = try fixtureConfigurationSource(origin: .liveFetch)
    let configuration = try #require(source.editableConfigurationPayload)

    let bytes = try model.currentConfigurationMessageBytes(payload: configuration, systemChannel: 2)
    let message = try FB01SysExMessage(bytes: bytes)

    guard case let .currentConfigurationDump(systemChannel, packet) = message else {
        Issue.record("Expected current configuration dump bytes")
        return
    }

    #expect(systemChannel == 2)
    #expect(packet.payload == configuration.bytes)
}

@MainActor
@Test func currentConfigurationSendAndConfirmMessagesSendThenRequestCurrentConfiguration() throws {
    let model = DocumentModel()
    let source = try fixtureConfigurationSource(origin: .liveFetch)
    let configuration = try #require(source.editableConfigurationPayload)

    let messages = try model.currentConfigurationSendAndConfirmMessages(payload: configuration, systemChannel: 3)
    #expect(messages.count == 2)

    guard case let .currentConfigurationDump(systemChannel, packet) = try FB01SysExMessage(bytes: messages[0]) else {
        Issue.record("Expected current configuration send dump")
        return
    }
    #expect(systemChannel == 3)
    #expect(packet.payload == configuration.bytes)

    #expect(try FB01SysExMessage(bytes: messages[1]) == .command(.requestCurrentConfiguration(systemChannel: 3)))
}

@MainActor
@Test func storeConfigurationMessagesTurnProtectOffThenSendCurrentThenStoreWritableSlot() throws {
    let model = DocumentModel()
    let source = try fixtureConfigurationSource(origin: .liveFetch)
    let configuration = try #require(source.editableConfigurationPayload)

    let messages = try model.storeConfigurationMessages(payload: configuration, systemChannel: 1, slot: 15)
    #expect(messages.count == 3)
    #expect(try FB01SysExMessage(bytes: messages[0]) == .command(.setMemoryProtect(systemChannel: 1, .off)))

    guard case let .currentConfigurationDump(systemChannel, packet) = try FB01SysExMessage(bytes: messages[1]) else {
        Issue.record("Expected current configuration send dump")
        return
    }
    #expect(systemChannel == 1)
    #expect(packet.payload == configuration.bytes)
    #expect(try FB01SysExMessage(bytes: messages[2]) == .command(.storeCurrentConfiguration(systemChannel: 1, number: 15)))
}

@MainActor
@Test func storeConfigurationMessagesRejectReadOnlySlots() throws {
    let model = DocumentModel()
    let source = try fixtureConfigurationSource(origin: .liveFetch)
    let configuration = try #require(source.editableConfigurationPayload)

    #expect(throws: FB01AppError.self) {
        _ = try model.storeConfigurationMessages(payload: configuration, systemChannel: 0, slot: 16)
    }
}

@MainActor
@Test func storeVoiceMessagesTurnProtectOffThenSendVoiceThenStoreWritableSlot() throws {
    let model = DocumentModel()
    let voice = try FB01VoiceData(bytes: Array(repeating: 0x00, count: FB01VoiceData.byteCount))

    let messages = try model.storeVoiceMessages(voice: voice, systemChannel: 2, instrument: 3, voiceSlot: 47)
    #expect(messages.count == 3)
    #expect(try FB01SysExMessage(bytes: messages[0]) == .command(.setMemoryProtect(systemChannel: 2, .off)))

    guard case let .instrumentVoiceDump(systemChannel, instrument, packet) = try FB01SysExMessage(bytes: messages[1]) else {
        Issue.record("Expected instrument voice send dump")
        return
    }
    #expect(systemChannel == 2)
    #expect(instrument == 3)
    #expect(try FB01.nibbleDecode(packet.payload) == voice.bytes)
    #expect(try FB01SysExMessage(bytes: messages[2]) == .command(.storeCurrentInstrumentVoice(systemChannel: 2, instrument: 3, voiceNumber: 47)))
}

@MainActor
@Test func voiceStoreReadbackMapsSlotsToRAMBanks() throws {
    let model = DocumentModel()

    #expect(try model.voiceRAMBankRequestKind(forVoiceSlot: 0) == .voiceBank(1))
    #expect(try model.voiceRAMBankRequestKind(forVoiceSlot: 47) == .voiceBank(1))
    #expect(try model.voiceRAMBankRequestKind(forVoiceSlot: 48) == .voiceBank(2))
    #expect(try model.voiceRAMBankRequestKind(forVoiceSlot: 95) == .voiceBank(2))

    #expect(throws: FB01SysExError.self) {
        _ = try model.voiceRAMBankRequestKind(forVoiceSlot: 96)
    }
}

@MainActor
@Test func storedVoicePayloadExtractsVoiceFromFetchedBank() throws {
    let model = DocumentModel()
    let fixtureURL = Bundle.module.url(
        forResource: "voice-bank-1",
        withExtension: "syx",
        subdirectory: "Fixtures"
    )!
    let artifact = try FB01Artifact.readSysEx(from: fixtureURL)
    let bytes = try artifact.sysexBytes

    let firstVoice = try #require(try model.storedVoicePayload(from: [bytes], voiceSlot: 0))
    let secondVoice = try #require(try model.storedVoicePayload(from: [bytes], voiceSlot: 1))

    #expect(firstVoice.name == "Brass")
    #expect(secondVoice.name == "Horn")
    #expect(try model.storedVoicePayload(from: [bytes], voiceSlot: 48) == nil)
}

@MainActor
@Test func systemChannelSelectionClampsToFB01Range() {
    let model = DocumentModel()

    model.setSystemChannel(12)
    #expect(model.systemChannel == 12)

    model.setSystemChannel(-1)
    #expect(model.systemChannel == 0)

    model.setSystemChannel(99)
    #expect(model.systemChannel == 15)
}

@MainActor
@Test func systemControlMessagesUseSelectedSystemChannel() throws {
    let model = DocumentModel()
    model.setSystemChannel(4)

    #expect(try model.systemMemoryProtectMessageBytes(enabled: false) == [0xF0, 0x43, 0x75, 0x04, 0x10, 0x21, 0x00, 0xF7])
    #expect(try model.systemMemoryProtectMessageBytes(enabled: true) == [0xF0, 0x43, 0x75, 0x04, 0x10, 0x21, 0x01, 0xF7])
    #expect(try model.systemMasterOutputMessageBytes(level: 200) == [0xF0, 0x43, 0x75, 0x04, 0x10, 0x24, 0x7F, 0xF7])
}

@MainActor
@Test func configurationSlotMenuTitleShowsKnownNamesAndUnknowns() throws {
    let model = DocumentModel()
    let source = try storedConfigurationSource(number: 2, name: "SLOT3", origin: .liveFetch)
    model.sources = [source]

    #expect(model.configurationSlotMenuTitle(slot: 2) == "Configuration 3 - SLOT3 (Fetched from FB-01)")
    #expect(model.configurationSlotMenuTitle(slot: 7) == "Configuration 8 - unknown current contents")

    var editedSource = source
    let configuration = try #require(editedSource.editableConfigurationPayload)
    editedSource.editedConfiguration = try configuration.settingName("EDIT3")
    model.sources = [editedSource]
    #expect(model.configurationSlotMenuTitle(slot: 2) == "Configuration 3 - EDIT3 (LOCAL EDIT)")
}

private func fixtureConfigurationSource(origin: LibrarySourceOrigin) throws -> LibrarySource {
    let fixtureURL = Bundle.module.url(
        forResource: "current-configuration-single",
        withExtension: "syx",
        subdirectory: "Fixtures"
    )!
    return LibrarySource(
        title: "Current Configuration",
        subtitle: origin == .liveFetch ? "FB-01 Live Fetch" : "current-configuration-single.syx",
        artifact: try FB01Artifact.readSysEx(from: fixtureURL),
        origin: origin
    )
}

private func fixtureVoiceBankSource() throws -> LibrarySource {
    let fixtureURL = Bundle.module.url(
        forResource: "voice-bank-1",
        withExtension: "syx",
        subdirectory: "Fixtures"
    )!
    return LibrarySource(
        title: "Bank 1",
        subtitle: "voice-bank-1.syx",
        artifact: try FB01Artifact.readSysEx(from: fixtureURL),
        origin: .loadedFromDisk
    )
}

private func storedConfigurationSource(number: Int, name: String, origin: LibrarySourceOrigin) throws -> LibrarySource {
    let current = try fixtureConfigurationSource(origin: origin)
    let configuration = try #require(current.editableConfigurationPayload).settingName(name)
    let artifact = FB01Artifact(message: .configurationDump(
        systemChannel: 0,
        number: number,
        packet: try FB01SysExPacket(payload: configuration.bytes)
    ))
    return LibrarySource(
        title: "Configuration \(number + 1)",
        subtitle: "FB-01 Stored Configuration",
        artifact: artifact,
        origin: origin
    )
}

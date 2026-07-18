import Foundation
import Testing
@testable import FB01Editor
@testable import FB01EditorApp

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

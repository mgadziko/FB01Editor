import Foundation
import Testing
@testable import FB01Editor

@Test func fb01ModuleDeclaresCurrentDeviceBoundary() {
    let module = FB01SynthModule.shared

    #expect(module.identity.manufacturer == "Yamaha")
    #expect(module.identity.modelName == "FB-01")
    #expect(module.identity.editorDisplayName == "Forest Editor")
    #expect(module.vocabulary.deviceDisplayName == "FB-01")
    #expect(module.vocabulary.writableVoiceBankSuffix == "RAM")
    #expect(module.vocabulary.readOnlyVoiceBankSuffixPrefix == "ROM")
    #expect(module.fileProfile.singleVoiceExtension == "fbv")
    #expect(module.fileProfile.singleConfigurationExtension == "fbc")
    #expect(module.fileProfile.voiceBankExtension == "fbvb")
    #expect(module.fileProfile.configurationBankExtension == "fbcb")
    #expect(module.fileProfile.genericSysExExtension == "fbx")
    #expect(module.fileProfile.importExtensions.contains("syx"))
    #expect(module.capabilities.supportsVoices)
    #expect(module.capabilities.supportsConfigurations)
    #expect(module.capabilities.supportsMultiInstrumentConfigurations)
    #expect(module.capabilities.supportsWritableVoiceBanks)
    #expect(module.capabilities.supportsReadOnlyVoiceBanks)
    #expect(module.capabilities.supportsMemoryProtect)
    #expect(module.capabilities.supportsLiveAuditionBuffer)
    #expect(module.capabilities.supportsGeneralMIDIInstall)
    #expect(module.supportedDocumentKinds == [.voice, .configuration, .voiceBank, .configurationBank])
    #expect(module.supportedDocumentDescriptors.map(\.kind) == module.supportedDocumentKinds)
    #expect(module.supportedDocumentDescriptors.first { $0.kind == .voice }?.supportsFetchFromDevice == true)
    #expect(module.commandDescriptors.first { $0.kind == .showVoiceBank }?.displayName == "Show Voice Bank")
    #expect(module.commandDescriptors.first { $0.kind == .copyVoiceToSlot }?.displayName == "Copy Voice to Slot...")
    #expect(module.commandDescriptors.first { $0.kind == .showConfigurationBank }?.displayName == "Show Configuration Bank")
    #expect(module.commandDescriptors.first { $0.kind == .storeGeneralMIDIVoices }?.menu == .voice)
    #expect(module.commandDescriptors.first { $0.kind == .sendSelectedConfigurationToEditBuffer }?.requiresConsoleSections == true)
    #expect(module.parameterDescriptors.contains { $0.id == "voice.operator.totalLevel" && $0.displayName == "Total Level" })
    #expect(module.parameterDescriptors.contains { $0.id == "configuration.instrument.noteCount" && $0.displayName == "Active Notes" })
    #expect(module.parameterBindingDescriptors.contains { $0.parameterID == "voice.operator.totalLevel" && $0.scope == .voiceOperator })
    #expect(module.parameterBindingDescriptors.contains { $0.parameterID == "configuration.instrument.stereoPan" && $0.fieldName == "stereoPan" })
    #expect(module.factoryVoiceNamesByBank.keys.sorted() == [3, 4, 5, 6, 7])
    #expect(module.factoryVoiceNamesByBank.values.allSatisfy { $0.count == module.voicesPerBank })
    #expect(module.factoryVoiceName(bank: 3, voiceNumber: 1) == "Brass")
    #expect(module.factoryVoiceName(bank: 7, voiceNumber: 40) == "Wave")
    #expect(module.factoryConfigurationName(slot: 17) == "single")
    #expect(module.factoryConfigurationName(slot: 20) == "split")
    #expect(module.writableVoiceBanks == [1, 2])
    #expect(module.readOnlyVoiceBanks == [3, 4, 5, 6, 7])
    #expect(module.allVoiceBanks == [1, 2, 3, 4, 5, 6, 7])
    #expect(module.voiceBankRange.closedRange == 1...7)
    #expect(module.writableVoiceBankRange.closedRange == 1...2)
    #expect(module.voicesPerBank == 48)
    #expect(module.voiceBankSelectorLayout.columns == 4)
    #expect(module.voiceBankSelectorLayout.rowsPerColumn == 12)
    #expect(module.configurationBankSelectorLayout?.columns == 4)
    #expect(module.configurationBankSelectorLayout?.rowsPerColumn == 5)
    #expect(module.fullDeviceCacheScope.voiceBanks == [1, 2, 3, 4, 5, 6, 7])
    #expect(module.fullDeviceCacheScope.configurationSlots?.closedRange == 1...20)
    #expect(module.fullDeviceCacheScope.includesCurrentConfiguration)
    #expect(module.cacheVoiceBankDescription(for: [1, 2]) == "FB-01 RAM voice banks 1-2")
    #expect(module.cacheVoiceBankDescription(for: [3, 4, 5, 6, 7]) == "FB-01 ROM voice banks 3-7")
    #expect(module.cacheProgressText(voiceBanks: [1, 2], fetchConfigurations: false).subject == "FB-01 RAM voice banks 1-2")
    #expect(module.writableVoiceSlotCount == 96)
    #expect(module.writableConfigurationSlots.closedRange == 1...16)
    #expect(module.readOnlyConfigurationSlots.closedRange == 17...20)
    #expect(module.allConfigurationSlots.closedRange == 1...20)
    #expect(module.isWritableVoiceBank(1))
    #expect(module.isWritableVoiceBank(2))
    #expect(!module.isWritableVoiceBank(3))
    #expect(module.isReadOnlyVoiceBank(7))
    #expect(module.isValidVoiceBank(7))
    #expect(!module.isValidVoiceBank(8))
    #expect(module.isWritableConfigurationSlot(16))
    #expect(!module.isWritableConfigurationSlot(17))
    #expect(module.isValidConfigurationSlot(20))
    #expect(!module.isValidConfigurationSlot(21))
    #expect(module.displayVoiceBank(forStorageBank: 0) == 1)
    #expect(module.storageVoiceBank(forDisplayBank: 1) == 0)
}

private struct MockFourOperatorModule: SynthModule {
    let identity = SynthModuleIdentity(
        manufacturer: "Test",
        modelName: "Mock-4OP",
        editorDisplayName: "Mock 4-OP Editor"
    )
    let capabilities = SynthModuleCapabilities(
        supportsVoices: true,
        supportsConfigurations: false,
        supportsMultiInstrumentConfigurations: false,
        supportsWritableVoiceBanks: true,
        supportsReadOnlyVoiceBanks: false,
        supportsMemoryProtect: false,
        supportsLiveAuditionBuffer: true,
        supportsGeneralMIDIInstall: false
    )
    let vocabulary = SynthModuleVocabulary(deviceDisplayName: "Mock-4OP")
    let supportedDocumentKinds: [SynthDocumentKind] = [.voice]
    let fileProfile = SynthFileProfile(
        singleVoiceExtension: "mockv",
        singleConfigurationExtension: "mockc",
        voiceBankExtension: "mockvb",
        configurationBankExtension: "mockcb",
        genericSysExExtension: "mockx",
        importExtensions: ["mockv", "mockx"]
    )
    let supportedDocumentDescriptors: [SynthDocumentDescriptor] = [
        SynthDocumentDescriptor(
            kind: .voice,
            displayName: "Voice",
            supportsLoadFromFile: true,
            supportsSaveToFile: true,
            supportsFetchFromDevice: true,
            supportsStoreToDevice: true
        ),
    ]
    let commandDescriptors: [SynthModuleCommandDescriptor] = [
        SynthModuleCommandDescriptor(kind: .showVoiceBank, menu: .voice, displayName: "Show Voice Bank"),
        SynthModuleCommandDescriptor(kind: .copyVoiceToSlot, menu: .voice, displayName: "Copy Voice to Slot...")
    ]
    let parameterDescriptors: [SynthParameterDescriptor] = [
        SynthParameterDescriptor(
            id: "voice.operator.totalLevel",
            displayName: "Total Level",
            valueKind: .integer,
            range: SynthSlotRange(0...99),
            defaultValue: 0,
            group: "Operator"
        ),
    ]
    let parameterBindingDescriptors: [SynthParameterBindingDescriptor] = [
        SynthParameterBindingDescriptor(
            id: "mock.voice.operator.totalLevel",
            parameterID: "voice.operator.totalLevel",
            scope: .voiceOperator,
            fieldName: "operatorLevel"
        ),
    ]
    let writableVoiceBanks = [1]
    let readOnlyVoiceBanks: [Int] = []
    let voicesPerBank = 32
    let voiceBankSelectorLayout = SynthSelectorGridLayout(
        columns: 2,
        rowsPerColumn: 16,
        buttonWidth: 120,
        minimumWindowHeight: 420
    )
    let configurationBankSelectorLayout: SynthSelectorGridLayout? = nil
    let fullDeviceCacheScope = SynthDeviceCacheScope(
        voiceBanks: [1],
        configurationSlots: nil,
        includesCurrentConfiguration: false
    )
    let writableConfigurationSlots = SynthSlotRange(1...1)
    let readOnlyConfigurationSlots = SynthSlotRange(1...1)
}

@Test func mockModuleExercisesDeviceNeutralBoundary() {
    let module = MockFourOperatorModule()

    #expect(module.identity.modelName == "Mock-4OP")
    #expect(module.capabilities.supportsVoices)
    #expect(!module.capabilities.supportsConfigurations)
    #expect(module.supportedDocumentKinds == [.voice])
    #expect(module.supportedDocumentDescriptors.first?.displayName == "Voice")
    #expect(module.commandDescriptors.map(\.kind) == [.showVoiceBank, .copyVoiceToSlot])
    #expect(module.parameterDescriptors.first?.range?.closedRange == 0...99)
    #expect(module.parameterBindingDescriptors.first?.fieldName == "operatorLevel")
    #expect(module.writableVoiceBanks == [1])
    #expect(module.voicesPerBank == 32)
    #expect(module.voiceBankSelectorLayout.columns == 2)
    #expect(module.voiceBankSelectorLayout.rowsPerColumn == 16)
    #expect(module.configurationBankSelectorLayout == nil)
    #expect(module.fullDeviceCacheScope.voiceBanks == [1])
    #expect(module.cacheProgressText(voiceBanks: [1], fetchConfigurations: false).subject == "Mock-4OP RAM voice banks 1")
}

@Test func fb01ModuleServicesExposeCurrentModuleServices() {
    let services = FB01ModuleServices.shared

    #expect(services.module.identity.modelName == "FB-01")
    #expect(services.module.capabilities.supportsConfigurations)
    #expect(services.voiceService.module.identity == services.module.identity)
    #expect(services.configurationService.module.identity == services.module.identity)
    #expect(services.cacheService.module.identity == services.module.identity)
}

@Test func fb01ModuleAdapterExposesCurrentModuleBoundary() {
    let adapter = FB01ModuleAdapter.shared

    #expect(adapter.identity == FB01SynthModule.shared.identity)
    #expect(adapter.capabilities == FB01SynthModule.shared.capabilities)
    #expect(adapter.supportedDocumentKinds == FB01SynthModule.shared.supportedDocumentKinds)
    #expect(adapter.commandDescriptors == FB01SynthModule.shared.commandDescriptors)
    #expect(adapter.parameterBindingDescriptors == FB01SynthModule.shared.parameterBindingDescriptors)
    #expect(adapter.module.writableVoiceBanks == [1, 2])
}

@Test func fb01DocumentServiceConformsToNeutralDocumentProtocols() throws {
    let service = FB01DocumentService.shared

    let voice: FB01DocumentService.Voice = try service.templateVoice()
    let configuration: FB01DocumentService.Configuration = try service.templateConfiguration()

    #expect(voice.name == "Init")
    #expect(configuration.name == "Init")
}

@Test func fb01DeviceServiceBuildsModuleScopedRequestLists() throws {
    let service = FB01DeviceService.shared

    #expect(service.allBankRequestKinds == [
        .currentConfiguration,
        .voiceBank(1),
        .voiceBank(2),
        .voiceBank(3),
        .voiceBank(4),
        .voiceBank(5),
        .voiceBank(6),
        .voiceBank(7),
        .voiceRAM1
    ])
    #expect(service.storedConfigurationRequestKinds == (1...20).map { .configuration($0) })
    #expect(try service.writableVoiceBankRequestKind(forVoiceSlot: 0) == .voiceBank(1))
    #expect(try service.writableVoiceBankRequestKind(forVoiceSlot: 47) == .voiceBank(1))
    #expect(try service.writableVoiceBankRequestKind(forVoiceSlot: 48) == .voiceBank(2))
    #expect(try service.writableVoiceBankRequestKind(forVoiceSlot: 95) == .voiceBank(2))
    #expect(throws: FB01SysExError.self) {
        _ = try service.writableVoiceBankRequestKind(forVoiceSlot: 96)
    }
}

@Test func fb01DeviceCacheServiceScopesRequestsToModule() {
    let service = FB01DeviceCacheService.shared

    #expect(service.normalizedVoiceBanks([7, 99, 1, 3, 1]) == [1, 3, 7])
    #expect(service.totalRequestCount(voiceBanks: [1, 2], fetchConfigurations: false) == 2)
    #expect(service.totalRequestCount(voiceBanks: [1, 2], fetchConfigurations: true) == 23)
    #expect(service.progressDetail(for: .configuration(20)) == "Fetching Configuration 20 of 20...")
    #expect(service.progressDetail(for: .finishing) == "Finishing cache update...")
}

@Test func fb01DocumentServiceProvidesTemplatesAndCandidates() throws {
    let service = FB01ModuleServices.shared.documentService
    let voice = try service.templateVoice()
    let configuration = try service.templateConfiguration()

    #expect(voice.name == "Init")
    #expect(voice.leftOutputEnabled)
    #expect(voice.rightOutputEnabled)
    #expect(configuration.name == "Init")

    let voiceBankURL = Bundle.module.url(
        forResource: "voice-bank-1",
        withExtension: "syx",
        subdirectory: "Fixtures"
    )!
    let voiceArtifact = try FB01Artifact.readSysEx(from: voiceBankURL)
    let voiceCandidates = try service.voiceCandidates(from: voiceArtifact)
    #expect(voiceCandidates.count == FB01SynthModule.shared.voicesPerBank)
    #expect(voiceCandidates.first?.voice.name == "Brass")

    let configurationURL = Bundle.module.url(
        forResource: "current-configuration-single",
        withExtension: "syx",
        subdirectory: "Fixtures"
    )!
    let configurationArtifact = try FB01Artifact.readSysEx(from: configurationURL)
    let configurationCandidates = try service.configurationCandidates(from: configurationArtifact)
    #expect(configurationCandidates.count == 1)
    #expect(configurationCandidates.first?.configuration.name == "single")
}

@Test func fb01DocumentServiceReadsAndWritesSingleDocuments() throws {
    let service = FB01ModuleServices.shared.documentService
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("FB01DocumentServiceTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: directory)
    }

    let voiceURL = directory.appendingPathComponent("single.fbv")
    let voice = try service.templateVoice().settingName("Round")
    try service.writeVoice(voice, systemChannel: 2, to: voiceURL)
    let voiceCandidates = try service.readVoiceCandidates(from: voiceURL)
    #expect(voiceCandidates.count == 1)
    #expect(voiceCandidates.first?.voice.name == "Round")
    #expect(voiceCandidates.first?.systemChannel == 2)

    let configurationURL = directory.appendingPathComponent("single.fbc")
    let configuration = try service.templateConfiguration().settingName("Cfg")
    try service.writeConfiguration(configuration, systemChannel: 3, to: configurationURL)
    let configurationCandidates = try service.readConfigurationCandidates(from: configurationURL)
    #expect(configurationCandidates.count == 1)
    #expect(configurationCandidates.first?.configuration.name == "Cfg")
    #expect(configurationCandidates.first?.systemChannel == 3)
}

@Test func fb01VoiceServiceExtractsBankDataNamesAndStoredVoices() throws {
    let fixtureURL = Bundle.module.url(
        forResource: "voice-bank-1",
        withExtension: "syx",
        subdirectory: "Fixtures"
    )!
    let bytes = Array(try Data(contentsOf: fixtureURL))
    let service = FB01VoiceService.shared

    let bank = try service.voiceBankData(from: bytes, expectedDisplayBank: 1)
    #expect(bank.bank == 0)
    #expect(bank.voices.count == FB01SynthModule.shared.voicesPerBank)

    let names = try service.voiceNames(fromVoiceBankDump: bytes, expectedDisplayBank: 1)
    #expect(names.prefix(3) == ["Brass", "Horn", "Trumpet"])

    let voice = try service.storedVoice(fromVoiceBankDump: bytes, expectedDisplayBank: 1, zeroBasedVoiceNumber: 7)
    #expect(voice?.name == "EGrand")

    let locationVoice = try service.storedVoice(fromDump: bytes, location: .bank(1), zeroBasedVoiceNumber: 7)
    #expect(locationVoice?.name == "EGrand")

    let prepMessages = try service.keyboardAuditionPreparationMessages(systemChannel: 0, midiChannel: 0)
    #expect(prepMessages.count == FB01ConfigurationData.instrumentCount + 4)

    let voicePrepMessages = try service.auditionPreparationMessages(
        voice: try #require(voice),
        systemChannel: 0,
        midiChannel: 0
    )
    #expect(voicePrepMessages.count == prepMessages.count + 1)
}

@Test func fb01ConfigurationServiceExtractsNamesAndBuildsStoreMessages() throws {
    let fixtureURL = Bundle.module.url(
        forResource: "current-configuration-single",
        withExtension: "syx",
        subdirectory: "Fixtures"
    )!
    let bytes = Array(try Data(contentsOf: fixtureURL))
    let service = FB01ConfigurationService.shared

    let current = try #require(try service.currentConfiguration(fromDump: bytes))
    #expect(current.name == "single")
    #expect(try service.configurationName(fromDump: bytes) == "single")

    let messages = try service.storeMessages(configuration: current, systemChannel: 1, zeroBasedSlot: 15)
    #expect(messages.count == 3)
    #expect(try FB01SysExMessage(bytes: messages[0]) == .command(.setMemoryProtect(systemChannel: 1, .off)))

    guard case let .currentConfigurationDump(systemChannel, packet) = try FB01SysExMessage(bytes: messages[1]) else {
        Issue.record("Expected current configuration dump")
        return
    }
    #expect(systemChannel == 1)
    #expect(packet.payload == current.bytes)
    #expect(try FB01SysExMessage(bytes: messages[2]) == .command(.storeCurrentConfiguration(systemChannel: 1, number: 15)))
    #expect(throws: FB01SysExError.self) {
        _ = try service.storeMessages(configuration: current, systemChannel: 1, zeroBasedSlot: 16)
    }
}

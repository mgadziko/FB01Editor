import Foundation
import Testing
@testable import FB01Editor

@Test func fb01ModuleDeclaresCurrentDeviceBoundary() {
    let module = FB01SynthModule.shared

    #expect(module.identity.manufacturer == "Yamaha")
    #expect(module.identity.modelName == "FB-01")
    #expect(module.identity.editorDisplayName == "Forest FB-01 Editor")
    #expect(module.capabilities.supportsVoices)
    #expect(module.capabilities.supportsConfigurations)
    #expect(module.capabilities.supportsMultiInstrumentConfigurations)
    #expect(module.capabilities.supportsWritableVoiceBanks)
    #expect(module.capabilities.supportsReadOnlyVoiceBanks)
    #expect(module.capabilities.supportsMemoryProtect)
    #expect(module.capabilities.supportsLiveAuditionBuffer)
    #expect(module.capabilities.supportsGeneralMIDIInstall)
    #expect(module.supportedDocumentKinds == [.voice, .configuration, .voiceBank, .configurationBank])
    #expect(module.writableVoiceBanks == [1, 2])
    #expect(module.readOnlyVoiceBanks == [3, 4, 5, 6, 7])
    #expect(module.allVoiceBanks == [1, 2, 3, 4, 5, 6, 7])
    #expect(module.voiceBankRange.closedRange == 1...7)
    #expect(module.writableVoiceBankRange.closedRange == 1...2)
    #expect(module.voicesPerBank == 48)
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
    #expect(adapter.module.writableVoiceBanks == [1, 2])
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

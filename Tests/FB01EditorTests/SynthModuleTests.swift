import Foundation
import Testing
@testable import FB01Editor

@Test func fb01ModuleDeclaresCurrentDeviceBoundary() {
    let module = FB01SynthModule.shared

    #expect(module.identity.manufacturer == "Yamaha")
    #expect(module.identity.modelName == "FB-01")
    #expect(module.identity.editorDisplayName == "Forest FB-01 Editor")
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
}

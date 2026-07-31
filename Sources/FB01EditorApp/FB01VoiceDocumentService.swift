import FB01Editor

enum FB01VoiceDocumentService {
    nonisolated static func fetchVoice(
        source: VoiceDocumentFetchSource,
        sourceIndex: Int,
        destinationIndex: Int,
        systemChannel: Int
    ) throws -> (voice: FB01VoiceData, systemChannel: Int, title: String) {
        let service = FB01ModuleServices.shared.voiceService

        switch source {
        case .instrument(let instrument):
            let result = try service.fetchInstrumentVoice(
                instrument: instrument,
                sourceIndex: sourceIndex,
                destinationIndex: destinationIndex,
                systemChannel: systemChannel
            )
            return (result.voice, result.systemChannel, result.title)
        case let .storedSlot(location, voiceNumber):
            let result = try service.fetchStoredVoice(
                location: location.serviceLocation,
                zeroBasedVoiceNumber: voiceNumber,
                sourceIndex: sourceIndex,
                destinationIndex: destinationIndex,
                systemChannel: systemChannel
            )
            return (result.voice, result.systemChannel, location.title + " Voice \(voiceNumber + 1)")
        }
    }

    nonisolated static func fetchRAMVoiceNames(
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

    static func auditionPreparationMessages(
        voice: FB01VoiceData,
        systemChannel: Int,
        midiChannel: Int
    ) throws -> [[UInt8]] {
        try FB01ModuleServices.shared.voiceService.auditionPreparationMessages(
            voice: voice,
            systemChannel: systemChannel,
            midiChannel: midiChannel
        )
    }
}

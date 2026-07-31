public struct FB01SynthModule: SynthModule {
    public static let shared = FB01SynthModule()

    public let identity = SynthModuleIdentity(
        manufacturer: "Yamaha",
        modelName: "FB-01",
        editorDisplayName: "Forest FB-01 Editor"
    )

    public let capabilities = SynthModuleCapabilities(
        supportsVoices: true,
        supportsConfigurations: true,
        supportsMultiInstrumentConfigurations: true,
        supportsWritableVoiceBanks: true,
        supportsReadOnlyVoiceBanks: true,
        supportsMemoryProtect: true,
        supportsLiveAuditionBuffer: true,
        supportsGeneralMIDIInstall: true
    )

    public let vocabulary = SynthModuleVocabulary(deviceDisplayName: "FB-01")

    public let fileProfile = SynthFileProfile(
        singleVoiceExtension: "fbv",
        singleConfigurationExtension: "fbc",
        voiceBankExtension: "fbvb",
        configurationBankExtension: "fbcb",
        genericSysExExtension: "fbx",
        importExtensions: ["fbv", "fbc", "fbvb", "fbcb", "fbx", "syx"]
    )

    public let factoryVoiceNamesByBank: [Int: [String]] = [
        3: [
            "Brass", "Horn", "Trumpet", "LoStrg", "Strings", "Piano", "NewEP", "EGrand",
            "Jazz Gt", "EBass", "WodBass", "EOrgan1", "EOrgan2", "POrgan1", "POrgan2", "Flute",
            "Picolo", "Oboe", "Clarine", "Glocken", "Vibes", "Xylophn", "Koto", "Zither",
            "Clav", "Harpsic", "Bells", "Harp", "SmadSyn", "Harmoni", "SteelDr", "Timpani",
            "LoStrg2", "Horn Lo", "Whistle", "zingPlp", "Metal", "Heavy", "FunkSyn", "Voices",
            "Marimba", "EBass2", "SnareDr", "RD Cymb", "Tom Tom", "Mars to", "Storm", "Windbel",
        ],
        4: [
            "UpPiano", "SPiano", "Piano2", "Piano3", "Piano4", "Piano5", "PhGrand", "Grand",
            "DpGrand", "LPiano1", "LPiano2", "EGrand2", "Honkey1", "Honkey2", "Pfbell", "PFvibe",
            "NewEP2", "NewEP3", "NewEP4", "NewEP5", "EPiano1", "EPiano2", "EPiano3", "EPiano4",
            "EPiano5", "HighTin", "HardTin", "PercPf", "WoodPf", "EPStrng", "EPBrass", "Clav2",
            "Clav3", "Clav4", "FuzzClv", "MuteClv", "MuteCl2", "SynClv1", "SynClv2", "SynClv3",
            "SynClv4", "Harpsi2", "Harpsi3", "Harpsi4", "Harpsi5", "Circut", "Celeste", "Squeeze",
        ],
        5: [
            "Horn2", "Horn3", "Horns", "Flugelh", "Trombon", "Trump2", "Brass2", "Brass3",
            "HardBr1", "HardBr2", "HardBr3", "HardBr4", "HardBr5", "PercBr1", "PercBr2", "String1",
            "String2", "String3", "String4", "SoloVio", "RichSt1", "RichSt2", "RichSt3", "RichSt4",
            "Cello1", "Cello2", "LoStrg3", "LoStrg4", "LoStrg5", "Orchestr", "5th Str", "Pizzic1",
            "Pizzic2", "Flute2", "Flute3", "Flute4", "Pan Flt", "SlowFlt", "5th Flt", "Oboe2",
            "Bassoon", "Reed", "Harmon2", "Harmon3", "Harmon4", "MonoSax", "Sax 1", "Sax 2",
        ],
        6: [
            "FnkSyn2", "FnkSyn3", "SynOrgn", "SynFeed", "SynHarm", "SynClar", "SynLead", "HuffTak",
            "SoHeavy", "Hollow", "Schmooh", "MonoSyn", "Cheeky", "SynBell", "SynPluk", "EBass3",
            "Rubbass", "SolBass", "PlukBas", "PortBas", "Fretles", "FrplBs", "MonoBas", "SynBas1",
            "SynBas2", "SynBas3", "SynBas4", "SynBas5", "SynBas6", "SynBas7", "Marimb2", "Marimb3",
            "Xylophn2", "Vibe2", "Vibe3", "Glockn2", "TubeBe1", "TubeBe2", "Bells 2", "TempleG",
            "SteelDr", "ElectDr", "HandDr", "SynTimp", "clock", "Heifer", "SnareD2", "SnareD3",
        ],
        7: [
            "JOrgan1", "JOrgan2", "COrgan1", "COrgan2", "EOrgan3", "EOrgan4", "EOrgan5", "EOrgan6",
            "EOrgan7", "EOrgan8", "SmlPipe", "MidPipe", "BigPipe", "StPipe", "Organ", "Guitar",
            "Folk Gt", "PluckGt", "BriteGt", "Fuzz Gt", "Zither2", "Lute", "Banjo", "SftHarp",
            "Harp2", "Harp3", "SftKoto", "HitKoto", "Sitar1", "Sitar2", "HuffSyn", "Fantasy",
            "Synvoic", "M.Voice", "VSAR", "Racing", "Water", "WildWar", "Ghostie", "Wave",
            "Space 1", "SpChime", "SpTalk", "Winds", "Smash", "Alarm", "Helicop", "SineWav",
        ],
    ]

    public let factoryConfigurationNamesBySlot: [Int: String] = [
        17: "single",
        18: "mono 8",
        19: "dual",
        20: "split",
    ]

    public let supportedDocumentKinds: [SynthDocumentKind] = [
        .voice,
        .configuration,
        .voiceBank,
        .configurationBank
    ]

    public let supportedDocumentDescriptors: [SynthDocumentDescriptor] = [
        SynthDocumentDescriptor(
            kind: .voice,
            displayName: "Voice",
            supportsLoadFromFile: true,
            supportsSaveToFile: true,
            supportsFetchFromDevice: true,
            supportsStoreToDevice: true
        ),
        SynthDocumentDescriptor(
            kind: .configuration,
            displayName: "Configuration",
            supportsLoadFromFile: true,
            supportsSaveToFile: true,
            supportsFetchFromDevice: true,
            supportsStoreToDevice: true
        ),
        SynthDocumentDescriptor(
            kind: .voiceBank,
            displayName: "Voice Bank",
            supportsLoadFromFile: true,
            supportsSaveToFile: true,
            supportsFetchFromDevice: true,
            supportsStoreToDevice: true
        ),
        SynthDocumentDescriptor(
            kind: .configurationBank,
            displayName: "Configuration Bank",
            supportsLoadFromFile: true,
            supportsSaveToFile: true,
            supportsFetchFromDevice: true,
            supportsStoreToDevice: true
        ),
    ]

    public let parameterDescriptors: [SynthParameterDescriptor] = [
        SynthParameterDescriptor(id: "voice.name", displayName: "Name", valueKind: .text(maxLength: 7), group: "Voice"),
        SynthParameterDescriptor(id: "voice.algorithm", displayName: "Algorithm", valueKind: .integer, range: SynthSlotRange(1...8), defaultValue: 1, group: "Voice"),
        SynthParameterDescriptor(id: "voice.feedback", displayName: "Feedback", valueKind: .integer, range: SynthSlotRange(0...7), defaultValue: 0, group: "Voice"),
        SynthParameterDescriptor(id: "voice.transpose", displayName: "Transpose", valueKind: .signedInteger, range: SynthSlotRange(-24...24), defaultValue: 0, group: "Voice"),
        SynthParameterDescriptor(id: "voice.lfoSpeed", displayName: "LFO Speed", valueKind: .integer, range: SynthSlotRange(0...255), defaultValue: 0, group: "LFO"),
        SynthParameterDescriptor(id: "voice.amd", displayName: "Amplitude MOD Depth", valueKind: .integer, range: SynthSlotRange(0...127), defaultValue: 0, group: "LFO"),
        SynthParameterDescriptor(id: "voice.pmd", displayName: "Pitch MOD Depth", valueKind: .integer, range: SynthSlotRange(0...127), defaultValue: 0, group: "LFO"),
        SynthParameterDescriptor(id: "voice.ams", displayName: "Amplitude MOD Sensitivity", valueKind: .integer, range: SynthSlotRange(0...3), defaultValue: 0, group: "LFO"),
        SynthParameterDescriptor(id: "voice.pms", displayName: "Pitch MOD Sensitivity", valueKind: .integer, range: SynthSlotRange(0...7), defaultValue: 0, group: "LFO"),
        SynthParameterDescriptor(id: "voice.operator.totalLevel", displayName: "Total Level", valueKind: .integer, range: SynthSlotRange(0...127), defaultValue: 0, group: "Operator"),
        SynthParameterDescriptor(id: "voice.operator.frequencyMultiplier", displayName: "OSC FRQ Multiplier", valueKind: .integer, range: SynthSlotRange(0...15), defaultValue: 1, group: "Operator"),
        SynthParameterDescriptor(id: "voice.operator.attack", displayName: "Attack", valueKind: .integer, range: SynthSlotRange(0...31), defaultValue: 0, group: "Operator Envelope"),
        SynthParameterDescriptor(id: "voice.operator.decay1", displayName: "Decay 1", valueKind: .integer, range: SynthSlotRange(0...31), defaultValue: 0, group: "Operator Envelope"),
        SynthParameterDescriptor(id: "voice.operator.decay2", displayName: "Decay 2", valueKind: .integer, range: SynthSlotRange(0...31), defaultValue: 0, group: "Operator Envelope"),
        SynthParameterDescriptor(id: "voice.operator.sustain", displayName: "Sustain", valueKind: .integer, range: SynthSlotRange(0...15), defaultValue: 0, group: "Operator Envelope"),
        SynthParameterDescriptor(id: "voice.operator.release", displayName: "Release", valueKind: .integer, range: SynthSlotRange(0...15), defaultValue: 0, group: "Operator Envelope"),
        SynthParameterDescriptor(id: "configuration.name", displayName: "Name", valueKind: .text(maxLength: 8), group: "Configuration"),
        SynthParameterDescriptor(id: "configuration.combine", displayName: "Combine", valueKind: .toggle, defaultValue: 0, group: "Configuration"),
        SynthParameterDescriptor(id: "configuration.instrument.noteCount", displayName: "Active Notes", valueKind: .integer, range: SynthSlotRange(0...8), defaultValue: 0, group: "Instrument"),
        SynthParameterDescriptor(id: "configuration.instrument.midiChannel", displayName: "MIDI Channel", valueKind: .integer, range: SynthSlotRange(1...16), defaultValue: 1, group: "Instrument"),
        SynthParameterDescriptor(id: "configuration.instrument.outputLevel", displayName: "Level", valueKind: .integer, range: SynthSlotRange(0...127), defaultValue: 127, group: "Instrument"),
        SynthParameterDescriptor(id: "configuration.instrument.stereoPan", displayName: "Stereo Pan", valueKind: .signedInteger, range: SynthSlotRange(-63...63), defaultValue: 0, group: "Instrument"),
    ]

    public let writableVoiceBanks = [1, 2]
    public let readOnlyVoiceBanks = [3, 4, 5, 6, 7]
    public let voicesPerBank = 48
    public let writableConfigurationSlots = SynthSlotRange(1...16)
    public let readOnlyConfigurationSlots = SynthSlotRange(17...20)

    private init() {}

    public var allVoiceBanks: [Int] {
        writableVoiceBanks + readOnlyVoiceBanks
    }

    public var voiceBankRange: SynthSlotRange {
        SynthSlotRange(allVoiceBanks.first!...allVoiceBanks.last!)
    }

    public var writableVoiceBankRange: SynthSlotRange {
        SynthSlotRange(writableVoiceBanks.first!...writableVoiceBanks.last!)
    }

    public var allConfigurationSlots: SynthSlotRange {
        SynthSlotRange(writableConfigurationSlots.lowerBound...readOnlyConfigurationSlots.upperBound)
    }

    public var writableVoiceSlotCount: Int {
        writableVoiceBanks.count * voicesPerBank
    }

    public func isWritableVoiceBank(_ bank: Int) -> Bool {
        writableVoiceBanks.contains(bank)
    }

    public func isReadOnlyVoiceBank(_ bank: Int) -> Bool {
        readOnlyVoiceBanks.contains(bank)
    }

    public func isValidVoiceBank(_ bank: Int) -> Bool {
        allVoiceBanks.contains(bank)
    }

    public func isWritableConfigurationSlot(_ slot: Int) -> Bool {
        writableConfigurationSlots.contains(slot)
    }

    public func isValidConfigurationSlot(_ slot: Int) -> Bool {
        allConfigurationSlots.contains(slot)
    }

    public func displayVoiceBank(forStorageBank storageBank: Int) -> Int {
        storageBank + 1
    }

    public func storageVoiceBank(forDisplayBank displayBank: Int) -> Int {
        displayBank - 1
    }

    public func factoryVoiceName(bank: Int, voiceNumber: Int) -> String? {
        guard let names = factoryVoiceNamesByBank[bank],
              (1...names.count).contains(voiceNumber) else {
            return nil
        }
        return names[voiceNumber - 1]
    }

    public func factoryConfigurationName(slot: Int) -> String? {
        factoryConfigurationNamesBySlot[slot]
    }
}

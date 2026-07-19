public struct FB01GeneralMIDIMapping: Equatable, Sendable {
    public var gmNumber: Int
    public var gmName: String
    public var sourceBank: Int
    public var sourceVoice: Int
    public var expectedName: String

    public init(gmNumber: Int, gmName: String, sourceBank: Int, sourceVoice: Int, expectedName: String) {
        self.gmNumber = gmNumber
        self.gmName = gmName
        self.sourceBank = sourceBank
        self.sourceVoice = sourceVoice
        self.expectedName = expectedName
    }
}

public enum FB01GeneralMIDI {
    public static let mappings: [FB01GeneralMIDIMapping] = [
        FB01GeneralMIDIMapping(gmNumber: 1, gmName: "Acoustic Grand", sourceBank: 4, sourceVoice: 8, expectedName: "Grand"),
        FB01GeneralMIDIMapping(gmNumber: 2, gmName: "Bright Piano", sourceBank: 4, sourceVoice: 9, expectedName: "DpGrand"),
        FB01GeneralMIDIMapping(gmNumber: 3, gmName: "Electric Grand", sourceBank: 3, sourceVoice: 8, expectedName: "EGrand"),
        FB01GeneralMIDIMapping(gmNumber: 4, gmName: "Honky Tonk", sourceBank: 4, sourceVoice: 13, expectedName: "Honkey1"),
        FB01GeneralMIDIMapping(gmNumber: 5, gmName: "Electric Piano 1", sourceBank: 4, sourceVoice: 22, expectedName: "EPiano2"),
        FB01GeneralMIDIMapping(gmNumber: 6, gmName: "Electric Piano 2", sourceBank: 4, sourceVoice: 23, expectedName: "EPiano3"),
        FB01GeneralMIDIMapping(gmNumber: 7, gmName: "Harpsichord", sourceBank: 3, sourceVoice: 26, expectedName: "Harpsic"),
        FB01GeneralMIDIMapping(gmNumber: 8, gmName: "Clavinet", sourceBank: 3, sourceVoice: 25, expectedName: "Clav"),
        FB01GeneralMIDIMapping(gmNumber: 9, gmName: "Celesta", sourceBank: 4, sourceVoice: 47, expectedName: "Celeste"),
        FB01GeneralMIDIMapping(gmNumber: 10, gmName: "Glockenspiel", sourceBank: 3, sourceVoice: 20, expectedName: "Glocken"),
        FB01GeneralMIDIMapping(gmNumber: 11, gmName: "Music Box", sourceBank: 5, sourceVoice: 14, expectedName: "SynBell"),
        FB01GeneralMIDIMapping(gmNumber: 12, gmName: "Vibraphone", sourceBank: 4, sourceVoice: 16, expectedName: "PfVibe"),
        FB01GeneralMIDIMapping(gmNumber: 13, gmName: "Marimba", sourceBank: 3, sourceVoice: 41, expectedName: "Marimba"),
        FB01GeneralMIDIMapping(gmNumber: 14, gmName: "Xylophone", sourceBank: 3, sourceVoice: 22, expectedName: "Xylophn"),
        FB01GeneralMIDIMapping(gmNumber: 15, gmName: "Tubular Bells", sourceBank: 6, sourceVoice: 37, expectedName: "TubeBe2"),
        FB01GeneralMIDIMapping(gmNumber: 16, gmName: "Dulcimer", sourceBank: 7, sourceVoice: 23, expectedName: "Santur"),
        FB01GeneralMIDIMapping(gmNumber: 17, gmName: "Drawbar Organ", sourceBank: 7, sourceVoice: 1, expectedName: "JOrgan1"),
        FB01GeneralMIDIMapping(gmNumber: 18, gmName: "Percussive Organ", sourceBank: 7, sourceVoice: 2, expectedName: "JOrgan2"),
        FB01GeneralMIDIMapping(gmNumber: 19, gmName: "Rock Organ", sourceBank: 7, sourceVoice: 3, expectedName: "COrgan1"),
        FB01GeneralMIDIMapping(gmNumber: 20, gmName: "Church Organ", sourceBank: 7, sourceVoice: 15, expectedName: "Organ"),
        FB01GeneralMIDIMapping(gmNumber: 21, gmName: "Reed Organ", sourceBank: 3, sourceVoice: 13, expectedName: "EOrgan1"),
        FB01GeneralMIDIMapping(gmNumber: 22, gmName: "Accordion", sourceBank: 7, sourceVoice: 11, expectedName: "MidiPipe"),
        FB01GeneralMIDIMapping(gmNumber: 23, gmName: "Harmonica", sourceBank: 5, sourceVoice: 13, expectedName: "HuffBr"),
        FB01GeneralMIDIMapping(gmNumber: 24, gmName: "Bandoneon", sourceBank: 3, sourceVoice: 14, expectedName: "EOrgan2"),
        FB01GeneralMIDIMapping(gmNumber: 25, gmName: "Nylon Guitar", sourceBank: 7, sourceVoice: 17, expectedName: "Guitar"),
        FB01GeneralMIDIMapping(gmNumber: 26, gmName: "Steel Guitar", sourceBank: 7, sourceVoice: 18, expectedName: "Folk Gt"),
        FB01GeneralMIDIMapping(gmNumber: 27, gmName: "Jazz Guitar", sourceBank: 7, sourceVoice: 19, expectedName: "PluckGt"),
        FB01GeneralMIDIMapping(gmNumber: 28, gmName: "Clean Guitar", sourceBank: 7, sourceVoice: 20, expectedName: "BriteGt"),
        FB01GeneralMIDIMapping(gmNumber: 29, gmName: "Muted Guitar", sourceBank: 4, sourceVoice: 35, expectedName: "FuzzClv"),
        FB01GeneralMIDIMapping(gmNumber: 30, gmName: "Overdrive Guitar", sourceBank: 7, sourceVoice: 21, expectedName: "Fuzz Gt"),
        FB01GeneralMIDIMapping(gmNumber: 31, gmName: "Distortion Guitar", sourceBank: 7, sourceVoice: 21, expectedName: "Fuzz Gt"),
        FB01GeneralMIDIMapping(gmNumber: 32, gmName: "Guitar Harmonics", sourceBank: 7, sourceVoice: 24, expectedName: "SftHarp"),
        FB01GeneralMIDIMapping(gmNumber: 33, gmName: "Acoustic Bass", sourceBank: 6, sourceVoice: 20, expectedName: "UprtBas"),
        FB01GeneralMIDIMapping(gmNumber: 34, gmName: "Finger Bass", sourceBank: 6, sourceVoice: 17, expectedName: "RubBass"),
        FB01GeneralMIDIMapping(gmNumber: 35, gmName: "Picked Bass", sourceBank: 6, sourceVoice: 19, expectedName: "PlukBas"),
        FB01GeneralMIDIMapping(gmNumber: 36, gmName: "Fretless Bass", sourceBank: 6, sourceVoice: 21, expectedName: "Fretles"),
        FB01GeneralMIDIMapping(gmNumber: 37, gmName: "Slap Bass 1", sourceBank: 6, sourceVoice: 24, expectedName: "SynBas1"),
        FB01GeneralMIDIMapping(gmNumber: 38, gmName: "Slap Bass 2", sourceBank: 6, sourceVoice: 25, expectedName: "SynBas2"),
        FB01GeneralMIDIMapping(gmNumber: 39, gmName: "Synth Bass 1", sourceBank: 6, sourceVoice: 13, expectedName: "Cheeky"),
        FB01GeneralMIDIMapping(gmNumber: 40, gmName: "Synth Bass 2", sourceBank: 6, sourceVoice: 12, expectedName: "MonoSyn"),
        FB01GeneralMIDIMapping(gmNumber: 41, gmName: "Violin", sourceBank: 5, sourceVoice: 16, expectedName: "String1"),
        FB01GeneralMIDIMapping(gmNumber: 42, gmName: "Viola", sourceBank: 5, sourceVoice: 17, expectedName: "String2"),
        FB01GeneralMIDIMapping(gmNumber: 43, gmName: "Cello", sourceBank: 5, sourceVoice: 26, expectedName: "Cello2"),
        FB01GeneralMIDIMapping(gmNumber: 44, gmName: "Contrabass", sourceBank: 5, sourceVoice: 27, expectedName: "LoStrg3"),
        FB01GeneralMIDIMapping(gmNumber: 45, gmName: "Tremolo Strings", sourceBank: 4, sourceVoice: 30, expectedName: "EPString"),
        FB01GeneralMIDIMapping(gmNumber: 46, gmName: "Pizzicato Strings", sourceBank: 5, sourceVoice: 31, expectedName: "Pizzic1"),
        FB01GeneralMIDIMapping(gmNumber: 47, gmName: "Orchestral Harp", sourceBank: 5, sourceVoice: 25, expectedName: "Cello1"),
        FB01GeneralMIDIMapping(gmNumber: 48, gmName: "Timpani", sourceBank: 3, sourceVoice: 32, expectedName: "Timpani"),
    ]
}

import AppKit
import FB01Editor
import Foundation

enum EditorDocumentTemplates {
    static func voice() -> FB01VoiceData {
        do {
            var voice = try FB01VoiceData(bytes: Array(repeating: 0, count: FB01VoiceData.byteCount))
            voice = try voice.settingName("Init")
            voice = try voice.settingLeftOutputEnabled(true)
            voice = try voice.settingRightOutputEnabled(true)
            return voice
        } catch {
            fatalError("Unable to create template voice: \(error)")
        }
    }

    static func configuration() -> FB01ConfigurationData {
        do {
            var configuration = try FB01ConfigurationData(bytes: Array(repeating: 0, count: FB01ConfigurationData.byteCount))
            configuration = try configuration.settingName("Init")
            return configuration
        } catch {
            fatalError("Unable to create template configuration: \(error)")
        }
    }
}

private enum EditorFileDefaultsKey {
    static let lastLoadDirectory = "FB01Editor.lastLoadDirectory"
    static let lastSaveDirectory = "FB01Editor.lastSaveDirectory"
}

struct RecentEditorFile: Codable, Identifiable, Equatable {
    var path: String

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
    var title: String { url.deletingPathExtension().lastPathComponent }
}

struct RecentVoiceFetch: Codable, Identifiable, Equatable {
    enum SourceKind: String, Codable {
        case instrument
        case bank
        case voiceRAM1
    }

    var kind: SourceKind
    var instrument: Int?
    var bank: Int?
    var voiceNumber: Int?
    var title: String

    var id: String {
        switch kind {
        case .instrument:
            return "instrument-\(instrument ?? 0)"
        case .bank:
            return "bank-\(bank ?? 0)-voice-\(voiceNumber ?? 0)"
        case .voiceRAM1:
            return "voiceRAM1-\(voiceNumber ?? 0)"
        }
    }

    var source: VoiceDocumentFetchSource? {
        switch kind {
        case .instrument:
            guard let instrument else { return nil }
            return .instrument(instrument)
        case .bank:
            guard let bank, let voiceNumber else { return nil }
            return .storedSlot(location: .bank(bank), voiceNumber: voiceNumber)
        case .voiceRAM1:
            guard let voiceNumber else { return nil }
            return .storedSlot(location: .voiceRAM1, voiceNumber: voiceNumber)
        }
    }
}

struct RecentConfigurationFetch: Codable, Identifiable, Equatable {
    var isCurrent: Bool
    var slot: Int
    var title: String

    var id: String {
        isCurrent ? "current" : "slot-\(slot)"
    }

    var options: ConfigurationFetchOptions {
        ConfigurationFetchOptions(isCurrent: isCurrent, slot: slot)
    }
}

struct VoiceDocumentStoreOptions: Sendable {
    var bank: Int
    var voiceNumber: Int

    var voiceSlot: Int {
        bank * FB01VoiceBankData.voiceCount + voiceNumber
    }
}

enum VoiceDocumentFetchSource: Sendable {
    case instrument(Int)
    case storedSlot(location: VoiceDocumentFetchLocation, voiceNumber: Int)

    func title(nameLookup: VoiceDocumentFetchNameLookup = .empty) -> String {
        switch self {
        case .instrument(let instrument):
            return "instrument \(instrument + 1) voice"
        case let .storedSlot(location, voiceNumber):
            return nameLookup.sourceTitle(location: location, voiceNumber: voiceNumber + 1)
        }
    }
}

enum VoiceDocumentFetchLocation: Sendable {
    case bank(Int)
    case voiceRAM1

    var title: String {
        switch self {
        case .bank(let bank):
            "Bank \(bank)"
        case .voiceRAM1:
            "Voice RAM 1"
        }
    }

    var requestKind: FB01MIDIRequestKind {
        switch self {
        case .bank(let bank):
            .voiceBank(bank)
        case .voiceRAM1:
            .voiceRAM1
        }
    }

    var menuTitle: String {
        switch self {
        case .bank(1):
            "Bank 1 RAM"
        case .bank(2):
            "Bank 2 RAM"
        case .bank(let bank):
            "Bank \(bank) ROM\(bank - 2)"
        case .voiceRAM1:
            "Voice RAM 1"
        }
    }
}

struct FB01FactoryVoiceNames {
    static let namesByBank: [Int: [String]] = [
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

    static func name(bank: Int, voiceNumber: Int) -> String? {
        guard let names = namesByBank[bank],
              (1...names.count).contains(voiceNumber) else {
            return nil
        }
        return names[voiceNumber - 1]
    }
}

struct VoiceDocumentFetchNameLookup: Sendable {
    static let empty = VoiceDocumentFetchNameLookup(ramBankNames: [:])

    var ramBankNames: [Int: [String]]

    var loadedBankTitles: String {
        let loaded = ramBankNames.keys.sorted().map { "Bank \($0)" }
        return loaded.isEmpty ? "no RAM banks" : loaded.joined(separator: ", ")
    }

    func statusTitle(for location: VoiceDocumentFetchLocation) -> String {
        switch location {
        case .bank(let bank) where bank <= 2:
            return ramBankNames[bank] == nil
                ? "RAM names not loaded for Bank \(bank)"
                : "RAM names loaded for Bank \(bank)"
        case .bank:
            return "Factory ROM names built in"
        case .voiceRAM1:
            return "Voice RAM names are not named by the fetch list"
        }
    }

    func name(location: VoiceDocumentFetchLocation, voiceNumber: Int) -> String? {
        switch location {
        case .bank(let bank) where bank <= 2:
            guard let names = ramBankNames[bank],
                  (1...names.count).contains(voiceNumber) else {
                return nil
            }
            return names[voiceNumber - 1]
        case .bank(let bank):
            return FB01FactoryVoiceNames.name(bank: bank, voiceNumber: voiceNumber)
        case .voiceRAM1:
            return nil
        }
    }

    func voiceMenuTitle(location: VoiceDocumentFetchLocation, voiceNumber: Int) -> String {
        guard let name = name(location: location, voiceNumber: voiceNumber), !name.isEmpty else {
            if case .bank(let bank) = location, bank <= 2 {
                return String(format: "%02d RAM name not loaded", voiceNumber)
            }
            return "Voice \(voiceNumber)"
        }
        return String(format: "%02d %@", voiceNumber, name)
    }

    func sourceTitle(location: VoiceDocumentFetchLocation, voiceNumber: Int) -> String {
        guard let name = name(location: location, voiceNumber: voiceNumber), !name.isEmpty else {
            return "\(location.title) Voice \(voiceNumber)"
        }
        return "\(location.title) Voice \(voiceNumber): \(name)"
    }
}

struct FB01FactoryConfigurationNames {
    static let namesBySlot: [Int: String] = [
        17: "single",
        18: "mono 8",
        19: "dual",
        20: "split",
    ]

    static func name(slot: Int) -> String? {
        namesBySlot[slot]
    }
}

struct ConfigurationFetchNameLookup: Sendable {
    static let empty = ConfigurationFetchNameLookup(storedNames: [:])

    var storedNames: [Int: String]

    func name(slot: Int) -> String? {
        storedNames[slot] ?? FB01FactoryConfigurationNames.name(slot: slot)
    }

    func menuTitle(slot: Int) -> String {
        let readOnly = slot >= 17 ? " Read Only" : ""
        guard let name = name(slot: slot), !name.isEmpty else {
            return "Configuration \(slot)\(readOnly)"
        }
        return "Configuration \(slot) - \(name)\(readOnly)"
    }
}

struct ConfigurationFetchOptions: Sendable {
    var isCurrent: Bool
    var slot: Int
}

struct ConfigurationDocumentStoreOptions: Sendable {
    var slot: Int
    var confirmAfterStore: Bool
}

func preferredEditorLoadDirectoryURL() -> URL {
    preferredEditorDirectory(defaultsKey: EditorFileDefaultsKey.lastLoadDirectory)
}

func preferredEditorSaveDirectoryURL() -> URL {
    preferredEditorDirectory(defaultsKey: EditorFileDefaultsKey.lastSaveDirectory)
}

private func preferredEditorDirectory(defaultsKey: String) -> URL {
    ensureDefaultEditorFileDirectory()

    if let path = UserDefaults.standard.string(forKey: defaultsKey) {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        if editorDirectoryExists(at: url) {
            return url
        }
    }

    return defaultEditorFileDirectoryURL
}

func rememberEditorLoadDirectory(for url: URL) {
    rememberEditorDirectory(for: url, defaultsKey: EditorFileDefaultsKey.lastLoadDirectory)
}

func rememberEditorSaveDirectory(for url: URL) {
    rememberEditorDirectory(for: url, defaultsKey: EditorFileDefaultsKey.lastSaveDirectory)
}

private func rememberEditorDirectory(for url: URL, defaultsKey: String) {
    let directoryURL: URL
    var isDirectory: ObjCBool = false
    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
        directoryURL = url.standardizedFileURL
    } else {
        directoryURL = url.deletingLastPathComponent().standardizedFileURL
    }

    guard editorDirectoryExists(at: directoryURL) else {
        return
    }
    UserDefaults.standard.set(directoryURL.path, forKey: defaultsKey)
}

private func ensureDefaultEditorFileDirectory() {
    try? FileManager.default.createDirectory(
        at: defaultEditorFileDirectoryURL,
        withIntermediateDirectories: true
    )
}

func ensureDefaultEditorBackupDirectory() throws -> URL {
    let url = defaultEditorBackupDirectoryURL
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func editorDirectoryExists(at url: URL) -> Bool {
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
}

func recentEditorItems<T: Decodable>(forKey key: String, as type: T.Type = T.self) -> [T] {
    guard let data = UserDefaults.standard.data(forKey: key) else {
        return []
    }
    return (try? JSONDecoder().decode([T].self, from: data)) ?? []
}

func saveRecentEditorItems<T: Encodable>(_ items: [T], forKey key: String) {
    guard let data = try? JSONEncoder().encode(items) else {
        return
    }
    UserDefaults.standard.set(data, forKey: key)
}

func addingRecentEditorItem<T: Identifiable & Equatable>(_ item: T, to items: [T], limit: Int = 7) -> [T] where T.ID: Equatable {
    var next = items.filter { $0.id != item.id }
    next.insert(item, at: 0)
    if next.count > limit {
        next.removeLast(next.count - limit)
    }
    return next
}

private var defaultEditorFileDirectoryURL: URL {
    FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Documents", isDirectory: true)
        .appendingPathComponent("Forest FB-01 Editor", isDirectory: true)
}

private var defaultEditorBackupDirectoryURL: URL {
    defaultEditorFileDirectoryURL.appendingPathComponent("Backups", isDirectory: true)
}

func safeEditorFileName(_ name: String, fallback: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let base = trimmed.isEmpty ? fallback : trimmed
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
    let sanitized = base
        .unicodeScalars
        .map { allowed.contains($0) ? Character($0) : "-" }
        .reduce("") { $0 + String($1) }
    return sanitized.isEmpty ? fallback : sanitized
}

func editorDocumentName(fromFileURL url: URL, maxLength: Int, fallback: String) -> String {
    let stem = url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
    let base = stem.isEmpty ? fallback : stem
    return String(base.prefix(maxLength))
}

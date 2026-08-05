import AppKit
import FB01Editor
import Foundation

enum EditorDocumentTemplates {
    static func voicePayload(systemChannel: Int = 0) -> SynthVoiceDocumentPayload<FB01VoiceData> {
        SynthVoiceDocumentPayload(
            moduleIdentity: EditorSynthModule.identity,
            voice: voice(),
            systemChannel: systemChannel
        )
    }

    static func configurationPayload(systemChannel: Int = 0) -> SynthConfigurationDocumentPayload<FB01ConfigurationData> {
        SynthConfigurationDocumentPayload(
            moduleIdentity: EditorSynthModule.identity,
            configuration: configuration(),
            systemChannel: systemChannel
        )
    }

    static func voice() -> FB01VoiceData {
        do {
            return try FB01ModuleServices.shared.documentService.templateVoice()
        } catch {
            fatalError("Unable to create template voice: \(error)")
        }
    }

    static func configuration() -> FB01ConfigurationData {
        do {
            return try FB01ModuleServices.shared.documentService.templateConfiguration()
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
        case currentVoice
        case instrument
        case bank
        case voiceRAM1
        case dx100Bank
    }

    var device: EditorDeviceSelection?
    var kind: SourceKind
    var instrument: Int?
    var bank: Int?
    var voiceNumber: Int?
    var title: String

    var id: String {
        let devicePrefix = device?.rawValue ?? "fb01"
        switch kind {
        case .currentVoice:
            return "\(devicePrefix)-current-voice"
        case .instrument:
            return "\(devicePrefix)-instrument-\(instrument ?? 0)"
        case .bank:
            return "\(devicePrefix)-bank-\(bank ?? 0)-voice-\(voiceNumber ?? 0)"
        case .voiceRAM1:
            return "\(devicePrefix)-voiceRAM1-\(voiceNumber ?? 0)"
        case .dx100Bank:
            return "\(devicePrefix)-dx100-bank-\(bank ?? 0)-voice-\(voiceNumber ?? 0)"
        }
    }

    var source: VoiceDocumentFetchSource? {
        switch kind {
        case .currentVoice:
            return .currentVoice
        case .instrument:
            guard let instrument else { return nil }
            return .instrument(instrument)
        case .bank:
            guard let bank, let voiceNumber else { return nil }
            return .storedSlot(location: .bank(bank), voiceNumber: voiceNumber)
        case .voiceRAM1:
            guard let voiceNumber else { return nil }
            return .storedSlot(location: .voiceRAM1, voiceNumber: voiceNumber)
        case .dx100Bank:
            guard let bank, let voiceNumber else { return nil }
            return .dx100Bank(bank: bank, voiceNumber: voiceNumber)
        }
    }

    func isCompatible(with selectedDevice: EditorDeviceSelection?) -> Bool {
        guard let device else {
            return true
        }
        return device == selectedDevice
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

enum VoiceDocumentFetchSource: Sendable, Equatable {
    case currentVoice
    case instrument(Int)
    case storedSlot(location: VoiceDocumentFetchLocation, voiceNumber: Int)
    case dx100Bank(bank: Int, voiceNumber: Int)

    func title(nameLookup: VoiceDocumentFetchNameLookup = .empty) -> String {
        switch self {
        case .currentVoice:
            return "current voice"
        case .instrument(let instrument):
            return "instrument \(instrument + 1) voice"
        case let .storedSlot(location, voiceNumber):
            return nameLookup.sourceTitle(location: location, voiceNumber: voiceNumber + 1)
        case let .dx100Bank(bank, voiceNumber):
            return "DX100/27 Bank \(bank) Voice \(voiceNumber + 1)"
        }
    }
}

enum VoiceDocumentFetchLocation: Sendable, Equatable {
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

    var serviceLocation: FB01VoiceFetchLocation {
        switch self {
        case .bank(let bank):
            .bank(bank)
        case .voiceRAM1:
            .voiceRAM1
        }
    }

    var menuTitle: String {
        let module = EditorSynthModule.module
        let vocabulary = module.vocabulary
        return switch self {
        case .bank(let bank) where module.isWritableVoiceBank(bank):
            "Bank \(bank) \(vocabulary.writableVoiceBankSuffix)"
        case .bank(let bank):
            "Bank \(bank) \(vocabulary.readOnlyVoiceBankSuffixPrefix)\(bank - module.writableVoiceBanks.count)"
        case .voiceRAM1:
            "Voice RAM 1"
        }
    }
}

struct FB01FactoryVoiceNames {
    static var namesByBank: [Int: [String]] {
        EditorSynthModule.module.factoryVoiceNamesByBank
    }

    static func name(bank: Int, voiceNumber: Int) -> String? {
        EditorSynthModule.module.factoryVoiceName(bank: bank, voiceNumber: voiceNumber)
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
        let module = EditorSynthModule.module
        switch location {
        case .bank(let bank) where module.isWritableVoiceBank(bank):
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
        case .bank(let bank) where EditorSynthModule.module.isWritableVoiceBank(bank):
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
            if case .bank(let bank) = location, EditorSynthModule.module.isWritableVoiceBank(bank) {
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
    static var namesBySlot: [Int: String] {
        EditorSynthModule.module.factoryConfigurationNamesBySlot
    }

    static func name(slot: Int) -> String? {
        EditorSynthModule.module.factoryConfigurationName(slot: slot)
    }
}

struct ConfigurationFetchNameLookup: Sendable {
    static let empty = ConfigurationFetchNameLookup(storedNames: [:])

    var storedNames: [Int: String]

    func name(slot: Int) -> String? {
        storedNames[slot] ?? FB01FactoryConfigurationNames.name(slot: slot)
    }

    func menuTitle(slot: Int) -> String {
        let readOnly = EditorSynthModule.module.isWritableConfigurationSlot(slot) ? "" : " Read Only"
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

struct VoiceBankSelectorItem: Identifiable, Equatable {
    var bank: Int
    var zeroBasedVoiceNumber: Int
    var name: String
    var source: VoiceDocumentFetchSource
    var fetchTitleOverride: String?

    var id: String {
        switch source {
        case .dx100Bank(let bank, let voiceNumber):
            return "dx100-bank-\(bank)-voice-\(voiceNumber)"
        default:
            return "bank-\(bank)-voice-\(zeroBasedVoiceNumber)"
        }
    }

    var displayNumber: Int {
        zeroBasedVoiceNumber + 1
    }

    var title: String {
        name.isEmpty ? "Voice \(displayNumber)" : name
    }

    var fetchTitle: String {
        fetchTitleOverride ?? "Bank \(bank) Voice \(displayNumber): \(title)"
    }
}

struct ConfigurationSelectorItem: Identifiable, Equatable {
    var slot: Int
    var name: String

    var id: Int { slot }

    var displayNumber: Int { slot }

    var title: String {
        name.isEmpty ? "Configuration \(slot)" : name
    }

    var fetchTitle: String {
        "Configuration \(slot) - \(title)"
    }

    var options: ConfigurationFetchOptions {
        ConfigurationFetchOptions(isCurrent: false, slot: slot - 1)
    }
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
        .appendingPathComponent("Forest Editor", isDirectory: true)
}

private var defaultEditorBackupDirectoryURL: URL {
    defaultEditorFileDirectoryURL.appendingPathComponent("Backups", isDirectory: true)
}

func safeEditorFileName(_ name: String, fallback: String) -> String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let base = trimmed.isEmpty ? fallback : trimmed
    let disallowed = CharacterSet(charactersIn: "/:\\")
    let controlCharacters = CharacterSet.controlCharacters
    let sanitized = base
        .unicodeScalars
        .map { disallowed.contains($0) || controlCharacters.contains($0) ? "-" : Character($0) }
        .reduce("") { $0 + String($1) }
    return sanitized.isEmpty ? fallback : sanitized
}

func editorDocumentName(fromFileURL url: URL, maxLength: Int, fallback: String) -> String {
    let stem = url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
    let base = stem.isEmpty ? fallback : stem
    return String(base.prefix(maxLength))
}

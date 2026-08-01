import FB01Editor

enum EditorSynthModule {
    static var adapter: FB01ModuleAdapter {
        FB01ModuleAdapter.shared
    }

    static var module: FB01SynthModule {
        adapter.module
    }

    static var identity: SynthModuleIdentity {
        adapter.identity
    }

    static var capabilities: SynthModuleCapabilities {
        adapter.capabilities
    }

    static var vocabulary: SynthModuleVocabulary {
        module.vocabulary
    }

    static var supportedDocumentDescriptors: [SynthDocumentDescriptor] {
        module.supportedDocumentDescriptors
    }

    static var commandDescriptors: [SynthModuleCommandDescriptor] {
        module.commandDescriptors
    }

    static var fileProfile: SynthFileProfile {
        module.fileProfile
    }

    static func documentDescriptor(for kind: SynthDocumentKind) -> SynthDocumentDescriptor? {
        supportedDocumentDescriptors.first { $0.kind == kind }
    }

    static func commandDescriptor(for kind: SynthModuleCommandKind) -> SynthModuleCommandDescriptor? {
        commandDescriptors.first { $0.kind == kind }
    }
}

enum EditorFeatureAvailability {
    static func supportsCommand(_ kind: SynthModuleCommandKind) -> Bool {
        EditorSynthModule.commandDescriptor(for: kind) != nil
    }

    static func commandTitle(_ kind: SynthModuleCommandKind, fallback: String) -> String {
        EditorSynthModule.commandDescriptor(for: kind)?.displayName ?? fallback
    }
}

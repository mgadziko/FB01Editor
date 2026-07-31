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

    static var fileProfile: SynthFileProfile {
        module.fileProfile
    }

    static func documentDescriptor(for kind: SynthDocumentKind) -> SynthDocumentDescriptor? {
        supportedDocumentDescriptors.first { $0.kind == kind }
    }
}

enum FB01UIFeatureAvailability {
    private static var capabilities: SynthModuleCapabilities {
        EditorSynthModule.capabilities
    }

    static var supportsConfigurations: Bool {
        capabilities.supportsConfigurations
    }

    static var supportsGeneralMIDIInstall: Bool {
        capabilities.supportsGeneralMIDIInstall
    }

    static var supportsMemoryProtect: Bool {
        capabilities.supportsMemoryProtect
    }
}

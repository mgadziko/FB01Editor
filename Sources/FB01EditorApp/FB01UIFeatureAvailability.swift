import FB01Editor

enum FB01UIFeatureAvailability {
    private static var capabilities: SynthModuleCapabilities {
        FB01ModuleAdapter.shared.capabilities
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

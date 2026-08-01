public struct FB01ModuleAdapter: SynthModuleServiceProviding {
    public typealias Module = FB01SynthModule

    public static let shared = FB01ModuleAdapter(services: .shared)

    public var services: FB01ModuleServices

    public init(services: FB01ModuleServices) {
        self.services = services
    }

    public var module: FB01SynthModule {
        services.module
    }

    public var identity: SynthModuleIdentity {
        module.identity
    }

    public var capabilities: SynthModuleCapabilities {
        module.capabilities
    }

    public var supportedDocumentKinds: [SynthDocumentKind] {
        module.supportedDocumentKinds
    }

    public var commandDescriptors: [SynthModuleCommandDescriptor] {
        module.commandDescriptors
    }

    public var parameterBindingDescriptors: [SynthParameterBindingDescriptor] {
        module.parameterBindingDescriptors
    }
}

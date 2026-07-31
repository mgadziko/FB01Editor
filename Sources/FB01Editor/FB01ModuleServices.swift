public struct FB01ModuleServices: Sendable {
    public static let shared = FB01ModuleServices()

    public let module = FB01SynthModule.shared
    public let deviceService = FB01DeviceService.shared
    public let voiceService = FB01VoiceService.shared
    public let configurationService = FB01ConfigurationService.shared
    public let cacheService = FB01DeviceCacheService.shared

    private init() {}
}

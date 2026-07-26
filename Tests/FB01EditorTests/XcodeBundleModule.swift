import Foundation

#if !SWIFT_PACKAGE
private final class XcodeBundleModuleToken {}

extension Bundle {
    static let module = Bundle(for: XcodeBundleModuleToken.self)
}
#endif

import Foundation
import Security

/// What PawGuard's own code signature means for permissions that outlive a
/// build.
///
/// macOS stores an Accessibility grant against the *designated requirement* of
/// the app it was granted to, not against a path or a name. That requirement
/// depends entirely on how the app was signed:
///
/// - Signed with a real identity, the requirement names the bundle identifier
///   and the signing certificate, both of which survive a rebuild. A grant
///   keeps working.
/// - Signed ad hoc — which is what Xcode does when no development team is set,
///   the option it calls "Sign to Run Locally" — the requirement is the exact
///   hash of that exact binary. Rebuilding produces a different hash, so the
///   stored grant no longer matches anything and `AXIsProcessTrusted()` returns
///   false again.
///
/// The second case is confusing in a specific way: System Settings still shows
/// a PawGuard row with its switch on, because that row belongs to the previous
/// binary. Toggling it cannot help, and re-granting only lasts until the next
/// build. PawGuard therefore checks its own signature so it can say this
/// outright rather than waiting for a permission that will never arrive.
enum CodeSignatureInfo {
    /// The ad-hoc code directory flag, from `cs_blobs.h`.
    private static let adhocFlag: UInt32 = 0x2

    /// Whether this build's Accessibility grant will be invalidated by the next
    /// rebuild.
    ///
    /// Computed once: a running app cannot change its own signature.
    static let isAdHocSigned: Bool = {
        var staticCode: SecStaticCode?
        guard
            SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &staticCode) == errSecSuccess,
            let staticCode
        else {
            return false
        }

        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard
            SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
            let details = information as? [String: Any]
        else {
            return false
        }

        guard let codeFlags = details[kSecCodeInfoFlags as String] as? UInt32 else { return false }
        return codeFlags & adhocFlag != 0
    }()
}

import Foundation

/// Known publishing targets requiring secret resolution.
public enum PublishTargets {
    public static let standardSite = "standard.site"
    public static let nostr = "nostr"
    public static let githubPages = "github.pages"
}

/// A seam protocol for vending secrets to publishing commands without exposing store implementations.
public protocol SecretProviding: Sendable {
    /// Provides the secret for the given target, if available.
    func provideSecret(for target: String) -> SecureBuffer?
}

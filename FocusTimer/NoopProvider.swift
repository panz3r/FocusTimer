import Foundation

/// The "off" provider. Every call is a no-op — no network traffic, no
/// stored state — so callers never special-case a disabled social layer.
final class NoopProvider: SocialProvider {
    var isConfigured: Bool { false }
    var displayName: String { "Disabled" }

    func registerUsername(_ name: String) async throws {}
    func postTodayStats(_ stats: TodayStats) async throws {}
    func fetchFriendsStats(usernames: [String]) async throws -> [FriendStats] {
        return []
    }
}

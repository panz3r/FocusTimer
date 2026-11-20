import Foundation

// MARK: - Shared model (Area 2)

/// One day of the local user's stats, pushed to the configured backend
/// after each completed work session.
struct TodayStats: Codable {
    let username: String
    let date: String              // yyyy-MM-dd in the user's calendar zone
    let sessions: Int
    let focusMinutes: Int
    let streak: Int
    let exportedAt: Date
}

/// A friend's current numbers, fetched from the configured backend.
struct FriendStats: Codable, Identifiable {
    let username: String
    let sessions: Int             // today
    let focusMinutes: Int         // today
    let streak: Int
    var lastUpdated: Date?        // optional: backends may omit it
    var id: String { username }
}

// MARK: - Config

/// Persisted at UserDefaults["social.config"]. Deny-by-default (cross-
/// cutting item L): a fresh install decodes to provider .none with no
/// inherited URLs or keys, and nothing in the app talks to the network
/// until the user explicitly configures a backend here.
struct SocialConfig: Codable {
    enum Provider: String, Codable, CaseIterable {
        case supabase, webhook, none
    }

    var provider: Provider = .none
    var baseURL: URL? = nil       // Supabase project URL or webhook base URL
    var anonKey: String? = nil    // Supabase publishable key
    var bearerToken: String? = nil
    var username: String? = nil   // local identity, user-set
    var usernames: [String] = []  // friend list, capped at 25

    static func load() -> SocialConfig {
        guard let data = UserDefaults.standard.data(forKey: "social.config"),
              let config = try? JSONDecoder().decode(SocialConfig.self, from: data) else {
            return SocialConfig()
        }
        return config
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "social.config")
        }
    }

    /// True only when the user explicitly picked a provider and gave it
    /// the values it needs. Never true by default.
    var isExplicitlyEnabled: Bool {
        switch provider {
        case .none:     return false
        case .supabase: return baseURL != nil && anonKey != nil
        case .webhook:  return baseURL != nil
        }
    }
}

// MARK: - Errors

enum SocialError: LocalizedError {
    case notConfigured
    case usernameTaken
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured:          return String(localized: "Social backend is not configured.")
        case .usernameTaken:          return String(localized: "Username already taken.")
        case .invalidResponse:        return String(localized: "Unexpected response from the social backend.")
        case .httpStatus(let code):   return String(localized: "Social backend error (HTTP \(code)).")
        }
    }
}

// MARK: - Provider protocol

/// Sendable: implementations are an actor (Supabase) or immutable classes
/// over the value-typed SocialConfig, and every method is async.
protocol SocialProvider: Sendable {
    var isConfigured: Bool { get }
    var displayName: String { get }

    /// Registers the local identity on backends that need a server-side
    /// profile. Local-identity providers (webhook) store nothing.
    func registerUsername(_ name: String) async throws

    /// Pushes today's stats for the local user.
    func postTodayStats(_ stats: TodayStats) async throws

    /// Fetches current numbers for the listed usernames. Order is not
    /// guaranteed; usernames the backend doesn't know are omitted.
    func fetchFriendsStats(usernames: [String]) async throws -> [FriendStats]
}

// MARK: - Registry

enum SocialProviderRegistry {
    /// Builds the provider for the given config. Call sites load the
    /// config fresh (cheap UserDefaults read) rather than holding state.
    static func activeProvider(using config: SocialConfig) -> SocialProvider {
        switch config.provider {
        case .supabase: return SupabaseProvider(config: config)
        case .webhook:  return WebhookProvider(config: config)
        case .none:     return NoopProvider()
        }
    }
}

import Foundation

/// SocialProvider implementation for a plain user-configured HTTP backend
/// (a Cloudflare Worker, Pipedream/n8n flow, or any small server).
///
/// Contract (documented in the plan and in the Settings UI):
///   POST {baseURL}/today    body: TodayStats (JSON, ISO-8601 dates)
///   POST {baseURL}/friends  body: {"usernames": ["a","b", …]}
///                           → [FriendStats]
///   Auth: optional "Authorization: Bearer {token}"
///
/// Both endpoints are POST so usernames never appear in URL query strings
/// (proxies and access logs record full URLs). Identity is server-defined;
/// TodayStats carries the locally-set username for reference, and
/// registerUsername is a no-op because there is no Supabase-style profile
/// table.
final class WebhookProvider: SocialProvider {
    private let config: SocialConfig

    init(config: SocialConfig) {
        self.config = config
    }

    var isConfigured: Bool { config.baseURL != nil }

    var displayName: String { "Webhook (\(config.baseURL?.host ?? "—"))" }

    func registerUsername(_ name: String) async throws {
        // No server-side profile: the identity is whatever the backend
        // derives (e.g., from the bearer token). Nothing to register.
    }

    func postTodayStats(_ stats: TodayStats) async throws {
        guard let baseURL = config.baseURL else { throw SocialError.notConfigured }
        var req = URLRequest(url: baseURL.appendingPathComponent("today"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in authHeaders() { req.setValue(value, forHTTPHeaderField: key) }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        req.httpBody = try encoder.encode(stats)
        let (_, resp) = try await URLSession.shared.data(for: req)
        try Self.validate(resp)
    }

    func fetchFriendsStats(usernames: [String]) async throws -> [FriendStats] {
        guard let baseURL = config.baseURL else { throw SocialError.notConfigured }
        var req = URLRequest(url: baseURL.appendingPathComponent("friends"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in authHeaders() { req.setValue(value, forHTTPHeaderField: key) }
        req.httpBody = try JSONEncoder().encode(["usernames": usernames])
        let (data, resp) = try await URLSession.shared.data(for: req)
        try Self.validate(resp)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([FriendStats].self, from: data)
    }

    private func authHeaders() -> [(key: String, value: String)] {
        guard let token = config.bearerToken?.trimmingCharacters(in: .whitespaces), !token.isEmpty else {
            return []
        }
        return [("Authorization", "Bearer \(token)")]
    }

    private static func validate(_ resp: URLResponse) throws {
        guard let http = resp as? HTTPURLResponse else { throw SocialError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw SocialError.httpStatus(http.statusCode) }
    }
}

import Foundation

/// SocialProvider implementation for a Supabase-compatible backend
/// (Upstream's hosted instance or any self-hosted one). URL and publishable
/// key come from SocialConfig — nothing is hardcoded (cross-cutting item L).
///
/// Identity: an anonymous per-device account (generated email + UUID
/// password) created on first use, exactly like the upstream flow. The
/// display username is registered into the `profiles` table so friends
/// can find this user.
actor SupabaseProvider: SocialProvider {
    private let config: SocialConfig

    private var token: String?
    private var uid: String?

    init(config: SocialConfig) {
        self.config = config
        token = UserDefaults.standard.string(forKey: UserDefaultsKeys.supabaseToken)
        uid = UserDefaults.standard.string(forKey: UserDefaultsKeys.supabaseUserId)
    }

    nonisolated var isConfigured: Bool { config.baseURL != nil && config.anonKey != nil }

    nonisolated var displayName: String { "Supabase (\(config.baseURL?.host ?? "—"))" }

    private nonisolated var baseURL: String { config.baseURL?.absoluteString ?? "" }
    private nonisolated var anon: String { config.anonKey ?? "" }

    // MARK: - Identity

    func registerUsername(_ name: String) async throws {
        try await ensureAuthenticated()
        guard let id = uid else { throw SocialError.notConfigured }
        do {
            // Upsert keyed on our own id: re-registering under the same
            // account just renames; a conflict means someone else owns it.
            try await upsert("/rest/v1/profiles", body: ["id": id, "username": name])
        } catch let error as SupabaseError {
            if case .conflict = error { throw SocialError.usernameTaken }
            throw error
        }
    }

    // MARK: - Stats

    func postTodayStats(_ stats: TodayStats) async throws {
        try await ensureAuthenticated()
        guard let id = uid else { throw SocialError.notConfigured }
        try await upsert("/rest/v1/daily_stats", body: [
            "user_id": id, "date": stats.date,
            "sessions": stats.sessions, "focus_minutes": stats.focusMinutes, "streak": stats.streak
        ])
    }

    /// Resolves usernames through the `profiles` table, then reads those
    /// users' last-7-day `daily_stats` rows and reduces to today's numbers.
    func fetchFriendsStats(usernames: [String]) async throws -> [FriendStats] {
        try await ensureAuthenticated()
        guard !usernames.isEmpty else { return [] }
        let list = usernames.joined(separator: ",")
        let profiles = try await get("/rest/v1/profiles", query: [
            "username": "in.(\(list))", "select": "*"
        ])
        let ids = profiles.compactMap { $0["id"] as? String }
        guard !ids.isEmpty else { return [] }

        let since = DateFormatter.yyyyMMdd.string(
            from: Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
        )
        let rows = try await get("/rest/v1/daily_stats", query: [
            "user_id": "in.(\(ids.joined(separator: ",")))", "date": "gte.\(since)", "select": "*"
        ])
        let today = DateFormatter.yyyyMMdd.string(from: Date())

        return profiles.compactMap { p in
            guard let id = p["id"] as? String,
                  let username = p["username"] as? String else { return nil }
            let mine = rows.filter { ($0["user_id"] as? String) == id }
            let todayRow = mine.first(where: { ($0["date"] as? String) == today })
            return FriendStats(
                username: username,
                sessions: todayRow?["sessions"] as? Int ?? 0,
                focusMinutes: todayRow?["focus_minutes"] as? Int ?? 0,
                streak: todayRow?["streak"] as? Int ?? 0,
                lastUpdated: Date()
            )
        }
    }

    // MARK: - Auth (upstream-compatible anonymous device accounts)

    func ensureAuthenticated() async throws {
        if token != nil, uid != nil { return }
        do    { try await signIn()  }
        catch { try await signUp()  }
    }

    private func signUp() async throws {
        let body: [String: Any] = ["email": deviceEmail, "password": deviceId]
        let r = try await authPost("/auth/v1/signup", body: body)
        guard let tok = r["access_token"] as? String,
              let u   = (r["user"] as? [String: Any])?["id"] as? String
        else { throw SupabaseError.authFailed }
        store(token: tok, uid: u)
    }

    private func signIn() async throws {
        let body: [String: Any] = ["email": deviceEmail, "password": deviceId]
        let r = try await authPost("/auth/v1/token?grant_type=password", body: body)
        guard let tok = r["access_token"] as? String,
              let u   = (r["user"] as? [String: Any])?["id"] as? String
        else { throw SupabaseError.authFailed }
        store(token: tok, uid: u)
    }

    private func reAuth() async throws {
        token = nil; uid = nil
        try await signIn()
    }

    private var deviceId: String {
        if let id = UserDefaults.standard.string(forKey: UserDefaultsKeys.supabaseDeviceId) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: UserDefaultsKeys.supabaseDeviceId)
        return id
    }

    private var deviceEmail: String {
        let safe = deviceId.prefix(16).lowercased().filter(\.isHexDigit)
        return "d\(safe)@focustimer.local"
    }

    private func store(token t: String, uid u: String) {
        token = t; uid = u
        UserDefaults.standard.set(t, forKey: UserDefaultsKeys.supabaseToken)
        UserDefaults.standard.set(u, forKey: UserDefaultsKeys.supabaseUserId)
    }

    // MARK: - HTTP

    private func get(_ path: String, query: [String: String]) async throws -> [[String: Any]] {
        var comps = URLComponents(string: baseURL + path)!
        comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        setBaseHeaders(&req)
        let (data, resp) = try await URLSession.shared.data(for: req)
        if (resp as? HTTPURLResponse)?.statusCode == 401 {
            try await reAuth()
            return try await get(path, query: query)
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]) ?? []
    }

    private func upsert(_ path: String, body: [String: Any]) async throws {
        var req = URLRequest(url: URL(string: baseURL + path)!)
        req.httpMethod = "POST"
        setBaseHeaders(&req)
        req.setValue("resolution=merge-duplicates,return=minimal", forHTTPHeaderField: "Prefer")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let (_, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 { try await reAuth(); try await upsert(path, body: body) }
        else if code == 409 { throw SupabaseError.conflict }
    }

    private func authPost(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: baseURL + path)!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(anon, forHTTPHeaderField: "apikey")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: req)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SupabaseError.decodingError
        }
        if let msg = json["error_description"] as? String { throw SupabaseError.serverError(msg) }
        if let msg = json["msg"] as? String, json["access_token"] == nil { throw SupabaseError.serverError(msg) }
        return json
    }

    private func setBaseHeaders(_ req: inout URLRequest) {
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(anon, forHTTPHeaderField: "apikey")
        if let t = token { req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
    }
}

enum SupabaseError: LocalizedError {
    case authFailed, notAuthenticated, conflict, decodingError, serverError(String)

    var errorDescription: String? {
        switch self {
        case .authFailed:          return "Sign-in failed. Check your Supabase config and make sure email confirmation is disabled."
        case .notAuthenticated:    return "Not signed in."
        case .conflict:            return "Username already taken."
        case .decodingError:       return "Unexpected server response."
        case .serverError(let m):  return m
        }
    }
}

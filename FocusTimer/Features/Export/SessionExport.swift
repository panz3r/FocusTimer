import AppKit
import Foundation
import UniformTypeIdentifiers

// MARK: - Formats

enum ExportFormat: String, CaseIterable {
    case jsonBackup = "JSON backup"
    case csv        = "CSV"
    case markdown   = "Markdown"

    var fileExtension: String {
        switch self {
        case .jsonBackup: return "json"
        case .csv:        return "csv"
        case .markdown:   return "md"
        }
    }

    var utType: UTType {
        switch self {
        case .jsonBackup: return .json
        case .csv:        return .commaSeparatedText
        case .markdown:   return UTType(filenameExtension: "md") ?? .plainText
        }
    }
}

// MARK: - Backup envelope (round-trippable JSON)

struct BackupPayload: Codable {
    static let currentSchemaVersion = 1
    static let kindIdentifier = "focus-timer.backup"

    let schemaVersion: Int
    let kind: String
    let exportedAt: Date
    let appVersion: String
    let dailyStats: [String: StatsStore.DaySnapshot]
    let sessionLog: [StatsStore.SessionEntry]
}

// MARK: - Errors

enum SessionExportError: LocalizedError {
    case decodingFailed
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .decodingFailed:        return String(localized: "This file isn't a FocusTimer JSON backup.")
        case .writeFailed(let path): return String(localized: "Couldn't write to \(path).")
        }
    }
}

// MARK: - Export / import

enum SessionExport {

    private static let iso8601 = ISO8601DateFormatter()

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private static var fileStamp: String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmm"
        return f.string(from: Date())
    }

    // MARK: Payload builders

    static func makeBackupPayload(store: StatsStore = .shared) -> BackupPayload {
        BackupPayload(
            schemaVersion: BackupPayload.currentSchemaVersion,
            kind: BackupPayload.kindIdentifier,
            exportedAt: Date(),
            appVersion: appVersion,
            dailyStats: store.dailyStatsSnapshot,
            sessionLog: store.sessionLog
        )
    }

    static func makeJSONData(store: StatsStore = .shared) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(makeBackupPayload(store: store))
    }

    static func makeCSVData(store: StatsStore = .shared) -> Data {
        var lines = ["timestamp,kind,duration_minutes,task_label"]
        for e in store.sessionLog {
            // The current codebase records work sessions only; Area 4 widens this.
            lines.append("\(iso8601.string(from: e.timestamp)),work,\(e.durationMinutes),\(csvField(e.taskLabel))")
        }
        return Data(lines.joined(separator: "\n").utf8)
    }

    /// RFC 4180: always quote; escape embedded quotes by doubling.
    private static func csvField(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    static func makeMarkdownData(store: StatsStore = .shared, days: Int = 7) -> Data {
        let cal = Calendar.current
        let history = store.history(days: days)

        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEE MMM d"
        let titleFormatter = DateFormatter()
        titleFormatter.dateFormat = "MMM d, yyyy"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        var md = "# Focus \(days == 7 ? "week" : "\(days) days") — "
        if let first = history.first?.date, let last = history.last?.date {
            md += "\(titleFormatter.string(from: first)) to \(titleFormatter.string(from: last))\n\n"
        }
        md += "| Day | Sessions | Focus time | Streak |\n"
        md += "|-----|----------|------------|--------|\n"
        for day in history {
            md += "| \(dayFormatter.string(from: day.date)) | \(day.sessions) | \(focusTime(day.focusMinutes)) | \(streakEnding(on: day.date, store: store)) |\n"
        }

        let totalSessions = history.reduce(0) { $0 + $1.sessions }
        let totalMinutes = history.reduce(0) { $0 + $1.focusMinutes }
        md += "\n**Totals:** \(totalSessions) session\(totalSessions == 1 ? "" : "s"), \(focusTime(totalMinutes)) focus time.\n"

        let cutoff = cal.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        var counts: [String: Int] = [:]
        for e in store.sessionLog where e.timestamp >= cutoff {
            let label = e.taskLabel.trimmingCharacters(in: .whitespaces)
            guard !label.isEmpty else { continue }
            counts[label, default: 0] += 1
        }
        let top = counts.sorted { $0.value > $1.value }.prefix(3)
        if !top.isEmpty {
            let parts = top.map { "\"\($0.key)\" (\($0.value))" }
            md += "**Top labels:** \(parts.joined(separator: ", "))\n"
        }

        md += "\n> Generated by FocusTimer v\(appVersion) · \(dayFormatter.string(from: Date())) \(timeFormatter.string(from: Date()))\n"
        return Data(md.utf8)
    }

    /// Consecutive days with sessions, ending on (and including) `date`.
    /// A day with no sessions has streak 0.
    private static func streakEnding(on date: Date, store: StatsStore) -> Int {
        let cal = Calendar.current
        var streak = 0
        var day = cal.startOfDay(for: date)
        while store.dayRecord(for: day).sessions > 0 {
            streak += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = prev
        }
        return streak
    }

    private static func focusTime(_ minutes: Int) -> String {
        guard minutes > 0 else { return "0m" }
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    // MARK: Export

    /// Writes the chosen file, plus keeps an archival JSON copy under
    /// ~/Library/Application Support/FocusTimer/backups/ so a latest export
    /// can always be found even if the user forgets where they saved it.
    static func export(to url: URL, format: ExportFormat, store: StatsStore = .shared) throws {
        let data: Data
        switch format {
        case .jsonBackup: data = try makeJSONData(store: store)
        case .csv:        data = makeCSVData(store: store)
        case .markdown:   data = makeMarkdownData(store: store)
        }
        do { try data.write(to: url, options: .atomic) }
        catch { throw SessionExportError.writeFailed(url.path) }
        archiveJSONCopy(store: store)
    }

    static func archiveJSONCopy(store: StatsStore = .shared) {
        let fm = FileManager.default
        let dir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/FocusTimer/backups", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        let file = dir.appendingPathComponent("focus-\(f.string(from: Date())).json")
        if let data = try? makeJSONData(store: store) {
            try? data.write(to: file, options: .atomic)
        }
    }

    // MARK: Import

    static func loadPayload(from url: URL) throws -> BackupPayload {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(BackupPayload.self, from: data),
              payload.kind == BackupPayload.kindIdentifier else {
            throw SessionExportError.decodingFailed
        }
        return payload
    }

    /// Counts what an import would change, without applying it. Used for the
    /// confirmation dialog ("merge N new sessions, update M days").
    static func diff(for payload: BackupPayload, store: StatsStore = .shared) -> (newSessions: Int, changedDays: Int) {
        var changedDays = 0
        for (day, inc) in payload.dailyStats {
            let cur = store.dayStats(for: day)
            if max(cur.sessions, inc.sessions) != cur.sessions
                || max(cur.focusMinutes, inc.focusMinutes) != cur.focusMinutes {
                changedDays += 1
            }
        }
        let known = Set(store.sessionLog.map(\.id))
        let newSessions = payload.sessionLog.filter { !known.contains($0.id) }.count
        return (newSessions, changedDays)
    }

    /// Applies the merge (max-of per day, log union by id) through StatsStore.
    @discardableResult
    static func apply(_ payload: BackupPayload, store: StatsStore = .shared) -> (newSessions: Int, changedDays: Int) {
        store.mergeImport(dailyStats: payload.dailyStats, sessionLog: payload.sessionLog)
    }

    // MARK: Panels (shared by Settings and Stats)

    /// Default filename per format, matching the plan's examples.
    private static func defaultFileName(for format: ExportFormat) -> String {
        switch format {
        case .jsonBackup: return "FocusTimer-backup-\(fileStamp).json"
        case .csv:        return "FocusTimer-sessions-\(fileStamp).csv"
        case .markdown:   return "FocusTimer-week-\(fileStamp).md"
        }
    }

    /// Save panel for a manual export in a specific format.
    /// Returns true when a file was written.
    @discardableResult
    static func runExportDialog(_ format: ExportFormat) -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.utType]
        panel.nameFieldStringValue = defaultFileName(for: format)
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try export(to: url, format: format)
            return true
        } catch {
            failureAlert(error)
            return false
        }
    }

    /// Open panel + confirm + merge. Returns true when data was applied.
    @discardableResult
    static func runImportDialog(onApplied: (() -> Void)? = nil) -> Bool {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            let payload = try loadPayload(from: url)
            let diff = diff(for: payload)
            if diff.newSessions == 0 && diff.changedDays == 0 {
                let alert = NSAlert()
                alert.messageText = String(localized: "Nothing to import")
                alert.informativeText = String(localized: "This backup doesn't contain any data that isn't already in your history.")
                alert.runModal()
                return false
            }
            let alert = NSAlert()
            alert.messageText = String(localized: "Import backup?")
            alert.informativeText = String(localized: "This will merge \(diff.newSessions) new session(s) and update \(diff.changedDays) day(s) of stats. Your current data is kept.")
            alert.addButton(withTitle: String(localized: "Import"))
            alert.addButton(withTitle: String(localized: "Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
            apply(payload)
            onApplied?()
            return true
        } catch {
            failureAlert(error)
            return false
        }
    }

    private static func failureAlert(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Backup failed")
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}

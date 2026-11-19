import Foundation

/// Weekly auto-export (Area 1). Follows the DigestChecker polling pattern:
/// a 30-minute timer checks whether we're inside the export window
/// (Sunday from 21:00) and whether this week already ran. Polling is
/// sleep-tolerant — a missed Sunday evening is picked up by any later
/// poll that same Sunday.
final class BackupScheduler {
    static let shared = BackupScheduler()

    private var timer: Timer?
    private init() {}

    private var jsonEnabled: Bool {
        UserDefaults.standard.object(forKey: UserDefaultsKeys.weeklyBackupEnabled) as? Bool ?? false
    }

    private var markdownEnabled: Bool {
        UserDefaults.standard.object(forKey: UserDefaultsKeys.weeklyBackupMarkdownEnabled) as? Bool ?? false
    }

    private var isEnabled: Bool { jsonEnabled }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
            self?.check()
        }
        check()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Called from TimerViewModel setting didSets so the timer tracks the
    /// enabled state without callers caring which flag changed.
    func restartIfNeeded() {
        isEnabled ? start() : stop()
    }

    private func check() {
        guard isEnabled else { return }
        let cal = Calendar.current
        let now = Date()
        guard cal.component(.weekday, from: now) == 1,   // Sunday
              cal.component(.hour, from: now) >= 21      // from 9 pm onward
        else { return }

        let thisWeek = cal.component(.weekOfYear, from: now)
        let lastWeek = UserDefaults.standard.integer(forKey: UserDefaultsKeys.weeklyBackupLastRunWeek)
        guard thisWeek != lastWeek else { return }

        do {
            let folder = try Self.backupFolder()
            if jsonEnabled {
                let jsonURL = folder.appendingPathComponent("FocusTimer-backup-\(Self.stamp(now)).json")
                try SessionExport.makeJSONData().write(to: jsonURL, options: .atomic)
            }
            if markdownEnabled {
                let mdURL = folder.appendingPathComponent("FocusTimer-week-\(Self.stamp(now)).md")
                try SessionExport.makeMarkdownData().write(to: mdURL, options: .atomic)
            }
            UserDefaults.standard.set(thisWeek, forKey: UserDefaultsKeys.weeklyBackupLastRunWeek)
            UserDefaults.standard.set(now, forKey: UserDefaultsKeys.weeklyBackupLastRunAt)
        } catch {
            // A broken folder shouldn't nag every week: surface once, disable.
            NotificationManager.shared.sendBackupFailed(error.localizedDescription)
            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.weeklyBackupEnabled)
            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.weeklyBackupMarkdownEnabled)
            stop()
        }
    }

    private static func stamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// The user-chosen folder (persisted as a bookmark) or the default
    /// ~/Documents/FocusTimer Backups, created on demand.
    static func backupFolder() throws -> URL {
        let fm = FileManager.default
        if let data = UserDefaults.standard.data(forKey: UserDefaultsKeys.weeklyBackupFolderBookmark) {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [],
                                  relativeTo: nil, bookmarkDataIsStale: &stale) {
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    return url
                }
            }
        }
        let fallback = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/FocusTimer Backups", isDirectory: true)
        try fm.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }

    /// Persists a folder choice from the picker as a bookmark (robust to
    /// renames/moves, and harmless with the sandbox off).
    static func setFolder(_ url: URL) {
        if let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(data, forKey: UserDefaultsKeys.weeklyBackupFolderBookmark)
        }
    }

    /// Human-readable path of the current folder for the Settings row.
    static var folderDisplayPath: String {
        if let data = UserDefaults.standard.data(forKey: UserDefaultsKeys.weeklyBackupFolderBookmark) {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [],
                                  relativeTo: nil, bookmarkDataIsStale: &stale) {
                return url.path
            }
        }
        return "~/Documents/FocusTimer Backups"
    }
}

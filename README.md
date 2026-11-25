# ⏱ FocusTimer

**A beautiful, minimal Pomodoro timer that lives in your macOS menu bar.**

[![macOS](https://img.shields.io/badge/macOS-14.0%2B-blue?logo=apple)](https://github.com/lumenworksco/FocusTimer/releases)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Release](https://img.shields.io/github/v/release/lumenworksco/FocusTimer?color=red)](https://github.com/lumenworksco/FocusTimer/releases/latest)

> **Personal fork** — adds custom schedules (beyond Pomodoro), session
> export/backup, iCloud Drive sync, and a pluggable social backend
> (Supabase or any webhook). Based on [iPwnds/FocusTimer](https://github.com/iPwnds/FocusTimer).

---

## Download

<div align="center">

<a href="https://github.com/lumenworksco/FocusTimer/releases/latest">
  <img src="https://img.shields.io/badge/Download_for_macOS-%23000000?style=for-the-badge&logo=apple&logoColor=white" alt="Download for macOS" height="48"/>
</a>

<br/>
<sub>macOS 14.0 Sonoma or later &nbsp;·&nbsp; Apple Silicon &amp; Intel &nbsp;·&nbsp; Free &amp; open source</sub>

</div>

<br/>

1. Download **FocusTimer.dmg** from the [latest release](https://github.com/lumenworksco/FocusTimer/releases/latest)
2. Open the DMG and drag `FocusTimer.app` to **Applications**
3. Launch it — the `⏱` icon appears in your menu bar

> **First launch:** macOS may show a security prompt. Go to **System Settings → Privacy & Security** and click **Open Anyway**.

---

## Features

### Timer
- **Menu bar native** — one click away, never clutters the Dock
- **Animated progress ring** — smooth arc with a pulsing glow while your session runs
- **Custom schedules** — data-driven step sequences beyond Pomodoro: Deep Work (90/20), 52/17 Flowtime, Sprint Focus, or build your own
- **Long-break cadence** — an automatic long break replaces the next break after every N work steps
- **Repeat modes** — run always, a fixed number of cycles, or against a total-minutes budget (the final step is trimmed to fit)
- **Auto-advance** — transitions automatically between steps
- **Idle detection** — auto-pauses when you step away, auto-resumes when you return

### Task management
- **Task label** — name what you're working on; shows next to the timer in the menu bar
- **Task autocomplete** — recent labels appear as suggestions when you click the field
- **Per-schedule labels** — the label is remembered per schedule and restored on the next work step
- **Session log** — every session recorded with task label, schedule, time, and duration

### Schedules & goals
- **Schedule picker** — switch between schedules (locked while a session runs; reset first)
- **Per-schedule daily goal** — each schedule carries its own session target; the goal footer tracks progress
- **Schedule editor** — name, ordered steps (label, minutes, kind), long-break cadence, repeat mode

### Stats & insights
- **Activity heatmap** — 16-week GitHub-style day grid showing your focus history
- **Daily bar chart** — sessions or focus time over 1, 2, or 4 weeks
- **Time-of-day patterns** — hourly distribution chart revealing your peak focus hours
- **Streak tracking** — current focus streak shown in the main window and Stats
- **Unbounded session log** — full history is kept (no entry cap)

### Export & backup
- **JSON backup** — round-trippable restore with an idempotent merge (importing the same backup twice changes nothing)
- **CSV export** — one row per session (with schedule) for spreadsheets
- **Markdown summary** — weekly table (sessions, focus time, streak, top labels) for your notes app
- **Weekly auto-backup** — optional Sunday-evening JSON (+ Markdown) snapshot to a folder of your choice

### iCloud sync
- **Multi-Mac sync** — daily stats and session history sync through iCloud Drive with convergent merges (max-of per day, union-by-session)
- **Live session awareness** — a session running on one Mac appears on your other Macs ("Work on MacBook Pro · 12m left")

### Notifications
- **Session alerts** — notification with optional sound when each step completes
- **Sound palette** — 8 curated system sounds (Bottle, Glass, Hero, Morse, Ping, Pop, Submarine, Tink), the notification default, or none — all previewable from Settings
- **Foreground delivery** — alerts banner and sound even while the timer window is focused (a `willPresent` delegate opts back in to macOS's frontmost suppression)
- **Schedule-complete alerts** — fired when a finite schedule finishes
- **Weekly digest** — Sunday evening summary of sessions, focus time, and streak
- **Milestone celebrations** — one-time notifications at 10, 50, 100, 500, and 1,000 sessions
- **Test notification** — one-tap pipeline check with permission guidance

> Note: notification sounds obey the separate alert volume — System
> Settings → Sound, not the output volume.

### Social
- **Pluggable backend** — off by default; point it at Supabase or any custom webhook URL
- **Focus friends** — add friends by username and see their session count, focus time, and streak
- **Local friend list** — adding/removing friends never touches the network

### Comfort
- **Break prompts** — a rotating micro-action suggestion on every break (stand up, breathe, etc.)
- **Global hotkeys** — customizable keyboard shortcuts to start/pause and skip from anywhere
- **Launch at login** — start automatically with macOS
- **Two-pane settings** — sidebar sections (Schedules, Behavior, Notifications, Shortcuts, Social, Sync, Data)

---

## Usage

| Action | How |
|--------|-----|
| Open timer | Click the `⏱` icon in the menu bar |
| Start / Pause | Click **Start** or press the global hotkey (default `⌃⌥Space`) |
| Skip session | Click **Skip** or press `⌃⌥S` |
| Reset session | Click **Reset** (also re-arms a finished schedule) |
| Switch schedule | Settings → Schedules (locked while a session runs) |
| Open full window | Click the app icon in the Dock |
| Export / import | Settings → Data, or the export menu in the Stats window |
| View stats | Click the chart icon `⊞` in the popover header |
| Settings | Click the gear icon `⚙` or right-click the menu bar icon |

The classic Pomodoro cycle:  
`Work → Short Break → Work → Short Break → Work → Short Break → Work → Long Break → repeat`

---

## Settings

| Setting | Default |
|---------|---------|
| Schedule | Pomodoro — 25 min Focus / 5 min break, long break (15) every 4 work steps |
| Repeat mode | Always (also: N cycles, N-minute budget) |
| Daily goal | 8 sessions — per schedule |
| Auto-advance sessions | On |
| Show task label in menu bar | Off |
| Pause when idle | On (5 min threshold) |
| Global hotkeys | On (`⌃⌥Space` start/pause, `⌃⌥S` skip) |
| Notifications | On |
| Weekly digest | On |
| Launch at login | Off |
| iCloud sync | On when iCloud Drive is available |
| Weekly auto-backup | Off |
| Social backend | Off (None; Supabase or custom webhook opt-in) |

---

## Building from Source

**Requirements:** Xcode 15+, macOS 14.0+

```bash
git clone https://github.com/lumenworksco/FocusTimer.git
cd FocusTimer

xcodebuild -scheme FocusTimer -configuration Release \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO
```

Or open `FocusTimer.xcodeproj` in Xcode and press **⌘R**.

> **Signing note:** use `CODE_SIGN_IDENTITY="-"` (ad-hoc "Sign to Run
> Locally"). A completely unsigned build (`CODE_SIGN_IDENTITY=""`) runs,
> but macOS will never show its notification permission prompt or deliver
> its banners — notifications silently do nothing. No Apple Developer
> account is needed for ad-hoc signing.

> **Update checks:** the fork never queries the upstream repo. To enable
> update checks against your own releases, point it at a
> GitHub-releases-compatible endpoint:
>
> ```bash
> defaults write com.focustimer.app update.apiURL \
>   "https://api.github.com/repos/YOUR/FocusTimer/releases/latest"
> ```

> **Bundle identifier:** the default is `com.focustimer.app`, defined in
> `FocusTimer/Config.xcconfig`. To personalize it (e.g. to run your fork
> alongside the upstream release), create a gitignored
> `FocusTimer/Local.xcconfig` next to it:
>
> ```bash
> echo 'PRODUCT_BUNDLE_IDENTIFIER = com.yourhandle.FocusTimer' > FocusTimer/Local.xcconfig
> ```
>
> Changing the bundle identifier starts a fresh identity (stats,
> settings, and notification authorization are keyed to it) — export a
> backup first and import it in the new install. Command-line builds can
> also override per invocation: `xcodebuild ... PRODUCT_BUNDLE_IDENTIFIER=…`.

---

## Contributing

Pull requests are welcome. For significant changes please open an issue first to discuss the approach.

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes
4. Push and open a Pull Request

---

## License

[MIT](LICENSE) © 2026 lumenworksco

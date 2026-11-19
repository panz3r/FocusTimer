import AppKit
import SwiftUI

/// A hotkey recorder button: click to start recording, press the desired
/// combination (Escape cancels). Only one recorder may be active at a time.
struct KeyRecorder: View {
    let label: String
    let onStartRecording: () -> Void
    let onCancel: () -> Void
    let onRecord: (Int, Int, String) -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    private static var isAnyRecording = false

    var body: some View {
        Button { toggleRecording() } label: {
            Text(isRecording ? "Press keys…" : label)
                .font(.caption.monospaced())
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(isRecording ? Color.accentColor.opacity(0.15) : Color(NSColor.controlColor))
                .foregroundStyle(isRecording ? Color.accentColor : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isRecording ? Color.accentColor.opacity(0.4) : Color.white.opacity(0.1), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .onDisappear { stopRecording(cancelled: true) }
    }

    private func toggleRecording() {
        isRecording ? stopRecording(cancelled: true) : startRecording()
    }

    private func startRecording() {
        guard !KeyRecorder.isAnyRecording else { return }
        isRecording = true
        KeyRecorder.isAnyRecording = true
        onStartRecording()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard self.isRecording else { return event }
            if event.keyCode == 53 { // Escape cancels
                self.stopRecording(cancelled: true)
                return nil
            }
            let mods = self.carbonMods(from: event.modifierFlags)
            guard mods != 0 else { return nil }
            let display = self.modifierSymbols(mods) + self.keyLabel(for: event)
            self.onRecord(Int(event.keyCode), mods, display)
            self.stopRecording(cancelled: false)
            return nil
        }
    }

    private func stopRecording(cancelled: Bool) {
        guard isRecording else { return }
        isRecording = false
        KeyRecorder.isAnyRecording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        if cancelled { onCancel() }
    }

    private func carbonMods(from flags: NSEvent.ModifierFlags) -> Int {
        var c = 0
        if flags.contains(.control) { c |= 4096 }
        if flags.contains(.option)  { c |= 2048 }
        if flags.contains(.command) { c |= 256  }
        if flags.contains(.shift)   { c |= 512  }
        return c
    }

    private func modifierSymbols(_ mods: Int) -> String {
        var s = ""
        if mods & 4096 != 0 { s += "⌃" }
        if mods & 2048 != 0 { s += "⌥" }
        if mods & 256  != 0 { s += "⌘" }
        if mods & 512  != 0 { s += "⇧" }
        return s
    }

    private func keyLabel(for event: NSEvent) -> String {
        switch event.keyCode {
        case 49:  return "Space"
        case 36:  return "↩"
        case 48:  return "⇥"
        case 51:  return "⌫"
        case 117: return "⌦"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:  return (event.charactersIgnoringModifiers ?? "?").uppercased()
        }
    }
}

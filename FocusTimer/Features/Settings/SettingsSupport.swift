import SwiftUI

/// Shared styling for Settings panes (Phase 2: extracted from the settings
/// monolith so panes can live in their own files).

extension View {
    /// Wraps pane content in the standard rounded settings card.
    func settingsCard() -> some View {
        VStack(spacing: 0) { self }
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.07), lineWidth: 1))
    }
}

/// One labeled row inside a settings card.
struct SettingsRow<Trailing: View>: View {
    let label: String
    @ViewBuilder var trailing: () -> Trailing

    init(_ label: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.label = label
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(label).font(.callout)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
    }
}

import NotchHubCore
import SwiftUI

/// A file-drop / sharing session.
///
/// Plain value model — the app drives the phase (idle → hovering → dropped)
/// and the destination the user picks; this view only renders the surface.
enum FileDropPhase {
    case idle
    case hovering
    case dropped
}

/// The file-drop / sharing surface.
///
/// When a file enters the island's drop zone the surface invites the user to
/// "Drop to Share"; on drop it animates the file in and offers destination
/// options (AirDrop, QR code, Clipboard, Cloud). No sharing is performed here —
/// the chosen destination is handed back through `onDestination`.
struct FileDropView: View {
    let fileName: String
    let phase: FileDropPhase
    let onDestination: (String) -> Void

    init(fileName: String, phase: FileDropPhase, onDestination: @escaping (String) -> Void) {
        self.fileName = fileName
        self.phase = phase
        self.onDestination = onDestination
    }

    var body: some View {
        VStack(spacing: DesignTokens.space16) {
            fileBadge
            Text(prompt)
                .font(DesignTokens.titleFont)
                .foregroundStyle(DesignTokens.textPrimary)
                .lineLimit(1)

            if phase == .dropped {
                destinationRow
            }
        }
        .padding(.horizontal, DesignTokens.contentInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(DesignTokens.springSettle, value: phase)
    }

    private var prompt: String {
        switch phase {
        case .idle: return "Drop to Share"
        case .hovering: return "Drop to Share"
        case .dropped: return "Share \(fileName)"
        }
    }

    private var fileBadge: some View {
        Image(systemName: "doc.fill")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(DesignTokens.accent)
            .frame(width: 44, height: 44)
            .background(DesignTokens.chipFill, in: RoundedRectangle(cornerRadius: DesignTokens.radiusChip, style: .continuous))
    }

    private var destinationRow: some View {
        HStack(spacing: DesignTokens.space8) {
            // Only destinations that map to a real macOS service are offered.
            // AirDrop uses NSSharingService; Clipboard copies the file URLs.
            // A QR upload or a "Cloud" provider would need network
            // infrastructure the app does not have, so they are not shown
            // rather than presented as working buttons that do nothing.
            destinationButton("AirDrop", symbol: "airplane", destination: "AirDrop")
            destinationButton("Copy", symbol: "doc.on.doc", destination: "Clipboard")
        }
    }

    private func destinationButton(_ label: String, symbol: String, destination: String) -> some View {
        Button {
            onDestination(destination)
        } label: {
            VStack(spacing: DesignTokens.space4) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                Text(label)
                    .font(DesignTokens.compactFont)
            }
            .foregroundStyle(DesignTokens.textPrimary)
            .frame(width: 64, height: 52)
            .background(DesignTokens.chipFill, in: RoundedRectangle(cornerRadius: DesignTokens.radiusChip, style: .continuous))
            // A `background` paints behind the label but adds no hit area, so
            // without this the chip is only clickable on the glyphs themselves
            // and a click anywhere else falls through the island.
            .contentShape(RoundedRectangle(cornerRadius: DesignTokens.radiusChip, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

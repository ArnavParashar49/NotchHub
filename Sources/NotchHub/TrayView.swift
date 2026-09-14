import NotchHubCore
import SwiftUI

/// The clipboard Tray browser panel.
///
/// A polished list on the island's near-black surface: a search field, a
/// horizontal filter row, and a scrollable, newest-first history of clips.
/// The panel is deliberately quiet — hairlines between rows, a whisper of
/// light on hover, no borders — so the content reads like it belongs to the
/// system rather than a third-party utility.
struct TrayView: View {
    /// The clipboard history the panel browses.
    let store: TrayStore
    @Binding var search: String
    @Binding var filter: TrayFilter

    let onSelect: (TrayClip) -> Void
    let onPin: (TrayClip) -> Void
    let onDelete: (TrayClip) -> Void

    init(
        store: TrayStore,
        search: Binding<String>,
        filter: Binding<TrayFilter>,
        onSelect: @escaping (TrayClip) -> Void,
        onPin: @escaping (TrayClip) -> Void,
        onDelete: @escaping (TrayClip) -> Void
    ) {
        self.store = store
        self._search = search
        self._filter = filter
        self.onSelect = onSelect
        self.onPin = onPin
        self.onDelete = onDelete
    }

    /// The clips matching the current search and filter, newest first.
    private var results: [TrayClip] {
        store.search(query: search, filter: filter)
    }

    var body: some View {
        VStack(spacing: DesignTokens.space8) {
            searchField
            filterRow
            if results.isEmpty {
                emptyState
            } else {
                clipList
            }
        }
        .padding(.horizontal, DesignTokens.space12)
        .padding(.top, DesignTokens.space12)
        .padding(.bottom, DesignTokens.space8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: DesignTokens.space8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DesignTokens.textTertiary)
            TextField("Search clips", text: $search)
                .textFieldStyle(.plain)
                .font(DesignTokens.subtitleFont)
                .foregroundStyle(DesignTokens.textPrimary)
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignTokens.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DesignTokens.space12)
        .frame(height: 30)
        .background(
            DesignTokens.fieldFill,
            in: RoundedRectangle(cornerRadius: DesignTokens.radiusChip, style: .continuous)
        )
    }

    // MARK: - Filter row

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignTokens.space8) {
                ForEach(TrayFilter.allCases, id: \.self) { candidate in
                    filterChip(candidate)
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func filterChip(_ candidate: TrayFilter) -> some View {
        let selected = candidate == filter
        return Button {
            filter = candidate
        } label: {
            Text(candidate.label)
                .font(DesignTokens.compactFont)
                .foregroundStyle(selected ? DesignTokens.islandFill : DesignTokens.textSecondary)
                .padding(.horizontal, DesignTokens.space12)
                .padding(.vertical, 5)
                .background(
                    selected ? DesignTokens.accent : DesignTokens.chipFill,
                    in: RoundedRectangle(cornerRadius: DesignTokens.radiusChip, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: DesignTokens.space4) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(DesignTokens.textTertiary)
            Text("Nothing copied yet")
                .font(DesignTokens.subtitleFont)
                .foregroundStyle(DesignTokens.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Clip list

    private var clipList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(results) { clip in
                    TrayRow(
                        clip: clip,
                        onSelect: onSelect,
                        onPin: onPin,
                        onDelete: onDelete
                    )
                    if clip.id != results.last?.id {
                        Rectangle()
                            .fill(DesignTokens.rowSeparator)
                            .frame(height: 1)
                            .padding(.leading, 46)
                    }
                }
            }
        }
    }
}

/// A single Tray row: leading kind icon, title + subtitle, a pin affordance,
/// and a quiet hover wash. The row itself selects; pin and delete live in the
/// context menu so the surface stays uncluttered.
private struct TrayRow: View {
    let clip: TrayClip
    let onSelect: (TrayClip) -> Void
    let onPin: (TrayClip) -> Void
    let onDelete: (TrayClip) -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            onSelect(clip)
        } label: {
            HStack(spacing: DesignTokens.space8) {
                Image(systemName: clip.kind.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DesignTokens.textPrimary)
                    .frame(width: 30, height: 30)
                    .background(
                        DesignTokens.chipFill,
                        in: RoundedRectangle(cornerRadius: DesignTokens.radiusChip, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: DesignTokens.space2) {
                    Text(clip.displayTitle)
                        .font(DesignTokens.titleFont)
                        .foregroundStyle(DesignTokens.textPrimary)
                        .lineLimit(1)
                    if let subtitle = clip.displaySubtitle {
                        Text(subtitle)
                            .font(DesignTokens.subtitleFont)
                            .foregroundStyle(DesignTokens.textSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if clip.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.textTertiary)
                }
            }
            .padding(.horizontal, DesignTokens.space8)
            .padding(.vertical, DesignTokens.space4)
            .contentShape(Rectangle())
            .background(
                isHovered ? DesignTokens.rowSelected : .clear,
                in: RoundedRectangle(cornerRadius: DesignTokens.radiusRow, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button {
                onPin(clip)
            } label: {
                Label(clip.pinned ? "Unpin" : "Pin", systemImage: "pin")
            }
            Button {
                onDelete(clip)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

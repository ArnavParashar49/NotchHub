import NotchHubCore
import SwiftUI

/// The island itself: one continuous black object that springs between shapes.
///
/// The black surface is a single sharp rectangle whose size is driven by
/// springs, so it appears to physically stretch and reshape rather than a
/// separate rectangle popping in. Content lives in an overlay that crossfades
/// independently inside the container.
struct IslandView: View {
    /// The current activity, if any.
    let current: Activity?
    /// How many activities are queued behind the primary one.
    let stackCount: Int
    /// The island's resting shape.
    let state: IslandState
    /// The island's frame in the hosting window's local coordinates.
    let localFrame: CGRect
    /// The notch's own corner radius.
    let cornerRadius: CGFloat
    /// The notch's height. Content is laid out below this line, since anything
    /// placed in the top `notchInset` points sits behind the notch cutout and
    /// would never be seen.
    let notchInset: CGFloat
    /// Whether the island is idle (tucked behind the notch).
    let isIdle: Bool
    /// What the two wings show while the island is in its sideways peek.
    var wingStatus: WingStatus = WingStatus()
    /// The notch's width — the gap the wings leave in the middle.
    var notchWidth: CGFloat = 0
    /// How much room the content needs, used to size the wings/compact bar.
    var contentSize: IslandContentSize = .default
    /// A surface that replaces the queue-driven content: the dashboard, the
    /// Tray, a call's controls, or an app skin. `nil` renders the activity instead.
    var panelContent: AnyView? = nil
    /// The drawn control the cursor is resting on, so the wings can light it.
    var hoveredControl: IslandControl? = nil
    /// Whether the now-playing surface may drive the player. False when the
    /// media framework is unavailable, so the controls render inert rather
    /// than inviting a click that does nothing.
    var canControlMedia: Bool = true

    /// Whether the black surface is painted. It stays opaque while the island
    /// drains back into the notch and fades only once it is notch-sized (the
    /// coordinator delays this by `DesignTokens.retractFadeDelay`).
    var surfaceVisible: Bool = true
    /// The live call, for the compact bar's timer and mute state.
    var meeting: Meeting? = nil
    /// The pixel pet, when shown. It lives in its own layer, placed from the
    /// island's right edge, so it travels with every resize.
    var pet: PetRenderModel? = nil
    /// Without a notch there is no idle dock, so no idle pet either.
    var hasNotch: Bool = true
    /// NEO's listening mark: the one pulse of light behind the pet when NEO
    /// starts to listen, in every shape the pet rides. `nil` while no pulse
    /// shows.
    var listening: NeoListeningMark? = nil
    /// NEO's microphone is live; a moving blue contour traces the hardware notch.
    var neoListeningActive: Bool = false
    /// AppKit context menus need smooth pointer tracking; hold the highlight still while one is open.
    var neoListeningAnimationPaused: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            // The black surface is ALWAYS present.
            islandSurface

            if !isIdle {
                contentGroup
                    .transition(.islandContent)
            }

            listeningSignalLayer
            // Explicit snapshot callers can still request the older one-shot
            // pet halo; the live app uses the inlaid signal mark above.
            if listening != nil {
                listeningGlowLayer
            }

            petLayer
        }
        .frame(width: localFrame.width, height: localFrame.height, alignment: .top)
        // Pinned by its top-left corner rather than positioned by its centre:
        // the top edge is welded to the screen's top, so it must never drift
        // while the height springs — even when a motion is interrupted.
        .offset(x: localFrame.minX, y: localFrame.minY)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The content layer.
    ///
    /// Each branch carries its own `.id` so a state change swaps it with a
    /// transition: the old content blurs and fades out quickly, the new one
    /// blurs in once the surface has started moving. The whole layer is MASKED
    /// to the island's own silhouette, so nothing ever hangs outside the black
    /// shape while it shrinks — content is poured out of the island with it.
    @ViewBuilder
    private var contentGroup: some View {
        ZStack(alignment: .top) {
            if state == .wings {
                WingView(
                    status: wingStatus,
                    notchWidth: notchWidth,
                    notchHeight: notchInset,
                    trailingReserve: petBarReserve,
                    leadWidth: contentSize.wingLead,
                    trailWidth: contentSize.wingSide,
                    hovered: hoveredControl
                )
                .id("wings")
                .transition(.islandContent)
            } else if let panelContent {
                panelContent
                    .padding(.trailing, state == .expanded ? petExpandedReserve : 0)
                    .id("panel-\(state.rawValue)")
                    .transition(.islandContent)
            } else if let current {
                content(for: current)
                    .id("content-\(current.id)-\(state.rawValue)")
                    .transition(.islandContent)
            } else {
                restingContent
                    .id("rest")
                    .transition(.islandContent)
            }
        }
        // Content sits at the notch line for compact/wings, and below the
        // cutout for the taller surfaces.
        .padding(.top, laysOutAtNotchHeight ? 0 : notchInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .mask(surfaceShape)
    }

    /// The pixel pet, anchored to the island edge it belongs to (the right one,
    /// or the left while it visits the left of the notch). Its offset changes
    /// in the same transaction as the island's frame, so it rides the island's
    /// spring rather than jumping; a change of pixel scale crossfades instead of
    /// scaling the art. Masked to the island, so a pet running into the notch
    /// or peeking out of it is cut exactly at the black shape's edge.
    @ViewBuilder
    private var petLayer: some View {
        if let pet, state != .idle || hasNotch,
           let placement = PetLayout.placement(for: state, islandSize: localFrame.size, notchHeight: notchInset,
                                               dock: contentSize.petDock ?? .home, size: pet.size) {
            let leading = placement.anchor == .leading
            // Measured from its own edge, so even while fading in or out it
            // travels with that edge.
            let x = leading ? placement.origin.x : placement.origin.x + placement.size - localFrame.width
            PetView(presentation: pet.presentation, scale: placement.scale, look: pet.look, hat: pet.hat,
                    palette: pet.palette, accessory: pet.accessory, name: pet.name)
                .id("pet-\(Int(placement.scale))")
                .transition(.opacity.animation(.easeOut(duration: 0.16)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: leading ? .topLeading : .topTrailing)
                .offset(x: x, y: placement.origin.y)
                .mask(surfaceShape)
                .allowsHitTesting(false)
        }
    }

    /// NEO's listening glow: a soft halo centred on the pet and drawn behind
    /// it, for one pulse when NEO starts to listen. Placed from the same edge as the pet, in the same transaction as
    /// the island's frame, so it rides the island's spring with the pet;
    /// masked to the island like the pet, so the light never spills past the
    /// black shape; and it never takes the mouse.
    ///
    /// The layer is there whenever the pet is — drawing nothing while no
    /// pulse shows — so that when the glow comes up it is already travelling
    /// with the pet's edge (see `NeoListeningGlowView`).
    @ViewBuilder
    private var listeningGlowLayer: some View {
        if let pet, state != .idle || hasNotch,
           let placement = PetLayout.placement(for: state, islandSize: localFrame.size, notchHeight: notchInset,
                                               dock: contentSize.petDock ?? .home, size: pet.size) {
            let leading = placement.anchor == .leading
            let frame = NeoListeningLayout.glowFrame(behind: placement)
            NeoListeningGlowView(mark: listening, petSize: placement.size,
                                 tint: pet.glow.map(PetCanvas.color) ?? DesignTokens.listeningGlow)
                // Like the pet, a change of pixel scale crossfades.
                .id("glow-\(Int(placement.scale))")
                .transition(.opacity.animation(.easeOut(duration: 0.16)))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: leading ? .topLeading : .topTrailing)
                .offset(x: leading ? frame.minX : frame.maxX - localFrame.width, y: frame.minY)
                .mask(surfaceShape)
                .allowsHitTesting(false)
        }
    }

    /// A thin black support rim follows the island's current silhouette,
    /// centered on the hardware notch, and carries a continuous blue beam. It
    /// extends only a couple of points so the light stays visible at the edge.
    private var listeningSignalLayer: some View {
        NeoWakeOutlineView(
            shape: surfaceShape,
            isActive: neoListeningActive && hasNotch,
            paused: neoListeningAnimationPaused,
            tint: pet?.glow.map(PetCanvas.color) ?? DesignTokens.accent
        )
            .frame(width: localFrame.width + NeoWakeOutlineView.supportInset * 2,
                   height: localFrame.height + NeoWakeOutlineView.supportInset * 2)
            .position(x: localFrame.width / 2, y: localFrame.height / 2)
            .allowsHitTesting(false)
    }

    /// Room kept free for the pet at the right of notch-height bars.
    private var petBarReserve: CGFloat { pet.map { PetMetrics($0.size).barSlot } ?? 0 }

    /// Room kept free for the larger pet at the right of the expanded island.
    private var petExpandedReserve: CGFloat { pet.map { PetMetrics($0.size).expandedReserve } ?? 0 }

    /// The island's silhouette for the current (target) shape: flared at the
    /// top like the notch, and in the pet's idle dock a continuation of the
    /// physical notch (see `NotchShape.surface`). Every radius animates.
    private var surfaceShape: NotchShape {
        let docked = state == .idle && pet != nil && hasNotch
        return NotchShape.surface(islandRadius: surfaceRadius, idleDock: docked ? contentSize.petDock : nil)
    }

    /// The bottom-corner radius for the current (target) shape. One animatable
    /// value, so corners morph continuously alongside the size.
    ///
    /// A PANEL takes the design system's own `radiusPanel`, which is what that
    /// token was written for and had never actually been wired up. The island's
    /// radius scales with height — sensible while it is a bar growing into a
    /// pill, but every panel is far taller than the notch, so they all pinned to
    /// the same maximum regardless of how WIDE they were. On a narrow panel that
    /// put a third of the bottom edge inside its own corners, which is the
    /// over-curved look; on a wide one the same number passed unnoticed.
    private var surfaceRadius: CGFloat {
        // NEO's two buttons: a small surface, its corners concentric with
        // the capsules inside it.
        if state == .neoConfirm { return NeoConfirmLayout.cornerRadius }
        if state == .expanded, current?.kind == .identifiedSong { return DesignTokens.radiusIslandBottom }
        if Self.panelStates.contains(state) { return DesignTokens.radiusPanel }
        let base = state == .wings ? DesignTokens.radiusWingBottom : DesignTokens.radiusIslandBottom
        guard notchInset > 0 else { return base }
        let scale = (state == .interactive || state == .appPanel) ? 1.5 : min(2, max(1, localFrame.height / notchInset))
        return base * scale
    }

    /// The surfaces that hang from the notch as a panel rather than growing out
    /// of it as a bar. The dashboard and an app panel are deliberately absent:
    /// they carry the notch strip's own controls and keep the island radius so
    /// they still read as the island, opened up.
    private static let panelStates: Set<IslandState> = [
        .tray, .settings, .fileDrop, .meeting, .skin,
        .teleprompter, .teleprompterCompose, .camera, .cameraExpanded, .neoPanel,
    ]

    /// Whether this surface is exactly notch-height, so its content should sit
    /// at the notch line rather than below the cutout.
    private var laysOutAtNotchHeight: Bool {
        state == .wings || state == .compact
    }

    /// The resting face, shown when the island is revealed with no activity to
    /// report. A glanceable clock is the natural thing to find at the notch.
    private var restingContent: some View {
        Text(Date(), style: .time)
            .font(DesignTokens.numericFont)
            .foregroundStyle(DesignTokens.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The morphing black surface. Size and corner radius both animate, which
    /// is what makes the shape feel like one stretching object.
    ///
    /// The silhouette is the notch's own: flaring into the screen's top edge
    /// with the same small concave curves as the physical notch, rounded
    /// outward on the bottom, flat along the bottom edge. It carries NO shadow and NO glow — the island is meant to
    /// read as the physical notch, a crisp flat matte-black shape, not a
    /// floating software widget.
    ///
    /// While idle the surface is fully transparent — the island *is* the notch,
    /// and painting a black rectangle over the cutout would show as a bar
    /// hanging off it. It stays opaque for the whole retract, though: fading
    /// a shape while it is still shrinking turns it translucent grey.
    private var islandSurface: some View {
        surfaceShape
            .fill(DesignTokens.islandFill)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(surfaceVisible ? 1 : 0)
    }

    /// Content laid out inside the island, with generous padding so it breathes.
    @ViewBuilder
    private func content(for activity: Activity) -> some View {
        if state == .compact || localFrame.width <= 200 {
            compactContent(for: activity)
        } else {
            expandedContent(for: activity)
        }
    }

    // MARK: - Compact

    /// The compact bar: the activity's icon at the extreme left, its title and
    /// value on the right, with the notch cutout left clear in the middle.
    ///
    /// The bar is exactly notch-height, so a transient activity (a volume
    /// change, a battery readout) shows *alongside* the notch rather than as a
    /// pill hanging underneath it. Both wings share one width so the cutout
    /// stays centred on the real notch; the glyph sits at the extreme left of
    /// its wing rather than hugging the cutout, so the side reads snug.
    private func compactContent(for activity: Activity) -> some View {
        let balancedSide = max(contentSize.compactLead, contentSize.compactTrail)
        // Let the visualizer fill the open right lane when a longer title
        // widens the centered bar, while keeping its usual size on short rows.
        let visualizerWidth = max(
            IslandMetrics.musicVisualizerWidth,
            balancedSide - DesignTokens.compactInset - petBarReserve
        )
        return HStack(spacing: 0) {
            // Left wing
            HStack(spacing: 8) {
                if activity.kind == .music || activity.kind == .identifiedSong {
                    // Square artwork thumbnail on the left, clearly visible.
                    Group {
                        if let artwork = activity.artwork, let image = NSImage(data: artwork) {
                            Image(nsImage: image)
                                .resizable()
                                .aspectRatio(1, contentMode: .fill)
                        } else {
                            ZStack {
                                DesignTokens.chipFill
                                Image(systemName: "music.note")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(DesignTokens.textSecondary)
                            }
                        }
                    }
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.radiusChip, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.radiusChip, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    )
                } else {
                    icon(for: activity, size: DesignTokens.iconSizeCompact)
                }

                if activity.kind == .meeting, let meeting {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(meeting.elapsedLabel(at: context.date))
                            .font(DesignTokens.compactFont)
                            .monospacedDigit()
                            .foregroundStyle(DesignTokens.textPrimary)
                            .lineLimit(1)
                    }
                }

                if (activity.kind == .music || activity.kind == .identifiedSong), let text = activity.compactText {
                    MarqueeText(
                        text: text,
                        font: DesignTokens.compactFont,
                        foregroundStyle: DesignTokens.textPrimary,
                        maxWidth: IslandMetrics.maxCompactMusicTextWidth
                    )
                } else if activity.kind == .songRecognition {
                    Text(activity.title)
                        .font(DesignTokens.compactFont)
                        .foregroundStyle(DesignTokens.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.leading, DesignTokens.compactInset)
            .frame(width: balancedSide, alignment: .leading)

            // Notch
            Color.clear.frame(width: notchWidth)

            // Right wing
            HStack(spacing: 0) {
                if activity.kind == .music {
                    MusicVisualizer(isPlaying: activity.isPlaying, color: Color(red: 0.19, green: 0.82, blue: 0.35), width: visualizerWidth)
                } else if activity.kind == .songRecognition {
                    MusicVisualizer(isPlaying: true, tint: DesignTokens.accent, width: visualizerWidth)
                } else if activity.kind == .identifiedSong, let detail = activity.compactDetail {
                    Text(detail)
                        .font(DesignTokens.compactFont)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else if activity.kind == .meeting {
                    meetingCompactControls
                } else if let text = activity.compactText {
                    Text(text)
                        .font(DesignTokens.compactFont)
                        .foregroundStyle(DesignTokens.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.trailing, DesignTokens.compactInset + petBarReserve)
            .frame(width: balancedSide, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Mute and leave on a call's compact bar, placed where
    /// `MeetingControlLayout.compactButtons` hit-tests them.
    private var meetingCompactControls: some View {
        let muted = meeting?.isMuted ?? false
        return HStack(spacing: MeetingControlLayout.compactButtonSpacing) {
            Image(systemName: muted ? "mic.slash.fill" : "mic.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(muted ? DesignTokens.warning : DesignTokens.textPrimary)
                .frame(width: MeetingControlLayout.compactButtonSize, height: MeetingControlLayout.compactButtonSize)
                .background(Circle().fill(Color.white.opacity(0.12)))
            Image(systemName: "phone.down.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: MeetingControlLayout.compactButtonSize, height: MeetingControlLayout.compactButtonSize)
                .background(Circle().fill(DesignTokens.live))
        }
    }

    // MARK: - Expanded

    private func expandedContent(for activity: Activity) -> some View {
        if activity.kind == .music {
            return AnyView(musicExpandedContent(for: activity))
        }
        if activity.kind == .identifiedSong {
            return AnyView(identifiedSongPopupContent(for: activity))
        }
        return AnyView(
            HStack(spacing: DesignTokens.space16) {
                icon(for: activity, size: DesignTokens.iconSizeLarge)
                    .frame(width: 44)

                VStack(alignment: .leading, spacing: DesignTokens.space2) {
                    Text(activity.title)
                        .font(DesignTokens.titleFont)
                        .foregroundStyle(DesignTokens.textPrimary)
                        .lineLimit(1)
                    if let subtitle = activity.subtitle {
                        Text(subtitle)
                            .font(DesignTokens.subtitleFont)
                            .foregroundStyle(DesignTokens.textSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: DesignTokens.space8)

                trailingControl(for: activity)
            }
            .padding(.leading, DesignTokens.contentInset)
            .padding(.trailing, DesignTokens.contentInset + petExpandedReserve)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
    }

    /// A compact NEO result card: cover art, song title and the artist/album
    /// line, without the transport controls or progress bar of a live player.
    private func identifiedSongPopupContent(for activity: Activity) -> some View {
        HStack(spacing: DesignTokens.space12) {
            artworkFill(for: activity)
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.radiusChip, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.radiusChip, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                )

            VStack(alignment: .leading, spacing: DesignTokens.space2) {
                Text(activity.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(DesignTokens.textPrimary)
                    .lineLimit(1)
                if let subtitle = activity.subtitle {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(DesignTokens.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, DesignTokens.contentInset + 2)
        // Keep the fox's expanded slot clear so the artist/album line never
        // renders underneath it.
        .padding(.trailing, DesignTokens.contentInset + 6 + petExpandedReserve)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// The expanded music surface: a clean square artwork on the left, track
    /// title and artist next to it, transport controls on the right, and a
    /// progress bar along the bottom.
    private func musicExpandedContent(for activity: Activity) -> some View {
        VStack(spacing: DesignTokens.space4) {
            HStack(spacing: DesignTokens.space12) {
                // Far Left: Album artwork square (strictly constrained to 52x52)
                Group {
                    if let artwork = activity.artwork, let image = NSImage(data: artwork) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(1, contentMode: .fill)
                    } else {
                        ZStack {
                            DesignTokens.chipFill
                            Image(systemName: "music.note")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(DesignTokens.textSecondary)
                        }
                    }
                }
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.radiusChip + 2, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.radiusChip + 2, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                )

                // Middle: Track title and artist (next to the square artwork)
                VStack(alignment: .leading, spacing: DesignTokens.space2) {
                    Text(activity.title)
                        .font(DesignTokens.titleFont)
                        .foregroundStyle(DesignTokens.textPrimary)
                        .lineLimit(1)
                    if let subtitle = activity.subtitle {
                        Text(subtitle)
                            .font(DesignTokens.subtitleFont)
                            .foregroundStyle(DesignTokens.textSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Right: transport controls cluster
                mediaControls(for: activity)
            }
            .frame(maxHeight: .infinity)

            // Bottom: the progress bar spanning the full width.
            progressTrack(activity.progress ?? 0)
        }
        .padding(.leading, DesignTokens.contentInset)
        .padding(.trailing, DesignTokens.contentInset + petExpandedReserve)
        .padding(.top, 2)
        .padding(.bottom, DesignTokens.space8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    /// The activity's leading mark: the source's own artwork when the player
    /// published any, otherwise its glyph.
    ///
    /// Artwork is clipped to a rounded square of the same footprint the glyph
    /// would occupy, so a track with art and a track without sit identically
    /// in the layout — the swap never shifts the text beside it.
    @ViewBuilder
    private func icon(for activity: Activity, size: CGFloat) -> some View {
        if let artwork = activity.artwork, let image = NSImage(data: artwork) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                )
        } else {
            Image(systemName: activity.resolvedSymbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(iconColor(for: activity))
        }
    }

    /// The artwork that fills its container — used by the expanded music
    /// surface where the album art is the hero.
    @ViewBuilder
    private func artworkFill(for activity: Activity) -> some View {
        if let artwork = activity.artwork, let image = NSImage(data: artwork) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            ZStack {
                DesignTokens.chipFill
                Image(systemName: "music.note")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func iconColor(for activity: Activity) -> Color {
        switch activity.kind {
        case .lowBattery, .recording, .microphone, .camera:
            return DesignTokens.warning
        default:
            return DesignTokens.textPrimary
        }
    }

    /// The right-side control: progress track, numeric readout, or media control.
    @ViewBuilder
    private func trailingControl(for activity: Activity) -> some View {
        switch activity.kind {
        case .volume, .brightness, .battery, .download:
            if let progress = activity.progress {
                progressTrack(progress)
            }
        case .timer:
            if let elapsed = activity.elapsed {
                Text(Activity.format(elapsed))
                    .font(DesignTokens.numericFont)
                    .foregroundStyle(DesignTokens.textPrimary)
                    .monospacedDigit()
            }
        case .music:
            mediaControls(for: activity)
        case .songRecognition:
            MusicVisualizer(isPlaying: true, tint: DesignTokens.accent)
        default:
            EmptyView()
        }
    }

    private func progressTrack(_ progress: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: DesignTokens.radiusTrack, style: .continuous)
                    .fill(DesignTokens.chipFill)
                RoundedRectangle(cornerRadius: DesignTokens.radiusTrack, style: .continuous)
                    .fill(DesignTokens.accent)
                    .frame(width: max(6, geo.size.width * CGFloat(progress)))
            }
        }
        .frame(height: 4)
        .animation(DesignTokens.springSettle, value: progress)
    }

    /// The transport cluster: skip-back, play/pause, skip-forward.
    ///
    /// The three sit in one rounded capsule so they read as a single control
    /// surface rather than three loose squares. Play/pause is the anchor — a
    /// filled white puck, larger than its neighbours — and the skip buttons are
    /// quiet glyphs beside it, which is the hierarchy every media player uses
    /// and why the previous row of three identical boxes looked wrong.
    private func mediaControls(for activity: Activity) -> some View {
        let transport = MediaTransport(isPlaying: activity.isPlaying, canControl: canControlMedia)
        return HStack(spacing: 2) {
            mediaButton(.previous, symbol: "backward.fill", size: 11)
            mediaButton(.togglePlayPause, symbol: transport.playPauseSymbol, size: 12, isPrimary: true)
            mediaButton(.next, symbol: "forward.fill", size: 11)
        }
        .padding(3)
        .background(DesignTokens.controlClusterFill, in: Capsule())
        .overlay(Capsule().strokeBorder(DesignTokens.controlClusterStroke, lineWidth: 0.5))
    }

    /// One transport button. `isPrimary` marks the play/pause puck, which is
    /// filled and slightly larger so the eye lands on it first.
    ///
    /// These are drawn as static glyphs — the window hit-tests clicks against
    /// `MediaControlLayout` and routes them, so the view never needs to hold
    /// interactive controls (which would force the window to take key focus).
    @ViewBuilder
    private func mediaButton(
        _ command: MediaCommand,
        symbol: String,
        size: CGFloat,
        isPrimary: Bool = false
    ) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(isPrimary ? DesignTokens.controlPrimaryGlyph : DesignTokens.textPrimary)
            .frame(width: isPrimary ? 28 : 24, height: 24)
            .background(
                isPrimary ? DesignTokens.controlPrimaryFill : Color.clear,
                in: Circle()
            )
            .contentShape(Circle())
            .opacity(canControlMedia ? 1 : 0.4)
    }

    // MARK: - Stack badge

    /// The "+N" badge shown when activities are queued behind the primary one.
    var stackBadge: some View {
        Text("+\(stackCount)")
            .font(DesignTokens.badgeFont)
            .foregroundStyle(DesignTokens.textPrimary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(DesignTokens.chipFill, in: Rectangle())
    }
}

// MARK: - Content transition

/// Blur + fade + a slight settle from the top — content condenses out of (and
/// back into) the notch rather than popping.
private struct IslandContentReveal: ViewModifier {
    /// 0 = hidden, 1 = fully shown.
    let progress: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .blur(radius: (1 - progress) * DesignTokens.contentBlurRadius)
            .scaleEffect(DesignTokens.contentScale + (1 - DesignTokens.contentScale) * progress, anchor: .top)
    }
}

extension AnyTransition {
    /// Island content: leaves fast, arrives just after the surface starts
    /// moving. Each direction carries its own timing, independent of the
    /// spring moving the surface.
    static var islandContent: AnyTransition {
        let reveal = AnyTransition.modifier(
            active: IslandContentReveal(progress: 0),
            identity: IslandContentReveal(progress: 1)
        )
        return .asymmetric(
            insertion: reveal.animation(DesignTokens.contentIn),
            removal: reveal.animation(DesignTokens.contentOut)
        )
    }
}

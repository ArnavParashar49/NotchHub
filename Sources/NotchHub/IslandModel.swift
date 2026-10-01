import NotchHubCore
import NotchHubSystem
import SwiftUI

/// The island's live state, owned by the coordinator and observed by the view.
///
/// The island used to be re-installed into the hosting view on every change
/// (`hostingView.rootView = AnyView(IslandView(…))`). That replaces the view
/// tree on each transition, which erases SwiftUI's structural identity and
/// stops the spring from animating a change continuously — the shape would
/// re-render rather than *morph*, which is exactly the jerkiness the animation
/// is supposed to avoid.
///
/// Holding the state in one observable object keeps the hosted view stable, so
/// `IslandView`'s `.animation(_:value:)` sees a real before/after and springs
/// between the two shapes.
@MainActor
final class IslandModel: ObservableObject {
    @Published var current: Activity?
    @Published var stackCount: Int = 0
    @Published var state: IslandState = .idle
    /// The island's frame in the hosting window's SwiftUI coordinates.
    @Published var localFrame: CGRect = .zero
    /// The notch's own corner radius.
    @Published var cornerRadius: CGFloat = 0
    /// The notch's height — the bar every sideways surface sits at.
    @Published var notchInset: CGFloat = 0
    /// The notch's width — the gap the wings leave in the middle.
    @Published var notchWidth: CGFloat = 0
    /// Whether the island is idle (tucked behind the notch).
    @Published var isIdle: Bool = true
    /// What the two wings show while the island is in its sideways peek.
    @Published var wingStatus: WingStatus = WingStatus()
    /// How much room the current content needs on each side of the notch. The
    /// island grows its surface to fit this and collapses when it shrinks.
    @Published var contentSize: IslandContentSize = .default
    /// A surface that replaces the queue-driven content, when one is showing.
    @Published var panelContent: AnyView?
    /// Whether the now-playing surface may drive the player.
    @Published var canControlMedia: Bool = MediaRemote.canControlTransport

    /// Whether the black surface is painted — see `IslandView.surfaceVisible`.
    @Published var surfaceVisible: Bool = false
    /// The live call, for the compact bar's timer and mute state.
    @Published var meeting: Meeting?
    /// The pixel pet, when shown.
    @Published var pet: PetRenderModel?
    /// Whether this display has a notch (no idle dock or idle pet without one).
    @Published var hasNotch: Bool = true
    /// The drawn control the cursor is resting on. The island's controls are
    /// drawn rather than being real buttons (it never takes key focus), so
    /// SwiftUI's own `.onHover` never fires for them — the coordinator resolves
    /// the cursor against the hit-test layouts and publishes the answer here.
    @Published var hoveredControl: IslandControl?
    /// NEO's lane — its orb and line — while NEO is out of the notch.
    @Published var neo: NeoLaneContent?
    /// The notch's left edge in the hosting window's SwiftUI coordinates: the
    /// lane hangs from it, whatever shape the island is in.
    @Published var notchLeadingX: CGFloat?
}

/// The hosted root: a thin adapter that observes the model and hands its values
/// to the pure `IslandView`. Keeping this view's identity stable across every
/// update is the whole point — see `IslandModel`.
struct IslandRootView: View {
    @ObservedObject var model: IslandModel

    var body: some View {
        IslandView(
            current: model.current,
            stackCount: model.stackCount,
            state: model.state,
            localFrame: model.localFrame,
            cornerRadius: model.cornerRadius,
            notchInset: model.notchInset,
            isIdle: model.isIdle,
            wingStatus: model.wingStatus,
            notchWidth: model.notchWidth,
            contentSize: model.contentSize,
            panelContent: model.panelContent,
            hoveredControl: model.hoveredControl,
            canControlMedia: model.canControlMedia,
            surfaceVisible: model.surfaceVisible,
            meeting: model.meeting,
            pet: model.pet,
            hasNotch: model.hasNotch,
            neo: model.neo,
            notchLeadingX: model.notchLeadingX
        )
    }
}

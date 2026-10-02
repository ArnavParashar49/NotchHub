import NotchHubCore
import SwiftUI

/// The island's user-configurable settings.
///
/// Plain value model. Each feature has an on/off toggle; disabled features read
/// as off and (per the app's contract) create no listeners or background work.
struct IslandSettings {
    var music: Bool = true
    var volume: Bool = true
    var brightness: Bool = true
    var battery: Bool = true
    var airPods: Bool = true
    var bluetooth: Bool = true
    var timers: Bool = true
    var downloads: Bool = true
    var notifications: Bool = true
    var calendar: Bool = true
    var meetings: Bool = true
    var focus: Bool = true
    var weather: Bool = false
    var clipboard: Bool = true
    var fileSharing: Bool = true
    var privacy: Bool = true
    var codingAgent: Bool = true
    var appDetails: Bool = true
    var teleprompter: Bool = true
    var camera: Bool = true
    var ghostMode: Bool = false
    var neo: Bool = true
    /// The pixel pet's settings (stored separately from the feature gates):
    /// its switches on the features page, and everything on its own page —
    /// whatever was chosen in the pet's panel is carried here too, so saving
    /// from Settings never writes back an older look or hat.
    var pet = PetSettings()

    var petSettings: PetSettings {
        get { pet }
        set { pet = newValue }
    }

    // The pet's switches, as the features page's tiles address them.
    var showPet: Bool {
        get { pet.showPet }
        set { pet.showPet = newValue }
    }
    var petReactions: Bool {
        get { pet.reactions }
        set { pet.reactions = newValue }
    }
    var petIdleAnimations: Bool {
        get { pet.idleAnimations }
        set { pet.idleAnimations = newValue }
    }
    var petInteraction: Bool {
        get { pet.interaction }
        set { pet.interaction = newValue }
    }
    var petMischief: Bool {
        get { pet.mischief }
        set { pet.mischief = newValue }
    }
    var petHolidays: Bool {
        get { pet.holidays }
        set { pet.holidays = newValue }
    }

    var weatherCity: String = ""
}

extension IslandSettings {
    /// Builds the view model from the persisted feature settings — the single
    /// source of truth that actually gates which listeners run.
    init(featureSettings: FeatureSettings) {
        self.init()
        music = featureSettings.isEnabled(.music)
        volume = featureSettings.isEnabled(.volume)
        brightness = featureSettings.isEnabled(.brightness)
        battery = featureSettings.isEnabled(.battery)
        airPods = featureSettings.isEnabled(.airpods)
        bluetooth = featureSettings.isEnabled(.bluetooth)
        timers = featureSettings.isEnabled(.timers)
        downloads = featureSettings.isEnabled(.downloads)
        notifications = featureSettings.isEnabled(.notifications)
        calendar = featureSettings.isEnabled(.calendar)
        meetings = featureSettings.isEnabled(.meetings)
        focus = featureSettings.isEnabled(.focus)
        weather = featureSettings.isEnabled(.weather)
        clipboard = featureSettings.isEnabled(.clipboard)
        fileSharing = featureSettings.isEnabled(.fileSharing)
        privacy = featureSettings.isEnabled(.privacy)
        codingAgent = featureSettings.isEnabled(.codingAgent)
        appDetails = featureSettings.isEnabled(.appDetails)
        teleprompter = featureSettings.isEnabled(.teleprompter)
        camera = featureSettings.isEnabled(.camera)
        ghostMode = featureSettings.isEnabled(.ghostMode)
        neo = featureSettings.isEnabled(.neo)
    }

    /// Persists this view model's toggles back into a `FeatureSettings`.
    func toFeatureSettings() -> FeatureSettings {
        var settings = FeatureSettings()
        settings.setEnabled(.music, enabled: music)
        settings.setEnabled(.volume, enabled: volume)
        settings.setEnabled(.brightness, enabled: brightness)
        settings.setEnabled(.battery, enabled: battery)
        settings.setEnabled(.airpods, enabled: airPods)
        settings.setEnabled(.bluetooth, enabled: bluetooth)
        settings.setEnabled(.timers, enabled: timers)
        settings.setEnabled(.downloads, enabled: downloads)
        settings.setEnabled(.notifications, enabled: notifications)
        settings.setEnabled(.calendar, enabled: calendar)
        settings.setEnabled(.meetings, enabled: meetings)
        settings.setEnabled(.focus, enabled: focus)
        settings.setEnabled(.weather, enabled: weather)
        settings.setEnabled(.clipboard, enabled: clipboard)
        settings.setEnabled(.fileSharing, enabled: fileSharing)
        settings.setEnabled(.privacy, enabled: privacy)
        settings.setEnabled(.codingAgent, enabled: codingAgent)
        settings.setEnabled(.appDetails, enabled: appDetails)
        settings.setEnabled(.teleprompter, enabled: teleprompter)
        settings.setEnabled(.camera, enabled: camera)
        settings.setEnabled(.ghostMode, enabled: ghostMode)
        settings.setEnabled(.neo, enabled: neo)
        return settings
    }
}

/// The island's settings panel.
///
/// A header with a live count and a Done button, then the features as tappable
/// tiles in three groups (Glance, Connected, Tools), the weather card with its
/// city field, and a quiet footer. Monochrome, like the island itself: a tile
/// is its own switch — lit white when on, dim when off. The window takes key status while this panel is open
/// (`needsInteraction`), so these are real SwiftUI controls.
///
/// One tile is a door instead of a switch: NEO's opens the NEO section
/// (`NeoSettingsSection`) — the feature's own switch, and NEO.app's menu,
/// which lives here while the notch hosts NEO. And the pet's group has a door
/// beside its caption: "Customise" opens the pet's page
/// (`PetSettingsSection`) — its look, what it wears, its size and side, its
/// personality and its name.
struct SettingsView: View {
    /// Which page of the panel shows.
    enum Page: Equatable {
        case features
        case neo
        /// Making the pet one's own.
        case pet
    }

    @Binding var settings: IslandSettings
    let onChange: () -> Void
    let onClose: () -> Void
    /// What the NEO section shows, and where its taps go.
    let neo: NeoSettingsModel
    let onNeo: (NeoSettingsIntent) -> Void
    /// `false` only for headless snapshots: an image renderer cannot draw a
    /// scroll view, so the page is laid out bare.
    let scrolls: Bool
    @State private var page: Page

    init(
        settings: Binding<IslandSettings>,
        onChange: @escaping () -> Void,
        onClose: @escaping () -> Void = {},
        neo: NeoSettingsModel = NeoSettingsModel(featureOn: false, connected: false, shell: nil),
        onNeo: @escaping (NeoSettingsIntent) -> Void = { _ in },
        page: Page = .features,
        scrolls: Bool = true
    ) {
        self._settings = settings
        self.onChange = onChange
        self.onClose = onClose
        self.neo = neo
        self.onNeo = onNeo
        self.scrolls = scrolls
        self._page = State(initialValue: page)
    }

    // MARK: - Model

    fileprivate struct Item: Identifiable {
        let title: String
        let symbol: String
        let key: WritableKeyPath<IslandSettings, Bool>
        /// A line under the title, for a tile whose name does not say enough on
        /// its own. Most do; Ghost Mode has to say what it actually hides.
        var detail: String? = nil
        /// The page the tile opens instead of switching (its switch is there).
        var opens: Page? = nil
        var id: String { title }
    }

    fileprivate struct Group: Identifiable {
        let title: String
        let tint: Color
        let items: [Item]
        /// A page the group's caption opens, with the button's title.
        var door: (title: String, page: Page)? = nil
        var id: String { title }
    }

    private var groups: [Group] {
        [
            Group(title: "Glance", tint: SettingsMetrics.ink, items: [
                Item(title: "Music", symbol: "music.note", key: \.music),
                Item(title: "Volume", symbol: "speaker.wave.2.fill", key: \.volume),
                Item(title: "Brightness", symbol: "sun.max.fill", key: \.brightness),
                Item(title: "Battery", symbol: "battery.75", key: \.battery),
                Item(title: "Downloads", symbol: "arrow.down.circle.fill", key: \.downloads),
                Item(title: "Timers", symbol: "timer", key: \.timers),
            ]),
            Group(title: "Connected", tint: SettingsMetrics.ink, items: [
                Item(title: "AirPods", symbol: "airpodspro", key: \.airPods),
                Item(title: "Bluetooth", symbol: "dot.radiowaves.left.and.right", key: \.bluetooth),
                Item(title: "Notifications", symbol: "bell.fill", key: \.notifications),
                Item(title: "Focus", symbol: "moon.fill", key: \.focus),
                Item(title: "Calendar", symbol: "calendar", key: \.calendar),
                Item(title: "Meetings", symbol: "video.fill", key: \.meetings),
            ]),
            Group(title: "Tools", tint: SettingsMetrics.ink, items: [
                Item(title: "Clipboard", symbol: "doc.on.clipboard.fill", key: \.clipboard),
                Item(title: "Teleprompter", symbol: "text.alignleft", key: \.teleprompter),
                Item(title: "Camera", symbol: "video.fill", key: \.camera),
                Item(title: "File Sharing", symbol: "square.and.arrow.up.fill", key: \.fileSharing),
                Item(title: "Privacy Indicators", symbol: "hand.raised.fill", key: \.privacy),
                Item(title: "App Details", symbol: "macwindow", key: \.appDetails),
                Item(title: "Coding Agent", symbol: "sparkles", key: \.codingAgent),
                Item(title: "Ghost Mode", symbol: "eye.slash.fill", key: \.ghostMode,
                     detail: "Hidden from screen sharing"),
                Item(title: "NEO", symbol: "waveform.circle.fill", key: \.neo,
                     detail: "Its chat, keys and permissions", opens: .neo),
            ]),
            Group(title: settings.pet.displayName, tint: SettingsMetrics.ink, items: [
                Item(title: "Show \(settings.pet.displayName)", symbol: "pawprint.fill", key: \.showPet),
                Item(title: "Reactions", symbol: "sparkles", key: \.petReactions),
                Item(title: "Idle Animations", symbol: "wind", key: \.petIdleAnimations),
                Item(title: "Interaction", symbol: "hand.tap.fill", key: \.petInteraction),
                Item(title: "Mischief", symbol: "hare.fill", key: \.petMischief),
                Item(title: "Holidays", symbol: "gift.fill", key: \.petHolidays),
            ], door: ("Customise", .pet)),
        ]
    }

    private var enabledCount: Int {
        groups.flatMap(\.items).filter { settings[keyPath: $0.key] }.count + (settings.weather ? 1 : 0)
    }

    private var totalCount: Int {
        groups.flatMap(\.items).count + 1
    }

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: SettingsMetrics.tileSpacing), count: 3)

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, SettingsMetrics.inset)
                .padding(.top, 8)
                .padding(.bottom, 12)

            if scrolls {
                ScrollView { pageContent }
                    .scrollIndicators(.hidden)
                    .overlay(alignment: .top) {
                        LinearGradient(colors: [DesignTokens.islandFill, DesignTokens.islandFill.opacity(0)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 10)
                            .allowsHitTesting(false)
                    }
            } else {
                pageContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var pageContent: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.groupSpacing) {
            switch page {
            case .features:
                ForEach(groups) { group in
                    groupView(group)
                }
                weatherCard
                footer
            case .neo:
                NeoSettingsSection(
                    model: neo,
                    featureOn: settings.neo,
                    onToggleFeature: {
                        settings.neo.toggle()
                        onChange()
                    },
                    onIntent: onNeo
                )
            case .pet:
                PetSettingsSection(pet: Binding(
                    get: { settings.pet },
                    set: {
                        settings.pet = $0
                        onChange()
                    }
                ), headless: !scrolls)
            }
        }
        .padding(.horizontal, SettingsMetrics.inset)
        .padding(.bottom, SettingsMetrics.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Header & footer

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            if page != .features {
                Button { page = .features } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DesignTokens.textPrimary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.white.opacity(0.10)))
                        .contentShape(Circle())
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Back to Settings")
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(pageTitle)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(DesignTokens.textPrimary)
                Text(pageSubtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(DesignTokens.textTertiary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Button(action: onClose) {
                Text("Done")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 16)
                    .frame(height: 28)
                    .background(Capsule().fill(Color.white))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
        }
    }

    private var pageTitle: String {
        switch page {
        case .features: return "Settings"
        case .neo: return "NEO"
        case .pet: return "Pet"
        }
    }

    private var pageSubtitle: String {
        switch page {
        case .features: return "\(enabledCount) of \(totalCount) features on"
        case .neo: return neo.subtitle
        case .pet: return "\(settings.pet.displayName) the fox — look, wear, size, personality"
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text("NotchHub \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
            Text("·")
            Text("⌥⌘, opens this panel")
                .lineLimit(1)
            Spacer(minLength: 8)
            Button { NSApp.terminate(nil) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "power")
                        .font(.system(size: 10, weight: .bold))
                    Text("Quit NotchHub")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(DesignTokens.live)
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background(Capsule().fill(DesignTokens.live.opacity(0.14)))
                .contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
        }
        .font(.system(size: 10, weight: .medium, design: .rounded))
        .foregroundStyle(DesignTokens.textTertiary)
        .padding(.horizontal, 4)
    }

    // MARK: - Groups

    private func groupView(_ group: Group) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let door = group.door {
                // The caption stays where it is; the door hangs off its row's
                // trailing end without taking any room.
                sectionLabel(group.title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .trailing) {
                        SectionDoor(title: door.title) { page = door.page }
                    }
            } else {
                sectionLabel(group.title)
            }
            LazyVGrid(columns: Self.columns, spacing: SettingsMetrics.tileSpacing) {
                ForEach(group.items) { item in
                    FeatureTile(
                        title: item.title,
                        symbol: item.symbol,
                        detail: item.detail,
                        tint: group.tint,
                        isOn: settings[keyPath: item.key],
                        opensSection: item.opens != nil
                    ) {
                        if let opens = item.opens {
                            page = opens
                        } else {
                            settings[keyPath: item.key].toggle()
                            onChange()
                        }
                    }
                }
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        SettingsSectionLabel(text: text)
    }

    // MARK: - Weather

    private var weatherCard: some View {
        let tint = SettingsMetrics.ink
        return VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Weather")
            HStack(spacing: 10) {
                Image(systemName: "cloud.sun.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(settings.weather ? tint : DesignTokens.textTertiary)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(settings.weather ? SettingsMetrics.onFill : 0.06))
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text("Weather")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(DesignTokens.textPrimary)
                    Text("On the hover strip and dashboard")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(DesignTokens.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DesignTokens.textTertiary)
                    TextField("City", text: $settings.weatherCity)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(DesignTokens.textPrimary)
                }
                .padding(.horizontal, 9)
                .frame(width: 128, height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.08)))
                .opacity(settings.weather ? 1 : 0.55)

                Button {
                    settings.weather.toggle()
                    onChange()
                } label: {
                    SwitchIndicator(isOn: settings.weather, tint: tint)
                }
                .buttonStyle(PressStyle())
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: SettingsMetrics.cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.045))
            )
            .overlay(
                RoundedRectangle(cornerRadius: SettingsMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
            )
        }
    }
}

// MARK: - Pieces

/// A group's caption: small, tracked capitals.
struct SettingsSectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(DesignTokens.textTertiary)
            .padding(.leading, 4)
    }
}

/// A small door at the end of a group's caption row: opens the group's page.
private struct SectionDoor: View {
    let title: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                Image(systemName: "chevron.right")
                    .font(.system(size: 7, weight: .heavy))
            }
            .foregroundStyle(DesignTokens.textPrimary)
            .padding(.horizontal, 9)
            .frame(height: 20)
            .background(Capsule().fill(Color.white.opacity(isHovered ? SettingsMetrics.onFillHovered : SettingsMetrics.onFill)))
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .accessibilityLabel("\(title): look, wear, size and personality")
    }
}

enum SettingsMetrics {
    static let inset: CGFloat = 18
    static let tileSpacing: CGFloat = 8
    static let groupSpacing: CGFloat = 16
    static let tileHeight: CGFloat = 58
    static let cornerRadius: CGFloat = 12
    /// The panel is monochrome: "on" is expressed in white, never in colour.
    static let ink = Color.white
    static let onFill: Double = 0.14
    static let onFillHovered: Double = 0.20
    static let offFill: Double = 0.045
    static let offFillHovered: Double = 0.08
}

/// One feature: a tile that is its own switch.
private struct FeatureTile: View {
    let title: String
    let symbol: String
    var detail: String? = nil
    let tint: Color
    let isOn: Bool
    /// The tile opens a section rather than switching: a chevron, not a dot.
    var opensSection = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Image(systemName: symbol)
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isOn ? tint : DesignTokens.textTertiary)
                        .frame(height: 18)
                    Spacer(minLength: 0)
                    if opensSection {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .heavy))
                            .foregroundStyle(Color.white.opacity(isOn ? 1 : 0.3))
                            .padding(.top, 2)
                    } else {
                        Circle()
                            .fill(Color.white.opacity(isOn ? 1 : 0.18))
                            .frame(width: 6, height: 6)
                            .padding(.top, 3)
                    }
                }
                Spacer(minLength: 0)
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(isOn ? DesignTokens.textPrimary : DesignTokens.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let detail {
                    Text(detail)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(DesignTokens.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: SettingsMetrics.tileHeight, maxHeight: SettingsMetrics.tileHeight, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: SettingsMetrics.cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(isOn
                        ? (isHovered ? SettingsMetrics.onFillHovered : SettingsMetrics.onFill)
                        : (isHovered ? SettingsMetrics.offFillHovered : SettingsMetrics.offFill)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: SettingsMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(isOn ? 0.22 : 0.06), lineWidth: 0.75)
            )
            .contentShape(RoundedRectangle(cornerRadius: SettingsMetrics.cornerRadius, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .onHover { isHovered = $0 }
        .animation(.spring(response: 0.28, dampingFraction: 0.85), value: isOn)
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

/// Presses feel physical: the control sinks slightly while held and springs
/// back on release, independent of how long the action takes.
struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .brightness(configuration.isPressed ? -0.04 : 0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// A compact on/off switch.
struct SwitchIndicator: View {
    let isOn: Bool
    let tint: Color

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? tint : Color.white.opacity(0.16))
            Circle()
                .fill(isOn ? Color.black : Color.white.opacity(0.9))
                .frame(width: 14, height: 14)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                .padding(2)
        }
        .frame(width: 32, height: 18)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: isOn)
    }
}

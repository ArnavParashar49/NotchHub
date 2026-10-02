import NotchHubCore
import SwiftUI

/// The pet's page of Settings: making the fox one's own.
///
/// A live preview at the top — the fox as it is now, enlarged, and at its true
/// size beside a notch on the side it lives on — then four groups: Look (its
/// fur: a preset or a colour of one's own, and the colour of NEO's listening
/// glow), Wear (a hat and an accessory, which combine), Size & place, and
/// Personality (its energy, its night, its name). Every control writes
/// `PetSettings` through the binding, and the app applies it at once: the fox
/// in the notch changes as the preview does, with no relaunch.
///
/// Monochrome like the rest of the panel; the only colour is the fox's own.
/// Every control is drawn here (no AppKit-backed sliders or pickers), so the
/// page looks the same in a headless snapshot as on screen.
struct PetSettingsSection: View {
    @Binding var pet: PetSettings
    /// The day the preview dresses for (a seasonal hat depends on it).
    var now = Date()
    /// Today's holiday, if the pet marks them.
    var holiday: PetHoliday? = nil
    /// `true` only for headless snapshots: an image renderer cannot draw a
    /// text field, so the name is shown as plain text.
    var headless = false

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.groupSpacing) {
            preview
            group("Look") {
                furRow
                if pet.usesCustomFur {
                    separator
                    customFurRows
                }
                separator
                glowRow
            }
            group("Wear") {
                hatRow
                separator
                accessoryRow
            }
            group("Size & place") {
                choiceRow("Size", symbol: "arrow.up.left.and.arrow.down.right", options: PetSize.allCases,
                          title: \.title, selection: $pet.size)
                separator
                choiceRow("Home", symbol: "house.fill", options: [PetHome.left, .right, .auto],
                          title: \.title, selection: $pet.home, caption: homeCaption)
            }
            group("Personality") {
                choiceRow("Energy", symbol: "bolt.fill", options: PetEnergy.allCases,
                          title: \.title, selection: $pet.energy, caption: energyCaption)
                separator
                nightRow
                separator
                nameRow
            }
        }
    }

    // MARK: - Preview

    private var hat: PetHat? { pet.hat.hat(on: now, holiday: pet.holidays ? holiday : nil) }
    private var palette: PetPalette { pet.palette }
    private var still: PetPresentation {
        PetPresentation(mood: .idle, animation: .happy, startedAt: .distantPast)
    }

    /// The fox as it is now: enlarged on the left; on the right at its true
    /// size, beside a notch, on the side it lives on.
    private var preview: some View {
        HStack(alignment: .center, spacing: 14) {
            PetView(presentation: still, scale: 3, look: pet.look, hat: hat,
                    palette: palette, accessory: pet.accessory.accessory, name: pet.displayName)
                .padding(.top, 24)
                .padding(.bottom, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(pet.displayName)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(DesignTokens.textPrimary)
                    .lineLimit(1)
                Text(summary)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(DesignTokens.textTertiary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            PetNotchPreview(pet: pet, hat: hat)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SettingsMetrics.cornerRadius, style: .continuous)
                .fill(Color.white.opacity(SettingsMetrics.offFill))
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsMetrics.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(pet.displayName): \(summary)")
    }

    private var summary: String {
        var parts = [pet.usesCustomFur ? "Custom fur" : "\(pet.look.title) fur"]
        if pet.hat != .none { parts.append(pet.hat.title) }
        if let accessory = pet.accessory.accessory { parts.append(accessory.title) }
        parts.append("\(pet.size.title) size")
        parts.append("\(pet.energy.title) energy")
        return parts.joined(separator: " · ")
    }

    // MARK: - Groups

    private func group(_ title: String, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSectionLabel(text: title)
            VStack(spacing: 0, content: rows)
                .background(
                    RoundedRectangle(cornerRadius: SettingsMetrics.cornerRadius, style: .continuous)
                        .fill(Color.white.opacity(SettingsMetrics.offFill))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SettingsMetrics.cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: SettingsMetrics.cornerRadius, style: .continuous))
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(DesignTokens.rowSeparator)
            .frame(height: 0.5)
            .padding(.leading, PetSettingsMetrics.textLeading)
    }

    private func rowIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(SettingsMetrics.ink)
            .frame(width: PetSettingsMetrics.textLeading)
    }

    private func rowTitle(_ title: String, caption: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(PetSettingsMetrics.titleFont)
                .foregroundStyle(DesignTokens.textPrimary)
                .lineLimit(1)
            if let caption {
                Text(caption)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(DesignTokens.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    // MARK: - Look

    /// The presets, then "a colour of your own".
    private var furRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                rowIcon("paintpalette.fill")
                rowTitle("Fur", caption: pet.usesCustomFur ? "Your own colour" : pet.look.title)
                Spacer(minLength: 8)
            }
            HStack(spacing: PetSettingsMetrics.swatchSpacing) {
                ForEach(PetLook.allCases, id: \.self) { look in
                    Button {
                        pet.look = look
                        pet.usesCustomFur = false
                    } label: {
                        PetSwatch(fill: .solid(PetCanvas.color(look.swatch)), isOn: !pet.usesCustomFur && pet.look == look)
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("\(look.title) fur")
                }
                Button {
                    pet.usesCustomFur = true
                } label: {
                    PetSwatch(fill: .spectrum, isOn: pet.usesCustomFur)
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Custom fur colour")
            }
            .padding(.leading, PetSettingsMetrics.textLeading)
        }
        .padding(.trailing, 10)
        .padding(.vertical, 9)
    }

    /// Hue, saturation and lightness of the custom fur. What is drawn is the
    /// pick kept readable on black (`PetPalette.custom`), and the sliders'
    /// tracks show exactly that.
    private var customFurRows: some View {
        VStack(spacing: 6) {
            slider("Hue", value: $pet.customFur.hue) { PetFurColor(hue: $0, saturation: 0.85, lightness: 0.6) }
            slider("Colour", value: $pet.customFur.saturation) {
                PetFurColor(hue: pet.customFur.hue, saturation: $0, lightness: pet.customFur.lightness)
            }
            slider("Light", value: $pet.customFur.lightness) {
                PetFurColor(hue: pet.customFur.hue, saturation: pet.customFur.saturation, lightness: $0)
            }
        }
        .padding(.leading, PetSettingsMetrics.textLeading)
        .padding(.trailing, 10)
        .padding(.vertical, 9)
    }

    private func slider(_ title: String, value: Binding<Double>, color: @escaping (Double) -> PetFurColor) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(DesignTokens.textSecondary)
                .frame(width: 40, alignment: .leading)
            PetColorSlider(value: value, stops: (0...12).map { step in
                PetCanvas.color(PetPalette.clampedFur(color(Double(step) / 12)).rgb)
            })
            .accessibilityLabel("\(title) of the custom fur colour")
        }
    }

    private var glowRow: some View {
        HStack(spacing: 0) {
            rowIcon("sun.max.fill")
            rowTitle("Listening glow", caption: pet.glow.title)
            Spacer(minLength: 8)
            HStack(spacing: PetSettingsMetrics.swatchSpacing) {
                ForEach(PetGlowColor.allCases, id: \.self) { glow in
                    Button { pet.glow = glow } label: {
                        PetSwatch(
                            fill: .solid(glow.rgb(palette: palette).map(PetCanvas.color) ?? DesignTokens.listeningGlow),
                            isOn: pet.glow == glow,
                            badge: glow == .matchFur ? "pawprint.fill" : nil
                        )
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel("\(glow.title) glow")
                }
            }
        }
        .padding(.trailing, 10)
        .frame(minHeight: PetSettingsMetrics.rowHeight)
        .padding(.vertical, 4)
    }

    // MARK: - Wear

    private static let hatColumns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)
    private static let accessoryColumns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)

    private var hatRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                rowIcon("party.popper.fill")
                rowTitle("Hat", caption: pet.hat == .seasonal ? "Seasonal — it dresses for the time of year" : pet.hat.title)
                Spacer(minLength: 8)
            }
            LazyVGrid(columns: Self.hatColumns, spacing: 6) {
                ForEach(PetHatChoice.allCases, id: \.self) { choice in
                    PetChip(title: Self.shortTitle(choice), symbol: PetPanelView.symbol(for: choice), isOn: pet.hat == choice) {
                        pet.hat = choice
                    }
                    .accessibilityLabel(choice.title)
                }
            }
            .padding(.leading, PetSettingsMetrics.textLeading)
        }
        .padding(.trailing, 10)
        .padding(.vertical, 9)
    }

    private var accessoryRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                rowIcon("eyeglasses")
                rowTitle("Accessory", caption: "Worn with any hat")
                Spacer(minLength: 8)
            }
            LazyVGrid(columns: Self.accessoryColumns, spacing: 6) {
                ForEach(PetAccessoryChoice.allCases, id: \.self) { choice in
                    PetChip(title: choice.title, symbol: Self.symbol(for: choice), isOn: pet.accessory == choice) {
                        pet.accessory = choice
                    }
                }
            }
            .padding(.leading, PetSettingsMetrics.textLeading)
        }
        .padding(.trailing, 10)
        .padding(.vertical, 9)
    }

    static func shortTitle(_ choice: PetHatChoice) -> String {
        switch choice {
        case .seasonal: return "Seasonal"
        case .none: return "None"
        case .party: return "Party"
        case .witch: return "Witch"
        case .santa: return "Santa"
        case .flowers: return "Flowers"
        case .hearts: return "Hearts"
        case .shamrock: return "Shamrock"
        case .bunny: return "Bunny"
        case .turkey: return "Turkey"
        case .lunar: return "Lunar"
        case .marigold: return "Marigold"
        }
    }

    static func symbol(for choice: PetAccessoryChoice) -> String {
        switch choice {
        case .none: return "circle.slash"
        case .glasses: return "eyeglasses"
        case .sunglasses: return "sunglasses.fill"
        case .scarf: return "wind"
        case .bowtie: return "gift.fill"
        case .headphones: return "headphones"
        }
    }

    // MARK: - Size, place, energy

    private func choiceRow<Option: Hashable>(
        _ title: String, symbol: String, options: [Option], title optionTitle: KeyPath<Option, String>,
        selection: Binding<Option>, caption: String? = nil
    ) -> some View {
        HStack(spacing: 0) {
            rowIcon(symbol)
            rowTitle(title, caption: caption)
            Spacer(minLength: 8)
            PetSegments(options: options, title: { $0[keyPath: optionTitle] }, selection: selection)
                .accessibilityLabel(title)
        }
        .padding(.trailing, 10)
        .frame(minHeight: PetSettingsMetrics.rowHeight)
        .padding(.vertical, 4)
    }

    private var homeCaption: String {
        switch pet.home {
        case .right: return "Right of the notch"
        case .left: return "Left of the notch"
        case .auto: return "Stays where its games leave it"
        }
    }

    private var energyCaption: String {
        switch pet.energy {
        case .calm: return "Mostly sits and breathes"
        case .normal: return "Fidgets and plays now and then"
        case .playful: return "Plays far more often"
        }
    }

    // MARK: - Night

    private var nightRow: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                rowIcon("moon.zzz.fill")
                rowTitle("Sleeps at night", caption: pet.sleepsAtNight ? "\(PetNight(startHour: pet.nightStart, endHour: pet.nightEnd).label), unless you or NEO need it" : "Curls up between two hours")
                Spacer(minLength: 8)
                Button { pet.sleepsAtNight.toggle() } label: {
                    SwitchIndicator(isOn: pet.sleepsAtNight, tint: SettingsMetrics.ink)
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Sleeps at night")
                .accessibilityValue(pet.sleepsAtNight ? "On" : "Off")
            }
            if pet.sleepsAtNight {
                HStack(spacing: 10) {
                    PetHourStepper(title: "From", hour: $pet.nightStart)
                    PetHourStepper(title: "Until", hour: $pet.nightEnd)
                    Spacer(minLength: 0)
                }
                .padding(.leading, PetSettingsMetrics.textLeading)
            }
        }
        .padding(.trailing, 10)
        .frame(minHeight: PetSettingsMetrics.rowHeight)
        .padding(.vertical, 4)
    }

    // MARK: - Name

    private var nameRow: some View {
        HStack(spacing: 0) {
            rowIcon("character.cursor.ibeam")
            rowTitle("Name", caption: "NEO the assistant stays NEO")
            Spacer(minLength: 8)
            SwiftUI.Group {
                if headless {
                    Text(pet.name).frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField(PetIdentity.name, text: Binding(
                        get: { pet.name },
                        set: { pet.name = String($0.prefix(PetIdentity.maxNameLength)) }
                    ))
                    .textFieldStyle(.plain)
                }
            }
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(DesignTokens.textPrimary)
            .padding(.horizontal, 9)
            .frame(width: 150, height: 26)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.08)))
            .accessibilityLabel("The pet's name")
        }
        .padding(.trailing, 10)
        .frame(minHeight: PetSettingsMetrics.rowHeight)
        .padding(.vertical, 4)
    }
}

private enum PetSettingsMetrics {
    static let rowHeight: CGFloat = 36
    /// Where a row's title starts: the icon's column.
    static let textLeading: CGFloat = 38
    static let swatchSize: CGFloat = 22
    static let swatchSpacing: CGFloat = 8
    static let titleFont = Font.system(size: 12, weight: .semibold, design: .rounded)
}

/// The fox at its true size beside a notch, on the side it lives on: what the
/// size and home settings do, shown rather than described.
private struct PetNotchPreview: View {
    let pet: PetSettings
    let hat: PetHat?

    private static let notchWidth: CGFloat = 58
    private static let notchHeight: CGFloat = 32

    var body: some View {
        let metrics = PetMetrics(pet.size)
        let side = pet.home.side
        let dock = metrics.idleDock
        let width = Self.notchWidth + dock
        ZStack(alignment: .topLeading) {
            // The idle island: the notch and the pet's dock beside it.
            NotchShape(bottomRadius: 9, topRadius: 0)
                .fill(DesignTokens.islandFill)
                .frame(width: width, height: Self.notchHeight)
            // The hardware notch, a shade lighter so it reads as hardware.
            NotchShape(bottomRadius: 9, topRadius: 0)
                .fill(Color.white.opacity(0.10))
                .frame(width: Self.notchWidth, height: Self.notchHeight)
                .offset(x: side == .left ? dock : 0)
            PetView(
                presentation: PetPresentation(mood: .idle, animation: .sit, startedAt: .distantPast, mirrored: side == .left),
                scale: metrics.scale, look: pet.look, hat: hat, palette: pet.palette,
                accessory: pet.accessory.accessory, name: pet.displayName
            )
            .offset(
                x: side == .left ? dock - metrics.dockInset - metrics.side : Self.notchWidth + metrics.dockInset,
                y: metrics.stripY(notchHeight: Self.notchHeight)
            )
        }
        .frame(width: Self.notchWidth + PetMetrics(.large).idleDock, height: Self.notchHeight, alignment: side == .left ? .trailing : .leading)
        .accessibilityHidden(true)
    }
}

/// A round colour swatch: ringed when it is the current one.
private struct PetSwatch: View {
    enum Fill {
        case solid(Color)
        /// Every hue: "a colour of your own".
        case spectrum
    }

    let fill: Fill
    let isOn: Bool
    var badge: String? = nil

    var body: some View {
        ZStack {
            switch fill {
            case let .solid(color):
                Circle().fill(color)
            case .spectrum:
                Circle().fill(AngularGradient(
                    colors: (0...12).map { PetCanvas.color(PetColor.hsl(Double($0) / 12, 0.85, 0.62)) },
                    center: .center
                ))
            }
            if let badge {
                Image(systemName: badge)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.55))
            }
        }
        .frame(width: PetSettingsMetrics.swatchSize, height: PetSettingsMetrics.swatchSize)
        .overlay(Circle().strokeBorder(Color.black.opacity(isOn ? 0.9 : 0), lineWidth: 1.5).padding(1.5))
        .overlay(Circle().strokeBorder(Color.white.opacity(isOn ? 0.95 : 0.18), lineWidth: isOn ? 1.5 : 0.5))
        .contentShape(Circle())
    }
}

/// A small titled chip that is one choice of several: lit when chosen.
private struct PetChip: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 12)
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isOn ? DesignTokens.textPrimary : DesignTokens.textSecondary)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 26, maxHeight: 26)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(isOn
                        ? (isHovered ? SettingsMetrics.onFillHovered : SettingsMetrics.onFill)
                        : (isHovered ? SettingsMetrics.offFillHovered : SettingsMetrics.offFill)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(isOn ? 0.22 : 0.06), lineWidth: 0.75)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .onHover { isHovered = $0 }
        .accessibilityValue(isOn ? "Selected" : "")
    }
}

/// A segmented choice, drawn: the chosen segment lit white.
private struct PetSegments<Option: Hashable>: View {
    let options: [Option]
    let title: (Option) -> String
    @Binding var selection: Option

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let isOn = option == selection
                Button { selection = option } label: {
                    Text(title(option))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(isOn ? Color.black : DesignTokens.textSecondary)
                        .lineLimit(1)
                        .frame(width: 58, height: 22)
                        .background(Capsule().fill(isOn ? Color.white : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .accessibilityValue(isOn ? "Selected" : "")
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }
}

/// An hour of the day, stepped one hour at a time and wrapping at midnight.
private struct PetHourStepper: View {
    let title: String
    @Binding var hour: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(DesignTokens.textSecondary)
            HStack(spacing: 0) {
                step("minus", by: -1)
                Text(String(format: "%02d:00", hour))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.textPrimary)
                    .frame(width: 44)
                step("plus", by: 1)
            }
            .frame(height: 22)
            .background(Capsule().fill(Color.white.opacity(0.08)))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(hour) o'clock")
    }

    private func step(_ symbol: String, by delta: Int) -> some View {
        Button { hour = (hour + delta + 24) % 24 } label: {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(DesignTokens.textPrimary)
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }
}

/// A slider drawn over a colour track: drag (or click) anywhere along it.
private struct PetColorSlider: View {
    @Binding var value: Double
    /// The track's colours, left to right.
    let stops: [Color]

    private static let height: CGFloat = 14
    private static let thumb: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            let travel = max(1, proxy.size.width - Self.thumb)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: stops, startPoint: .leading, endPoint: .trailing))
                    .frame(height: 8)
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 1))
                    .frame(width: Self.thumb, height: Self.thumb)
                    .offset(x: CGFloat(min(1, max(0, value))) * travel)
            }
            .frame(height: Self.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                value = Double(min(1, max(0, (drag.location.x - Self.thumb / 2) / travel)))
            })
        }
        .frame(height: Self.height)
        .accessibilityValue("\(Int((value * 100).rounded())) percent")
    }
}

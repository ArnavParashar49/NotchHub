import AppKit
import NotchHubCore
import SwiftUI

/// One app on the Lid page: a chosen one, or one that could be added. Built
/// by the app coordinator from NSWorkspace (`+LidAwake`); the view only draws.
struct LidAppRow: Identifiable {
    let bundleID: String
    let name: String
    let icon: NSImage?
    /// Running right now.
    let isOpen: Bool
    var id: String { bundleID }
}

/// The apps the Lid page shows: the chosen ones, and the running apps that
/// could be added.
struct LidAppChoices {
    var chosen: [LidAppRow] = []
    var candidates: [LidAppRow] = []
}

/// Settings → Lid: "Keep working with the lid closed".
///
/// A view of `LidSettingsModel` and nothing more: every tap is a `LidIntent`
/// handed to the app, which hands it to `LidAwakeController` — the switch
/// moves when the controller says the system did, never on the tap alone, so
/// it always shows what the Mac will really do when the lid closes.
/// Monochrome like the rest of the panel; the one warning line is the
/// design system's amber, because a closed Mac that never sleeps can cook
/// itself in a bag.
struct LidSettingsSection: View {
    let model: LidSettingsModel
    let apps: LidAppChoices
    let now: Date
    /// `true` only for headless snapshots: an image renderer cannot draw a
    /// menu, so its button is drawn bare.
    var headless = false
    let onIntent: (LidIntent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.groupSpacing) {
            group("Lid closed") {
                mainRow
                separator
                warningRow
                if let action = statusAction {
                    separator
                    LidActionRow(title: action.title, symbol: action.symbol, isEnabled: model.isEnabled(action.intent)) {
                        onIntent(action.intent)
                    }
                }
            }
            group("Safety") {
                switchRow(
                    "Only on the power adapter", symbol: "powerplug.fill",
                    caption: model.settings.onlyOnPower
                        ? "On battery your Mac sleeps as usual."
                        : "On battery it keeps working down to the floor below.",
                    isOn: model.settings.onlyOnPower, intent: .onlyOnPower(!model.settings.onlyOnPower)
                )
                separator
                floorRow
                separator
                autoOffRow
                separator
                switchRow(
                    "Keep after NotchHub quits", symbol: "rectangle.portrait.and.arrow.right",
                    caption: model.settings.keepAfterQuit
                        ? "Stays awake with no checks until NotchHub opens again."
                        : "Quitting NotchHub lets your Mac sleep again.",
                    isOn: model.settings.keepAfterQuit, intent: .keepAfterQuit(!model.settings.keepAfterQuit)
                )
            }
            group("Apps") {
                switchRow(
                    "Only while these apps are open", symbol: "app.badge.checkmark",
                    caption: "When none of them is open, your Mac sleeps as usual. An agent in a terminal counts through the terminal app.",
                    isOn: model.settings.onlyWhileApps, intent: .onlyWhileApps(!model.settings.onlyWhileApps)
                )
                ForEach(apps.chosen) { app in
                    separator
                    appRow(app)
                }
                separator
                addAppRow
            }
            group("Helper") {
                helperRow
            }
        }
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
            .padding(.leading, LidSettingsMetrics.textLeading)
    }

    private func rowIcon(_ symbol: String, lit: Bool) -> some View {
        Image(systemName: symbol)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(lit ? SettingsMetrics.ink : DesignTokens.textTertiary)
            .frame(width: LidSettingsMetrics.textLeading)
    }

    private func rowText(_ title: String, caption: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(LidSettingsMetrics.titleFont)
                .foregroundStyle(DesignTokens.textPrimary)
                .lineLimit(1)
            if let caption {
                Text(caption)
                    .font(LidSettingsMetrics.captionFont)
                    .foregroundStyle(DesignTokens.textTertiary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - The switch

    /// The feature's own switch, with what closing the lid does right now.
    private var mainRow: some View {
        let isOn = model.switchOn
        let enabled = model.isEnabled(.setEnabled(!isOn))
        return HStack(spacing: 10) {
            Image(systemName: "laptopcomputer")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isOn ? SettingsMetrics.ink : DesignTokens.textTertiary)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(isOn ? SettingsMetrics.onFill : 0.06))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("Keep working with the lid closed")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(DesignTokens.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(model.detail)
                    .font(LidSettingsMetrics.captionFont)
                    .foregroundStyle(DesignTokens.textTertiary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button { onIntent(.setEnabled(!isOn)) } label: {
                SwitchIndicator(isOn: isOn, tint: SettingsMetrics.ink)
            }
            .buttonStyle(PressStyle())
            .disabled(!enabled)
            .opacity(enabled ? 1 : LidSettingsMetrics.disabledOpacity)
            .accessibilityLabel("Keep working with the lid closed")
            .accessibilityValue(isOn ? "On" : "Off")
            .accessibilityHint(model.headline)
        }
        .padding(10)
    }

    private var warningRow: some View {
        HStack(alignment: .top, spacing: 0) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DesignTokens.warning)
                .frame(width: LidSettingsMetrics.textLeading)
                .padding(.top, 1)
            Text("A closed Mac that doesn't sleep can overheat in a bag and drain its battery. Don't pack it away while this is on.")
                .font(LidSettingsMetrics.captionFont)
                .foregroundStyle(DesignTokens.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.trailing, 12)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }

    /// The one button a status asks for, if any.
    private var statusAction: (title: String, symbol: String, intent: LidIntent)? {
        switch model.status {
        case .needsYou: return ("Resume…", "play.fill", .resume)
        case .outside, .stillOff: return ("Restore normal sleep…", "moon.zzz.fill", .restoreNormalSleep)
        default: return nil
        }
    }

    // MARK: - Safety

    private func switchRow(_ title: String, symbol: String, caption: String?, isOn: Bool, intent: LidIntent) -> some View {
        let enabled = model.isEnabled(intent)
        return HStack(spacing: 0) {
            rowIcon(symbol, lit: enabled && isOn)
            rowText(title, caption: caption)
            Spacer(minLength: 8)
            Button { onIntent(intent) } label: {
                SwitchIndicator(isOn: isOn, tint: SettingsMetrics.ink)
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel(title)
            .accessibilityValue(isOn ? "On" : "Off")
        }
        .padding(.trailing, 10)
        .padding(.vertical, 8)
        .frame(minHeight: LidSettingsMetrics.rowHeight)
        .opacity(enabled ? 1 : LidSettingsMetrics.disabledOpacity)
        .disabled(!enabled)
    }

    /// "Stop at 20 % battery": − / + in steps of 5, only without the
    /// adapter guard (with it, battery already means sleep).
    private var floorRow: some View {
        let floor = model.settings.batteryFloor
        let range = LidAwakeSettings.floorRange
        let step = LidAwakeSettings.floorStep
        let enabled = model.isEnabled(.batteryFloor(floor))
        return HStack(spacing: 0) {
            rowIcon("battery.25", lit: enabled)
            rowText("Stop at \(floor) % battery",
                    caption: model.settings.onlyOnPower ? "Used when “Only on the power adapter” is off." : "At or below it, your Mac sleeps as usual.")
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                StepButton(symbol: "minus", isEnabled: floor > range.lowerBound) { onIntent(.batteryFloor(floor - step)) }
                    .accessibilityLabel("Lower the battery floor")
                Text("\(floor) %")
                    .font(LidSettingsMetrics.valueFont)
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.textSecondary)
                    .frame(minWidth: 38)
                StepButton(symbol: "plus", isEnabled: floor < range.upperBound) { onIntent(.batteryFloor(floor + step)) }
                    .accessibilityLabel("Raise the battery floor")
            }
        }
        .padding(.trailing, 10)
        .padding(.vertical, 8)
        .frame(minHeight: LidSettingsMetrics.rowHeight)
        .opacity(enabled ? 1 : LidSettingsMetrics.disabledOpacity)
        .disabled(!enabled)
    }

    /// "Turn off after": Never, 1, 2, 4 or 8 hours.
    private var autoOffRow: some View {
        let hours = model.settings.autoOffHours
        let enabled = model.isEnabled(.autoOff(hours: hours))
        let choices: [Int?] = [nil] + LidAwakeSettings.autoOffChoices.map { Optional($0) }
        return HStack(spacing: 0) {
            rowIcon("timer", lit: enabled && hours != nil)
            rowText("Turn off after", caption: model.autoOffLine(now: now) ?? (hours == nil ? "Stays on until you turn it off." : "Counts from when it's turned on."))
            Spacer(minLength: 8)
            HStack(spacing: 3) {
                ForEach(choices, id: \.self) { choice in
                    let selected = choice == hours
                    Button { onIntent(.autoOff(hours: choice)) } label: {
                        Text(choice.map { "\($0) h" } ?? "Never")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(selected ? Color.black : DesignTokens.textSecondary)
                            .padding(.horizontal, 7)
                            .frame(height: 22)
                            .background(Capsule().fill(selected ? Color.white : Color.white.opacity(0.08)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressStyle())
                    .accessibilityLabel(choice.map { "Turn off after \($0) hours" } ?? "Never turn off by itself")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .padding(.trailing, 10)
        .padding(.vertical, 8)
        .frame(minHeight: LidSettingsMetrics.rowHeight)
        .opacity(enabled ? 1 : LidSettingsMetrics.disabledOpacity)
        .disabled(!enabled)
    }

    // MARK: - Apps

    private func appRow(_ app: LidAppRow) -> some View {
        let enabled = model.isEnabled(.removeApp(bundleID: app.bundleID))
        return HStack(spacing: 0) {
            SwiftUI.Group {
                if let icon = app.icon {
                    Image(nsImage: icon).resizable().interpolation(.high).frame(width: 18, height: 18)
                } else {
                    Image(systemName: "app.dashed").font(.system(size: 13)).foregroundStyle(DesignTokens.textTertiary)
                }
            }
            .frame(width: LidSettingsMetrics.textLeading)
            Text(app.name)
                .font(LidSettingsMetrics.titleFont)
                .foregroundStyle(DesignTokens.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(app.isOpen ? "Open" : "Not open")
                .font(LidSettingsMetrics.valueFont)
                .foregroundStyle(app.isOpen ? DesignTokens.textSecondary : DesignTokens.textTertiary)
                .padding(.trailing, 8)
            Button { onIntent(.removeApp(bundleID: app.bundleID)) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .contentShape(Circle())
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Remove \(app.name)")
        }
        .padding(.trailing, 10)
        .frame(height: LidSettingsMetrics.rowHeight)
        .opacity(enabled ? 1 : LidSettingsMetrics.disabledOpacity)
        .disabled(!enabled)
        .help(app.bundleID)
    }

    /// "Add app": the running apps, then one from /Applications.
    private var addAppRow: some View {
        let enabled = model.isEnabled(.chooseApp)
        let label = HStack(spacing: 0) {
            rowIcon("plus.circle.fill", lit: enabled)
            Text("Add app…")
                .font(LidSettingsMetrics.titleFont)
                .foregroundStyle(DesignTokens.textPrimary)
            Spacer(minLength: 8)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(Color.white.opacity(0.3))
        }
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, minHeight: LidSettingsMetrics.rowHeight, maxHeight: LidSettingsMetrics.rowHeight)
        .contentShape(Rectangle())

        return SwiftUI.Group {
            if headless {
                label
            } else {
                Menu {
                    if !apps.candidates.isEmpty {
                        Section("Open now") {
                            ForEach(apps.candidates) { app in
                                Button {
                                    onIntent(.addApp(bundleID: app.bundleID))
                                } label: {
                                    if let icon = app.icon {
                                        Label { Text(app.name) } icon: { Image(nsImage: Self.menuIcon(icon)) }
                                    } else {
                                        Text(app.name)
                                    }
                                }
                            }
                        }
                    }
                    Button("Choose from Applications…") { onIntent(.chooseApp) }
                } label: {
                    label
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }
        }
        .opacity(enabled ? 1 : LidSettingsMetrics.disabledOpacity)
        .disabled(!enabled)
        .accessibilityLabel("Add an app")
    }

    /// Menu items draw their image at its own size: a 16-pt copy.
    private static func menuIcon(_ icon: NSImage) -> NSImage {
        let copy = icon.copy() as? NSImage ?? icon
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }

    // MARK: - Helper

    private var helperRow: some View {
        let installed = model.helperInstalled && !model.helperRefused
        let intent: LidIntent = installed ? .removeHelper : .installHelper
        let enabled = model.isEnabled(intent)
        return HStack(alignment: .center, spacing: 0) {
            rowIcon("key.fill", lit: installed)
            rowText(
                "Password-free switching",
                caption: "One admin prompt adds a rule that lets NotchHub run only “pmset -a disablesleep 0 / 1” without asking, so it can put sleep back on its own. Remove deletes it."
            )
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 5) {
                Text(model.helperLabel)
                    .font(LidSettingsMetrics.valueFont)
                    .foregroundStyle(installed ? DesignTokens.textSecondary : DesignTokens.textTertiary)
                    .lineLimit(1)
                Button { onIntent(intent) } label: {
                    Text(installed ? "Remove…" : "Set Up…")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(installed ? DesignTokens.textPrimary : Color.black)
                        .padding(.horizontal, 11)
                        .frame(height: 22)
                        .background(Capsule().fill(installed ? Color.white.opacity(0.12) : Color.white))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .disabled(!enabled)
                .opacity(enabled ? 1 : LidSettingsMetrics.disabledOpacity)
            }
        }
        .padding(.trailing, 10)
        .padding(.vertical, 9)
    }
}

private enum LidSettingsMetrics {
    static let rowHeight: CGFloat = 36
    /// Where a row's title starts: the icon's column.
    static let textLeading: CGFloat = 38
    static let disabledOpacity: Double = 0.38
    static let titleFont = Font.system(size: 12, weight: .semibold, design: .rounded)
    static let captionFont = Font.system(size: 10, weight: .medium, design: .rounded)
    static let valueFont = Font.system(size: 11, weight: .medium, design: .rounded)
}

/// A small round − / + button.
private struct StepButton: View {
    let symbol: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(DesignTokens.textPrimary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.white.opacity(0.10)))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

/// A full-width row that is its own button (Resume…, Restore normal sleep…).
private struct LidActionRow: View {
    let title: String
    let symbol: String
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SettingsMetrics.ink)
                    .frame(width: LidSettingsMetrics.textLeading)
                Text(title)
                    .font(LidSettingsMetrics.titleFont)
                    .foregroundStyle(DesignTokens.textPrimary)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(Color.white.opacity(0.3))
            }
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, minHeight: LidSettingsMetrics.rowHeight, maxHeight: LidSettingsMetrics.rowHeight)
            .background(Color.white.opacity(isHovered && isEnabled ? 0.06 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .opacity(isEnabled ? 1 : LidSettingsMetrics.disabledOpacity)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

/// The features page's door to the Lid page: a full-width card (like the
/// weather's) with the switch's state in a few words and, while the Mac is
/// being kept awake, one small glyph. Outside its page the feature also has
/// the lid chip on the dashboard's quick-action bar (`DashboardLidChip`);
/// the compact island never changes for it.
struct LidSettingsCard: View {
    let model: LidSettingsModel
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "laptopcomputer")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(model.switchOn ? SettingsMetrics.ink : DesignTokens.textTertiary)
                    .frame(width: 30, height: 30)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(model.switchOn ? SettingsMetrics.onFill : 0.06))
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text("Lid Closed")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(DesignTokens.textPrimary)
                    Text(model.shortLabel)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(DesignTokens.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if model.isAwake {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(SettingsMetrics.ink)
                        .accessibilityLabel("Keeping your Mac awake")
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(Color.white.opacity(model.switchOn ? 1 : 0.3))
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: SettingsMetrics.cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(model.switchOn
                        ? (isHovered ? SettingsMetrics.onFillHovered : SettingsMetrics.onFill)
                        : (isHovered ? SettingsMetrics.offFillHovered : SettingsMetrics.offFill)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: SettingsMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(model.switchOn ? 0.22 : 0.06), lineWidth: 0.75)
            )
            .contentShape(RoundedRectangle(cornerRadius: SettingsMetrics.cornerRadius, style: .continuous))
        }
        .buttonStyle(PressStyle())
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .accessibilityLabel("Lid Closed: \(model.shortLabel)")
        .accessibilityHint("Opens the settings for keeping your Mac working with the lid closed")
    }
}

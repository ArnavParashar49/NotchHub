import NotchHubCore
import SwiftUI

/// The NEO section of Settings: the feature's own switch, and NEO.app's menu.
///
/// While the notch hosts NEO, NEO.app keeps no menu-bar item; what that menu
/// showed and did is here instead — whether NEO runs, the two permissions
/// macOS grants it, its chat, its keys, its logs, restart, erase, Open at
/// Login, quit. A view of `NeoSettingsModel` and nothing more: every tap is a
/// `NeoSettingsIntent` handed to the app, which alone decides what it means.
/// Rows whose control has nobody to act on it (NEO is off, or not running)
/// stay in place, dimmed, so the section never jumps around as NEO comes and
/// goes. Monochrome, like the rest of the panel.
struct NeoSettingsSection: View {
    let model: NeoSettingsModel
    /// The switch's side as the panel holds it (it moves on the tap, before
    /// the listener it starts or stops has caught up).
    let featureOn: Bool
    let onToggleFeature: () -> Void
    let onIntent: (NeoSettingsIntent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsMetrics.groupSpacing) {
            group("In the notch") {
                featureRow
            }
            group("Status") {
                statusRow(
                    symbol: "bolt.fill", title: "NEO", value: model.runningLabel, good: model.isRunning,
                    button: model.canStart ? ("Start NEO", .start) : nil
                )
                separator
                permissionRow(.accessibility, symbol: "figure.wave")
                separator
                permissionRow(.screenRecording, symbol: "rectangle.dashed.badge.record")
            }
            group("Actions") {
                actionRow("Open NEO chat", symbol: "bubble.left.fill", intent: .openChat, hint: model.hotkey)
                separator
                actionRow("API Keys…", symbol: "key.fill", intent: .apiKeys)
                separator
                actionRow("Open Logs", symbol: "doc.text.fill", intent: .openLogs)
                separator
                actionRow("Restart NEO", symbol: "arrow.clockwise", intent: .restart)
                separator
                actionRow("Erase NEO's Memory…", symbol: "trash.fill", intent: .eraseMemory, hint: "NEO asks first")
                separator
                loginRow
            }
            footer
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
            .padding(.leading, NeoSettingsMetrics.textLeading)
    }

    // MARK: - The feature's switch

    private var featureRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(featureOn ? SettingsMetrics.ink : DesignTokens.textTertiary)
                .frame(width: 30, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(featureOn ? SettingsMetrics.onFill : 0.06))
                )
            VStack(alignment: .leading, spacing: 1) {
                Text("NEO in the notch")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(DesignTokens.textPrimary)
                Text("Neo the fox and its chat in the notch")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(DesignTokens.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(action: onToggleFeature) {
                SwitchIndicator(isOn: featureOn, tint: SettingsMetrics.ink)
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("NEO in the notch")
            .accessibilityValue(featureOn ? "On" : "Off")
        }
        .padding(10)
    }

    // MARK: - Status

    private func permissionRow(_ permission: NeoPermission, symbol: String) -> some View {
        let state = model.permission(permission)
        return statusRow(
            symbol: symbol, title: permission.title, value: state.label, good: state == .allowed,
            button: state == .notAllowed ? ("Allow…", .openPermission(permission)) : nil
        )
    }

    private func statusRow(
        symbol: String, title: String, value: String, good: Bool, button: (title: String, intent: NeoSettingsIntent)?
    ) -> some View {
        HStack(spacing: 0) {
            rowIcon(symbol, lit: good)
            Text(title)
                .font(NeoSettingsMetrics.titleFont)
                .foregroundStyle(DesignTokens.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(value)
                .font(NeoSettingsMetrics.valueFont)
                .foregroundStyle(good ? DesignTokens.textSecondary : DesignTokens.textTertiary)
                .lineLimit(1)
            if let button {
                Button { onIntent(button.intent) } label: {
                    Text(button.title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 11)
                        .frame(height: 22)
                        .background(Capsule().fill(Color.white))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .padding(.leading, 8)
            }
        }
        .padding(.trailing, 10)
        .frame(height: NeoSettingsMetrics.rowHeight)
    }

    // MARK: - Actions

    private func actionRow(_ title: String, symbol: String, intent: NeoSettingsIntent, hint: String? = nil) -> some View {
        NeoActionRow(
            title: title, symbol: symbol, hint: hint, isEnabled: model.isEnabled(intent)
        ) { onIntent(intent) }
    }

    private var loginRow: some View {
        let isOn = model.openAtLogin ?? false
        let enabled = model.isEnabled(.openAtLogin(!isOn))
        return HStack(spacing: 0) {
            rowIcon("power", lit: enabled)
            Text("Open at Login")
                .font(NeoSettingsMetrics.titleFont)
                .foregroundStyle(DesignTokens.textPrimary)
            Spacer(minLength: 8)
            Button { onIntent(.openAtLogin(!isOn)) } label: {
                SwitchIndicator(isOn: isOn, tint: SettingsMetrics.ink)
            }
            .buttonStyle(PressStyle())
            .accessibilityLabel("Open NEO at Login")
            .accessibilityValue(isOn ? "On" : "Off")
        }
        .padding(.trailing, 10)
        .frame(height: NeoSettingsMetrics.rowHeight)
        .opacity(enabled ? 1 : NeoSettingsMetrics.disabledOpacity)
        .disabled(!enabled)
    }

    private func rowIcon(_ symbol: String, lit: Bool) -> some View {
        Image(systemName: symbol)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(lit ? SettingsMetrics.ink : DesignTokens.textTertiary)
            .frame(width: NeoSettingsMetrics.textLeading)
    }

    // MARK: - Footer

    private var footer: some View {
        let enabled = model.isEnabled(.quit)
        return HStack(spacing: 6) {
            Text(model.footnote)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            Button { onIntent(.quit) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "power")
                        .font(.system(size: 10, weight: .bold))
                    Text("Quit NEO")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(DesignTokens.live)
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background(Capsule().fill(DesignTokens.live.opacity(0.14)))
                .contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
            .opacity(enabled ? 1 : NeoSettingsMetrics.disabledOpacity)
            .disabled(!enabled)
        }
        .font(.system(size: 10, weight: .medium, design: .rounded))
        .foregroundStyle(DesignTokens.textTertiary)
        .padding(.horizontal, 4)
    }
}

private enum NeoSettingsMetrics {
    static let rowHeight: CGFloat = 36
    /// Where a row's title starts: the icon's column.
    static let textLeading: CGFloat = 38
    static let disabledOpacity: Double = 0.38
    static let titleFont = Font.system(size: 12, weight: .semibold, design: .rounded)
    static let valueFont = Font.system(size: 11, weight: .medium, design: .rounded)
}

/// One of NEO's actions: a full-width row that is its own button.
private struct NeoActionRow: View {
    let title: String
    let symbol: String
    var hint: String? = nil
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Image(systemName: symbol)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(SettingsMetrics.ink)
                    .frame(width: NeoSettingsMetrics.textLeading)
                Text(title)
                    .font(NeoSettingsMetrics.titleFont)
                    .foregroundStyle(DesignTokens.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let hint {
                    Text(hint)
                        .font(NeoSettingsMetrics.valueFont)
                        .foregroundStyle(DesignTokens.textTertiary)
                        .lineLimit(1)
                        .padding(.trailing, 8)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(Color.white.opacity(0.3))
            }
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, minHeight: NeoSettingsMetrics.rowHeight, maxHeight: NeoSettingsMetrics.rowHeight)
            .background(Color.white.opacity(isHovered && isEnabled ? 0.06 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .opacity(isEnabled ? 1 : NeoSettingsMetrics.disabledOpacity)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

import AppKit
import NotchHubCore

/// The menu-bar presence: a status item with the island's controls.
///
/// The app is an accessory (`LSUIElement`), so this is the only persistent
/// chrome it has — deliberately quiet.
final class StatusItemController {

    private let statusItem: NSStatusItem
    private let onShow: () -> Void
    private let onDemo: (ActivityKind) -> Void
    private let onToggleIdle: () -> Void
    private let onTray: () -> Void
    private let onDictate: () -> Void
    private let onSettings: () -> Void
    private let onTimer: () -> Void

    init(
        onShow: @escaping () -> Void,
        onDemo: @escaping (ActivityKind) -> Void,
        onToggleIdle: @escaping () -> Void,
        onTray: @escaping () -> Void,
        onDictate: @escaping () -> Void,
        onSettings: @escaping () -> Void,
        onTimer: @escaping () -> Void
    ) {
        self.onShow = onShow
        self.onDemo = onDemo
        self.onToggleIdle = onToggleIdle
        self.onTray = onTray
        self.onDictate = onDictate
        self.onSettings = onSettings
        self.onTimer = onTimer
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configure()
    }

    private func configure() {
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "capsule.fill",
                accessibilityDescription: "NotchHub"
            )
            button.image?.isTemplate = true
            button.toolTip = "NotchHub"
        }

        let menu = NSMenu()

        let show = NSMenuItem(title: "Show Island", action: #selector(showIsland), keyEquivalent: "s")
        show.target = self
        menu.addItem(show)

        menu.addItem(.separator())

        let tray = NSMenuItem(title: "Clipboard Tray", action: #selector(toggleTray), keyEquivalent: "v")
        tray.keyEquivalentModifierMask = [.option, .command]
        tray.target = self
        menu.addItem(tray)

        let dictate = NSMenuItem(title: "Start Dictation", action: #selector(toggleDictation), keyEquivalent: "m")
        dictate.keyEquivalentModifierMask = [.option, .command]
        dictate.target = self
        menu.addItem(dictate)

        let timer = NSMenuItem(title: "Start / Stop Timer", action: #selector(toggleTimer), keyEquivalent: "t")
        timer.keyEquivalentModifierMask = [.option, .command]
        timer.target = self
        menu.addItem(timer)

        menu.addItem(.separator())

        let demoHeader = NSMenuItem(title: "Preview Activity", action: nil, keyEquivalent: "")
        demoHeader.isEnabled = false
        menu.addItem(demoHeader)

        let demos: [(String, ActivityKind)] = [
            ("Now Playing", .music),
            ("Volume", .volume),
            ("Brightness", .brightness),
            ("Battery", .battery),
            ("Timer", .timer),
            ("Download", .download),
            ("AirPods", .airpods),
            ("Notification", .notification),
        ]
        for (title, kind) in demos {
            let item = NSMenuItem(title: title, action: #selector(runDemo(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = kind.rawValue
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let idle = NSMenuItem(title: "Return to Idle", action: #selector(toggleIdle), keyEquivalent: "i")
        idle.target = self
        menu.addItem(idle)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.keyEquivalentModifierMask = [.option, .command]
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit NotchHub", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func showIsland() { onShow() }

    @objc private func toggleTray() { onTray() }

    @objc private func toggleDictation() { onDictate() }

    @objc private func toggleTimer() { onTimer() }

    @objc private func openSettings() { onSettings() }

    @objc private func runDemo(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let kind = ActivityKind(rawValue: raw) else { return }
        onDemo(kind)
    }

    @objc private func toggleIdle() { onToggleIdle() }

    @objc private func quit() { NSApp.terminate(nil) }
}

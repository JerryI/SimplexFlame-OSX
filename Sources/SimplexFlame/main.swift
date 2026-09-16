import AppKit
import MetalKit

final class DesktopWindow: NSWindow {
    var presentsPomodoro = false
    override var canBecomeKey: Bool { presentsPomodoro }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let settings = Settings()
    var preview: NSWindow!
    var previewRenderer: FlameRenderer!
    var previewView: MTKView!
    var statusItem: NSStatusItem!
    var desktops: [(NSWindow, MTKView, FlameRenderer)] = []
    var wallpaperEnabled = false
    var displayAsleep = false
    var wallpaperButton: NSButton!
    var pauseButton: NSButton!
    var wallpaperMenuItem: NSMenuItem!
    var pauseMenuItem: NSMenuItem!
    var pomodoroMenuItems: [NSMenuItem] = []
    var pomodoro = PomodoroSession()
    var pomodoroTimer: Timer?
    var pomodoroOverlays: [PomodoroOverlay] = []
    var previewWasVisible = false
    var previousApplication: NSRunningApplication?
    var previousPresentationOptions: NSApplication.PresentationOptions = []
    var valueLabels: [Int: NSTextField] = [:]
    var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let defaults = UserDefaults.standard
            if defaults.object(forKey: "speed") != nil { settings.speed = defaults.float(forKey: "speed") }
            if defaults.object(forKey: "grain") != nil { settings.grain = defaults.float(forKey: "grain") }
            if defaults.object(forKey: "brightness") != nil { settings.brightness = defaults.float(forKey: "brightness") }
            previewRenderer = try FlameRenderer(settings: settings)
            buildMenu()
            buildPreview()
            observeSystem()
            showPreview()
        } catch {
            NSAlert(error: error).runModal()
            NSApp.terminate(nil)
        }
    }

    func buildMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Show Preview & Controls…", action: #selector(showPreview), keyEquivalent: ",").target = self
        let appPomodoro = appMenu.addItem(withTitle: "Pomodoro · 20 Minutes", action: #selector(togglePomodoro), keyEquivalent: "")
        appPomodoro.target = self
        pomodoroMenuItems.append(appPomodoro)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit SimplexFlame", action: #selector(quit), keyEquivalent: "q").target = self
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        NSApp.mainMenu = mainMenu

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "flame.fill", accessibilityDescription: "SimplexFlame")
        let menu = NSMenu()
        menu.addItem(withTitle: "SimplexFlame", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Show Preview & Controls…", action: #selector(showPreview), keyEquivalent: "").target = self
        wallpaperMenuItem = menu.addItem(withTitle: "Enable Wallpaper", action: #selector(toggleWallpaper), keyEquivalent: "")
        wallpaperMenuItem.target = self
        pauseMenuItem = menu.addItem(withTitle: "Pause Animation", action: #selector(togglePause), keyEquivalent: "")
        pauseMenuItem.target = self
        menu.addItem(.separator())
        let pomodoroMenuItem = menu.addItem(withTitle: "Pomodoro · 20 Minutes", action: #selector(togglePomodoro), keyEquivalent: "")
        pomodoroMenuItem.target = self
        pomodoroMenuItems.append(pomodoroMenuItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit SimplexFlame", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
    }

    func buildPreview() {
        preview = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 1060,height: 780), styleMask: [.titled,.closable,.miniaturizable,.resizable], backing: .buffered, defer: false)
        preview.title = "SimplexFlame"
        preview.subtitle = "Living gradients · Metal"
        preview.minSize = NSSize(width: 960,height: 540)
        preview.isReleasedWhenClosed = false
        preview.delegate = self
        preview.center()
        let root = preview.contentView!
        previewView = previewRenderer.makeView(frame: NSRect(x: 0,y: 112,width: 1060,height: 668))
        previewView.autoresizingMask = [.width,.height]
        root.addSubview(previewView)

        let bar = NSVisualEffectView(frame: NSRect(x: 0,y: 0,width: 1060,height: 112))
        bar.autoresizingMask = [.width]
        bar.material = .sidebar
        bar.blendingMode = .withinWindow
        root.addSubview(bar)

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 28
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: bar.leadingAnchor,constant: 24),
            stack.trailingAnchor.constraint(equalTo: bar.trailingAnchor,constant: -24),
            stack.topAnchor.constraint(equalTo: bar.topAnchor,constant: 18)
        ])
        let names = ["Flow speed", "Grain", "Brightness"]
        let values = [settings.speed, settings.grain, settings.brightness]
        for i in 0..<3 {
            let group = NSStackView()
            group.orientation = .vertical
            group.alignment = .leading
            group.spacing = 4
            let label = NSTextField(labelWithString: "\(names[i])  \(String(format: "%.2f", values[i]))")
            label.font = .systemFont(ofSize: 12,weight: .medium)
            valueLabels[i] = label
            group.addArrangedSubview(label)
            let slider = NSSlider(value: Double(values[i]), minValue: i == 2 ? 0.5 : 0, maxValue: i == 2 ? 1.5 : 2, target: self, action: #selector(sliderChanged(_:)))
            slider.tag = i
            slider.isContinuous = true
            slider.widthAnchor.constraint(equalToConstant: 150).isActive = true
            group.addArrangedSubview(slider)
            stack.addArrangedSubview(group)
        }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        stack.addArrangedSubview(spacer)
        pauseButton = NSButton(title: "Pause", target: self, action: #selector(togglePause))
        pauseButton.bezelStyle = .rounded
        stack.addArrangedSubview(pauseButton)
        wallpaperButton = NSButton(title: "Use as Wallpaper", target: self, action: #selector(toggleWallpaper))
        wallpaperButton.bezelStyle = .rounded
        stack.addArrangedSubview(wallpaperButton)
        let hint = NSTextField(labelWithString: "30 fps · Procedural color & grain · Use the flame in the menu bar to return or quit")
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 11)
        hint.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(hint)
        NSLayoutConstraint.activate([hint.leadingAnchor.constraint(equalTo: bar.leadingAnchor,constant: 24),hint.bottomAnchor.constraint(equalTo: bar.bottomAnchor,constant: -15)])
    }

    @objc func sliderChanged(_ sender: NSSlider) {
        let value = sender.floatValue
        let keys = ["speed","grain","brightness"]
        let names = ["Flow speed","Grain","Brightness"]
        switch sender.tag {
        case 0: settings.speed = value
        case 1: settings.grain = value
        default: settings.brightness = value
        }
        UserDefaults.standard.set(value, forKey: keys[sender.tag])
        valueLabels[sender.tag]?.stringValue = "\(names[sender.tag])  \(String(format: "%.2f",value))"
        updateRendering()
        if previewView.isPaused { previewView.draw() }
        for (_,view,_) in desktops where view.isPaused { view.draw() }
    }

    @objc func showPreview() {
        if pomodoro.isOnBreak { finishPomodoroBreak() }
        preview.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        previewRenderer.resize(previewView)
        updateRendering()
        if previewView.isPaused { previewView.draw() }
    }

    @objc func togglePause() {
        settings.paused.toggle()
        pauseButton.title = settings.paused ? "Resume" : "Pause"
        pauseMenuItem.title = settings.paused ? "Resume Animation" : "Pause Animation"
        updateRendering()
    }

    @objc func toggleWallpaper() {
        if pomodoro.isOnBreak { finishPomodoroBreak() }
        wallpaperEnabled.toggle()
        rebuildDesktops()
        wallpaperButton.title = wallpaperEnabled ? "Stop Wallpaper" : "Use as Wallpaper"
        wallpaperMenuItem.title = wallpaperEnabled ? "Disable Wallpaper" : "Enable Wallpaper"
        wallpaperMenuItem.state = wallpaperEnabled ? .on : .off
        if wallpaperEnabled { preview.orderOut(nil) }
        updateRendering()
    }

    func rebuildDesktops() {
        pomodoroOverlays.removeAll()
        for (window,view,_) in desktops { view.isPaused = true; window.close() }
        desktops.removeAll()
        guard wallpaperEnabled || pomodoro.isOnBreak else { return }
        do {
            for screen in NSScreen.screens {
                let renderer = try FlameRenderer(settings: settings)
                let window = DesktopWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
                window.isReleasedWhenClosed = false
                window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow))+1)
                window.collectionBehavior = [.canJoinAllSpaces,.stationary,.ignoresCycle]
                window.ignoresMouseEvents = true
                window.hasShadow = false
                window.isOpaque = true
                window.backgroundColor = .black
                window.hidesOnDeactivate = false
                let view = renderer.makeView(frame: NSRect(origin: .zero,size: screen.frame.size))
                view.autoresizingMask = [.width,.height]
                window.contentView = view
                window.setFrame(screen.frame,display: true)
                window.orderFrontRegardless()
                renderer.resize(view)
                desktops.append((window,view,renderer))
                if settings.paused || settings.speed == 0 { view.draw() }
            }
        } catch {
            if pomodoro.isActive { stopPomodoro() }
            wallpaperEnabled = false
            rebuildDesktops()
            NSAlert(error: error).runModal()
        }
        if pomodoro.isOnBreak { presentPomodoro() }
        updateRendering()
    }

    @objc func togglePomodoro() {
        if pomodoro.isActive { stopPomodoro(); return }
        pomodoro.start()
        for item in pomodoroMenuItems { item.state = .on }
        schedulePomodoroTimer()
    }

    func schedulePomodoroTimer() {
        pomodoroTimer?.invalidate()
        // A single wake-up after work; only the visible break ticks every second.
        let interval = pomodoro.isOnBreak ? 1 : TimeInterval(pomodoro.remainingSeconds())
        let timer = Timer(timeInterval: interval, repeats: pomodoro.isOnBreak) { [weak self] _ in self?.updatePomodoro() }
        timer.tolerance = 0.1
        pomodoroTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func startPomodoroBreak() {
        previewWasVisible = preview.isVisible
        previousApplication = NSWorkspace.shared.frontmostApplication
        previousPresentationOptions = NSApp.presentationOptions
        pomodoro.startBreak()
        preview.orderOut(nil)
        if desktops.isEmpty { rebuildDesktops() } else { presentPomodoro() }
        guard pomodoro.isActive else { return }
        schedulePomodoroTimer()
        updateRendering()
    }

    func presentPomodoro() {
        for overlay in pomodoroOverlays { overlay.removeFromSuperview() }
        pomodoroOverlays.removeAll()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.presentationOptions = [.autoHideDock, .autoHideMenuBar]
        for (window, view, _) in desktops {
            (window as? DesktopWindow)?.presentsPomodoro = true
            // Cover normal windows and the Dock, but allow the menu bar to reveal on hover.
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) - 1)
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.ignoresMouseEvents = false
            let overlay = PomodoroOverlay(frame: view.bounds)
            overlay.onInterrupt = { [weak self] in self?.finishPomodoroBreak() }
            overlay.update(seconds: pomodoro.remainingSeconds())
            view.addSubview(overlay)
            pomodoroOverlays.append(overlay)
            window.orderFrontRegardless()
            window.makeFirstResponder(overlay)
        }
        desktops.first?.0.makeKey()
    }

    func updatePomodoro() {
        guard pomodoro.isActive, !displayAsleep else { return }
        let remaining = pomodoro.remainingSeconds()
        if remaining == 0 {
            if pomodoro.isOnBreak { finishPomodoroBreak() } else { startPomodoroBreak() }
        } else if pomodoro.isOnBreak {
            for overlay in pomodoroOverlays { overlay.update(seconds: remaining) }
        }
    }

    func finishPomodoroBreak() {
        guard pomodoro.isOnBreak else { return }
        pomodoro.start()
        dismissPomodoro()
        schedulePomodoroTimer()
    }

    func stopPomodoro() {
        guard pomodoro.isActive else { return }
        pomodoroTimer?.invalidate()
        pomodoroTimer = nil
        let wasOnBreak = pomodoro.isOnBreak
        pomodoro.reset()
        for item in pomodoroMenuItems { item.state = .off }
        if wasOnBreak { dismissPomodoro() }
    }

    func dismissPomodoro() {
        for overlay in pomodoroOverlays { overlay.removeFromSuperview() }
        pomodoroOverlays.removeAll()
        NSApp.presentationOptions = previousPresentationOptions
        for (window, _, _) in desktops {
            window.resignKey()
            (window as? DesktopWindow)?.presentsPomodoro = false
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            window.ignoresMouseEvents = true
        }
        if !wallpaperEnabled { rebuildDesktops() }
        if previewWasVisible { preview.orderFront(nil) }
        if NSApp.isActive, previousApplication?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApplication?.activate(options: [])
        }
        previousApplication = nil
        updateRendering()
    }

    func updateRendering() {
        let pause = settings.paused || settings.speed == 0 || displayAsleep
        previewView?.isPaused = pause || !preview.isVisible || !preview.occlusionState.contains(.visible)
        for (_,view,_) in desktops { view.isPaused = pause }
    }

    func observeSystem() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification,object: nil,queue: .main) { [weak self] _ in
            self?.rebuildDesktops()
            if let self = self { self.previewRenderer.resize(self.previewView) }
        })
        for name in [NSWorkspace.screensDidSleepNotification,NSWorkspace.willSleepNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name,object: nil,queue: .main) { [weak self] _ in self?.displayAsleep = true; self?.updateRendering() })
        }
        for name in [NSWorkspace.screensDidWakeNotification,NSWorkspace.didWakeNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name,object: nil,queue: .main) { [weak self] _ in self?.displayAsleep = false; self?.updatePomodoro(); self?.updateRendering() })
        }
    }

    func windowDidResize(_ notification: Notification) { previewRenderer.resize(previewView) }
    func windowDidChangeBackingProperties(_ notification: Notification) { previewRenderer.resize(previewView) }
    func windowDidChangeOcclusionState(_ notification: Notification) { updateRendering() }
    func windowWillClose(_ notification: Notification) { previewView.isPaused = true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPreview()
        return true
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        pomodoroTimer?.invalidate()
        if pomodoro.isOnBreak { NSApp.presentationOptions = previousPresentationOptions }
    }
}

if let index = CommandLine.arguments.firstIndex(of: "--snapshot"), CommandLine.arguments.count > index+1 {
    do {
        let renderer = try FlameRenderer(settings: Settings(),reference: CommandLine.arguments.contains("--reference"))
        let time = CommandLine.arguments.count > index+2 ? Float(CommandLine.arguments[index+2]) ?? 0 : 0
        func dimension(_ flag: String, fallback: Int) -> Int {
            guard let i = CommandLine.arguments.firstIndex(of: flag), i+1 < CommandLine.arguments.count,
                  let value = Int(CommandLine.arguments[i+1]), value > 0, value <= 16384 else { return fallback }
            return value
        }
        try renderer.snapshot(path: CommandLine.arguments[index+1],time: time,
                              width: dimension("--width",fallback: 1512),height: dimension("--height",fallback: 1000))
    } catch { fputs("\(error)\n",stderr); exit(1) }
} else if CommandLine.arguments.contains("--benchmark") {
    do {
        try FlameRenderer(settings: Settings(),reference: CommandLine.arguments.contains("--reference")).benchmark()
    } catch { fputs("\(error)\n",stderr); exit(1) }
} else {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}

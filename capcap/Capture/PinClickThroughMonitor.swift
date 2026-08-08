import AppKit

/// Tracks pinned windows that currently ignore mouse events and installs a
/// key monitor so the user can leave click-through without being able to
/// click the pin chrome.
enum PinClickThroughCoordinator {
    private static var clickThroughWindows = NSHashTable<NSWindow>.weakObjects()
    private static var localMonitor: Any?
    private static var globalMonitor: Any?

    static var hasActiveClickThrough: Bool {
        !clickThroughWindows.allObjects.isEmpty
    }

    static func register(_ window: NSWindow) {
        clickThroughWindows.add(window)
        ensureMonitors()
    }

    static func unregister(_ window: NSWindow) {
        clickThroughWindows.remove(window)
        if clickThroughWindows.allObjects.isEmpty {
            removeMonitors()
        }
    }

    static func disableAll() {
        let windows = clickThroughWindows.allObjects
        for window in windows {
            if let pin = window as? PinWindow {
                pin.setClickThrough(false)
            } else {
                window.ignoresMouseEvents = false
                unregister(window)
            }
        }
        if !windows.isEmpty {
            ToastWindow.show(message: L10n.pinClickThroughOff)
        }
    }

    static func toggleAll() {
        if hasActiveClickThrough {
            disableAll()
        }
    }

    private static func ensureMonitors() {
        guard localMonitor == nil else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if matchesToggle(event) {
                disableAll()
                return nil
            }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if matchesToggle(event) {
                DispatchQueue.main.async {
                    disableAll()
                }
            }
        }
    }

    private static func removeMonitors() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }

    private static func matchesToggle(_ event: NSEvent) -> Bool {
        HotkeyManager.eventMatchesPinClickThroughHotkey(event)
    }
}

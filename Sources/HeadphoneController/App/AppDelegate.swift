import Cocoa
import SwiftUI
import Combine

public class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: MenuBarPanel!
    private var hostingView: NSHostingView<MainPopoverView>!
    private var globalClickMonitor: Any?
    private var localKeyMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private let manager = HeadphoneManager.shared
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPanel()
        setupBindings()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "headphones", accessibilityDescription: "Headphones")
            button.imagePosition = .imageLeading
            button.action = #selector(statusItemClicked(_:))
            button.target = self
        }
        updateStatusItem()
    }
    
    private func setupPanel() {
        let rootView = MainPopoverView(manager: manager)
        hostingView = NSHostingView(rootView: rootView)
        
        panel = MenuBarPanel(contentRect: NSRect(x: 0, y: 0, width: 330, height: 460))
        panel.contentView = hostingView
    }
    
    private func setupBindings() {
        manager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusItem()
            }
            .store(in: &cancellables)
    }
    
    private func updateStatusItem() {
        guard let button = statusItem.button else { return }
        
        let iconName = manager.menuBarIcon
        button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Headphones")
        
        if let active = manager.activeDevice, active.isConnected, let batt = active.batteryLevel {
            button.title = " \(batt)%"
        } else {
            button.title = ""
        }
    }
    
    @objc private func statusItemClicked(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        
        if panel.isVisible {
            closePanel()
        } else {
            showPanel(button: button)
        }
    }
    
    private func showPanel(button: NSStatusBarButton) {
        manager.refreshAll()
        
        guard let buttonWindow = button.window else { return }
        let buttonScreenFrame = buttonWindow.convertToScreen(button.bounds)
        let screen = buttonWindow.screen ?? NSScreen.main ?? NSScreen.screens.first!
        let visibleFrame = screen.visibleFrame
        
        // Measure dynamic height from SwiftUI view
        hostingView.layoutSubtreeIfNeeded()
        let fitting = hostingView.fittingSize
        let width: CGFloat = 330.0
        let height: CGFloat = max(360.0, fitting.height)
        
        // Calculate X: Center underneath status item, safely clamped inside screen edges
        var x = buttonScreenFrame.midX - (width / 2.0)
        let margin: CGFloat = 10.0
        
        if x + width > visibleFrame.maxX - margin {
            x = visibleFrame.maxX - width - margin
        }
        if x < visibleFrame.minX + margin {
            x = visibleFrame.minX + margin
        }
        
        // Calculate Y: Exactly 5 points below the menu bar bottom edge
        let y = buttonScreenFrame.minY - height - 5.0
        
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        
        // Highlight menu bar button like native macOS menus
        button.isHighlighted = true
        panel.orderFrontRegardless()
        panel.makeKey()
        
        setupMonitors()
    }
    
    private func closePanel() {
        panel.orderOut(nil)
        statusItem.button?.isHighlighted = false
        removeMonitors()
    }
    
    private func setupMonitors() {
        removeMonitors()
        
        // Dismiss when clicking anywhere outside the panel
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self = self else { return }
            let mouseLocation = NSEvent.mouseLocation
            if !self.panel.frame.contains(mouseLocation) {
                // If clicked on the status bar button itself, the button action handles toggling
                if let button = self.statusItem.button, let window = button.window {
                    let btnFrame = window.convertToScreen(button.bounds)
                    if btnFrame.contains(mouseLocation) {
                        return
                    }
                }
                self.closePanel()
            }
        }
        
        // Dismiss when pressing ESC
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { // ESC
                self?.closePanel()
                return nil
            }
            return event
        }
    }
    
    private func removeMonitors() {
        if let gcm = globalClickMonitor {
            NSEvent.removeMonitor(gcm)
            globalClickMonitor = nil
        }
        if let lkm = localKeyMonitor {
            NSEvent.removeMonitor(lkm)
            localKeyMonitor = nil
        }
    }
}

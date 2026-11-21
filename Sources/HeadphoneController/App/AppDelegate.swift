import Cocoa
import SwiftUI
import Combine

public class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var cancellables = Set<AnyCancellable>()
    private let manager = HeadphoneManager.shared
    
    public func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        setupBindings()
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "headphones", accessibilityDescription: "Headphones")
            button.imagePosition = .imageLeading
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        updateStatusItem()
    }
    
    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 330, height: 420)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MainPopoverView(manager: manager))
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
    
    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            manager.refreshAll()
        }
    }
}

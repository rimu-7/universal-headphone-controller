import Cocoa

if CommandLine.arguments.contains("--self-test") {
    exit(AppSelfTest.run())
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // Menu bar only app, no Dock icon
app.run()

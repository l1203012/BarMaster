import AppKit

// Agent app: no Dock icon, no main window. LSUIElement in Info.plist does the
// same for the bundled app; this keeps a bare `swiftc` binary consistent.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

import AppKit

/// "Connect Slack…": copies an app manifest for Slack's "create app" page and
/// asks for the two tokens that app gives you. They go to the Keychain.
@MainActor
enum SlackSetup {
    static func run(_ slack: Slack) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Connect Slack"
        alert.informativeText = """
            1. Click "Copy Manifest & Open Slack", choose Create New App → From a manifest, \
            pick your workspace and paste.
            2. Install it to the workspace, then copy the User OAuth Token (xoxp-…) from OAuth & Permissions.
            3. In Basic Information → App-Level Tokens, generate one with the connections:write scope (xapp-…).
            4. Paste both below.
            """
        let userField = NSSecureTextField(frame: NSRect(x: 0, y: 30, width: 320, height: 24))
        userField.placeholderString = "User OAuth Token (xoxp-…)"
        let appField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        appField.placeholderString = "App-Level Token (xapp-…)"
        let fields = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 54))
        fields.addSubview(userField)
        fields.addSubview(appField)
        alert.accessoryView = fields
        alert.addButton(withTitle: "Connect")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Copy Manifest & Open Slack")
        alert.window.initialFirstResponder = userField

        while true {
            switch alert.runModal() {
            case .alertThirdButtonReturn:
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(manifest, forType: .string)
                NSWorkspace.shared.open(URL(string: "https://api.slack.com/apps?new_app=1")!)
                continue
            case .alertFirstButtonReturn:
                let user = userField.stringValue.trimmingCharacters(in: .whitespaces)
                let app = appField.stringValue.trimmingCharacters(in: .whitespaces)
                guard user.hasPrefix("xoxp-"), app.hasPrefix("xapp-") else {
                    alert.informativeText = "The first token starts with xoxp-, the second with xapp-. " + alert.informativeText
                    continue
                }
                Keychain.set(Slack.userTokenAccount, user)
                Keychain.set(Slack.appTokenAccount, app)
                slack.connect()
            default:
                break
            }
            return
        }
    }

    static func disconnect(_ slack: Slack) {
        Keychain.set(Slack.userTokenAccount, nil)
        Keychain.set(Slack.appTokenAccount, nil)
        slack.disconnect()
    }

    /// A user-token app with Socket Mode, receiving the messages you can see.
    static let manifest = """
        {
          "display_information": {
            "name": "BarMaster",
            "description": "Touch Bar channel switcher and mentions",
            "background_color": "#1e8e4f"
          },
          "oauth_config": {
            "scopes": {
              "user": [
                "search:read", "users:read",
                "channels:read", "groups:read", "im:read", "mpim:read",
                "channels:history", "groups:history", "im:history", "mpim:history"
              ]
            }
          },
          "settings": {
            "event_subscriptions": {
              "user_events": ["message.channels", "message.groups", "message.im", "message.mpim"]
            },
            "socket_mode_enabled": true,
            "org_deploy_enabled": false,
            "token_rotation_enabled": false
          }
        }
        """
}

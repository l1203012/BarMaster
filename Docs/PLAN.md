# BarMaster — Plan

A tiny native macOS menu-bar app that gives the Touch Bar real controls for
**Google Chrome**, **Slack** and **Ghostty**: switch tabs, close tabs, open new
ones, jump to your latest Slack mention, and so on. It should use close to no
resources while idle. It is built in Swift with the Whiteprint toolchain
(SwiftPM + plain `swiftc` build scripts, macOS 13+, Command Line Tools only)
and has a green theme.

Target machine: MacBookPro14,3 (15" 2017, Touch Bar, **no physical Esc key**),
macOS 13.7. Installed: Chrome 154, Slack 4.49, Ghostty 1.3.1.

---

## 1. How the Touch Bar can be taken over correctly

The public `NSTouchBar` API only shows a bar while **your own app** is
frontmost. When Chrome is active, Chrome owns the bar. A public-API-only app
cannot do what we want.

Every tool that does this (BetterTouchTool, MTMR, Pock, Touch Bär) uses the
private **DFRFoundation** framework
(`/System/Library/PrivateFrameworks/DFRFoundation.framework`, present on this Mac):

| Private API | Purpose |
|---|---|
| `+[NSTouchBar presentSystemModalTouchBar:systemTrayItemIdentifier:]` | Show our bar on top of whatever app is frontmost |
| `+[NSTouchBar dismissSystemModalTouchBar:]` / `minimizeSystemModalTouchBar:` | Hide it and give the bar back to the app |
| `+[NSTouchBarItem addSystemTrayItem:]` | Put a BarMaster button in the Control Strip |
| `DFRElementSetControlStripPresenceForIdentifier(id, true)` | Make that Control Strip button visible |
| `DFRSystemModalShowsCloseBoxWhenFrontMost(false)` | Hide the system "×" close box |

`Sources/BarMasterApp/SystemTouchBar.swift` resolves these at runtime with
`dlopen`/`dlsym` and `class_getClassMethod`. It needs no bridging header and no
private-framework linking, and a missing symbol just disables the Touch Bar
features instead of crashing. **Consequence:** no Mac App Store. That's fine for a
personal tool shipped as a DMG, like Whiteprint.

### Behaviour

1. BarMaster runs as an agent app (`LSUIElement = YES`): no Dock icon, just a
   green bottle in the menu bar plus a Control Strip button.
2. It listens for `NSWorkspace.didActivateApplicationNotification`. This is
   **event-driven, with no polling or timers**.
3. When Chrome, Slack or Ghostty becomes frontmost, BarMaster presents that
   app's bar as a system-modal Touch Bar. When any other app becomes frontmost,
   it dismisses its bar and the app's own Touch Bar comes back.
4. Tapping the Control Strip bottle toggles the BarMaster bar by hand, for
   example to see the app's own bar for a moment.
5. **Every layout starts with an Esc button.** System-modal bars cover the
   virtual Esc key, and this MacBook has no physical one. The button posts a
   real Esc key event.

---

## 2. Talking to each app (cheapest correct way)

The rule: prefer **Apple Events (AppleScript)**, which is structured and exact
and needs no focus tricks. Fall back to **synthesized keystrokes (`CGEvent`)**
only when an app has no scripting dictionary.

### Google Chrome: Apple Events

Chrome has a full scripting dictionary.

| Button | Implementation |
|---|---|
| ◀ / ▶ tab | `set active tab index of front window to (n ± 1)` (wraps around) |
| Tab strip (scrubber of tab titles) | `get title of every tab of front window` → `NSScrubber`; tap → `set active tab index` |
| Close tab | `close active tab of front window` |
| New tab | `make new tab at end of tabs of front window` |
| Reopen closed tab | keystroke ⌘⇧T (no AppleScript equivalent) |
| Back / Forward / Reload | `go back` / `go forward` / `reload` on `active tab` |

### Ghostty: AppleScript (Ghostty ≥ 1.3, on by default)

Object model: application → windows → tabs → terminals
([docs](https://ghostty.org/docs/features/applescript), `Ghostty.sdef`).

| Button | Implementation |
|---|---|
| ◀ / ▶ tab | read `selected tab` / `index` of front window, then `select tab (tab n of front window)` |
| Tab strip | `name of every tab of front window` → scrubber |
| Close tab | `close tab (selected tab of front window)` |
| New tab | `new tab in front window` |
| Split right / down | `send key "d" modifiers "command"` / `"command,shift"` to focused terminal (default keybinds) |
| Clear | `send key "k" modifiers "command"` |

If someone sets `macos-applescript = false`, fall back to keystrokes
(⌘⇧[ / ⌘⇧] / ⌘W / ⌘T).

### Slack: keystrokes, plus the Web API for "latest mention"

Slack (Electron) has no scripting dictionary, so this is done in two parts:

| Button | Implementation |
|---|---|
| **@ Latest mention** | **v1:** ⌘⇧M (opens Activity → Mentions; the newest is on top). **v2:** on tap, call Slack Web API `search.messages` with query `<@MY_USER_ID>`, `sort=timestamp`, `count=1`, then `open` its `permalink`. Slack desktop opens it straight on the message. |
| Next / previous unread channel | ⌥⇧↓ / ⌥⇧↑ |
| All unreads | ⌘⇧A |
| Threads | ⌘⇧T |
| Jump to… | ⌘K |
| Back / Forward | ⌘[ / ⌘] |
| Mark channel read | Esc |

The v2 Slack token (a user token with `search:read`) is stored in the
**Keychain**, never in defaults. It is called **only on tap**, never polled.

### Keystroke delivery

Use `CGEvent(keyboardEventSource:virtualKey:keyDown:)` with flags, posted to
the target with `postToPid(_:)` so focus is never stolen. This needs the
**Accessibility** permission once.

---

## 3. Resource budget (the "barely uses resources" promise)

| Rule | Why |
|---|---|
| Pure **AppKit**, no SwiftUI or Combine in the hot path, no Electron, no web views | Smallest memory footprint and fastest launch |
| **Zero timers and zero polling.** All work comes from app activation notifications or button taps | 0% CPU at idle; the app sleeps and lets App Nap help |
| Tab titles are refreshed only (a) when the app activates and (b) right after a BarMaster action. Otherwise the scrubber has a ↻ button | No per-second Apple Events. Optional later: listen for Chrome's window-title change through the AX observer (`kAXTitleChangedNotification`), which is still event-driven |
| Apple Events run on one background serial queue with a 1 s timeout. Scripts are compiled once with `NSAppleScript` and cached, or sent as raw `NSAppleEventDescriptor` | Main thread never blocks; no recompiling each tap |
| Touch Bar items are built once per app and reused. Only the scrubber's data source changes | No view churn |
| No networking except the optional on-tap Slack call | — |
| **Targets:** idle CPU 0.0%, RSS < 35 MB (measured 31 MB with all bars), binary < 2 MB | Check with Activity Monitor and `footprint BarMaster` |

---

## 4. Permissions and signing

- `Info.plist`: `LSUIElement`, `NSAppleEventsUsageDescription`
  ("BarMaster controls Chrome and Ghostty tabs from your Touch Bar").
- **Automation** prompts (Chrome, Ghostty) appear on first use, are granted per
  app, and can be checked with `AEDeterminePermissionToAutomateTarget`.
- **Accessibility** (for keystrokes): check `AXIsProcessTrustedWithOptions` on
  launch. A green onboarding window explains both permissions and has buttons
  that deep-link to System Settings.
- **Signing gotcha:** macOS ties these grants to the code signature. Ad-hoc
  (`-`) signing gives a new identity on every rebuild, so permissions get
  re-prompted. Make a self-signed "BarMaster Dev" code-signing certificate once
  and set `SIGN_IDENTITY` in `Scripts/build.sh`, as Whiteprint does.
- Not sandboxed; Developer ID + notarization only if it is ever distributed.

---

## 5. Look and feel: green

- Accent / theme color: bottle green (`#1E8E4F` light, `#2FBF6B` dark) defined
  once in `Theme.swift`. Touch Bar buttons use `bezelColor` set to the theme
  green for primary actions (e.g. **@ Mention**, **New tab**) and default grey
  for the rest.
- The settings / onboarding window has a green gradient header, the app icon,
  and simple AppKit controls. It stays deliberately minimal.
- Icon: a whisky bottle on a green macOS-style squircle (being generated into
  `Resources/App/`, script in `Scripts/make_logo.*`). The menu bar uses a
  template bottle glyph.

---

## 6. Project layout (mirrors Whiteprint)

```
BarMaster/
├── Package.swift                 // swift-tools 5.8, macOS 13
├── Sources/
│   ├── BarMasterCore/            // no AppKit: layouts, key codes, AppleScript strings, config model (unit-testable)
│   └── BarMasterApp/
│       ├── main.swift / AppDelegate.swift
│       ├── FrontmostAppWatcher.swift     // NSWorkspace activation → layout switch
│       ├── SystemTouchBar.swift          // present/dismiss/control-strip wrapper
│       ├── Layouts/ChromeBar.swift, SlackBar.swift, GhosttyBar.swift, CommonItems.swift (Esc)
│       ├── Drivers/AppleEventDriver.swift, KeystrokeDriver.swift, SlackAPI.swift
│       ├── Permissions.swift
│       ├── Theme.swift
│       └── UI/StatusItem.swift, SettingsWindow.swift, Onboarding.swift
├── Tests/BarMasterCoreTests/
├── Resources/Info.plist, Resources/App/AppIcon.icns, MenuBarIcon*.png
├── Scripts/build.sh (app / dmg), targets.sh, test.sh, make_logo.*
└── Docs/PLAN.md
```

Config lives in `UserDefaults`: which apps are enabled, button order, and
whether to auto-present or require a Control Strip tap. A JSON layout file can
come later if needed.

---

## 7. Milestones

1. ✅ **Skeleton:** Package, build script producing `.build/BarMaster.app`, agent
   app with a green status item and Quit. *Check: launches, RSS < 20 MB.*
2. ✅ **Private Touch Bar spike:** Control Strip bottle plus a system-modal bar
   with Esc + "Hello", shown over any app. *This is the riskiest step, so do it
   first.*
3. ✅ **App switching:** activation watcher auto-presents and dismisses per
   bundle ID (`com.google.Chrome`, `com.tinyspeck.slackmacgap`,
   `com.mitchellh.ghostty`).
4. 🔨 **Chrome bar:** Apple Events driver, tab ◀ ▶, close, new, back/forward,
   tab scrubber.
5. 🔨 **Ghostty bar:** same through the Ghostty dictionary, plus split buttons.
6. 🔨 **Slack bar (v1):** keystroke driver plus Accessibility onboarding;
   @ Mention (⌘⇧M), unread ↑↓, All unreads, Threads, Jump.
7. **Settings + onboarding window** (green), launch at login with
   `SMAppService.mainApp`.
8. **Slack v2:** Keychain token and on-tap `search.messages` → permalink.
9. **Polish:** stable signing, DMG, README, resource check
   (`footprint`, Instruments idle trace).

## 7b. Added along the way

- **Dialogs get through.** An Accessibility observer on the frontmost app
  notices sheets and dialogs (e.g. Ghostty's "Close tab?"). BarMaster steps
  aside so the dialog's own Touch Bar buttons can be tapped, then comes back
  when the dialog closes.
- **Live tab strip.** Tab switches made outside BarMaster update the strip.
  Chrome's window title follows the active tab; each Ghostty tab is its own
  window, so a focus change marks a Ghostty switch. Both are event-driven.
- **Git status on the Ghostty bar.** Shows `branch · commit count` for the
  focused terminal's directory. The directory comes from the window's proxy
  icon over Accessibility. A kqueue watch on `.git/logs/HEAD` updates it after
  commits and checkouts, with no polling.
- **Brightness and volume** sit behind one popover button to make room.
- **Install & signing:** `Scripts/build.sh install` puts the app in
  /Applications. `Scripts/make-dev-cert.sh` creates the stable signing
  identity, and the menu has an **Open at Login** toggle.

## 8. Risks

- **Private API breakage.** DFRFoundation has been stable since 10.14, and
  Touch Bar Macs top out at macOS 13–15, so the risk is low. Keep it all behind
  `SystemTouchBar.swift`.
- **Slack shortcut changes.** Keep the key map in `BarMasterCore` so it is a
  one-line fix.
- **Apple Event latency** of about 20–50 ms per call is fine for taps. Never
  call it in a loop.
- **The system-modal bar hides the app's own bar.** That is intentional. The
  Control Strip toggle is the escape hatch.
- **The system × close box** shows whenever the bar shares the Touch Bar with
  the Control Strip, even with `DFRSystemModalShowsCloseBoxWhenFrontMost(false)`.
  BarMaster now presents full width (`placement: 1`, as MTMR does) to drop it.
  Every bar therefore carries its own brightness, volume and mute keys (posted
  as media keys, so macOS shows its usual HUD) and a bottle that hands the
  Touch Bar back.

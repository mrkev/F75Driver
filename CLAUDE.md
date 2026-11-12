# F75 Driver

A native macOS app for configuring the EPOMAKER x AULA F75 keyboard. It is
a status and settings app that talks USB HID, not a kernel driver. SwiftUI,
IOKit, no third-party code, no daemon.

Read `docs/PROTOCOL.md` before touching anything that talks to the
keyboard. It records what is known, how each fact was established, and
what is still open.

## Safety rules for hardware

A bad write can brick the keyboard. The reference project reports an F75
bricked by writing settings over the dongle.

- **Dongle is read-only.** Never send a write over the 2.4 GHz dongle.
- **Cable writes are read-modify-write-verify.** Read the current page,
  change the fewest bytes possible, write, read back and compare. Never
  build a page from constants.
- **Guard every write.** `F75Protocol.wiredSettingsWrite` refuses a page
  that differs outside the lighting bytes. A new writable field means
  widening that guard on purpose, with a test.
- **Never send factory reset** (`11` on cable, `06` on dongle) or any
  command not documented in `docs/PROTOCOL.md`.
- **Ask the owner before the first write of any new kind.** State what
  will be sent and what the keyboard should do, and have them confirm the
  result on the physical keyboard.
- **Do not copy a settings page between transports.** Byte 14 differs.

## Layout

| Path | Role |
|---|---|
| `F75Driver/Protocol/F75Protocol.swift` | Pure protocol: request bytes, reply parsing, settings page model, write guard. Foundation only. |
| `F75Driver/HID/HIDTransport.swift` | IOKit HID: finds the two interfaces, opens them, moves raw reports. |
| `F75Driver/KeyboardMonitor.swift` | `@Observable` state: permission, connections, periodic reads, the lighting write. |
| `F75Driver/ContentView.swift` | Status window, permission prompt, lighting controls. |
| `F75Driver/StatusMenu.swift` | Menu bar item and its menu, in AppKit (`NSStatusItem`) so the header row can be a custom view. |
| `F75Driver/F75DriverApp.swift` | Window scene and app delegate. The status item is made in `applicationDidFinishLaunching`; making it in `App.init()` crashes. |
| `F75DriverTests/F75DriverTests.swift` | Swift Testing suites for the protocol layer. |
| `Scripts/test-protocol.sh` | Runs those tests without Xcode. |
| `Scripts/make-icon.swift` | Draws the app icon and writes every size into the asset catalog. Run from the repo root. |

Keep the protocol file free of IOKit and SwiftUI so the test script keeps working.

## Build and test

Build:

```bash
xcodebuild -project F75Driver.xcodeproj -scheme F75Driver -configuration Debug build
```

Protocol tests:

```bash
./Scripts/test-protocol.sh
```

Do not rely on `xcodebuild test`. The unit tests are hosted in the app,
and from the command line the run stalled after "Testing started" every
time it was tried; the cause was never found. The script copies the
protocol file and the tests into a throwaway Swift package instead.

Project facts: Xcode 26, file-system-synchronised groups (new files under
`F75Driver/` are picked up automatically), Swift 5 language mode with
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so types are main-actor
unless marked `nonisolated`. The app is sandboxed with the USB entitlement
(`ENABLE_RESOURCE_ACCESS_USB`).

## Running against the keyboard

- **Input Monitoring is required** for both the cable and the dongle
  interface. Without it `IOHIDDeviceOpen` fails, and calling it on the
  main thread blocks until the system prompt is answered. That is why
  `HIDTransport.mayOpenDevices` exists and why `IOHIDRequestAccess` runs
  off the main thread.
- **The grant only takes effect after relaunching the app.**
- **A command-line probe cannot open the keyboard.** Permission belongs to
  the app bundle, so hardware checks go through the running app. Its "Raw
  data" disclosure shows the bytes of every reply.
- **The mode switch matters.** The cable interface only exists with the
  switch on USB. On 2.4G the cable just charges.
- **The keyboard sleeps**, possibly after one minute, and then ignores the
  dongle until a key is pressed. `KeyboardMonitor.lastBattery` keeps the
  last reading for the menu bar.
- `monitor.start()` is skipped under XCTest so tests never touch hardware.

## Status

Done and verified on a real F75:

- Read model, battery and settings page over cable and dongle.
- Menu bar battery percentage, refreshed every minute.
- Menu header in the style of the system battery menu (model, level,
  connection, power), lighting submenu over the cable, Open at Login.
  Lighting from the menu has not yet been exercised on hardware.
- Power state: on battery, charging, plugged in and not charging.
- Lighting over the cable: effect, brightness, speed. Only "Fixed on" and
  brightness changes were exercised on hardware.

Not built, roughly in the order discussed with the owner:

- Colour selection per effect (cable command `0A`, see the protocol doc).
- Custom per-key lighting.
- Key remapping and macros.
- Other settings writes: sleep timer, polling rate, Win lock, Mac layout.
- Menu-bar-only mode (no Dock icon, no window at launch).

## Conventions

- Credit any outside source in `ACKNOWLEDGEMENTS.md`. Do not copy code
  from aula-f75-mac-driver: it has no licence.
- The vendor's script is not stored here. Re-download it when needed.
- When something is learned from the keyboard, record it in
  `docs/PROTOCOL.md` with its confidence level, and resolve or add to the
  open questions there.

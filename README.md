# A50 Dock Switch — macOS (native)

Native Swift port of [a50-dock-switch](https://github.com/bboymain/a50-dock-switch): menu bar app that watches your Astro A50 Gen 4 dock state over USB HID and automatically switches the default audio output — docked → speakers, undocked → headphones. No Python, no wrapper.

## Status

MVP: dock/undock auto-switching, battery in the menu bar, manual override, device routing config, notifications.

Not yet ported: EQ/sidetone/mic controls, dashboard window, volume memory, update checks.

## Requirements

- macOS 14+
- Xcode 26 (or any toolchain with the macOS SDK)
- Astro A50 Gen 4 base station connected over USB

## Build & run

```sh
./scripts/build_app.sh
open A50DockSwitch.app
```

## a50probe — protocol diagnostics

Same idea as `probe.py` in the Windows repo. Run this first if switching doesn't work:

```sh
swift build
.build/debug/a50probe            # list interfaces + 5 snapshots, 2s apart
.build/debug/a50probe --list     # HID interfaces only (usage page/usage/openable)
.build/debug/a50probe --cmd 0x54 # raw dump: headset status
.build/debug/a50probe --cmd 0x7C # raw dump: battery
```

## How it works

- **HID** — `Sources/A50HID/AstroHID.swift` talks to VID `0x9886` / PID `0x002C` with IOKit, using the same framing as the hyperheadset Python client: `[0x02, cmd, len, payload...]` as feature reports, reading `0x54` (docked/on) and `0x7C` (battery).
- **Audio switching** — `Sources/A50DockSwitch/AudioDevices.swift` lists output devices and sets `kAudioHardwarePropertyDefaultOutputDevice` via CoreAudio.
- **Polling/debounce** — `Sources/A50DockSwitch/AppState.swift`: polls every 0.5s, acts on the configured interval, debounce frames like the Windows app before switching.
- **Config** — `~/Library/Application Support/A50DockSwitch/config.json`.

## Known caveats

- Astro Command Center (if running on macOS) may hold the vendor HID interface exclusively — same conflict as Windows.
- macOS exposes several HID interfaces for the base station; the client picks the first openable one. If reads fail once hardware is connected, check `a50probe --list` and we'll pin the exact usage page/usage.
- App is unsigned — Gatekeeper may complain when distributing; local `open` is fine.

## Credits

- [a50-dock-switch](https://github.com/bboymain/a50-dock-switch) by [@mainlek](https://x.com/mainlek)
- [hyperheadset](https://github.com/HyperRaccoon13/HyperHeadset), [eh-fifty](https://github.com/tdryer/eh-fifty) — protocol research

MIT.

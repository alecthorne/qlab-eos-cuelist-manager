# QLab Eos Cuelist Manager

A macOS app that keeps one ETC Eos cue list in sync with the numbered cues of a QLab cue list.
QLab is always the source of truth: Eos is made to match it, including cue labels.

Runs on the same Mac as QLab and talks to both over OSC. Requires macOS 13 or later.

## Status

| Step | What | State |
| --- | --- | --- |
| 1 | App skeleton, settings, OSC connections to QLab and Eos | Done |
| 2 | Side-by-side view with mismatches flagged, live active Eos cue | This branch |
| 3 | Add, edit and delete Eos cues, each change approved by you, with a 500-line action log | Planned |
| 4 | Unit tests for the matching logic, and a test checklist for Eos Nomad and QLab | Planned |

The app reads only so far. Nothing is sent to Eos that changes the show.

## The Compare view

Every numbered cue in the chosen QLab cue list is lined up with the Eos cue of the same number
(1, 1.0 and 01 all count as cue 1). Each row gets one status:

| Status | Meaning | What step 3 will offer |
| --- | --- | --- |
| Matches | Same number, and the Eos label equals the QLab name | Nothing |
| Label differs | Cue exists in both, label is different | Update the Eos label |
| Missing in Eos | QLab has the number, Eos doesn't | Add the cue in Eos |
| Not in QLab | Eos has the number, QLab doesn't | Delete the cue in Eos |
| Not an Eos number | QLab number like "1A" or "Pre" that Eos can't use | Nothing: renumber it in QLab |
| Duplicate number | Two QLab cues map to the same Eos number | Nothing: fix it in QLab |

The QLab name used is the one shown in QLab's cue list, so a cue with no name uses QLab's default
name. Eos cue parts are not compared. Eos numbers may have up to 4 decimal places.
The "Eos cue list" and "QLab cues" tabs show each side on its own.

## Build and run

1. Install Xcode 15 or later.
2. Open `Package.swift` in Xcode (File > Open, or `open Package.swift`).
3. Choose the **QLabEosCuelistManager** scheme and **My Mac**, then Run.

Or from Terminal: `swift run QLabEosCuelistManager`. Tests: `swift test`.

On macOS 15 and later, macOS asks for permission to find devices on local networks the first time
the app connects to Eos. Allow it, or the Eos connection fails.

## Settings

- **QLab workspace**: if only one workspace is open, it is used automatically. Otherwise choose one.
- **QLab passcode**: only if the workspace has OSC passcodes set.
- **QLab cue list**: every numbered cue in this list (including inside groups) is synced.
- **Eos console IP address** and **network interface**: choose the interface that is on the Eos network.
  "Automatic" lets macOS pick using its routing table.
- **Protocol**: OSC 1.1 on TCP port 3037 (default), or OSC 1.0 on TCP port 3032.
- **Eos cue list to sync**: required. There is deliberately no default.

## Setting up Eos

In the Eos Shell or Setup > System > Show Control > OSC, turn on **OSC RX** and **OSC TX**.
The app connects over TCP, so the UDP ports and IP address fields there don't matter for it.
It works with Eos Nomad too, which is the easiest way to test without a console.

## Setting up QLab

In Workspace Settings > Network > OSC Access, make sure the passcode you use (or "no passcode")
has at least View access for reading cues. Step 1 needs nothing else, because only Eos is changed later.

## How it talks to each side

- **QLab**: TCP to `127.0.0.1:53000` with SLIP framing. Sends `/workspaces`,
  `/workspace/{id}/connect`, `/workspace/{id}/updates 1` and `/workspace/{id}/cueLists`,
  and re-reads cue lists when QLab sends `/update/...` messages.
- **Eos**: TCP to the console on the chosen interface. Sends `/eos/subscribe 1`,
  `/eos/get/cue/{list}/count` and `/eos/get/cue/{list}/index/{n}`, re-reads the list when
  Eos sends `/eos/out/notify/cue/{list}/...`, and shows `/eos/out/active/cue/...`.
  It pings every 5 seconds and reconnects after 15 seconds of silence.

## Code layout

- `Sources/CueSyncCore`: OSC encoding and decoding, TCP framing, and parsing of QLab and Eos
  messages. Foundation only, covered by unit tests.
- `Sources/QLabEosCuelistManager`: the SwiftUI app, settings and Network.framework connections.
- `Tests/CueSyncCoreTests`: unit tests, run on GitHub Actions (macOS) for every pull request.

## References

- [Eos OSC dictionary](https://www.etcconnect.com/WebDocs/Controls/EosFamilyOnlineHelp/en/Content/22_Show_Control/08_OSC/OSC_Dictionary.htm)
- [QLab 5 OSC dictionary](https://qlab.app/docs/v5/scripting/osc-dictionary-v5/)

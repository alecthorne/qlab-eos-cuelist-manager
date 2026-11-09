# Test checklist: Eos Nomad and QLab

Run this on the Mac that runs QLab, with Eos Nomad on the same Mac or another computer
on the Eos network. Work through it in order; each section builds on the one before.
Tick each box, and note anything that fails with what the connection log or action log says.

Automated tests (`swift test`) cover OSC encoding, framing, message parsing, cue number rules,
the comparison and the commands built for each change. This checklist covers what they can't:
the real QLab and Eos.

## 0. Setup

- [ ] Eos Nomad running with a new, empty show. In Setup > System > Show Control > OSC, **OSC RX** and **OSC TX** on.
- [ ] In Nomad, create cue list **5** (any number other than 1 is a good test that the app doesn't assume 1).
- [ ] QLab 5 open with a test workspace. In Workspace Settings > Network > OSC Access, no passcode with full access (or note the passcode).
- [ ] In QLab, a cue list called "Lights" with these cues (any cue type; Memo cues are fine):

  | Number | Name |
  | --- | --- |
  | 1 | Preset |
  | 2 | Scene 1 |
  | 2.5 | Scene 1 tweak |
  | 3 | (leave empty, so QLab's default name is used) |
  | 4A | Bad number |
  | 6 | Six |
  | 6.0 | Also six |

  Put cue 2.5 inside a Group cue to check that cues inside groups count.

## 1. Connections

- [ ] Launch the app. Settings opens because no Eos cue list is set.
- [ ] QLab: the workspace connects on its own (only one open). Status is green with the workspace name.
- [ ] QLab cue list picker lists "Lights". Choose it.
- [ ] Eos: enter Nomad's IP. The interface picker lists this Mac's interfaces with their IPs; choose the one on the Eos network (or Automatic if Nomad is on this Mac).
- [ ] With the Eos cue list still empty, the main window shows "Choose the Eos cue list to sync" and nothing is compared.
- [ ] Enter `0`, then `abc`: both are rejected in red. Enter `5`.
- [ ] Connect to Eos. Status is green and shows the Eos version.
- [ ] Unplug the Eos network (or quit Nomad). Within about 15 seconds status turns red; plug back in (or relaunch) and it reconnects on its own.
- [ ] Choose an interface that isn't connected to the Eos network: status says Eos can't be reached, and nothing connects through another interface.
- [ ] Repeat the connection with Protocol set to OSC 1.0 (port 3032), then set it back to OSC 1.1.

## 2. Reading and comparing

- [ ] Compare tab, with Eos list 5 empty: 1, 2, 2.5, 3 show **Missing in Eos**; 4A shows **Not an Eos number**; 6 and 6.0 show **Duplicate number**.
- [ ] The Eos cue list tab is empty; the QLab cues tab lists all 7 cues in QLab order.
- [ ] In Nomad, record cue 5/1 by hand with label "Preset": row 1 turns **Matches** within a couple of seconds.
- [ ] In Nomad, record cue 5/9 by hand: a **Not in QLab** row appears for 9.
- [ ] Rename QLab cue 2 to "Scene One": nothing changes for it yet (it's still missing in Eos). Rename QLab cue 1 to "Pre-show": row 1 turns **Label differs** within a second.
- [ ] Press Go on Nomad for cue 5/1: the ▶ marker and "Eos active cue" in the top bar follow it.
- [ ] Turn on "Only show differences": the matching rows disappear.

## 3. Adding blank cues (check this before using the app on a real show)

- [ ] Clear everything on stage in Nomad (no manual data).
- [ ] Approve **Add cue 5/2 "Scene One"**. The card shows the three commands before you approve.
- [ ] In Nomad, cue 5/2 exists, has **no levels**, Time 0 and label "Scene One". The row turns **Matches**; the action log says **Confirmed**.
- [ ] Now bring up some channels manually in Nomad (manual data on stage), then approve **Add cue 5/2.5**.
  Check whether cue 5/2.5 picked up those levels. **If it did, Record Only isn't safe with manual data on stage**: note it, and either clear manual data before syncing or change "Command to add a blank cue" in Settings to a command that's blank in every case.
- [ ] Approve **Add cue 5/3**: its Eos label is QLab's default name for that cue.

## 4. Editing and deleting

- [ ] Approve **Change label of cue 5/1** to "Pre-show". Nomad's label changes; row turns **Matches**.
- [ ] Rename a QLab cue to `Enter Time 5 Go`, then approve the label change: Nomad's label is exactly that text and nothing else happened on the console (it was treated as text, not keys).
- [ ] Clear a QLab cue's name so its displayed name is QLab's default, and check the Eos label follows.
- [ ] Approve **Delete cue 5/9**. Nomad no longer has cue 5/9, with no confirmation left waiting on the command line.
- [ ] Skip a change: it disappears and "1 skipped" shows. Press Show skipped: it's back.
- [ ] Disconnect Eos: Approve buttons are disabled and the panel says Eos is not connected.
- [ ] Make a change by hand in Nomad that undoes an approved one within 6 seconds of approving: the card says **Eos still differs** and offers Try again, and the action log says so.

## 5. Command line and Eos user

- [ ] With "Send as Eos user" empty, type something on Nomad's command line, then approve a change: note that it replaces what you typed (expected).
- [ ] Set "Send as Eos user" to an unused user number (e.g. 50), type something on Nomad's command line, approve a change: the change happens and your typing is left alone. If it doesn't work on your Eos version, leave the setting empty.
- [ ] Enter `100` as the user: it's rejected in red and Approve is disabled.

## 6. Action log

- [ ] Every approved change is in the Action log tab, newest first, with time, change, commands and result.
- [ ] "Copy all" puts the log on the clipboard as text.
- [ ] The log never shows more than 500 lines (shown as "n of 500 lines").

## 7. Things to report back

- Eos version and Nomad or console model:
- Did Record Only make blank cues with nothing on stage? With manual data on stage?
- Did "Send as Eos user" work?
- Anything in the connection log that looked wrong:

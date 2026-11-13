# QLab → Eos CueSync

QLab → Eos CueSync keeps one ETC Eos cue list in step with the numbered cues in a QLab cue list.
It's built for the common setup where Eos fires QLab cues with matching numbers: whenever you add,
renumber or rename cues in QLab, the app shows you exactly what's different on the console and
fixes it for you, one approved change at a time.

**QLab is always the source of truth.** The app only ever changes Eos, and it never changes
anything on the console until you approve it.

## What you need

- A Mac running macOS 13 or later, with QLab 5 running on the same Mac.
- An ETC Eos family console (or Eos Nomad) on a network this Mac can reach.

## One-time setup

### 1. Allow OSC in Eos

On the console, go to **Setup › System › Show Control › OSC** (or the same settings in the Eos
Shell) and turn on **OSC RX** and **OSC TX**. The app connects over TCP, so the UDP port and IP
address fields on that page don't matter.

### 2. Allow OSC access in QLab

In your QLab workspace, open **Workspace Settings › Network › OSC Access**. The passcode you'll
enter in the app (or "no passcode") needs **View** access. Without it, QLab refuses to share its
cue lists and changes won't appear automatically.

### 3. Connect the app

Open the app. The first time, the Settings sheet opens on its own; you can reopen it any time with
the **gear** button in the toolbar.

**QLab (on this Mac)**

| Setting | What to choose |
| --- | --- |
| Workspace | Leave as **The Only Open Workspace** if you only have one open. Otherwise pick the one to use. |
| Passcode | Only needed if the workspace's OSC Access uses passcodes. |
| Cue List | The QLab cue list whose numbered cues Eos should match. Cues inside groups count too. |

**Eos**

| Setting | What to choose |
| --- | --- |
| Console IP Address | The console's IP address, e.g. `10.101.92.101`. |
| Network Interface | The network port on this Mac that's connected to the Eos network. Until you choose one, the app uses the port with a 10.101.x.x address. **Use Default** goes back to that. |
| Protocol | Leave on **OSC 1.1 (TCP Port 3037)** unless you have a reason to use OSC 1.0 (port 3032). |
| Video Cuelist to Sync | The number of the Eos cue list to keep in sync (1 to 999). There's deliberately no default, so the app can't touch the wrong list by accident. |
| Main Cuelist | The cuelist whose current cue is shown in the toolbar (1 to 999). The default is **1**. |
| Send as Eos User | The Eos user the app types as. The default, **61**, keeps the app's commands off the operator's own command line. Leave it empty to use the console's current user. |

The first time the app connects to Eos, macOS asks whether it may find devices on your local network. Click **Allow**, or it can't reach the console.
## The main window

### Connection status

The top of the window shows both connections side by side:

- **QLab Connection**: the workspace and cue list in use.
- **Eos Connection**: the show file and the cue list being synced (**Video Cuelist**). If that cue
  list doesn't exist on the console yet, it says **Cuelist not found in console** in red.

The dot next to each title is green when connected, yellow while connecting, and red if there's a
problem (the reason is shown next to it).

The toolbar shows the **Active Eos Cue (Main Cuelist)**, the cue Eos is playing back right now in the **Main Cuelist** chosen in Settings.
**Refresh** (↻) re-reads both cue lists, though you'll rarely need it: changes made in QLab or on
the console show up on their own within a second or so.

### Compare

Every numbered QLab cue is lined up with the Eos cue of the same number (1, 1.0 and 01 all count
as cue 1). The columns are **QLab Cue Name**, **QLab Cue #**, **Status**, **Eos Cue #** and
**Eos Cue Label**, and a green ▶ marks the active Eos cue.

| Status | Meaning | What the app offers |
| --- | --- | --- |
| Matches | Same number, and the Eos label equals the QLab name | Nothing to do |
| Label Differs | The cue exists in both, but the Eos label is different | Update the Eos label |
| Missing in Eos | QLab has this number, Eos doesn't | Add a blank cue in Eos |
| Not in QLab | Eos has this number, QLab doesn't | Delete the cue in Eos |
| Not a Valid Eos Cue # | A QLab number Eos can't use, like "1A" or "Pre" | Nothing: renumber it in QLab |
| Duplicate Number | Two QLab cues share the same number | Nothing: fix it in QLab |

Hover over a status for a longer explanation. Turn on **Only Show Differences** to hide matching
cues. The summary above the table counts each kind of difference.

A few details:

- The QLab name used is the one shown in QLab's cue list, so an unnamed cue uses QLab's default name.
- Eos cue numbers can have up to 4 decimal places.
- Multipart cues aren't compared part by part.

## Making changes to Eos

The **Changes to approve** panel, on the right, lists one card for every change Eos needs. Each
card shows what will happen and the exact commands that will be sent. Nothing is sent until you
press a button.

| Button | What it does |
| --- | --- |
| **Add Eos Cue** | Creates a blank cue with time 0 and the QLab name as its label. |
| **Update Eos Cue Label** | Sets the Eos label to the QLab name. |
| **Delete Eos Cue** (red) | Deletes the cue from Eos. |
| **Skip** | Hides the change for now. **Show Skipped** brings skipped changes back. |
| **Approve All** | Sends every change that isn't skipped, after a confirmation listing how many adds, label edits and deletes there are. |
| **Update All Eos Cue Labels** | Sends just the label updates, straight away. |

After a change is sent, the app re-reads the Eos cue list to check it worked. When it has, the
card disappears and the row turns **Matches**. If Eos still differs after about 6 seconds, the card
says so and offers **Try Again**. Check the console, and see the Action Log for what Eos said.

If the Eos cue list you chose doesn't exist on the console yet, adding the first cue would create
it. The app asks first: **Create a new Eos cue list?**

### Good to know before using it on a show

- **New cues are created blank** with Record Only, which stores only manual data. With nothing
  manual on stage, the new cue is empty. Clear any manual data before adding cues, or check the
  new cues afterwards.
- **Commands are sent as Eos user 61** (unless you change it), so the app doesn't type on the
  operator's command line.
- **Labels are sent as text, not typed**, so any characters in a QLab cue name are safe.
- **Deletes are permanent.** Delete cards are red, and Approve All lists how many deletes it will
  send before you confirm.

## Logs

Two panels at the bottom of the window, both collapsed when the app opens. Click a title to expand it.

- **Action Log**: every change sent to Eos (newest 500), with the time, the change, the commands
  sent and the result. If a change didn't take, the result includes what Eos's command line said,
  which usually explains why. **Copy All** copies the log as text.
- **Connection Log**: connections, disconnections, errors, and every message sent to Eos.

## Troubleshooting

| What you see | What to check |
| --- | --- |
| Eos dot is red or stays yellow | The console IP address and network interface in Settings, that OSC RX/TX are on, and that macOS was allowed to use the local network (System Settings › Privacy & Security › Local Network). |
| **Cuelist not found in console** | The **Video Cuelist to Sync** number in Settings. If you do want a new list, adding a cue creates it (the app asks first). |
| QLab cues don't appear, or changes in QLab need Refresh | The passcode and its **View** permission in QLab's OSC Access settings. The Connection Log says if QLab refused access. |
| A change keeps saying Eos still differs | The Action Log entry: it includes what Eos's command line said, such as a syntax error. |
| **Not a Valid Eos Cue #** or **Duplicate Number** | Renumber the cue in QLab. The app never changes QLab. |

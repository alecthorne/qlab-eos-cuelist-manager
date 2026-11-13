import AppKit
import CueSyncCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var qlab: QLabClient
    @EnvironmentObject private var interfaces: NetworkInterfaceMonitor
    @State private var mainCueListText = ""
    @State private var mainCueListInvalid = false
    @FocusState private var mainCueListFocused: Bool
    @FocusState private var passcodeFocused: Bool
    @FocusState private var hostFocused: Bool

    var body: some View {
        Form {
            Section("QLab (On This Mac)") {
                HStack {
                    StatusLabel(qlab: qlab)
                    Spacer()
                    Button("Reconnect to QLab") { model.connectQLab() }
                }

                Picker("Workspace", selection: $settings.qlabWorkspaceID) {
                    Text("The Only Open Workspace").tag("")
                    ForEach(qlab.workspaces) { workspace in
                        Text(workspace.displayName).tag(workspace.id)
                    }
                    if !settings.qlabWorkspaceID.isEmpty,
                       !qlab.workspaces.contains(where: { $0.id == settings.qlabWorkspaceID }) {
                        Text("Saved Workspace (Not Open)").tag(settings.qlabWorkspaceID)
                    }
                }

                LabeledContent {
                    TextField("Passcode", text: $settings.qlabPasscode, prompt: Text("None"))
                        .labelsHidden()
                        .frame(width: Self.passcodeFieldWidth)
                        .focused($passcodeFocused)
                } label: {
                    Text("Passcode")
                    // Checked once the user leaves the field, so a half-typed value isn't flagged.
                    if !passcodeFocused, !QLabPasscode.isValid(settings.qlabPasscode) {
                        settingNote("QLab passcodes are four digits. Leave it empty if the workspace doesn't use one.",
                                    isError: true)
                    } else {
                        settingNote("Only needed if the workspace's OSC Access uses a passcode.")
                    }
                }

                Picker("Cue List", selection: $settings.qlabCueListID) {
                    Text("Choose a Cue List…").tag("")
                    ForEach(qlab.cueLists) { list in
                        Text(list.displayName).tag(list.id)
                    }
                    if !settings.qlabCueListID.isEmpty,
                       !qlab.cueLists.contains(where: { $0.id == settings.qlabCueListID }) {
                        Text("Saved Cue List (Not Found)").tag(settings.qlabCueListID)
                    }
                }
            }

            Section("Eos") {
                HStack {
                    EosStatusLabel()
                    Spacer()
                    Button("Connect to Eos") { model.connectEos() }
                        .disabled(!EosDefaults.isIPv4Address(eosHost))
                }

                LabeledContent {
                    TextField("Console IP Address", text: $settings.eosHost, prompt: Text("e.g. 10.101.100.101"))
                        .labelsHidden()
                        .frame(width: Self.addressFieldWidth)
                        .focused($hostFocused)
                } label: {
                    Text("Console IP Address")
                    if !hostFocused, !eosHost.isEmpty, !EosDefaults.isIPv4Address(eosHost) {
                        settingNote("Enter the console's IP address as four numbers from 0 to 255, e.g. 10.101.100.101.",
                                    isError: true)
                    }
                }

                Picker(selection: $settings.eosInterfaceName) {
                    Text("Automatic (Let macOS Choose)").tag("")
                    ForEach(interfaces.interfaces) { interface in
                        Text(interface.title).tag(interface.name)
                    }
                    if !settings.eosInterfaceName.isEmpty,
                       !interfaces.interfaces.contains(where: { $0.name == settings.eosInterfaceName }) {
                        Text("\(settings.eosInterfaceName) (Not Available)").tag(settings.eosInterfaceName)
                    }
                } label: {
                    Text("Network Interface")
                    settingNote(settings.eosInterfaceChosen
                                ? "Chosen by you."
                                : "Default: the interface with a 10.101.x.x address, or Automatic if there isn't one.")
                }
                Picker("Protocol", selection: $settings.eosFraming) {
                    Text("OSC 1.1 (TCP Port 3037)").tag(OSCTCPFraming.slip)
                    Text("OSC 1.0 (TCP Port 3032)").tag(OSCTCPFraming.lengthPrefix)
                }

                LabeledContent {
                    TextField("Video Cuelist to Sync", text: $settings.eosCueListText, prompt: Text("Required"))
                        .labelsHidden()
                        .frame(width: Self.cueListFieldWidth)
                } label: {
                    Text("Video Cuelist to Sync")
                    if settings.eosCueList == nil {
                        settingNote("Enter the number of the Eos cue list to keep in sync (1 to 999). There is no default.",
                                    isError: true)
                    }
                }

                LabeledContent {
                    TextField("Main Cuelist", text: $mainCueListText)
                        .labelsHidden()
                        .frame(width: Self.cueListFieldWidth)
                        .focused($mainCueListFocused)
                        .onSubmit(commitMainCueList)
                } label: {
                    Text("Main Cuelist")
                    if mainCueListInvalid {
                        settingNote("Enter a cuelist number from 1 to 999. Still using cuelist \(settings.eosMainCueList).",
                                    isError: true)
                    } else {
                        settingNote("Primary cuelist to watch for the current cue.")
                    }
                }

                LabeledContent {
                    TextField("Send as Eos User", text: $settings.eosUserText, prompt: Text("Current User"))
                        .labelsHidden()
                        .frame(width: Self.userFieldWidth)
                } label: {
                    Text("Send as Eos User")
                    if settings.eosUser == nil {
                        settingNote("Enter a user number from 0 to 99, or leave it empty.", isError: true)
                    } else {
                        settingNote("Default is user \(EosDefaults.user). A number sends as that Eos user, so the operator's command line isn't touched. Leave empty to type on the console's current command line.")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.qlabWorkspaceID) { _ in model.connectQLab() }
        .onChange(of: settings.eosCueListText) { _ in model.eos.setCueList(settings.eosCueList) }
        .onChange(of: mainCueListFocused) { focused in
            if !focused { commitMainCueList() }
        }
        .onAppear { mainCueListText = String(settings.eosMainCueList) }
        // Closing Settings while still typing doesn't always move focus first.
        .onDisappear(perform: commitMainCueList)
    }

    // Grouped-form text fields are borderless and right-aligned, so any width beyond what they
    // hold is invisible space that the setting's name and explanation can't use. Each field is
    // sized to its longest value or its prompt, whichever is wider, measured in the form's font.
    private static let passcodeFieldWidth = fieldWidth(fitting: "8888", "None")
    private static let addressFieldWidth = fieldWidth(fitting: "255.255.255.255", "e.g. 10.101.100.101")
    private static let cueListFieldWidth = fieldWidth(fitting: "999", "Required")
    private static let userFieldWidth = fieldWidth(fitting: "99", "Current User")

    private static func fieldWidth(fitting samples: String...) -> CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let widest = samples.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        // A little extra for the text field's own inset and the insertion point.
        return ceil(widest) + 8
    }

    private var eosHost: String { settings.eosHost.trimmingCharacters(in: .whitespaces) }

    /// Checks the Main Cuelist field once the user is done with it. Only valid numbers are saved;
    /// otherwise the error stays up and the last valid number keeps being used.
    private func commitMainCueList() {
        guard let list = EosCueListNumber.parse(mainCueListText) else {
            mainCueListInvalid = true
            return
        }
        mainCueListInvalid = false
        mainCueListText = String(list)
        settings.eosMainCueList = list
        model.eos.setMainCueList(list)
    }
}

/// Explanation or error under a setting's name. Placed in the setting's label, so the grouped
/// form shows it as a subtitle in the same row as the control. Kept a plain `Text` so the form
/// recognizes it as the label's subtitle.
private func settingNote(_ text: String, isError: Bool = false) -> Text {
    Text(text).foregroundColor(isError ? .red : .secondary)
}

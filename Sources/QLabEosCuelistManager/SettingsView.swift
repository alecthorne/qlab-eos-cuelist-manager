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

                TextField("Passcode", text: $settings.qlabPasscode, prompt: Text("Only If the Workspace Has One"))
                    .focused($passcodeFocused)
                // Checked once the user leaves the field, so a half-typed value isn't flagged.
                if !passcodeFocused, !QLabPasscode.isValid(settings.qlabPasscode) {
                    Text("QLab passcodes are four digits. Leave it empty if the workspace doesn't use one.")
                        .font(.callout)
                        .foregroundStyle(.red)
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

                TextField("Console IP Address", text: $settings.eosHost, prompt: Text("e.g. 10.101.100.101"))
                    .focused($hostFocused)
                if !hostFocused, !eosHost.isEmpty, !EosDefaults.isIPv4Address(eosHost) {
                    Text("Enter the console's IP address as four numbers from 0 to 255, e.g. 10.101.100.101.")
                        .font(.callout)
                        .foregroundStyle(.red)
                }

                Picker("Network Interface", selection: $settings.eosInterfaceName) {
                    Text("Automatic (Let macOS Choose)").tag("")
                    ForEach(interfaces.interfaces) { interface in
                        Text(interface.title).tag(interface.name)
                    }
                    if !settings.eosInterfaceName.isEmpty,
                       !interfaces.interfaces.contains(where: { $0.name == settings.eosInterfaceName }) {
                        Text("\(settings.eosInterfaceName) (Not Available)").tag(settings.eosInterfaceName)
                    }
                }
                HStack {
                    Text(settings.eosInterfaceChosen
                         ? "Chosen by you."
                         : "Default: the interface with a 10.101.x.x address, or Automatic if there isn't one.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Use Default") { model.useDefaultEosInterface() }
                        .disabled(!settings.eosInterfaceChosen)
                }

                Picker("Protocol", selection: $settings.eosFraming) {
                    Text("OSC 1.1 (TCP Port 3037)").tag(OSCTCPFraming.slip)
                    Text("OSC 1.0 (TCP Port 3032)").tag(OSCTCPFraming.lengthPrefix)
                }

                TextField("Video Cuelist to Sync", text: $settings.eosCueListText, prompt: Text("Required"))
                if settings.eosCueList == nil {
                    Text("Enter the number of the Eos cue list to keep in sync (1 to 999). There is no default.")
                        .font(.callout)
                        .foregroundStyle(.red)
                }

                TextField("Main Cuelist", text: $mainCueListText)
                    .focused($mainCueListFocused)
                    .onSubmit(commitMainCueList)
                if mainCueListInvalid {
                    Text("Enter a cuelist number from 1 to 999. Still using cuelist \(settings.eosMainCueList).")
                        .font(.callout)
                        .foregroundStyle(.red)
                } else {
                    Text("Primary cuelist to watch for the current cue.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                TextField("Send as Eos User", text: $settings.eosUserText, prompt: Text("Current User"))
                if settings.eosUser == nil {
                    Text("Enter a user number from 0 to 99, or leave it empty.")
                        .font(.callout)
                        .foregroundStyle(.red)
                } else {
                    Text("Default is user \(EosDefaults.user). A number sends as that Eos user, so the operator's command line isn't touched. Leave empty to type on the console's current command line.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
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

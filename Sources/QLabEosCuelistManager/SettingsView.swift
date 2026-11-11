import CueSyncCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var qlab: QLabClient
    @EnvironmentObject private var interfaces: NetworkInterfaceMonitor

    var body: some View {
        Form {
            Section("QLab (on this Mac)") {
                HStack {
                    StatusLabel(qlab: qlab)
                    Spacer()
                    Button("Reconnect to QLab") { model.connectQLab() }
                }

                Picker("Workspace", selection: $settings.qlabWorkspaceID) {
                    Text("The only open workspace").tag("")
                    ForEach(qlab.workspaces) { workspace in
                        Text(workspace.displayName).tag(workspace.id)
                    }
                    if !settings.qlabWorkspaceID.isEmpty,
                       !qlab.workspaces.contains(where: { $0.id == settings.qlabWorkspaceID }) {
                        Text("Saved workspace (not open)").tag(settings.qlabWorkspaceID)
                    }
                }

                TextField("Passcode", text: $settings.qlabPasscode, prompt: Text("Only if the workspace has one"))

                Picker("Cue list", selection: $settings.qlabCueListID) {
                    Text("Choose a cue list…").tag("")
                    ForEach(qlab.cueLists) { list in
                        Text(list.displayName).tag(list.id)
                    }
                    if !settings.qlabCueListID.isEmpty,
                       !qlab.cueLists.contains(where: { $0.id == settings.qlabCueListID }) {
                        Text("Saved cue list (not found)").tag(settings.qlabCueListID)
                    }
                }
            }

            Section("Eos") {
                HStack {
                    EosStatusLabel()
                    Spacer()
                    Button("Connect to Eos") { model.connectEos() }
                        .disabled(settings.eosHost.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                TextField("Console IP address", text: $settings.eosHost, prompt: Text("e.g. 10.101.100.101"))

                Picker("Network interface", selection: $settings.eosInterfaceName) {
                    Text("Automatic (let macOS choose)").tag("")
                    ForEach(interfaces.interfaces) { interface in
                        Text(interface.title).tag(interface.name)
                    }
                    if !settings.eosInterfaceName.isEmpty,
                       !interfaces.interfaces.contains(where: { $0.name == settings.eosInterfaceName }) {
                        Text("\(settings.eosInterfaceName) (not available)").tag(settings.eosInterfaceName)
                    }
                }
                HStack {
                    Text(settings.eosInterfaceChosen
                         ? "Chosen by you."
                         : "Default: the interface with a 10.101.x.x address, or Automatic if there isn't one.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Use default") { model.useDefaultEosInterface() }
                        .disabled(!settings.eosInterfaceChosen)
                }

                Picker("Protocol", selection: $settings.eosFraming) {
                    Text("OSC 1.1 (TCP port 3037)").tag(OSCTCPFraming.slip)
                    Text("OSC 1.0 (TCP port 3032)").tag(OSCTCPFraming.lengthPrefix)
                }

                TextField("Cue list to sync", text: $settings.eosCueListText, prompt: Text("Required"))
                if settings.eosCueList == nil {
                    Text("Enter the number of the Eos cue list to keep in sync (1 to 999). There is no default.")
                        .font(.callout)
                        .foregroundStyle(.red)
                }

                TextField("Send as Eos user", text: $settings.eosUserText, prompt: Text("Current user"))
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
    }
}

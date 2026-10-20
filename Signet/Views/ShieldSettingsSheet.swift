import SwiftUI

/// Shielded settings: shielded transactions (TzEL) on or off per layer 1 network, the services
/// of the deployment Signet talks to there (each replaceable, with Use Default) and the
/// operator's access token. Opened from "Shielded settings…" under Networks in both menus.
struct ShieldSettingsSheet: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss

    /// The layer 1 network whose shielded settings are being edited; starts on the one in use.
    @State private var editingNetworkName = ""
    @State private var operatorTokenText = ""
    @State private var operatorTokenError: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("Network", selection: $editingNetworkName) {
                        ForEach(Network.all) { network in
                            Text(network.name + (network.name == model.network.name ? "  (in use)" : "")).tag(network.name)
                        }
                    }
                    Toggle("Enable Shielded Transactions", isOn: shieldedEnabled)
                    if let base = editingNetwork, model.isShieldedEnabled(for: base), base.shieldedDefault == nil {
                        Text(base.shieldedAvailable
                             ? "\(base.name) has shielded transactions, but Signet does not know its TzEL services yet; the switch is remembered."
                             : "\(base.name) has no shielded transactions yet; the switch is remembered for when it does.")
                            .font(.callout).foregroundStyle(.orange)
                    }
                } header: {
                    SectionHeader(title: "Shielded Transactions", help: help)
                }
                if let base = editingNetwork, model.isShieldedEnabled(for: base), base.shieldedDefault != nil {
                    Section {
                        ForEach(ShieldedConfig.Setting.allCases, id: \.self) { setting in
                            SettingField(
                                title: setting.title,
                                current: model.shieldedSetting(setting, in: base) ?? "",
                                defaultValue: base.shieldedDefault?.text(for: setting) ?? "",
                                prompt: setting.prompt,
                                monospaced: true,
                                apply: { model.setShieldedSetting($0, for: setting, in: base) },
                                problem: { ShieldedConfig.problem($0, for: setting) },
                                useDefault: { model.useDefaultShieldedSetting(for: setting, in: base) }
                            )
                            .id("\(base.name)/shielded/\(setting.rawValue)")
                        }
                    } header: {
                        SectionHeader(title: "TzEL services", help: servicesHelp)
                    }
                    Section {
                        LabeledContent("Operator token") {
                            VStack(alignment: .trailing, spacing: 8) {
                                SecureField("", text: $operatorTokenText, prompt: Text(model.shieldedOperatorTokenIsSet(for: base) ? "On file; paste a new one to replace it" : "Paste the operator's access token"))
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit(applyOperatorToken)
                                    .frame(minWidth: 300)
                                if let operatorTokenError { Text(operatorTokenError).font(.callout).foregroundStyle(.red) }
                                HStack {
                                    if model.shieldedOperatorTokenIsSet(for: base) {
                                        Button("Remove") { operatorTokenText = ""; applyOperatorToken() }
                                    }
                                    Button("Apply", action: applyOperatorToken)
                                        .disabled(operatorTokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                }
                            }
                        }
                    } header: {
                        SectionHeader(title: "Access", help: tokenHelp)
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .navigationTitle("Shielded settings")
        .onAppear { editingNetworkName = model.network.name }
        .onChange(of: editingNetworkName) { operatorTokenText = ""; operatorTokenError = nil }
    }

    private var help: String {
        "With Shielded Transactions on, the dashboard shows the account's shielded tez on the TzEL rollup of the chosen layer 1 network, and the menus offer Shield tez, Unshield tez, Send shielded and Shielded address. The choice and the settings below are kept per network."
    }

    private var servicesHelp: String {
        "The rollup node serves the notes and nullifiers; the rollup and bridge ticketer are checked before any tez move; the proving service makes the proofs; the operator relays them to the rollup. The producer fee is the note every shielded operation pays the DAL slot producer, in mutez. Plain http is accepted, but macOS only lets it through for the hosts Signet ships with; use https for anything else. Use Default restores what Signet ships."
    }

    private var tokenHelp: String {
        "The operator relays shielded operations only with its access token. It is kept with the shielded wallet in the wallet directory, never in Signet's settings, and shielding is refused until it is on file."
    }

    private var editingNetwork: Network? { Network.named(editingNetworkName) }

    private var shieldedEnabled: Binding<Bool> {
        Binding(
            get: { editingNetwork.map { model.isShieldedEnabled(for: $0) } ?? false },
            set: { on in if let base = editingNetwork { model.setShieldedEnabled(on, for: base) } }
        )
    }

    /// Keeps the token in the network's shielded wallet file; the field empties once it is on file.
    private func applyOperatorToken() {
        guard let base = editingNetwork else { return }
        operatorTokenError = nil
        do {
            try model.setShieldedOperatorToken(operatorTokenText, for: base)
            operatorTokenText = ""
        } catch {
            operatorTokenError = error.localizedDescription
        }
    }
}

#Preview {
    ShieldSettingsSheet(model: .preview())
}

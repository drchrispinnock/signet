import SwiftUI

/// App settings. For now: which node to talk to.
struct SettingsView: View {
    @Bindable var model: WalletViewModel

    var body: some View {
        Form {
            Section {
                Picker("Node", selection: $model.network) {
                    ForEach(Network.all) { network in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(network.name)
                            Text(network.rpcURL.absoluteString)
                                .font(.callout.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        .tag(network)
                    }
                }
                .pickerStyle(.radioGroup)
            } footer: {
                Text("Balances and names are fetched from the selected network. More networks will be added later.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .navigationTitle("Settings")
    }
}

#Preview {
    SettingsView(model: .preview())
}

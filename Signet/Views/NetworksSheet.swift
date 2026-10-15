import SwiftUI

/// Networks: which node Signet talks to on each network, the Layer 2 (Etherlink) node, and
/// the TzKT API, block explorer and faucet links it uses there. Opened from the burger and
/// Operations menus and from the network badge; the network in use is switched with the badge,
/// not here.
struct NetworksSheet: View {
    @Bindable var model: WalletViewModel
    @Environment(\.dismiss) private var dismiss

    /// The network whose node is being edited; starts on the one in use.
    @State private var editingNetworkName = ""
    /// The node beneath the network dropdown is free text so any RPC endpoint can replace the
    /// default for that network. The text is applied on Return or with Apply.
    @State private var nodeText = ""
    @State private var nodeError: String?
    @State private var l2NodeText = ""
    @State private var l2NodeError: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                nodeSection
                servicesSection
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .navigationTitle("Networks")
        .onAppear { editingNetworkName = model.network.name; syncNodeText() }
        .onChange(of: editingNetworkName) { syncNodeText() }
        .onChange(of: model.network) { if editingNetworkName == model.network.name { syncNodeText() } }
    }

    private var nodeSection: some View {
        Section {
            Picker("Network", selection: $editingNetworkName) {
                ForEach(Network.all) { network in
                    Text(network.name + (network.name == model.network.name ? "  (in use)" : "")).tag(network.name)
                }
            }
            LabeledContent("Node") {
                VStack(alignment: .trailing, spacing: 8) {
                    TextField("", text: $nodeText)
                        .font(.callout.monospaced())
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .onSubmit(applyNode)
                        .frame(minWidth: 300)
                    if let nodeError {
                        Text(nodeError)
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                    HStack {
                        Button("Use Default") {
                            if let base = editingNetwork { model.useDefaultNode(for: base); syncNodeText() }
                        }
                        .disabled(editingNetwork.map { model.nodeURL(for: $0) == $0.defaultRPCURL } ?? true)
                        Button("Apply", action: applyNode)
                            .disabled(!nodeIsDirty)
                    }
                }
            }
            Toggle("Enable Layer 2", isOn: l2Enabled)
            if let base = editingNetwork, model.isL2Enabled(for: base) {
                LabeledContent("Layer 2 Michelson node") {
                    VStack(alignment: .trailing, spacing: 8) {
                        TextField("", text: $l2NodeText, prompt: Text("https://…"))
                            .font(.callout.monospaced())
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .onSubmit(applyL2Node)
                            .frame(minWidth: 300)
                        if let l2NodeError {
                            Text(l2NodeError).font(.callout).foregroundStyle(.red)
                        } else if model.l2NodeURL(for: base) == nil {
                            Text("Enter the Layer 2 Michelson node to use; the balance is not shown until then.").font(.callout).foregroundStyle(.orange)
                        }
                        HStack {
                            Button("Use Default") { model.useDefaultL2Node(for: base); syncNodeText() }
                                .disabled(base.l2DefaultRPCURL == nil || model.l2NodeURL(for: base) == base.l2DefaultRPCURL)
                            Button("Apply", action: applyL2Node)
                                .disabled(!l2NodeIsDirty)
                        }
                    }
                }
            }
        } header: {
            Text("Networks")
        } footer: {
            Text(nodeFooter)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    /// The links beside the node. Each field is applied on Return or with Apply; empty text
    /// turns the link off (no explorer links, no Get test tez button); Use Default restores ours.
    private var servicesSection: some View {
        Section {
            if let base = editingNetwork {
                ForEach(Network.Service.allCases.filter { base.offers($0) }, id: \.self) { service in
                    LinkField(
                        title: service.title,
                        current: model.serviceURL(for: service, in: base),
                        defaultURL: base.defaultURL(for: service),
                        apply: { model.setServiceURL($0, for: service, in: base) },
                        useDefault: { model.useDefaultServiceURL(for: service, in: base) }
                    )
                    .id("\(base.name)/\(service.rawValue)")
                }
            }
        } header: {
            Text("Links")
        } footer: {
            Text(servicesFooter)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var servicesFooter: String {
        guard let base = editingNetwork else { return "" }
        var text = "The TzKT API feeds the history, token and NFT lists; the explorer is where operations are opened; the faucet is behind Get test tez. Leave a link empty to do without it."
        if base.isMainnet {
            text += " Mainnet has no faucet."
        } else {
            text += base.faucetKind == .pqpark
                ? " A replacement faucet must speak PQPark's faucet API."
                : " A replacement faucet must speak the teztnets faucet API."
        }
        return text
    }

    private var l2Enabled: Binding<Bool> {
        Binding(
            get: { editingNetwork.map { model.isL2Enabled(for: $0) } ?? false },
            set: { on in if let base = editingNetwork { model.setL2Enabled(on, for: base); syncNodeText() } }
        )
    }

    private var editingNetwork: Network? { Network.named(editingNetworkName) }

    private var nodeIsDirty: Bool {
        guard let base = editingNetwork else { return false }
        return Network.nodeURL(from: nodeText) != model.nodeURL(for: base)
    }

    private var l2NodeIsDirty: Bool {
        guard let base = editingNetwork else { return false }
        return Network.nodeURL(from: l2NodeText) != model.l2NodeURL(for: base)
    }

    private var nodeFooter: String {
        guard let base = editingNetwork else { return "" }
        var text = "The node Signet uses for \(base.name). Each network keeps its own; switch networks with the badge at the top of the main window."
        if base.chain == "custom" {
            text += " Custom is yours to point anywhere, for example a node you run yourself."
        } else {
            text += " The default is \(base.defaultRPCURL.absoluteString)."
        }
        if base.chain == "weeklynet" {
            text += " Weeklynet restarts every Wednesday and its address carries that date, so the default follows the calendar."
        }
        if model.isL2Enabled(for: base) {
            text += " With Layer 2 on, the dashboard shows each tz1, tz2 or tz3 account's balance on Etherlink, read from the Layer 2 Michelson node"
            text += base.l2DefaultRPCURL.map { " (default \($0.absoluteString))." } ?? " you enter here."
        }
        return text
    }

    private func syncNodeText() {
        if let base = editingNetwork {
            nodeText = model.nodeURL(for: base).nodeDisplayTextStandalone
            l2NodeText = model.l2NodeURL(for: base)?.nodeDisplayTextStandalone ?? ""
        }
        nodeError = nil
        l2NodeError = nil
    }

    private func applyNode() {
        guard let base = editingNetwork else { return }
        if model.setNode(nodeText, for: base) {
            nodeError = nil
            syncNodeText()
        } else {
            nodeError = Network.nodeURLProblem(nodeText)
        }
    }

    private func applyL2Node() {
        guard let base = editingNetwork else { return }
        if model.setL2Node(l2NodeText, for: base) {
            l2NodeError = nil
            syncNodeText()
        } else {
            l2NodeError = Network.nodeURLProblem(l2NodeText)
        }
    }
}

/// One URL field with its error line and Use Default / Apply buttons.
private struct LinkField: View {
    let title: String
    let current: URL?
    let defaultURL: URL?
    /// Applies the text; false when it was refused.
    let apply: (String) -> Bool
    let useDefault: () -> Void

    @State private var text = ""
    @State private var error: String?

    var body: some View {
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 8) {
                TextField("", text: $text, prompt: Text("https://…"))
                    .font(.callout.monospaced())
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onSubmit(submit)
                    .frame(minWidth: 300)
                if let error {
                    Text(error).font(.callout).foregroundStyle(.red)
                }
                HStack {
                    Button("Use Default") { useDefault(); error = nil }
                        .disabled(defaultURL == nil || current == defaultURL)
                    Button("Apply", action: submit)
                        .disabled(!isDirty)
                }
            }
        }
        .onAppear(perform: sync)
        .onChange(of: current) { sync() }
    }

    private var typed: URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : Network.nodeURL(from: trimmed)
    }

    private var isDirty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? current != nil : typed != current
    }

    private func sync() {
        text = current?.nodeDisplayTextStandalone ?? ""
        error = nil
    }

    private func submit() {
        if apply(text) {
            error = nil
        } else {
            error = Network.nodeURLProblem(text)
        }
    }
}

#Preview {
    NetworksSheet(model: .preview())
}

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
    /// A node on a network that pins a chain id is asked which chain it serves before Apply
    /// adopts it; a wrong or silent answer is shown here with a Use Anyway button.
    @State private var nodeWarning: NodeIdentity?
    @State private var nodeChecking = false
    @State private var l2NodeWarning: NodeIdentity?
    @State private var l2NodeChecking = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                nodeSection
                shieldedSection
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
        .onChange(of: nodeText) { nodeWarning = nil }
        .onChange(of: l2NodeText) { l2NodeWarning = nil }
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
                    } else if let nodeWarning, let base = editingNetwork {
                        Text(warning(nodeWarning, for: base))
                            .font(.callout)
                            .foregroundStyle(.orange)
                    } else if nodeChecking {
                        checkingLabel
                    }
                    HStack {
                        Button("Use Default") {
                            if let base = editingNetwork { model.useDefaultNode(for: base); syncNodeText() }
                        }
                        .disabled(editingNetwork.map { model.nodeURL(for: $0) == $0.defaultRPCURL } ?? true)
                        if nodeWarning != nil {
                            Button("Use Anyway") {
                                if let base = editingNetwork { model.setNode(nodeText, for: base); syncNodeText() }
                            }
                        } else {
                            Button("Apply", action: applyNode)
                                .disabled(!nodeIsDirty || nodeChecking)
                        }
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
                        } else if let l2NodeWarning {
                            Text(warning(l2NodeWarning, for: base, layer: .two)).font(.callout).foregroundStyle(.orange)
                        } else if l2NodeChecking {
                            checkingLabel
                        } else if model.l2NodeURL(for: base) == nil {
                            Text("Enter the Layer 2 Michelson node to use; the balance is not shown until then.").font(.callout).foregroundStyle(.orange)
                        }
                        HStack {
                            Button("Use Default") { model.useDefaultL2Node(for: base); syncNodeText() }
                                .disabled(base.l2DefaultRPCURL == nil || model.l2NodeURL(for: base) == base.l2DefaultRPCURL)
                            if l2NodeWarning != nil {
                                Button("Use Anyway") { model.setL2Node(l2NodeText, for: base); syncNodeText() }
                            } else {
                                Button("Apply", action: applyL2Node)
                                    .disabled(!l2NodeIsDirty || l2NodeChecking)
                            }
                        }
                    }
                }
            }
        } header: {
            SectionHeader(title: "Networks", help: nodeHelp)
        }
    }

    /// Shielded transactions (TzEL): the switch, every service of the deployment (each
    /// replaceable, with Use Default), and the operator's access token.
    private var shieldedSection: some View {
        Section {
            Toggle("Enable Shielded Transactions", isOn: shieldedEnabled)
            if let base = editingNetwork, model.isShieldedEnabled(for: base) {
                if base.shieldedDefault != nil {
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
                } else {
                    Text(base.shieldedAvailable
                         ? "\(base.name) has shielded transactions, but Signet does not know its TzEL services yet; the switch is remembered."
                         : "\(base.name) has no shielded transactions yet; the switch is remembered for when it does.")
                        .font(.callout).foregroundStyle(.orange)
                }
            }
        } header: {
            SectionHeader(title: "Shielded Transactions", help: shieldedHelp)
        }
    }

    private var shieldedHelp: String {
        "With Shielded Transactions on, the dashboard shows the account's shielded tez on the TzEL rollup and the menus offer Shield tez, Unshield tez, Send shielded and Shielded address. "
        + "The rollup node serves the notes and nullifiers, the rollup and bridge ticketer are checked before any tez move, the proving service makes the proofs, and the operator relays them to the rollup, which needs its access token (kept with the shielded wallet in the wallet directory, never in Signet's settings). "
        + "The producer fee is the note every shielded operation pays the DAL slot producer, in mutez. Plain http is accepted, but macOS only lets it through for the hosts Signet ships with; use https for anything else. "
        + "Settings are kept per network; Use Default restores what Signet ships."
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
            SectionHeader(title: "Links", help: servicesFooter)
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

    @State private var operatorTokenText = ""
    @State private var operatorTokenError: String?

    /// Keeps the token in the network's shielded wallet file (never in the app state or the
    /// repository); the field empties once it is on file.
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

    private var shieldedEnabled: Binding<Bool> {
        Binding(
            get: { editingNetwork.map { model.isShieldedEnabled(for: $0) } ?? false },
            set: { on in if let base = editingNetwork { model.setShieldedEnabled(on, for: base) } }
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

    private var nodeHelp: String {
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
        if base.expectedChainID != nil {
            text += " A new node is asked which chain it serves before it is used, and one on another chain is warned about."
        }
        if model.isL2Enabled(for: base) {
            text += " With Layer 2 on, the dashboard shows each tz1, tz2 or tz3 account's balance on Etherlink, read from the Layer 2 Michelson node"
            text += base.l2DefaultRPCURL.map { " (default \($0.absoluteString))." } ?? " you enter here."
        }
        return text
    }

    private var checkingLabel: some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text("Checking which chain the node serves…").font(.callout).foregroundStyle(.secondary)
        }
    }

    /// The warning under a node field: the node serves another chain, or could not be asked.
    private func warning(_ identity: NodeIdentity, for base: Network, layer: NodeMonitor.Layer = .one) -> String {
        let name = layer == .two ? "\(base.name)'s Etherlink" : base.name
        switch identity {
        case .mismatch(let found, let expected):
            return "This node serves chain \(found), not \(name) (\(expected)). Signet would show it in red and refuse to sign through it."
        case .unchecked(let reason):
            return "Signet could not check which chain this node serves. \(reason)."
        case .unpinned, .matches:
            return ""
        }
    }

    private func syncNodeText() {
        if let base = editingNetwork {
            nodeText = model.nodeURL(for: base).nodeDisplayTextStandalone
            l2NodeText = model.l2NodeURL(for: base)?.nodeDisplayTextStandalone ?? ""
        }
        nodeError = nil
        l2NodeError = nil
        nodeWarning = nil
        l2NodeWarning = nil
    }

    /// Apply asks a node on a pinned network which chain it serves first; only a matching (or
    /// unpinned) node is adopted straight away, anything else waits for Use Anyway.
    private func applyNode() {
        guard let base = editingNetwork else { return }
        guard Network.nodeURL(from: nodeText) != nil else { nodeError = Network.nodeURLProblem(nodeText); return }
        nodeError = nil
        nodeWarning = nil
        nodeChecking = true
        let text = nodeText
        Task {
            let identity = await model.checkNode(text, for: base)
            nodeChecking = false
            // The field or the dropdown moved on while the node was being asked.
            guard text == nodeText, editingNetwork?.name == base.name else { return }
            switch identity {
            case .unpinned, .matches:
                model.setNode(text, for: base)
                syncNodeText()
            case .mismatch, .unchecked:
                nodeWarning = identity
            }
        }
    }

    private func applyL2Node() {
        guard let base = editingNetwork else { return }
        guard Network.nodeURL(from: l2NodeText) != nil else { l2NodeError = Network.nodeURLProblem(l2NodeText); return }
        l2NodeError = nil
        l2NodeWarning = nil
        l2NodeChecking = true
        let text = l2NodeText
        Task {
            let identity = await model.checkNode(text, for: base, layer: .two)
            l2NodeChecking = false
            guard text == l2NodeText, editingNetwork?.name == base.name else { return }
            switch identity {
            case .unpinned, .matches:
                model.setL2Node(text, for: base)
                syncNodeText()
            case .mismatch, .unchecked:
                l2NodeWarning = identity
            }
        }
    }
}

/// A section title with an ⓘ that shows the explanation on hover, instead of a paragraph
/// under the section.
private struct SectionHeader: View {
    let title: String
    let help: String
    @State private var showing = false

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .onHover { showing = $0 }
                .popover(isPresented: $showing, arrowEdge: .bottom) {
                    Text(help).font(.callout).frame(width: 400, alignment: .leading).padding(12)
                }
                .help(help)
                .accessibilityLabel("About \(title)")
        }
    }
}

/// One text setting with its error line and Use Default / Apply buttons.
private struct SettingField: View {
    let title: String
    let current: String
    let defaultValue: String
    let prompt: String
    var monospaced = false
    /// Applies the text; false when it was refused.
    let apply: (String) -> Bool
    let problem: (String) -> String
    let useDefault: () -> Void

    @State private var text = ""
    @State private var error: String?

    var body: some View {
        LabeledContent(title) {
            VStack(alignment: .trailing, spacing: 8) {
                TextField("", text: $text, prompt: Text(prompt))
                    .font(monospaced ? .callout.monospaced() : .callout)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onSubmit(submit)
                    .frame(minWidth: 300)
                if let error { Text(error).font(.callout).foregroundStyle(.red) }
                HStack {
                    Button("Use Default") { useDefault(); error = nil }
                        .disabled(current == defaultValue)
                    Button("Apply", action: submit)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines) == current)
                }
            }
        }
        .onAppear(perform: sync)
        .onChange(of: current) { sync() }
    }

    private func sync() {
        text = current
        error = nil
    }

    private func submit() {
        if apply(text) { error = nil } else { error = problem(text) }
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

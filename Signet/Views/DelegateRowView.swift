import SwiftUI

/// One line under the balances: who the wallet delegates to (or that it is a baker). Click → Staking.
struct DelegateRowView: View {
    @Bindable var model: WalletViewModel
    @State private var delegateName: String?

    var body: some View {
        Button {
            model.isPresentingStaking = true
        } label: {
            HStack(spacing: 12) {
                icon
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline).font(.body.weight(.medium))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Delegation and staking")
        .task(id: model.delegateInfo?.delegate) {
            delegateName = nil
            guard let delegate = model.delegateInfo?.delegate, model.delegateInfo?.isBaker != true else { return }
            let known = model.displayName(for: delegate, indexerAlias: nil)
            if known.isOurs { delegateName = known.name; return }
            delegateName = await model.profileName(for: delegate) ?? delegate.shortened()
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let info = model.delegateInfo, let delegate = info.delegate, !info.isBaker {
            AccountAvatarView(address: delegate, size: 44)
        } else {
            ZStack {
                Circle().fill(.quaternary)
                Image(systemName: model.delegateInfo?.isBaker == true ? "server.rack" : "person.crop.circle.badge.questionmark")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var headline: String {
        guard let info = model.delegateInfo else { return "Delegation" }
        if info.isBaker { return model.selectedWallet?.keyKind.canSign == true ? "You are a baker" : "This address is a baker" }
        if let delegate = info.delegate { return "Delegated to \(delegateName ?? delegate.shortened())" }
        return "Not delegated"
    }

    private var subtitle: String {
        guard let info = model.delegateInfo else { return "Checking…" }
        if let baker = info.baker {
            if let kind = model.selectedWallet?.keyKind, !kind.canSign {
                let why = kind == .ledger ? "its key is on a Ledger" : kind == .remote ? "it signs remotely" : "Signet holds only its public key"
                return (baker.deactivated ? "Deactivated. " : "") + "Watch only: \(why). Baking shows its keys and parameters."
            }
            return baker.deactivated ? "Deactivated; see Baking in the menu" : "Self-delegated; keys and staking parameters under Baking"
        }
        if info.delegate != nil {
            switch info.delegateAcceptsStaking {
            case .some(true): return "This baker accepts staked tez"
            case .some(false): return "This baker does not accept staking"
            case .none: return "Tap to stake or change delegate"
            }
        }
        return "Delegate to a baker to earn rewards"
    }
}

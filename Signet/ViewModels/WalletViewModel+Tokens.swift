import Foundation

/// FA2 token transfers from the selected account (NFT Transfer and Burn, 0.9.13): estimated
/// in a context and sent only in that same context with the approved limits (S14, S31).
extension WalletViewModel {
    /// A token transfer estimate together with everything it was made for: the exact request,
    /// the layer, and the account, network and directory.
    struct TokenTransferApproval: Sendable {
        let estimate: TokenTransferEstimate
        let request: TokenTransferRequest
        let layer: Int
        let context: BridgeContext
    }

    /// Whether the selected account can move its tokens on `layer`: a key Signet can sign for,
    /// and on Etherlink a tz1, tz2 or tz3 account with Layer 2 on.
    func canTransferTokens(on layer: Int) -> Bool {
        guard let wallet = selectedWallet, wallet.keyKind.canSign else { return false }
        if layer == 2 { return network.hasL2 && wallet.address.isUsableOnEtherlink && layer2Chain != nil }
        return layer == 1
    }

    /// The network tokens on `layer` live on, for explorer links.
    func tokenNetwork(on layer: Int) -> Network {
        layer == 2 ? (network.layer2 ?? network) : network
    }

    private func tokenChain(on layer: Int) -> (any ChainService)? {
        layer == 2 ? layer2Chain : chainService
    }

    func estimateTokenTransfer(_ request: TokenTransferRequest, on layer: Int) async throws -> TokenTransferApproval {
        guard let wallet = selectedWallet, let context = bridgeContext else { throw WalletError.emptyAlias }
        guard canTransferTokens(on: layer), let chain = tokenChain(on: layer) else { throw SendViewModel.SendError.noSecretKey }
        guard request.isValid, layer == 1 || request.to.isUsableOnEtherlink else { throw ChainError.invalidTokenTransfer }
        let estimate = try await chain.estimateTokenTransfer(request, from: wallet)
        // The account, network, node or directory may have changed while the node was asked.
        guard bridgeContext == context else { throw WalletError.contextChanged }
        return TokenTransferApproval(estimate: estimate, request: request, layer: layer, context: context)
    }

    /// Sends the approved transfer with its approved limits and waits for its block. The
    /// estimate must have been made for exactly this request, on this layer, in the context the
    /// transfer runs in now (S31).
    func transferTokens(_ request: TokenTransferRequest, on layer: Int, approved: TokenTransferApproval?, passphrase: String?) async throws -> (hash: String, level: Int) {
        guard let wallet = selectedWallet else { throw WalletError.emptyAlias }
        guard let approved else { throw WalletError.notEstimated }
        guard approved.request == request, approved.layer == layer, approved.context == bridgeContext else { throw WalletError.contextChanged }
        guard canTransferTokens(on: layer), let chain = tokenChain(on: layer) else { throw SendViewModel.SendError.noSecretKey }
        guard request.isValid, layer == 1 || request.to.isUsableOnEtherlink else { throw ChainError.invalidTokenTransfer }
        guard let signer = try signingKey(for: wallet, passphrase: passphrase) else { throw SendViewModel.SendError.noSecretKey }
        let sent = try await chain.sendTokenTransfer(request, from: wallet, signer: signer, limits: approved.estimate.limits)
        let level: Int
        do {
            level = try await chain.waitForConfirmation(of: sent.hash)
        } catch where !sent.injected {
            throw WalletError.outcomeUnknown(sent.hash)
        }
        await refreshAfterOperation()
        return (sent.hash, level)
    }
}

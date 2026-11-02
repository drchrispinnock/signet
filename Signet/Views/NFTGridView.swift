import AppKit
import SwiftUI

/// What the NFT grid's context menu can do with the tokens, handed in by the dashboard; `nil`
/// (previews) leaves only the links and copies.
struct NFTActions {
    /// The network tokens on a layer live on, for explorer links.
    let network: (Int) -> Network
    /// Whether the selected account can transfer or burn tokens on a layer.
    let canOperate: (Int) -> Bool
    /// Opens the Transfer or Burn sheet on the tokens.
    let start: (NFTOperation) -> Void
    /// Saves the tokens' artwork to disk.
    let download: (NFTDownload) -> Void
}

/// Grid of NFT thumbnails at the bottom of the default screen. Tiles select like files in the
/// Finder (click, Cmd-click to add, Shift-click for a range) and a right-click opens the menu
/// for the clicked tile, or for the whole selection when it is part of one.
struct NFTGridView: View {
    let nfts: [NFT]
    let isLoading: Bool
    var state: Portfolio.State = .complete
    /// What to say instead of "No NFTs" when the layer toggles leave the tab empty.
    var layerEmptyText: String? = nil
    var actions: NFTActions? = nil

    @State private var selection: Set<NFT.ID> = []
    /// Where a Shift-click range starts: the last tile clicked without Shift.
    @State private var anchor: NFT.ID?

    private let columns = [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PortfolioStateNote(state: state)
            if nfts.isEmpty {
                Text(isLoading ? "Loading…" : (state.isUnavailable ? "NFT data is unavailable." : layerEmptyText ?? "No NFTs in this account."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 24)
            } else {
                ScrollView(.vertical) {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                        ForEach(nfts) { nft in
                            NFTTileView(nft: nft, isSelected: selection.contains(nft.id))
                                .onTapGesture { click(nft) }
                                .contextMenu {
                                    NFTContextMenu(targets: targets(for: nft), actions: actions, canSelectAll: selection.count < nfts.count,
                                                   selectAll: { selection = Set(nfts.map(\.id)) }, deselect: selection.isEmpty ? nil : { selection = [] })
                                }
                        }
                    }
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.clear.contentShape(Rectangle()).onTapGesture { selection = [] })
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: nfts.map(\.id)) { _, ids in selection = selection.intersection(ids) }
        .accessibilityAction(named: "Deselect all NFTs") { selection = [] }
    }

    /// The tokens a menu on `nft` acts on: the selection when the tile is in it, else that tile alone.
    private func targets(for nft: NFT) -> [NFT] {
        selection.contains(nft.id) ? nfts.filter { selection.contains($0.id) } : [nft]
    }

    private func click(_ nft: NFT) {
        let flags = NSApp.currentEvent?.modifierFlags ?? []
        if flags.contains(.command) {
            if selection.contains(nft.id) { selection.remove(nft.id) } else { selection.insert(nft.id) }
        } else if flags.contains(.shift), let anchor, let from = nfts.firstIndex { $0.id == anchor }, let to = nfts.firstIndex { $0.id == nft.id } {
            selection = Set(nfts[min(from, to)...max(from, to)].map(\.id))
            return
        } else {
            selection = [nft.id]
        }
        anchor = nft.id
    }
}

/// The right-click menu of one tile or of the selection: Transfer and Burn when the account
/// can sign for its tokens (never for a selection spanning Tezos and Etherlink, or a soulbound
/// token), Download for the artwork, then the links and copies of a single token, then selection.
struct NFTContextMenu: View {
    let targets: [NFT]
    let actions: NFTActions?
    let canSelectAll: Bool
    let selectAll: () -> Void
    let deselect: (() -> Void)?

    private var layer: Int { targets.first?.layer ?? 1 }
    private var sameLayer: Bool { Set(targets.map(\.layer)).count == 1 }
    private var transferable: Bool { targets.allSatisfy(\.isTransferable) }
    private var canOperate: Bool { sameLayer && transferable && targets.count <= TokenTransferRequest.maxTokens && (actions?.canOperate(layer) ?? false) }
    private var plural: String { targets.count == 1 ? "" : " \(targets.count) NFTs" }

    var body: some View {
        Button("Transfer\(plural)…") { actions?.start(NFTOperation(kind: .transfer, nfts: targets)) }
            .disabled(!canOperate)
        Button("Burn\(plural)…", role: .destructive) { actions?.start(NFTOperation(kind: .burn, nfts: targets)) }
            .disabled(!canOperate)
        if let reason {
            Text(reason)
        }
        Divider()
        Button("Download\(plural)…") { actions?.download(NFTDownload(nfts: targets)) }
            .disabled(actions == nil || !targets.allSatisfy { !$0.artifactURLs.isEmpty || !$0.imageURLs.isEmpty })
        if targets.count == 1, let nft = targets.first {
            if let actions {
                let network = actions.network(nft.layer)
                if let url = network.explorerURL(token: nft.contract, id: nft.tokenId) {
                    Button("Open in Explorer") { NSWorkspace.shared.open(url) }
                }
                if let url = network.objktURL(token: nft.contract, id: nft.tokenId) {
                    Button("Open on objkt.com") { NSWorkspace.shared.open(url) }
                }
            }
            if let url = nft.artifactURLs.first {
                Button(nft.isMoving ? "View Artwork (plays in the browser)" : "View Artwork") { NSWorkspace.shared.open(url) }
            }
            Divider()
            Button("Copy Contract Address") { copy(nft.contract) }
            Button("Copy Token ID") { copy(nft.tokenId) }
        }
        Divider()
        Button("Select All") { selectAll() }.disabled(!canSelectAll)
        if let deselect { Button("Deselect All") { deselect() } }
    }

    /// Why Transfer and Burn are off, when they are.
    private var reason: String? {
        if !sameLayer { return "Choose NFTs on one chain at a time" }
        if !transferable { return targets.count == 1 ? "This token cannot be transferred" : "One of these tokens cannot be transferred" }
        if targets.count > TokenTransferRequest.maxTokens { return "At most \(TokenTransferRequest.maxTokens) NFTs at once" }
        if let actions, !actions.canOperate(layer) { return layer == 2 ? "Signet cannot sign for this account on Etherlink" : "Signet cannot sign for this account" }
        return nil
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct NFTTileView: View {
    let nft: NFT
    var isSelected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // A square frame that the image fills and is centre-cropped to.
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .overlay { thumbnail }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .contentShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary.opacity(0.25)), lineWidth: isSelected ? 3 : 1))
                .overlay(alignment: .topLeading) {
                    if nft.isLayer2 {
                        EtherlinkMark(size: 16)
                            .padding(3)
                            .background(Circle().fill(.black.opacity(0.6)))
                            .padding(6)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if nft.isMoving {
                        Image(systemName: nft.artifactMime?.hasPrefix("audio/") == true ? "speaker.wave.2.fill" : "play.fill")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(.black.opacity(0.6)))
                            .foregroundStyle(.white)
                            .padding(6)
                            .help(nft.artifactMime?.hasPrefix("audio/") == true ? "A sound: the tile shows its cover image" : "A video: the tile shows its still image")
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if nft.balance > 1 {
                        Text("×\(nft.balance)")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.black.opacity(0.6)))
                            .foregroundStyle(.white)
                            .padding(6)
                    }
                }
            Text(nft.name)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .help((nft.isLayer2 ? "On Etherlink\n" : "") + "\(nft.name)\n\(nft.contract) #\(nft.tokenId)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(nft.name + (nft.isMoving ? ", video or sound" : "") + (nft.isLayer2 ? ", on Etherlink" : ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var thumbnail: some View {
        if nft.imageURLs.isEmpty {
            placeholder(systemImage: "photo")
        } else {
            RemoteImage(urls: nft.imageURLs) { image in
                Image(nsImage: image).resizable().scaledToFill()
            } placeholder: { failed in
                placeholder(systemImage: failed ? "photo.badge.exclamationmark" : nil)
            }
        }
    }

    private func placeholder(systemImage: String?) -> some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }
}

#Preview {
    NFTGridView(nfts: (1...5).map { NFT(id: "k:\($0)", contract: "KT1x", tokenId: "\($0)", name: "NFT number \($0)", balance: $0 == 2 ? 20 : 1, thumbnailURL: nil) }, isLoading: false)
        .padding()
}

/// Loads an image through `ImageLoader`, trying each URL in turn.
struct RemoteImage<Content: View, Placeholder: View>: View {
    let urls: [URL]
    @ViewBuilder let content: (NSImage) -> Content
    @ViewBuilder let placeholder: (_ failed: Bool) -> Placeholder

    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                content(image)
            } else {
                placeholder(failed)
            }
        }
        .task(id: urls) {
            failed = false
            image = await ImageLoader.shared.image(for: urls)
            if image == nil { failed = true }
        }
    }
}

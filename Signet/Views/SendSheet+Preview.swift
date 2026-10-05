import SwiftUI

/// Renders the confirm step on its own, for previews and offscreen checks.
struct SendSheetConfirmPreview: View {
    @Bindable var send: SendViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ConfirmTransferView(send: send, network: .mainnet)
        }
    }
}

import SwiftUI

/// Round avatar for an address, from TzKT's avatar service (TzProfiles logo, known-account logo,
/// or an identicon). Falls back to a neutral placeholder on networks without the service.
struct AccountAvatarView: View {
    let address: Address
    let network: Network
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let url = network.avatarURL(for: address) {
                RemoteImage(urls: [url]) { image in
                    Image(nsImage: image).resizable().scaledToFill()
                } placeholder: { _ in
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(.secondary.opacity(0.25)))
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            Circle().fill(.quaternary)
            Image(systemName: "person.fill")
                .font(.system(size: size * 0.45))
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    AccountAvatarView(address: Address("tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N"), network: .mainnet, size: 64)
        .padding()
}

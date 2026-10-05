import SwiftUI

/// Round avatar for an address from TzKT's avatar service (TzProfiles logo, known-account logo,
/// or an identicon). Always mainnet: a TzProfile is a mainnet identity.
struct AccountAvatarView: View {
    let address: Address
    var size: CGFloat = 44

    init(address: Address, network: Network? = nil, size: CGFloat = 44) {
        self.address = address
        self.size = size
    }

    var body: some View {
        Group {
            if let url = Profiles.avatarURL(for: address) {
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
    AccountAvatarView(address: Address("tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N"), size: 64)
        .padding()
}

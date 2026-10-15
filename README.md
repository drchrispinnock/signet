<p align="center">
  <img src="docs/images/signet-256.png" width="160" alt="Signet: a gold signet ring engraved with the Tezos ꜩ">
</p>

<h1 align="center">Signet</h1>

<p align="center">A Tezos wallet for the Mac.</p>

We are writing a wallet using Claude.AI for Tezos. It is for Macs only.
ChatGPT made the Macintosh App icon.

*Disclaimer:* This is very very new software. There is absolutely no warranty. If it breaks you get to keep ALL the pieces. Use at your own risk. Keys can be kept encrypted with a password (the default on mainnet) or on a Ledger; unencrypted keys on disk are only sensible on test networks.

## Frequently Asked Questions

### Why are you doing this then?

Simply because I haven't attempted a project in Swift using AI before. All the code is written by Claude. Codex is auditing it. It is an exercise in using AI for software development. The winter nights are drawing in. The TV offerings on Netflix and Prime are not what they used to be. Also having a nice shiny wallet for Tezos on the Mac won't hurt anyone.

### What features are done?

**It's still an alpha application, but we have done the following:**

- Account creation
- Mainnet and test network integration (including quantumnet)
- Banking operations (Send, Receive, Buy, Faucet)
- dApp signing
- Staking and Delegation
- Baking and Governance operations
- Native multisig accounts (compatible with octez-client)
- Basic explorer - transactions, assets and NFTs
- Session-only key store
- Etherlink support. Transactions between tz addresses.

### Will it steal my keys?

Probably not. Codex will be checking what Claude is doing. But of course, you can read the sources too.

### Will you be adding XYZ feature any time soon?

Ping me and we can queue it up. Work on this will be between other things and might fall right down the stack.

### This is only on Macs right? What about other platforms

There might be a Windows version soon. There might also be a Linux version tool. 
Claude tells me I can turn this into an iOS app. I would probably have to remove a few things such as "Buy" to get it into the app store.

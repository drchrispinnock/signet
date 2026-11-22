{id: ID100-introduction_2_Blockchain}
## Blockchains and Cryptocurrencies

{id: ID100-introduction_2_What_2}
## What is Tezos?
xx

{id: ID100-introduction_2_What}
## What is a Wallet?
xx

{id: ID100-introduction_2_What_3}
## What is Signet?
xxx

This probably needs to go in the introduction.
￼What is Baking
￼Fold in material from the baking chapter

Blockchains need participants that produce the blocks. The block production on Tezos is called baking. On other chains it is called mining or validating. The participants are called bakers. In fact we refer to both the systems that do the baking and the people who run them as bakers.

Tezos is a proof-of-stake blockchain. A baker has an account on the Tezos chain, like any other participant. They need to attach their wallet to the baking process to provide a security bond, called a stake.  The block production is scheduled, favouring the bakers with the most stake. They get more opportunities to bake a block. Additionally, bakers attest other blocks produced by other bakers. The security bond is there to provide a guarantee against bad behaviour.

{id: ID100-introduction_2_Other}
## Other Wallets

There are other wallets for Tezos and I encourage you to try them out. I haven't written Signet to rule the world and I would prefer that you used a wallet you are comfortable with. Wallet software is a matter of personal preference. For example, Signet is a desktop wallet and you might prefer to work on your mobile. Here is an overview of some other wallets that support Tezos:

**AirGap** - A mobile wallet with the facility to hold the key in a second mobile, hence using an "Air Gap" security model.

**Kukai** - A Tezos-only web and mobile-based wallet. You can use your Google account or social login to create an account.

**Ledger Wallet** - Desktop and mobile software to work with the Ledger hardware security module. You can use the Ledger with other Tezos wallets, once set up.

**`octez-client`** - A command-line wallet typically used on Linux or Mac. It is part of [Octez](https://octez.tezos.com/), the Tezos blockchain software. The `octez-client` command is typically used by developers and infrastructure users.

**Temple** - A browser extension that works on Chrome and Edge and also a mobile app. It offers a flexible Tezos experience with asset swapping. It recently added EVM support for Etherlink and other EVM-style chains.

**Umami** - Originally a wallet running on the desktop, Umami has evolved into a multi-chain mobile and web wallet.

| Wallet                                                                | Developer                                             | Mobile | Web Browser | Supports                 |
| --------------------------------------------------------------------- | ----------------------------------------------------- | ------ | ----------- | ------------------------ |
| [AirGap](https://airgap.it)                                           | [Papers](https://papers.ch)                           | Yes    | No          | Multi-asset              |
| [Kukai](https://wallet.kukai.app)                                     | Kukai                                                 | Yes    | Yes         | Tezos only               |
| [Ledger Wallet](https://shop.ledger.com/pages/ledger-wallet-download) | [Ledger](https://www.ledger.com)                      | Yes    | No          | Multi-asset              |
| `octez-client`                                                        | [Nomadic Labs](https://www.nomadic-labs.com) *et al.* | No     | No          | Tezos only               |
| [Signet](https://signetwallet.org)                                    | Me                                                    | Soon   | No          | Tezos only               |
| [Temple](https://www.templewallet.com)                                | [Madfish](https://mad.fish)                           | Yes    | Yes         | Tezos, EVM-style chains. |
| [Umami](https://www.umamiwallet.com)                                  | [Trilitech](https://www.trili.tech)                   | Yes    | Yes         | Tezos, EVM-style chains. |

There are other multi-chain wallets that support Tezos.

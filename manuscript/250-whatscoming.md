{#id: 250-whatscoming_1_What}
# What's Coming in Signet

Signet is still under development and I will continue to add features for the foreseeable future. Here are some possible directions.

**User interface enhancements and changes**

The user interface is too wordy and isn't necessarily the best. Over time I will refine it to give the user the best experience.

**Better Octez Connect support**

Octez Connect (formerly Beacon) is the library and infrastructure used to connect wallets to dApp web sites. To connect to a dApp in the current version you have to copy and paste codes to pair Signet with the dApp. I've put in a request to the Octez Connect team to include Signet in the list of applications to make this automatic. Unfortunately we will have to wait for dApp sites to upgrade Octez Connect before we see Signet in the list.

**Better Etherlink/Tezos X support**

At the moment, we support tz addresses on the layer 2. These can be mapped to an EVM address and then that address can be used on the chain with EVM dApps and contracts. We need to add the ability to use a native EVM address in the application. We also need to be able to connect to dApps using EVM addresses, which means adding Wallet Connect support. Generally, EVM accounts need to be treated a first-class citizens.

**TzEL shielded transactions**

TzEL is a smart-rollup for private post-quantum transactions. You'll be able to move your tez into the rollup (called "shielding" them), then transfer them to other accounts. You'll be able to withdraw them (that is "unshield" them) from the rollup. TzEL is available on *Shadownet* and it will soon be available on *Quantumnet*. Signet needs to handle shielding, transfers and unshielding on this rollup. I expect this will be implemented as a third balanced on the main Signet screen. Signet is able to use the TzEL rollup on *Shadownet* today but it is an early implementation. You can enabled Shielded Transactions in the menu. 

**Swapping and obtaining other tokens**

Other wallets support swapping tokens at DEXs in the wallet. We might investigate this in a later release, but you can go to a DEX and connect it as a dApp, as we saw earlier.

**Windows and Linux support**

I am getting Claude to port the application to Windows 11 as a native application. This will take me some time. If there is enough demand, I may port to Linux as well. The problem will be one of maintenance - I will add a feature to the Mac version and then have to port it (or do it independently on the other platforms).

**Mobile support**

Claude tells me it would be easy to make an iOS application out of the current codebase. However, that means using an app store and we would be restricted by their rules. I suspect I would have to remove support for buying tez directly in the app.

**Post-quantum support**

Once Taquito supports tz6 addresses, I will add support for them. They will likely only be used for consensus, but for completeness we will need to use them on the chains.

**Octez.js vs Taquito**

Taquito is the library that does most of the magic under the scenes. I started with Taquito because it added tz5 addresses early and I wanted to get Signet on *Quantumnet.* Octez.js is a fork of Taquito and is likely to have more features to use Tezos X in the future. Therefore I shall probably switch to Octez.js.

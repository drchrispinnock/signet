# What's Coming in Signet

Signet is still under development and I will continue to add features for the foreseeable future. Here are some possible directions.

**User interface enhancements and changes**

The user interface is too wordy and isn't necessarily the best. Over time I will refine it to give the user the best experience.

**Better Octez Connect support**

Octez Connect (formerly Beacon) is the library and infrastructure used to connect wallets to dApp web sites. To connect to a dApp in the current version you have to copy and paste codes to pair Signet with the dApp. I've put in a request to the Octez Connect team to include Signet in the list of applications to make this automatic.

**Better Etherlink/Tezos X support**

At the moment, we support tz addresses on the layer 2. These can be mapped to an EVM address and then that address can be used on the chain with EVM dApps and contracts. We need to add the ability to use a native EVM address in the application. We also need to be able to connect to dApps using EVM addresses, which means adding Wallet Connect support. Generally, EVM accounts need to be treated a first-class citizens.

**Tzel shielded transactions**

Tzel is a smart-rollup for private post-quantum transactions. You'll be able to move your tez into the rollup (called "shielding" them), then transfer them to other accounts. You'll be able to withdraw them (that is "unshield" them) from the rollup. Tzel is available on *shadownet* and it will soon be available on *quantumnet*. Signet needs to handle shielding, transfers and unshielding on this rollup. I expect this will be implemented as a third balanced on the main Signet screen.

**Windows and Linux support**

I am getting Claude to port the application to Windows 11 as a native application. This will take me some time. If there is enough demand, I may port to Linux as well. The problem will be one of maintenance - I will add a feature to the Mac version and then have to port it (or do it independently on the other platforms).

**Mobile support**

Claude tells me it would be easy to make an iOS application out of the current codebase. However, that means using an app store and we would be restricted by their rules. I suspect I would have to remove support for buying tez directly in the app.

**Post-quantum support**

Once Taquito supports tz6 addresses, I will add support for them. They will likely only be used for consensus, but for completeness we will need to use them on the chains.

**Octez.JS vs Taquito**

Taquito is the library that does most of the magic under the scenes.
Currently I'm using Taquito because it added tz5 addresses early and I wanted to get Signet on Quantumnet. I will continue with Taquito whilst it's supported.

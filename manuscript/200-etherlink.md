{#id: 200-etherlink_1_Etherlink}
# Etherlink and Tezos X

In 2023, smart rollups were introduced to the Tezos blockchain. A *rollup* is a means of processing transactions away from the main blockchain, "rolling them up" and injecting them back to the main chain later on. A Tezos *smart* *rollup* is one managed by a computer program, usually written in WebAssembly (Wasm). These rollups are managed by a separate set of servers from the layer 1. There are *operators* which collect together, batch and commit the operations. There are *observers* that just listen to the rollup and record it. There are *endpoints* (also called *nodes*) which wallets and applications use to communicate with the rollup.

Etherlink is the first official rollup on Tezos and it brings an Ethereum compatible virtual machine to Tezos. This means that you can deploy an Ethereum smart contract on the Etherlink rollup without modification. Now Tezos smart contracts (written in a language called Michelson) can be deployed in the rollup and they can interact with the EVM contracts.

Tezos X is the strategic target architecture of Tezos and a potential outcome is a fast, but simple, layer 1 that does settling and staking, together with a rollup compatible with both EVM and Tezos. It's likely that dApps and day-to-day transactions will live on the rollup. The good news is Signet is capable of working with Etherlink and you don't have to understand much about rollups to use it.

On Etherlink, you can have Ethereum-style addresses beginning with 0x and Tezos-style addresses `tz1`, `tz2` and `tz3`. If you have one of these Tezos accounts already, you can use your address on the rollup. There are other ways of getting addresses on Etherlink, but for now this is the only method that Signet supports. One thing to be aware of is that to use your funds on Etherlink, you have to bridge them from the main Tezos chain.

 At the moment, Signet doesn't support dApps on Etherlink, but it will in the future. It supports bridging funds to Etherlink and establishing your EVM address from your Tezos address.

{#id: 200-etherlink_2_Setting}
## Setting up Signet to use Etherlink

To use Signet on Etherlink, first you must enable layer 2 for the network. Go to the `Networks...` menu and enable it. There are Etherlink rollups on *Mainnet* and *Shadownet.* We will do everything on *Shadownet* in this chapter.

Signet holds a default node entry for each one. You can change it to another node if you want. If Etherlink is ever deployed on another test network, Signet will probably have a default node for it, but you can set it in the Networks menu otherwise. Also there are configuration items for the governance contracts. These contracts are used by bakers to vote on Etherlink upgrades. On *Mainnet* these fields are filled out with the production contracts.

![](200/networks.png)

Once you've enabled Layer 2, when you return to the main screen, you will have a balance on the Etherlink network, probably 0tz.

![](200/balance.png)
{#id: 200-etherlink_2_Bridging}
## Bridging funds between Tezos and Etherlink

To move some funds between Tezos and Etherlink is easy and there is a bridge for it. To make it convenient, Signet knows about the bridges on *Mainnet* and *Shadownet.* To bridge funds, choose the account you want to work in and choose `Bridge...` from the burger menu. 

![](200/bridge.png)
Choose the amount that you want to send and click `Bridge`.

![](200/bridgeprogress.png)
Then you can see that your 10tz has moved between the networks. The call to the bridge smart contract is also visible in the transaction list.

![](200/balances.png)
Back on the bridge menu, we can reverse the direction of bridging by clicking the arrow in the middle. This is to bridge funds from Etherlink back to Tezos. At the time of writing, it's early days for this bridge. It doesn't work for Michelson addresses but it will soon. When it does, there will be two methods: Fast and Slow. The Slow method returns your funds in approximately 14-15 days. The 14 days is related to the refutation window in the smart rollup architecture. The Fast method returns your funds immediately but is subject to a fee.
![](200/bridgeback.png)
<!-- we need to understand how the bridge actually works here XXX -->
{#id: 200-etherlink_2_Sending}
## Sending and receiving funds

Sending and receiving funds on the Etherlink network with Tezos addresses is done in Signet in exactly the same way as for the normal Tezos network. Now that we have enabled layer 2, the Send and Receive dialogues have another option to pick the network. You can select Tezos or Etherlink.

![](200/send.png)
To send on Etherlink, simply pick Etherlink in the drop down and send in exactly the same way you did for the Tezos network.

To receive on Etherlink, you can use your `tz1`, `tz2` or `tz3` address.

{#id: 200-etherlink_2_EVM}
## EVM address and receiving funds

<!-- XXX this has changed in Etherlink 8.0. We need to reenable it -->

Now on Etherlink, there are Ethereum-style addresses as well as Tezos addresses. For each Tezos address, there is a derived Ethereum-style address beginning with 0x. To find your 0x address, click the Receive button and choose Etherlink.

![](200/link.png)
The first time you do this, you will need to pay a small fee to link your Ethereum-style address with your Tezos address. Click the Link button, then you will have your 0x address.

![](200/eth.png)
Now users on the Etherlink rollup with 0x addresses can send tez to your account using your 0x address. The original Etherlink users had 0x addresses from the start and used Ethereum-compatible wallets. I'm undecided whether to add support for this to Signet.

{#id: 200-etherlink_2_Connecting}
## Connecting to Michelson dApps

Signet can connect to Michelson dApps on Etherlink. These are the dApps that have been deployed using the native Tezos smart contract language, Michelson. The connection mechanism is exactly the same as for the native Tezos chain and Signet works out which chain the dApp connection request is on.

We saw [TezInvaders](#170-dapps_2_TezInvader) in the dApps chapter. This dApp has versions on Etherlink as well as the native Tezos chain. In fact, TezInvaders was designed to help with Signet development. On either *Mainnet* or *Shadownet*, you can play TezInvaders and participate in the competitions on layer 2, by clicking the layer 2 button `L2`. Then connect your wallet and play as normal.

There will be more applications appearing on Etherlink soon. Work is being done to allow Tezos addresses to use EVM dApps as well. Once the support is in Etherlink, we will add it to Signet as well.

{#id: 200-etherlink_2_Voting}
## Voting in the Etherlink Governance Process

If you are a baker, you can use Signet to vote in the Etherlink Governance process. There is a [slow governance process ](https://governance.etherlink.com/governance/slow)for regular upgrades and a [fast governance process](https://governance.etherlink.com/governance/fast) for security upgrades. There's also a process to vote on who runs the sequencer. In Signet, you can vote on the slow and fast processes. At the moment, you have to do this with the master baking key. In future versions, you'll be able to do it with a delegated governance key. 

The processes have a proposal period and a promotion period. In the proposal period, proposals are made and upvoted like in the layer 1 governance process. In the promotion period, the bakers vote `Yea`, `Nay` and `Pass` (or abstain).

To vote, go to the `Governance` menu (which will only be there if your account is a baker), then click the `Etherlink` tab.
We are going to show you a vote in the recent Etherlink 7.3 fast security upgrade. Captain Stake upvoted the proposal  that was already proposed. Signet found this proposal and he clicked the `Upvote` button. 

![](200/ethgov/upvote.png)

And then confirmed it:

![](200/ethgov/upvote2.png)

He could have made his own proposal by submitting a hash, but at the moment Etherlink proposals are usually made on behalf of the development team. There were enough upvotes to move the proposal into the promotion stage. In this stage, Captain Stake came back and used Signet to vote `Yea` in the election.

![](200/ethgov/promotion.png)

He clicked the `Yea` voting button and then confirmed the vote:

![](200/ethgov/promotion2.png)

Finally, the vote was confirmed on the Etherlink chain.

![](200/ethgov/yea.png)

If you have a delegated governance key and the key is in Signet, you can of course connect directly to the [governance.etherlink.com](https://governance.etherlink.com) site as a dApp and vote that way.



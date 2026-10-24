{#id: 200-etherlink_1_Etherlink}
# Etherlink and Tezos X

In 2023, smart rollups were introduced to the Tezos blockchain. A *rollup* is a means of processing transactions away from the main blockchain, "rolling them up" and injecting them back to main chain later on. A Tezos *smart* *rollup* is one managed by a computer program, usually written in WebAssembly (Wasm). These rollups are managed by a separate set of servers from the layer 1. There are *operators* which collect together, batch and commit the operations. There are *observers* that just listen to the rollup and record it. There are *endpoints* (also called *nodes*) which wallets and applications use to communicate with the rollup.

Etherlink is the first official rollup on Tezos and it brings an Ethereum compatible virtual machine to Tezos. This means that you can deploy an Ethereum smart contract on the Etherlink rollup without modification. Now Tezos smart contracts (written in a language called Michelson) can be deployed in the rollup and they can interact with the EVM contracts.

Tezos X is the strategic target architecture of Tezos and a potential outcome is a fast, but simple, layer 1 that does settling and staking, together with a rollup compatible with both EVM and Tezos. It's likely that dApps and day-to-day transactions will live on the rollup. The good news is Signet is capable of working with Etherlink and you don't have to understand much about rollups to use it.

On Etherlink, you can have Ethereum-style addresses beginning with 0x and Tezos-style addresses tz1, tz2 and tz3. If you have one of these Tezos accounts already, you can use your address on the rollup. There are other ways of getting addresses on Etherlink, but for now this is the only method that Signet supports. One thing to be aware of is that to use your funds on Etherlink, you have to bridge them from the main Tezos chain.

 At the moment, Signet doesn't support dApps on Etherlink, but it will in the future. It supports bridging funds to Etherlink and establishing your EVM address from your Tezos address.

{#id: 200-etherlink_2_Setting}
## Setting up Signet to use Etherlink

To use Signet on Etherlink, first you must enable layer 2 for the network. Go to the `Networks...` menu and enable it. There are Etherlink rollups on *Mainnet* and *Shadownet.* We will do everything on *Shadownet* in this chapter.

Signet holds a default node entry for each one. You can change it to another node if you want. If Etherlink is ever deployed on another test network, Signet will probably have a default node for it, but you can set it in the Networks menu otherwise.

![](200/networks.png)
Once you've done this, when you return to the main screen, you will have a balance on the Etherlink network, probably 0tz.

![](200/balance.png)
{#id: 200-etherlink_2_Bridging}
## Bridging funds between Tezos and Etherlink

To move some funds between Tezos and Etherlink is easy and there is a bridge for it. To make it convenient, Signet knows about the bridges on *Mainnet* and *Shadownet.* To bridge funds, choose the account you want to work in and choose `Bridge... `from the burger menu. 

![](200/bridge.png)
Choose the amount that you want to send and click `Bridge`.

![](200/bridgeprogress.png)
Then you can see that your 10tz has moved between the networks. The call to the bridge smart contract is also visible in the transaction list.

![](200/balances.png)
Back on the bridge menu, we can reverse the direction of bridging by clicking the arrow in the middle. This is to bridge funds from Etherlink back to Tezos. 

![](200/bridgeback.png)
XXX At the moment this bridge doesn't work for Michelson addresses but it will soon. When it does, there will be two methods: Fast and Slow. The Slow method returns your funds in 14 days. The 14 days is related to the refutation window in the smart rollup architecture XXX. The Fast method returns your funds immediately but is subject to a fee. XXX

<!-- we need to understand how the bridge actually works here XXX -->

{#id: 200-etherlink_2_Sending}
## Sending and receiving funds

Send and receiving funds on the Etherlink network with Tezos addresses is done in Signet in exactly the same way as for the normal Tezos network. Now that we have enabled layer 2, the Send and Receive dialogues have another option to pick the network. You can select Tezos or Etherlink.

![](200/send.png)
To send on Etherlink, simply pick Etherlink in the drop down and send in exactly the same way you did for the Tezos network.

To receive on Etherlink, you can use your tz1, tz2 or tz3 address.

{#id: 200-etherlink_2_EVM}
## EVM address and receiving funds

Now on Etherlink, there are Ethereum-style addresses as well as Tezos addresses. For each Tezos address, there is a derived Ethereum-style address beginning with 0x. To find your 0x address, click the Receive button and choose Etherlink.

![](200/link.png)
The first time you do this, you will need to pay a small fee to link your Ethereum-style address with your Tezos address. Click the Link button, then you will have your 0x address.

![](200/eth.png)
Now users on the Etherlink rollup with 0x addresses can send tez to your account using your 0x address. 

At the moment, this is all that Signet can do with Etherlink. More features will be coming soon, including dApp support. This will use a relay service so that Tezos account can use its Ethereum-style address for dApps. Also, the transactions, assets and NFTs tabs will be populated with items from the Etherlink network.

The original Etherlink users had 0x addresses from the start and used Ethereum-compatible wallets. I'm undecided whether to add support for this to Signet.




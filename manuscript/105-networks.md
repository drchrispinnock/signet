{id: networks-material_1_Tezos}
# Tezos Protocols and Networks

{id: ID105-networks_2_Protocols}
## Protocols

One of the key features of Tezos is the ability to upgrade the rules of the network and to do so via a governance process. The set of rules for how the chains works including consensus, transaction validation, smart contract execution and governance is called a *protocol.* As I write this in November 2026, the protocol running on Tezos *Mainnet* is *Ushuaia.* This protocol introduced performance improvements and also some test features such as quantum-resistant accounts (`tz5` addresses). Please see <!-- MARKUPBIBTAG 5a9bea80 -->[10]<!-- ENDMARKUPBIBTAG --> for the full details.

The first protocols were called *Alpha I, II* and *III.* These were used to get the Tezos network working in its early days. Then *Athens* was introduced by governance in May 2019. *Ushuaia* is the 21st upgrade activated via the governance process. The naming convention since *Athens* is to use names of historic cities of the world in alphabetical order.

In principle, any baker can propose a new protocol. In practice, the Tezos core development team work on new protocols. In 2027, there will be a new protocol proposal and as expected its name will begin with V. A baker will propose it and the other bakers will vote on it in the governance process.

Some of the features (e.g. staking) affect users directly. Others are under the hood. All you need to know as a beginner is that Tezos is capable of upgrading very easily and that the bakers vote on the protocol proposals. For more information about the protocols please see the [Tezos website](https://tezos.com/about/governance/) <!-- MARKUPBIBTAG d56b99d2 -->[11]<!-- ENDMARKUPBIBTAG -->.

{id: ID120-networks_2_Networks}
## Networks

The Tezos production network is called *Mainnet.* Most wallets connect directly to *Mainnet* and more users work only on this network. The Tezos coins have real-world value on this network. It's where users send real-life transactions, buy art and use dApps with real tez. *Mainnet* is running the *Ushuaia* protocol.

There are also test networks. On a test network, the coins do not have real-world value, so in theory you can make mistakes and it won't matter. Test networks are the place the people learn about blockchains, where application developers build distributed applications and where the blockchain developers test their software. It's also where new versions of the protocol are tested.

As far as a user and an application are concerned, there is no difference in terms of software, other than perhaps a test network is running a newer version or a different protocol. One main difference however is that on a test network you don't have to invest money to get tez coins. You can get them from a website called a *faucet.* 

You can switch Signet between networks very easy by choosing the network in the selector at the top right of the window:

![](120/networks.png)


There's around five public test networks, each with a different purpose. The long-term test networks allow the users and bakers to build up applications and state over time. 

The protocol test networks are just for testing the current and proposed protocols of Tezos. When the next protocol is ready to be stabilised, there is usually a test network called *Nextnet* for testing it. This network is usually restarted as bugs are found. When a new protocol is under consideration in governance, there is usually an accompanying protocol network. *Ushuaianet* was started when Ushuaia was proposed in the governance process and continues to run so that users can test their applications.

*Weeklynet* is for developers who want to try something out quickly. *Quantumnet* is being used to trial new post-quantum key features on Tezos.

Here is a list of test networks. If you want to try something out as a user, the best network to try is *Shadownet*. For most test networks, the detail is at [teztnets.com](https://teztnets.com).

{column-widths: "15% 10% 75%"}
| Network      | Type      | Purpose                                                                                                                                                                                                                                        |
| ------------ | --------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| *Shadownet*  | Long-term | A production-like network for testing Tezos applications. It runs the same version of Tezos as *Mainnet*. When *Mainnet* is upgraded, *Shadownet* is upgraded soon after.                                                                      |
| *Bakingnet*  | Long-term | A network for testing baking. This network switches to the next version of Tezos about 1-2 weeks before mainnet, to test the switchover process.                                                                                               |
| *Ushuaianet* | Protocol  | This is a network for testing the current protocol. When it was started, it was the proposed protocol and was made available for testing                                                                                                       |
| *Weeklynet*  | Dev       | A bleeding-edge development network running on the development version of Tezos. It starts automatically on Wednesday morning using the last development release of Tezos committed on Tuesday evening. Runs *alpha* the development protocol. |
| *Quantumnet* | Dev       | A post-quantum capable test network. Many things on Tezos change and so a separate test environment is needed. Runs a specific version of the *alpha* protocol.                                                                                |

As a general user of Tezos, the best place for you to try things out is on *shadownet*. 

Signet will work on all of the test networks and of course mainnet. Your accounts will work on all networks, except that some of the new key types like `tz5` will not work on *mainnet* yet. To change the network, you simply click the network name in the top-left of the Signet window. What this really does under the hood is change the network node XXX
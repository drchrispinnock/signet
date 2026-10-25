{#id: networks-material_1_Tezos}
# Tezos Protocols and Networks


This probably needs to go in the introduction.
￼What is Baking
￼Fold in material from the baking chapter

Blockchains need participants that produce the blocks. The block production on Tezos is called baking. On other chains it is called mining or validating. The participants are called bakers. In fact we refer to both the systems that do the baking and the people who run them as bakers.

Tezos is a proof-of-stake blockchain. A baker has an account on the Tezos chain, like any other participant. They need to attach their wallet to the baking process to provide a security bond, called a stake.  The block production is scheduled, favouring the bakers with the most stake. They get more opportunities to bake a block. Additionally, bakers attest other blocks produced by other bakers. The security bond is there to provide a guarantee against bad behaviour.


{#id: networks-material_2_Protocols}
## Protocols

xxx


{#id: networks-material_2_Networks}
## Networks

The Tezos production blockchain is called *mainnet.* By default, most wallets will connect to it including Signet. The Tezos coins, tez, have real-world value on this network. Obviously it is where the action happens, but there are also some test networks. On a test network, the coins do not have real-world value, so in theory you can make mistakes and it won't matter. Test networks are the place the people learn about blockchans, where application developers build distributed applications and where the blockchain developers test their software.

At the time of writing there are at least five test networks, each with a different purpose. The long-term test networks allow the users and bakers to build up applications and state over time. The protocol test networks are just for testing the current and proposed protocols of Tezos. Weeklynet is for developers who want to try something out quickly. Quantumnet is being used to trial new post-quantum key features on Tezos.


| Network                          | Type        | Purpose                                                                                                                                                                                                 |
| -------------------------------- | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| shadownet                        | Long-term   | A production-like network for testing Tezos applications. It runs the same version of Tezos as mainnet. When mainnet is upgraded, shadownet is upgraded soon after.                                     |
| bakingnet                        | Long-term   | A network for testing baking. This network switches to the next version of Tezos about 1-2 weeks before mainnet, to test the switchover process.                                                        |
| ushuaianet, the current protocol | Protocol    | This is a network for testing the current protocol. When it was started, it was the proposed protocol and was made available for testing                                                                |
| the proposed protocol            | Protocol    | TBA. This network will begin with the letter V. When it is being proposed, the team will start this network and users of Tezos will be able to test on it.                                              |
| Weeklynet                        | Dev         | A bleeding-edge development network running on the development version of Tezos. It starts automatically on Wednesday morning using the last development release of Tezos committed on Tuesday evening. |
| Quantumnet                       | New feature | A post-quantum capable testnet XXX                                                                                                                                                                      |

As a general user of Tezos, the best place for you to try things out is on *shadownet*. 

Signet will work on all of the test networks and of course mainnet. Your accounts will work on all networks, except that some of the new key types like tz5 will not work on *mainnet* yet. To change the network, you simply click the network name in the top-left of the Signet window. What this really does under the hood is change the network node XXX
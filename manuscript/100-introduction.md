{mainmatter}
{id: ID100-introduction_1_Introducti}
# Introduction

This is a book about using the Tezos blockchain. Usually a user of a blockchain interacts with it using a *wallet.* Signet is a wallet supporting only the Tezos blockchain. You can send and receive funds on the Tezos network with it. You can interact with applications on Tezos and much more. But before we get into using Signet, let's look at some background. 

The good news is that you don't have to fully understand the background to be able to use Tezos, so feel free to skip over the detail if you want. We will explain the key concepts in this chapter and we will assume that you are a beginner. Our aim is to convey understanding and we will explain the concepts in simple terms. This means we will skip some of the in-depth technical detail, which as a beginner you will not need anyway. Feel free to dip in and out of this chapter, and move straight to [Getting Started](#ID110-starting_1_Getting).

It's very likely that you've heard about Bitcoin. Bitcoin is considered to be the first decentralised currency and was created in 2008. No-one knows the identity of the person who created it, but they were prominent member of the cryptography community. They have since disappeared, even leaving their Bitcoin accounts alone. 

Anyone can use the Bitcoin network to send value to someone else without using a central organisation such as a bank. Furthermore, the ledger that stores the transactions is distributed and fault tolerant.

Under the hood of Bitcoin is a blockchain, which is used to record the transactions on the network. Many computers on the internet hold a copy of the blockchain and these are called *nodes.* Users sign transactions with *wallet* software using public key cryptography and submit them to the nodes. New blocks containing the transactions are created by a process called *mining.*

Since Bitcoin was introduced, they have been other cryptocurrencies and blockchain platforms set up to provide different features. One example is Ethereum, devised in 2013 and launched in 2015, which has smart contract capabilities. A *smart contract* is a computer program stored on the blockchain that runs when a transaction calls it. These can be used in the same way as a traditional contract. For example, you could fund a smart contract designed to implement payroll and have it pay designated users on a payday. Smart contracts are the technology behind NFTs (non-fungible tokens) which you have probably heard about in the context of blockchain art.

Another example is Tezos. Tezos was designed to address some shortcomings in the Bitcoin protocol. It was described in the Position Paper <!-- MARKUPBIBTAG 20cdb1d3 -->[1]<!-- ENDMARKUPBIBTAG --> and White Paper <!-- MARKUPBIBTAG 1d054870 -->[2]<!-- ENDMARKUPBIBTAG --> by one of the co-founders working under the pseudonym L. M. Goodman in 2014. On Tezos, you can also send value to other users of Tezos. It is a fully functioning smart contract platform. You can participate in decentralised finance applications, along with buying digital art and everything you would expect from a modern chain.

One key thing is that Tezos can be easily upgraded and the set of rules for how the chain runs can be changed easily. The changes are subject to a governance process, where key users of the chain vote on new proposals. Tezos launched in 2018 and has upgraded <!-- MARKUPTAG govtimes-->21<!-- ENDMARKUPTAG --> times.

{id: ID100-introduction_2_What_2}
## Blockchain Concepts on Tezos

Tezos is based on blockchain technology, so let's examine this concept first. A *blockchain* is a sequential chain of blocks, starting with a first block called the *Genesis* block. Each block has a header and a list of operations. The header contains information about the block and the operations include things like transactions (actually much more, but we are going to keep the explanations simple). The blocks are numbered, usually from 0 and the block's number is called its *height* or *level.*

A blockchain is designed to be tamper-free. This is done with something called a *hash.* Hashes are used everything in blockchains and cryptography. A hash is a short, fixed-length fingerprint of a piece of data, computed by a one-way function. If the data is changed, the hash will change to.

In a blockchain, each block contains a hash of the previous block. Therefore it's possible to tell if the block has been tampered with or not, because one can check the hash. The Genesis block is the only block not to hold a hash like this because it is the first block of the chain.

![](100/blockchain.png)


The blockchain is stored live on the Internet, on computers running the Tezos software. A *node* is a computer server that keeps a copy of the Tezos blockchain. Some nodes do not keep all the data needed but just enough to participate in the chain. The nodes keep their copy of the blockchain up to date by communicating with each other on a *peer to peer* network, also called a *gossip* network. 

Users submit transactions to a node using a *wallet*. A wallet doesn't hold money or value, but holds cryptographic keys representing the user's account on the chain. We'll come back to this in a minute.

Blockchains need participants that produce the blocks. The block production on Tezos is called *baking*. On other chains it is called *mining* or *validating*. The participants who bake are called *bakers*. In fact we refer to both the systems that do the baking and the people who run them as bakers. 

![](100/networkback.png)


Each baker is allocated slots to produce blocks. They also *attest* other bakers blocks to check for validity. A baker connects to the Tezos network using a node, usually one running on the same server. The nodes gather together submitted transactions into a memory pool (called the *mempool*). These can be transactions directly submitted or shared via the gossip network. When it is a bakers turn to produce a block, they pick the operations from the mempool and add them to the block. The other bakers check the block and it is accepted into the blockchain.

Of course, given that this is happening over the whole internet, it's entirely possible that part of the network doesn't see the block straight away. If for some reason a baker cannot submit a block, another baker in the schedule can take over. There are algorithms in place so that the network can resolve which block should be the accepted one. So, it's possible that a block might be replaced with another one and that might mean that a transaction isn't included. 

On the Tezos network, the consensus algorithm (called *Tenderbake)* guarantees that XXX 2 blocks help!

To summarise, the blockchain is a distributed ledger containing all the transactions. The nodes keep a live online copy of the blockchain. Applications and users submit transactions to the nodes. The bakers add new blocks to the blockchain including new transactions and check other blocks baked by other bakers.

{id: ID100-introduction_2_What}
## Wallets


public key crypto here.











Signet is a wallet.
<!--
{id: networks-material_1_Tezos}
# Tezos Protocols and Networks
-->

{id: ID100-introduction_2_Tezos}
## Tezos Features

Let's circle back and look at what Tezos offers as a blockchain. The original position paper of Tezos describes four shortcomings of the Bitcoin protocol. They are:

1. The Hard Fork problem. For a change or an upgrade on the Bitcoin network, its node operators need to upgrade the software xxx
2. The Proof-of-work mechanism used by Bitcoin uses excessive power, has bad incentives and has high cost for miner operators.
3. Smart Contract support is minimal.
4. Correctness xxx

One of the aims of Tezos was to provide a blockchain wihtout these shortcomings.

Tezos introduced an on-chain governance facility early on in its development. 

Tezos is a proof-of-stake blockchain. A baker has an account on the Tezos chain, like any other participant. They need to attach their wallet to the baking process to provide a security bond, called a stake.  The block production is scheduled, favouring the bakers with the most stake. They get more opportunities to bake a block. Additionally, bakers attest other blocks produced by other bakers. The security bond is there to provide a guarantee against bad behaviour.

{id: ID105-networks_2_Protocols}
## Tezos Protocols and Governance

One of the key features of Tezos is the ability to upgrade the rules of the network and to do so via a governance process. The set of rules for how the chains works including consensus, transaction validation, smart contract execution and governance is called a *protocol.* As I write this in November 2026, the protocol running on Tezos *Mainnet* is *Ushuaia.* This protocol introduced performance improvements and also some test features such as quantum-resistant accounts (`tz5` addresses). Please see <!-- MARKUPBIBTAG 5a9bea80 -->[10]<!-- ENDMARKUPBIBTAG --> for the full details.

The first protocols were called *Alpha I, II* and *III.* These were used to get the Tezos network working in its early days. Then *Athens* was introduced by governance in May 2019. *Ushuaia* is the 21st upgrade activated via the governance process. The naming convention since *Athens* is to use names of historic cities of the world in alphabetical order.

In principle, any baker can propose a new protocol. In practice, the Tezos core development team work on new protocols. In 2027, there will be a new protocol proposal and as expected its name will begin with V. A baker will propose it and the other bakers will vote on it in the governance process.

Some of the features (e.g. staking) affect users directly. Others are under the hood. All you need to know as a beginner is that Tezos is capable of upgrading very easily and that the bakers vote on the protocol proposals. For more information about the protocols please see the [Tezos website](https://tezos.com/about/governance/) <!-- MARKUPBIBTAG d56b99d2 -->[11]<!-- ENDMARKUPBIBTAG -->.

{id: ID120-networks_2_Networks}
## Tezos Networks

The Tezos production network is called *Mainnet.* Most wallets connect directly to *Mainnet* and more users work only on this network. The Tezos coins have real-world value on this network. It's where users send real-life transactions, buy art and use dApps with real tez. *Mainnet* is running the *Ushuaia* protocol.

There are also test networks. On a test network, the coins do not have real-world value, so in theory you can make mistakes and it won't matter. Test networks are the place the people learn about blockchains, where application developers build distributed applications and where the blockchain developers test their software. It's also where new versions of the protocol are tested.

As far as a user and an application are concerned, there is no difference in terms of software, other than perhaps a test network is running a newer version or a different protocol. One main difference however is that on a test network you don't have to invest money to get tez coins. You can get them from a website called a *faucet.* 

There's around five public test networks, each with a different purpose. The long-term test networks allow the users and bakers to build up applications and state over time. 

The protocol test networks are just for testing the current and proposed protocols of Tezos. When the next protocol is ready to be stabilised, there is usually a test network called *Nextnet* for testing it. This network is usually restarted as bugs are found. When a new protocol is under consideration in governance, there is usually an accompanying protocol network. *Ushuaianet* was started when Ushuaia was proposed in the governance process and continues to run so that users can test their applications.

*Weeklynet* is for developers who want to try something out quickly. *Quantumnet* is being used to trial new post-quantum key features on Tezos.

Here is a list of test networks. If you want to try something out as a user, the best network to try is *Shadownet*. For most test networks, the detail is at [teztnets.com](https://teztnets.com).

{width: "100%", column-widths: "20% 20% 60%"}
| Network      | Type      | Purpose                                                                                                                                                                                                                                        |
| ------------ | --------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| *Shadownet*  | Long-term | A production-like network for testing Tezos applications. It runs the same version of Tezos as *Mainnet*. When *Mainnet* is upgraded, *Shadownet* is upgraded soon after.                                                                      |
| *Bakingnet*  | Long-term | A network for testing baking. This network switches to the next version of Tezos about 1-2 weeks before mainnet, to test the switchover process.                                                                                               |
| *Ushuaianet* | Protocol  | This is a network for testing the current protocol. When it was started, it was the proposed protocol and was made available for testing                                                                                                       |
| *Weeklynet*  | Dev       | A bleeding-edge development network running on the development version of Tezos. It starts automatically on Wednesday morning using the last development release of Tezos committed on Tuesday evening. Runs *alpha* the development protocol. |
| *Quantumnet* | Dev       | A post-quantum capable test network. Many things on Tezos change and so a separate test environment is needed. Runs a specific version of the *alpha* protocol.                                                                                |

As a general user of Tezos, the best place for you to try things out is on *shadownet*. 

Signet will work on all of the test networks and of course mainnet. Your accounts will work on all networks, except that some of the new key types like `tz5` will not work on *mainnet* yet. To change the network, you simply click the network name in the top-left of the Signet window. What this really does under the hood is change the network node XXX

{id: ID100-introduction_2_Other}
## Other Tezos Wallets

There are other wallets for Tezos and I encourage you to try them out. I haven't written Signet to rule the world and I would prefer that you used a wallet you are comfortable with. Wallet software is a matter of personal preference. For example, Signet is a desktop wallet and you might prefer to work on your mobile. Here is an overview of some other wallets that support Tezos:

**AirGap** - A mobile wallet with the facility to hold the key in a second mobile, hence using an "Air Gap" security model. The wallet application is called AirGap Wallet and the key store is called AirGap Vault. You can run the Vault application on a spare offline mobile phone, keeping your keys off the Internet.

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

There are other multi-chain wallets that support Tezos. Also we encourage you to look at other chains. There are some recommended books in the Further Reading section at the end of the book.

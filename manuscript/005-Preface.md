{#id: 005-Preface_1_Preface}
# Preface

[Tezos](https://tezos.com/) is an environmentally friendly proof-of-stake blockchain with on-chain governance. [Signet](https://signetwallet.org) is an open source wallet application for Tezos available for the Mac. It's been written entirely with AI tools. In fact, as I type this preface (into an application I've also written with AI), I haven't written or read a single line of code. Some of my colleagues might say that this is a good thing.

A blockchain wallet is the user's interface to the blockchain. It is where they store their cryptographic keys. These keys represent their accounts on the blockchain. The wallet is also where they sign operations. But it can be more. It can display information about the user's balances and their assets. Signet has been in development since 5th October 2026, but it can already do most things a wallet should.

In this book, we will tell you a bit about Tezos and how to use the Signet wallet to interact with Tezos. By the end of the book you will have set up an account on Tezos, be able to send and receive coins, and be able to interact with distributed apps too. You'll be able to buy and sell artwork on NFT sites. Also you'll be able to buy and sell other assets on the chain.

You will need a Mac computer and some patience. Buying cryptocurrency for the first time can take a few days due to cooling off rules. It depends where you live of course. But you can practice on the test networks. It's better to make mistakes on the test networks where the coins have no value, than on *Mainnet* where the coins do. 

I wish you luck in your journey on Tezos and on blockchain generally.

Chris Pinnock  
5th November 2026

{#id: 005-Preface_1_AI}
# Developing Signet

Before we start, I want to tell you a story about AI application development. I'm going to tell you how I developed Signet. You can skip over this if you like. I'm going to use a lot of terms, which you might not understand. What I want you to take away is this: it's incredibly easy to get an application written using AI tools, provided you know what you want and you can be descriptive.

Recently, I've had urge to write an application using AI. Over the summer, I'd tried to use Claude Code to write a graphical Tezos wallet based on `octez-client`, the command-line wallet. I managed to get something usable but the user interface was not good. Most Tezos wallets use the library Octez.js (or Taquito). This library has many functions to interact with the Tezos blockchain. I asked Claude to replace the `octez-client` interface with the library but later abandoned the project and moved on to other things. The point here is that I didn't start off with a good enough design and I'd let Claude do the work. 

For some reason, I got the urge to pick up the project on Monday 5th October 2026. It would be a wallet for Tezos, but this time it would be different. I started a blank GIT repository, mulled over a few ideas, and picked up a pencil and drew a user interface. It was probably the least interesting user interface ever designed, but here it is:

![](005/paper.png)

I wanted a "burger" menu for options, details about my account (an alias MyWallet, my address and my .tez name), buttons to Send, Receive, Buy and Sell, then my balances on Tezos and Etherlink. Also at the bottom would be my NFT collection. I wrote a very [simple specification](https://github.com/drchrispinnock/signet/blob/main/docs/spec/SPEC.md). You can find this in the source tree of Signet, but here it is:

- I will ask Claude to write a simple Tezos Wallet.
- It should run natively on the Mac and the source should be compilable by XCode. Swift is preferred.
- It needs to support multiple addresses and all Tezos address types tz1, 6
- It should use the Taquito library where possible to talk to the chain
- The default screen is in the file EXAMPLE.png *(the picture above)*
- Top left is the wallet alias (set by the user when the wallet is created) and the wallet tz address shortened (e.g. tz132...4N). There should be a copy button next to the address. On the right, should be any Tezos Domain aliases.
- Then four buttons: Send, Receive, Buy, Sell
- Then the key assets: The Tezos balance, then the Etherlink balance (don't worry about the address at this stage), also other balances will appear here.
- At the bottom we should drag in NFT thumbnails.

I ran `claude init` and it read the specification. I set up Claude to use Fable. Claude asked a few questions, and then developed a layout resembling the diagram above. And from that point onwards, the rest was a conversation with AI about how I wanted a Tezos wallet to look. Once we had the layout, I quickly added menu items to Create a wallet and Rename it. 

From the beginning I decided to use the same on-disk format as `octez-client`. On a cold start, Signet will offer to import the directory into its configuration, reusing the keys from the command-line wallet. In fact, originally I wanted Signet to share the directory with `octez-client`, but thought better of it. You can use the Signet wallet files with `octez-client` by running it with `-d ~/.signet`. 

Also from the beginning, I got Claude to implement backups. Signet backs up the wallet files when it starts and keeps 10 generations by default. This is to avoid any catastrophes and key loss, which to be fair I haven't had yet.

After some vibe-coding, I had the first version of Signet. It was based on the Taquito library. It could connect to both *Mainnet* and *Shadownet*, but not do very much else. It was integrated to the tzkt block explorer's profile service, so icons and names were taken from there if relevant. The first button I implemented was `Receive`. 

Here is a screenshot from version 0.1 of Signet. The NFT view was done early on and has only had one refinement since. Also the balance lookup was there too. I removed the Etherlink balance to begin with - this would come later on.
![](005/signet-v0.1.png)
According to Github, I released v0.1 at 2007 on the 5th October 2026, the same day I started the project. At 2053 on the same day, I released v0.2 which included a basic address book and the capability to send tez. 

When I started working for the Tezos Foundation in 2021, I used two desktop wallets on the Mac. One of my biggest frustrations with them was logging into dApps. A dApp is essentially a web site and the site needs a connect from the desktop wallet to sign operations. This is done with a system called Octez Connect (formerly Beacon). A session is established through the Octez Connect infrastructure so that the dApp can request operations from the wallet. This didn't work very well for me then, and I switched to the browser based wallet, Temple.

I decided that Signet must have good dApp support, or there was little point in continuing with it. On Tuesday 6th October, I asked Claude to implement dApp support. Claude started work on it, but we didn't finish it. In fact, there was an obstacle getting it to work. On Wednesday, I had other things to do.

On Thursday 8th October 2026, I logged into X to see that Taquito had added tz5 key support. This is significant because they are quantum resistant keys and quantum computing is a current topic. Once we have a quantum computer available, our traditional crypto keys will not be safe. Recently, the development team launched *Quantumnet*, an experimental post-quantum test network for Tezos. On that Thursday morning over coffee, I realised that I could make the first transaction on *Quantumnet* with a graphical wallet.

I asked Claude to use the beta version of Taquito and at 1335 on the same day, I [tweeted](https://x.com/chrispinnock/status/2108174370967368073):

![](005/tweet.png)
I had generated a tz5 key, used the *Quantumnet* faucet to get some coins and then sent them to another account. Also I'd added recent transactions to Signet as you can see in the tweet. 

According to the Github logs, I did 7 releases on that day - versions 0.3, 0.4, 0.4.1, 0.4.2, 0.5, 0.6 and 0.7. Features that I added:

- Sync names with tzkt profiles service
- Add a tab of deFi assets to the front screen
- Apple package signing (to avoid errors for other users wanting to run Signet)
- Ledger Support - using a key from the hardware wallet
- Buy Tez from Mt Pellerin
- On a test network, Buy becomes Get and integrates directly to the test network faucet.
- Baker key management and governance
- Import keys, seed phrases, export keys and forget accounts
- Fix the dApp Octez Connect work
- I got ChatGPT/Codex to audit the code and did some cleanup
- Automatic updates of the application with Sparkle

Not bad for a days work. Essentially the wallet was fully functional on the 8th October. And it had operations to make life for a baker easier. You can keep your master baking key in Signet (or on a ledger of course), delegate consensus and companion keys to ones on your baker, and handle all your baking parameters in Signet. 

Buying tez worked via a widget with Mt Pellerin. The only disadvantage is the cooling off periods, so it took me 7 days to receive the tez (which I did). On a test network, you don't buy tez, but why not make it easy to get tez? I integrated the test networks faucet into Signet so that users can easily get tez on accounts.

Then I took a day off.

On Saturday 10th October, I spent the day ferrying people around in my car, but I had a couple of hours free in the afternoon. One thing that is missing from most Tezos wallets is multisig account support. A multisig account is one where more than one account signs the operations. You can have a committee of accounts as signers and at deployment time, choose how many are needed to sign the transactions. For example, you can set up a multisig account with 5000tz with 5 signers of which 3 are needed. The Code Development team implemented multisig recently, using a smart contract and by adding commands to `octez-client` to make it easier to use it.

I asked Claude to get me a list of commands to use a multisig wallet using `octez-client`. It wrote me a nice "how to" document, which I tried myself. I summarised it in a [text file](https://github.com/drchrispinnock/signet/blob/main/docs/spec/multisig.txt). I decided we needed four new menu items, Create Multisig (to create a new multisig account), Add Multisig (to add an existing multisig contract to Signet), Sign a multisig transaction and Submit a multisig transaction. Claude read the Octez sources and figured out how to implement these functions.

At 1633, I released Signet v0.8 with multisig account support. (On 12th October, I made a [video demonstrating multisig](https://www.youtube.com/watch?v=CV-jszi9uuk&list=PLaeBlcwTd5PY&index=5) and showed that the smart contracts are the same as the ones originated by `octez-client` for multisig accounts.)

In the evening, I ran a source code audit on ChatGPT/Codex and got Claude to fix the issues. Codex finished any outstanding problems. This was release v0.8.1 at 1939.

I took a break on the Sunday and resumed on Monday 12th. The good thing about using an AI agent is it is essentially like a member of staff. You tell it what you want and you tell it when to come back to you with questions. I haven't turned off the checks with Claude yet, because I'm using a machine that I use for other things. But if I had, it would have sped things up even more.

On Monday 12th, I did some further audit with Codex (v0.8.2), added support to forget a key when Signet exits, added the ability to fund a multisig at creation in the UI and added *Ushuaianet* to the list of test networks (v0.8.3). At this point, Signet could participate on the production network *Mainnet* and all the test networks for Tezos. 

 Etherlink is a smart rollup on Tezos and you can deploy an Ethereum smart contract on it. You can use Ethereum-style accounts on it too - these are addresses that start with 0x. They use the same cryptographic curve to Tezos's tz2 addresses and so you can use your tz2 key pair on Ethereum (and Bitcoin and other Ethereum-based chains). I'd wondered whether this was the right starting point. But recently there was an update to Etherlink that added Michelson smart contracts. These are contracts that already run on Tezos. Also, since the update you can use tz1, tz2 and tz3 Tezos addresses on the Etherlink via the Michelson interface. Then you can used a derived 0x address to communicate with the Ethereum-style contracts.

I cannot remember in the timeline when I did this, but I had a call with Thomas Letan to talk about this interface. As a result of that call, I decided this style of address was the right one to start with on Signet. There would be no need to create new addresses and the Taquito library should be able to use the Michelson interface on Etherlink as it uses a similar remote procedure call scheme (RPC) to the Tezos layer 1 RPC.

On Monday 12th at 1725 I released 0.9 which included support to show the Etherlink balance of the account. Then about 2 hours later, I had bridge integration, so that a user could bridge tez from their layer 1 account to Etherlink. According to Github I did a release at 535 on Tuesday 13th - this is entirely possible as my sleep patterns were disturbed that week. The release included send and receive of tez between Tezos addresses on the Etherlink rollup. Also I added a switch to hide Etherlink in the wallet.

The Etherlink work was done with about 30 minutes of Thomas's wisdom, a bit of thought on my part to design it and then Claude reading source code and documentation.

There were several other releases that week. Features included:

- A network settings page, so that the node, block explorer, tzkt API, the faucet (on a test network) could be set for each network
- Signet attempts to check that the connected node is on the correct network (except for a custom network)
- Etherlink account linking - to create the corresponding 0x address from a tz1, tz2 or tz3 address.
- Helper links to Coinbase, Kraken and Transak to buy tez
- Another audit and tidy up by Codex

Unfortunately I had to use links to Coinbase, Kraken and Transak for buying. Transak offer a widget that can be embedded into Signet, like the Mt Pellerin one, but I have to get a developer API key and I want to avoid too much administration at the moment.

On Thursday 15th, I was talking with some colleagues about other Tezos features under development. One big feature is the [Tezos Encrypted Ledger (TzEL)](https://tzel.tezos.com). On the Thursday, I had a quick conversation with Arthur about it and on Friday, had a 30 minute meeting with Devon, who had set up the infrastructure on *Shadownet.* TzEL is a rollup and you move tez into it, much like you do with Etherlink. On TzEL you can make private transactions using quantum keys and signing. Having had these conversations, I asked Claude to start researching. I decided that I needed three new functions: 1. Shield tez (where you bridge tez into the rollup), Unshield tez (where you bridge tez from the rollup) and 3. Send shield transaction (where you can send tez to another participant using a shielded transaction).

It wasn't until the following week, that I really got started. The Shield transaction took a day of Claude researching and me approving operations. Originally it wanted to use the command-line wallet that comes as part of the TzEL software. But I told it that it could not do this and that it must implement the feature itself. By the end of the day, I could move tez into the TzEL rollup. By Wednesday 21st, I'd released v0.9.6 with TzEL support. You can turn it on and off in Signet, and by default it is off, but it is there. As far as I now, no other graphical Tezos wallet supports TzEL.

Skipping back a bit in the timeline, I decided that Signet should have a manual. On the 12th October, I added a manuscript folder to the Signet source code and two special branches for the book. I then added a book to Leanpub. If you are reading this, you are reading that book in some form. Since 21st October, I have focused on writing up the Signet application in this book. 

It's been a good exercise for me and also for Signet, because I've found a few bugs along the way. When I found a bug, I've stopped and asked Claude to fix it. Then continued with the writeup. 

Signet will continue to develop. Etherlink is very much a second-class citizen in Signet. I need to add features to it and maybe the ability to use 0x addresses directly. There is relay service that allows a Tezos wallet to use EVM dApps on Etherlink, and this will probably be my next project. I suspect the TzEL implementation will change over time and so Signet will need to change with it. There will be new features as Tezos develops. 

It has, of course, been developed solely by AI and the source code hasn't been reviewed by humans. Does this matter? Maybe. I might get an audit done in the future. 

Also, it is Mac only. Now I only know three people in my immediate circle of family and friends that don't use Macs. In fact a few years ago when I broke my arm and the X-rays were supplied in a Windows-only format, I asked my neighbours if I could borrow their Windows machine. No-one in my road has Windows. They use Macs. However, my road is not the world. I intend to ask Claude to port Signet to Windows. Maybe Claude will port it to Linux too. Let's see.

I finished the first draft of this book on XXX. That's only XXX weeks after I started the Signet project. I wanted to tell you this story because it is an example of the new AI world we live in. You can build an application on your computer rapidly using Claude or Codex or other tools. You need to be as prescriptive as possible. Tell the AI tool what you want. Draw it pictures. Tell it what you don't like and tell it what you do like. Eventually you'll get the application you need. 

I'm typing this text into [Markup](https://github.com/drchrispinnock/markup), a Markdown editor that I got Claude to write. It has a formatted view and a markdown view - you can write in both. It handles images, formatting, hyperlinks, tables, citations and crosslinks. It is the editor I've always needed. And I wrote it in hours.

But let's get back to the main topics. We are here to show you how to use the Tezos blockchain with the Signet wallet. I hope you enjoy reading this book, learning about blockchain. But I also hope it will inspire you to look further into AI tools if you haven't already.




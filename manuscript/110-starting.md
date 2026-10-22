{#id: 110-starting_1_Getting}
# Getting started

{#id: 110-starting_2_Installati}
## Installation

Signet is an open-source project and the source code is available from [Github](https://github.com/drchrispinnock/signet). At the moment it's for Apple Mac's only. It is written in Swift and is built with the standard Xcode tools from Apple. Pre-built binaries are available from the [release page](https://github.com/drchrispinnock/signet/releases). At the moment, it is not in the Mac AppStore.

To install Signet is the same as most stand-alone Apple Mac applications: download the latest version and move it to the application folder. Go to the release page and download the DMG file. Click the file in your Downloads directory and your Mac will open it. Drag the Signet application into your applications folder. 

![](110/finder.png)

On the first run, you will get this message because it is a stand-alone application from outside the AppStore:
![](110/warning.png)
<!-- XXX we need a way of providing some certainly on this XXX XXX GPG signing XXX -->
Click Open and continue.

{#id: 110-starting_2_Running}
## Running Signet for the first time

When you run Signet for the first time, you'll be presented with some options to set up an account for use on the Tezos network. Many wallets start from cold and assume you'll want to create a new wallet. When we designed Signet, we assumed that you might have a Tezos wallet already. If you have not used Tezos before, you'll need to `Create a new account`.
![](110/coldstart.png)
<!-- XXX options need reordering -->
To create a new account, click the option on the menu and you'll move to a dialogue to create a key pair. What you are doing is creating a public-private cryptographic key suitable for use on a blockchain. This option will generate a new key pair which will allow you to use the Tezos blockchain. You can use the tz1 key type for now - we'll cover the other types in a later chapter. Simply choose a name for your address book ("My Account" is the default) and supply a password. The password encrypts the keys on disc making it harder for someone to steal them. If this is your first time to a blockchain and cryptocurrency, welcome. You now have an account on the Tezos blockchain.
![](110/create.png)
There are three other options to start with Signet. We will touch on them briefly now, but will cover them in more detail later on. If you have used Tezos before, you can import an existing account. The import account option allows you to bring your keys from another wallet. First you'll need to export the secret key from the wallet, then paste it into the dialogue below. You choose a name for it and optionally encrypt it with a password. If the key was protected with a password, you'll be asked for it when you import it. 
![](110/secret.png)
Alternatively if you have a recovery phrase, you can use the Recovery phrase tab and import your key there. 

![](110/recovery.png)
If your key is already set up on a Ledger with the Tezos Wallet application installed, you can use the key with Signet. Plug the ledger in and run the Tezos Wallet application, then use the Connect a Ledger option.

Finally, if you happen to have used the command-line wallet `octez-client`, Signet will detect its wallet directory and offer you the option to import it. This option does not appear if the directory is not detected. As it happens, Signet's wallet directory is compatible with `octez-client`'s.

{#id: 110-starting_2_Key}
## Key hygiene

If you lose your keys, you lose your funds. If someone gets your keys, they have your funds. There's two rules for beginners:

1\. Before you do anything, back up your account keys.

Before you do anything, particularly anything involving monetary value, back up your keys. You may think: "Whatever, I'll do it later". No, please do it now. To do this in Signet is easy. Go to the Operations menu and choose `Export secret key...`.

![](110/export.png)

You can press the view button to look at it and write it down. Or you can use the copy facility to copy and paste it somewhere. The best way to back this up is write it down on paper. Keep two copies in a two safe and different places. We will go into more detail on key storage later on. But please do this step before you do anything involving real-world value. 

2\. Don't get too attached to your account.

There's a temptation to treat your crypto account like a bank account. Your main bank account details probably haven't changed for years. Don't get too attached to your crypto address. You can make a new one very easily. With your first account, use it to try things out and test things. Once someone knows that this account is yours, they will know forever and they will be able to see all your transactions on the chain and know they are yours. When you've done a bit of experimenting, it might be worth generating some keys for different purposes. Perhaps you want to buy some NFTs and show your collection? Well, why not have a seperate key for that?

{#id: 110-starting_2_Navigating}
## Navigating around Signet

The main screen of Signet has four buttons, a burger menu and information about your account. At the top-level, is your account alias (in this case `My Account`) and a shortened Tezos address beginning `tz1`. You can copy the address by clicking the icon next to it. This is the address that will be used on the chain. The account alias is your name for the address and it is only known by your wallet software. It's a way for you to label your account. The account picture comes from your account's picture on the tzkt explorer.

By dropping down next to `My Account`, you can switch between accounts if you have more than one.

On the right is the network name *mainnet*. This is the production Tezos network. You can drop this down and switch to another network, usually a test network. We'll cover networks in a section below. Below these are four buttons: Send, Receive, Buy and Stake. Send is for sending tez coins to other accounts. Receive is to get details about your Tezos address so that others can send coins to you. Buy takes you to a menu to buy tez from a centralised exchange. Stake is for delegation and staking, and we will cover these much later.


![](110/main.png)
The burger menu on the top-right can also be found in the Mac menu bar. Click Operations and you will get the same options.

Before we cover the message in the middle, the three tabs in the second half of the dialogue show information about the account. Recent transactions will show your transactions including sends, receives and calls to smart contracts. Assets will show your defi assets and NFTs will show the NFTs that you have purchased. 

At the very bottom is the name of the network node we are using to connect to the Tezos network. The green indicator says it is healthy.

The message "Key not found on chain" is there because we have not received any tez on *mainnet* yet. Before we go and get some tez, let's look at a more interesting account. This is Captain Stake's account. He has some transactions:

![](110/recenttx.png)


Some defi assets:

![](110/assets.png)


And some NFTs. These are artworks purchased from various NFT sites. We will purchase some artwork in the [Distributed Apps ](#170-dapps_1_Distribute)chapter below.

![](110/nfts.png)


You can see the same screens. Go to the little burger menu top-right and choose `Add address` and paste in 

```
tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N
```

This should resolve as Captain Stake. Signet looks up addresses on the block explorer. and suggests names for them for your address book. You'll then be able to see the same screens as above by switching to the account. Note that this is just an address book entry - you don't have his secret key.

{#id: 110-starting_2_Getting}
## Getting your first tez

In the first days of cryptocurrencies, one would have to find someone else who had some and persuade them to give you some usually for cash. Things are different now. There are *centralised exchanges* offering cryptocurrencies in exchange for money (or *fiat currency*). Three examples are [Mt Pellerin](https://www.mtpelerin.com/), [Coinbase](https://coinbase.com/) and [Kraken](https://kraken.com/). There are some things to be aware of:

1. Buying tez or any cryptoasset for the first time might require significant patience on your part.
2. In your country, there may be laws around purchasing cryptocurrencies. I'm afraid it's up to you to find out what is possible where you live.
3. You will have to provide details about yourself when you buy cryptocurrency. It is increasingly difficult to buy cryptocurrencies anonymously.
4. There may be some waiting times between signing up to a centralised exchange and being able to trade. There may even be waiting times between purchasing and receiving the coins.


For example, in the UK there is a legally required cooling off period when signing up at a centralised exchange. Such exchanges are required to show a disclaimer such as [this one](https://www.kraken.com/legal/uk/disclaimer):

![](110/kraken.png)
Make sure you read and understand the disclaimer. The key thing is that UK government wants it citizens to understand that there are risks involved in crypto investments and that there is no central bank to help with mistakes. Similarly cryptoassets are not protected in the UK in the same way that some savings accounts are.

To get Tez in your new Signet account, you can use the `Buy` button. Click the button and you will be presented with some options:

![](110/buy.png)

The provider is selectable and so is the currency. In my case I'm using United Kingdom pounds sterling (GBP) and Mt Pelerin. Clicking `Continue` takes us to a dialogue where we can choose how much tez we want to buy. Clicking `Buy` takes us to an account signup process. If you are sure you want to buy tez, you can follow this process and use your credit card to get some tez. Note that you might have to wait up to seven days to receive your tez - it depends on where you live and how much information you provide about yourself. If you'd rather not use the widget, you can click the `Open in browser instead` button and use your web browser.

![](110/mtpellerin.png)
Mt Pelerin is the only provider that is directly integrated into Signet. Unfortunately they don't serve every country of the world and the USA is one country that is not served. You can pick for 3 others in Signet: Coinbase, Kraken and Transak, but the providers are not integrated. Let's see what happens if we choose Coinbase:

![](110/coinbase.png)
Here we get a page with our address details, instructions and a button to click. The button will take us to the Coinbase web site. You'll have to sign up there, buy the tez and transfer it to your wallet.

Now I could improve this piece of Signet and in fact Transak will allow wallets to embed it, as will other providers. But that requires some extra work and developer API access. This may come later on depending on demand for the feature.

{#id: 110-starting_2_Getting_2}
## Getting tez on a test network

If you don't want to spend any money at this stage, you can always use a test network. When you switch to a test network in Signet, the Buy button becomes a Get button. A test network usually has a *faucet* that gives out tez to participants. At the tez do not have real-world value, this is possible. Signet is integrated with the faucets on the test networks. 

![](110/faucet.png)

The best test network to try things on for a beginning is *shadownet.* Change to *Shadownet* by clicking on *Mainnet* and choosing *Shadownet* from the drop-down. The Buy button will now be a Get button. Click it, choose an amount of tez and click `Request` to get the tez. It takes a little while because there is a "proof-of-work challenge" to do to stop people draining the faucet of funds. Signet takes care of this for you. You can request more funds or click `Done` when you have finished.

After a minute or two, you will have some tez in your account.

![](110/funds.png)
Now that you have some tez coins, you can truly use the Tezos blockchain. You can work through the book on *Shadownet*, or with care on *Mainnet.* Remember that there is no central body to help you if you make a mistake, so double check everything before you make a transaction. Measure twice, cut once.



{#id: 170-dapps_1_Distribute}
# Distributed Apps

*Distributed Apps* (*dApps*) are applications that interact with the blockchain. As a beginner, you'll come as across these as sites to buy digital artwork or at a *distributed exchange (DEX)* to swap tez with other coins. There are other applications of course. In this section, we will connect Signet to the art site [Objkt.com](https://objkt.com) and purchase a piece of art.  We will also swap some tez for another coin at the DEX [Quipuswap](https://quipuswap.com) and also at the cross-DEX aggregator [3route](https://3route.io/).

{#id: 170-dapps_2_Connecting}
## Connecting to a dApp

Signet uses [Octez Connect](https://octez-connect.tezos.com) (formerly called Beacon) to connect to dApp websites. We will go through the full process with Objkt.com and 3Route, but here are some things to be aware of. On dApp websites, there will be a button to `Sign in`, `Connect Wallet` or `Sync`. If you click on this, a dialogue will appear. Sometimes it will ask you which style of connection to use - choose Beacon or Octez Connect. Then usually there will be a popup asking you which wallet you use.

![](170/beacon.png)

<!-- Waiting -->
At the writing, Signet is not on this list, but you can still connect to these sites if they will give you a QR code for the connection. Select `Show QR Code`, then `Octez Connect` if necessary, then there will be a barcode on the screen. You can copy the value to the clipboard.

Then in Signet, choose `dApps..` from burger menu. In the first dialogue, you will be able to paste the pairing code to connect Signet to the dApp website.

You will always be able to use this method to connect Signet to a dApp, but in the future, Signet will be on the list of wallets. You'll be able to choose it there and the Signet application will automatically receive the pairing code without you having to worry about it.

{#id: 170-dapps_2_Buying}
## Buying an NFT from Objkt

We will cover what a non-fungible token (NFT) is more precisely at the end of this section. For the purposes of this exercise, you can think of an NFT as being a unique record of ownership of a digital asset. We are going to buy a piece of digital art from Objkt and the ownership will be recorded on the Tezos blockchain.

Objkt is the largest digital art marketplace on Tezos. At the time of writing there are over 7 million pieces of art on the site. You can use the site to buy and sell artworks, but also to showcase your work too. The items sometimes have a fixed price and others you can make offers. There are also auctions. Once you have connected Signet to the Objkt site, you can buy, sell or participate in the auctions by signing transactions.



This time, we are going to buy *[Vespera Blackthorn](https://objkt.com/tokens/KT1Hg4HcS78G8HoJjk74oeCDN7nmS6mYJvvp/11)* by the artist Monika (monikasart.tez).

![](170/vespera.png)

Let's connect our wallet. On objkt.com, I click `Log In`, then I choose "Log in with Tezos wallets",  Show More, Show QR Code, then choose Beacon. Click Copy to clipboard.

![](170/objkt-code.png)

In Signet, choose the account you want to buy the NFT from. I'm using a new account with 10tz. Then in the burger menu, choose `dApps...`. Paste the code into the dialogue and click `Pair`.

![](170/objkt-signet-pair.png)

You'll see a connection request dialogue from Objkt. Choose `Connect`.

![](170/objkt-connect.png)

Then choose `Sign` to sign the connection transaction.

![](170/objkt-sign.png)

You should now be logged in with your account. Choose `Continue` on objkt.com if needed. We started our login on a specific piece of art. We can now buy this. Scroll down to `Buy from artist` and click it.

![](170/objkt-buy.png)

Choose the tz price, in this case 6.66tz. Click `Buy`.

![](170/objkt-buy2.png)

Then Signet will receive a request to sign the transaction. In this case I approved it.

![](170/objkt-signet-approval.png)

And the NFT was mine. The transaction is in the list:

![](170/objkt-signet-tx.png)

And also appears in the NFT tab in Signet:

![](170/objkt-signet-nft.png)

I'm the proud owner of the NFT.

If I click the icon top-right on objkt.com, I can go to my Profile. Under the `Owned` tab, I can see the purchase as well as in my wallet. Top right on the thumbnail are three dots. Click this and choose `Properties`

![](170/verpera-properties.png)
There are details about the image on the objkt site. The image is a PNG file. The royalty rate is 25% which goes to the artist in this case. You can see when the token was minted (i.e. created) and the smart contract used to record the ownership on chain. Additionally there are download links for the image from Objkt's asset server and the IPFS service (more on this below).

You can do various other things here with the NFT. For example, you transfer it another account on the chain. You can even burn (i.e. destroy) the NFT if you want to - it's your property.

Let's end the section with some terminology about NFTs.

A *fungible token* is a digital asset that can be interchanged with another one of the same type and value. A tez coin is an example of a fungible token. A *non-fungible token (NFT)* is one that represents a unique digital token that represents ownership of an item or asset. We will be purchasing a piece of art and we will receive an NFT to show our ownership. We can sell or transfer this NFT.

Note that the artwork usually too big to be stored on the blockchain itself, but the NFT is on the blockchain and proves our ownership. The art is stored on a distributed file service called the *interplanetary file system (IPFS)*.

Although it may be possible to buy more than one copy of each artwork, each one has a unique record of ownership on the chain. So an NFT is unique in this sense.

NFTs are implemented as smart contracts and often there are some interesting rules that don't happen for physical art. For example, if you sell a piece of artwork on-chain, the smart contract might have a provision for the creator. This means the artist gets a cut of every sale of their artwork, despite not owning it.

People tend to refer to digital art whose purchases have been recorded on blockchains as NFTs, but it is the record of ownership that is the NFT really.

{#id: 170-dapps_2_Minting}
## Minting an NFT at Teia

[Teia](https://teia.art) is another art NFT site on the Tezos blockchain. It's based on the *hic et nunc* NFT marketplace that is no longer with us. You can buy and sell NFTs there. We are going to upload a piece of art and mint an NFT to represent the ownership on chain. You can do this at Objkt as well, but I want to show you an alternative site on Tezos. Using the terminology of making coins, we will *mint* the NFT. On blockchains, creating assets is called *minting.*

First we go to the Teia site. Top right there is a button called `Sync`. Click this and connect the dApp to Signet. Do this in exactly the same way we did for Objkt. Choose `Show More`, then `Show QR Code`, then choose Beacon. Click Copy to clipboard and paste the value into the dApps menu in Signet.

Now we are logged into Teia. I'm going to mint a piece of artwork of Ms BLS and Quantum Man, who have been spending a lot of time together recently. Here is the artwork:

![](170/blsquantum.png)

On Teia, click the burger menu and under Create, choose `Mint`. 

![](170/teiadetail.png)

I fill out the detail - the name of the artwork, a description of it and some tags. I'm going to mint 5 editions of it, which means there will be 5 of these available on the network. I'm setting the royalties to 10%. If the artwork is sold by someone else later on, I will receive 10% of the proceeds (despite not owning it anymore). Under Artefact, I upload the image and click `Submit`. Then I can preview my submission:

![](170/preview.png)
Scrolling down and checking all the details, I click `Mint`. Then Signet receives a request for signing the operation:

![](170/teiasign.png)
After this Teia mints the NFT and asks me how many I want to swap. This lists them on the Teia marketplace. I want to swap 4 and I'm going to price them at 1tz. I fill in the detail and sign the operation in Signet.

After some time, the NFT appears in my NFT view in Signet.

![](170/nftview.png)
On the burger menu at Teia, you can go to your profile and view all your creations. The activity tab will show you the create and list operations that we just did:

![](170/createandlist.png)

Under Creations, click on the NFT that you have minted and it will show you the information about it. From there you can swap more, transfer any remaining ones and even destroy it with the burn function.

It took a little while for my NFT to be listed but some time later, it appeared on the front page of Teia as a new NFT.

![](170/teiafront.png)
From the listing you can buy one of these artworks for 1tz.

{#id: 170-dapps_2_Buying_2}
## Buying a Tezos Domain

Tezos Domains are text names, such as drchris.tez, used to identify accounts on the Tezos network. It's easier for me to give another user the name drchris.tez than it is my Tezos wallet address. The [Tezos Domains](https://tezos.domains/) project provides a dApp for purchasing these domains. We are going to purchase signetwallet.tez. 

First, let's go to the Tezos Domains website https://tezos.domains and see if the domain is available by typing it in the search box.

![](170/td-search.png)

It turns out that it is and we can click the button to reserve it:

![](170/td-yes.png)

Click Reserve, the site will ask me to connect my wallet. Follow the instructions, use Show More, then Show QR Code, then Beacon. Copy the code and paste it into the dApps dialogue in Signet.

![](170/td-request.png)

Next we request the domain as above. This requires you to sign an operation in Signet to hold the domain. Then after a little wait, you can register the domain for the price. In this case, it's 16tz.

![](170/td-register.png)

Register the domain and sign the operation to purchase it. After you have purchased it, you can set up email reminders to remind you to renew the domain at the end of the registration period. Next you can set up information about the domain:

![](170/td-settings.png)

I'm going to set up a website redirect to Signet's website. This means that https://signetwallet.tez.page will redirect to my site. You can also host a small website with Tezos Domains.

![](170/td-website.png)

Also on the settings page, you can transfer the name to another account, sell it or give permissions to another account to edit it. 

You can use Tezos domain names in Signet as recipients of transactions.

One word of caution. You might want to live anonymously on a blockchain. It's difficult to do this actually, but one way to be anonymous is not to have any obvious identifiers on your account. A domain name may hint that an account belongs to you.

{#id: 170-dapps_2_Quipuswap}
## Quipuswap

*In this section, we look at swapping tokens. There may be financial implications for you if you do this. Please take professional advice if you are unsure.*

[Quipuswap](https://quipuswap.com) is an on-chain Tezos decentralised exchange. You can swap tokens such as tez with other tokens. In this section, we will swap 1tz for some [USDtz](https://usdtz.com). USDtz is a full-reserve backed stablecoin pegged to the US dollar. This means for every 1 USDtz in existence there is a real US dollar in reserve.

![](170/quipuswap.png)

To swap at Quipuswap, click `Connect Wallet` and then `Other wallets`. Choose `Show more` and then `Show QR code`. Choose `Beacon`, then copy the code to the clipboard. As we did with Objkt, open Signet, choose the account you want to use, go to `dApps...` in the burger menu and paste the copy into the dialogue. Click `Pair` and then `Connect`. You should now be logged into Quipuswap.

<!--
![](170/quipuswap-tokens.png)
-->

Click the burger icon on the right hand site and choose `Swap`. For the target token, I can select and choose any available token for swap. I'm going to choose USDtz and click `Swap`. (On the day I did this, the value of 1tz was about $0.30 and so I was getting about $0.30 USDtz in return.)

![](170/quipuswap-usdtzsend.png)

In Signet, I get a notification to sign the operation.

![](170/quipuswap-sign.png)

And once I've signed, the tez has been swapped for USDtz and I can see it in my assets. I also got some Quipuswap governance tokens whilst I was there.

![](170/quipuswap-assets.png)

{#id: 170-dapps_2_3Route}
## 3Route

3Route is a cross-DEX aggregator where you can swap your Tezos crypto tokens for other ones cost-efficiently across various DEXes. In this section, we are going to swap 1tz for some Tezos Domains Governance Tokens (TED). This token allows you to vote with in the [Tezos Domains Decentralised Autonomous Organisation](https://tezos.domains/en/governance/dao). A *Decentralised Autonomous Organisation (DAO)* is a system for handling voting and finances of an organisation on a decentralised system such as a blockchain. There are many other tokens that you can swap with at 3route, but TED will be fine for this demonstration.

![](170/3route.png)

To use 3Route, go to [3route.io](https://3route.io) into your web browser. Click `Swap` and then `Connect Wallet`. As with the other dApps, our wallet isn't on the list yet, so choose `Show more`, then `Show QR code`. Choose `octez.connect` and copy the code to the clipboard, click `Pair` and then `Connect` in the next screen. You are now connected to 3route.io with your Signet wallet.

<!-- ![](170/3route-selectted.png) -->
![](170/3route-clickswap.png)

Now enter the amount of tez you want to swap and the token that you want to swap it with (TED in this case). I have chosen to swap just 1tz. At the time of exchange, I could get approximately 132 TED tokens for my 1tz. Click `Swap`. As you would expect, Signet will ask you to sign the operation.

![](170/3route-signet-sign.png)

Click `Approve and Send`, and the assets will be swapped. We can see them in the assets view:

![](170/3route-signet-assets.png)

And the calls to the various smart contracts are visible in the transaction view:

![](170/3route-signet-tx.png)

<!--
## Swapping Tez for other cryptocurrencies
XXX
-->

# Distributed Apps

Distributed Apps (dApps) are applications that interact with the blockchain. As a beginner, you'll come as across these as sites to buy digital artwork or at a distributed exchange (DEX) to swap tez with other coins. There are other applications of course. In this section, we will connect Signet to the art site [Objkt.com](https://objkt.com) and purchase a piece of art.  We will also swap some tez for another coin at the DEX [Quipuswap](https://quipuswap.com) and also at the cross-DEX aggregator [3route](https://3route.io/).

## Connecting to a dApp

Signet uses [Octez Connect](https://octez-connect.tezos.com) (formerly called Beacon) to connect to dApp websites. We will go through the full process with Object.com and 3Route, but here are some things to be aware of. On dApp websites, there will be a button to `Sign in`, `Connect Wallet` or `Sync`. If you click on this, a dialogue will appear. Sometimes it will ask you which style of connection to use - choose Beacon or Octez Connect. Then usually there will be a popup asking you which wallet you use.

![](beacon.png)

<!-- Waiting -->
At the writing, Signet is not on this list, but you can still connect to these sites if they will give you a QR code for the connection. Select `Show QR Code`, then `Octez Connect` if necessary, then there will be a barcode on the screen. You can copy the value to the clipboard.

Then in Signet, choose `dApps..` from burger menu. In the first dialogue, you will be able to paste the pairing code to connect Signet to the dApp website.

You will always be able to use this method to connect Signet to a dApp, but in the future, Signet will be on the list of wallets. You'll be able to choose it there and the Signet application will automatically receive the pairing code without you having to worry about it.

## Buying an NFT from Objkt

We will cover what an non-fungible token (NFT) is more precisely at the end of this section. For the purposes of this exercise, you can think of an NFT as being a unique record of ownership of a digital asset. We are going to buy a piece of digital art from Objkt and the ownership will be recorded on the Tezos blockchain.

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

You should now be logged in with you account. Choose `Continue` on objkt.com if needed. We started our login on a specific piece of art. We can now buy this. Scroll down to `Buy from artist` and click it.

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

We have only scratched the surface here. You can mint your own NFTs at Objkt.com and if you have an artistic streak, I would encourage you to experiment with it. Let's end the section with some terminology about NFTs.

A *fungible token* is a digital asset that can be interchanged with another one of the same type and value. A tez coin is an example of a fungible token. A *non-fungible token (NFT)* is one that represents a unique digital token that represents ownership of an item or asset. We will be purchasing a piece of art and we will receive an NFT to show our ownership. We can sell or transfer this NFT.

Note that the artwork usually too big to be stored on the blockchain itself, but the NFT is on the blockchain and proves our ownership. The art is stored on a distributed file service called the *interplantary file system (IPFS)*.

Although it may be possible to buy more than one copy of each artwork, each one has a unique record of ownership on the chain. So an NFT is unique in this sense.

NFTs are implemented as smart contracts and often there are some interesting rules that don't happen for physical art. For example, if you sell a piece of artwork on-chain, the smart contract might have a provision for the creator. This means the artist gets a cut of every sale of their artwork, despite not owning it.

People tend to refer to digital art whose purchases have been recorded on blockchains as NFTs, but it is the record of ownership that is the NFT really.

## 3Route

3Route is a distributed exchange where you can swap your crypto tokens for others. In this section, we are going to swap 2tz for some Tezos Domains Governance Tokens. XXX There are many other tokens that you can swap with at 3route XXX


Go to 3route.io.
Click Swap, Connect Wallet.

As with Objkt.com, our wallet isn't on the list yet, so choose `Show more`, then `Show QR code`. Choose `octez.connect` and copy the code to the clipboard, click `Pair` and then `Connect` in the next screen. You are now connected to 3route.io with your Signet wallet.


On the day, the exchange was rought



## Quipiswap

Connect Wallet
Other wallets
Show more
Show QR code
Beacon

Choose the burger, swap.

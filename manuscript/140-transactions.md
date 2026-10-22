{#id: 140-transactions_1_Making}
# Making Transactions

When Bitcoin first appeared, it was novel in the way that it offered the possibility to transfer value between two people using a completely decentralised system. There is no bank, no intermediary. The transactions happen on chain and the users sign the transactions with their private key. 

Tezos is no different. You can replace the basic banking functions of transferring value over the network. We will concentrate on sending and receiving tez in this chapter. You can also send other tokens to other accounts on Tezos including DeFi assets and NFTs. You can also use your account to sign other operations too.

{#id: 140-transactions_2_Receiving}
## Receiving

Receiving tez in your Signet account is a passive operation. All you need to do is give the sender your address. You can either copy it from the top left of your Signet menu, or click the Receive button. 

![](120/receive.png)
This screen gives you the possible to copy your address, but also a bar code. Some mobile wallets will read the bar code and use it as a sending address. This is useful if you are near to the person that wants to send you the funds.

In this case, someone has kindly send my wallet 1tz on *Shadownet.* You can see the transaction in the list, which is in most recent order. The first transaction is the inbound 1tz. The second transaction is where I got funds from the faucet (on the test networks, the faucet account is called *Farrah Fawcet*). 

![](140/tx.png)
{#id: 140-transactions_2_Sending}
## Sending

Sending is where we need to be a bit more careful, as we cannot fix mistakes. 

XXX


{#id: 140-transactions_2_Selling}
## Selling and Swapping

We have not implemented any interfaces to centralised exchanges to sell tez. If you want to sell tez, you'll need to use a centralised exchange like the ones in the previous chapter. You can transfer your tez in and then sell them at a market value.

You can also swap your tez for other cryptocurrencies. You can do this at a centralised exchange as well, but you can also do it at a *decentralised exchange* (DEX) such as Spicyswap. You'll need accounts on the other chains if you do this and this is out of scope of this book. We will show you some *on-chain DEXes* later on - these are DEXes for swapping assets that are solely on the Tezos chain.

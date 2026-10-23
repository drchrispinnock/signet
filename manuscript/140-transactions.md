{#id: 140-transactions_1_Making}
# Transactions and Addresses

*Please note that the addresses on the Tezos blockchain used in the chapter are shown for demonstrative purposes only. Please do not send funds to them.*

When Bitcoin first appeared, it was novel in the way that it offered the possibility to transfer value between two people using a completely decentralised system. There is no bank, no intermediary. The transactions happen on chain and the users sign the transactions with their private key. 

Tezos is no different. You can replace the basic banking functions of transferring value over the network. We will concentrate on sending and receiving tez in this chapter. You can also send other tokens to other accounts on Tezos including DeFi assets and NFTs. You can also use your account to sign other operations too.

{#id: 140-transactions_2_Receiving}
## Receiving

Receiving tez in your Signet account is a passive operation. All you need to do is give the sender your address. You can either copy it from the top left of your Signet menu, or click the Receive button. 

![](140/receive.png)
This screen gives you the possible to copy your address, but also a bar code. Some mobile wallets will read the bar code and use it as a sending address. This is useful if you are near to the person that wants to send you the funds.

In this case, someone has kindly send my wallet 1tz on *Shadownet.* You can see the transaction in the list, which is in most recent order. The first transaction is the inbound 1tz. The second transaction is where I got funds from the faucet (on the test networks, the faucet account is called *Farrah Fawcet*). 

![](140/tx.png)
{#id: 140-transactions_2_Sending}
## Sending

Sending is where we need to be a bit more careful, as we cannot fix mistakes. To send tez, you need the address of the recipient. In this example, we will send 5tz on *Shadownet* to another account that we know the address for:

\```
tz1ULZN2uHvhcnbkyfBnvJhGf3n5gRs3QbN4
\```

If you have more than one account in Signet, make sure you've selected the right account by dropping down on the account name and choosing it. Then to send, click the Send button:

![](140/sendblank.png)

Now we can enter an address in several ways. We can:

1. Enter a Tezos address, such as the one above.
2. Use an address book entry (such as Captain Stake shown above).
3. Use a .tez name. These are *Tezos Domains.* You can register a name such as drchris.tez or captstake.tez, and it can be used as an identifier your account. Note that these work on *Mainnet.*

In this case, we are going to use the address above, so I type that in:

![](140/sendfill.png)

Signet doesn't recognise the address, because it is not in its address book, but we know the recipient so we will continue. We are going to send 15tz as in the dialogue. We click `Continue`:

![](140/confirm.png)


There is a final confirmation window. We click `Confirm and Send`. And the transaction goes through:

![](140/confirmed.png)

It is possible sometimes that the transaction does not go through. Usually this is due to congested or busy node. We will should you have to change nodes later on. But you can try the transaction again in such circumstances.

Let's pop back to the address window again. Let's put in this address:

```
tz1Xf8zdT3DbAX9cHw3c3CXh79rc4nK4gCe8
```

into the Send dialogue.

![](140/dictator.png)

In this case, Signet has looked the address up on tzkt and found that it has a name. It's still not verified, because anyone with an account can update their name at tzkt using profiles.tzkt.io. On *Mainnet*, we can also put in .tez addresses. For example, we can put in *etherlink.tez.* This resolves to

```
tz1VBLpuDKMoJuHRLZ4HrCgRuiLpEr7zZx2E
```

And we can send to it in the same way:

![](140/usetezaddr.png)

{#id: 140-transactions_2_Making}
## Making large transactions

As we have said before and will probably say again, there is no central authority to help you out if you send tez to the wrong place. So you need to be careful. Firstly, do not send tez to an address that you don't know. (By the way, that includes the addresses in this book which are provided for example only.) Secondly, if you are making a large transaction of tez, make sure you are in contact with the receiver. It's best practice to send 1tz first, make sure it arrives in the right place and then send the rest with another transaction. It's also a good idea to add commonly used addresses to the address book, which we will cover next

{#id: 140-transactions_2_Address}
## Address Book

XXX

{#id: 140-transactions_2_Selling}
## Selling and Swapping

We have not implemented any interfaces to centralised exchanges to sell tez. If you want to sell tez, you'll need to use a centralised exchange like the ones in the previous chapter. You can transfer your tez in and then sell them at a market value.

You can also swap your tez for other cryptocurrencies. You can do this at a centralised exchange as well, but you can also do it at a *decentralised exchange* (DEX). Also you can swap you tez using a *bridge*. The other side is on another blockchain. You'll need accounts on the other chains if you do this and this is out of scope of this book. We will show you some *on-chain DEXes* later on - these are DEXes for swapping assets that are solely on the Tezos chain.

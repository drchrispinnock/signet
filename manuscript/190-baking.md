{#id: 190-baking_1_Operations}
# Operations for Bakers

If you are not going to bake on Tezos, you can safely skip this chapter.

We introduced the concept of baking in the [Delegating and Staking](#delegating) chapter. Signet supports baker operations and you can hold your baking key in the wallet. A baker can use a different key to the one holding the funds (the master key) on the baking server. This is called a *consensus key*. It is still possible to do damage if someone has access to it, but it is possible to rotate it. Additionally, there is a key called a *companion key* that is used with the Data Availability Layer (DAL). The baker uses the consensus key to sign blocks and the companion key to attest using the DAL. These keys can be set by signing an operation with the master key.

A baker also has some parameters to manage regarding staking. They can set their *Staking over Baking Limit*, which is the multiplier used to determine how much external stake they can accept. They can also set their *Edge of Baking over Staking* (sometimes called the *Staking Fee*). This is the fee the baker takes from the staking reward provided to the staker.

The bakers also vote in the on-chain governance elections and this is done by signing operations with the master key.

The good news is that you can do all of these operations with the Signet wallet. You just need to import the master key into to wallet or connect the ledger that they key is held on. This, of course, works particularly well if you want to use a separate key for consensus. 

A good way to manage the key is to hold the master key on a Ledger and delegate consensus and companion to two tz4 keys. The baking fund is safe and the other keys do the work. Moreover, the Tezos X roadmap needs the baking community to use tz4 keys.

{#id: 190-baking_2_Registerin}
## Registering as a baker

Only follow this section if you intend to use your key for baking. Once you register as a baker, you cannot unregister. One consequence of this is that you cannot delegate or stake to another baker ever again. We will assume that you have imported your master baking key in Signet. In the tutorial below, we are going to do everything on the *Ushuaianet* test network, but it works on all other networks.

Select the key and go to `Baking...` on the burger menu.

![](190/delegate.png)

Click `Register as Baker`.

![](190/delegate2.png)

There is a small fee to pay, which you can confirm and then your key is registered as a baker. You will need to stake some tez. You'll need to stake at least 6000tz or 10% of your total balance, whichever is higher. You can do this in exactly the same way as you learnt in the [Delegating and Staking](#delegating) chapter. Go to the `Staking` button and stake whatever you would like.

You now need to setup your baker if you haven't already, as soon as possible so that it will bake when you get rights. If you are not going to use a consensus key, you'll need to export the secret key and use it on the baker. There are several ways to secure your key in a baking environment, such as using a remote signer. This is beyond the scope of this book, but you can look at my other book on Tezos Infrastructure <!-- MARKUPBIBTAG 63d75376 -->[4]<!-- ENDMARKUPBIBTAG --> or my quick start guide <!-- MARKUPBIBTAG 02bbf5b2 -->[5]<!-- ENDMARKUPBIBTAG -->. If you are going to hold your baking key

{#id: 190-baking_2_Consensus}
## Consensus and Companion keys

Now that you have a baking key, you can set your consensus and companion keys. If you are using tz4 for your consensus key and you are using DAL, then you'll need a tz4 companion key. We will assume that you are using tz4 keys because it is currently the best practice for the Tezos network.

Choose the `Baking...` menu again and you'll have more options:
![](190/parameters.png)
Now the consensus and companion keys are usually generated on the baking machine. Typically they do not have any tez. And this usually means that their public keys have not been revealed on the network. There is no reason why you can't generate them in the Signet wallet, in which case you will already have their public keys - it's just you'll have to export them and move them to your baker. 

For this demonstration, I will assume that the keys are being generated on the baking machine. I've created two tz4 keys on another machine using the command-line wallet `octez-client`:

```
$ octez-client gen keys Bonnie --sig bls
$ octez-client gen keys Clyde --sig bls
$ octez-client list known addresses
Clyde: tz4FZUa4chtuSFyUyf1N9VedayHbqST29kUW (unencrypted sk known)
Bonnie: tz4TiyX6pedf2vpy9SACczNiPxoFv7YBNGWY (unencrypted sk known)
```

I can get their public keys by typing these commands:

````
$ octez-client show address Bonnie
Hash: tz4TiyX6pedf2vpy9SACczNiPxoFv7YBNGWY
Public Key: BLpk1nd7xWibPCo63auH1twvib6ubfT6ZqQe6u5wYpKBCdGcZw7L4xTmaqLxCsbjxrkaXpxF7Snz
$ octez-client show address Clyde
Hash: tz4FZUa4chtuSFyUyf1N9VedayHbqST29kUW
Public Key: BLpk1zRVPqHjeXjsfyv82oPbNgYs97BHEaYa5BHEBmudNmAUMqJGT5BF677Xd5bTfxjbfwrVSjwP
```
````


To use the keys Bonnie and Clyde, I'll need to generate a proof of possession signature. To do this `octez-client` must be connected to a node.

```
$ octez-client create bls proof for Bonnie
BLsigA4xmMaC26r5LqRxdxnuurM3vwGG6bmmQs8a4nwPf4ACMBFvCt3pCZy8bAtzTXRhFpBTkysewrwTgaFnDeTb73Ga4ZjLemEkKPy6skbEabhs5smD8tWDCoUuXLX5s4RVnL7MV22jft
$ octez-client create bls proof for Clyde
BLsig9efYbCxYMiVxuvAWBprtrr1U8mFWzfjaWk9iUyucYuzNuWXmo67y6gmUmKHbq7etoDLtMWCAJ9ioZ4b46pEmM2e7bhwvdcw7dwfoHgbrGdUEPkVE52iPVfwA9yecEtMCz5mW2oQe8
```

Now we can set the Consensus and Companion keys by pasting the public addresses and proofs into Signet. We'll do Consensus here, but Companion is exactly the same:

![](190/consensus.png)

Now click `Continue`, then `Confirm` the operation to set the key.

If you have the keys in your wallet already, you can select them from the address book. Let's see what happens if we just use the tz4 key rather than the public key:

![](190/notrevealed.png)

Signet cannot get the public key from the tz4 address, which is a hash of the public key and it complains. This would have worked if the address was created in our wallet or if the key had been revealed on the network.

Anyway, now you have set the consensus and companion key for your baker and we can see all the operations on the block explorer. Now you need to finalise setting you your baker with the companion and consensus key.

![](190/blkexplorer.png)


{#id: 190-baking_2_Staking}
## Staking parameters

Now go back to the `Baking...` menu and scroll to the bottom of it.

![](190/stakingparameters.png)
Here you can set the two staking parameters. The Limit of staking over baking controls the amount of external stake you can accept from our accounts. If it is set to 0 (the default), you cannot accept staking requests. The maximum value is 9. The Edge of baking over staking is the amount of reward you take as a baker from the block reward. The rest goes to the external stakers in proportion to their stake. The default is 100%, so any staker would not get any rewards. If you are going to offer staking, it's up to you what you set these parameters too. There's probably no good reason not to set the limit to 9 if you are accepting staking. Then you need to choose a rate that is attractive enough to stakers, but good enough for you to make a fee.

You can change these parameters at any time, but the changes take XXX cycles to take affect.

{#id: 190-baking_2_Governance}
## Governance

Signet also supports governance operations for baking keys. The full governance process is discussed and monitored at [Tezos Agora](https://tezosagora.org). 
If a key is registered for baking, then an extra option appears in the burger menu called `Governance`. The flow detects what period of governance the chain is in. 

The proposal period is where bakers can submit proposals for a new protocol. They do this by submitting a hash.

![](190/proposal.png)

*Note to reader - we need to set up a test or wait for Mainnet to enter governance to fully test this section. It needs finishing.*
<!-- XXX --->


{#id: 190-baking_2_Baking}
## Baking Key considerations

Bakers need to be careful when setting up their infrastructure. The worst thing you can do as a baker is double bake or attest - that is bake (or attest) two different blocks at the allotted time. The reason for this is that it can cause chain confusion. Some operations might not be included in the other block or they might be an attempt to double spend. If a baker double bakes, they lose some or all of their stake.

It's unlikely a baker will do this with a sensible baking setup. Usually bakers run one instance of the software at a time and protect their keys with a piece of software called a remote signer. This checks to see if a baker has tried to sign a block at the same slot before and prevents the signing.

There's far more to it than my explanation, but it's safe to say that all bakers want to protect their baking key, as someone else having access to it can cause serious problems. Another person could cause the baker to double-bake. So storing your key away from your baking environment where you can manage the balance, baking operations and parameters is a good thing. This is why the baking and governance menus were added to Signet.


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

You now need to setup your baker if you haven't already, as soon as possible so that it will bake when you get rights. If you are not going to use a consensus key, you'll need to export the secret key and use it on the baker. There are several ways to secure your key in a baking environment, such as using a remote signer. This is beyond the scope of this book, but you can look at my other book on Tezos Infrastructure  <!-- MARKUPBIBTAG ad263967 -->[3]<!-- ENDMARKUPBIBTAG --> or my quick start guide <!-- MARKUPBIBTAG 7a121253 -->[4]<!-- ENDMARKUPBIBTAG -->. If you are going to hold your baking key

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

You can change these parameters at any time, but the changes take XXX cycles to take effect.

{#id: 190-baking_2_Governance}
## Governance

Signet also supports governance operations for baking keys. We discussed governance in the Introduction. The discussion around the governance process happens at [Tezos Agora](https://tezosagora.org). It's possible for bakers to participate in the on-chain governance process from Signet. If a key is registered for baking, then an extra option appears in the burger menu called `Governance`. The flow detects what period of governance the chain is in and provides the right actions to the bakers.

Most of the time, a network is in the proposal period.  During the proposal period, bakers can propose new protocols and upvote other proposals. 
A new protocol proposal is represented by a hash. For Ushuaianet, the hash is:

```
PsUshuai9QapM5TGj1JpuVGkdxz5GykdnEvS6Rh8SUVrARvZLCY
```

We can see this here in the governance window. Choose a key that is a baking key and go to `Governance`. Here we are in the proposal period, there are 254 blocks remaining and our voting power is 999999tz:

![](gvn/propose.png)
(Note that when I wrote this, the Tezos chain was running the Ushuaia protocol and there were no new proposals. To demonstrate the governance feature, I set up a test network with short cycles and governance periods. The test network run the Tallinn protocol. We will vote for the Ushuaia protocol on the network.).

To propose it, paste the protocol hash into the proposal dialogue and upvote it. It's unlikely that you will do this, unless you someone proposing a new protocol that you or the core development team have developed. It's more likely that you will upvote an existing proposal. Here is the screen when a proposal has been made already by a baker. There can be more than one proposal at a time. The proposal that has the most votes and has quorum XXX wins the round.
![](gvn/upvote.png)
Here I select the only proposal and click `Upvote` to add my baker's vote to it. We can return to the screen any time to see the progress. Here we have 39.95% of the voting power supporting the proposal:

![](gvn/2-proposal-162togo.png)
Now it turns out that enough bakers upvoted the proposal. The next stage of the governance process is Exploration. During this phase, bakers vote for, against or simply pass for the proposal. There needs to be a quorum for the vote to go through. Bakers decide on the proposal by testing it on a test network, reading the documentation at Tezos Agora and doing their own checks. Here we are in the Exploration period:

![](gvn/3-exploration-before-vote.png)
And now there are voting buttons: `Yay`, `Nay` and `Pass`. We are going to vote `Yay` by clicking the button. Then `Confirm` in the next screen.

![](gvn/2-voting-yay.png)
Coming back to the Governance screen, we see that we have 39.92% of the 55% quorum and the vote is currently 100% on `Yay`.
![](gvn/3-exploration.png)


The next phase of the governance process is Cooldown. During this period, blockchain participants do more testing, review their results and if they haven't already implement changes to their code and infrastructure in preparation for the protocol changes. Here we are in Cooldown and there is nothing for us to do from a voting perspective:
![](gvn/4-cooldown.png)

The next phase is the Promotion period. By this stage, the bakers are confident that the protocol proposal is fit for purpose. If they are not, this is their chance to vote against it. Again, they can vote for, against or pass. Here we are in the Promotion period:

![](gvn/promotion.png)
We are going to vote `Yay` again by clicking `Yay` and confirming the transaction in the next windows. Now in this case, the other bakers also voted positively and the vote was yes for the new protocol.

The last phase is Adoption. There is nothing to do from a governance process. It's time to make sure all of our applications are up to date. If we are running a baker, we'll need to update it to the latest Octez. Essentially the governance process is complete. The Adoption period gives the blockchain participants time to update their applications and systems.

![](gvn/adoption.png)

After this period, the network switches to the new protocol and returns to the Proposal stage.

If you are a baker and you are having trouble figuring out how to vote in a governance election, the most pragmatic thing to do is vote pass. This contributes to the quorum and allows the process to go ahead, whilst letting the other bakers decide the outcome. If there is not enough votes in the Proposal, Exploration and Promotion phases, the process stops and the network returns to the Proposal stage.


{#id: 190-baking_2_Baking}
## Baking Key considerations

Bakers need to be careful when setting up their infrastructure. The worst thing you can do as a baker is double bake or attest - that is bake (or attest) two different blocks at the allotted time. The reason for this is that it can cause chain confusion. Some operations might not be included in the other block or they might be an attempt to double spend. If a baker double bakes, they lose some or all of their stake.

It's unlikely a baker will do this with a sensible baking setup. Usually bakers run one instance of the software at a time and protect their keys with a piece of software called a remote signer. This checks to see if a baker has tried to sign a block at the same slot before and prevents the signing.

There's far more to it than my explanation, but it's safe to say that all bakers want to protect their baking key, as someone else having access to it can cause serious problems. Another person could cause the baker to double-bake. So storing your key away from your baking environment where you can manage the balance, baking operations and parameters is a good thing. This is why the baking and governance menus were added to Signet.


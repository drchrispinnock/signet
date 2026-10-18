# Operations for Bakers

If you are not going to bake on Tezos, you can safely skip this chapter.

Blockchains need participants that produce the blocks. The block production on Tezos is called *baking*. On other chains it is called *mining* or *validating*. The participants are called *bakers*. In fact we refer to both the systems that do the baking and the people who run them as bakers.

Tezos is a proof-of-stake blockchain. A baker has an account on the Tezos chain, like any other participant. They need to attach their wallet to the baking process to provide a security bond, called a stake.  The block production is scheduled, favouring the bakers with the most stake. They get more opportunities to bake a block. Additionally, bakers attest other blocks produced by other bakers. The security bond is there to provide a guarantee against bad behaviour.

The worst thing you can do as a baker is double bake or attest - that is bake (or attest) two different blocks at the alloted time. The reason for this is that it can cause chain confusion. Some operations might not be included in the other block or they might be an attempt to double spend. If a baker double bakes, they lose some or all of their stake.

It's unlikely a baker will do this with a sensible baking setup. Usually bakers run one instance of the software at a time and protect their keys with a piece of software called a remote signer. This checks to see if a baker has tried to sign a block at the same slot before and prevents the signing.

There's far more to it than my explanation, but it's safe to say that all bakers want to protect their baking key, as someone else having access to it can cause serious problems. Another person could cause the baker to double-bake.

A baker can use a different key to the one holding the funds (the master key). This is called a *consensus key*. It is the key used on the baking system and it has slightly less power than the master key. It is still possible to do damage if someone has access to it, but it is possible to rotate it. Additionally, there is a key called a *companion key* that is used with the Data Availability Layer (DAL). The baker uses the consensus key to sign blocks and the companion key to attest using the DAL. These keys can be set by signing an operation with the master key.

A baker also has some paramaters to manage regarding staking. They can set their Staking over Baking Limit, which is the multiplier used to determine how much external stake they can accept. They can also set their Edge of baking over staking (sometimes called the Staking Fee). This is the fee the baker takes from the staking reward provided to the staker.

The bakers also vote in the on-chain governance elections and this is done by signing operations with the master key.

The good news is that you can do all of these operations with the Signet wallet. You just need to import the master key into to wallet or connect the ledger that they key is held on. This works particularly well if you want to use a seperate key for consensus.

## Registering as a baker

Only follow this section if you intend to use your key for baking. Once you register as a baker, you cannot unregister. One consequence of this is that you cannot delegate or stake to another baker ever again. We will assume that you have the key that you want to be the master baking key in Signet. You've either imported it or generated it there, or it is on a ledger you've connected.

Select the key and go to `Baking...` on the burger menu.

![](190/delegate.png)

Click Register as Baker.

![](190/delegate2.png)

There is a small fee to pay, which you can confirm and then your key is registered as a baker. You will need to stake some tez. You'll need to stake at least 6000tz or 10% of your total balance, whichever is higher. You can do this in exactly the same way as you learnt in the [Delegating and Staking](#delegating) chapter.




You now need to setup your baker if you haven't already, as soon as possible so that it will bake when you get rights. This is beyond the scope of this book. XXX Guides?

## Consensus and Companion keys

![](190/parameters.png)


## Staking parameters

## Governance

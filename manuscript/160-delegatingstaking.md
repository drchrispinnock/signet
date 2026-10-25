{#id: delegating}
# Delegating and Staking

From its inception, a Tezos account holder has been able to *delegate* their tez to a baker. By doing this, the extra coins contribute to the baker's power on the network. They get more baking opportunities and more power in the governance process. Sometimes a baker will pay a small reward to the account holder in return for delegating their tez. A baker that does this is called a *public baker*. All of reward payment is handled off chain and by good will.

In 2023, account *staking* was added as a feature to Tezos. A baker has always had a stake on the network, usually 10% of the total balance including the delegators. But after this change, a baker can stake more than 10% and normal account holders can stake too. Their stake contributes to the baker's security bond. The baker sets a fee as a parameter and the account holders automatically receive rewards on the network.

Delegated funds are liquid in that they can be spent at any time. Staked funds cannot be spent. They need to be unstaked and finalised before they become liquid again. At the moment this takes <!-- MARKUPTAG unstake-->4<!-- ENDMARKUPTAG --> cycles (roughly <!-- MARKUPTAG unstakedays-->4<!-- ENDMARKUPTAG --> days). Delegated funds at not at risk. Staked funds are part of the baker's security bond. If the baker misbehaves, you might lose your staked funds. We will talk about this at the end of the chapter.

The account has a spendable fund balance and a staked fund balance. You can see the seperate balances in the main Signet screen if you click the arrow at the end of the Tezos balance line.

The network effectively creates tez when a block is baked and gives it to the baker and related stakers. This means that tez is subject to inflation. By delegating and staking, and subsequently receiving rewards you are keeping up with inflation to some degree.

It's not an accurate analogy but you can think of your Tezos account as a current account at the bank. You don't get any interest on it and if you do nothing, the money just sits there. Delegating is a bit like an instant access savings account. Provided your baker pays you some rewards, you get something in return, and you can spend the money at any time. Staking is more like a higher interest savings account where you have to lock your money in for a period of time.

Note that to stake, you can only stake with your delegated baker. So staking and delegation are related, but they are not the same thing.

In this chapter we look at choosing a baker, delegating with them and staking with them.

{#id: 160-delegatingstaking_2_Choosing}
## Choosing a baker

Choosing a baker is a matter of personal preference. We've tried to make the process easier with Signet, but you need to do a bit of research to choose a baker. There are at least two places to go to find possible bakers. Firstly, TzKT maintains a list of [public bakers](https://tzkt.io/bakers/).

![](160/tzktbakers.png)
This is information regarding delegation is information that the bakers have submitted themselves. Bakers set their staking parameters on-chain, so the staking information is read from there. 

A public baker is a baker that has declared itself public by telling tzkt. There is practically no difference on-chain between a public baker and a "private" one. The list tells you if the baker is active in the governance process and how they voted. It tells you want delegation fee they take and the rough APY your funds will receive if you delegate with them. For example, TezOasis takes a fee of 4% and your delegated coins are likely to grow by 2.21% APY if you delegate with them. 

Clicking on the TezOasis link takes me to their account page in tzkt, where there are details to contact them. They have 965k tz capacity, so they are a possibility to delegate to. Also, if you click the `SCHEDULE` tab you will be able to see their performance. On the day I wrote this, TezOasis's performance was very good - it had a few network misses but this is perfectly normal.

TezOasis is also offering staking and passes on all of the reward to the staker (it has a 0% fee). You can expect your staked funds to grow at 6.9% APY. They have less staking capacity at 126k tz but still enough for us to consider them.

You can also delegate to any baker - it doesn't have to be public. But the baker might not pay you delegation rewards. To see if they will accept staking, go to their page on TzKT and look on the left panel. There are two items: 1. The Staking Fee - tells you how much the baker takes from a staking reward and 2. The Staking over Baking limit - this is the amount of stake that the baker can accept as a multiple of its own stake. If the Staking over Baking limit is 0, they don't accept staking. If the Staking Fee is 100%, they don't pay staking rewards.

There are some bakers, such as the Tezos Foundation, that accept staking for their own fund purposes but don't pay rewards. This is to encourage the community to stake with community bakers and not them.

When choosing a baker you should be looking for a baker that is:

- performing well on the network (see it's `SCHEDULE` in TzKT)
- offering delegation rewards if you want to just delegate
- offering staking if you want to stake
- responds to you with questions and queries about delegating with them

With staking there is a further consideration because your funds are at risk. You want a baker that is trustworthy and has well setup infrastructure. The key problem here is if the baker double-bakes (produces two blocks at the same level), the staked funds are at risk. 


{#id: 160-delegatingstaking_2_Delegating}
## Delegating

Delegating to a baker is easy in Signet. For the purpose of this exercise, I have set up a new account with 2tz. I want to delegate them to a baker. I've spent the last days researching and decided to delegate them to Capt Stake. 
![](160/notdelegated.png)
To delegate, I can either click on Not delegated . If you click Stake you will also go to the delegation workflow, because you need to delegate before you stake.

![](160/stakingmenu.png)

Now click `Delegate...` and choose your baker either from the list or type in the address:

![](160/bakers.png)
Signet lists the public bakers, some detail about them and whether they accept staking. If you want to stake later, you'll need a baker that accepts staking. It doesn't list all the bakers and Capt Stake is not on the list. His address is:

```
tz1dCaMnnMJk76UodjewCK67ABiXWjcKj73N

```

Let's paste that in and click use. Then there is a small fee to pay for the delegate operation which can be confirmed. Now my 2tz is delegated to Capt Stake. Whether Capt Stake pays me rewards for my delegated tez is between him and me. I need to discuss it off chain directly if there is any ambiguity.
![](160/captstake.png)

{#id: 160-delegatingstaking_2_Staking}
## Staking

To stake tez uses the same dialogue as for delegating. You can get there either by clicking the `Delegated to` section or the `Stake` button. Capt Stake accepts staking. One thing to be aware of is that you cannot stake all of your tez. You need to have a small amount spare for the fee of the staking operation. We are going to stake 1tz with Capt Stake.

On the Staking menu, click `Stake` then put in your amount and click `Continue`.

![](160/staking.png)
Then check you are happy with the fee and `Confirm` the transaction. You have now staked. On the main screen, you can drop down your Tezos balance and see what is spendable and what is staked. You can now only spend 0.998837 tez - the staked tez is locked. 

![](160/balance.png)

If you want to stake more, you can go back at any time and stake the extra tez.


{#id: 160-delegatingstaking_2_Unstaking}
## Unstaking and finalising

If you want to unstake your funds, you can do so at any time, but you will have to wait <!-- MARKUPTAG unstake-->4<!-- ENDMARKUPTAG --> cycles (<!-- MARKUPTAG unstakedays-->4<!-- ENDMARKUPTAG --> days) before you can get them. I'm going to unstake everything that I have with Capt Stake, but you can unstake any amount and leave the rest staked. Go to the `Stake` menu, click `Unstake` and choose the amount. I am going to choose `Max`, then `Continue`. Then I check the fee and confirm the transaction.


![](160/unstake.png)


I've unstaked the funds and now I have to wait for them to unlock. Once they are unlocked, I can come back to Signet and finalise the unstake. Since 2026, there has been a bot on Tezos called Finn. This bot automatically finalises unstaked funds, so you should have them back in your spendable balance as soon as the <!-- MARKUPTAG unstake-->4<!-- ENDMARKUPTAG --> cycles are up. Finn is only present on *Mainnet*. On the test networks, you'll have to finalise yourself.

When there are funds available to finalise, you use the `Finalize` button on the Staking menu (Tezos has adopted American spellings and so we have used them in Signet too).

![](160/finalize.png)
Choose `Confirm` and the funds will be finalised and returned to the spendable balance.


{#id: 160-delegatingstaking_2_The}
## The risks of staking

Staked funds form part of the baker's security bond on the network. The worst thing that a baker can do is double sign a block at the same level. This could be producing two blocks (double baking) or attesting two blocks at the same level (double attestation). It has happened very often on the Tezos network. A full list of [double baking incidents can be found on TzKT](https://tzkt.io/double_baking). Usually it has happened because of a misconfiguration of infrastructure. The provider has run two separate bakers with the same key and the systems injected blocks into the network at the same time.

The problem for you as a wallet holder is if you baker double bakes or attests, your funds are also at risk. If you are concerned about this, you should try to contact your baker to discuss what protection they have in place. Ideally they will have a remote signer to protect their key. Remote signers are able to prevent signing twice, so if two baking instances try to sign from the same remote signer, double baking will be prevented. You can usually rely on the reputation of the baker in question and you can check their performance on the block explorer.

If you are unsure about your current baker, you can always unstake. If they pay delegation rewards, you will continue to receive those and delegated funds are not at risk. But staking is essential to the security of the network and consequently pays better rewards, so it is best to find a baker that you are comfortable with.

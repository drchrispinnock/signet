{id: ID180-multisig_1_Multisig}
# Multisig Accounts

A *multisig account* is one where more than one person or entity needs to sign the transaction. The set of signatories is called a *committee*. The whole *committee* doesn't need to sign the transactions necessarily. When one sets up the multisig account, one can choose how many of the committee sign.

On Tezos, there are two multisig account features. The first works by deploying a smart contract holding the balance of the account, with the code implementing the signing committee. Signet uses the same multisig contract scheme as `octez-client`, with a graphical user interface. There is also a native multisig feature using `tz4` keys. Currently, Signet doesn't implement this.

The functions available in Signet are:

- Create a multisig account
- Add an existing multisig account
- Sign a multisig transaction
- Submit a multisig transaction

Signet will remember any multisig transactions signed in the wallet and they will be available to submit later on. You will just need the signatures from the other parties to complete the transaction. In this section, we will create a multisig wallet containing 10tz and with five signatories: Alice, Bob, Christopher, Diana and Edward. We will require 3 of their signatures to sign a transaction. We'll do it on Shadownet as well.

{id: ID180-multisig_2_Creating}
## Create a Multisig Account

Creating a multisig account is straightforward. You need to have the addresses of the other signatories to hand, or better add them to your address book. Select the account you want to use to originate the multisig contract. In my case, I will use the account Alice. Then in the burger menu choose `Create multisig...`

Fill in the details. I'm going to call mine `My Multisig Account`.

In the Signers section, I drop down on Add account and add Alice (although I don't have to add the originating wallet as a signing party). Then I add Bob and Christopher. I can do this because I have them in my address book. For Diana and Edward, I add their addresses directly in the dialogue and press `Add`. They are `tz1ULZN2uHvhcnbkyfBnvJhGf3n5gRs3QbN4` and `tz1RupNMvGtytrekvWx4FkBdEyeFKV5Vr2jT` respectively.

![](180/multisig.png)

Each of the signers must have revealed their public key on the network (e.g. by doing a transaction), otherwise Signet will not let you create the multisig account.

Then I set the required number of signatures to 3 with the arrows. This means that I need 3 signatures to sign transactions on the multisig account.

Finally I fund the account with 10tz and press the `Create` button. This creates the account, which is really a smart contract. The address is `KT1Bx9kfAML973xrSVyMw5KA7EXMaLSjcozA`. This is a smart contract with a balance of 10tz and code to enforce the rules of the committee. The multisig account is created.

{id: ID180-multisig_2_Add}
## Add an Existing Multisig Account

Now our friend Bob, who also uses Signet, wants to sign transactions on the multisig account. He needs to add it to Signet. On Bob's Signet, he chooses `Add multisig...` and pastes the address of the multisig account. He also gives it a name.

![](180/bobmultisig.png)

Now Bob's wallet is aware of the multisig account.

{id: ID180-multisig_2_Sign}
## Sign a Multisig Transaction

We want to send an account `tz1etTUnFd6cYsmrZuS9awPSppFPwH1G3e9Q` 5tz, but we want to do it from the multisig account. Any of the signatories can start the process, but the signing is not done on-chain - it has to be submitted later. In this case, Alice, Bob and Edward are going to sign the transaction. Alice and Bob are using Signet, and Edward is using `octez-client`. Alice will submit the transaction to the chain. Let's start with Alice.

Alice chooses `Sign multisig transaction...` from the burger menu and fills in the details. She adds the amount and the address to send the tez to. Notice at the top, the multisig wallet is listed. If Alice has access to more than one multisig wallet, she can choose which one to sign for here.

![](180/alicesign.png)

Click `Sign` and Alice receives a signature. Signet will keep hold of the signature for submission later on. If one of the others in the committee were submitting the transaction, Alice should send them the signature string. Signature strings are safe to send in plain text.

![](180/alicesig.png)

Now Bob needs to sign the transaction as well. He does exactly the same as Alice in Signet. He selects `Sign multisig transaction...` and fills in the same details. Then he clicks sign. He saves the signature string

`edsigtu...CBzvsUJ7G2hSucjZ`

and sends it to Alice.

![](180/bobsign.png)

Any one of Christopher, Diana and Edward can provide the final signature. Edward does it. He could do it with Signet but he does it with `octez-client`. This is the command-line wallet provided with the Tezos blockchain software, [Octez](https://octez.tezos.com).

```
$ octez-client -E https://rpc.shadownet.teztnets.com \
  sign multisig transaction on \
  KT1Bx9kfAML973xrSVyMw5KA7EXMaLSjcozA \
  transferring 5 to \
  tz1etTUnFd6cYsmrZuS9awPSppFPwH1G3e9Q \
  using secret key Edward
edsigty...PjoHdBb6qPiFi
```

Edward sends the signature string to Alice.

{id: ID180-multisig_2_Submit}
## Submit a Multisig Transaction

Once all the necessary parties have signed the transaction, it can be submitted to the blockchain. Alice is going to do this. She takes the signature strings from Bob and Edward. Then in Signet she chooses `Submit multisig transaction...`.

![](180/submit.png)

Alice chooses the transaction that Signet has remembered for her in the top drop down. Then she pastes in the signatures from Bob and Edward, and clicks `Add signatures`. She then clicks `Submit`. Provided the signatures are valid for the transaction, the multisig account smart contract will execute and move the funds to the target account.

Note also that Alice can `Discard proposal`. This is used to delete the record of the multisig transaction if it is no longer needed.

We can see the transaction, in this case in Bob's Signet view:

![](180/transaction.png)

{id: ID180-multisig_2_Delegating}
## Delegating

You can delegate smart contracts to bakers on Tezos. The `Sign multisig transaction...` feature can be used to sign the transactions to set the delegate (i.e. the baker) or remove it. As with delegating from normal accounts, you need to have an agreement directly with the baker to receive any rewards for your delegation. To set the delegate, choose the tab in the dialogue `Set delegate`, paste in a baker address and click `Sign`. You will get a signature string as with a transfer transaction.

![](180/setdelegate.png)

The `Remove delegate` function works in a similar way.

Once the other members of the committee have provided their signatures, you can submit the transaction in the same way as you would for a transfer transaction. Or, of course, you can provide the signature string to another member of the committee for them to submit.

![](180/delegatesign.png)

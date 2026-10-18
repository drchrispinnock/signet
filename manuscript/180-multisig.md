# Multisig accounts

A *multisig account* is one where more than one account needs to sign the transaction. The set of accounts that sign the transaction is called a *committee*. The whole *committee* doesn't need to sign the transactions necessarily. When one sets up the multisig account, one can choose how many of the committee are needed to sign.

On Tezos, there is a native multisig account feature. It's available in the command-line wallet `octez-client`. It works by deploying a smart contract holding the balance of the account, with the code implementing the signing committee. Signet implements the feature in exactly the same way, but provides a graphical user interface.

The functions available in Signet are:

- Create a multisig account
- Add an existing multisig account
- Sign a multisig transaction
- Submit a multisig transaction

Signet will remember any multisig transactions signed in the wallet and they will be available to submit later on. You will just need the signatures from the other parties to complete the transaction. In this section, we will create a multisig wallet containing 10tz and with five signatories: Alice, Bob, Christopher, Diana and Edward. We will required 3 of their signatures to sign a transaction. We'll do it on Shadownet as well.

## Creating a multisig account

Creating a multisig account is straightforward. You need to have the addresses of the other signatories to hand, or better add them to your address book. Select the account you want to originate the multisig. In my case, I will use the account Alice. Then in the burger menu choose `Create multisig...`

Fill in the details. I'm going to call mine `My Multisig Account`.

In the Signers section, I drop down on Add account and add Alice (although I don't have to add the originating wallet as a signing party). Then I add Bob and Christopher. I can do this because I have them in my address book. For Diana and Edward, I add their addresses directly in the dialogue and press `Add`. They are `tz1ULZN2uHvhcnbkyfBnvJhGf3n5gRs3QbN4` and `tz1RupNMvGtytrekvWx4FkBdEyeFKV5Vr2jT` respectively.

![](180/multisig.png)

Each of the signers must have revealed their public key on the network (e.g. by doing a transaction), otherwise Signet will not let you create the multisig account.

Then I increase the number of signatories to 3 with the arrows. This means that I need 3 signatures to sign transactions on the multisig account.

Finally I fund the account with 10tz and press the `Create` button. This creates the account, in this case the address is `KT1Bx9kfAML973xrSVyMw5KA7EXMaLSjcozA`. This is a smart contract with a balance of 10tz and code to enforce the rules of the committee. The multisig account is created.

## Add an existing multisig account

Now our friend Bob, who also uses Signet, wants to sign transactions on the multisig account. He needs to add it to Signet. On Bob's Signet, he chooses `Add multisig...` and pastes the address of the mulitsig account. He also gives it a name.

![](180/bobmultisig.png)

Now Bob's wallet is aware of the multisig account.

## Sign a multisig transaction

We want to send an account `tz1etTUnFd6cYsmrZuS9awPSppFPwH1G3e9Q` 5tz, but we want to do it from the multisig account. Any of the signatories can start the process, but the signing is not done on-chain - it has to be submitted later. In this case, Alice, Bob and Edward are going to sign the transaction. Alice and Bob are using Signet, and Edward is using `octez-client`. Alice will submit the transaction to the chain. Let's start with Alice.

Alice chooses `Sign multisig transaction...` from the burger menu and fills out the detail. She adds the amount and the address to send the tez to. Notice at the top, the multisig wallet is listed. If Alice has access to more than one multisig wallet, she can choose which one to sign for here.

![](180/alicesign.png)

Click `Sign` and Alice receives a signature. She should keep a copy of this. But as she will submit the transaction later, she doesn't need to do this. Signet will keep hold of it for the submission. If one of the others in the committee were submitting the transaction, Alice should send them the signature string. They are safe to send in plain text.

![](180/alicesig.png)

Now Bob needs to sign the transaction as well. He does exactly the same as Alice in Signet. He selects `Sign multisig transaction...` and fills out the same detail. Then he clicks sign. He saves the signature string

```edsigtuHs3L9mkyomyT1kXgbPj8dPnfpwJ8ZHF3AZ8G9xeEpuRYEYU8pd5e9XhPky7WxHcQHy1ZASSLRk7vCBzvsUJ7G2hSucjZ```

and sends it to Alice.

![](180/bobmultisig.png)

Christopher, Diana and Edward can provide the final signature. Edward does it. He could do it with Signet but he does it with `octez-client`. This is the command-line wallet provided with the Tezos blockchain software, [Octez](XXX).

```
$ octez-client -E https://rpc.shadownet.teztnets.com \
  sign multisig transaction on \
  KT1Bx9kfAML973xrSVyMw5KA7EXMaLSjcozA \
  transferring 5 to \
  tz1etTUnFd6cYsmrZuS9awPSppFPwH1G3e9Q \
  using secret key Edward
edsigtyYSNqe2msWMwFdU5tVFGq1HKcRuXHDAQ8DD3tgoVojkYwn8jxXdwNxrbx3AQcD5JeVa9fyzkNMk8nHcuPjoHdBb6qPiFi
```

Edward sends the signature string to Alice.

## Submit a multisig transaction

Once all the necessary parties have signed the transaction, it can be submitted to the blockchain. Alice is going to do this. She takes the signature strings from Bob and Edward. Then in Signet she chooses `Submit multisig transaction...`.

!(180/submit.png)

Alice choose the transaction that Signet has remember for her in the top drop down. Then she pastes in the signatures from Bob and Edward, and clicks `Add Signatures`. She then clicks `Sign`. Provided the transactions match the signatures, the multisig account smart contract will execute and move the funds to the target account.

Note also that Alice can `Discard proposal`. This deletes the record of the multisig transaction if is no longer needed.

We can see the transaction, in this case in Bob's Signet view:

![](180/transaction.png)

## Delegating

You can delegate smart contracts to bakers on Tezos. The `Sign multisig transaction` feature can be used to sign the transactions to set the delegate (i.e. the baker) or remove it. As with delegating from normal accounts, you need to have an agreement directly with the baker to receive any rewards for your delegation. To set the delegate, choose the tab in the dialogue `Set delegate`, paste in a baker address and click `Sign`. You will get a signature string as with a transfer transaction.

![](180/delegate.png)

The `Remove delegate` function works in a similar way.

Once the other members of the committee have provided their signatures, you can submit the transaction in the same way as you would for a transfer transaction. Or, of course, you can provide the signature string to another member of the committee for them to submit.

![](180/delegatesign.png)

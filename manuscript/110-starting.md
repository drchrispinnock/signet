# Getting started

## Installation

Signet is an open-source project and the source code is available from [Github](https://github.com/drchrispinnock/signet). At the moment it's for Apple Mac's only. It is written in Swift and is built with the standard Xcode tools from Apple. Pre-built binaries are available from the [release page](https://github.com/drchrispinnock/signet/releases).

To install Signet is like most Apple Mac applications: download it and move it to the application folder. Go to the release page and download the zip file. Your Mac may decompress this automatically. If not, you can click on the zip folder and it will decompress. Copy the Signet application into your applications folder. There's usually a shortcut in your Finder window.

![](110/finder.png)

On the first run, you will get this message:

![](110/warning.png)

XXX we need a way of providing some certainly on this XXX
XXX GPG signing XXX

Click `OK` and continue.

## Running Signet for the first time

When you run Signet for the first time, you'll be presented with some options to set up an account for use on the Tezos network. Many wallets start from cold and assume you'll want to create a new wallet. When we designed Signet, we assumed that you might have a Tezos wallet already.

![](110/coldstart.png)
<!-- XXX options need reordering -->

There are four options are startup. If you are a beginner and don't have a Tezos account already, use the second (XXX this should be the first XXX) option.

1. Import your `octez-client` wallet (XXX this should be fourth). This option only appears if you have a directory called `~/.tezos-client` on your filesystem. If you have, you have used the `octez-client` command-line wallet. Signet will import this directory into its own directory and you'll be able to use the keys in Signet. Actually, Signet uses the same keystore format as `octez-client`, so you can use the keys with `octez-client -d ~/.signet`.

2. Create a new account.

![](110/create.png)

This option will generate a new key pair which will allow you to use the Tezos blockchain. If it's your first time using Tezos, you can create an account here. You can use the tz1 key type - we'll cover the other types in a later chapter. Simply choose a name for your address book ("My Account" is the default) and supply a password. The password encrypts the keys on disc making it harder for someone to steal them.

If this is your first time to a blockchain and cryptocurrency, welcome. You now have an account on the Tezos blockchain.

3. Import an existing account.

![](110/secret.png)

This option allows you to bring your keys from another wallet. If you can export the secret key from the wallet, you can paste it into the dialogue above, choose a name for it, optionally encrypt it with a password and add it. Alternatively if you have a recovery phrase, you can use the Recovery phrase tab:

![](110/recovery.png)

and import your key there. We will cover all the options on this import method in a later chapter.

4. Connect a Ledger

If your key is already set up on a Ledger with the Tezos Wallet application installed, you can use the key with Signet. Plug the ledger in and run the Tezos Wallet application, then choose the key type to add the key. We will cover this option more in a later chapter.

## Key hygiene

There's two rules for beginners.

1\. Before you do anything, back up your account keys.

Before you do anything, particularly anything involving monetary value, back up your keys. You may think: "Whatever I'll do it later". No, do it now. To do this on Signet is easy. Go to the Operations menu and choose `Export secret key...`.

![](110/export.png)

You can press the view button to look at it and write it down. Or you can use the copy facility to copy and paste it somewhere. The best way to back this up is write it down on paper. Keep two copies in a very safe place. We will go into more detail on key storage later on. But please do this step.

2\. Don't get too attached to your account.

There's a temptation to treat your crypto account like a bank account, but don't get too attached to it. You can make a new one very easily. With your first account, use it to try things out. Perhaps just use it on the test networks which we will cover in the next section. Once someone knows that this account is yours, they will know forever and they will be able to see all your transactions on the chain and know they are yours. When you've done a bit of experimenting, it might be worth generating some keys for different purposes. Perhaps you want to buy some NFTs and show your collection? Well, why not have a seperate key for that.

{#id: 150-othertypesofaccount_1_Other}
# Key Management

So far we have created a `tz1` key and used it for our transactions. There are other types of Tezos key and we will cover those in this chapter. There are also other ways to import a key into Signet. Also Signet can use a key on a hardware wallet called a Ledger. We will also look at ways of using keys temporarily in Signet and storing your keys offline.

{#id: 150-othertypesofaccount_2_Key_2}
## Key and Account Generation

When we started Signet, we created an account on Tezos and we created an account using the `tz1` key type. This is sufficient for most purposes, but there are other key types and other ways to get keys into Signet. You can create a new account at any time with `Create Account`. You can choose between five key types which we cover in the next section.

![](150/keytypes.png)

For most purposes, you can choose any key type. The `tz4` type was added recently and is good for baking, but it can still be used for normal accounts. The `tz5` type is new and is quantum resistant. It doesn't work on *Mainnet* yet but will soon.

During account creation, you can choose to protect the key with a password. This encrypts the key before it is stored on disk. You need to supply the password every time you want to use the key. This adds a layer of protection on the key, but choose your password carefully. If someone gets hold of the encrypted string, they could use a password cracker to decrypt the key. Using a complex password is best practice.

Once the account is created, you can use it to receive funds straightaway. When you do your first operation on the network, for example to send tez or to delegate or stake, your public key will be *revealed*. This means that it is available on the network and can be used to verify your operations. 

There are some things you cannot do if your public key is not revealed. These will not affect most users and we will see an example in the [Operations for Bakers](#190-baking_1_Operations) chapter.
￼
{#id: 150-othertypesofaccount_2_Key}
## Key Types

There are currently 6 types of keys on Tezos. You can tell which key you are using by its public key hash which begins with `tz`. Each key type uses a different signing scheme. You don't have to understand the different key types to use Tezos, just be aware that there are different key types and they sometimes have different uses. As a beginner to Tezos, you can use the `tz1` key type. You can safely skip this section if you want.

When you use `Create Account` on Signet, you are really generating a cryptographic key pair - a secret key (also called a private key) and a public key using a signing scheme. A *signing scheme* is the key generation algorithm together with a signing algorithm and a signature verifying algorithm. The signing algorithm is used on a blockchain to sign operations with the secret key and the signature verifying algorithm is used to check them with the public key. 

The secret key is chosen at random out of all possible secret keys. The number of possibilities is so huge that it is very unlikely for two people to generate the same secret key. The public key is converted into a common format (it is hashed) and becomes your Tezos address starting with `tz`. By doing this, there is a consistent key format across the different types of key. Also it allows the public key to be kept private until it is needed. The secret key is stored in the file `secret_keys` in your Signet wallet directory, the public key is stored in `public_keys` and the public key hash is stored in `public_key_hashs`. 

The secret key, as the name suggests, needs to be kept secret. If someone else gets the key, they have access to your funds and can sign operations with it.

The first key type uses the [EdDSA signature scheme](https://en.wikipedia.org/wiki/EdDSA). Two of the key types use the ECDSA signing scheme ([Elliptic Curve Digital Signature Algorithm](https://en.wikipedia.org/wiki/Elliptic_Curve_Digital_Signature_Algorithm)). Both use [elliptic curves](https://en.wikipedia.org/wiki/Elliptic_curve) - an abstract geometric mathematical object suitable for use in cryptography. Each type uses a different elliptic curve. The other keys use different signing schemes. Here are the key types available on Tezos today:

| Key type | Type      | Notes                                                                                                                                                                                   | Networks                                                                                                            |
| -------- | --------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| tz1      | Ed25519   | EdDSA signing scheme with the Curve25519 curve                                                                                                                                          | All                                                                                                                 |
| tz2      | Secp256k1 | ECDSA signing scheme with the Secp256k1 curve. The public key can also be used on Bitcoin and Ethereum-style networks                                                                   | All                                                                                                                 |
| tz3      | P-256     | ECDSA signing scheme with the P-256 curve (a.k.a. Secp256r1). This is a curve recommended by NIST. It is used in accredited hardware security modules.                                  | All                                                                                                                 |
| tz4      | BLS       | BLS signing scheme with the BLS12-381 curve. Can be used for consensus and companion keys on Mainnet to leverage the aggregation properties of BLS, improving consensus on the network. | All                                                                                                                 |
| tz5      | ML-DSA-44 | Using the ML-DSA-44 signing scheme, these keys are secure against classical and quantum computer attacks.                                                                               | Shadownet, Quantumnet, Ushuaianet. Cannot be used for baking.                                                       |
| tz6      | XMSS      | A stateful hash-based signing scheme. New to Tezos.                                                                                                                                     | Used as a consensus key for bakers on Quantumnet. The keys have a "finite budget" and need to be rotated regularly. |

You can generate and use keys of all types in Signet, except for `tz6` which is a relative newcomer and only available on the *Quantumnet* test network. You can safely use `tz1`, `tz2`, `tz3` and `tz4` keys today for day to day work on the Tezos production network *Mainnet.* The Ledger hardware security key only supports `tz1`, `tz2` and `tz3` keys.

Which key type you should use is up to you. It's expected that blockchains will shift to quantum resistant keys soon, so you may need to move your funds to a new address. This is another reason not to get attached to your address.

{#id: 150-othertypesofaccount_2_Importing}
## Importing Secret Keys

You can import secret keys that have been created in other Tezos wallets directly into Signet. You can paste them into the import window. If the secret key is encrypted, then you will be asked for the password and you will have to use it each time.

![](150/import.png)
Choose the name for your key - this is for your address book. Then paste in the secret key. Signet will work out the address. You can encrypt an unencrypted secret key if you want. 

Also you have the option to keep the key only until Signet quits. I added this feature because there are times where you want to use a key for a session but you don't want to keep it on disk. The key remains in memory for the session and when Signet exits, it will not be stored. 

I've added this feature to Signet because I want to use keys that I store on paper or a memory stick in a safe. The idea is to keep them off the internet as much as possible. Of course, a better way to do this is with a hardware security module, such as a Ledger.

{#id: 150-othertypesofaccount_2_Importing_2}
## Importing using a Recovery Phrase

On the same Import screen, there is a tab for a recovery phrase (or seed phrase). This allows you to import keys from phrases made from words, usually 12 or 24 words based on [Bitcoin Improvement Proposal BIP39](https://cryptotag.io/bip39-list/). An example is this (please don't use it!):

```
tuition blur they crop quantum dad pupil album season peanut possible lecture
```

The words represent a secret number which can be used to derive many cryptographic keys. In the Signet import, you can choose which `tz` key type to pick. You can also pick an account number which we will cover in the next section. You'll need to know which key type you used with the passphrase, but other wallets such as Temple, Kukai and Umami usually use the `tz1` account 0.
![](150/recover.png)
Similar to the secret key import, you can decide to keep the key just for the session in which case Signet will discard it when it exits. You can also encrypt the secret key with a password for storage.

{#id: 150-othertypesofaccount_2_Importing_3}
## Importing using a Fundraiser Account

Signet also supports fundraiser accounts although we doubt there are many of these around that have not been activated. A fundraiser account belongs to someone that participated in the original fundraiser. Flip the switch for Legacy fundraiser derivation:

![](150/fundraiser.png)
In addition to a recovery phrase, a fundraiser account has an email address and a fundraiser password. Supply all of these and then click `Import`.

{#id: 150-othertypesofaccount_2_The}
## The Key Hierarchy

In the recovery phrase import there is an account reference of the form `44'/1729'/0'/0'`. For each `tz` key type, you'll find a different key on each of `44'/1729'/0'/0'`, `44'/1729'/1'/0'`, `44'/1729'/2'/0'` and so on.

There is a general format defined in Bitcoin Improvement Proposals BIP32 and BIP44 called the *derivation path*:

```
m/purpose'/coin_type'/account'/change/address_index
```

The `m` is the private key which is not included in our account reference. The other fields mean:

| Field         | Definition                                                                                                                             |
| ------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| purpose       | Wallet standard - 44 means legacy, there are other values                                                                              |
| coin_type     | The coin. 0 is Bitcoin, 60 is Ethereum and 1729 (the [Hardy–Ramanujan number](https://en.wikipedia.org/wiki/Taxicab_number)) is Tezos. |
| account       | is the account number - you can have multiple accounts starting from 0                                                                 |
| change        | 0 for receiving addresses and 1 for internal addresses                                                                                 |
| address_index | A sequence number for an individual address                                                                                            |

The ' means that the derivation is a hardened derivation and the parent private key is required to calculate child keys. From the seed (the number represented by the seed phrase) you can derive many cryptographic keys. One seed can be used to set up accounts on many different blockchains. This is how the Ledger is set up, with one seed phrase. Some other wallets use this method too.

{#id: 150-othertypesofaccount_2_Connecting}
## Connecting a Ledger

A [Ledger](https://www.ledger.com) is a hardware security module that holds cryptographic keys for signing operations and plugs into your computer via USB. When you want to use your key, you attach it. When you have finished, you remove it and your key is safely offline. The Ledger supports many cryptocurrencies. It has a seed phrase and implements the key hierarchy above (without showing the detail to the user, unless they look of course). All the signing operations happen on the hardware device, so the keys never leave it.

To use a Ledger with Tezos, you need to run through the installation process with [Ledger Wallet](https://shop.ledger.com/pages/ledger-wallet-download) (formerly Ledger Live) and install the Tezos Wallet application from the Ledger app store. Once you have this, you can use the Ledger with Signet.

Plug the Ledger into your computer, open Signet and choose `Connect Ledger`. Signet will complain if it cannot find a Ledger. If it is plugged in and Signet can't find it, it is likely that you are not running the Tezos Wallet application.

![](150/ledger.png) 

Choose a name for the key in the ledger, pick the key type and account number. If you have used Ledger Live and you have a Tezos address on it, the `tz1` and `44'/1729'/0'/0'` path will match the same address. In Ledger Live, any additional accounts will be `tz1` and on path `44'/1729'/1'/0'`, `44'/1729'/2'/0'` and so on. You can also use `tz2` and `tz3` keys using the Ledger in Signet, but they will not be visible in the Ledger Live software.

Click `Add` and confirm the operation on your Ledger. Once the Ledger is connected, you can use the keys like any other keys in Signet. You'll need to connect the Ledger and open the Tezos Wallet application to use the key. When a transaction or operation is done, Signet will use the Ledger to sign it and you'll have to confirm it on the Ledger itself.

{#id: 150-othertypesofaccount_2_Exporting}
## Exporting Keys

You can export your secret keys from Signet at any time. Signet displays the key obscured until you click the view button or the copy button. You need to be incredibly careful handling this key. If you do copy it, make sure you clear your copy and paste buffer by copying something else. Avoid storing the key online anywhere. If someone gets into your files, they get your keys and then they have your funds.

![](150/export.png)


{#id: 150-othertypesofaccount_2_Storing}
## Storing Keys Offline

The best way to store keys as a backup is to store them on paper. Write down the secret key onto good quality paper using permanent ink that will not fade. Using printers or photocopiers to make copies is not necessarily a good idea. Some photocopiers have a memory and other people can print out previous jobs. Then they have your keys.

If you are worried further about offline security, you could shard the key. This is where you write down half of it on one piece of paper and the other half on another. Store one half in one location (e.g. a safe) and the other half in another (e.g. a vault somewhere else). This requires two safe locations. If you want a backup as well, you will need two additional safe locations. However, it's worth it if your key gives access to significant funds.

If you use a Ledger or another hardware security module to generate the key, you should store the seed materials (such as recovery phrase) in a similar way. You can break it up into shards if you like and store it in multiple locations.

{#id: 150-othertypesofaccount_2_Forgetting}
## Forgetting Keys

To remove a key from Signet, you can forget it. Choose the account, then choose `Forget account` from the burger menu.

![](150/forget1.png)

Signet will warn you of the implications. If you don't have a backup, you will probably lose the key forever. Press `Continue`.

![](150/forget2.png)
It then warns you again. To forget the key, click `Forget for good`.

There is one caveat here. The key might be stored in the backup folder still. The most reliable way to get rid of the key is to delete all the backups, but this is not necessarily recommended. You could go into `Settings`, take a backup and then delete the previous backups. You'll have to do this by hand. Forgetting accounts is not recommended, unless you really know what you are doing.

You can also use `Forget account` to delete an address book entry.
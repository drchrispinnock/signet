{#id: 150-othertypesofaccount_1_Other}
# Key Management

So far we have created a tz1 key and used it for our transactions. There are other types of Tezos key and we will cover those in this chapter. There are also other ways to import a key into Signet. Also Signet can use a key on a hardware wallet called a Ledger. We will also look at ways of using keys temporarily in Signet and storing your keys offline.

{#id: 150-othertypesofaccount_2_Key}
## Key types

There are currently 6 types of keys on Tezos. You can tell which key you are using by its public key hash which begins with `tz`. Each key type uses a different signing scheme. Here are the key types:

| Key type | Type      | Notes                                                                                                                                                                                     | Networks                                                                                                            |
| -------- | --------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| tz1      | Ed25519   | EcDSA signature scheme with the Curve25519 curve                                                                                                                                          | All                                                                                                                 |
| tz2      | Secp256k1 | EcDSA signature scheme with the Secp256k1 curve. The public key can also be used on Bitcoin and Ethereum-style networks                                                                   | All                                                                                                                 |
| tz3      | P-256     | EcDSA signature scheme with the P-256 curve (a.k.a. Secp256r1). This is a curve recommended by NIST and is supported by Hardware Security Modules.                                        | All                                                                                                                 |
| tz4      | BLS       | BLS signature scheme with the BLS12-381 curve. Can be used for consensus and companion keys on Mainnet to leverage the aggregation properties of BLS, improving consensus on the network. | All                                                                                                                 |
| tz5      | ML-DSA-44 | Using the ML-DSA-44 signature scheme, these keys are secure against classical and quantum computer attacks.                                                                               | Shadownet, Quantumnet, Ushuaianet. Cannot be used for baking.                                                       |
| tz6      | XMSS      | A stateful hash-based signature scheme. New to Tezos.                                                                                                                                     | Used as a consensus key for bakers on Quantumnet. The keys have a "finite budget" and need to be rotated regularly. |

You can generate keys of all types in Signet, except for tz6 which is a relative newcomer and only available on the *Quantumnet* test network.



{#id: 150-othertypesofaccount_2_Importing}
## Importing secret keys

{#id: 150-othertypesofaccount_2_Importing_2}
## Importing using a seed phrase

{#id: 150-othertypesofaccount_2_Importing_3}
## Importing using a fundraiser account

{#id: 150-othertypesofaccount_2_The}
## The key hierachy

{#id: 150-othertypesofaccount_2_Connecting}
## Connecting a ledger

{#id: 150-othertypesofaccount_2_Using}
## Using a key temporariliy

{#id: 150-othertypesofaccount_2_Exporting}
## Exporting keys

{#id: 150-othertypesofaccount_2_Storing}
## Storing keys offline

{#id: 150-othertypesofaccount_2_Key_2}
## Key ceremonies
# Etherlink and Tezos X

In 2023, smart rollups were introduced to the Tezos blockchain. A *rollup* is a means of processing transactions away from the main blockchain, "rolling them up" and injecting them back to main chain later on. A Tezos *smart* *rollup* is one managed by a computer program, usually written in WebAssembly (Wasm). These rollups are managed by a separate set of servers from the layer 1. There are *operators* which collect together, batch and commit the operations. There are *observers* that just listen to the rollup and record it. There are *endpoints* (also called *nodes*) which wallets and applications use to communicate with the rollup.

Etherlink is the first official rollup on Tezos and it brings an Ethereum compatible virtual machine to Tezos. This means that you can deploy an Ethereum smart contract on the Etherlink rollup without modification. Now Tezos smart contracts (written in Michelson XXX) can be deployed in the rollup and they can interact with the EVM contracts.

Tezos X is the strategic target architecture of Tezos and a potential outcome is a fast, but simple, layer 1 that does settling and staking, together with a rollup compatible with both EVM and Tezos. It's likely that dApps and day-to-day transactions will live on the rollup. 

On Etherlink, you can have Ethereum-style addresses beginning with 0x and Tezos-style addresses tz1, tz2 and tz3. If you have a Tezos account already, you can use your address on the rollup. There are other ways of getting addresses on Etherlink, but for now this is what Signet supports. 

The good news is Signet is capable of working with Etherlink and you don't have to understand much about rollups to use it. One thing to be aware of is that to use your funds on Etherlink, you have to bridge them to it.

At the moment, Signet doesn't support dApps on Etherlink, but it will in the future. It supports bridging funds to Etherlink and establishing your EVM address from your Tezos address.

## Setting up Signet to use Etherlink

xxx


## Bridging funds between Tezos and Etherlink

xx

## Sending and receiving

xx

## EVM address and receiving funds

xx



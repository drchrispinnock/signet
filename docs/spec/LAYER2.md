
# Etherlink

## 0.9

Every tz1, 2 and 3 key can be used on the rollup now, via the michelson interface RPC.

### RPCs
- In settings, add a tick box to each network called Enable L2.
- For Mainnet and Shadownet it should be ticked by default
- When ticked, there is a second node called L2 Node.
- The defaults are:
- - mainnet:  https://michelson.etherlink.mainnet.octez.io 
- - shadownet: https://michelson.etherlink.shadownet.octez.io 

### Balances

- Only on networks where we have layer 2 enabled please
- When we have a tz1, 2 or 3 key selected, display a balance for Etherlink. Use the same format as the TEzos one but use the Etherlink logo (which we originally had in the very first PoC please). If it comes back as unrevealed, you can list 0 for now (and perhaps indicate that the key has not been revealed yet).

## 0.9.1

When on a tz1, 2 or 3 address with Layer 2 enabled, there should be a new burger item called Bridge

This opens a dialogue up with Tez on the left and Etherlink on the right (logo). The user can choose which direction to go in. If it is from Etherlink to Tez, there should be an option to choose Fast or Slow. In all cases, there should be an amount of tez. On confirmation, the tz coins should be bridged between the networks.

## 0.9.2

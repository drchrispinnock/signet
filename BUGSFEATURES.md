# Bugs and Features for 0.9 release

## Payment providers

- [x] Add Transak as second provider (browser hand-off, 0.9.5)

## Etherlink

- [ ] Transactions need to go into the recent transactions
- [ ] Assets need to go into the assets tab
- [ ] NFTs also
- [ ] There ought to be a way of segregating

## Audit

- [ ] Continual Codex audit
- [ ] Run the slop auditor and look at fixes

## Multi-sig

- [ ] Option to Delete transactions in the queue - they might not be needed anymore

# Later

- [ ] Offline signing (e.g. go to the vault, no internet, sign a transaction and submit later)
- [ ] Double check each network against a known chain ID held in our code. If it mismatches, display a red error at the bottom next to the node status.
- [ ] Have a tunable for this check to turn it off in Networks. Turn it off by default on Custom and Weeklynet.

# Done

## Node statuses
- [X] Remove levels and synced (green is enough)

## Key Management

- [x] Indicate that a key will be forgotten in the UI on exit 
- [x] Perhaps "Remember key" option for these session only keys

## Menus and Settings

- [x] Rename "Connect to dApp..." to "dApps..."
- [x] Remove the node selection settings from Settings and add a new menu called Nodes... (called Networks)
- [x] Add in the block explorer, faucet and tzkt (API?) links used on each network - make them configurable. Obviously mainnet has no faucet.

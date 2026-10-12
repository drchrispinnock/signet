# Bugs and Features for 0.8.3 release

## Key management

- [ ] When importing a key, have a radio to forget the key at the end of the Signet session. The idea of this is to use "paper keys" for one session and then forget it. The key must be held in memory and not on disc in this case. We need to think about crash dumps but that is only relevant if the application crashes with the key in memory - is there a way to avoid this?

## Multisig contracts

- [ ] We had three accounts Alice, Bob and Christopher on a multisig contract with 2/3 required. Alice signed the transaction and added Bob's key. The transaction transferred 5 to Capt Stake. The contract worked as intended, however the Signet transactions should that 5 went to Alice (as we as Capt Stake). I suspect there is some transaction saving logic somewhere.

- [ ] There should be provision to transfer funds into the multisig contract at its creation (this can be 0 and 0 should be the default).

## Test networks

- [ ] Currentnet's transaction display is not working - this is because currentnet is an alias for the current protocol. We need to think about mapping this to the correct tzkt instance.

# Bugs and Features for 0.8.4 release

## AI Slop

- [ ] Run the slop auditor and look at fixes

# Bugs and Features for 0.9 release

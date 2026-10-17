# Multisig accounts

A *multisig account* is one where more than one account needs to sign the transaction. The set of accounts that sign the transaction is called a *committee*. The whole *committee* doesn't need to sign the transactions necessarily. When the multisig account is set up, the originator can choose how many of the committee is needed to sign.

On Tezos, there is a native multisig account feature. It is available in the command-line wallet `octez-client`. It works by deploying a smart contract holding the balance of the account, with the code implementing the signing committee. Signet implements the feature in exactly the same way, but provides a graphical user interface.

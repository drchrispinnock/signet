{#id: 165-Settings_1_Settings}
# Settings

You can configure Signet using its Settings facility. Additionally you can change the nodes and services that Signet uses on each network, including turning features on and off. This chapter covers the settings screens.

{#id: 165-Settings_2_Applicatio}
## General Settings

You can get to the general settings for Signet either by choosing `Settings...` in the burger menu, in the Operations menu, in the Signet menu or by pressing Command and , (`Cmd+,`). Here are the options:
![](165/settings.png)
Firstly, you can set the appearance of the application. You can choose either Light or Dark mode, or you can follow the OS preference. The images in this book were made in Light mode. I prefer Dark mode for day to day use.

You can set the wallet directory. Signet stores its files including your keys in your home directory in a folder called `.signet`. You can change the location if you want.

Signet automatically backs up its wallet directory every time you start it. You can change the destination of the backups here and you can also change the number of backups that Signet keeps. By default, it keeps 10 copies.

Should you want to restore from a backup, you can navigate to the directory by pressing `Show in Finder`. The relevant backup file (they are dated) can be moved to `~/.signet` to recover a previous state. Please be careful not to delete any keys by accident.

![](165/finder.png)
You can also initiate a backup with the `Back Up Now` button.

Finally, Signet uses the Sparkle framework and can update itself. You can choose if you want to check for software updates automatically, and also download and install them automatically. You can check now for updates with the button. There is also an option in the Signet menu in the menu bar.

{#id: 165-Settings_2_Network}
## Network Settings

The network settings are for advanced users. They are accessed from the burger menu from `Networks...`. You can drop down the network and change it. The networks available are *Shadownet, Bakingnet, Ushuaianet, Weeklynet, Quantumnet* and *Custom.* Custom allows you to connect to any nodes. This is the page for *Mainnet*:
![](165/networks.png)
It shows that the network is the one we are using at the moment next to the network name. We can do several things here. We can change the node we use to communicate with the Tezos network. By default, Signet uses https://rpc.tzbeta.net which is provided by the Tezos Foundation. There are other public nodes. At the time of writing:

| Mainnet node                   | Provider                                     |
| ------------------------------ | -------------------------------------------- |
| https://mainnet.smartpy.io     | [SmartPy](https://smartpy.tezos.com)         |
| https://rpc.tzbeta.net         | [Tezos Foundation](https://tezos.foundation) |
| https://tezos-mainnet.octez.io | [Trilitech](https://www.trili.tech)          |
| https://rpc.tzkt.io/mainnet    | [TzKT](https://tzkt.io)                      |

When choosing a node, it is important to understand that the node provider could control your data unexpectedly. Although they cannot change your signed operations, they could censor them and not submit them to the network. They could also provide you with incorrect information. Choose a node provider that you trust. You can also run your own node if you want - we cover this in [the appendix](#910-apx-ownnode_1_Running).

Signet will attempt to check that the node is running on the correct network. If we try to use a node on *Shadownet* in the *Mainnet* configuration, Signet will warn us.

![](165/warn.png)

We can continue anyway but Signet won't work properly on *Mainnet.* You can always reset each node to the default with `Use Default`.

You can also change the API service for TzKT and the URL for the block explorer. You are unlikely to need to change these, but you can replace the URL with another block explorer's address. If you run your own TzKT API node (e.g. for development purposes), you can use it by changing this field.

You can also turn on Layer 2 support in this screen. Flicking the switch makes Signet capable of working on Etherlink, a network implemented in a smart rollup on Tezos. 

![](165/withether.png)
Now we can change the layer 2 Michelson endpoint node. This is the Tezos compatible RPC node on Etherlink. You are unlikely to need to change this for now, but more node providers will appear in the future. If you go back to the main screen, you will see the Etherlink logo and a balance for it. Please see the [Etherlink chapter](#200-etherlink_1_Etherlink) below for more detail.

If we switch to *Shadownet*, we'll see that test networks have one further setting.

![](165/shadow.png)
We can change the faucet address here. It's unlikely that we will need to do this, but I wanted to make Signet as configurable as possible. And *Quantumnet* uses a different scheme of links. You can check the differences in Signet yourself.

Finally, we can add a *Custom* network. You can use *Custom* to quickly switch to an alternative node, or one you've set up yourself. If you are a developer, you can use *Custom* to connect to your own Tezos test network. 

{#id: 165-Settings_2_Shielded}
## Shielded Settings

These settings are for the highly experimental support for the Tezos Encrypted Ledger (TzEL). We will cover these in a later edition of the book.
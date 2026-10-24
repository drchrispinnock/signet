{#id: 165-Settings_1_Settings}
# Settings

You can configure Signet using its Settings facility. Additionally you can change the nodes and services that Signet uses on each network, including turning features on and off. This chapter covers the settings screens.

{#id: 165-Settings_2_Applicatio}
## General Settings

You can get to the general settings for Signet either by choosing `Settings...` in the burger menu, in the Operations menu, in the Signet menu or by pressing Command and , (`CMD+,).` Here are the options:



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


{#id: 165-Settings_2_Shielded}
## Shielded Settings

This settings are for the highly experimental support for the Tezos Encrypted Ledger (Tzel). We may cover these in a later edition of the book.
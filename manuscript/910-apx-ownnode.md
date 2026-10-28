{#id: 910-apx-ownnode_1_Running}
# Appendix - Running your own node

{#id: 910-apx-ownnode_2_Running}
## Running nodes

You can connect to any Tezos node from Signet. We will cover running a node on your Mac and running it on a server on your home network. The Octez suite contains `octez-node`, the node and we will show you how to install that.

In the case of running the node on the same machine as Signet, the node address will be `http://localhost:8732`. For the server, on your home network, you'll need the IP address. For example, if it is 192.168.1.140, the node address will be `http://192.168.1.140:8732`.

In Signet, go to the `Networks...` page and choose `Custom`. Fill out the node address in the dialogue:

![](910/custom.png)
By default, Signet will try to use the node on the local machine. Alternatively, if you are running the node on *Mainnet,* you can simply change the node in the settings there. 

{#id: 910-apx-ownnode_2_Running_2}
## Running directly on your Mac

You can run your own node on your Mac and connect Signet to it. You'll need to have enough RAM to support the node and also your other applications. The easiest way to do this is to use Docker. Install Docker Desktop from the [Docker site](https://www.docker.com/products/docker-desktop/) and run it. 

Docker Desktop reserves half of the system memory for Docker. If you have 16GB of RAM, it will limit memory usage to 8GB which might not be enough. You can change this by clicking the settings cog top right, going into `Resources` and changing the Memory Limit to 16GB.

Then run the `Terminal` application (you can search for it in Spotlight Search). In the commands below, `$` represents the shell prompt; do not type it. Get the latest release of Octez:

```
$ docker pull tezos/tezos:latest
```

Make a node directory and configure the node to use it. We've split the long lines with `\`.

```
$ mkdir ${HOME}/node
$ docker run -v ${HOME}/node:/home/tezos/.tezos-node \
	-p 8732:8732 \
	--entrypoint /usr/local/bin/octez-node \
	tezos/tezos config init --network=mainnet \
	--rpc-addr=0.0.0.0 --allow-all-rpc=0.0.0.0 \
	--net-addr=0.0.0.0
```

If you run the node now it will attempt to sync the network state from the genesis block, which will take a long time. You can import a backup called a snapshot.

```
$ cd
$ curl -o rolling https://snapshots.tzinit.org/mainnet/rolling
$ docker run -v ${HOME}/rolling:/snapshot \
    -v ~/node:/home/tezos/.tezos-node \
    --entrypoint /usr/local/bin/octez-node \
    tezos/tezos snapshot import /snapshot
$ rm rolling
```

Now run the node:

```
$ docker run -d -v ${HOME}/node:/home/tezos/.tezos-node \
   	--entrypoint /usr/local/bin/octez-node \
	--name node -p 8732:8732 -P \
	tezos/tezos run
```

You can observe the logs with:

```
docker logs -f node
```

You can now connect to the node from Signet with `http://localhost:8732`.

The other way to do it is to build Octez from source. This is beyond the scope of this book, but you can find details at the [Octez documentation site](https://octez.tezos.com/docs/introduction/howtobuild.html) and also in <!-- MARKUPBIBTAG 63d75376 -->[??]<!-- ENDMARKUPBIBTAG -->. Once you have it installed, open the `Terminal` application and configure the node:

```
$ octez-node config init --network=mainnet \
	--history-mode=rolling 
	--net-addr="0.0.0.0" \
	--rpc-addr="127.0.0.1"
```

Import a snapshot (as with the docker method).

```
$ wget https://snapshots.tzinit.org/mainnet/rolling
$ octez-node snapshot import rolling
$ rm -f rolling
```

Then you can run the node in the terminal and see the progress there. Then connect Signet to the node as above.

```
$ octez-node run
Oct 24 19:17:14.046 NOTICE │ the node configuration has been successfully
Oct 24 19:17:14.046 NOTICE │   validated.
Oct 24 19:17:14.046 NOTICE │ generating an identity file
Generating a new identity... (level: 26.00)
....
```

You can get your Mac to use a dedicated user (e.g. tezos) to run the Octez software and you can set it up to run at boot using launchctl. For more details see ￼ or ￼.


{#id: 910-apx-ownnode_2_Running_3}
## Running on a Linux Server

If you have a Linux machine on your home network, you can set it up to be a node very easily. The Tezos Foundation provides packages of the Octez software via the [Tzinit project](https://packages.tzinit.org). A rolling node is suitable for most applications.

For Debian Linux 13, you can install the release version of `octez-node`, the node, as follows:

As a user with `sudo` access:

```
$ sudo apt install extrepo
$ sudo extrepo enable tzinit
$ sudo apt update
$ sudo apt install -y octez-node
```

Then to configure your node, become the tezos user and run these commands:

```
$ sudo su - tezos
$ octez-node config init --network=mainnet \
	--history-mode=rolling \
	--net-addr="0.0.0.0" \
	--rpc-addr="0.0.0.0" \
	--allow-all-rpc="0.0.0.0"
```

This will set up a node that you can do everything with. This is fine if you are running a node on a private home network, but if it will be directly on the internet, you should protect it with a firewall or consider removing the `--allow-all-rpc` which allows operations that might cause your node to use a lot of resources.

As with the method for the Mac above, you can import a backup called a snapshot.

```
$ wget https://snapshots.tzinit.org/mainnet/rolling
$ octez-node snapshot import rolling
$ rm -f rolling
$ exit
```

Now you can set up the node to start now and run at boot:

```
$ sudo systemctl enable octez-node
$ sudo systemctl start octez-node
```

Connect Signet to the node as per the first section in this Appendix. You'll need the IP address of your Linux machine and you can get this on Debian Linux 13 using `ifconfig` - for example, in this case 192.168.1.140.


```
$ ifconfig -a
....
eth0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1500
        inet 192.168.1.140  netmask 255.255.255.0  broadcast 192.168.1.255
        inet6 fe80::7e3d:9ff:fec3:3661  prefixlen 64  scopeid 0x20<link>
...
```

{#id: 910-apx-ownnode_2_Running_4}
## Running nodes on test networks

If you want to run a node on a different network to *Mainnet*, replace `mainnet` with the values below. For the snapshot, use the link below instead of the one above. For some test networks such as *Weeklynet* and *Quantumnet*, you may need development versions of the software instead of the release.

| Network      | --network=                                                  |
| ------------ | ----------------------------------------------------------- |
| *Shadownet*  | https://teztnets.com/shadownet                              |
| *Bakingnet*  | https://teztnets.com/bakingnet                              |
| *Ushuaianet* | https://teztnets.com/ushuaianet                             |
| *Quantumnet* | https://quantumnet.pqpark.dal.nomadic-labs.com/network.json |

| Network      | Snapshot                                                                |
| ------------ | ----------------------------------------------------------------------- |
| *Shadownet*  | https://snapshots.tzinit.org/shadownet/rolling                          |
| *Bakingnet*  | https://snapshots.tzinit.org/bakingnet/rolling                          |
| *Ushuaianet* | https://snapshots.tzinit.org/ushuaianet/rolling                         |
| *Quantumnet* | https://quantumnet.pqpark.dal.nomadic-labs.com/snapshots/latest.rolling |

For *Weeklynet*, refer to the instructions at the [Teztnets site](https://teztnets.com), as it reboots every week. 

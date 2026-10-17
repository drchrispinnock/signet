# What's Coming in Signet

Signet is still under development and I will continue to add features for the foreseeable future. Here are some possible directions.

## Windows and Linux support

I am getting Claude to port the application to Windows 11 as a native application. This will take me some time. If there is enough demand, I may port to Linux as well. The problem will be one of maintenance - I will add a feature to the Mac version and then have to port it (or do it independently on the other platforms).

## Mobile support

Claude tells me it would be easy to make an iOS application out of the current codebase. However, that means using an app store and we would be restricted by their rules. I suspect I would have to remove support for buying tez directly in the app.

## Post-quantum support

Once Taquito supports tz6 addresses, I will add support for them. They will likely only be used for consensus, but for completeness we will need to use them on the chains.

## Octez.JS vs Taquito

Currently I'm using Taquito because it added tz5 addresses early and I wanted to get Signet on Quantumnet. I will continue with Taquito whilst it's supported.

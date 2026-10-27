
Bakers can vote in the etherlink governance process. Also, bakers can elect for another key to vote on their behalf. So we should see if we can identify these keys, or just attempt to vote with any key.

For mainnet, the slow process is KT1VZVNCNnhUp7s15d9RsdycP7C1iwYhAQ8r
The fast process is KT1DxndcFitAbxLdJCN3C1pPivqbC3RJxD1R

We should hold these in configuration, under the layer 2 tab I think. (For
the test networks, defaults should be blank).

To propose:

octez-client call <CONTRACT> from <KEY> \
  --entrypoint "new_proposal" \
  --arg "0x<KERNEL_HASH>"

To upvote the octez-client command is:

octez-client call <CONTRACT> from <KEY> \
  --entrypoint "upvote_proposal" \
  --arg "<KERNEL_HASH>"

  where <CONTRACT> is one of the contracts above, KEY is the key and 
  KERNEL_HASH is a hash supplied by the user beginning 0x

For upvote_proposal, it would be good to be able to choose the proposal from the ones that have been proposed.

To vote:

octez-client call <CONTRACT> from <KEY> --entrypoint "vote" --arg '"<VOTE>"'

where VOTE is pass, yea, nay

(check the last two please).

I'm not sure how we check which phase of governance we are in. Perhaps you could read the docs for me? https://docs.etherlink.com/governance/how-is-etherlink-governed/

So on Governance... we can have a tab for Etherlink. We only display governance for bakers. If we have a way of determining if the key is a voting key, then use that or we have to display the Governance option for all.

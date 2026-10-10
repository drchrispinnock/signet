# Updated frontend review

Screenshots captured from the local dark-mode demo on 10 October 2026.
All accounts and balances are sample data. No transactions were signed.

- [Frontend PDF: 12 views](signet-updated-frontend.pdf)
- [Overview](frontend-overview.png)
- [Dashboard](dashboard.png)
- [Send](send.png)
- [3Route connection sheet](swap.png)

To try the interactive frontend on macOS, run `./scripts/preview.sh` from the
repository root. It builds an isolated app with bundle identifier
`org.tezos.signet.demo` and starts it with `--demo`. Account edits stay in memory;
dApp pairing and signing are unavailable in the demo.

Swap uses 3Route in the browser with the existing Octez Connect permission and
transaction approval flow in Signet. There is no native quote API integration.
Real-account pairing and live swaps have not been tested.

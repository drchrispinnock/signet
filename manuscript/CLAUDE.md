# CLAUDE.md (manuscript)

Guidance for working on the Signet book in this directory. The app's own guidance is in `../CLAUDE.md`.

## What this is

The Leanpub book about Signet, a Tezos wallet. `Book.txt` lists the chapters in order; a line
starting `#` is left out of the build (`#210-shield.md`: TzEL is deliberately not covered, and
`006-DevelopingSignet.md` says so). Images live in `resources/<chapter number>/`, referenced as
`![](110/foo.png)`. Two git branches, `book_preview` and `book_release`, feed Leanpub's preview
and publish builds (PDF and EPUB).

The author writes in **Markup**, their own Markdown editor, and often edits a file while a review
is running. Markup manages the `{#id: ...}` lines and the `<!-- MARKUPBIBTAG ... -->` citation tags:
never flag or change them, even when an ID's prefix doesn't match the file name.

## How reviews work here

- The usual request is "check X" followed by "and now?" (in any language). Every time, re-read the
  file from disk (check `ls -l` for the save time) and report what's now fixed and what's still
  outstanding. Never work from an earlier read.
- Before editing, re-read the file and make substitutions that fail safely if the text has changed.
  Keep a copy of the pre-edit file in the scratchpad. Edit only when asked; by default, report.
- Group findings: facts first, then the style guide, spelling, wording and layout/whitespace.
  Give line numbers.
- Check claims against the app's source (`../Signet`) and releases where it's cheap to: button and
  menu labels, release asset names, and the APT key fingerprint.
- Accept the author's decisions and don't raise them again. Settled: the author ran `claude init`
  (don't "correct" it to `/init`); well-known Tezos people such as Arthur need no surname; section
  IDs are fine.

## House style

- `STANDARDS.md` is the style guide. Network names go in italics with a capital letter
  (*Mainnet*, *Shadownet*), and punctuation goes outside the italics (`*Mainnet*.`). Menu items go
  in code font. It's TzKT and TzEL. `tz` addresses go in code font.
- Menu items use the app's exact labels, including the ellipsis: `Export secret key...`,
  `Add address...`, `Connect Ledger...`, `Create multisig...`, `Check for Updates...`. Cold-start
  buttons are `Create a new account`, `Import an existing account`, `Connect a Ledger`.
- Terminology: each address is an **account**, and the **wallet** is the whole app. The coin is
  **tez**, lower case. Ledger is capitalised.
- British spelling: decentralised, practise (verb), catalogue, dialogue. But "disk" for storage,
  and "website" as one word. Also cooling-off, double-check, browser-based, quantum-resistant,
  open-source (as an adjective), pre-built.
- Leave a blank line before and after every image. Footnotes are `[^1]:`, not `[^1:]`.
- No trailing spaces, no doubled blank lines, and one final newline. Exception: two spaces at the
  end of a line are a deliberate Markdown line break (for example, the preface signature).
- `<!-- XXX ... -->` comments and italic "at the time of writing" notes are placeholders. Flag
  any left in a chapter as "resolve before publishing".

## Facts to keep consistent

- Signet runs on the Mac (Swift, `drchrispinnock/signet`), Windows (C#, `signet-windows`) and Linux
  (GTK, Swift, `signet-gtk`). 0.9.13 was the first release where all three had the same features,
  and 0.9.14 came out on 7th November 2026. The book uses the Mac version for screenshots.
- Development started on Monday 5th October 2026. Mac releases ship as both a DMG and a zip.
- The Linux APT repository is `apt.signetwallet.org` (Debian 13, trixie). The signing key
  fingerprint is `867D46AE151D860DCA62F18739AF78B567D9A004`; verify it with `gpg --show-keys`.
  The install steps must run `sudo apt update` before `apt install`.
- Mt Pelerin is the only integrated on-ramp and doesn't serve the USA. Coinbase, Kraken and
  Transak are links out to the browser.
- The book says "vibe coding" (no hyphen) for the noun, and defines it in `006-DevelopingSignet.md`.

## Review status (11th November 2026)

`REVIEW.md` is the authoritative numbered progress tracker. Preserve its finding numbers,
anchors and original findings; move completed items into DONE with dated completion notes.
Do not interpret original findings archived under DONE as active requests.

Completed numbered findings: 1, 2, 3, 6, 10, 11, 12, 16, 17, 21, 22, 24, 26, 27, 28,
29, 30, 31, 32, 33, 34, 36. Finding 23 has only Docker version pinning outstanding.
Finding 25's text is corrected; complete Debian 13 execution validation remains unverified.
Other active findings have not been resolved by this targeted session.

The 11 November work was a series of targeted source checks, not a fresh whole-book or PDF
review. The Bob signing and 15 tez send/confirmation screenshots were visually verified.
No nodes, wallet operations or Debian installs were run. No new PDF was generated.

Earlier prose reviews covered 005, 006, 007, 915 and 918. Do not call entire other chapters
finished merely because individual findings are done. Installation placeholders in 110 remain;
the earlier doubled “the the” is fixed. Remaining small typo: 110 line 112 says “a key pair
and an address are ready”; remove “are”. Two stray U+FFFC characters remain only in the unused
`networks-material.md` draft, not the published passages covered by finding 31.

## Decisions and details from the 11 November review

- The author runs Docker with a 16GB memory limit successfully. Accept this tested setting;
  the text now makes readers' choice hardware-dependent. Do not reopen finding 24 as a claim
  that the configuration cannot work.
- Docker RPC must listen on 0.0.0.0 inside the container; the same-Mac example publishes it
  on host 127.0.0.1:8732:8732. The unnecessary -P is removed. Do not confuse these bindings.
- The author confirms Octez Connect support was patched. Updated dApps can offer direct
  Signet pairing; manual pairing depends on a compatible code being available.
- The Preface is dated 14 November 2026. The development story now covers just over a month
  from 5 October and completion of the first draft in November; the old 23-day frame is gone.
- The seven-day Mt Pelerin wait is the author's experience, separate from the FCA minimum
  24-hour promotion pause. The current Getting Started wording makes this distinction.
- The consensus-key passage now names the spendable-balance exposure and activation two
  cycles after the current cycle, checked against Ushuaia documentation. Keep version scope
  in mind when revisiting protocol claims.
- Backticks were added to bare tz1–tz5 labels in chapters and networks-material.md, preserving
  code blocks and unrelated author changes. The two final published U+FFFC characters were
  removed without altering Markup citation tags.

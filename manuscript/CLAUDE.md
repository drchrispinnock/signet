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

## Review status (9th November 2026)

Done: `005-Preface.md`, `006-DevelopingSignet.md`, `007-Disclaimer.md`, `915-colophon.md`,
`918-acknowledgements.md`.
`110-starting.md` is done apart from the placeholders on lines 30, 36 and 37, a doubled "the the"
on line 46 and one doubled blank line. Not yet reviewed: 100, 140–200, 250, 910, 920.

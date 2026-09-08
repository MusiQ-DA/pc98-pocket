---
name: deploy
description: Wait for the current CI build, fetch the bitstream, convert it to the Pocket's rbf_r format, wait for the SD card to be mounted, copy, verify and eject. Use when a build has been pushed and the result needs to reach the hardware — including when the card is not plugged in yet, since it waits. Also use to re-flash a specific run number or to target a named core directory.
---

# Deploying a build to the Pocket

`scripts/deploy.sh` does the whole loop. Run it in the background and report
what it says; do not re-implement the steps by hand.

```
scripts/deploy.sh                  # latest run -> hiroya.PCXTDEV
scripts/deploy.sh --core PCXTA     # into a named core directory
scripts/deploy.sh --run 87         # a specific run
scripts/deploy.sh --no-eject       # leave the card mounted
```

Always launch it with `run_in_background: true`. It polls CI every 45 s and the
card every 15 s, for up to 90 minutes, so it will happily sit waiting while the
user is asleep or the Pocket is unplugged. Tell the user it is running and that
they can plug the card in whenever.

## What it guards against

Each check exists because its absence cost a hardware round trip:

- **The Quartus job is checked separately from the run's overall result.** A red
  sim job or a red timing gate after a good compile still leaves a usable
  bitstream; refusing to flash those wastes a build.
- **The converted image's header is verified** before anything touches the card.
  The conversion is a bit-order reversal within each byte, *not* xor 0xFF — the
  wrong one produces a Load error on the Pocket and looks like a core bug.
- **The copy is compared back** off the card, and the card is ejected. macOS
  caches writes; without the eject the Pocket can read the previous image, which
  looks exactly like "the fix did nothing".

## Several variants at once

`scripts/package_variant.sh <artifact_dir> <letter> <description>` builds a
whole core directory (`hiroya.PCXT<letter>`, matching shortname, its own Assets
folder) so multiple builds can sit on one card and be chosen from the Pocket's
menu instead of swapped by hand. Use it when there is more than one hypothesis
to test in a session.

## Reading the result

The core carries a POST monitor (`post_monitor.sv` and the OSD strip drawn by
`postmon.c`). `docs/HANDOVER.md` has the POST code map for the shipped BIOS and
what each field means. `MAX` is the furthest code reached; `POST` and `SEQ` are
frozen at the first eight and are not the same thing — mixing them up has
produced wrong conclusions here before.

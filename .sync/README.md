# Exact worktree snapshot

Repository: `ZTSCODE/medieval-shop-romance`
Branch: `sync/dot-approved-20261005-055546`
Godot: `4.7.1.stable.official.a13da4feb`

All game files preserve the captured local bytes. Intentional deletions are retained. This directory contains transfer metadata only; no game code was modified for the sync. `SOURCE-SHA256SUMS.txt` and `source-manifest.json` describe the 1,590 source files, including 430 Godot `.import` settings. The source manifest excludes only local caches, credentials/configuration and generated production/review outputs.

## Required opening film

`assets/video/opening/opening_film.ogv` exceeds GitHub's 100 MiB regular Git limit. The original file is stored as an asset on the same private repository's draft release `sync-dot-20261005-055546`. It is included at its original path in the complete Library snapshot. LFS is not used, and the film was not re-encoded. A plain Git checkout requires this one additional download.

From an authenticated GitHub CLI in the project directory:

```
gh release download sync-dot-20261005-055546 --repo ZTSCODE/medieval-shop-romance --pattern opening_film.ogv --dir assets/video/opening
```

Verify the opening film SHA256 against `large-assets.json`; verify all source files against `SOURCE-SHA256SUMS.txt`. Do not overwrite a locally modified asset.

## Open the snapshot

Unpack the complete snapshot into a new directory, import `project.godot` with Godot 4.7.1, and allow Godot to regenerate `.godot/` and the two `.translation` files from `localization/game.csv`. No original save data is included. Preserve the source `.import` settings. The snapshot's `.sync/COMMIT.json` records the exact Git commit and tree. The game uses Forward Plus; Windows selects D3D12.

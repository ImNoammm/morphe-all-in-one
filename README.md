# Morphe All-in-One

**One** Morphe patch source that bundles patches from **all** the community Morphe patch
repositories at once — so you add a single source instead of hunting down and adding dozens.

The bundle is rebuilt automatically every day, so it always tracks the latest release of
every upstream repository.

## Add it to Morphe

Open this link on a device with Morphe installed:

> https://morphe.software/add-source?github=ImNoammm/morphe-all-in-one&name=All-in-One

or, in the app: **Sources → + → Remote**, and paste this exact repository URL:

```
https://github.com/ImNoammm/morphe-all-in-one
```

Direct metadata URL (also accepted by Morphe):

```
https://raw.githubusercontent.com/ImNoammm/morphe-all-in-one/main/patches-bundle.json
```

If an earlier attempt is still listed as **Metadata N/A**, refresh it or remove it and add it
again with either URL above.

Morphe fetches `patches-bundle.json` from this repo, downloads the merged `.mpp` from the
latest Release, and keeps it updated on its normal schedule. Use **Expert mode** to browse
every included patch; enable per-app what you want.

> ⚠️ Only add patch sources you trust — a patch source decides what ends up inside your
> patched apps. This repo simply re-bundles other people's public patches; review
> `sources.json` to see exactly what is included.

## What's inside

Patches from **72 community repositories** (see `sources.json`), including the official
YouTube / YT Music / Reddit set plus community patches for Twitter/X, Instagram, TikTok,
Spotify-likes, Reddit clients, Gboard, Android TV, WhatsApp, Edge, and many more.

## How the merge works (and why it isn't trivial)

A Morphe patch source resolves to **exactly one** `.mpp` bundle — the app has no built-in
way to federate several sources under one entry. So "add one, get all" requires physically
**merging** every bundle into one.

That is harder than concatenating files. Each `.mpp` is a JAR whose patches are compiled
code (`classes.dex` for the Android manager, `.class` for the desktop patcher). Every
repository is a fork of the same `morphe-patches-template`, so they all ship their own copy
of the shared patch-library classes (`app.morphe.patches.*`) — built against **different
patcher versions** with **incompatible method signatures**. Naively merging them makes one
source's patch call another source's copy of a shared helper and crash the entire bundle
(`NoSuchMethodError`) at load.

The build pipeline (`build.sh`) solves this by treating the first source
(`MorpheApp/morphe-patches`) as canonical and **namespace-relocating** every other source's
`app.morphe.patches.*` classes to a unique prefix (`app.morphe.patches_sN.*`) in **both**
the `.class` files (via ASM / jar-relocator) and the DEX (via baksmali → rewrite → smali).
Each source then references its **own** shared helpers with matching signatures, framework /
Kotlin / Gson classes are de-duplicated (provided once, as the originals expect), and the
result is one clean multidex bundle that loads every source's patches together.

This was verified end-to-end with the real Morphe patcher (`morphe-desktop list-patches`):
merging the official + Hoodles + Rushiranpise bundles yields exactly `136 + 78 + 295 = 509`
patches with no load errors.

### Notes & trade-offs
- When several repositories patch the **same app**, all of their patches appear (pick the
  one you want in Expert mode). Ordering in `sources.json` is the priority: the primary is
  canonical, and earlier entries win when a shared resource can only have one copy.
- Any source whose latest release has no `.mpp`, or that fails to merge, is **skipped**
  automatically — one bad repo never breaks the build (see the release notes / merge report).
- This is a re-bundler; it authors no patches. See `NOTICE.md`.

## Rebuilding / contributing
- Edit `sources.json` to add/remove/reorder sources.
- The `Build aggregated bundle` GitHub Action rebuilds on push, daily, or via manual
  dispatch, publishes the merged `.mpp` as a Release, and updates `patches-bundle.json`.
- Run locally: `GITHUB_TOKEN=... REPO_SLUG=ImNoammm/morphe-all-in-one bash build.sh`
  (needs `java`, `smali`/`baksmali`, `jq`, `zip`).

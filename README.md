# Morphe All-in-One

**One** Morphe patch source that combines every bundle listed in the
[Morphe Community Patches catalog](https://morphe-patches.software/#bundles), plus additional
configured community repositories — so you add a single source instead of hunting down dozens.

The bundle is rebuilt automatically every day to refresh the configured upstreams. Newly listed
catalog bundles are added to `sources.json` explicitly; the daily job does not discover them.

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
latest Release, and keeps it updated on its normal schedule.

> **Duplicate-app warning:** Morphe sees the merged `.mpp` as one bundle. When multiple
> upstreams target the same app, Simple mode may select default patches from several of them
> in one run. Namespace relocation prevents shared-library **load** failures; it does not detect
> or prevent apply-time conflicts between patches. Use **Expert mode** and avoid overlapping
> alternatives unless you have tested them together. Duplicate patch names may be numbered,
> but reliable upstream provenance is not preserved in the merged UI.

> ⚠️ Only add patch sources you trust — a patch source decides what ends up inside your
> patched apps. This repo simply re-bundles other people's public patches; review
> `sources.json` to see exactly what is included.

## What's inside

`sources.json` contains **127 configured repositories**: all **104 bundles** present in the
Morphe catalog on 2026-08-22, plus 23 additional sources that were already configured. This
includes the official YouTube / YT Music / Reddit set plus community patches for Twitter/X,
Instagram, TikTok, Spotify-likes, Reddit clients, Gboard, Android TV, WhatsApp, Edge, and more.

“Configured” does not mean every source merged successfully. Repositories with no valid `.mpp`
are skipped, and every published Release includes the exact merged/skipped report.

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
(`MorpheApp/morphe-patches`) as canonical and **namespace-relocating** each other source's
bundled `app/<root>/<subpackage>` libraries to a source-specific package in **both** the
`.class` files (via ASM / jar-relocator) and the DEX (via baksmali → rewrite → smali).
Host-provided `morphe/patcher` and apply-time `*/extension` packages are excluded. Each source
then references its own matching helpers, while shared framework classes are de-duplicated.

Before publication, the pipeline validates every downloaded archive and the final `.mpp`, then
loads the combined bundle with Morphe Desktop. The Release report records the exact merged/skipped
sources and the verified patch count.

### Notes & trade-offs
- When several repositories patch the **same app**, their patches coexist but are not guaranteed
  compatible. Ordering in `sources.json` controls the canonical primary and first-wins precedence
  when an extension, resource, or other non-DEX path can only have one copy.
- Any source whose latest release has no `.mpp`, or that fails to merge, is **skipped**
  automatically — one bad repo never breaks the build (see the release notes / merge report).
- This is a re-bundler; it authors no patches. See `NOTICE.md`.

## Rebuilding / contributing
- Edit `sources.json` to add/remove/reorder sources. GitHub is the default; add
  `"host": "gitlab"` for a GitLab project.
- The `Build aggregated bundle` GitHub Action rebuilds on push, daily, or via manual
  dispatch, publishes the merged `.mpp` as a Release, and updates `patches-bundle.json`.
- Run locally: `GITHUB_TOKEN=... REPO_SLUG=ImNoammm/morphe-all-in-one bash build.sh`
  (needs `java`, `smali`/`baksmali`, `jq`, `zip`).

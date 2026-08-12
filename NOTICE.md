# NOTICE

This repository does **not** author any patches. It is an automated aggregator that
downloads the published `.mpp` patch bundles of the community Morphe patch repositories
listed in `sources.json`, and merges them into a single Morphe-compatible bundle so the
whole set can be added to the Morphe Manager app as one patch source.

- All patches remain the work and property of their original authors, under their own
  licenses (the Morphe patch ecosystem is predominantly GPL-3.0).
- The primary/canonical source is the official `MorpheApp/morphe-patches`.
- If you maintain a source and want it added, removed, or reprioritized, open an issue or
  edit `sources.json`.

Merging is done by namespace-relocating each non-primary source's shared patch-library
classes so independently-built bundles do not collide. See `README.md` for details.

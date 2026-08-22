#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCES_FILE="${1:-$ROOT/sources.json}"
CATALOG_FILE="${2:-$ROOT/catalog/bundles.json}"

jq -e '
  .sources as $sources |
  (($sources | type) == "array" and ($sources | length) > 0) and
  all($sources[];
    . as $source |
    (($source.repo | type) == "string") and
    ($source.repo | test("^[^/[:space:]]+/[^/[:space:]]+$")) and
    (($source.host // $source.source // "github") as $host |
      ($host | type) == "string" and
      (($host | ascii_downcase) == "github" or ($host | ascii_downcase) == "gitlab"))
  )
' "$SOURCES_FILE" >/dev/null

source_keys(){
  jq -r '.sources[] |
    [((.host // .source // "github") | ascii_downcase), (.repo | ascii_downcase)] |
    @tsv' "$SOURCES_FILE"
}

duplicates="$(source_keys | LC_ALL=C sort | uniq -d)"
if [ -n "$duplicates" ]; then
  printf 'Duplicate configured sources:\n%s\n' "$duplicates" >&2
  exit 1
fi

if [ ! -f "$CATALOG_FILE" ]; then
  printf 'Catalog snapshot not found: %s\n' "$CATALOG_FILE" >&2
  exit 1
fi

jq -e '
    .bundles as $bundles |
    (($bundles | type) == "array" and ($bundles | length) > 0) and
    all($bundles[];
      (.source | type) == "string" and
      ((.source | ascii_downcase) == "github" or (.source | ascii_downcase) == "gitlab") and
      (.repo | type) == "string" and
      (.repo | test("^[^/[:space:]]+/[^/[:space:]]+$"))
    )
  ' "$CATALOG_FILE" >/dev/null

missing="$(comm -23 \
  <(jq -r '.bundles[] | [(.source | ascii_downcase), (.repo | ascii_downcase)] | @tsv' "$CATALOG_FILE" | LC_ALL=C sort -u) \
  <(source_keys | LC_ALL=C sort -u))"
if [ -n "$missing" ]; then
  printf 'Catalog sources missing from sources.json:\n%s\n' "$missing" >&2
  exit 1
fi

printf 'Validated %s configured sources; catalog coverage is complete.\n' \
  "$(jq '.sources | length' "$SOURCES_FILE")"

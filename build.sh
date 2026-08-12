#!/usr/bin/env bash
# Morphe All-in-One — merge many community Morphe patch repos into one .mpp bundle.
#
# The FIRST source in sources.json is the "primary" and is kept verbatim. Every other
# source is namespace-relocated (app.morphe.patches -> app.morphe.patches_sN) so its copy
# of the shared patch-library cannot collide with, or break against, another source's copy
# (sources are built against different patcher versions, so their shared classes have
# incompatible signatures). Framework / kotlin / gson classes are de-duplicated and
# provided once (by the host patcher at runtime, exactly as the originals expect).
#
# Output: dist/morphe-all.mpp  +  patches-bundle.json
set -uo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
WORK="${WORK:-$ROOT/work}"; DIST="${DIST:-$ROOT/dist}"
SOURCES_JSON="${SOURCES_JSON:-$ROOT/sources.json}"; TOOLS="$WORK/tools"
GH_TOKEN="${GITHUB_TOKEN:-}"; API="https://api.github.com"
OUT_MPP="$DIST/morphe-all.mpp"
REPO_SLUG="${REPO_SLUG:-ImNoammm/morphe-all-in-one}"
VERSION="${VERSION:-v$(date -u +%Y.%m.%d)}"
CREATED_AT="${CREATED_AT:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
log(){ printf ':: %s\n' "$*" >&2; }
warn(){ printf '!! %s\n' "$*" >&2; }
rm -rf "$WORK" "$DIST"; mkdir -p "$WORK" "$TOOLS" "$DIST"
curl_gh(){ if [ -n "$GH_TOKEN" ]; then curl -sL -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" "$1" -o "$2"; else curl -sL -H "Accept: application/vnd.github+json" "$1" -o "$2"; fi; }
curl_dl(){ if [ -n "$GH_TOKEN" ]; then curl -sL -H "Authorization: Bearer $GH_TOKEN" "$1" -o "$2"; else curl -sL "$1" -o "$2"; fi; }
log "Fetching build tools ..."
cd "$TOOLS"
dl(){ [ -f "$2" ] || curl -sL -o "$2" "$1"; }
dl "https://repo1.maven.org/maven2/org/ow2/asm/asm/9.7/asm-9.7.jar" asm.jar
dl "https://repo1.maven.org/maven2/org/ow2/asm/asm-commons/9.7/asm-commons-9.7.jar" asm-commons.jar
dl "https://repo1.maven.org/maven2/org/ow2/asm/asm-tree/9.7/asm-tree-9.7.jar" asm-tree.jar
dl "https://repo1.maven.org/maven2/org/ow2/asm/asm-analysis/9.7/asm-analysis-9.7.jar" asm-analysis.jar
dl "https://repo1.maven.org/maven2/me/lucko/jar-relocator/1.7/jar-relocator-1.7.jar" jar-relocator.jar
RCP="$TOOLS/asm.jar:$TOOLS/asm-commons.jar:$TOOLS/asm-tree.jar:$TOOLS/asm-analysis.jar:$TOOLS/jar-relocator.jar"
cp "$ROOT/tools/Relocate.java" .
javac -cp "$RCP" Relocate.java || { warn "javac failed"; exit 1; }
relocate_jar(){ java -cp "$TOOLS:$RCP" Relocate "$@" >/dev/null; }
cd "$ROOT"
STAGE="$WORK/stage"; mkdir -p "$STAGE/META-INF"
SEEN="$WORK/seen.txt"; : > "$SEEN"; DEXN=0; MERGED=(); SKIPPED=()
mapfile -t SRCS < <(jq -r '.sources[].repo' "$SOURCES_JSON")
idx=0
for repo in "${SRCS[@]}"; do
  tag="s${idx}"; log "[$idx] $repo"
  meta="$WORK/rel_$idx.json"; curl_gh "$API/repos/$repo/releases/latest" "$meta"
  mpp_url="$(jq -r '[.assets[]?|select(.name|endswith(".mpp"))][0].browser_download_url // empty' "$meta" 2>/dev/null)"
  if [ -z "$mpp_url" ]; then
    for br in main master; do
      pb="$WORK/pb_$idx.json"; curl_dl "https://raw.githubusercontent.com/$repo/$br/patches-bundle.json" "$pb"
      u="$(jq -r '.download_url // empty' "$pb" 2>/dev/null)"; [ -n "$u" ] && { mpp_url="$u"; break; }
    done
  fi
  [ -z "$mpp_url" ] && { warn "  no .mpp — skip"; SKIPPED+=("$repo:no-mpp"); idx=$((idx+1)); continue; }
  mpp="$WORK/src_$idx.mpp"; curl_dl "$mpp_url" "$mpp"
  unzip -tq "$mpp" >/dev/null 2>&1 || { warn "  bad archive — skip"; SKIPPED+=("$repo:bad"); idx=$((idx+1)); continue; }
  ex="$WORK/ex_$idx"; rm -rf "$ex"; mkdir -p "$ex"; unzip -oq "$mpp" -d "$ex"
  ls "$ex"/classes*.dex >/dev/null 2>&1 || { warn "  no dex — skip"; SKIPPED+=("$repo:no-dex"); idx=$((idx+1)); continue; }
  if [ ${#MERGED[@]} -eq 0 ]; then
    n=0; for dx in "$ex"/classes*.dex; do
      if [ $n -eq 0 ]; then cp "$dx" "$STAGE/classes.dex"; else DEXN=$((DEXN+1)); cp "$dx" "$STAGE/classes$((DEXN+1)).dex"; fi; n=$((n+1)); done
    for dx in "$ex"/classes*.dex; do bk="$WORK/bk_${idx}_$(basename "$dx")"; rm -rf "$bk"
      baksmali disassemble "$dx" -o "$bk" 2>/dev/null && (cd "$bk" && find . -name '*.smali') >> "$SEEN"; done
    (cd "$ex" && find . -type f ! -name 'classes*.dex' ! -path './META-INF/MANIFEST.MF' | while IFS= read -r f; do
        mkdir -p "$STAGE/$(dirname "$f")"; cp "$f" "$STAGE/$f"; done)
    MERGED+=("$repo"); log "  primary set."
  else
    relj="$WORK/reloc_$idx.jar"
    # Discover this source's bundled patch-library subpackages (app/<root>/<sub>) and relocate each
    # — everything except the host-provided framework app.morphe.patcher and apply-time extensions —
    # so this source's copies never clash with, or break against, another source built on a
    # different patcher version.
    SRC_SUBS=$( (cd "$ex" && ls -d app/*/* 2>/dev/null) | awk -F/ '{print $2"/"$3}' | grep -vE '^morphe/patcher$|/extension$' | sort -u )
    RARGS=(); for sp in $SRC_SUBS; do r="${sp%/*}"; sub="${sp#*/}"; RARGS+=("app.$r.$sub" "app.$r.${sub}_$tag"); done
    if [ ${#RARGS[@]} -gt 0 ]; then
      relocate_jar "$mpp" "$relj" "${RARGS[@]}" || { warn "  reloc fail — skip"; SKIPPED+=("$repo:reloc"); idx=$((idx+1)); continue; }
    else cp "$mpp" "$relj"; fi
    rex="$WORK/rex_$idx"; rm -rf "$rex"; mkdir -p "$rex"; unzip -oq "$relj" -d "$rex"
    (cd "$rex" && find . -type f ! -name 'classes*.dex' ! -path './META-INF/MANIFEST.MF' | while IFS= read -r f; do
        [ -e "$STAGE/$f" ] || { mkdir -p "$STAGE/$(dirname "$f")"; cp "$f" "$STAGE/$f"; }; done)
    ok=1
    for dx in "$ex"/classes*.dex; do
      sm="$WORK/sm_${idx}_$(basename "$dx")"; rm -rf "$sm"
      baksmali disassemble "$dx" -o "$sm" 2>/dev/null || { ok=0; break; }
      for sp in $SRC_SUBS; do
        r="${sp%/*}"; sub="${sp#*/}"
        find "$sm" -name '*.smali' -exec sed -i "s#Lapp/$r/$sub/#Lapp/$r/${sub}_${tag}/#g" {} +
        if [ -d "$sm/app/$r/$sub" ]; then mkdir -p "$sm/app/$r/${sub}_${tag}"; cp -r "$sm/app/$r/$sub/." "$sm/app/$r/${sub}_${tag}/"; rm -rf "$sm/app/$r/$sub"; fi
      done
      (cd "$sm" && while IFS= read -r f; do grep -qxF "$f" "$SEEN" && rm -f "$f"; done < <(find . -name '*.smali'))
      if find "$sm" -name '*.smali' | grep -q .; then
        DEXN=$((DEXN+1)); outdex="$STAGE/classes$((DEXN+1)).dex"
        if smali assemble "$sm" -a 26 -o "$outdex" 2>/dev/null; then (cd "$sm" && find . -name '*.smali') >> "$SEEN"
        else warn "  assemble fail"; rm -f "$outdex"; DEXN=$((DEXN-1)); ok=0; break; fi
      fi
    done
    if [ $ok -eq 1 ]; then MERGED+=("$repo"); log "  merged ($tag)."; else SKIPPED+=("$repo:dex"); fi
  fi
  idx=$((idx+1))
done
[ ${#MERGED[@]} -eq 0 ] && { warn "No sources merged."; exit 1; }
DESC="Aggregated Morphe community patches from ${#MERGED[@]} repositories. Rebuilt ${CREATED_AT}."
{ echo "Manifest-Version: 1.0"; echo "Name: Morphe All-in-One"; echo "Description: $DESC"
  echo "Version: ${VERSION#v}"; echo "Author: Morphe community (aggregated)"
  echo "Website: https://github.com/$REPO_SLUG"; echo "Patcher-Version: 1.8.0"; } > "$STAGE/META-INF/MANIFEST.MF"
log "Packaging ..."; ( cd "$STAGE" && zip -qr -X "$OUT_MPP" . ); ls -l "$OUT_MPP" >&2
DL="https://github.com/$REPO_SLUG/releases/download/$VERSION/morphe-all.mpp"
jq -n --arg v "$VERSION" --arg u "$DL" --arg c "$CREATED_AT" --arg d "$DESC" \
  '{version:$v, download_url:$u, created_at:$c, description:$d}' > "$ROOT/patches-bundle.json"
cp "$ROOT/patches-bundle.json" "$DIST/patches-bundle.json"
{ echo "## Merged (${#MERGED[@]})"; printf ' - %s\n' "${MERGED[@]}"
  echo "## Skipped (${#SKIPPED[@]})"; [ ${#SKIPPED[@]} -gt 0 ] && printf ' - %s\n' "${SKIPPED[@]}"; } | tee "$DIST/merge-report.md" >&2
{ echo "MERGED_COUNT=${#MERGED[@]}"; echo "VERSION=$VERSION"; } >> "${GITHUB_OUTPUT:-/dev/null}"

#!/usr/bin/env bash
# verify-ytdlp.sh — prove a yt-dlp release is yt-dlp's before anything pins it.
#
# Downloads the asset ClipHack bundles, plus SHA2-256SUMS and its signature,
# and requires all of: a good signature on SHA2-256SUMS from the signing key
# fingerprinted below, the asset's SHA-256 in that file, and the same SHA-256 in
# GitHub's own digest for the asset. Then prints the manifest lines to use and
# leaves the verified binary in the output directory for testing. It edits no
# repository.
#
# The key comes from public.key in yt-dlp's repo at that tag, but only a
# signature by the fingerprint pinned here is accepted: someone able to publish
# a release could change public.key in the same commit. If yt-dlp rotates its
# key this fails, and adopting the new one is a decision for the owner, made
# from yt-dlp's announcement — not something to fix by editing the fingerprint.
#
# Usage: verify-ytdlp.sh [TAG] [OUT_DIR]   (TAG default: the latest release)

set -euo pipefail

YTDLP_REPO=yt-dlp/yt-dlp
ASSET=yt-dlp_macos
# Simon Sawicki (yt-dlp signing key); the key behind 2026.06.09 and 2026.08.19.
SIGNING_FPR=AC0CBBE6848D6A873464AF4E57CF65933B5A7581

for t in gh gpg curl shasum; do
  command -v "$t" >/dev/null 2>&1 || { echo "verify-ytdlp.sh: $t not found" >&2; exit 1; }
done

TAG=${1:-$(gh api "repos/$YTDLP_REPO/releases/latest" --jq .tag_name)}
OUT=${2:-$(mktemp -d "${TMPDIR:-/tmp}/yt-dlp-$TAG.XXXXXX")}
mkdir -p "$OUT"
BASE="https://github.com/$YTDLP_REPO/releases/download/$TAG"

echo "▶ yt-dlp $TAG → $OUT"
for f in "$ASSET" SHA2-256SUMS SHA2-256SUMS.sig; do
  curl -fsSL --retry 3 -o "$OUT/$f" "$BASE/$f"
done
curl -fsSL --retry 3 -o "$OUT/public.key" "https://raw.githubusercontent.com/$YTDLP_REPO/$TAG/public.key"

# A throwaway keyring, so nothing is added to the user's own. gpg's socket path
# must stay short, which a deep TMPDIR does not guarantee, hence /tmp.
GNUPGHOME=$(mktemp -d /tmp/ytdlp-gpg.XXXXXX); export GNUPGHOME
trap 'gpgconf --kill gpg-agent >/dev/null 2>&1; rm -rf "$GNUPGHOME"' EXIT
gpg --batch --quiet --import "$OUT/public.key" 2>/dev/null
status=$(gpg --batch --status-fd 1 --verify "$OUT/SHA2-256SUMS.sig" "$OUT/SHA2-256SUMS" 2>/dev/null || true)
signer=$(awk '$2 == "VALIDSIG" { print $3 }' <<<"$status")
if [[ $signer != "$SIGNING_FPR" ]]; then
  echo "✗ SHA2-256SUMS is not validly signed by $SIGNING_FPR (signer: ${signer:-none})" >&2
  exit 1
fi
echo "  ✓ SHA2-256SUMS signed by $SIGNING_FPR"

want=$(awk -v a="$ASSET" '$2 == a { print $1 }' "$OUT/SHA2-256SUMS")
got=$(shasum -a 256 "$OUT/$ASSET" | awk '{ print $1 }')
digest=$(gh api "repos/$YTDLP_REPO/releases/tags/$TAG" --jq ".assets[] | select(.name == \"$ASSET\") | .digest")
[[ -n $want && $got == "$want" ]] || { echo "✗ $ASSET does not match SHA2-256SUMS" >&2; exit 1; }
[[ $digest == "sha256:$got" ]] || { echo "✗ $ASSET does not match GitHub's digest ($digest)" >&2; exit 1; }
echo "  ✓ $ASSET matches SHA2-256SUMS and GitHub's digest"

chmod 755 "$OUT/$ASSET"
reported=$("$OUT/$ASSET" --version)
[[ $reported == "$TAG" ]] || { echo "✗ the binary reports $reported, not $TAG" >&2; exit 1; }
echo "  ✓ runs, and reports $reported"

cat <<EOF

Vendor/ytdlp-manifest.env:
YTDLP_VERSION=$TAG
YTDLP_TAG=$TAG
YTDLP_SHA256=$got

Verified binary: $OUT/$ASSET
EOF

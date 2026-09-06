#!/bin/bash
# verify-opk.sh - list the content checksums of the published NanoCraft OPK.
#
# Compare these against the console with:
#   mount -t squashfs -o loop "/mnt/Native games/NanoCraft_funkey-s.opk" /tmp/v
#   cd /tmp/v && md5sum * | sort -k2
#
# Compare CONTENTS, not the .opk file itself: mksquashfs stamps a build time
# into the image, so two builds of identical sources differ byte for byte while
# every file inside them matches.
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Defaults to the newest archive present rather than a pinned version, so
# this keeps verifying the current release instead of an old one.
VERSION=${1:-}
if [ -z "$VERSION" ]; then
  latest=$(basename "$(ls "$HERE"/nanocraft-v*-rgnano.zip | sort -V | tail -1)")
  latest=${latest#nanocraft-}
  VERSION=${latest%-rgnano.zip}
fi
WORK="$HERE/verify"
rm -rf "$WORK"
mkdir -p "$WORK"
cd "$WORK"
unzip -q -o "$HERE/nanocraft-$VERSION-rgnano.zip" NanoCraft_funkey-s.opk
unsquashfs -d sq -q NanoCraft_funkey-s.opk >/dev/null
cd sq
echo "=== md5 of files inside the published NanoCraft OPK ($VERSION) ==="
# find, not a glob: the package now carries a modules/ directory and the
# kernel modules in it are the part most worth checking against a console.
find . -type f -exec md5sum {} + | sed 's#[.]/##' | sort -k2

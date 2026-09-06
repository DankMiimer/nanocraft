#!/bin/bash
# build-payload.sh - rebuild nanocraft-payload.tar.gz around a given runtime.
#
# WHY THIS EXISTS. v1.0.10 shipped a payload whose `ninecraft` predated the
# GUI-scale and FOV patches that its own launcher asked for, so selecting FIT
# did nothing and could not be made to do anything. build-archive.sh copies the
# OPK out of the working tree on every run, but it reused whatever payload
# happened to be sitting in this directory - and the game itself is in the
# payload, not the OPK. Rebuilding it is therefore part of cutting a release,
# not an occasional chore.
#
# WHAT IS AND IS NOT REBUILT. Only `ninecraft` is replaced. The GL bundle -
# egl-wrap, gl, lib, mesa, runtime - is the output of build/Dockerfile.mesa-nano
# and build/Dockerfile.client-glibc and has not changed since v1.0.0, so it is
# unpacked and repacked with its original timestamps rather than rebuilt. That
# makes this safe to run repeatedly: nothing but the runtime moves.
#
#   ./build-payload.sh <path-to-ninecraft>
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

RUNTIME="${1:?usage: build-payload.sh path-to-ninecraft}"
PAYLOAD=nanocraft-payload.tar.gz
VERIFY="$HERE/../src/verify-runtime.py"
[ -f "$VERIFY" ] || VERIFY="$HERE/../tools/verify-runtime.py"

STAGE=$(mktemp -d "${TMPDIR:-/tmp}/nanocraft-payload.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT

tar xzf "$PAYLOAD" -C "$STAGE"
[ -f "$STAGE/ninecraft" ] || { echo "ERROR: $PAYLOAD has no ninecraft at its root"; exit 1; }
OLD=$(sha256sum "$STAGE/ninecraft" | cut -d' ' -f1)

cp "$RUNTIME" "$STAGE/ninecraft"
chmod 755 "$STAGE/ninecraft"
python3 "$VERIFY" "$STAGE/ninecraft"

( cd "$STAGE" && tar czf "$HERE/$PAYLOAD.new" \
    --owner=root --group=root --numeric-owner --sort=name -- * )
mv "$HERE/$PAYLOAD.new" "$HERE/$PAYLOAD"

NEW=$(sha256sum "$STAGE/ninecraft" | cut -d' ' -f1)
echo "runtime  $OLD"
echo "      -> $NEW"
echo "$PAYLOAD  $(wc -c < "$PAYLOAD") bytes, sha256 $(sha256sum "$PAYLOAD" | cut -d' ' -f1)"

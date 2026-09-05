#!/usr/bin/env python3
"""Reject a NanoCraft runtime missing the features its launcher exposes.

Run on the executable extracted from the final package, as well as the build
output. This is a packaging guard, not a substitute for an on-device test.
"""
import argparse
import hashlib
from pathlib import Path
import struct


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("runtime", type=Path)
    parser.add_argument("--sha256", help="also require this build-output hash")
    args = parser.parse_args()
    data = args.runtime.read_bytes()
    if (len(data) < 52 or data[:6] != b"\x7fELF\x01\x01" or
            struct.unpack_from("<H", data, 18)[0] != 40):
        parser.error("expected a 32-bit little-endian ARM ELF")
    for marker in (b"NINECRAFT_GUI_SCALE", b"NINECRAFT_FOV",
                   b"NINECRAFT_INPUT_SETTINGS", b"NINECRAFT_NATIVE_UI",
                   b"NINECRAFT_CHAT_BUTTON"):
        if marker not in data:
            parser.error(f"runtime is missing {marker.decode()}; rebuild/repackage it")
    digest = hashlib.sha256(data).hexdigest()
    if args.sha256 and digest != args.sha256.lower():
        parser.error(f"packaged runtime differs from build output: {digest}")
    print(f"PASS: ARM runtime with GUI, FOV, sensitivity, native-UI and chat-button support; SHA256 {digest}")


if __name__ == "__main__":
    main()

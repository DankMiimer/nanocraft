#!/usr/bin/env python3
"""Check the assumption the chat-button hook is built on, against a real library.

The hook replaces one vtable slot of XperiaPlayInput with an empty function. It
guards itself at runtime, so a wrong assumption here means the button simply
stays; but the guard cannot tell you *why* it declined, and this can. It reads
the ELF directly and needs no toolchain.

    ./tests/chat_button_vtable_check.py <libminecraftpe.so>

Verified against 0.8.1, SHA256 baf9ca24...5a32677, where the vtable lives at
0x293080 and XperiaPlayInput::render at 0x139a70. No Minecraft data is included
in this repository; point this at your own extracted library.
"""
import struct
import sys

VTABLE = "_ZTV15XperiaPlayInput"
RENDER = "_ZN15XperiaPlayInput6renderEf"
RENDER_SLOT = 5
# gui.png is a 256x256 atlas and the chat sprite is x=200..218, y=82..100, so
# render's literal pool holds these four texture coordinates and nothing else
# does. Finding them is what identifies the quad as the chat button rather than
# some other single quad.
SPRITE_UV = {"x0": 200 / 256, "x1": 218 / 256, "y0": 82 / 256, "y1": 100 / 256}

R_ARM_RELATIVE = 23


def sections(data):
    e_shoff, = struct.unpack_from("<I", data, 0x20)
    e_shentsize, e_shnum, e_shstrndx = struct.unpack_from("<HHH", data, 0x2E)
    raw = [struct.unpack_from("<10I", data, e_shoff + i * e_shentsize)
           for i in range(e_shnum)]
    names_off = raw[e_shstrndx][4]
    out = []
    for name, typ, flags, addr, off, size, link, info, align, entsize in raw:
        end = data.index(b"\0", names_off + name)
        out.append({"name": data[names_off + name:end].decode(), "type": typ,
                    "addr": addr, "off": off, "size": size, "link": link,
                    "entsize": entsize})
    return out


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    data = open(sys.argv[1], "rb").read()
    if data[:6] != b"\x7fELF\x01\x01" or struct.unpack_from("<H", data, 18)[0] != 40:
        sys.exit("expected a 32-bit little-endian ARM ELF")
    shdrs = sections(data)

    symbols = {}
    for sh in shdrs:
        if sh["type"] != 11:            # SHT_DYNSYM
            continue
        strtab = shdrs[sh["link"]]
        for i in range(sh["size"] // sh["entsize"]):
            name, value, size = struct.unpack_from("<III", data, sh["off"] + i * sh["entsize"])
            end = data.index(b"\0", strtab["off"] + name)
            symbols[data[strtab["off"] + name:end].decode()] = (value, size)
    for wanted in (VTABLE, RENDER):
        if wanted not in symbols:
            sys.exit(f"{wanted} is not exported by this library")

    def offset(addr):
        for sh in shdrs:
            if sh["addr"] and sh["addr"] <= addr < sh["addr"] + sh["size"] and sh["type"] != 8:
                return sh["off"] + (addr - sh["addr"])
        sys.exit(f"address {addr:#x} is in no loaded section")

    # A vtable entry is filled in by the loader, so the word in the file may be
    # zero with the real value carried as a relocation addend.
    relative = {}
    for sh in shdrs:
        if sh["type"] != 9:             # SHT_REL
            continue
        for i in range(sh["size"] // sh["entsize"]):
            where, info = struct.unpack_from("<II", data, sh["off"] + i * sh["entsize"])
            if info & 0xFF == R_ARM_RELATIVE:
                relative[where] = struct.unpack_from("<I", data, offset(where))[0]

    vtable = symbols[VTABLE][0]
    render = symbols[RENDER][0]
    slot_at = vtable + RENDER_SLOT * 4
    entry = relative.get(slot_at, struct.unpack_from("<I", data, offset(slot_at))[0])
    # Thumb function pointers carry a set low bit; the two need not agree on it.
    if (entry ^ render) & ~1:
        sys.exit(f"vtable slot {RENDER_SLOT} holds {entry:#x}, not {RENDER} at {render:#x}")

    body = data[offset(render):offset(render) + symbols[RENDER][1]]
    missing = [name for name, value in SPRITE_UV.items()
               if struct.pack("<f", value) not in body]
    if missing:
        sys.exit(f"{RENDER} does not use the chat sprite: missing {', '.join(sorted(missing))}")

    print(f"PASS: {VTABLE}+{RENDER_SLOT * 4:#x} is {RENDER} ({render:#x}), "
          f"and it draws the gui.png chat sprite (200..218 x 82..100)")


if __name__ == "__main__":
    main()

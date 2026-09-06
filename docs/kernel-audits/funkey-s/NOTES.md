# The FunKey S kernel from issue #2

September 6, 2026. badcats72 reported that NanoCraft would not start on a
FunKey S running DrUm78's FunKey-OS 2.3.0, and then sent the two files the
launcher had written for exactly this: `nanocraft-kernel.txt` and
`nanocraft-kernel.zImage`.

## What they sent, and what it says

```text
4.14.14-funkey #1 SMP Sun Jan 18 03:45:29 CET 2026
gcc 10.2.0 (Buildroot 2020.11-341-g1f59bd3b48), root@LAPTOP-DAVID
```

A **third** build of the same source. DrUm78's card image already carried two,
built 03:01:26 and 03:17:24 the same morning; this is 03:45:29, 28 minutes after
the RG Nano kernel the shipped modules were verified against, by the same
builder in the same session.

`CONFIG_IKCONFIG` is off, so the console cannot hand over its `.config`. That is
the whole reason this is an audit rather than a comparison of two files.

## Extracting their kernel

`extract-kernel.sh`. The zImage carries an LZO payload, as DrUm78's images do —
but **at offset 6814, not 6432 where the RG Nano's sits**. Both files contain the
LZO magic at both offsets; on this one the 6432 hit is inside the decompressor
stub's string table and only 6814 decompresses. Anything that assumes the RG
Nano's offset gets "header corrupted" and looks like a truncated upload.

Result: `vmlinux`, 9662464 bytes, whose version string matches their `uname -a`.

## The audit

`audit-funkeys.py` recovers each kernel's export table out of the decompressed
image — `__ksymtab` entries are (value, name-pointer) pairs — and compares the
tester's against the RG Nano kernel the `smp` set was built and verified for.

**Only entries inside one long contiguous 8-byte-stride chain are kept.** A
loose scan matches coincidences: a USB-audio device-name table alone resolves
dozens of plausible-looking identifiers, and an earlier pass reported 94
"missing exports" that were all names like `MOTIF6` and `AudioPhile`. Chains
must be walked by stride rather than in sorted order, or a stray 4-byte-aligned
match inside a real section splits it and starts inventing gaps —
`crypto_has_alg` was reported missing that way while sitting in a run of 4227.

| | exports |
|---|---:|
| RG Nano factory (verified, ships as `smp/`) | 6749 |
| FunKey S (this console) | 6722 |

- **All 158 undefined symbols** across `lz4_compress`, `lz4_decompress`, `lz4`,
  `zsmalloc` and `zram` resolve against the FunKey S export table.
- **Nothing is exported here that the verified kernel does not export.** The
  difference is one-directional: 27 exports present on the RG Nano and absent
  here, and every one of them is USB MIDI or USB host —
  `snd_rawmidi_*`, `snd_usbmidi_*`, `musb_root_disconnect`. None is anything
  zram, zsmalloc or lz4 touches.
- `check-layout-markers.py`: every config option that would move `struct page`,
  a spinlock, a zone or the allocator — SLUB/SLAB, MEMCG, SPARSEMEM, HIGHMEM,
  DEBUG_SPINLOCK, LOCKDEP, PREEMPT, page poisoning, KASAN — is exported
  identically by both kernels. That is the risk the whitelist exists for, and it
  is the closest thing to a config diff available with `CONFIG_IKCONFIG` off.

## What this does and does not establish

It establishes that the modules will **load**, and that no configuration
difference detectable from the outside touches the memory internals they reach
into. It does not establish that anybody has watched it run, which is the bar
slot 1 of the card image is still waiting on.

It is whitelisted anyway, and the comment in `opk/modules/kernels` says why: the
person who reported it cannot verify it while the launcher refuses to load
anything, and theirs is the only console in the world that can.

## What to expect if it works

Their report's memory probe already passed on this console — it allocated 80 MB
and touched every page — because a FunKey S has a 128 MB swap partition its
firmware enables. NanoCraft disables that partition once zram is up, by design,
so the working set will be coming from compressed memory, exactly as on the
RG Nano. If it starts, they should also get past **Play**, which crashed for
them on v1.0.0 and v1.0.5: that was RakNet's LAN broadcast faulting with no
network interface, fixed in v1.0.7.

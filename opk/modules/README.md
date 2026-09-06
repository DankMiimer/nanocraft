# zram modules

The RG Nano's stock kernel has no zram, so NanoCraft ships its own. These are
loaded at launch by `../ensure-memory.sh` and unloaded by a reboot. Nothing is
written to the read-only rootfs and no firmware change is involved.

| File | Purpose |
|---|---|
| `lz4_compress.ko` | LZ4 compressor |
| `lz4_decompress.ko` | LZ4 decompressor |
| `lz4.ko` | crypto API shim (`lz4-scomp`, `lz4-generic`) |
| `zsmalloc.ko` | compressed page allocator |
| `zram.ko` | the block device itself |

**There are two sets, because there are two kernels.** DrUm78's factory RG Nano
image is built `CONFIG_SMP=y`; the console this port was developed on is a
custom uniprocessor build. Their vermagic strings differ by exactly one word:

```
smp/   4.14.14-funkey SMP mod_unload ARMv7 p2v8     factory image
up/    4.14.14-funkey mod_unload ARMv7 p2v8         the development console
```

A module from the wrong set is refused by the loader, so one set cannot serve
both. `kernels` says which build gets which, and the launcher picks from it.
About 100 KB per set.

The factory **FunKey S** kernel takes the `smp` set as well. It is a third build
of the same source, 28 minutes after the RG Nano's, and the set was audited
against the image a tester sent rather than assumed to fit: every symbol the
modules import resolves, its export table is a strict subset of the RG Nano
kernel's, and the 27 exports it lacks are all USB MIDI and USB host. See
`../../docs/kernel-audits/funkey-s/`.

## Source

**Unmodified Linux 4.14.14**, from kernel.org. No patches. Each set's `kernel.config` is the exact
configuration it was built with, and is the only thing that differs from a stock
upstream build. They are GPLv2 like the kernel
they come from; see `../../THIRD_PARTY_NOTICES.md`.

To rebuild, with the FunKey SDK toolchain (`arm-linux-`):

```sh
make O=$BUILD ARCH=arm CROSS_COMPILE=arm-linux- modules_prepare
make O=$BUILD ARCH=arm CROSS_COMPILE=arm-linux- \
     KCFLAGS='-march=armv7-a -mcpu=cortex-a7' M=drivers/block/zram modules
# likewise for M=mm CONFIG_ZSMALLOC=m, M=lib/lz4, M=crypto CONFIG_CRYPTO_LZ4=m
```

## Which kernels these work on

The module loader compares a `vermagic` string exactly, and these carry:

```
4.14.14-funkey mod_unload ARMv7 p2v8
```

That is DrUm78's RG Nano kernel: uniprocessor, no preemption, no MODVERSIONS.
A module built for any other configuration is refused, which is the safe
outcome — `ensure-memory.sh` reports it and stops rather than guessing.

**Matching vermagic is not sufficient, and this is the important part.** It
encodes the version, SMP, preemption, module-unload support and the
architecture, and nothing else. Two builds of `4.14.14-funkey` with different
configurations share it exactly while disagreeing about the layout of
`struct page`, of a spinlock, or of the mm internals zram and zsmalloc reach
into. `insmod` accepts such a module, and the result is memory corruption rather
than a clean refusal.

So the launcher does not rely on vermagic alone. `kernels` in this directory
lists the build identities — `uname -r` plus `uname -v` — that somebody has
actually verified, each followed by `|` and the set it needs. Nothing is loaded
into a kernel that is not on that list. Adding one is deliberate, not automatic.

The directory comes after a pipe rather than after a space because the identity
contains runs of spaces: a single-digit build day reads `Jun  5`, and splitting
on whitespace would quietly stop matching it.

Vermagic also says nothing about whether the symbols a module needs are
actually exported. That was checked separately: `audit-modules.py` in the research notes recovers the running
kernel's export table straight out of `/boot/zImage` and confirms every
undefined symbol in all five modules resolves against it. **Re-run that audit
before shipping a rebuild.** A missing export is a load-time failure; a
mismatched struct layout is a crash, and only the config match protects against
that one.

## If a firmware update breaks them

Expected, and handled: `insmod` fails, the launcher says so and refuses to
start. There is no fallback to SD paging — that is the behaviour the modules
exist to remove — so the fix is to rebuild them against the new kernel with the
configuration above, re-run the export audit, and add the new build identity to
`kernels`. It needs no firmware change.

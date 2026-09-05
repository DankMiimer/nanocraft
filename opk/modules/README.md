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

97 KB in total.

## Source

**Unmodified Linux 4.14.14**, from kernel.org. No patches. `kernel.config` in
this directory is the exact configuration they were built with, and is the only
thing that differs from a stock upstream build. They are GPLv2 like the kernel
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

Matching vermagic is necessary but not sufficient, because it says nothing about
whether the symbols a module needs are actually exported. That was checked
separately: `audit-modules.py` in the research notes recovers the running
kernel's export table straight out of `/boot/zImage` and confirms every
undefined symbol in all five modules resolves against it. **Re-run that audit
before shipping a rebuild.** A missing export is a load-time failure; a
mismatched struct layout is a crash, and only the config match protects against
that one.

## If a firmware update breaks them

Expected, and handled: `insmod` fails, the launcher says so and refuses to
start. There is no fallback to SD paging — that is the behaviour the modules
exist to remove — so the fix is to rebuild them against the new kernel with the
configuration above and re-run the export audit. It needs no firmware change.

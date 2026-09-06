#!/usr/bin/env python3
"""Report whether any layout-critical config option differs between two kernels.

    ./check-layout-markers.py <audit.json>

Reads the export difference audit-funkeys.py recorded. Every option listed here
changes the layout of struct page, a spinlock, a zone or the allocator - the
things zram and zsmalloc reach into - and every one of them also adds or removes
exported symbols, so a difference is visible even when the kernel does not
expose its configuration.

A difference here is the one result that should stop a kernel being added to
opk/modules/kernels. Exits non-zero if it finds one.
"""
import json
import pathlib
import sys

MARKERS = {
    "SLUB/SLAB allocator": [
        "kmem_cache_alloc", "kmem_cache_alloc_trace", "__kmalloc", "kmem_cache_create"],
    "MEMCG (adds fields to struct page)": [
        "mem_cgroup_from_task", "memcg_kmem_enabled_key", "mem_cgroup_uncharge"],
    "SPARSEMEM vs FLATMEM": [
        "mem_section", "__section_mem_map_addr"],
    "HIGHMEM (kmap machinery)": [
        "kmap", "kunmap", "kmap_atomic", "pkmap_page_table"],
    "DEBUG_SPINLOCK / LOCKDEP (spinlock size)": [
        "lock_acquire", "lock_release", "_raw_spin_lock", "spin_dump", "debug_locks"],
    "PREEMPT (vermagic, and preempt_count)": [
        "preempt_schedule", "preempt_schedule_notrace"],
    "PAGE_POISONING / DEBUG_PAGEALLOC": [
        "__kernel_map_pages", "page_poisoning_enabled"],
    "KASAN / DEBUG_VM": [
        "kasan_report", "dump_page"],
    "the modules' own subsystems": [
        "crypto_has_alg", "crypto_alloc_base", "zs_malloc",
        "bdi_register_owner", "blk_queue_make_request"],
}


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    rec = json.loads(pathlib.Path(sys.argv[1]).read_text())
    differ = set(rec["exports_only_in_reference"]) | set(rec["exports_only_in_candidate"])
    bad = 0
    for label, syms in MARKERS.items():
        hits = [s for s in syms if s in differ]
        if hits:
            bad += 1
            print("  DIFFERENT  " + label + ": " + ", ".join(hits))
    if bad:
        print()
        print(str(bad) + " layout-critical option(s) differ - do NOT add this kernel")
        return 1
    print("  (none - every one is exported by both kernels or by neither)")
    print()
    print("no layout-critical option differs between these two kernels")
    return 0


if __name__ == "__main__":
    sys.exit(main())

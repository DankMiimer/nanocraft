"""Compare the config options that actually move a struct these modules touch.

Every one of these changes the layout of struct page, a spinlock, a zone or the
allocator - and every one of them adds or removes exported symbols, so a
difference is visible without the .config the kernel does not expose.
"""
import json, pathlib
rec = json.loads((pathlib.Path.home()/"nanocraft-zram/funkeys/audit-funkeys.json").read_text())
only_a = set(rec["exports_only_in_rgnano"]); only_b = set(rec["exports_only_in_funkey_s"])

MARKERS = {
    "SLUB/SLAB allocator": ["kmem_cache_alloc", "kmem_cache_alloc_trace", "__kmalloc", "kmem_cache_create"],
    "MEMCG (adds fields to struct page)": ["mem_cgroup_from_task", "memcg_kmem_enabled_key", "mem_cgroup_uncharge"],
    "SPARSEMEM vs FLATMEM": ["mem_section", "__section_mem_map_addr"],
    "HIGHMEM (kmap machinery)": ["kmap", "kunmap", "kmap_atomic", "pkmap_page_table"],
    "DEBUG_SPINLOCK / LOCKDEP (spinlock size)": ["lock_acquire", "lock_release", "_raw_spin_lock", "spin_dump", "debug_locks"],
    "PREEMPT (vermagic, and preempt_count)": ["preempt_schedule", "preempt_schedule_notrace"],
    "PAGE_POISONING / DEBUG_PAGEALLOC": ["__kernel_map_pages", "page_poisoning_enabled"],
    "KASAN / DEBUG_VM": ["kasan_report", "dump_page"],
    "the modules' own subsystems": ["crypto_has_alg", "crypto_alloc_base", "zs_malloc", "bdi_register_owner", "blk_queue_make_request"],
}
print("config markers that differ between the two kernels:")
diff = 0
for label, syms in MARKERS.items():
    hits = [s for s in syms if s in only_a or s in only_b]
    if hits:
        diff += 1
        print(f"  DIFFERENT  {label}: {hits}")
if not diff:
    print("  (none - every one of them is either exported by both kernels or by neither)")
print()
print("the only exports that differ, in full:")
for s in sorted(only_a):
    print("  rgnano-only:", s)
for s in sorted(only_b):
    print("  funkeys-only:", s)

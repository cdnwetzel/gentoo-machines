# vllm/ — PARTIAL TREE

Origin: a vLLM-on-T5810 tuning tree authored externally (Fable 5.1), delivered
2026-09-02. **Only 5 of the ~13 files arrived.** `README.md` describes the full
layout and therefore references paths that are not in this commit yet.

Committed so the surviving files are versioned rather than lost in a chat
transcript. Do not follow `README.md` end-to-end until the gaps below are filled.

## Present

| path | what |
|---|---|
| `README.md` | order of operations, rationale, win-ordering |
| `kernel/cmdline.txt` | boot cmdline, annotated per flag |
| `build/build-vllm.sh` | SM86-only source build into a venv |
| `vllm-env.sh` | NCCL / CUDA / cache env, sourced before `vllm serve` |
| `99-vllm-t5810.conf` | sysctl fragment — **see conflict note below** |

## Missing

- `kernel/vllm-t5810.config` — the kernel config fragment
- `portage/` — make.conf snippet, package.use, emerge.sh
- `build/patches/` — local patch dir applied on each rebuild
- `build/pin.md` — `nohz_full`/`taskset` core-pinning notes
- `openrc/init.d/vllm-host-tune`
- `openrc/init.d/vllm-qwen38`, `openrc/conf.d/vllm-qwen38`
- `serve-qwen38.sh`

## Verified against the live box, 2026-09-02/03

Checked before adopting anything. Recorded here because several README items do
not apply to this machine as it is actually configured.

**Does not apply**

- **MTP speculative decode** (README win #2). The served model's `config.json`
  has `num_nextn_predict_layers: None` — there is no MTP head. The referenced
  vllm#40807 drafter patch is moot here.
- **Custom TP=2 all-reduce** (a stated benefit of the source build). The serving
  config passes `--disable-custom-all-reduce`, because custom all-reduce cannot
  be CUDA-graph-captured (vllm#5613) and graphs are worth far more on this box.
  Startup log confirms `Using ['PYNCCL'] all-reduce backends`, and
  `SymmMemCommunicator: Device capability 8.6 not supported`. Compiling it does
  not make it usable.
- **`kernel.numa_balancing = 0`** — single NUMA node (Cluster-on-Die off), so
  this is a no-op. Harmless, as the file's own comment allows.
- **`-march=broadwell`** — already set in this machine's `make.conf`.

**Conflicts with what is already here**

- `99-vllm-t5810.conf` would be installed alongside the existing
  `/etc/sysctl.d/99-precision-t5810-performance.conf` (this machine's
  `sysctl-performance.conf`). Both begin `99-`, and `v` sorts after `p`, so the
  vLLM file silently wins on three overlapping keys:
  `vm.dirty_ratio` 40 -> 10, `vm.dirty_background_ratio` 10 -> 5,
  `vm.swappiness` 5 -> 1.
  **Merge these keys into the existing file instead of adding a second one.**
  Dropping `dirty_ratio` by 4x is a real change and should be deliberate.
- `kernel_config.sh` sets `TRANSPARENT_HUGEPAGE_ALWAYS`; the README wants
  `madvise`. No rebuild is needed — `transparent_hugepage=madvise` on the
  cmdline overrides it.

**Cheaper than the README implies**

- `PREEMPT_DYNAMIC` is already enabled, so the preemption model is selectable at
  boot with `preempt=voluntary`. No kernel rebuild required.
- Consequently the main host-latency wins (idle states, THP, preempt) are all
  **cmdline-only, one reboot**. The kernel fragment is not on the critical path.

**Open questions**

- The portage snippet selects `kernel-open` NVIDIA modules; this machine
  currently runs the proprietary driver and is in production. Open modules are
  not faster — this swaps a working driver stack for no measured gain. The
  `HMM_MIRROR`/`ZONE_DEVICE`/`DEVICE_PRIVATE` kernel options exist to support
  that swap, so declining it also drops those.
- `build-vllm.sh` defaults to `REF=main`. The validated, serving version is
  0.27.1, and a prior measurement on this same hardware found a version bump
  slower than the incumbent while config changes carried the real win. Pin
  `REF=v0.27.1` so only one variable moves.
- `nohz_full` pinning needs `CONFIG_NO_HZ_FULL`; this kernel has `NO_HZ_IDLE`,
  so that step requires a rebuild rather than a cmdline edit.
- Two OpenRC units currently target this endpoint (`vllm-qwen38`, started, and
  `qwen38-writer`, stopped but still in the default runlevel). Installing the
  tree's `openrc/init.d/vllm-qwen38` would overwrite a unit that is live and has
  survived a reboot. Resolve the duplicate before adopting.

## Baseline for comparison

Measured 2026-09-02, greedy, 200 tokens, single request, TP=2 FP8:
**33.2 / 33.3 / 27.3 tok/s** (the spread is real; host idle-state jitter is the
suspected cause and is what the cmdline changes target).

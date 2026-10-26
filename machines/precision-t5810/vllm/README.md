# vLLM on the T5810 — Qwen3.8-27B, 2x A4500 NVLink — Gentoo / OpenRC

```
kernel/    config fragment + boot cmdline            (merge_config.sh, then your bootloader)
portage/   make.conf snippet, package.use, emerge.sh
build/     build-vllm.sh (SM86-only source build), patches/, pin.md
openrc/    init.d/vllm-host-tune, init.d/vllm-qwen38, conf.d/vllm-qwen38
serve-qwen38.sh, vllm-env.sh, 99-vllm-t5810.conf     (unchanged from the first cut)
```

## Order of operations
1. `portage/` — merge make.conf snippet, drop package.use in place, run `emerge.sh`.
2. `kernel/` — merge the fragment into your T5810 kernel, add the cmdline, rebuild,
   re-emerge `nvidia-drivers` (`emerge @module-rebuild`), reboot.
   Check: `nvidia-smi topo -m` → NV4; `cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor` → performance;
   `cat /sys/kernel/mm/transparent_hugepage/enabled` → [madvise].
3. `build/build-vllm.sh` — install torch into `/opt/vllm/venv` first (cuXXX index
   matching `nvcc --version`), then run it. Pin `REF=` to a tag once it validates.
4. `cp serve-qwen38.sh vllm-env.sh /opt/vllm/`, `cp openrc/init.d/* /etc/init.d/`,
   `cp openrc/conf.d/* /etc/conf.d/`, `cp 99-vllm-t5810.conf /etc/sysctl.d/`.
5. `rc-update add vllm-host-tune default && rc-update add vllm-qwen38 default && rc-service vllm-qwen38 start`
   Logs: `/var/log/vllm/vllm-qwen38.log`. Profile switch: edit `/etc/conf.d/vllm-qwen38`, restart.

`serve-qwen38.sh` needs one edit for the venv: prepend
`source /opt/vllm/venv/bin/activate` after the `vllm-env.sh` source line.

## What the source build buys you here
- One arch. Wheels ship 6; the build drops to ~1/5 of the objects and the resulting
  `.so` loads faster on a slow-IPC host.
- Marlin (INT4 decode path), the custom TP=2 allreduce, and the GDN Triton ops all
  compiled against your CUDA + gcc-14. Triton JITs at first request; the cache dir
  keeps it.
- A `patches/` dir that survives rebuilds. First candidate if you hit it: the MTP
  CUDA-graph capture crash tracked as vllm #40807 — a piecewise fallback for the
  drafter is a ten-line change if it bites on 0.25.x.

## Where the wins actually are on this box (in order)
1. INT4 weights (bandwidth-bound decode on 640 GB/s cards)
2. MTP speculative decode, 1 token verified, try 2
3. `FULL_DECODE_ONLY` CUDA graphs (gets Broadwell's launch overhead out of the loop)
4. C1-only idle + performance governor (decode jitter)
5. `mitigations=off` (host-side ioctl cost; your call on threat model)
6. core pinning — last, and only with numbers in hand

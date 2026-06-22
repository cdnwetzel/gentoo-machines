# XPS 9510 — Inference Baseline

Captured to know what "normal" looks like, so future regressions are visible.

## Test rig

- Kernel: (record `uname -r` at time of bench)
- nvidia-drivers: (record `cat /sys/module/nvidia/version`)
- Ollama: (record `ollama --version`)
- Model: `qwen2.5:3b-instruct-q4_K_M` (~2.2 GB GGUF on disk)
- Power state: AC, lid closed, docked
- RAPL: PL1=35 W, PL2=60 W (verify with `powercap-profile show`)
- NVIDIA: persistence mode on (`nvidia-smi -pm 1`), default power limit

## How to run

```bash
# Cold start (model load from disk into VRAM)
sudo rc-service ollama restart
time curl -s http://localhost:11434/api/generate \
    -d '{"model":"qwen2.5:3b-instruct-q4_K_M","prompt":"hello","stream":false}' \
    | jq .total_duration

# Warm prefill (512-token prompt)
ollama run --verbose qwen2.5:3b-instruct-q4_K_M \
    "$(yes 'word ' | head -512 | tr -d '\n')please reply 'OK'"

# Sustained generation (5-minute loop)
for i in $(seq 1 30); do
    curl -s http://localhost:11434/api/generate \
      -d '{"model":"qwen2.5:3b-instruct-q4_K_M","prompt":"Write a paragraph about climate.","stream":false}' \
      | jq -r '"\(.eval_count) tokens in \(.eval_duration/1e9)s = \((.eval_count*1e9)/.eval_duration | floor) tok/s"'
done | awk '{sum+=$NF; n++} END {print "mean", sum/n, "tok/s over", n, "runs"}'

# Thermals during the loop (run in parallel)
watch -n2 'sensors | grep -E "Package id|GPU"; nvidia-smi --query-gpu=temperature.gpu,power.draw --format=csv,noheader'
```

## Numbers — fill in after first run

| Metric                          | With PL1=35/PL2=60 | Uncapped (reference) |
|---------------------------------|--------------------|----------------------|
| Cold model load                 |                    |                      |
| Warm prefill (512 tok)          |                    |                      |
| Sustained generation (mean)     |                    |                      |
| Sustained generation (p95)      |                    |                      |
| Package temp (5-min mean)       |                    |                      |
| GPU temp (5-min mean)           |                    |                      |
| Throttle events (dmesg)         |                    |                      |

Target (sanity): warm sustained ≥ 30 tok/s on the 3050 Ti. Anything noticeably
under that and either the model didn't fit VRAM (check `nvidia-smi`), the
runtime dropped to CPU, or thermals are crushing the GPU.

## Observations

(blank — fill in once bench has run)

## Re-bench triggers

Re-run this whenever:
- Kernel updates past the LTS series boundary (6.18 → 7.x)
- nvidia-drivers branch jump (current 595 → next)
- Ollama major version (0.x → 1.0)
- Model swap to a different verifier
- Powercap profile changes

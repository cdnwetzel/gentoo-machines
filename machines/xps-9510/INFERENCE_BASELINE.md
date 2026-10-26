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

## Numbers — initial baseline (2026-06-21)

Captured immediately after first deploy. **NOTE**: RAPL was still in the
broken-from-boot state (PL1=200W, PL2=60W) when these numbers were taken,
not the intended 35W/60W. Re-bench after `rc-service powercap-profile restart`
to get the production envelope.

| Metric                          | 2026-06-21 (PL1=200, PL2=60) | Target / Uncapped reference |
|---------------------------------|------------------------------|------------------------------|
| Kernel                          | 6.18.29-gentoo               | -                            |
| nvidia-drivers                  | 595.71.05                    | -                            |
| Ollama                          | v0.30.10                     | -                            |
| Warm gen tok/s (200 tok)        | **62 tok/s**                 | ≥ 30 tok/s (sanity floor)    |
| Prompt eval (45 tok prefill)    | 0.06 s (~750 tok/s prefill)  | -                            |
| GPU mem in use                  | 2.4 GB / 4.0 GB              | < 4.0 GB (fit)               |
| GPU temp at idle (post-call)    | 60 °C                        | < 85 °C sustained            |
| Verifier round-trip (fact-check)| 3.8 s                        | < 10 s                       |
| Verifier round-trip (judge)     | 4.2 s                        | < 10 s                       |

Quick verifier sanity (LLM-as-judge correctly distinguishes):
- "The capital of France is London" → verdict=fail, reasoning cites Paris ✓
- "L1/L2/L3 cache explanation" judged against "mentions L1, L2, and L3" → verdict=pass ✓

## Observations (first deploy)

- **62 tok/s warm gen blows past the 30 tok/s target** — verifier latency is bounded by
  model loading (cold start, ~36 s) far more than generation. Once warm, calls return in
  3-5 s regardless of payload size (within reason).
- **GPU idles at 14.8 W, 60 °C between calls** — well within the thermal envelope.
  Power-cap impact on sustained tok/s should be minimal since the GPU never approached
  thermal throttle even uncapped.
- **Cold start is 30+ s** because Ollama loads the GGUF into VRAM. `OLLAMA_KEEP_ALIVE=24h`
  in ollama.confd keeps it resident — first call after boot pays cold cost, all subsequent
  calls within 24h are warm.

## Re-bench triggers

## Re-bench triggers

Re-run this whenever:
- Kernel updates past the LTS series boundary (6.18 → 7.x)
- nvidia-drivers branch jump (current 595 → next)
- Ollama major version (0.x → 1.0)
- Model swap to a different verifier
- Powercap profile changes

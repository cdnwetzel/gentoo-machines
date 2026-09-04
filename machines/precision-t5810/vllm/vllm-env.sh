#!/usr/bin/env bash
# vllm-env.sh — source before `vllm serve`. No `set -e` (this file is sourced).
# Precision T5810 · E5-2699 v4 (22c/44t, AVX2 only) · 2x RTX A4500 20 GB, NVLink (NV4)

# --- Device ordering
export CUDA_DEVICE_ORDER=PCI_BUS_ID
export CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES:-0,1}

# --- NCCL: keep the TP=2 all-reduce on the bridge, never on PCIe 3.0
export NCCL_P2P_LEVEL=NVL
export NCCL_IB_DISABLE=1              # no fabric NIC on this box
export NCCL_NET_GDR_LEVEL=0           # no GPUDirect RDMA path; documents intent
export NCCL_BUFFSIZE=8388608          # 8 MB

# --- CUDA / PyTorch
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
export VLLM_WORKER_MULTIPROC_METHOD=spawn
export OMP_NUM_THREADS=4              # per TP worker; keeps 2 workers off each other's cores
export TOKENIZERS_PARALLELISM=false

# --- Persistent caches on the single 2 TB 990 Pro
# torch.compile + CUDA-graph artefacts are reused across restarts, which matters
# because first-boot compile on Broadwell is slow.
export HF_HOME=${HF_HOME:-/var/lib/vllm/hf}
export VLLM_CACHE_ROOT=${VLLM_CACHE_ROOT:-/var/lib/vllm/cache}

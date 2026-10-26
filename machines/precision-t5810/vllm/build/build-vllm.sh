#!/usr/bin/env bash
# build/build-vllm.sh — source build of vLLM for SM86 only, in a venv, on the T5810
#
# Why a source build at all on this box:
#  * wheels carry SM80/86/89/90/100/120 kernels; you want 86 and nothing else
#  * Marlin/AWQ/GPTQ, the GDN (fla) Triton ops and the custom allreduce all get
#    compiled against your exact CUDA + gcc instead of manylinux's
#  * you can carry local patches (see build/patches/) without fighting pip
#
# Time on 22c Broadwell with ccache warm: ~40-60 min. Cold: ~2 h. Plan accordingly.
set -euo pipefail

VENV=${VENV:-/opt/vllm/venv}
SRC=${SRC:-/opt/vllm/src/vllm}
REF=${REF:-main}                       # pin a tag once you've validated one, e.g. v0.25.1
PY=${PY:-python3.12}

# --- toolchain: nvcc wants gcc 14; Gentoo's cuda ebuild sets NVCC_CCBIN in /etc/env.d
export CUDA_HOME=${CUDA_HOME:-/opt/cuda}
export PATH="$CUDA_HOME/bin:$PATH"
export CUDAHOSTCXX=${CUDAHOSTCXX:-/usr/bin/g++-14}
export CC=${CC:-/usr/bin/gcc-14} CXX=${CXX:-/usr/bin/g++-14}
export NVCC_CCBIN="$CUDAHOSTCXX"

# --- the whole point: one arch
export TORCH_CUDA_ARCH_LIST="8.6"
export VLLM_TARGET_DEVICE=cuda
export CMAKE_BUILD_TYPE=Release
export MAX_JOBS=${MAX_JOBS:-18}        # nvcc jobs; 256 GB RAM so memory isn't the limiter
export NVCC_THREADS=${NVCC_THREADS:-2}
export CMAKE_ARGS="-GNinja -DVLLM_GPU_ARCHES=86 -DCMAKE_CUDA_ARCHITECTURES=86 \
  -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache -DCMAKE_CUDA_COMPILER_LAUNCHER=ccache"
export CCACHE_DIR=${CCACHE_DIR:-/var/cache/ccache-vllm}
export CCACHE_MAXSIZE=40G
export VLLM_USE_PRECOMPILED=0

# --- venv
[[ -d "$VENV" ]] || "$PY" -m venv "$VENV"
source "$VENV/bin/activate"
pip install -U pip wheel setuptools ninja cmake packaging

# --- torch first, then read its CUDA version and insist nvcc matches the major
if ! python -c 'import torch' 2>/dev/null; then
  echo "install torch into $VENV first (pip index matching your CUDA, e.g. cu128), then rerun" >&2; exit 1
fi
TORCH_CUDA=$(python -c 'import torch;print(torch.version.cuda)')
NVCC_CUDA=$(nvcc --version | sed -n 's/.*release \([0-9]*\.[0-9]*\).*/\1/p')
[[ "${TORCH_CUDA%%.*}" == "${NVCC_CUDA%%.*}" ]] || { echo "torch cuda $TORCH_CUDA vs nvcc $NVCC_CUDA — fix before building" >&2; exit 1; }

# --- source
mkdir -p "$(dirname "$SRC")"
[[ -d "$SRC/.git" ]] || git clone https://github.com/vllm-project/vllm.git "$SRC"
git -C "$SRC" fetch --tags origin && git -C "$SRC" checkout "$REF"
for p in "$(dirname "$0")"/patches/*.patch; do [[ -e "$p" ]] && git -C "$SRC" apply "$p"; done

# --- build. requirements pinned by vLLM; --no-build-isolation so it sees our torch
pip install -r "$SRC/requirements/build.txt"
pip install --no-build-isolation -v -e "$SRC"

# --- optional: FlashInfer for SM86 (needed for fp8_e5m2 KV on Ampere; skip if KV_FP8=0)
if [[ "${WITH_FLASHINFER:-0}" == 1 ]]; then
  FLASHINFER_CUDA_ARCH_LIST="8.6" pip install --no-build-isolation -v flashinfer-python
fi

python - << 'PY'
import vllm, torch
print("vllm", vllm.__version__, "torch", torch.__version__, "cuda", torch.version.cuda,
      "sm", torch.cuda.get_device_capability(0))
PY

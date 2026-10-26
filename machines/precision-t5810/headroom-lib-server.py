#!/usr/bin/env python3
"""headroom-lib-server — tiny FastAPI service exposing Headroom's compress()
library directly, bypassing the full proxy's prefix-freeze policy.

Built because cwdotcom's single-turn-RAG request shape (2 messages, every
request has a different system prompt) trips Headroom's proxy-mode
prefix-freeze logic, which protects what it thinks is a cacheable prefix.
On cwdotcom this yields router:noop / 0% savings even with the agent-90
profile, force_kompress, and HEADROOM_COMPRESS_SYSTEM_MESSAGES=1 all set.

Library mode applies a different policy and produces ~23-30% real savings on
the same input. So we expose just that — one HTTP endpoint that wraps
`from headroom import compress` and returns the compressed messages.

Endpoints:
  POST /compress  — compress a message list (see request_body fields below)
  GET  /livez     — process is alive
  GET  /readyz    — kompress model loaded + warmed up
  GET  /stats     — counters (calls, mean savings, mean ms)

Binds 127.0.0.1:8788 by default (loopback only). The cwdotcom VPS reaches
this via the existing portfolio-ai-tunnel.service ssh -L port forward.
"""
import asyncio
import logging
import os
import time
from contextlib import asynccontextmanager
from typing import Any

from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

from headroom import compress  # the library entrypoint we proved works on cwdotcom

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("headroom-lib")

HOST = os.environ.get("HEADROOM_LIB_HOST", "127.0.0.1")
PORT = int(os.environ.get("HEADROOM_LIB_PORT", "8788"))

# Default knobs — match what the cwdotcom A/B harness uses. Callers can
# override per-request. compress_user_messages=False keeps short user
# queries bit-identical.
DEFAULT_MODEL          = "gpt-4o"
DEFAULT_TARGET_RATIO   = 0.1
DEFAULT_PROTECT_RECENT = 0
DEFAULT_COMPRESS_USER  = False


class CompressRequest(BaseModel):
    messages: list[dict[str, Any]]
    model: str | None = None
    compress_user_messages: bool | None = None
    target_ratio: float | None = None
    protect_recent: int | None = None


# Tiny in-process counters so /stats can show a live picture without
# pulling out a real metrics lib.
_state = {
    "ready": False,
    "calls": 0,
    "tokens_before_total": 0,
    "tokens_after_total": 0,
    "ms_total": 0.0,
    "errors": 0,
    "started_at": time.time(),
}


@asynccontextmanager
async def lifespan(app: FastAPI):  # noqa: ARG001
    """Warm up kompress before serving so the first real request doesn't
    pay the ~25s cold ONNX + tokenizer + model load."""
    logger.info("Warming up Headroom kompress (this takes ~25s on first run)…")
    t0 = time.time()
    try:
        # Realistic-shape warm-up: one system + one user, big enough to
        # actually engage the prose compressor.
        await asyncio.get_running_loop().run_in_executor(
            None,
            lambda: compress(
                [
                    {"role": "system", "content": "warmup " * 200},
                    {"role": "user", "content": "warmup"},
                ],
                model=DEFAULT_MODEL,
                compress_user_messages=DEFAULT_COMPRESS_USER,
                target_ratio=DEFAULT_TARGET_RATIO,
                protect_recent=DEFAULT_PROTECT_RECENT,
            ),
        )
        _state["ready"] = True
        logger.info(f"Warm-up complete in {time.time() - t0:.1f}s — ready to serve")
    except Exception as e:
        logger.exception(f"Warm-up failed: {e!r}")
        # Stay alive; readyz will report not-ready so callers can fall back.
    yield


app = FastAPI(lifespan=lifespan)


@app.get("/livez")
async def livez():
    return {"status": "healthy", "alive": True, "uptime_s": time.time() - _state["started_at"]}


@app.get("/readyz")
async def readyz():
    if not _state["ready"]:
        return JSONResponse(
            status_code=503,
            content={"status": "starting", "ready": False, "reason": "kompress warm-up in progress"},
        )
    return {"status": "healthy", "ready": True}


@app.get("/stats")
async def stats():
    calls = _state["calls"]
    saved = _state["tokens_before_total"] - _state["tokens_after_total"]
    return {
        "ready": _state["ready"],
        "calls": calls,
        "errors": _state["errors"],
        "tokens_before_total": _state["tokens_before_total"],
        "tokens_after_total": _state["tokens_after_total"],
        "tokens_saved_total": saved,
        "mean_savings_pct": (saved / _state["tokens_before_total"] * 100) if _state["tokens_before_total"] else 0.0,
        "mean_ms": (_state["ms_total"] / calls) if calls else 0.0,
        "uptime_s": time.time() - _state["started_at"],
    }


@app.post("/compress")
async def do_compress(req: CompressRequest):
    if not req.messages:
        raise HTTPException(status_code=400, detail="messages: empty list")

    kwargs = {
        "model":                  req.model or DEFAULT_MODEL,
        "compress_user_messages": req.compress_user_messages if req.compress_user_messages is not None else DEFAULT_COMPRESS_USER,
        "target_ratio":           req.target_ratio   if req.target_ratio   is not None else DEFAULT_TARGET_RATIO,
        "protect_recent":         req.protect_recent if req.protect_recent is not None else DEFAULT_PROTECT_RECENT,
    }

    t0 = time.time()
    try:
        result = await asyncio.get_running_loop().run_in_executor(
            None, lambda: compress(req.messages, **kwargs)
        )
    except Exception as e:
        _state["errors"] += 1
        logger.exception(f"compress() raised: {e!r}")
        raise HTTPException(status_code=500, detail=f"compress() failed: {e!r}") from e
    ms = (time.time() - t0) * 1000

    _state["calls"] += 1
    _state["tokens_before_total"] += result.tokens_before
    _state["tokens_after_total"]  += result.tokens_after
    _state["ms_total"] += ms

    saved_pct = (1 - result.tokens_after / result.tokens_before) * 100 if result.tokens_before else 0.0
    logger.info(
        f"compress: {result.tokens_before}→{result.tokens_after} "
        f"({saved_pct:+.1f}%) {ms:.0f}ms transforms={result.transforms_applied}"
    )

    return {
        "messages":      result.messages,
        "tokens_before": result.tokens_before,
        "tokens_after":  result.tokens_after,
        "saved_pct":     saved_pct,
        "transforms":    list(result.transforms_applied),
        "ms":            ms,
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host=HOST, port=PORT, log_level="info", access_log=False)

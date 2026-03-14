#!/usr/bin/env python3
"""
autopatcher — AI panel-powered Nix kernel build fixer for Popcorn Kernel Forge.

Usage (via flake):
  nix run .#autopatcher -- --variant M-salami

Usage (direct):
  python3 autopatcher.py --variant M-salami [--flake-root /path/to/flake]

Environment variables:
  ANTHROPIC_API_KEY      Claude models (default judge)
  OPENAI_API_KEY         OpenAI models
  GEMINI_API_KEY         Gemini via OpenAI-compat endpoint
  OLLAMA_BASE_URL        Ollama endpoint (default: http://localhost:11434/v1)

How the panel works:
  1. Each available "panelist" model independently proposes a fix for the
     failing Nix script based on the build error.
  2. The "judge" model (highest-priority available) receives all proposals
     and synthesizes the best one (or picks outright).
  3. The winning fix is written back; the build is retried.
  4. Loop until success or --max-retries is exhausted.

Custom panel example:
  --models anthropic/claude-opus-4-5 openai/gpt-4o gemini/gemini-2.0-flash
  First model listed is treated as judge.
"""

import argparse
import os
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

# ── Optional provider imports ─────────────────────────────────────────────────

try:
    import anthropic as _anthropic_lib
    HAS_ANTHROPIC = True
except ImportError:
    HAS_ANTHROPIC = False

try:
    import openai as _openai_lib
    HAS_OPENAI = True
except ImportError:
    HAS_OPENAI = False


# ── Model spec ────────────────────────────────────────────────────────────────

@dataclass
class ModelSpec:
    provider: str   # "anthropic" | "openai" | "gemini" | "ollama"
    model: str
    is_judge: bool = False
    base_url: Optional[str] = None
    api_key_env: str = ""

    def __str__(self) -> str:
        role = " [judge]" if self.is_judge else ""
        return f"{self.provider}/{self.model}{role}"


# ── Default panel (first one with a key wins judge) ───────────────────────────

DEFAULT_PANEL: list[ModelSpec] = [
    ModelSpec("anthropic", "claude-opus-4-5",
              is_judge=True, api_key_env="ANTHROPIC_API_KEY"),
    ModelSpec("openai",    "gpt-4o",
              is_judge=False, api_key_env="OPENAI_API_KEY"),
    ModelSpec("gemini",    "gemini-2.0-flash",
              is_judge=False,
              base_url="https://generativelanguage.googleapis.com/v1beta/openai/",
              api_key_env="GEMINI_API_KEY"),
    ModelSpec("ollama",    "llama3",
              is_judge=False,
              base_url=os.environ.get("OLLAMA_BASE_URL", "http://localhost:11434/v1"),
              api_key_env=""),
]


# ── Terminal colors ───────────────────────────────────────────────────────────

class C:
    RED     = "\033[91m"
    GREEN   = "\033[92m"
    YELLOW  = "\033[93m"
    CYAN    = "\033[96m"
    MAGENTA = "\033[95m"
    BOLD    = "\033[1m"
    DIM     = "\033[2m"
    RESET   = "\033[0m"


def log(msg: str, color: str = "") -> None:
    print(f"{color}[autopatcher] {msg}{C.RESET}", flush=True)


def banner(title: str) -> None:
    bar = "─" * 68
    print(f"\n{C.BOLD}{bar}{C.RESET}", flush=True)
    print(f"{C.BOLD}  {title}{C.RESET}", flush=True)
    print(f"{C.BOLD}{bar}{C.RESET}\n", flush=True)


# ── Prompts ───────────────────────────────────────────────────────────────────

_SYS_PANELIST = """\
You are an expert Nix and Linux kernel build engineer specialising in Android/AOSP \
kernel builds, OnePlus devices (SM8550 / kalama), KernelSU integration, and Nix derivations.

You receive a Nix build script and the output from a failed nix build invocation.
Return ONLY the complete corrected Nix script — no explanation, no markdown fences, \
no preamble, no commentary whatsoever.
Rules:
- Output the FULL file. Never truncate or summarise.
- Make the MINIMAL change required to fix the error.
- Bad fetchurl/fetchFromGitHub hash → update the hash.
- Patch fails to apply → fix or remove the sed/patch line.
- Invalid kernel config option for the version → remove or correct it.
- Missing nativeBuildInput / buildInput → add it.
- If you genuinely cannot determine a fix, return the original script UNCHANGED.
"""

_SYS_JUDGE = """\
You are a senior Nix and Linux kernel build engineer acting as technical lead.
You receive:
  • The original failing Nix build script
  • The full build error output
  • Proposed fixes from several AI models

Your task:
1. Determine which proposals correctly diagnose the root cause.
2. Select the best fix, or synthesise the strongest parts of multiple proposals.
3. Return ONLY the complete corrected Nix script — no explanation, no markdown, \
   no preamble, no commentary.
Output the FULL file. Never truncate.
"""


def _panelist_user(script: str, error: str) -> str:
    return (
        f"=== NIX SCRIPT ===\n{script}\n\n"
        f"=== BUILD ERROR (last 10k chars) ===\n{error[-10_000:]}"
    )


def _judge_user(script: str, error: str, proposals: list[tuple[str, str]]) -> str:
    proposal_block = "\n\n".join(
        f"--- Proposed fix by {name} ---\n{fix}" for name, fix in proposals
    )
    return (
        f"=== ORIGINAL FAILING NIX SCRIPT ===\n{script}\n\n"
        f"=== BUILD ERROR (last 10k chars) ===\n{error[-10_000:]}\n\n"
        f"=== PROPOSED FIXES ===\n{proposal_block}\n\n"
        f"Now synthesise the best corrected Nix script and output it in full."
    )


# ── Model callers ─────────────────────────────────────────────────────────────

def _call_anthropic(spec: ModelSpec, system: str, user: str) -> str:
    if not HAS_ANTHROPIC:
        raise RuntimeError("'anthropic' Python package not installed")
    key = os.environ.get(spec.api_key_env, "")
    if not key:
        raise RuntimeError(f"Env var {spec.api_key_env} not set")
    client = _anthropic_lib.Anthropic(api_key=key)
    resp = client.messages.create(
        model=spec.model,
        max_tokens=8192,
        system=system,
        messages=[{"role": "user", "content": user}],
    )
    return resp.content[0].text.strip()


def _call_openai_compat(spec: ModelSpec, system: str, user: str) -> str:
    """Works for OpenAI, Gemini (compat endpoint), and Ollama."""
    if not HAS_OPENAI:
        raise RuntimeError("'openai' Python package not installed")
    key = os.environ.get(spec.api_key_env, "ollama") if spec.api_key_env else "ollama"
    if spec.api_key_env and not key:
        raise RuntimeError(f"Env var {spec.api_key_env} not set")
    kwargs: dict = {"api_key": key}
    if spec.base_url:
        kwargs["base_url"] = spec.base_url
    client = _openai_lib.OpenAI(**kwargs)
    resp = client.chat.completions.create(
        model=spec.model,
        max_tokens=8192,
        messages=[
            {"role": "system", "content": system},
            {"role": "user",   "content": user},
        ],
    )
    return resp.choices[0].message.content.strip()


def call_model(spec: ModelSpec, system: str, user: str) -> str:
    if spec.provider == "anthropic":
        return _call_anthropic(spec, system, user)
    # openai / gemini / ollama all speak the OpenAI wire protocol
    return _call_openai_compat(spec, system, user)


# ── Availability filter ───────────────────────────────────────────────────────

def available_models(panel: list[ModelSpec]) -> list[ModelSpec]:
    """Return models whose API keys are present (Ollama assumed always available)."""
    out: list[ModelSpec] = []
    for spec in panel:
        if spec.provider == "ollama":
            out.append(spec)
            continue
        if os.environ.get(spec.api_key_env, ""):
            out.append(spec)
        else:
            log(f"Skipping {spec.provider}/{spec.model} — {spec.api_key_env} not set", C.DIM)
    return out


# ── Build runner ──────────────────────────────────────────────────────────────

_TAIL_LINES = 30   # how many lines to show in the live tail

def run_build(cmd: str, cwd: Path) -> tuple[int, str]:
    """Stream build output live with a rolling tail, and return full log."""
    log(f"Running: {cmd}", C.BOLD)

    all_lines: list[str] = []
    tail: list[str] = []

    def _redraw() -> None:
        # Move cursor up _TAIL_LINES+1 lines and redraw
        sys.stdout.write(f"\033[{_TAIL_LINES + 1}A\033[J")
        sys.stdout.write(f"{C.DIM}{'─' * 68}{C.RESET}\n")
        for line in tail:
            sys.stdout.write(f"{C.DIM}{line}{C.RESET}\n")
        # pad to always occupy _TAIL_LINES rows so cursor math stays stable
        for _ in range(_TAIL_LINES - len(tail)):
            sys.stdout.write("\n")
        sys.stdout.flush()

    # Print initial blank tail block so _redraw has rows to overwrite
    sys.stdout.write(f"{C.DIM}{'─' * 68}{C.RESET}\n")
    for _ in range(_TAIL_LINES):
        sys.stdout.write("\n")
    sys.stdout.flush()

    proc = subprocess.Popen(
        cmd, shell=True, cwd=cwd,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, bufsize=1,
    )

    for raw_line in proc.stdout:          # type: ignore[union-attr]
        line = raw_line.rstrip("\n")
        all_lines.append(line)
        tail.append(line)
        if len(tail) > _TAIL_LINES:
            tail.pop(0)
        _redraw()

    proc.wait()
    return proc.returncode, "\n".join(all_lines)


# ── Nix sanity check ──────────────────────────────────────────────────────────

def looks_like_nix(text: str) -> bool:
    """Very rough check — real Nix has braces and is non-trivially long."""
    return "{" in text and "}" in text and len(text.strip()) > 150


# ── Panel logic ───────────────────────────────────────────────────────────────

def run_panel(
    models: list[ModelSpec],
    script: str,
    error: str,
    attempt: int,
) -> str:
    """
    Run all panelist models in parallel (sequentially for now; trivially
    parallelisable with ThreadPoolExecutor if you want speed).
    Then hand all proposals to the judge for synthesis.
    Returns the final fixed Nix script.
    """
    panelists = [m for m in models if not m.is_judge]
    judges    = [m for m in models if m.is_judge]

    banner(f"Panel deliberation — attempt {attempt}")
    proposals: list[tuple[str, str]] = []

    # ── Panelist phase ────────────────────────────────────────────────────────
    for spec in panelists:
        log(f"Asking panelist: {spec}", C.CYAN)
        try:
            fix = call_model(spec, _SYS_PANELIST, _panelist_user(script, error))
            if looks_like_nix(fix):
                log(f"  ✓ {spec} → valid Nix script ({len(fix)} chars)", C.GREEN)
                proposals.append((str(spec), fix))
            else:
                log(f"  ✗ {spec} → response doesn't look like Nix, discarding", C.YELLOW)
        except Exception as exc:
            log(f"  ✗ {spec} → error: {exc}", C.RED)

    # ── Judge phase ───────────────────────────────────────────────────────────
    if not judges:
        if not proposals:
            raise RuntimeError("No panelist proposals and no judge model available")
        log("No judge configured — using first valid panelist proposal", C.YELLOW)
        return proposals[0][1]

    judge = judges[0]

    if not proposals:
        # Judge flies solo
        log(f"No panelist proposals — asking judge {judge} directly", C.YELLOW)
        fix = call_model(judge, _SYS_PANELIST, _panelist_user(script, error))
        return fix

    if len(proposals) == 1 and not panelists:
        # Only a judge, skip the synthesis step
        return proposals[0][1]

    log(f"Asking judge: {judge} to synthesise {len(proposals)} proposal(s)", C.MAGENTA)
    try:
        synthesis = call_model(
            judge, _SYS_JUDGE, _judge_user(script, error, proposals)
        )
        if looks_like_nix(synthesis):
            log(f"  ✓ Judge synthesis looks valid ({len(synthesis)} chars)", C.GREEN)
            return synthesis
        log("  ✗ Judge output doesn't look like Nix — falling back to first proposal", C.YELLOW)
        return proposals[0][1]
    except Exception as exc:
        log(f"  ✗ Judge failed ({exc}) — falling back to first proposal", C.RED)
        return proposals[0][1]


# ── Variant → script path ─────────────────────────────────────────────────────

def resolve_script(flake_root: Path, variant: str) -> Path:
    """
    'M-salami'  →  <flake_root>/scripts/M/salami.nix

    Splits on the FIRST dash only — variant directory names must not contain
    dashes (device names may).
    """
    parts = variant.split("-", 1)
    if len(parts) != 2:
        sys.exit(f"Error: --variant must be <dir>-<device>, got '{variant}'")
    variant_dir, device = parts
    path = flake_root / "scripts" / variant_dir / f"{device}.nix"
    if not path.exists():
        sys.exit(f"Error: script not found at {path}")
    return path


# ── CLI ───────────────────────────────────────────────────────────────────────

def parse_model_arg(raw: str) -> ModelSpec:
    """Parse 'provider/model' into a ModelSpec."""
    parts = raw.split("/", 1)
    if len(parts) != 2:
        sys.exit(f"Invalid model spec '{raw}' — expected provider/model, e.g. anthropic/claude-opus-4-5")
    provider, model = parts
    key_env_map = {
        "anthropic": "ANTHROPIC_API_KEY",
        "openai":    "OPENAI_API_KEY",
        "gemini":    "GEMINI_API_KEY",
        "ollama":    "",
    }
    base_url_map = {
        "gemini": "https://generativelanguage.googleapis.com/v1beta/openai/",
        "ollama": os.environ.get("OLLAMA_BASE_URL", "http://localhost:11434/v1"),
    }
    return ModelSpec(
        provider=provider,
        model=model,
        base_url=base_url_map.get(provider),
        api_key_env=key_env_map.get(provider, ""),
    )


# ── Main ──────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="AI panel-powered Nix kernel build auto-fixer",
        epilog=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--variant", required=True,
        help="Build target, e.g. M-salami  (maps to scripts/M/salami.nix)",
    )
    parser.add_argument(
        "--flake-root", default=".",
        help="Path to flake root (default: current directory)",
    )
    parser.add_argument(
        "--max-retries", type=int, default=10,
        help="Max AI fix attempts before giving up (default: 10)",
    )
    parser.add_argument(
        "--no-backup", action="store_true",
        help="Skip creating .bak.<N> backups before each edit",
    )
    parser.add_argument(
        "--models", nargs="+", metavar="PROVIDER/MODEL",
        help=(
            "Override the default panel. "
            "First entry is the judge. "
            "Supported providers: anthropic, openai, gemini, ollama. "
            "Example: --models anthropic/claude-opus-4-5 openai/gpt-4o gemini/gemini-2.0-flash"
        ),
    )
    args = parser.parse_args()

    flake_root  = Path(args.flake_root).resolve()
    script_path = resolve_script(flake_root, args.variant)
    build_cmd   = f"nix build .#{args.variant} -L"

    # Build the panel
    if args.models:
        panel = [parse_model_arg(m) for m in args.models]
        panel[0].is_judge = True   # first is always judge
    else:
        panel = DEFAULT_PANEL

    active = available_models(panel)
    if not active:
        sys.exit(
            "No models available — set at least one API key:\n"
            "  ANTHROPIC_API_KEY, OPENAI_API_KEY, GEMINI_API_KEY\n"
            "or run a local Ollama instance."
        )

    # Promote first available model to judge if the default judge isn't available
    if not any(m.is_judge for m in active):
        active[0].is_judge = True
        log(f"Promoted {active[0]} to judge (no default judge available)", C.YELLOW)

    log(f"Flake root    : {flake_root}", C.BOLD)
    log(f"Script        : scripts/{args.variant.split('-', 1)[0]}/{args.variant.split('-', 1)[1]}.nix", C.BOLD)
    log(f"Build command : {build_cmd}", C.BOLD)
    log(f"Panel         : {', '.join(str(m) for m in active)}", C.BOLD)
    log(f"Max retries   : {args.max_retries}", C.BOLD)
    print()

    for attempt in range(1, args.max_retries + 2):
        returncode, output = run_build(build_cmd, flake_root)

        if returncode == 0:
            log("Build succeeded! 🎉", C.GREEN)
            sys.exit(0)

        log(f"Build failed (attempt {attempt}/{args.max_retries})", C.RED)

        if attempt > args.max_retries:
            log(f"Reached max retries ({args.max_retries}). Giving up.", C.RED)
            sys.exit(1)

        script_text = script_path.read_text()

        try:
            fixed = run_panel(active, script_text, output, attempt)
        except Exception as exc:
            log(f"Panel error: {exc}", C.RED)
            log("Waiting 15s before next attempt...", C.YELLOW)
            time.sleep(15)
            continue

        if not looks_like_nix(fixed):
            log("Panel output isn't valid Nix — skipping this attempt", C.YELLOW)
            continue

        if fixed.strip() == script_text.strip():
            log("Panel returned the script unchanged — couldn't determine a fix.", C.YELLOW)
            log("Manual intervention needed.", C.RED)
            sys.exit(2)

        if not args.no_backup:
            backup_path = script_path.with_suffix(f".bak.{attempt}")
            shutil.copy2(script_path, backup_path)
            log(f"Backup saved → {backup_path.name}", C.CYAN)

        script_path.write_text(fixed)
        log(f"Script updated by panel (attempt {attempt} → {attempt + 1})", C.CYAN)
        print()


if __name__ == "__main__":
    main()

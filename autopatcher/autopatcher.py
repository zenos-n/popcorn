#!/usr/bin/env python3
"""
FUCKING BROKEN LM<FASOOOAOAOAOAOFNMASIODFNADGIOPL:UKHBG:OP(UASDGBVIOPL:YUADHGBN)
autopatcher — AI panel-powered Nix kernel build fixer for Popcorn Kernel Forge.
FULLY LOCAL EDITION: Optimized for RX 6900XT / ROCm.
"""

import argparse
import os
import shutil
import subprocess
import sys
import time
import json
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

# ── Optional provider imports ─────────────────────────────────────────────────

_AIRLLM_MODEL_CACHE = {}
_OLLAMA_CHECKED_MODELS = set()

# ── Model spec ────────────────────────────────────────────────────────────────

@dataclass
class ModelSpec:
    provider: str   # "anthropic" | "openai" | "gemini" | "ollama" | "airllm"
    model: str
    is_judge: bool = False
    base_url: Optional[str] = None
    api_key_env: str = ""
    chunked: bool = False

    def __str__(self) -> str:
        role = " [judge]" if self.is_judge else ""
        mode = " [chunked]" if self.chunked else ""
        return f"{self.provider}/{self.model}{role}{mode}"

DEFAULT_PANEL: list[ModelSpec] = [
    ModelSpec("ollama", "qwen2.5-coder:14b", is_judge=True, base_url=os.environ.get("OLLAMA_BASE_URL", "http://localhost:11434/v1")),
    ModelSpec("ollama", "qwen2.5-coder:7b", is_judge=False, base_url=os.environ.get("OLLAMA_BASE_URL", "http://localhost:11434/v1")),
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

_SYS_SUMMARIZER = """\
[ ROLE: FORENSIC ANALYST ]
Your job is to find why the build FAILED. 

RULES:
1. NEVER say "The build completed successfully" unless you see a 'Finished' message at the very end.
2. If you see 'skipping ... architecture differs', list it as a WARNING.
3. If you see 'warn: auto-patchelf ignoring missing...', list it as a CRITICAL ERROR.
4. If you see 'No such file or directory', copy the EXACT command that caused it.
5. IGNORE "Setting RPATH" lines—they are noise. 
6. IGNORE "interpreter directive changed" lines - they are noise.
7. Output format:
   ERRORS: [List exact snippets of error logs]
   CONTEXT: [What was it doing?]
SECTION: {current}/{total}
"""

_SYS_PANELIST = """\
[ ROLE: ARCHITECT ]
You are a Nix Patcher. You ONLY speak in Unified Diff format.

### [ ! ] NEGATIVE EXAMPLE - DO NOT DO THIS:
"I found the error! You have a typo in the cd command. Here is the fix:
--- file
+++ file..."

### [ + ] POSITIVE EXAMPLE - DO THIS:
--- original.nix
+++ fixed.nix
@@ -145,1 +145,1 @@
-    cd /build/workspace..
+    cd /build/workspace

[ CONSTRAINTS ]
- NO conversational filler.
- NO Markdown code blocks (```).
- Start IMMEDIATELY with '---'.
- If you explain anything, the build will fail and you will be terminated.
"""

def _panelist_user(script: str, summaries: str, files: str, full_log: str) -> str:
    prompt = f"=== NIX SCRIPT ===\n{script}\n\n=== LOG SUMMARIES ===\n{summaries}\n"
    if files:
        prompt += f"\n=== REFERENCED FILES ===\n{files}\n"
    prompt += f"\n=== FULL LOG TAIL ===\n{full_log[-4000:]}"
    return prompt

# ── Map Reduce Logic ──────────────────────────────────────────────────────────

def _chunk_text(text: str, chunk_chars: int = 16000) -> list[str]:
    chunks, current = [], []
    current_len = 0
    for line in text.splitlines(keepends=True):
        if current_len + len(line) > chunk_chars and current:
            chunks.append("".join(current))
            current, current_len = [], 0
        current.append(line)
        current_len += len(line)
    if current: chunks.append("".join(current))
    return chunks

def _extract_and_read_files(text: str, cwd: Path) -> str:
    # Scan for file paths in the summaries
    paths = set(re.findall(r'(?:[a-zA-Z0-9_.-]+/)?[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+\.[a-zA-Z0-9]+', text))
    paths.update(re.findall(r'(?:\./)?[a-zA-Z0-9_./-]+\.(?:nix|c|h|patch|sh|mk|Makefile)', text))
    
    file_contents = []
    for p in paths:
        clean_p = p.strip("':\",()[]{}")
        full_path = cwd / clean_p
        
        # Only read existing local files inside the flake_root that aren't excessively huge
        if full_path.exists() and full_path.is_file():
            try:
                content = full_path.read_text()
                if len(content) < 15000: 
                    file_contents.append(f"--- FILE: {clean_p} ---\n{content}")
            except Exception:
                pass
                
    return "\n\n".join(file_contents) if file_contents else ""

def run_summarizer(summarizer: ModelSpec, log_text: str) -> str:
    chunks = _chunk_text(log_text, chunk_chars=16000) # ~4000 tokens
    summaries = []
    
    log(f"Breaking log into {len(chunks)} chunks for summarization...", C.CYAN)
    
    for i, chunk in enumerate(chunks, 1):
        log(f"  → Summarizing part {i}/{len(chunks)}...", C.DIM)
        sys_prompt = _SYS_SUMMARIZER.replace("{current}", str(i)).replace("{total}", str(len(chunks)))
        user_msg = f"=== LOG CHUNK ===\n{chunk}"
        
        try:
            res = call_model(summarizer, sys_prompt, user_msg)
            
            # Formatting safety fallback in case the model ignored instructions
            if "ERRORS FOUND:" not in res:
                res = f"ERRORS FOUND: {res}\nLOG SUMMARY: Unknown\nSECTION: {i}/{len(chunks)}"
                
            summaries.append(res.strip())
            print(res.strip())
        except Exception as e:
            log(f"  ✗ Summarizer failed on chunk {i}: {e}", C.YELLOW)
            summaries.append(f"ERRORS FOUND: (Failed to summarize)\nLOG SUMMARY: (Failed)\nSECTION: {i}/{len(chunks)}")
            print(res.strip())

    return "\n\n=================================\n\n".join(summaries)


# ── Model callers ─────────────────────────────────────────────────────────────

def _call_airllm(spec: ModelSpec, system: str, user: str) -> str:
    # PREVENT FRAGMENTATION ON RDNA2
    os.environ["PYTORCH_HIP_ALLOC_CONF"] = "expandable_segments:True"
    
    try:
        import torch
        from airllm import AutoModel
    except Exception as e:
        raise RuntimeError(f"ML Stack initialization failed (Missing Nix lib?): {e}")

    if spec.model not in _AIRLLM_MODEL_CACHE:
        log(f"[AirLLM] Initializing {spec.model} (Memory-tuned)...", C.CYAN)
        
        # HACK: Bypass ROCm multi-GPU polling hang in Transformers 4.46+
        # AirLLM rejects the 'attn_implementation' kwarg, so we spoof the device count instead.
        original_device_count = torch.cuda.device_count
        torch.cuda.device_count = lambda: 1
        
        # 4224 gives breathing room for the 4096 truncation to avoid off-by-one RoPE crashes
        _AIRLLM_MODEL_CACHE[spec.model] = AutoModel.from_pretrained(
            spec.model, 
            max_seq_len=4224
        )
        
        # Restore original device count logic
        torch.cuda.device_count = original_device_count

    model = _AIRLLM_MODEL_CACHE[spec.model]
    prompt = f"<|im_start|>system\n{system}<|im_end|>\n<|im_start|>user\n{user}<|im_end|>\n<|im_start|>assistant\n"
    
    # Strictly truncate at 4096 to keep VRAM usage predictable
    input_tokens = model.tokenizer([prompt], return_tensors="pt", return_attention_mask=False, truncation=True, max_length=4096, padding=False)
    
    log(f"[AirLLM] Evaluating context ({input_tokens['input_ids'].shape[1]} tokens). Executing final pass...", C.MAGENTA)
    
    with torch.no_grad():
        generation_output = model.generate(input_tokens['input_ids'].cuda(), max_new_tokens=1024, use_cache=True, return_dict_in_generate=True)
    
    output = model.tokenizer.decode(generation_output.sequences[0])
    torch.cuda.empty_cache()

    if "<|im_start|>assistant\n" in output:
        raw_fix = output.split("<|im_start|>assistant\n")[-1].replace("<|im_end|>", "").strip()
    else:
        raw_fix = output.strip()
        
    # Final cleanup to remove any stubborn markdown blocks that Qwen might hallucinate
    return raw_fix.replace("```diff", "").replace("```", "").strip()

def _call_openai_compat(spec: ModelSpec, system: str, user: str) -> str:
    import requests
    # Correcting base_url to point to the base instead of /v1 for native API compatibility
    base_url = spec.base_url.replace("/v1", "") if spec.base_url else "http://localhost:11434"
    
    # Ollama Pull Logic (Native API)
    if spec.provider == "ollama" and spec.model not in _OLLAMA_CHECKED_MODELS:
        try:
            log(f"Checking/Pulling Ollama model '{spec.model}' (this may take a while)...", C.CYAN)
            # FIX: Use "name" instead of "model" and require "stream": False to block execution
            pull_resp = requests.post(f"{base_url}/api/pull", json={"name": spec.model, "stream": False})
            pull_resp.raise_for_status()
            _OLLAMA_CHECKED_MODELS.add(spec.model)
        except Exception as e:
            # FIX: Stop silently swallowing pull errors so you know if your tag is invalid
            log(f"Ollama pull failed for {spec.model}: {e}", C.YELLOW)

    # Using Native Ollama /api/chat endpoint to bypass /v1 404 errors
    resp = requests.post(f"{base_url}/api/chat", json={
        "model": spec.model,
        "messages": [
            {"role": "system", "content": system}, 
            {"role": "user", "content": user}
        ],
        "keep_alive": 0,
        "stream": False,
        "options": {
            "temperature": 0.0,
            "num_ctx": 8192
        }
    })
    resp.raise_for_status()
    content = resp.json()["message"]["content"]
    
    # FORCE: Strip Markdown code blocks if the model ignored instructions
    if "```" in content:
        # Extract only the content between ```diff and ``` or ``` and ```
        match = re.search(r"```(?:diff)?\n(.*?)\n```", content, re.DOTALL)
        if match:
            content = match.group(1)
        else:
            # Fallback: just remove the tick marks manually
            content = content.replace("```diff", "").replace("```", "")
            
    return content.strip()

def call_model(spec: ModelSpec, system: str, user: str) -> str:
    if spec.provider == "airllm":
        return _call_airllm(spec, system, user)
    return _call_openai_compat(spec, system, user)

# ── Build runner ──────────────────────────────────────────────────────────────

_TAIL_LINES = 30

def _terminal_width() -> int: return os.get_terminal_size().columns if sys.stdout.isatty() else 120
def _strip_ansi(text: str) -> str: return re.sub(r'\x1b\[[0-9;]*[mAJK]', '', text)
def _fit_line(line: str, width: int) -> str:
    clean = _strip_ansi(line)
    return clean[:width - 1] + "…" if len(clean) > width else clean

def run_build(cmd: str, cwd: Path) -> tuple[int, str]:
    log(f"Running: {cmd}", C.BOLD)
    all_lines, tail = [], []

    def _redraw() -> None:
        width = _terminal_width()
        sys.stdout.write(f"\033[{_TAIL_LINES + 1}A\033[J{C.DIM}{'─' * min(68, width)}{C.RESET}\n")
        for line in tail: sys.stdout.write(f"{C.DIM}{_fit_line(line, width)}{C.RESET}\n")
        for _ in range(_TAIL_LINES - len(tail)): sys.stdout.write("\n")
        sys.stdout.flush()

    sys.stdout.write(f"{C.DIM}{'─' * min(68, _terminal_width())}{C.RESET}\n" + "\n" * _TAIL_LINES)
    sys.stdout.flush()

    proc = subprocess.Popen(cmd, shell=True, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
    for raw_line in proc.stdout:
        line = raw_line.rstrip("\n")
        all_lines.append(line); tail.append(line)
        if len(tail) > _TAIL_LINES: tail.pop(0)
        _redraw()
    proc.wait()
    return proc.returncode, "\n".join(all_lines)

def looks_like_patch(text: str) -> bool:
    return "--- " in text and "+++ " in text and "@@" in text

# ── Main Logic ────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--variant", required=True)
    parser.add_argument("--flake-root", default=".")
    parser.add_argument("--max-retries", type=int, default=100)
    parser.add_argument("--models", nargs="+")
    parser.add_argument("--summarizer")
    args = parser.parse_args()

    flake_root = Path(args.flake_root).resolve()
    parts = args.variant.split("-", 1)
    script_path = flake_root / "scripts" / parts[0] / f"{parts[1]}.nix"
    build_cmd = f"nix build .#{args.variant} -L"

    # Setup Models
    def parse_spec(s):
        p, m = s.split("/", 1)
        url = os.environ.get("OLLAMA_BASE_URL", "http://localhost:11434/v1") if p == "ollama" else None
        return ModelSpec(p, m, base_url=url)

    active = [parse_spec(m) for m in args.models] if args.models else DEFAULT_PANEL
    active[0].is_judge = True
    summarizer = parse_spec(args.summarizer) if args.summarizer else ModelSpec("ollama", "qwen2.5-coder:3b", base_url="http://localhost:11434/v1")

    # ── Pre-flight Checks (with Retry for Ollama Initialization) ──
    if summarizer.provider == "ollama":
        connected = False
        import requests
        for attempt in range(5):
            try:
                requests.get(summarizer.base_url.replace("/v1", "/api/tags"), timeout=2)
                connected = True
                break
            except Exception:
                log(f"Waiting for Ollama to initialize (Attempt {attempt+1}/5)...", C.DIM)
                time.sleep(3)
        
        if not connected:
            log(f"CRITICAL: Ollama is not responding at {summarizer.base_url}. Please start it (e.g., `systemctl start ollama` or `ollama serve`).", C.RED)
            sys.exit(1)

    for attempt in range(1, args.max_retries + 1):
        returncode, output = run_build(build_cmd, flake_root)
        if returncode == 0:
            log("SUCCESS! Build complete. 🎉", C.GREEN); sys.exit(0)

        log(f"Build failed (Attempt {attempt})", C.RED)
        script_text = script_path.read_text()
        
        banner(f"Deliberation — Attempt {attempt}")
        
        try:
            # Phase 1: Summarize massive logs via fast model (Ollama)
            summaries = run_summarizer(summarizer, output)
            
            # Phase 2: Extract any local context files mentioned in the summary
            referenced_files = _extract_and_read_files(summaries, flake_root)
            
            # Phase 3: Synthesize patch via Judge model
            user_prompt = _panelist_user(script_text, summaries, referenced_files, output)
            fixed_patch = call_model(active[0], _SYS_PANELIST, user_prompt)
            
            # --- NEW: Debug Output ---
            print(f"\n{C.CYAN}--- RAW MODEL RESPONSE START ---{C.RESET}")
            print(fixed_patch)
            print(f"{C.CYAN}--- RAW MODEL RESPONSE END ---\n{C.RESET}")
            # -------------------------

            if not looks_like_patch(fixed_patch):
                log("Invalid patch format returned. Retrying...", C.YELLOW)
                continue

            # Apply patch
            shutil.copy2(script_path, script_path.with_suffix(f".bak.{attempt}"))
            patch_res = subprocess.run(["patch", "--force", "-u", str(script_path)], input=fixed_patch, text=True, capture_output=True)
            
            if patch_res.returncode != 0:
                log(f"Patch apply failed: {patch_res.stderr}", C.RED)
                shutil.copy2(script_path.with_suffix(f".bak.{attempt}"), script_path)
                continue

            log("Patch applied! Re-trying build...\n", C.GREEN)
            
        except Exception as e:
            log(f"Error: {e}", C.RED)
            time.sleep(5)

if __name__ == "__main__":
    main()

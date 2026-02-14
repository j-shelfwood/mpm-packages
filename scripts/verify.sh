#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
export PATH="$HOME/.luarocks/bin:$PATH"

FAILURES=0

log() {
  printf '%s\n' "$*"
}

fail() {
  printf '[FAIL] %s\n' "$*"
  FAILURES=$((FAILURES + 1))
}

pass() {
  printf '[PASS] %s\n' "$*"
}

run_section() {
  local name="$1"
  log ""
  log "== $name =="
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1
}

run_section "JSON validation"
while IFS= read -r file; do
  if jq empty "$file" >/dev/null 2>&1; then
    pass "$file"
  else
    fail "$file is invalid JSON"
  fi
done < <(find mpm mpm-packages -type f \( -name 'manifest.json' -o -name 'index.json' \) | sort)

run_section "Lua syntax"
while IFS= read -r file; do
  if luac -p "$file" >/dev/null 2>&1; then
    pass "$file"
  else
    fail "$file has syntax errors"
  fi
done < <(find mpm mpm-packages -type f -name '*.lua' | sort)

run_section "Manifest coverage (mpm-packages)"
while IFS= read -r manifest; do
  pkg_dir="$(dirname "$manifest")"
  pkg_name="$(basename "$pkg_dir")"

  if ! jq -e '.files and (.files | type == "array")' "$manifest" >/dev/null 2>&1; then
    fail "$manifest missing files array"
    continue
  fi

  declared_tmp="$(mktemp)"
  disk_tmp="$(mktemp)"

  jq -r '.files[]?' "$manifest" | sort -u > "$declared_tmp"
  find "$pkg_dir" -type f -name '*.lua' | sed "s#^$pkg_dir/##" | sort -u > "$disk_tmp"

  while IFS= read -r rel; do
    [[ -z "$rel" ]] && continue
    if [[ ! -f "$pkg_dir/$rel" ]]; then
      fail "$manifest references missing file: $rel"
    fi
  done < "$declared_tmp"

  while IFS= read -r rel; do
    [[ -z "$rel" ]] && continue
    if ! grep -Fxq "$rel" "$declared_tmp"; then
      fail "$manifest missing file entry: $pkg_name/$rel"
    fi
  done < "$disk_tmp"

  rm -f "$declared_tmp" "$disk_tmp"
  pass "$manifest"
done < <(find mpm-packages -mindepth 2 -maxdepth 2 -type f -name manifest.json | sort)

run_section "Index cross-check (mpm-packages/index.json)"
if [[ -f mpm-packages/index.json ]]; then
  while IFS= read -r pkg; do
    [[ -z "$pkg" ]] && continue
    if [[ -f "mpm-packages/$pkg/manifest.json" ]]; then
      pass "index entry '$pkg' has manifest"
    else
      fail "index entry '$pkg' missing manifest at mpm-packages/$pkg/manifest.json"
    fi
  done < <(jq -r '.[].name' mpm-packages/index.json)
else
  fail "mpm-packages/index.json missing"
fi

run_section "Lua unit tests"
if lua tests/lua/run.lua "$ROOT_DIR"; then
  pass "tests/lua/run.lua"
else
  fail "tests/lua/run.lua"
fi

run_section "Optional tool checks"
if require_cmd luacheck; then
  if [[ -f ".luacheckrc" || -f "luacheckrc" ]]; then
    if luacheck mpm mpm-packages; then
      pass "luacheck"
    else
      fail "luacheck"
    fi
  else
    log "[SKIP] luacheck installed but no .luacheckrc found"
  fi
else
  log "[SKIP] luacheck not installed"
fi

if require_cmd stylua; then
  if [[ -f ".stylua.toml" || -f "stylua.toml" ]]; then
    if stylua --check mpm mpm-packages tests/lua scripts; then
      pass "stylua --check"
    else
      fail "stylua --check"
    fi
  else
    log "[SKIP] stylua installed but no stylua.toml found"
  fi
else
  log "[SKIP] stylua not installed"
fi

CRAFTOS_CMD=""
if require_cmd craftos; then
  CRAFTOS_CMD="craftos"
elif require_cmd craftos-pc; then
  CRAFTOS_CMD="craftos-pc"
elif [[ -x "/Applications/CraftOS-PC.app/Contents/MacOS/craftos" ]]; then
  CRAFTOS_CMD="/Applications/CraftOS-PC.app/Contents/MacOS/craftos"
fi

if [[ -n "$CRAFTOS_CMD" ]]; then
  CRAFTOS_DATA_DIR="$ROOT_DIR/.tmp/craftos-ci"
  mkdir -p "$CRAFTOS_DATA_DIR"
  if "$CRAFTOS_CMD" \
      --headless \
      --directory "$CRAFTOS_DATA_DIR" \
      --mount-ro "/workspace=$ROOT_DIR" \
      --exec 'local p=dofile("/workspace/mpm-packages/net/Protocol.lua"); local c=dofile("/workspace/mpm-packages/net/Crypto.lua"); local t=dofile("/workspace/mpm-packages/utils/Text.lua"); local m=p.createMessage(p.MessageType.PING,{}); assert(m.type=="ping"); print("craftos smoke ok"); os.shutdown()' \
      >/dev/null 2>&1; then
    pass "$CRAFTOS_CMD headless smoke"
  else
    fail "$CRAFTOS_CMD headless smoke"
  fi
else
  log "[SKIP] craftos/craftos-pc not installed"
fi

log ""
if [[ $FAILURES -eq 0 ]]; then
  log "Verification PASSED"
  exit 0
else
  log "Verification FAILED ($FAILURES issue(s))"
  exit 1
fi

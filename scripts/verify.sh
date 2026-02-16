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

run_section "JSON validation"
while IFS= read -r file; do
  if jq empty "$file" >/dev/null 2>&1; then
    pass "$file"
  else
    fail "$file is invalid JSON"
  fi
done < <(find . -type f \( -name 'manifest.json' -o -name 'index.json' \) -not -path './tests/*' -not -path './.git/*' | sort)

run_section "Lua syntax"
while IFS= read -r file; do
  if luac -p "$file" >/dev/null 2>&1; then
    pass "$file"
  else
    fail "$file has syntax errors"
  fi
done < <(find . -type f -name '*.lua' -not -path './tests/*' -not -path './.git/*' | sort)

run_section "Manifest coverage"
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
done < <(find . -mindepth 2 -maxdepth 2 -type f -name manifest.json -not -path './tests/*' -not -path './.git/*' | sort)

run_section "Index cross-check (index.json)"
if [[ -f index.json ]]; then
  while IFS= read -r pkg; do
    [[ -z "$pkg" ]] && continue
    if [[ -f "./$pkg/manifest.json" ]]; then
      pass "index entry '$pkg' has manifest"
    else
      fail "index entry '$pkg' missing manifest at $pkg/manifest.json"
    fi
  done < <(jq -r '.[].name' index.json)
else
  fail "index.json missing"
fi

run_section "CraftOS integration scenarios"
if tests/craftos/run_tests.sh; then
  pass "tests/craftos/run_tests.sh"
else
  fail "tests/craftos/run_tests.sh"
fi

log ""
if [[ $FAILURES -eq 0 ]]; then
  log "Verification PASSED"
  exit 0
else
  log "Verification FAILED ($FAILURES issue(s))"
  exit 1
fi

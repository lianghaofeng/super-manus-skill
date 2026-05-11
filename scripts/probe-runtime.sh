#!/usr/bin/env bash
# Passive runtime probe for /super-manus:reverse-prd-spec Stage 2 (renamed from
# /super-manus:reverse-prd in v0.9.5 R9 — script unchanged otherwise).
#
# Reads what's currently running (processes, ports, docker containers, compose
# services, OpenAPI contracts) plus git activity (deleted/cold/hot files) and
# emits a fixed-format report on stdout. The reverse-architect agent consumes
# this as cross-validation evidence against static source reading (agent
# renamed from reverse-prd-architect in v0.9.5 R9).
#
# Contract:
#   - Read-only. NEVER invokes mutating commands (docker run/up, psql -c "...",
#     git commit/push/reset/checkout). docker compose up gating is the
#     orchestrator's job, not this script's.
#   - Always exits 0 even when every probe fails — orchestrator does not
#     depend on exit code.
#   - Total wall-clock budget ≤ 30s; every external command has its own timeout.
#   - Header lines (=== / ---) are part of the contract; renaming breaks the
#     agent's parser. See docs/design-v0.8.md.

set -uo pipefail

PROJECT_ROOT="${PWD}"
PORTS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --project-root)
      PROJECT_ROOT="$2"; shift 2 ;;
    --ports)
      PORTS="$2"; shift 2 ;;
    *)
      shift ;;
  esac
done

START_EPOCH=$(date +%s)
SKIPPED=()

case "$(uname -s)" in
  Darwin) PLATFORM="darwin" ;;
  Linux)  PLATFORM="linux"  ;;
  *)      PLATFORM="other"  ;;
esac

# tiny helper: runs a command with timeout, returns its stdout, swallows stderr.
# Preference: GNU timeout > gtimeout > perl alarm > raw exec. macOS lacks GNU
# timeout by default but ships perl; perl alarm is silent (no job-control noise).
# usage: with_timeout <secs> <cmd> [args...]
with_timeout() {
  local secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@" 2>/dev/null || true
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secs" "$@" 2>/dev/null || true
  elif command -v perl >/dev/null 2>&1; then
    perl -e 'alarm shift; exec @ARGV' "$secs" "$@" 2>/dev/null || true
  else
    "$@" 2>/dev/null || true
  fi
}

ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || echo "unknown")
echo "=== RUNTIME PROBE (probe-runtime.sh @ ${ts}) ==="
echo

# ---------- 1. Running processes ----------
echo "--- Running processes ---"
proc_pat='uvicorn|gunicorn|hypercorn|fastapi|flask|node |npm run|pnpm |yarn |cargo run|go run|python -m|python3 -m|next |vite|rails |puma|streamlit'
proc_out=$(ps -eo pid,command 2>/dev/null \
  | grep -iE "$proc_pat" \
  | grep -vE 'grep -iE|probe-runtime\.sh' \
  | grep -F "$PROJECT_ROOT" \
  | head -20 \
  || true)
if [ -z "$proc_out" ]; then
  echo "(none detected)"
else
  echo "$proc_out"
fi
echo

# ---------- 2. Listening ports ----------
echo "--- Listening ports ---"
# v0.9.3: grayfilter drops processes that are guaranteed-non-project on macOS
# / Linux developer machines (system / IDE / chat-app noise). Without the
# filter, lsof | head -40 spends most of its quota on ControlCe, rapportd,
# Code\x20H Helper, Electron, language_, WeChat, privoxy, ss-local, and
# docker-desktop's own management process com.docke — none of which can be
# super-manus modules. Filter is intentionally conservative; only entries
# that are 100% confidence "not a project process" land here. See
# docs/design-v0.9.3.md item 1 for criteria + how to extend the list.
LISTEN_NOISE_RE='^(ControlCe|rapportd|Code\\x20H|Electron|language_|WeChat|privoxy|ss-local|com\.docke)'
listen_out=""
if command -v lsof >/dev/null 2>&1; then
  listen_out=$(with_timeout 3 lsof -iTCP -sTCP:LISTEN -P -n \
    | awk 'NR==1 || $0 ~ /LISTEN/' \
    | grep -vE "$LISTEN_NOISE_RE" \
    | head -40 || true)
elif command -v ss >/dev/null 2>&1; then
  listen_out=$(with_timeout 3 ss -tlnp 2>/dev/null \
    | grep -vE "$LISTEN_NOISE_RE" \
    | head -40 || true)
fi
if [ -z "$listen_out" ]; then
  echo "(probe unavailable: neither lsof nor ss returned data)"
  SKIPPED+=("Listening ports: no usable listing tool")
else
  echo "$listen_out"
fi

# Extract localhost-bound TCP ports for OpenAPI probing
detected_ports=$(echo "$listen_out" \
  | grep -oE '(127\.0\.0\.1|localhost|0\.0\.0\.0|\*|::1|\[::\]):[0-9]+' \
  | grep -oE '[0-9]+$' \
  | sort -un \
  | head -20 \
  || true)
echo

# ---------- 3. Docker containers ----------
echo "--- Docker containers ---"
if ! command -v docker >/dev/null 2>&1; then
  echo "(docker not installed)"
  SKIPPED+=("Docker containers: docker CLI missing")
else
  if ! with_timeout 3 docker info >/dev/null 2>&1; then
    echo "(docker daemon not running)"
    SKIPPED+=("Docker containers: daemon not running")
  else
    docker_out=$(with_timeout 3 docker ps \
      --format '{{.Names}}	{{.Image}}	{{.Status}}	{{.Ports}}' \
      | head -30 || true)
    if [ -z "$docker_out" ]; then
      echo "(none)"
    else
      echo "$docker_out"
    fi
  fi
fi
echo

# ---------- 4. Compose services ----------
echo "--- Compose services ---"
compose_file=""
for cand in \
  "$PROJECT_ROOT/docker-compose.yml" \
  "$PROJECT_ROOT/compose.yaml" \
  "$PROJECT_ROOT/compose.yml" \
  "$PROJECT_ROOT/infra/docker-compose.yml" \
  "$PROJECT_ROOT/deploy/docker-compose.yml" \
  "$PROJECT_ROOT/docker/docker-compose.yml" \
; do
  if [ -f "$cand" ]; then
    compose_file="$cand"
    break
  fi
done

if [ -z "$compose_file" ]; then
  echo "(no compose file detected)"
  SKIPPED+=("Compose services: no compose file in standard locations")
elif ! command -v docker >/dev/null 2>&1; then
  echo "Compose file: $compose_file"
  echo "(docker CLI missing — cannot enumerate services)"
  SKIPPED+=("Compose services: docker CLI missing")
else
  echo "Compose file: $compose_file"
  ps_out=$(with_timeout 5 docker compose -f "$compose_file" ps \
    --format '{{.Service}}	{{.Image}}	{{.State}}	{{.Status}}' \
    | head -30 || true)
  if [ -z "$ps_out" ]; then
    # Try classic docker-compose binary as a fallback
    if command -v docker-compose >/dev/null 2>&1; then
      ps_out=$(with_timeout 5 docker-compose -f "$compose_file" ps | head -30 || true)
    fi
  fi
  if [ -z "$ps_out" ]; then
    echo "(no services running — compose file present but `docker compose ps` empty)"
  else
    echo "$ps_out"
  fi
  # Extract service-declared ports from the compose file (best effort, regex)
  declared_ports=$(grep -E '^\s+-\s+"?[0-9]+(:[0-9]+)?' "$compose_file" 2>/dev/null \
    | grep -oE '[0-9]+(:[0-9]+)?' \
    | awk -F: '{print $1}' \
    | sort -un \
    | head -20 || true)
fi
echo

# ---------- 5. OpenAPI contracts ----------
echo "--- OpenAPI contracts ---"
# Port set: explicit --ports arg ∪ compose-declared ports, intersected with
# what's actually listening. We do NOT auto-probe arbitrary listening ports —
# on a developer machine that's 30+ ports of WeChat / Code / system services,
# and the curl × paths matrix would exceed the 30s wall-clock budget.
# If compose has no port declarations and no --ports passed, we skip OpenAPI.
known_infra_ports='^(5432|5433|3306|6379|11211|27017|9200|9300|2181|9092|5672|15672|4222|8222|6333|6334|6335|6336|9090|9093|3000|9100|3100|4317|4318|16686|16685|9411|25|587|465|143|993|110|995|22)$'

candidate_ports=$(printf "%s\n%s\n" \
  "$(echo "$PORTS" | tr ',' '\n')" \
  "${declared_ports:-}" \
  | grep -E '^[0-9]+$' \
  | grep -vE "$known_infra_ports" \
  | sort -un \
  | head -10 \
  || true)
# Intersect with actually-listening (skip ports that are declared but nothing listens on)
if [ -n "$candidate_ports" ] && [ -n "$detected_ports" ]; then
  all_ports=$(comm -12 <(echo "$candidate_ports" | sort -un) <(echo "$detected_ports" | sort -un) | head -10)
elif [ -n "$candidate_ports" ]; then
  # No detected_ports list (lsof/ss missing); try the candidates anyway
  all_ports="$candidate_ports"
else
  all_ports=""
fi
if [ -z "$all_ports" ]; then
  echo "(no candidate ports — nothing to probe)"
  SKIPPED+=("OpenAPI contracts: no candidate ports")
elif ! command -v curl >/dev/null 2>&1; then
  echo "(curl not installed)"
  SKIPPED+=("OpenAPI contracts: curl missing")
else
  any_hit=0
  for port in $all_ports; do
    for path in /openapi.json /docs/openapi.json /api/openapi.json /v1/openapi.json /swagger.json /api-docs /openapi.yaml; do
      url="http://localhost:${port}${path}"
      tmp=$(mktemp 2>/dev/null) || continue
      code=$(with_timeout 3 curl -sS -o "$tmp" -w '%{http_code}' "$url" 2>/dev/null || echo "000")
      if [ "$code" = "200" ] && [ -s "$tmp" ]; then
        first_byte=$(head -c1 "$tmp" 2>/dev/null)
        case "$first_byte" in
          '{'|'o'|'s')
            size=$(wc -c < "$tmp" | tr -d ' ')
            # Extract path keys (JSON only — quick & dirty regex)
            path_lines=$(grep -oE '"/[A-Za-z0-9_./{}-]+"' "$tmp" 2>/dev/null \
              | sed 's/^"//; s/"$//' \
              | sort -u \
              | head -15 || true)
            total_paths=$(grep -oE '"/[A-Za-z0-9_./{}-]+"' "$tmp" 2>/dev/null \
              | sort -u | wc -l | tr -d ' ' || echo "0")
            echo "${url} (${size} bytes, ${total_paths} paths)"
            if [ -n "$path_lines" ]; then
              echo "$path_lines" | while IFS= read -r p; do echo "  ${p}"; done
              if [ "$total_paths" -gt 15 ] 2>/dev/null; then
                echo "  ...(truncated, total ${total_paths})"
              fi
            fi
            any_hit=1
            rm -f "$tmp"
            break  # one hit per port is enough
            ;;
        esac
      fi
      rm -f "$tmp"
    done
  done
  if [ "$any_hit" -eq 0 ]; then
    echo "(no OpenAPI/Swagger response on candidate ports: $all_ports)"
  fi
fi
echo

# ---------- 6. Git activity ----------
echo "--- Git activity ---"
if ! command -v git >/dev/null 2>&1; then
  echo "(git not installed)"
  SKIPPED+=("Git activity: git missing")
elif ! git -C "$PROJECT_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  echo "(not a git repository: $PROJECT_ROOT)"
  SKIPPED+=("Git activity: not a git repo")
else
  echo "Deleted in last 50 commits:"
  deleted=$(with_timeout 5 git -C "$PROJECT_ROOT" log --diff-filter=D \
    --name-only --pretty=format: -50 2>/dev/null \
    | grep -vE '^$' \
    | sort -u \
    | head -10 || true)
  if [ -z "$deleted" ]; then
    echo "  (none)"
  else
    echo "$deleted" | while IFS= read -r f; do echo "  $f"; done
  fi
  echo

  echo "Cold files (no edit in last 6 months, top 10 code files):"
  six_months_ago=$(with_timeout 2 git -C "$PROJECT_ROOT" log \
    --since="6 months ago" --name-only --pretty=format: 2>/dev/null \
    | grep -vE '^$' | sort -u || true)
  all_code=$(with_timeout 2 git -C "$PROJECT_ROOT" ls-files 2>/dev/null \
    | grep -E '\.(py|ts|tsx|js|jsx|go|rs|rb|java|kt|swift)$' \
    | grep -vE '(^|/)(node_modules|vendor|dist|build|\.venv|venv|target|out|\.next)/' \
    || true)
  if [ -n "$all_code" ] && [ -n "$six_months_ago" ]; then
    cold=$(comm -23 <(echo "$all_code" | sort -u) <(echo "$six_months_ago" | sort -u) | head -10)
  else
    cold=""
  fi
  if [ -z "$cold" ]; then
    echo "  (none — all code files have been touched recently, or no code files found)"
  else
    echo "$cold" | while IFS= read -r f; do
      last=$(with_timeout 1 git -C "$PROJECT_ROOT" log -1 --format='%ad' --date=short -- "$f" 2>/dev/null || echo "?")
      echo "  $f  (last touched $last)"
    done
  fi
  echo

  echo "Hot files (most edits in last 6 months, top 10):"
  hot=$(with_timeout 5 git -C "$PROJECT_ROOT" log --since="6 months ago" \
    --name-only --pretty=format: 2>/dev/null \
    | grep -vE '^$' \
    | grep -E '\.(py|ts|tsx|js|jsx|go|rs|rb|java|kt|swift)$' \
    | grep -vE '(^|/)(node_modules|vendor|dist|build|\.venv|venv|target|out|\.next)/' \
    | sort | uniq -c | sort -rn | head -10 || true)
  if [ -z "$hot" ]; then
    echo "  (none)"
  else
    echo "$hot" | while IFS= read -r line; do
      count=$(echo "$line" | awk '{print $1}')
      file=$(echo "$line" | awk '{$1=""; print substr($0,2)}')
      echo "  $file  ($count edits)"
    done
  fi
fi
echo

# ---------- 7. Notes ----------
echo "--- Notes ---"
echo "Platform: $PLATFORM"
END_EPOCH=$(date +%s)
DURATION=$((END_EPOCH - START_EPOCH))
echo "Total duration: ${DURATION}s"
if [ "${#SKIPPED[@]}" -eq 0 ]; then
  echo "Skipped probes: (none)"
else
  echo "Skipped probes:"
  for s in "${SKIPPED[@]}"; do
    echo "  - $s"
  done
fi
echo

exit 0

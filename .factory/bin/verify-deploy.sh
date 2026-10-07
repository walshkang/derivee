#!/bin/bash
# verify-deploy.sh — orchestrator verify-before-claim for deploys.
#
# Usage: verify-deploy.sh <url> <expected-commit>
#
# Catches the two mistakes that burned us on 2026-10-06:
#   1. Wrong deployment target: pages.dev can never serve /api/* (static
#      hosting). Only the worker URL serves app + API on one origin.
#   2. Stale build: the served bundle must report the expected commit.
#
# Checks:
#   1. <url>/ returns HTTP 200.
#   2. <url>/api/health returns JSON {"ok": true} — proves worker-served.
#      HTML or 404 here means wrong target (or Access-blocked; reported).
#   3. The served JS bundle contains the expected commit hash (7-char).
#
# Exit 0: verified. Exit 1: FAILED with reason on stderr.
# Exit 2: could not verify (Access-blocked / unreachable) — honest unknown,
#   never a pass.

set -u

URL="${1:-}"
EXPECTED="${2:-}"

fail() { echo "VERIFY-FAIL: $1" >&2; exit 1; }
unknown() { echo "VERIFY-UNKNOWN: $1" >&2; exit 2; }

[ -n "$URL" ] || { echo "usage: verify-deploy.sh <url> <expected-commit>" >&2; exit 2; }
[ -n "$EXPECTED" ] || { echo "usage: verify-deploy.sh <url> <expected-commit>" >&2; exit 2; }
# Normalize commit to 7-char lowercase prefix
EXPECTED="$(echo "$EXPECTED" | cut -c1-7 | tr 'A-Z' 'a-z')"
URL="$(echo "$URL" | sed 's:/*$::')"

CURL="curl -sS -m 20 -L --max-redirs 3"

# 1. App reachable
CODE="$($CURL -o /dev/null -w '%{http_code}' "$URL/" 2>/dev/null)" \
  || unknown "cannot reach $URL/ (network error)"
[ "$CODE" = "200" ] || unknown "$URL/ returned HTTP $CODE (likely Cloudflare Access gate — verify in browser)"

# 2. /api/health must return JSON {"ok": true}
HEALTH="$($CURL "$URL/api/health" 2>/dev/null)" \
  || unknown "cannot reach $URL/api/health"
echo "$HEALTH" | grep -q '"ok"[[:space:]]*:[[:space:]]*true' \
  || fail "$URL/api/health did not return {\"ok\": true} — wrong deployment target (pages.dev cannot serve /api/*) or Access-blocked. Got: $(echo "$HEALTH" | head -c 120)"

# 3. Served bundle reports the expected commit.
#    The build hash is Vite-injected into the main JS bundle at build time.
JS_PATH="$( $CURL "$URL/" 2>/dev/null \
  | grep -o 'assets/index-[A-Za-z0-9_.-]*\.js' | head -1 )"
[ -n "$JS_PATH" ] || unknown "could not find main JS bundle in $URL/ HTML"
JS="$($CURL "$URL/$JS_PATH" 2>/dev/null)" \
  || unknown "cannot fetch $URL/$JS_PATH"
echo "$JS" | grep -qi "$EXPECTED" \
  || fail "served bundle does not contain commit $EXPECTED (stale build). Bundle: $JS_PATH"

echo "VERIFY-OK: $URL serves commit $EXPECTED with working /api/*"
exit 0

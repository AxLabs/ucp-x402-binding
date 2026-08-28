#!/usr/bin/env bash
# validate.sh — validate the binding's schemas and examples with the official
# ucp-schema CLI (https://github.com/Universal-Commerce-Protocol/ucp-schema).
#
# Requirements:
#   cargo install ucp-schema            # official UCP org, Apache-2.0
#   UCP_SPEC_REPO — a clone of Universal-Commerce-Protocol/ucp at tag v2026-08-25
#
# Usage:
#   ./validate.sh /path/to/ucp   # defaults to /tmp/research/ucp-20260825
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SPEC="${1:-/tmp/research/ucp-20260825}"
LB="$SPEC/source"
REMOTE="https://ucp.dev/2026-08-25"
fail=0

echo "== lint =="
ucp-schema lint "$REPO/schema/" || fail=1

echo
echo "== self-describing checkout responses =="
for f in "$REPO"/examples/res/checkout-session-created.json \
         "$REPO"/examples/res/checkout-complete-success.json; do
  ucp-schema validate "$f" --op read \
    --schema-local-base "$LB" --schema-remote-base "$REMOTE" || fail=1
done

echo
echo "== error message bodies (messages[0] vs message_error) =="
for f in "$REPO"/examples/res/checkout-complete-payment-expired.json \
         "$REPO"/examples/res/checkout-complete-asset-unavailable.json; do
  tmp="$(mktemp)"
  python3 -c "import json,sys; d=json.load(open('$f')); json.dump(d['messages'][0], open('$tmp','w'))"
  ucp-schema validate "$tmp" --schema "$LB/schemas/common/types/message_error.json" \
    --response --op read || fail=1
  rm -f "$tmp"
done

echo
echo "== handler discovery entry (org.x402.payment vs payment_handler business_schema) =="
tmp="$(mktemp)"
python3 -c "import json; d=json.load(open('$REPO/examples/discovery.json')); json.dump(d['ucp']['payment_handlers']['org.x402.payment'][0], open('$tmp','w'))"
ucp-schema validate "$tmp" --schema "$LB/schemas/payment_handler.json" \
  --response --op read --def business_schema || fail=1
rm -f "$tmp"

echo
echo "== raw x402 PaymentRequired bodies (out of UCP-schema scope; JSON sanity only) =="
for f in "$REPO"/examples/res/payment-required-same-url.json \
         "$REPO"/examples/res/payment-required-external-url.json \
         "$REPO"/examples/res/payment-required-same-url-neox.json; do
  python3 -m json.tool "$f" >/dev/null && echo "  $(basename "$f"): JSON OK" || fail=1
done

echo
if [ "$fail" -ne 0 ]; then
  echo "RESULT: FAIL"
  exit 1
fi
echo "RESULT: PASS"
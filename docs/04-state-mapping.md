# State Mapping: UCP Checkout Session States vs x402 Settlement (B5)

Status: pre-draft.

## 1. The two state machines

UCP checkout session lifecycle: `incomplete` -> `ready_for_complete` (all info present, PRE-completion) -> `complete_in_progress` -> `completed`; `payment_failed` on failure. A `payment_required` condition is reserved at submission.

x402 settlement lifecycle: challenge issued -> signature submitted -> facilitator verifies (amount, payTo, validity window, nonce) -> on-chain settlement -> receipt.

The binding must map one onto the other without inventing new UCP states.

## 2. Proposed mapping

| Event in the x402 flow | UCP session state | Notes |
|---|---|---|
| Agent submits `complete` without payment | stays `ready_for_complete` | 402 response, no state change |
| Agent submits `complete` with PAYMENT-SIGNATURE | `complete_in_progress` | Signature received, verification underway |
| Facilitator verifies + settles on-chain | `completed` | Order webhooks fire as usual |
| Verification fails (bad sig, expired, wrong payTo) | `payment_failed` | Error envelope: `ucp.status: "error"`, severity `recoverable` |
| Settlement submitted but unconfirmed | `complete_in_progress` (hold) | See timeout policy below |
| Settlement reorged/finality not reached | `complete_in_progress` (hold) | Policy: hold, do not fail, until timeout |

## 3. Timeout vs pending policy

The dangerous window is "signature accepted, on-chain settlement not yet final". Rules:

1. **Never auto-fail a session while a settlement is in flight.** A `payment_failed` that later conflicts with an on-chain transfer is the worst outcome (double-pay risk if the agent retries elsewhere).
2. **Merchant MUST expose the session state on `GET /checkout-sessions/{id}`** so a polling agent can distinguish "processing" from "failed".
3. **Default hold timeout: `maxTimeoutSeconds` + 120s.** After that, the merchant either marks `payment_failed` (with evidence the settlement cannot land: expired validity, reverted tx) or reconciles manually. Manual reconciliation path is facilitator-specific and out of scope for the binding.
4. **Idempotent retry:** the payment-identifier extension (session id) guarantees a retried `complete` with the same signature hits the same idempotency key. Duplicate submissions MUST NOT double-settle. This is B4 and it is what makes the whole state machine safe.

## 4. UCP error envelope

On `payment_failed`, the merchant returns the standard UCP error shape:

```json
{
  "ucp": {
    "status": "error",
    "messages": [
      {
        "code": "payment_failed",
        "severity": "recoverable",
        "message": "Payment signature rejected: offer expired"
      }
    ]
  }
}
```

`recoverable` for transient/retryable failures (expired offer: request a fresh challenge); `fatal` for terminal ones (asset not accepted). Retryable failures leave the session at `ready_for_complete` after a fresh challenge is issued.

## 5. Open questions

1. Should a `payment_failed` event also fire a UCP Order webhook, or is the checkout-session surface sufficient? (UCP order state vs checkout session state split needs a careful read of the Order capability spec.)
2. Is `complete_in_progress` legitimately observable by the agent via GET, or does the spec treat it as a server-internal transition? To be confirmed against UCP spec text before this doc goes normative.
3. Exact retry semantics when the agent signs a NEW offer after an expiry: new payment-identifier value (fresh session) vs same session id re-used with a new signature. Leaning: same session id, the identifier is session-scoped, the signature is per-offer.

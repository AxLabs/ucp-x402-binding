# State Mapping: UCP Checkout Session States vs x402 Settlement (B5)

Status: pre-draft.

## 1. The two state machines

UCP checkout session lifecycle: `incomplete` -> `ready_for_complete` (all info present, PRE-completion) -> `complete_in_progress` -> `completed`; `payment_failed` on failure. A `payment_required` condition is reserved at submission.

x402 settlement lifecycle: challenge issued -> signature submitted -> facilitator verifies (amount, payTo, validity window, nonce) -> on-chain settlement -> receipt.

The binding must map one onto the other without inventing new UCP states.

## 2. Normative mapping (UCP 2026-04-08 status enum)

UCP 2026-04-08 defines exactly six checkout statuses: `incomplete`, `requires_escalation`, `ready_for_complete`, `complete_in_progress`, `completed`, `canceled`. The binding maps x402 events onto them:

| Event in the x402 flow | UCP session state | Notes |
|---|---|---|
| Agent submits `complete` without payment | stays `ready_for_complete` | 402 response, no state change. Not an error status, not `complete_in_progress`. |
| Agent submits `complete` selecting an instrument (no signature) | stays `ready_for_complete` | New 402 for the selected asset; instrument marked `selected: true` in the session offer |
| Agent requests a network/asset outside the session offer | stays `ready_for_complete` | Recoverable error `payment_method_not_available` naming the available pairs; never a silent substitute |
| Agent submits `complete` with PAYMENT-SIGNATURE | **Ideal:** `complete_in_progress`; **Adapter:** treated as reconcile (§02 3.1.6) | Ideal: signature received, verification underway. Adapter: the merchant MUST NOT replay the signature to `resource.url`; it polls settlement / consumes the upstream fulfill, then transitions as below |
| Merchant finishes verify+settle synchronously inside the complete call | `completed` (no `complete_in_progress` observable) | If verify+settle completes within the complete HTTP call, the merchant MAY skip the in-progress state entirely; the agent then only ever sees 402 or `completed` |
| **Adapter: agent pays `resource.url` directly (outside UCP)** | no status change | Out-of-protocol settlement. UCP observes only the consequence: the following `complete` finds the settlement and transitions |
| **Adapter: agent POSTs `complete` again after paying** | `completed` if settlement observed, else `complete_in_progress` or stays `ready_for_complete` | Reconcile call (empty body or same instrument selection). Merchant polls settlement state; `payment_failed` stays a recoverable message while settlement may still land |
| Facilitator verifies + settles on-chain | `completed` | Order webhooks fire as usual |
| Verification fails (bad sig, expired, wrong payTo) | stays `ready_for_complete` + recoverable `payment_failed` message | See error envelope below; agent requests a fresh challenge |
| Settlement submitted but unconfirmed | `complete_in_progress` (hold) | See timeout policy below; if settlement is async, GET MUST be able to show `complete_in_progress` |
| Settlement reorged/finality not reached | `complete_in_progress` (hold) | Policy: hold, do not fail, until timeout |
| Session invalid or expired | `canceled` | Terminal; agent starts a new session |
| Buyer input needed (e.g. cannot be provided via API) | `requires_escalation` | UCP status, not a message code: businesses MUST provide `continue_url` with this status |

Rules:

- A 402 or instrument switch is **never** a session status change. The session stays `ready_for_complete` throughout the challenge/selection loop.
- `payment_failed` is a **message code** (in `messages[]`), paired with `ucp.status: "error"` in the envelope, while the session itself remains `ready_for_complete` (recoverable) or moves to `canceled` (terminal). It is not a session status.
- `requires_escalation` is a **status** in UCP 2026-04-08. A message code alone is not a substitute. (Merchants that currently signal escalation via message while staying `incomplete` are non-conformant and should migrate; this binding follows the status enum.)
- Never mark `payment_failed`/`canceled` as terminal while a settlement may still land (see timeout policy).

## 3. Timeout vs pending policy

The dangerous window is "signature accepted, on-chain settlement not yet final". Rules:

1. **Never auto-fail a session while a settlement is in flight.** A `payment_failed` that later conflicts with an on-chain transfer is the worst outcome (double-pay risk if the agent retries elsewhere).
2. **Merchant MUST expose the session state on `GET /checkout-sessions/{id}`** so a polling agent can distinguish "processing" from "failed".
3. **Default hold timeout: `maxTimeoutSeconds` + 120s.** After that, the merchant either marks `payment_failed` (with evidence the settlement cannot land: expired validity, reverted tx) or reconciles manually. Manual reconciliation path is facilitator-specific and out of scope for the binding.
4. **Idempotent retry:** the payment-identifier extension guarantees a retried `complete` with the same signature hits the same idempotency key. In x402 v2 the identifier is **client-supplied**: the merchant advertises `required` in the challenge; the agent generates the id (UUID-v4-with-prefix recommended) and echoes it in `PaymentPayload.extensions`. Duplicate submissions MUST NOT double-settle. This is B4 and it is what makes the whole state machine safe.

## 4. UCP error envelope

On payment failure, the merchant returns the standard UCP error shape (message field is `content`, per UCP 2026-04-08):

```json
{
  "ucp": {
    "version": "2026-04-08",
    "status": "error"
  },
  "messages": [
    {
      "type": "error",
      "code": "payment_failed",
      "severity": "recoverable",
      "content": "Payment signature rejected: offer expired"
    }
  ]
}
```

`recoverable` for transient/retryable failures (expired offer: request a fresh challenge); `unrecoverable` for terminal ones (asset not accepted). Retryable failures leave the session at `ready_for_complete` after a fresh challenge is issued. UCP severity values are `recoverable`, `requires_buyer_input`, `requires_buyer_review`, `unrecoverable`; this binding does not use `requires_*` severities (escalation is the `requires_escalation` **status**).

## 5. Open questions

1. ~~Should a `payment_failed` event also fire a UCP Order webhook, or is the checkout-session surface sufficient?~~ **RESOLVED (2026-08-24)**: the checkout-session surface is sufficient for v1. Order webhooks follow the Order capability and fire only for placed orders (`completed`), not for payment events on a session still at `ready_for_complete`.
2. ~~Is `complete_in_progress` legitimately observable by the agent via GET, or does the spec treat it as a server-internal transition?~~ **RESOLVED (2026-08-24)**: both are legal. Synchronous merchants MAY finish verify+settle inside the complete call and never expose `complete_in_progress`; async merchants MUST expose it via GET. Verified against UCP 2026-04-08: `complete_in_progress` is a first-class status in the enum ("Business is processing the Complete Checkout request").
3. Exact retry semantics when the agent signs a NEW offer after an expiry: new payment-identifier value (fresh session) vs same session id re-used with a new signature. Leaning: same session id, the identifier is session-scoped, the signature is per-offer.

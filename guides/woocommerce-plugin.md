# WooCommerce Plugin Implementation Guide

Audience: implementers (human or agent) working on `AxLabs/ax402-woocommerce-extension`.
Spec baseline: this repo at commit `d24848c` (rounds 6 and 7). Read [../spec/02-payment-flows.md](../spec/02-payment-flows.md) §3 and §3.1 before touching code.

## 1. Context: what happened and why the spec changed

WooCommerce order #141 was marked paid with no settlement and no USDC received. Root cause: the plugin's complete handler received the agent's `complete` retry carrying `PAYMENT-SIGNATURE` and forwarded that signature server-side to the Monetization Gateway and treated the gateway's HTTP response as proof of payment. The gateway never settled anything, but the order was marked paid.

The binding's old rule (pre-round-6 §3.1.4) mandated exactly that hop: "retry shop complete with the signature". With the gateway binding resources to its own endpoints, that rule had no safe implementation. Round 6 (`61be129`) replaced it with the direct-pay rule and the no-impersonation principle. Round 7 (`d24848c`) aligned everything to UCP 2026-08-25.

## 2. What the binding says (the rules you implement)

From [../spec/02-payment-flows.md](../spec/02-payment-flows.md) §3.1:

1. The x402 challenge is always issued on the shop's `POST /checkout-sessions/{id}/complete`. Never on MCP JSON-RPC, never on any other URL.
2. Same-URL Payment path: the challenge's signed `resource.url` equals the complete URL. The agent retries complete with the signature; the merchant verifies and settles.
3. External-URL Payment path: the signed `resource.url` MAY be the gateway/facilitator URL. It appears ONLY inside the signed 402 challenge (REST body/header, or MCP `structuredContent`), never in any UCP JSON body.
4. Resource derivation rule: if `resource.url` equals the complete URL, take the Same-URL path. If it differs, the agent pays `resource.url` directly with standard x402 v2, using the HTTP method named in the challenge (`extensions.bazaar.info.input.method`, else the method that received the 402), then POSTs shop complete again to reconcile.
5. Merchant no-impersonation rule: the shop MUST NOT make any server-side request to `resource.url` carrying the buyer's `PAYMENT-SIGNATURE`. No proxying, no replay, no "helpful" forwarding. This is the #141 fix, in one sentence.
6. Forward compatibility: when `complete` arrives with a `PAYMENT-SIGNATURE` (an agent assuming the Same-URL path), treat it as a reconcile request: check settlement state for the session, never replay the signature anywhere.

Round 7 additions that touch you:

- `complete` is an idempotent operation: each distinct complete attempt carries a fresh `Idempotency-Key`; duplicates of the same attempt return the same state without side effects. On MCP, `complete_checkout` requires `meta["idempotency-key"]`.
- Checkout responses may now carry `actions[]` and `policies[]` (UCP 2026-08-25). Tolerate them; never reject a response for having them.
- The binding defines an advisory Action `org.x402.payment.challenge` whose `config.instructions` is text telling the agent to POST the session's complete URL to get the 402 challenge. Text only: no gateway URLs, no amounts, no addresses in any action config. Agents that ignore it must still be able to pay.
- Handler discovery advertises `schema: https://x402.org/schemas/ucp-payment-handler.json` and version `2026-08-25`.

## 3. Plugin work items

Ordered by dependency, not priority. Items A and B are the incident fix; C is spec conformance; D and E are small wins.

**A. Delete the signature-forwarding path (class-ucp-complete.php).** Remove the code path that takes `PAYMENT-SIGNATURE` from the complete request and issues `wp_remote_get`/`wp_remote_post` to the gateway with it (the `submit_payment` forward). Add a regression test that a signature-bearing complete never produces an outbound request to the gateway carrying that signature.

**B. Replace it with settlement reconciliation.** When `complete` arrives and no settlement is recorded for the session: query the Monetization Gateway Provider's settlement state for the session's quote (poll per the provider contract, [../spec/04-gateway-provider-contract.md](../spec/04-gateway-provider-contract.md) §3.6). Mark the order paid ONLY on a settlement that matches the session (payer is free, but amount, asset, network, and `payTo` must match the challenge the session issued). While pending, respond `complete_in_progress`. On confirmed settlement, respond `completed` and set the order state. If the gateway reports no payment and no in-flight transaction, re-issue the 402 challenge (the agent may have paid the wrong resource; the challenge tells it where to pay).

**C. Idempotency on complete.** Accept `Idempotency-Key` on complete: same key returns the recorded state, no new settlement effects. Different key on a session already past `ready_for_complete` is a new attempt: allowed, must not double-settle. For the MCP surface, require `meta["idempotency-key"]` on `complete_checkout` and reject with a UCP error message when absent.

**D. 402 body for UCP-native agents.** The 402 on complete should carry a UCP error message with code `payment_required` (severity per the UCP error message shape) alongside the x402 challenge, so UCP-only agents get an in-protocol explanation. The x402 challenge stays authoritative for payment coordinates.

**E. Optional: emit the advisory Action.** On sessions in a pre-paid state you MAY attach `actions: [{type: "org.x402.payment.challenge", config: {instructions: "<text>"}}]` with instructions like: "POST this session's complete URL to receive the x402 v2 payment challenge. The signed challenge names the payment resource, accepted assets, and HTTP method. Pay the resource it names, then POST complete again." Strictly text. Zero payment data. Removing the action must never break payment.

**F. Discovery and version strings.** Point the handler `schema` at `https://x402.org/schemas/ucp-payment-handler.json` (placeholder until the canonical file is hosted; the GitHub blob will fail UCP 2026-08-25 authority binding). Bump profile/spec version strings to `2026-08-25`.

## 4. Acceptance criteria

1. External-URL flow end-to-end: agent completes without payment, receives 402 challenge with gateway `resource.url` and `bazaar input.method: GET`; pays the gateway directly; re-POSTs complete; plugin confirms settlement; order paid exactly once, only after settlement.
2. #141 regression: a `complete` retry bearing `PAYMENT-SIGNATURE` produces zero outbound gateway requests carrying that signature; the order is marked paid only if reconciliation finds a real settlement.
3. Old-agent compat: signature-on-complete with no settlement behind it does NOT mark the order paid; the plugin either reconciles or re-issues the 402.
4. Idempotency: same-key duplicate completes return the same state; two different keys cannot produce two paid transitions for one session.
5. MCP: `complete_checkout` without `meta["idempotency-key"]` errors cleanly.
6. Tolerance: checkout responses carrying `actions`/`policies` pass through the plugin's response handling without validation errors.

## 5. Out of scope

- Changing the Same-URL flow (when the provider binds resources to complete URLs, everything above collapses to: verify signature, settle, done).
- Putting gateway URLs in any UCP JSON body, discovery advertisement, action config, or webhook payload.
- Asset allow-lists, FX rate logic, receipt verification beyond the settlement match in B (all settled in the binding already).

## 6. References

- [../spec/02-payment-flows.md](../spec/02-payment-flows.md) §3, §3.1 (paths), §3.2 (derivation rule), §3.3 (merchant rules), §3.4 (UCP 2026-08-25 alignment)
- [../spec/04-gateway-provider-contract.md](../spec/04-gateway-provider-contract.md) (settlement state exposure, §3.6)
- [../examples/checkout-flow.md](../examples/checkout-flow.md) §6a (External-URL trace), `../examples/res/payment-required-external-url.json` (real wire shape, `bazaar` method included)
- Commits: `61be129` (direct-pay rule), `d24848c` (UCP 2026-08-25 alignment, Action type)

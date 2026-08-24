# Wire Binding: UCP Checkout <-> x402 v2 HTTP (B3/B4)

Status: pre-draft. Wire formats below are verified against UCP `docs/specification/*.md` and x402 `specs/transports-v2/http.md`, `specs/extensions/extension-offer-and-receipt.md`, `specs/extensions/payment_identifier.md` (see `00-prior-art.md` for exact sources).

## 1. Where the 402 sits

UCP's checkout flow ends with `POST /checkout-sessions/{id}/complete`. That is the natural seam for x402: the merchant has a final total, the agent has a session, and UCP already reserves a `payment_required` condition at submission.

Binding: **when an agent POSTs `complete` without a valid payment, the merchant responds `402` with the x402 v2 challenge. When the agent retries `complete` carrying the payment signature, settlement and completion happen together.**

```
Agent                                     Merchant (UCP server)
  |                                            |
  | GET /.well-known/ucp                        |
  |  (sees org.x402.payment handler:           |
  |   capability networks + assets)            |
  |<-------------------------------------------|
  |                                            |
  | POST /carts ... (build cart)               |
  | POST /checkout-sessions                    |
  |<-- session, total, ready_for_complete,     |
  |    payment.instruments[] (session offer)   |
  |                                            |
  | POST /checkout-sessions/{id}/complete      |
  |   (no payment attached)                    |
  |<-- 402 + PAYMENT-REQUIRED header           |
  |    (accepts[] = challenge for the          |
  |     selected/default asset)                |
  |                                            |
  | [agent verifies signed offer for the       |
  |    accepts[] entry it will pay, signs      |
  |    the scheme authorization]               |
  |                                            |
  | POST /checkout-sessions/{id}/complete      |
  |   PAYMENT-SIGNATURE header                 |
  |<-- 200: session completed + receipt        |
  |    (PAYMENT-RESPONSE, signed receipt)      |
```

## 2. Three layers of asset information (normative)

Agents and implementers keep collapsing three distinct lists. This binding names them and constrains their relationship:

| Layer | Where | Meaning |
|---|---|---|
| **Capability** | Discovery: handler `x402.networks` / `x402.assets` | Assets the merchant **may** settle, store-wide. Not a quote. MAY include assets that are not quotable on a given checkout (FX source down, chain paused, per-checkout policy). |
| **Session offer** | Checkout session `payment.instruments[]` (present when `ready_for_complete`) | Assets the merchant **can quote for this session**, with per-asset settlement prepared. Subset of capability. |
| **Challenge** | x402 `PaymentRequired.accepts[]` in the 402 (or MCP `payment_required` block) | Options valid for **this** `resource` only, with amounts. Subset of the session offer. |

Normative rules:

1. **Discovery MUST NOT be treated as the 402 catalog.** It is capability advertisement, not a quote.
2. **Containment: challenge ⊆ session offer ⊆ capability.** Every entry in `PaymentRequired.accepts[]` MUST be payable to **that** `resource`. If the merchant cannot settle asset B on the same resource as asset A, it MUST NOT list B in A's challenge. Whether a merchant serves all session assets from one x402 resource or one resource per asset is facilitator-side architecture and is not specified here.
3. **Selection is how the agent moves between assets.** If the handler supports more than one settlement asset, `complete` MUST allow the buyer to select the asset via handler-specific fields on the UCP instrument (`network` + `asset`; `payment_instrument` has `additionalProperties: true`). The next 402 MUST be the challenge for that selection.
4. **No preference means default.** If the agent sends no asset preference, the merchant MAY challenge a default instrument. The session response (and the 402's UCP body, when present) SHOULD still list all session instruments so the agent can retry `complete` with a different selection.
5. **Unknown pair is an error, not a silent substitute.** If the agent requests a `network` + `asset` (or instrument `id`) not in the session offer, the merchant MUST return a recoverable UCP error (`payment_method_not_available`, see `04-state-mapping.md`) naming the available pairs. The merchant MUST NOT 402 a different asset silently.
6. **Unquotable assets are omitted from the session offer**, not advertised as payable in a challenge.

These rules cover both facilitator architectures without describing either: one x402 resource with many `accepts[]` entries, or one resource per asset. In the second case the challenges for different selections are simply different `PaymentRequired` payloads for the same UCP complete URL; the agent never needs to know which architecture it is talking to.

## 3. The 402 challenge at `complete` (x402 v2 wire)

x402 v2 carries everything in headers. The binding at the `complete` seam:

```
HTTP/1.1 402 Payment Required
PAYMENT-REQUIRED: <base64 PaymentRequired JSON>
```

`PaymentRequired` payload (x402 v2 shape, single-asset example; see `payment-required-neox.json` for the same session challenged in a different asset):

```json
{
  "x402Version": 2,
  "error": "X402_PAYMENT_REQUIRED",
  "resource": {
    "url": "https://shop.example/checkout-sessions/chk_123/complete",
    "description": "Order for checkout session chk_123",
    "mimeType": "application/json"
  },
  "accepts": [
    {
      "scheme": "exact",
      "network": "eip155:8453",
      "asset": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
      "payTo": "0x209693Bc6afc0C5328bA36FaF03C514EF312287C",
      "amount": "135500000",
      "maxTimeoutSeconds": 600,
      "extra": {
        "name": "USDC",
        "version": "2"
      }
    }
  ],
  "extensions": {
    "offer-receipt": {
      "info": {
        "offers": [
          {
            "format": "eip712",
            "acceptIndex": 0,
            "payload": {
              "version": 1,
              "resourceUrl": "https://shop.example/checkout-sessions/chk_123/complete",
              "scheme": "exact",
              "network": "eip155:8453",
              "asset": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
              "payTo": "0x209693Bc6afc0C5328bA36FaF03C514EF312287C",
              "amount": "135500000",
              "validUntil": 1786233600
            },
            "signature": "0x... merchant EIP-712 signature over the offer payload ..."
          }
        ]
      }
    },
    "payment-identifier": {
      "info": {
        "required": false
      }
    }
  }
}
```

Key points:

- `resource.url` **MUST be the UCP checkout `complete` URL** (the resource the agent is paying for). The agent retries **that** URL with `PAYMENT-SIGNATURE`. Agents MUST NOT treat any facilitator/gateway URL appearing inside signed payloads as the retry URL.

### 3.1 Adapter period (time-boxed, normative)

The ideal above assumes the facilitator can verify payments whose signed `resource` is the shop complete URL. Not every facilitator can today. This subsection documents the transition, so agents behave correctly in both eras and merchants know when the adapter ends.

1. **HTTP 402 location (stable, both eras):** the 402 challenge is always issued on the shop `POST …/checkout-sessions/{id}/complete`. The agent retries **that** URL. The agent MUST NOT treat the MCP JSON-RPC endpoint as the x402 resource.
2. **Signed `resource` (ideal, end state):** the signed `resourceUrl` inside the offer MUST be the same complete URL. This is the binding's end state and becomes strictly REQUIRED once facilitators can verify shop-bound payments.
3. **Signed `resource` (adapter, current practice):** during the adapter period, the signed `resourceUrl` inside `PAYMENT-REQUIRED` MAY be the facilitator/gateway URL, because the facilitator's verify pipeline binds to the gateway resource. UCP JSON bodies (discovery, catalog, session, complete responses) MUST NOT expose gateway hosts: the leak is confined to the signed challenge (REST header and/or its MCP mirror). Non-UCP direct-to-facilitator flows are unaffected.
4. **Agent rule (both eras):** pay the shop complete URL. Do not POST `payment_required.resource.url` unless you are talking to the facilitator directly outside UCP.
5. **Exit criterion:** the adapter clause ends for a facilitator when it can `/verify` and `/settle` a payment whose `resource` is the shop complete URL. The binding itself does not sunset; merchants SHOULD migrate as their facilitator qualifies.

Containment rules (Section 2) are unaffected: an `accepts[]` entry for a network/asset the resource cannot settle is forbidden in both eras.
- Each `accepts[]` entry carries `amount` = the session's final total converted to that asset, in base units. Fiat total 135.50 USD -> `135500000` (USDC, 6 decimals). See `03-amount-semantics.md`.
- The **signed offer** (offer-receipt extension, one per `accepts[]` entry, `acceptIndex` links them) is the price lock: the merchant commits to `amount` + `payTo` + `validUntil` for `resourceUrl` before the agent signs the irreversible scheme authorization. Offers are matched to `accepts[]` by payload fields (`network`, `asset`, `payTo`, `amount`), never by array index alone. Signer authorization per the extension spec (simplest: the `payTo` key signs).
- `validUntil` is a Unix timestamp (seconds). It SHOULD agree with `maxTimeoutSeconds` and the handler's `quote_window`.
- The **payment-identifier** extension is client-supplied idempotency: the server advertises `required` (default `false`); when used, the **agent** generates the id (UUID-v4-with-prefix recommended) and echoes it in `PaymentPayload.extensions`. The UCP session id is a natural id source. This gives duplicate-submission protection at both resource server and facilitator (B4).
- `challenge ⊆ session offer`: every `accepts[]` entry MUST also appear (same `network` + `asset`) in the session's `payment.instruments[]`.

## 4. The payment retry

The retry carries both the UCP payment selection and the x402 signature. The UCP body selects the instrument; the header carries the x402 payment:

```
POST /checkout-sessions/chk_123/complete HTTP/1.1
Host: shop.example
UCP-Agent: profile="https://agent.example/profile"
Content-Type: application/json
PAYMENT-SIGNATURE: <base64 PaymentPayload JSON>

{
  "payment": {
    "instruments": [
      {
        "id": "instr_x402_1",
        "handler_id": "org.x402.payment",
        "type": "x402",
        "selected": true,
        "network": "eip155:8453",
        "asset": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
      }
    ]
  }
}
```

Instrument selection fields (handler-specific, legal via `additionalProperties: true` on the UCP payment instrument):

- `network`: CAIP-2 chain id, MUST match discovery notation.
- `asset`: asset identifier in the notation of its network (per-network schema, see handler spec).
- Matching is by instrument `id` (merchant-assigned, opaque) OR by (`network` + `asset`). If both are sent and disagree, the merchant returns a validation error.
- When `PAYMENT-SIGNATURE` is present, the selection MUST identify the asset the signature pays for (the `accepts[]` entry chosen), so the merchant routes verification correctly.

Notes on the two payment structures in UCP (they serve different purposes, both are standard):

- `ucp.payment_handlers` (response envelope) is the **runtime handler configuration**: what the merchant/platform can accept for THIS session, resolved per checkout. The response_schema handler variant per the UCP payment-handler guide. For this binding the runtime entry carries `id`, `version`, `available_instruments: [{"type": "x402"}]`.
- `payment.instruments` (top level, request and response) serves two roles in this binding: on a **ready session** it is the **session offer** (all quotable assets, `selected: true` on at most one); at **complete** it is the buyer's selection.

The merchant (via its facilitator, merchant-side) verifies the signature against the challenge it issued, settles on-chain, and responds:

```
HTTP/1.1 200 OK
PAYMENT-RESPONSE: <base64 SettlementResponse JSON>
```

`PAYMENT-RESPONSE` (SettlementResponse, x402 v2 shape) including the signed receipt:

```json
{
  "success": true,
  "transaction": "0x1234...abcdef",
  "network": "eip155:8453",
  "payer": "0x857b06519E91e3A54538791bDbb0E22373e36b66",
  "extensions": {
    "offer-receipt": {
      "info": {
        "receipt": {
          "format": "eip712",
          "payload": {
            "version": 1,
            "network": "eip155:8453",
            "resourceUrl": "https://shop.example/checkout-sessions/chk_123/complete",
            "payer": "0x857b06519E91e3A54538791bDbb0E22373e36b66",
            "issuedAt": 1786233300,
            "transaction": "0x1234...abcdef"
          },
          "signature": "0x... merchant signature over the receipt payload ..."
        }
      }
    }
  }
}
```

## 5. Agent algorithm (non-normative guidance)

1. Discover: read the handler's `x402.networks` / `x402.assets` (capability). If none overlap the wallet's holdings, stop: cannot pay here.
2. Build the checkout (cart, session) until `ready_for_complete`.
3. Read the **session** `payment.instruments[]`, not discovery, for this order's payable set.
4. If the buyer wants a specific asset, `complete` with that instrument selected (`network` + `asset`, or its `id`).
5. Otherwise `complete` with no preference: the merchant challenges a default asset.
6. Pay an entry from **this** challenge's `accepts[]` only. To switch assets, re-`complete` with a different instrument selection (a new challenge is issued); do not mix assets across challenges.
7. Retry the **checkout complete URL** with `PAYMENT-SIGNATURE` (plus the same instrument selection).

Skipping steps 3-6 against any multi-asset merchant produces wrong-asset payments; the containment rules exist to prevent exactly that.

## 6. MCP transport parity (B3b)

UCP also runs over MCP (tools/call with `create_cart`, `complete_checkout`). x402 v2 defines its own MCP transport; this binding adopts its keys verbatim so x402-native tooling interoperates without translation:

**Challenge (no signature), tool result:**

- HTTP stays 200 for JSON-RPC (the 402 semantic lives in the payload, not the transport status).
- `result.structuredContent` = the decoded `PaymentRequired` object, same object as REST's `PAYMENT-REQUIRED` header (this is the x402-standard, REQUIRED location).
- `result._meta["x402/payment-required"]` = the same object (MAY, redundant mirror for clients that only scan `_meta`).

**Retry:**

- `params._meta["x402/payment"]` = the `PaymentPayload` object (x402-standard).
- `params._meta["x402/payment-data"]` = MAY, auxiliary unsigned data.
- Instrument selection stays in the tool **arguments** (`payment.instruments[]`), field-for-field with the REST body.

**Settlement:**

- `result._meta["x402/payment-response"]` = the `SettlementResponse` object (x402-standard).

**Large signatures (Hedera and similar):** `PAYMENT-SIGNATURE` headers carrying JWS payloads can exceed ~8KB, beyond common proxy limits (`LimitRequestFieldSize`, ngrok, managed LBs). Merchants MUST accept the payment also as structured JSON in the request body, not only in the header: `payment.payment_signature` / `payment.payment_signature_data` inside the UCP checkout body (fields the UCP payment object tolerates via its open schema), or `params._meta["x402/payment"]` on MCP. Body/`_meta` payment is first-class, not a fallback hack: a complete payment flow MUST be possible without putting the signature in an HTTP header.

A2A parity follows the same rule via x402's A2A transport.

## 7. What this binding deliberately does NOT specify

- How many x402 resources a merchant serves (one with many `accepts[]`, or one per asset). Only the containment rule is normative.
- How the merchant picks the default asset when the agent sends no preference (local policy; the chosen default SHOULD be marked `selected: true` in the session offer).
- Facilitator internals: verification pipelines, settlement batching, gateway topology.
- What happens to assets with no resolvable rate at session time (they are simply absent from the session offer).
- Refunds/mandates/disputes in v1 (Layer 4).

## 8. Open questions

1. Does the `payment_required` condition UCP reserves at submission need a formal condition-type registration, or is the 402 response sufficient? To be raised with the UCP spec repo.
2. Should the session offer (instruments on a ready session) carry per-asset indicative amounts, or do amounts live exclusively in the challenge? Current rule: amounts live in the challenge + signed offer only; instruments carry `network` + `asset` (+ display fields). Revisit if agents demonstrably need pre-complete price comparison across assets.
3. ~~Multiple `offers[]` entries (multi-network): v1 allows one; multi-network selection is a v2 question.~~ **RESOLVED**: multi-asset selection is v1 (Section 2). The challenge MAY contain multiple `accepts[]` entries (all payable to its `resource`), and selection between challenge-exhausted assets happens by re-completing with a different instrument.

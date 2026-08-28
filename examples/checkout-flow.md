# End-to-End Checkout Flow: Wire Trace

Illustrative trace using the shapes from `02-wire-binding.md`. Addresses are placeholders. Amount: 135.50 USD total, USDC settlement (6 decimals).

Requests are shown inline. Responses live in separate JSON files under [`res/`](res/) and are linked at each step.

The three asset layers at a glance: discovery lists **capability**; the session lists the **session offer** (`payment.instruments[]`); each 402 lists the **challenge** (`accepts[]`, valid for its `resource` only). The agent selects by re-completing with an instrument; it never mixes assets across challenges.

## 1. Discovery

```
GET /.well-known/ucp HTTP/1.1
Host: shop.example
```

Response: [`discovery.json`](discovery.json). The agent sees `org.x402.payment`, checks `x402.networks` / `x402.assets` (capability) against its wallet. Decision: can pay here (wallet holds USDC on Base and Neo X). This is a capability check only: it is not a quote and not a per-checkout promise.

## 2. Cart and session

```
POST /carts HTTP/1.1
Host: shop.example
UCP-Agent: profile="https://agent.example/profile"
Content-Type: application/json

{ "items": [ { "product_id": "prod_451", "quantity": 2 } ] }
```

```
POST /checkout-sessions HTTP/1.1
Host: shop.example
UCP-Agent: profile="https://agent.example/profile"
Content-Type: application/json

{ "cart_id": "cart_789" }
```

Response: [`res/checkout-session-created.json`](res/checkout-session-created.json). Session `chk_123`, total `135.50 USD` (`totals[type=total].amount = 13550` minor units), status `ready_for_complete`. `payment.instruments[]` is the session offer: two x402 rows (Base USDC `selected: true`, Neo X USDC `selected: false`). The `payment` object is optional at creation per the UCP checkout spec; when present on a ready session it is the session offer.
> The session response may also carry the optional `actions` map from wire binding 3.2, pointing the agent at the x402 challenge for payment instructions.

## 3. Complete without payment: the 402

Default challenge (no asset preference sent):

```
POST /checkout-sessions/chk_123/complete HTTP/1.1
Host: shop.example
UCP-Agent: profile="https://agent.example/profile"
Content-Type: application/json

{ "payment": { "instruments": [] } }
```

```
HTTP/1.1 402 Payment Required
PAYMENT-REQUIRED: eyJ4ND...fV19
```

Decoded `PaymentRequired` (default asset = Base USDC, the session's `selected` instrument): [`res/payment-required.json`](res/payment-required.json). One `accepts[]` entry for Base USDC, `amount` `135500000` base units, `resource.url` = this session's complete URL (ideal binding; see the adapter-period variant below), extensions carry the signed offer (price lock) and the payment-identifier advertisement.

Adapter period: while the facilitator verifies gateway-bound resources, the signed challenge MAY carry the gateway URL instead: [`res/payment-required-adapter-ax402.json`](res/payment-required-adapter-ax402.json). Then the derivation rule (§3.1.4) applies — see the adapter trace in §6a below. The ideal trace continues in §4.

## 4. Agent-side verification, then signature

Agent verifies, in order:

1. Offer signature is by the `payTo` key (or otherwise authorized for `resourceUrl` per the extension spec).
2. Offer `resourceUrl` matches the challenge's `resource.url` (ideal: the session's complete URL; adapter: the gateway URL). The offer and the challenge MUST agree.
3. `amount` is derivable from the session total (135.50 USD, USDC peg matches, 1:1 minor units -> `135500000`).
4. `validUntil` is in the future and inside its policy window.
5. The `accepts[]` entry it is paying matches the signed offer payload fields (`network`, `asset`, `payTo`, `amount`) - never index alone.

Then signs the scheme authorization (e.g. EIP-3009 `transferWithAuthorization` for `exact` on EVM) for `135500000` USDC to `payTo`.

## 5. Switching assets: re-complete with a different instrument

The agent's policy prefers Neo X (cheaper gas). It re-POSTs complete with the Neo X instrument selected:

```
POST /checkout-sessions/chk_123/complete HTTP/1.1
Host: shop.example
UCP-Agent: profile="https://agent.example/profile"
Content-Type: application/json

{
  "payment": {
    "instruments": [
      {
        "id": "instr_x402_2",
        "handler_id": "org.x402.payment",
        "type": "x402",
        "selected": true,
        "network": "eip155:47763",
        "asset": "0x4200000000000000000000000000000000000023"
      }
    ]
  }
}
```

```
HTTP/1.1 402 Payment Required
PAYMENT-REQUIRED: eyJ4ND...bXg0
```

Decoded challenge: [`res/payment-required-neox.json`](res/payment-required-neox.json). A **different** challenge: `accepts[]` now carries the Neo X pair, with a fresh signed offer for `eip155:47763`. Still POSTed to the **same** shop complete URL. If the agent had requested a pair outside the session offer, the merchant would answer [`res/checkout-complete-asset-unavailable.json`](res/checkout-complete-asset-unavailable.json) (recoverable error naming the available pairs), never a silent substitute.

## 6. Complete with payment

```
POST /checkout-sessions/chk_123/complete HTTP/1.1
Host: shop.example
UCP-Agent: profile="https://agent.example/profile"
Content-Type: application/json
PAYMENT-SIGNATURE: eyJ4ND...9fX0

{
  "payment": {
    "instruments": [
      {
        "id": "instr_x402_2",
        "handler_id": "org.x402.payment",
       "type": "x402",
        "selected": true,
        "network": "eip155:47763",
        "asset": "0x4200000000000000000000000000000000000023"
      }
    ]
  }
}
```

```
HTTP/1.1 200 OK
PAYMENT-RESPONSE: eyJzdW...uLn0
```

Response: [`res/checkout-complete-success.json`](res/checkout-complete-success.json). Session `completed`, order id `ord_99887766`. The selected `payment.instruments` entry carries the settlement facts (network, asset, tx hash) in `display`, and the signed x402 receipt in `x402_receipt` bound to the session's complete URL. Order webhooks fire.

## 6a. Adapter trace: direct gateway payment + reconcile

Same session as above, but the facilitator verifies gateway-bound resources. The derivation rule (§3.1.4) sends the agent down a different path after the same first three steps:

```
POST /checkout-sessions/chk_123/complete   (no payment)
<-- 402 + PAYMENT-REQUIRED: challenge whose resource.url =
     https://gateway.ax402.example/v1/pay/cm9yZGVyLTEyMw
     (differs from the complete URL -> adapter path)
     bazaar extension: input.method = GET
```

1. Agent verifies the signed offer exactly as §4 — except `resourceUrl` is the **gateway** URL, and it MUST match the challenge's `resource.url`.
2. Agent signs the scheme authorization and pays the gateway directly, with standard x402 v2:

```
GET https://gateway.ax402.example/v1/pay/cm9yZGVyLTEyMw
PAYMENT-SIGNATURE: eyJ4ND...  (method per bazaar input.method)
<-- 200 + PAYMENT-RESPONSE (settlement + signed receipt, resourceUrl = gateway)
```

3. Agent POSTs shop `complete` again — empty body or the same instrument selection, **no signature required**:

```
POST /checkout-sessions/chk_123/complete
{ "payment": { "instruments": [ ...same selection... ] } }
<-- 200 completed        (merchant reconciled settlement: order attached)
<-- 200 complete_in_progress   (settle still in flight: poll GET the session)
```

The merchant never touches the buyer's signature (§3.1.5 no-impersonation). It polls settlement state or consumes the upstream fulfill to decide `completed` vs `complete_in_progress` (§04). The order binding is the session id on the reconcile call, not the receipt URL.

## 7. Failure path (expired offer)

Agent was slow, offer expired, merchant rejects the signature:

Response: [`res/checkout-complete-payment-expired.json`](res/checkout-complete-payment-expired.json).

Session returns to `ready_for_complete`. Agent re-attempts `complete`, gets a fresh 402 with a new signed offer, re-verifies, re-signs. Same session id, new signature. No double-settle risk: the payment-identifier (client-supplied in `PaymentPayload.extensions`) makes retries idempotent.

## 8. MCP transport

Same flow over MCP (`tools/call` with `complete_checkout`): the challenge arrives as `result.structuredContent` (the decoded `PaymentRequired` object; x402-standard location, mirrored at `result._meta["x402/payment-required"]`), and the retry carries the `PaymentPayload` at `params._meta["x402/payment"]` plus the same instrument selection in the tool arguments. Field-for-field identical to HTTP; only the transport differs. Large signatures (Hedera JWS) MAY travel in the body (`payment.payment_signature`) instead of the header. In the adapter era the agent never pays the MCP endpoint: it pays the challenge's `resource.url` over HTTP, then calls `complete_checkout` again to reconcile (see §6a).

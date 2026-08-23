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

Decoded `PaymentRequired` (default asset = Base USDC, the session's `selected` instrument): [`res/payment-required.json`](res/payment-required.json). One `accepts[]` entry for Base USDC, `amount` `135500000` base units, `resource.url` = this session's complete URL, extensions carry the signed offer (price lock) and the payment-identifier advertisement.

## 4. Agent-side verification, then signature

Agent verifies, in order:

1. Offer signature is by the `payTo` key (or otherwise authorized for `resourceUrl` per the extension spec).
2. Offer `resourceUrl` is this session's complete URL.
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

## 7. Failure path (expired offer)

Agent was slow, offer expired, merchant rejects the signature:

Response: [`res/checkout-complete-payment-expired.json`](res/checkout-complete-payment-expired.json).

Session returns to `ready_for_complete`. Agent re-attempts `complete`, gets a fresh 402 with a new signed offer, re-verifies, re-signs. Same session id, new signature. No double-settle risk: the payment-identifier (client-supplied in `PaymentPayload.extensions`) makes retries idempotent.

## 8. MCP transport

Same flow over MCP (`tools/call` with `complete_checkout`): the 402 becomes a structured `payment_required` block in the tool result carrying the same `PaymentRequired` object (with `accepts[]` and extensions), and the retry carries the `PaymentPayload` as a structured argument plus the same instrument selection in the tool arguments. Field-for-field identical to HTTP; only the transport differs.

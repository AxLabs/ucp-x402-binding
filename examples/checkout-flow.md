# End-to-End Checkout Flow: Wire Trace

Illustrative trace using the shapes from `02-wire-binding.md`. Addresses are placeholders. Amount: 135.50 USD total, USDC on Base, 6 decimals.

Requests are shown inline. Responses live in separate JSON files under [`res/`](res/) and are linked at each step.

## 1. Discovery

```
GET /.well-known/ucp HTTP/1.1
Host: shop.example
```

Response: [`discovery.json`](discovery.json). The agent sees `org.x402.crypto`, checks `x402.networks` against its wallet's chain, checks `x402.assets` for something it holds (validating asset shapes against `x402.networkSchemas`). Decision: can pay here.

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

Response: [`res/checkout-session-created.json`](res/checkout-session-created.json). Session `chk_123`, total `135.50 USD` (`totals[type=total].amount = 13550` minor units), status `ready_for_complete`. The `ucp.payment_handlers` envelope carries the runtime `org.x402.crypto` entry with `available_instruments: [{"type": "x402"}]` for this session. (The `payment` object is optional at creation per the UCP checkout spec; the agent selects the instrument at complete.)

## 3. Complete without payment: the 402

```
POST /checkout-sessions/chk_123/complete HTTP/1.1
Host: shop.example
UCP-Agent: profile="https://agent.example/profile"
```

```
HTTP/1.1 402 Payment Required
PAYMENT-REQUIRED: eyJ2ZX...4ufQ
```

Decoded `PaymentRequired` payload: [`res/payment-required.json`](res/payment-required.json). Amount `135500000` base units, `payTo` `0xmerchant...`, `resource` bound to this session's URL, extensions carry the signed offer (price lock, `validUntil` +600s) and the payment-identifier `ucp:chk_123`.

## 4. Agent-side verification, then signature

Agent verifies, in order:

1. Offer signature is by the `payTo` key.
2. `resourceUrl` is this session.
3. `amount` is derivable from the session total (135.50 USD, USDC peg matches, 1:1 minor units -> `135500000`).
4. `validUntil` is in the future and inside its policy window.

Then signs EIP-3009 `transferWithAuthorization` for `135500000` USDC to `payTo`.

## 5. Complete with payment

```
POST /checkout-sessions/chk_123/complete HTTP/1.1
Host: shop.example
UCP-Agent: profile="https://agent.example/profile"
Content-Type: application/json
PAYMENT-SIGNATURE: eyJzY2...In19

{
  "payment": {
    "instruments": [
      {
        "id": "instr_x402_1",
        "handler_id": "org.x402.crypto",
        "type": "x402",
        "selected": true
      }
    ]
  }
}
```

```
HTTP/1.1 200 OK
PAYMENT-RESPONSE: eyJzdW...uLn0
```

Response: [`res/checkout-complete-success.json`](res/checkout-complete-success.json). Session `completed`, order id `ord_99887766`. The `payment.instruments` entry carries the settlement facts (network, asset, tx hash) in `display`, and the signed x402 receipt in `x402_receipt` bound to `https://shop.example/checkout-sessions/chk_123`. Order webhooks fire.

## 6. Failure path (expired offer)

Agent was slow, offer expired, merchant rejects the signature:

Response: [`res/checkout-complete-payment-expired.json`](res/checkout-complete-payment-expired.json).

Session returns to `ready_for_complete`. Agent re-attempts `complete`, gets a fresh 402 with a new signed offer, re-verifies, re-signs. Same session id, same payment-identifier, new signature. No double-settle risk: the identifier is idempotent at the facilitator.

## 7. MCP transport

Same flow over MCP (`tools/call` with `complete_checkout`): the 402 becomes a structured `payment_required` block in the tool result carrying the same `PaymentRequired` object (with extensions), and the retry carries the payment payload as a structured argument. Field-for-field identical to HTTP; only the transport differs.

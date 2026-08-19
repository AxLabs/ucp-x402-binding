# End-to-End Checkout Flow: Wire Trace

Illustrative trace using the shapes from `02-wire-binding.md`. Addresses are placeholders. Amount: 135.50 USD total, USDC on Base, 6 decimals.

## 1. Discovery

```
GET /.well-known/ucp HTTP/1.1
Host: shop.example
```

Response: see `discovery.json`. The agent sees `org.x402.crypto`, checks `x402.networks` against its wallet's chain, checks `x402.assets` for something it holds. Decision: can pay here.

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

{ "cart_id": "cart_789", "payment": { "handlers": ["org.x402.crypto"] } }
```

Response (abbreviated): session `chk_123`, total `135.50 USD`, state `ready_for_complete`.

## 3. Complete without payment: the 402

```
POST /checkout-sessions/chk_123/complete HTTP/1.1
Host: shop.example
UCP-Agent: profile="https://agent.example/profile"
```

```
HTTP/1.1 402 Payment Required
PAYMENT-REQUIRED: eyJ2ZXJzaW9uIjoiMiIsIm5ldHdvcmsiOiJlaXAxNTU6ODQ1MyIsLi4ufQ
```

Decoded `PaymentRequired` (see `02-wire-binding.md` section 2 for the full payload): amount `135500000`, payTo `0xmerchant...`, resource `https://shop.example/checkout-sessions/chk_123`, extensions carry the signed offer (price lock, `validUntil` +600s) and the payment-identifier `ucp:chk_123`.

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
PAYMENT-SIGNATURE: eyJzY2hlbWUiOiJleGFjdCIsInBheWxvYWQiOnsiLi4uIn19
```

```
HTTP/1.1 200 OK
PAYMENT-RESPONSE: eyJzdWNjZXNzIjp0cnVlLC4uLn0
```

Decoded `SettlementResponse`: `success: true`, tx hash, signed receipt bound to `https://shop.example/checkout-sessions/chk_123`. UCP session state: `completed`. Order webhooks fire.

## 6. Failure path (expired offer)

Agent was slow, offer expired, merchant rejects the signature:

```
HTTP/1.1 200 OK
Content-Type: application/json

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

Session returns to `ready_for_complete`. Agent re-attempts `complete`, gets a fresh 402 with a new signed offer, re-verifies, re-signs. Same session id, same payment-identifier, new signature. No double-settle risk: the identifier is idempotent at the facilitator.

## 7. MCP transport

Same flow over MCP (`tools/call` with `complete_checkout`): the 402 becomes a structured `payment_required` block in the tool result carrying the same `PaymentRequired` object (with extensions), and the retry carries the payment payload as a structured argument. Field-for-field identical to HTTP; only the transport differs.

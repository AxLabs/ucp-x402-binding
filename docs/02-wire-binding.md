# Wire Binding: UCP Checkout <-> x402 v2 HTTP (B3/B4)

Status: pre-draft. Wire formats below are verified against UCP `docs/specification/*.md` and x402 `specs/` (see `00-prior-art.md` for exact sources).

## 1. Where the 402 sits

UCP's checkout flow ends with `POST /checkout-sessions/{id}/complete`. That is the natural seam for x402: the merchant has a final total, the agent has a session, and UCP already reserves a `payment_required` condition at submission.

Binding: **when an agent POSTs `complete` without a valid payment, the merchant responds `402` with the x402 v2 challenge. When the agent retries `complete` carrying the payment signature, settlement and completion happen together.**

```
Agent                                     Merchant (UCP server)
  |                                            |
  | GET /.well-known/ucp                        |
  |  (sees org.x402.crypto handler)            |
  |<-------------------------------------------|
  |                                            |
  | POST /carts ... (build cart)               |
  | POST /checkout-sessions                    |
  |<-- session id, total, ready_for_complete   |
  |                                            |
  | POST /checkout-sessions/{id}/complete      |
  |   (no payment attached)                    |
  |<-- 402 + PAYMENT-REQUIRED header           |
  |    (amount = final total, base units)      |
  |    (extensions: offer-receipt,             |
  |     payment-identifier = session id)       |
  |                                            |
  | [agent verifies signed offer, signs        |
  |  EIP-3009 transferWithAuthorization]       |
  |                                            |
  | POST /checkout-sessions/{id}/complete      |
  |   PAYMENT-SIGNATURE header                 |
  |<-- 200: session completed + receipt        |
  |    (PAYMENT-RESPONSE, signed receipt)      |
```

## 2. The 402 challenge at `complete` (v2 headers)

x402 v2 carries everything in headers. The binding at the `complete` seam:

```
HTTP/1.1 402 Payment Required
PAYMENT-REQUIRED: <base64url PaymentRequired JSON>
```

`PaymentRequired` payload (x402 v2 shape):

```json
{
  "version": "2",
  "network": "eip155:8453",
  "asset": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
  "payTo": "0x merchant receiving address",
  "maxAmountRequired": "135500000",
  "resource": "https://shop.example/checkout-sessions/chk_123",
  "description": "Order for checkout session chk_123",
  "mimeType": "application/json",
  "maxTimeoutSeconds": 600,
  "extra": {
    "name": "USDC",
    "version": "2"
  },
  "extensions": {
    "offer-receipt": {
      "info": {
        "offers": [
          {
            "version": "1",
            "resourceUrl": "https://shop.example/checkout-sessions/chk_123",
            "scheme": "exact",
            "network": "eip155:8453",
            "asset": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
            "payTo": "0x merchant receiving address",
            "amount": "135500000",
            "validUntil": "2026-08-20T12:00:00Z"
          }
        ]
      },
      "signatures": ["0x... merchant EIP-712 signature over the offer ..."]
    },
    "payment-identifier": {
      "info": { "identifier": "ucp:chk_123" },
      "signatures": []
    }
  }
}
```

Key points:

- `resource` binds the payment to the checkout session URL. The settlement is for THIS session, not a generic charge.
- `maxAmountRequired` = the session's final total in base units. Fiat total 135.50 USD → `135500000` (USDC, 6 decimals). See `03-amount-semantics.md`.
- The **signed offer** (offer-receipt extension) is the price lock: the merchant commits to `amount` + `payTo` + `validUntil` for `resourceUrl` before the agent signs the irreversible EIP-3009 transfer. The agent verifies the merchant signature (simplest authorization: the `payTo` key signs) before signing.
- The **payment-identifier** extension carries the checkout session id (`ucp:chk_123`), giving idempotency and session binding in one rule (B4). UUID-v4-with-prefix recommended by the extension; UCP session ids qualify.
- `maxTimeoutSeconds` and the offer's `validUntil` should agree; both default to the handler's `quoteWindow`.

## 3. The payment retry

```
POST /checkout-sessions/chk_123/complete HTTP/1.1
Host: shop.example
UCP-Agent: profile="https://agent.example/profile"
PAYMENT-SIGNATURE: <base64url Payment payload>
```

The merchant (via its facilitator, merchant-side) verifies the signature against the challenge it issued, settles on-chain, and responds:

```
HTTP/1.1 200 OK
PAYMENT-RESPONSE: <base64url settlement payload>
```

`PAYMENT-RESPONSE` (SettlementResponse, x402 v2 shape) including the signed receipt:

```json
{
  "success": true,
  "network": "eip155:8453",
  "asset": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913",
  "payer": "0x agent wallet",
  "payTo": "0x merchant receiving address",
  "amount": "135500000",
  "transaction": "0x tx hash",
  "extensions": {
    "offer-receipt": {
      "info": {
        "receipt": {
          "version": "1",
          "network": "eip155:8453",
          "resourceUrl": "https://shop.example/checkout-sessions/chk_123",
          "payer": "0x agent wallet",
          "issuedAt": "2026-08-20T11:45:00Z",
          "transaction": "0x tx hash"
        }
      },
      "signatures": ["0x... merchant signature over the receipt ..."]
    }
  }
}
```

## 4. MCP transport parity (B3b)

UCP also runs over MCP (tools/call with `create_cart`, `complete_checkout`). x402 has its own MCP transport. Parity rule: **the challenge and payment are structured fields in the tool result, not HTTP headers.** When `complete_checkout` is called without payment, the tool result carries the same `PaymentRequired` object (with extensions) as a structured `payment_required` block; the agent re-calls `complete_checkout` with the payment payload as a structured argument. Field-for-field identical to the HTTP binding; transport is the only difference.

A2A parity follows the same rule via x402's A2A transport.

## 5. What this binding deliberately does NOT do

- No facilitator URL anywhere in the flow. The agent learns `payTo`, networks, assets, amount. Which facilitator verifies and settles is invisible merchant-side plumbing.
- No changes to UCP core schemas. The binding rides existing UCP extension points and x402 extensions.
- No refunds/mandates/disputes in v1 (Layer 4).

## 6. Open questions

1. Does the `payment_required` condition UCP reserves at submission need a formal condition-type registration, or is the 402 response sufficient? To be raised with the UCP spec repo.
2. Exact `resource` URL shape: absolute session URL vs session id only. Leaning absolute URL (matches offer-receipt `resourceUrl`).
3. Multiple `offers[]` entries (multi-network): v1 allows one; multi-network selection is a v2 question.

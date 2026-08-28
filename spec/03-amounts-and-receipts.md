# Amounts and Receipts

Status: pre-draft.

## 1. Amount semantics: fiat totals to base units

### 1.1 The problem

UCP checkout totals are fiat (USD, EUR, CHF). x402 amounts are integer base units of an on-chain asset. The mapping must be deterministic, auditable, and time-boxed, because the agent is about to sign an irreversible transfer.

fd.xyz/Prism solves this by making the gateway do the math ("Prism does all token/chain/x402 math, the plugin only relays"). That works for them because they own the gateway. A neutral spec needs normative rules anyone can implement.

### 1.2 Normative rules

1. **The quote is the challenge.** The amount the agent signs is exactly the amount in the 402 challenge, and the challenge embeds the signed offer (price lock). There is no second source of truth. If a merchant's session total and its challenge amount disagree, the agent aborts.
2. **USD-pegged assets map 1:1 from fiat minor units when the fiat currency matches the peg.** 135.50 USD -> `135500000` USDC (6 decimals). This is the common case and needs no oracle.
3. **Non-pegged or non-matching currencies require an explicit quoted rate inside the signed offer.** The offer payload gains an optional `quote` object: `{rate: "0.885", base: "USD", target: "USDC", capturedAt: "...", source: "..."}`. The rate is committed under the merchant's signature, so the agent can verify the math and hold the merchant to it. The **merchant owns the rate**: it fetches rates from an external provider, converts the checkout-currency total to the settlement-asset amount, and locks that amount plus the rate metadata in the signed offer. `capturedAt` (RFC 3339 timestamp of when the rate was fetched/established) is REQUIRED whenever `quote` is present, so the agent can judge rate staleness. v1 RECOMMENDED, likely v2 REQUIRED for non-pegged pairs.
4. **The quoted amount is for the selected asset.** A 402 for USDC (6 decimals) and a later 402 for XGAS (18 decimals) are different quotes for the same fiat total. Assets that cannot be quoted (no rate) are omitted from the session offer entirely; they are never advertised as payable in a challenge and never silently substituted. See [02-payment-flows.md](02-payment-flows.md) for the containment rules.
5. **`validUntil` is the quote window.** The offer expiry defines how long the total is locked. Default 600s. After expiry the merchant re-issues the challenge with a fresh offer; the agent re-verifies.
6. **Base units, never decimals.** `"135500000"`, not `"135.50"`. This is x402 core; repeating it because every fabricated example in the wild gets it wrong.
7. **Rounding: half-up to the smallest on-chain unit, rounding difference always favors the merchant ceiling but MUST NOT exceed 1 smallest unit.** (Open for discussion: favor-the-merchant vs favor-the-agent on the boundary unit. Current leaning: ceiling with a 1-unit cap, so the worst case for the agent is 1 wei-equivalent.)

### 1.3 Worked example

Checkout session `chk_123`, total 135.50 USD:

| Step | Value |
|---|---|
| Fiat total | 135.50 USD |
| Asset | USDC on `eip155:8453`, 6 decimals |
| Base units | 135.50 x 10^6 = `135500000` |
| Offer signed | amount `135500000`, validUntil +600s |
| Agent signs | EIP-3009 transfer of `135500000` USDC |
| Settlement | `135500000` on-chain, receipt returned |

Same session quoted in EUR (rate 1.0852 USD/EUR captured by the merchant):

| Step | Value |
|---|---|
| Fiat total | 135.50 EUR |
| USD equivalent | 147.04 USD (135.50 x 1.0852) |
| Base units | `147042000` (rounded half-up from 147.042) |

## 2. Receipts

### 2.1 Offer and receipt, from the x402 offer-and-receipt extension

The x402 offer-receipt extension defines two merchant-signed artifacts (EIP-712, chainId hardcoded to 1 since these are off-chain commitments, or JWS for non-EVM):

- **Signed offer**, delivered in the 402 challenge next to `accepts[]`/`PaymentRequired`: payload `{version, resourceUrl, scheme, network, asset, payTo, amount, validUntil?}`. Simplest signer authorization: the `payTo` key signs.
- **Signed receipt**, returned in the SettlementResponse extensions: payload `{version, network, resourceUrl, payer, issuedAt, transaction?}`. Deliberately privacy-minimal: no amount, no order id.

This binding uses both as specified, no changes:

1. The signed offer is the **price lock** at the 402-at-complete seam (see [02-payment-flows.md](02-payment-flows.md)). The agent verifies it before signing the irreversible EIP-3009 transfer.
2. The signed receipt is the **portable proof of purchase**: verifiable by anyone, usable as dispute evidence, input for reputation systems (the extension's stated use cases).
3. `resourceUrl` binds both artifacts to the UCP checkout session URL, making them order-scoped without any UCP schema change.

### 2.2 Why the receipt matters for UCP specifically

UCP's Order capability tells the agent what the merchant says about an order. The signed receipt is what the agent can **verify independently**: the merchant signed it, it references the session, the tx hash is on-chain. Two different trust anchors, one artifact.

### 2.3 The gap, and the follow-up proposal

The receipt payload has no amount and no order id. For UCP order flows, a buyer agent wants to prove "I paid 135.50 for order #1001", not just "I paid something at this URL". That is a small extension of the extension: add optional `amount` and `orderId` fields to the receipt payload.

Plan: ship v1 of the binding with the receipt as-is (privacy-minimal is a feature for some merchants), and submit the **receipt order-binding** as a follow-up proposal to the x402 Foundation (it is protocol-level, not UCP-level). v1 merchants MAY already include order metadata in the settlement response body; the signed receipt stays minimal.

## 3. Open questions

1. Does UCP expose the session's currency anywhere the agent must cross-check against the offer? (Session `total` fields are fiat; the binding should require the challenge amount to be derivable from the session total + offer quote.)
2. Oracle sourcing for the `quote.source` field: named public feeds vs merchant-discretionary string. v1: discretionary string, agent-side sanity checks are out of scope.
3. Whether the receipt should also carry the amount (currently it does not, by design). See §2.3 for the order-binding proposal that subsumes this.

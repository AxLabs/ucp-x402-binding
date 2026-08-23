# Amount Semantics: Fiat Totals to Base Units (B3a)

Status: pre-draft.

## 1. The problem

UCP checkout totals are fiat (USD, EUR, CHF). x402 amounts are integer base units of an on-chain asset. The mapping must be deterministic, auditable, and time-boxed, because the agent is about to sign an irreversible transfer.

fd.xyz/Prism solves this by making the gateway do the math ("Prism does all token/chain/x402 math, the plugin only relays"). That works for them because they own the gateway. A neutral spec needs normative rules anyone can implement.

## 2. Normative rules (proposed)

1. **The quote is the challenge.** The amount the agent signs is exactly the amount in the 402 challenge, and the challenge embeds the signed offer (price lock). There is no second source of truth. If a merchant's session total and its challenge amount disagree, the agent aborts.
2. **USD-pegged assets map 1:1 from fiat minor units when the fiat currency matches the peg.** 135.50 USD → `135500000` USDC (6 decimals). This is the common case and needs no oracle.
3. **Non-pegged or non-matching currencies require an explicit quoted rate inside the signed offer.** The offer payload gains an optional `quote` object: `{rate: "0.885", base: "USD", target: "USDC", capturedAt: "...", source: "..."}`. The rate is committed under the merchant's signature, so the agent can verify the math and hold the merchant to it. The **merchant owns the rate**: it fetches rates from an external provider, converts the checkout-currency total to the settlement-asset amount, and locks that amount plus the rate metadata in the signed offer. `capturedAt` (RFC 3339 timestamp of when the rate was fetched/established) is REQUIRED whenever `quote` is present, so the agent can judge rate staleness. v1 RECOMMENDED, likely v2 REQUIRED for non-pegged pairs.
4. **The quoted amount is for the selected asset.** A 402 for USDC (6 decimals) and a later 402 for XGAS (18 decimals) are different quotes for the same fiat total. Assets that cannot be quoted (no rate) are omitted from the session offer entirely; they are never advertised as payable in a challenge and never silently substituted. See `02-wire-binding.md` for the containment rules.
5. **`validUntil` is the quote window.** The offer expiry defines how long the total is locked. Default 600s. After expiry the merchant re-issues the challenge with a fresh offer; the agent re-verifies.
6. **Base units, never decimals.** `"135500000"`, not `"135.50"`. This is x402 core; repeating it because every fabricated example in the wild gets it wrong.
7. **Rounding: half-up to the smallest on-chain unit, rounding difference always favors the merchant ceiling but MUST NOT exceed 1 smallest unit.** (Open for discussion: favor-the-merchant vs favor-the-agent on the boundary unit. Current leaning: ceiling with a 1-unit cap, so the worst case for the agent is 1 wei-equivalent.)

## 3. Worked example

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

The rate lands inside the signed offer's `quote` object, so the arithmetic is verifiable end-to-end.

## 4. Open questions

1. Does UCP expose the session's currency anywhere the agent must cross-check against the offer? (Session `total` fields are fiat; the binding should require the challenge amount to be derivable from the session total + offer quote.)
2. Oracle sourcing for the `quote.source` field: named public feeds vs merchant-discretionary string. v1: discretionary string, agent-side sanity checks are out of scope.
3. Whether the receipt should also carry the amount (currently it does not, by design). See `06-receipts.md` for the order-binding proposal that subsumes this.

# Facilitator Contract (B6)

Status: pre-draft.

## 1. Facilitator neutrality

The binding is facilitator-neutral by rule. Any facilitator (Ax402, Coinbase CDP, Prism, icpay, self-hosted open-source) can sit behind a merchant's `org.x402` handler, provided it implements the contract below. The agent never learns which one is there.

This is also the commercial thesis: a neutral spec expands the market for every facilitator, and Ax402 competes on economics ($0.005/settlement) and reliability, not lock-in.

## 2. Required facilitator behavior

To serve a merchant exposing the `org.x402` handler, a facilitator MUST:

1. **Verify** x402 payments per the x402 spec for the scheme and network in the challenge: e.g. for the `exact` scheme on EVM, EIP-3009 `transferWithAuthorization` or Permit2 `permitWitnessTransferFrom` (the `assetTransferMethod` inside the exact scheme); for `exact` on Solana, `TransferChecked` for SPL tokens. Verify amount, payTo, validity window, nonce per the scheme's critical validation requirements.
2. **Settle** on-chain to the merchant's `payTo` on every network the handler advertises.
3. **Honor the payment-identifier as idempotency key.** Same identifier + same signature = one settlement, ever. Duplicate submissions return the original settlement result (same tx hash), not an error and not a second transfer.
4. **Return the signed receipt** (offer-receipt extension) in the settlement response, signed by the `payTo` key (or the merchant's designated signer).
5. **Accept the quote window.** A challenge issued with `validUntil` must remain verifiable until that timestamp; verification after expiry MUST fail with a recoverable error, never a silent settle.
6. **Expose settlement state** to the merchant (webhook or poll) so the merchant can implement the B5 state machine: in-flight, settled, failed-with-reason. In the adapter era this is not optional plumbing: after the agent pays `resource.url` directly, complete is **reconcile** — the merchant polls settlement state (or consumes the upstream fulfill) to decide `completed` vs `complete_in_progress`.

RECOMMENDED:

7. **Receipt webhook to the merchant** keyed by checkout session id, so the merchant can reconcile UCP order state with on-chain settlement asynchronously.
8. **Testnet parity** on at least Base Sepolia (`eip155:84532`) for conformance testing, since that is where the ecosystem's reference implementations live.

## 3. Reference implementation

Ax402 (ax402.io) will implement this contract as the reference facilitator: $0.005 per settlement, stablecoins on EVM chains, Go/TS/Python SDKs.

Goal worth restating: Prism behind `org.x402` too. A standard with only one facilitator is not a standard. The fastest way to make this real is a conformance suite (Layer 4, deferred) plus reference integrations on the two platforms that matter first (WooCommerce via the AxLabs extension, plus one headless reference server).

## 4. Out of scope (v1)

- Facilitator discovery/ranking: merchants pick their facilitator out of band.
- Refund flows (Layer 4; see x402 #1425 authCapture work for the escrow direction).
- Cross-chain settlement (asset must be on an advertised network).

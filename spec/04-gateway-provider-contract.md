# Monetization Gateway Provider Contract

Status: pre-draft.

## 1. Terminology

A **Monetization Gateway** is a service that provides a way to charge an amount with x402: it issues challenges, verifies payment signatures, and settles on-chain. All the facilitator infrastructure (verification pipelines, settlement batching, node operations, exchange-rate sourcing) is handled by the **Monetization Gateway Provider**, the operator of the gateway.

In this binding, the Monetization Gateway is merchant-side configuration. The agent never learns which gateway sits behind the merchant.

## 2. Neutrality

The binding is gateway-neutral by rule. Any Monetization Gateway Provider (Ax402, Coinbase CDP, Prism, icpay, self-hosted open-source) can sit behind a merchant's `org.x402` handler, provided it implements the contract below. The agent never learns which one is there.

This is also the commercial thesis: a neutral spec expands the market for every provider, and each competes on economics and reliability, not lock-in.

## 3. Required provider behavior

To serve a merchant exposing the `org.x402` handler, a Monetization Gateway Provider MUST:

1. **Verify** x402 payments per the x402 spec for the scheme and network in the challenge: e.g. for the `exact` scheme on EVM, EIP-3009 `transferWithAuthorization` or Permit2 `permitWitnessTransferFrom` (the `assetTransferMethod` inside the exact scheme); for `exact` on Solana, `TransferChecked` for SPL tokens. Verify amount, payTo, validity window, nonce per the scheme's critical validation requirements.
2. **Settle** on-chain to the merchant's `payTo` on every network the handler advertises.
3. **Honor the payment-identifier as idempotency key.** Same identifier + same signature = one settlement, ever. Duplicate submissions return the original settlement result (same tx hash), not an error and not a second transfer.
4. **Return the signed receipt** (offer-receipt extension) in the settlement response, signed by the `payTo` key (or the merchant's designated signer).
5. **Accept the quote window.** A challenge issued with `validUntil` must remain verifiable until that timestamp; verification after expiry MUST fail with a recoverable error, never a silent settle.
6. **Expose settlement state** to the merchant (webhook or poll) so the merchant can implement the state machine in [05-state-mapping.md](05-state-mapping.md): in-flight, settled, failed-with-reason. On the External-URL payment path this is not optional plumbing: after the agent pays `resource.url` directly, complete is **reconcile** - the merchant polls settlement state (or consumes the upstream fulfill) to decide `completed` vs `complete_in_progress`.

RECOMMENDED:

7. **Receipt webhook to the merchant** keyed by checkout session id, so the merchant can reconcile UCP order state with on-chain settlement asynchronously.
8. **Testnet parity** on at least Base Sepolia (`eip155:84532`) for conformance testing, since that is where the ecosystem's reference implementations live.

## 4. Provider capability: resource binding (which payment path a merchant gets)

The two payment paths in [02-payment-flows.md](02-payment-flows.md) §3.1 map to a provider capability:

- A provider that can **verify and settle payments whose signed resource is an arbitrary merchant URL** (such as the shop's complete URL) enables **Same-URL Payment** for its merchants.
- A provider whose verification pipeline **binds payments to resources it operates itself** (its gateway endpoints) places its merchants on **External-URL Payment**.

Both are fully conformant. A merchant's provider choice determines the path; the agent discovers which path applies from the signed challenge alone, with no out-of-band knowledge. Providers that add arbitrary-resource verification later move their merchants to the shorter round trip with no spec change; nothing in this binding schedules or requires that.

## 5. Reference implementations

The goal is multiple providers behind the same neutral handler. A standard with only one provider is not a standard. The fastest way to make this real is a conformance suite (Layer 4, deferred) plus reference integrations on the two platforms that matter first (WooCommerce via the AxLabs extension, plus one headless reference server).

## 6. Out of scope (v1)

- Provider discovery/ranking: merchants pick their provider out of band.
- Refund flows (Layer 4; see x402 #1425 authCapture work for the escrow direction).
- Cross-chain settlement (asset must be on an advertised network).

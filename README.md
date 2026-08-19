# ucp-x402-binding

A vendor-neutral UCP payment-handler binding for x402.

Status: **pre-draft, private**. Everything here is under active development by AxLabs and not yet submitted to the UCP Shopping Tech Council or the x402 Foundation.

## Why

The Universal Commerce Protocol (UCP) is deliberately payment-rail agnostic: its `ucp.payment_handlers` extension point carries nothing but a namespaced handler entry (`id`, `version`, `spec`, `schema`). Google Pay and Shop Pay are the only real instances today. Meanwhile x402 has become the de-facto machine-to-machine payment primitive (HTTP 402 challenge + EIP-3009/Permit2 signatures + stablecoin settlement).

There is no neutral way for a UCP merchant to say "I accept agent-wallet stablecoin payments via x402" and for a buying agent to pay without knowing which facilitator sits behind the merchant. The only production integration (fd.xyz Prism) is proprietary: handler `xyz.fd.prism_payment`, hardwired to the Prism gateway.

This repo defines the missing layer:

1. **`org.x402` handler spec** - what a merchant advertises in `/.well-known/ucp` when it accepts x402, and what the buying agent needs to select a payment method. Deliberately free of any facilitator detail.
2. **Wire binding** - how the UCP checkout flow maps onto x402 v2 HTTP (and MCP/A2A transports), with the 402 challenge at `checkout-sessions/{id}/complete`, price lock via the offer-receipt extension, and session-bound idempotency via the payment-identifier extension.
3. **Prior art** - what exists today, verified from source, so we don't re-research it.

## Design rules (fixed)

1. **The facilitator stays merchant-side and hidden from agents.** Discovery and checkout expose only what the buying agent needs: handler id, networks, assets, amount, `payTo`. Facilitator choice is merchant config, never advertised. The binding is facilitator-neutral: Ax402 is one of many.
2. **Open posture beats proprietary handlers.** fd.xyz/Prism sitting behind the neutral `org.x402` handler is a stated goal, not a threat. AxLabs wins at the spec layer, not in a plugin race.
3. **Scope is Layers 1-3**: discovery, commerce flow, settlement. Layer 4 (auth mandates, refunds, governance, conformance) is deferred until the core lands.
4. **Every wire format in this repo is verified against the actual specs** (UCP `docs/specification/*.md`, x402 `specs/`), not blog summaries.

## Repository layout

```
docs/
  00-prior-art.md          # verified landscape: fd.xyz Prism, ACP SEP #109, UCP/x402 signals
  01-handler-spec.md       # B1: the org.x402 handler entry (discovery layer)
  02-wire-binding.md       # B3/B4: UCP checkout <-> x402 v2 HTTP binding
  03-amount-semantics.md   # B3a: fiat totals -> base units, quote windows
  04-state-mapping.md      # B5: UCP session states vs x402 settlement states
  05-facilitator-contract.md # B6: what any facilitator must implement
  06-receipts.md           # B7: offer-and-receipt usage, order-binding proposal
  07-namespace-governance.md # B2: org.x402 ownership and path into the x402 Foundation
schema/
  handler.schema.json      # JSON Schema for the org.x402 handler entry
examples/
  discovery.json           # /.well-known/ucp with the org.x402 handler
  checkout-flow.md         # end-to-end wire trace (HTTP + MCP)
```

## Non-goals (v1)

- No facilitator discovery, ranking, or advertisement.
- No refunds, mandates, or dispute resolution (Layer 4).
- No changes to UCP core schemas. Everything rides on the existing `payment_handlers` and extension mechanisms.
- No new cryptography. Reuses x402 payment schemes (open registry: `exact`, `upto`, `batch-settlement` today) and the offer-receipt extension as specified.

## License

TBD - likely Apache-2.0 when made public, to match common standards-repo practice.

## Contributing

Private while pre-draft. AxLabs internal only.

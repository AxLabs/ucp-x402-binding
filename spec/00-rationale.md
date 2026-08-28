# Rationale and Prior Art

Status of this document: context, not normative. It records why the binding is shaped the way it is, the landscape it was designed against (verified from primary sources), and the governance path for the `org.x402` namespace. The normative specification lives in [01-payment-handler.md](01-payment-handler.md) through [05-state-mapping.md](05-state-mapping.md).

## 1. The problem this binding solves

The Universal Commerce Protocol (UCP) is deliberately payment-rail agnostic: its `ucp.payment_handlers` extension point carries nothing but a namespaced handler entry (`id`, `version`, `spec`, `schema`). Google Pay and Shop Pay are the only real instances today. Meanwhile x402 has become the de-facto machine-to-machine payment primitive (HTTP 402 challenge + EIP-3009/Permit2 signatures + stablecoin settlement).

There is no neutral way for a UCP merchant to say "I accept agent-wallet stablecoin payments via x402" and for a buying agent to pay without knowing which facilitator sits behind the merchant. The only production integration (fd.xyz Prism) is proprietary: handler `xyz.fd.prism_payment`, hardwired to the Prism gateway.

This repo defines the missing layer:

1. **`org.x402` handler spec** - what a merchant advertises in `/.well-known/ucp` when it accepts x402, and what the buying agent needs to select a payment method. Deliberately free of any facilitator detail.
2. **Wire binding** - how the UCP checkout flow maps onto x402 v2 HTTP (and MCP/A2A transports), with the 402 challenge at `checkout-sessions/{id}/complete`, price lock via the offer-receipt extension, and session-bound idempotency via the payment-identifier extension. Two payment paths, Same-URL and External-URL, both first-class (see [02-payment-flows.md](02-payment-flows.md)).
3. **Prior art** - what exists today, verified from source, so nobody re-researches it.

## 2. Design principles (fixed)

1. **The facilitator stays merchant-side and hidden from agents.** Discovery and checkout expose only what the buying agent needs: handler id, networks, assets, amount, `payTo`. Facilitator choice is merchant config, never advertised. The binding is facilitator-neutral.
2. **Open posture beats proprietary handlers.** fd.xyz/Prism sitting behind the neutral `org.x402` handler is a stated goal, not a threat. AxLabs wins at the spec layer, not in a plugin race.
3. **Scope is Layers 1-3**: discovery, commerce flow, settlement. Layer 4 (auth mandates, refunds, governance, conformance) is deferred until the core lands.
4. **Every wire format in this repo is verified against the actual specs** (UCP `docs/specification/*.md`, x402 `specs/`), not blog summaries.

## 3. Prior art (verified, with sources)

Research complete as of 2026-08-20. Everything below was verified against primary sources (repo files, spec text, issue threads), not blog summaries. Re-verify before external use.

### 3.1 UCP: no x402 direction, by design

| Signal | Finding | Source |
|---|---|---|
| x402 mentions in UCP issues | 0 relevant (only #450, smart-account credential provider, zero comments) | github.com/Universal-Commerce-Protocol/ucp/issues |
| x402 in UCP discussions | 0 relevant | org discussions tab |
| `payment_handlers` in spec | Generic by design: namespace + id + version + spec + schema. Only real instances: Google Pay (`com.google.pay`), Shop Pay (`dev.shopify.shop_pay`) | UCP spec, discovery docs |
| Spec posture | "Built on Standards: leverages existing open standards for payments wherever applicable" | UCP README |
| Governance | Shopping Tech Council: Google (5 seats), Shopify (4), Amazon, Microsoft, Stripe, Meta, Etsy, Target, Salesforce, Wayfair | UCP governance docs |
| External implementation engagement | UCP discussion #297: "UCPReady" spec-complete WooCommerce implementation, live on 40k SKU store, council engaged via show-and-tell | github.com/Universal-Commerce-Protocol/ucp/discussions/297 |

UCP issue #450 (smart-account credential provider for agent-led commerce): zero comments. Decision: do not engage.

### 3.2 fd.xyz / Finance District / Prism: the real integration

Organization: financedistrict-platform on GitHub, backed by 1st Digital (fd.xyz). This is production software, not a demo.

| Fact | Detail | Source |
|---|---|---|
| Platforms | WooCommerce, Shopware 6.7, Medusa v2, PrestaShop plugins, MIT-licensed | github.com/financedistrict-platform |
| Handler id | `xyz.fd.prism_payment`, advertised in `/.well-known/ucp` | plugin source |
| Flow | session create -> plugin calls Prism `prepare_ucp_payment` (fiat minor units in, `accepts[]` out) -> agent submits x402 credential at complete -> plugin validates + settles via Prism gateway -> order meta gets tx hash | plugin source (PHP), Shopware handler README |
| Facilitator isolation | Agent never sees facilitator URL. "Currency- & chain-agnostic: Prism does all token/chain/x402 math, the plugin only relays" | Shopware plugin README |
| Order lifecycle | Order created pending at session time, so order number is available in payment descriptions pre-settlement. Idempotency keys on prepare | plugin source, commit history |
| Testnet | Base Sepolia staging, real USDC contracts | repo config |
| Activity | Active commits through Jul 2026, 82 tests in the WooCommerce package | GitHub commit history |
| Limitation | Gateway-locked, proprietary namespace, no offer-and-receipt usage. Their "receipt" is order meta with a tx hash | plugin source |

Key architectural validation: their facilitator-isolation design (agent sees handler id, `accepts[]`, and a credential submission point only) matches our rule #1. We keep that shape and remove the lock-in.

### 3.3 ACP: live x402 proposal in the competing protocol

| Fact | Detail | Source |
|---|---|---|
| SEP #109/#111 | "Crypto Payment Method (x402-based)", open since Feb 2026, author icpay/BackTrack | github.com/agentic-commerce-protocol/agentic-commerce-protocol/issues |
| Mechanism | Reuses ACP's Shared Payment Token flow: agent signs x402 payload, PSP `delegate_payment` verifies via facilitator, settlement deferred until merchant executes | SEP text |
| Sponsor | Prasad Wangikar, Stripe's seat on the UCP Shopping Tech Council | SEP + council roster |
| Signal | The same people are watching this space across both protocols. A neutral UCP handler and a neutral ACP SEP are complementary, not competing | - |

### 3.4 x402 spec facts the binding depends on

| Fact | Source |
|---|---|
| v2 HTTP: 402 + `PAYMENT-REQUIRED` header (base64 `PaymentRequired`); payment in `PAYMENT-SIGNATURE`; settlement in `PAYMENT-RESPONSE`; CAIP-2 networks | coinbase/x402 `specs/` |
| v1 HTTP: 402 + `PaymentRequirementsResponse` body with `accepts[]`; `X-PAYMENT` / `X-PAYMENT-RESPONSE` headers | same |
| Amounts: integer base units as strings, never decimals | same |
| Schemes: open, extensible registry. Today: `exact` (per-network bindings: evm, svm, algo, aptos, hedera, keeta, stellar, sui), `upto` (usage-based), `batch-settlement`. On EVM `exact`, `assetTransferMethod` is `eip3009` (preferred) or `permit2` (universal fallback) | same |
| offer-receipt extension: signed offer `{version, resourceUrl, scheme, network, asset, payTo, amount, validUntil?}` + signed receipt `{version, network, resourceUrl, payer, issuedAt, transaction?}`, EIP-712 chainId=1 or JWS | coinbase/x402 extension spec |
| payment-identifier extension: idempotency key 16-128 chars, UUID-v4-with-prefix recommended | coinbase/x402 extension spec |
| x402-foundation/x402 (6.5k stars): where issues and spec discussions live | github.com/x402-foundation/x402 |

### 3.5 Minor prior art (low signal)

- TRON-based UCP+x402 demo repo, 1 star, throwaway. No follow-up commits.
- Sandbox/landscape comparison repos (agentcommerce.xyz etc.) listing protocols side by side. No implementation work.
- Medium article "Building the Agentic Commerce Stack: connecting x402 with UCP" (iamanuragsaini): conceptually right direction, but contains fabricated wire formats (invented `ucp.cart.add`-style JSON-RPC methods, invented `WWW-Authenticate: x402` headers). Useful as misinformation reference, not as source.

### 3.6 The opening

Nobody has shipped a vendor-neutral UCP x402 handler. fd.xyz built the proprietary version and proved the architecture. ACP has an open SEP doing the equivalent for their protocol. The neutral UCP handler spec is unclaimed, and it is the layer any Monetization Gateway can sit behind as one facilitator among several.

## 4. Namespace governance: `org.x402` ownership

### 4.1 The problem

UCP payment handlers are keyed by reverse-domain namespace (`com.google.pay`, `dev.shopify.shop_pay`, `xyz.fd.prism_payment`). Whoever owns the namespace owns the handler semantics. If AxLabs ships under `net.axlabs.x402`, we get an AxLabs-locked handler, which is exactly the fd.xyz mistake with our name on it. The goal is a neutral namespace owned by a standards body.

### 4.2 Proposed ownership

**The x402 Foundation should own `org.x402`.**

- `org.x402.payment` (this binding) would be the crypto-rail handler.
- The namespace leaves room for future handlers (`org.x402.mcp` variants, scheme-specific handlers) without new namespaces.
- AxLabs authors the spec and reference implementation, proposes it via the Discovery working group (where we are already active), and donates it. Authorship credit, not ownership.

Precedent: ACP's SEP process shows the pattern that works: an external company (icpay) proposes, a council member (Prasad Wangikar) sponsors, the standard becomes neutral. Our path into UCP is analogous: propose through the x402 Foundation, cross-post to UCP discussions once the handler spec is stable (see UCP discussion #297 for the show-and-tell pattern the UCP council responds to).

### 4.3 Migration story (why fd.xyz can join later)

`xyz.fd.prism_payment` and `org.x402.payment` can coexist in the same discovery profile: a merchant running Prism plugins advertises both, agents that understand `org.x402` prefer it. Prism adopting the neutral handler is a config change plus a gateway feature, not a rewrite. That is the point of designing compatible-by-construction.

### 4.4 Sequence

1. AxLabs publishes the handler spec + reference implementation (this repo, public once stable).
2. Socialize in the x402 Foundation Discovery WG (already active; the discovery work there is complementary: they define how x402 endpoints are found, we define how UCP merchants advertise x402).
3. Foundation adopts namespace governance, spec moves to the Foundation repo or stays here under Foundation stewardship.
4. UCP Shopping Tech Council submission: cross-post the handler spec as a UCP discussion item, citing the reference implementation.
5. fd.xyz engagement: direct outreach once the spec is public. "Prism behind org.x402" is the headline.

### 4.5 Risks

- **Namespace squatting:** if someone else registers a neutral-sounding x402 namespace in UCP before us, we fragment the space. This is the urgency argument: the ACP SEP and fd.xyz's head start mean the neutral spec should land within roughly a quarter.
- **Foundation disinterest:** if the x402 Foundation does not want namespace governance, fallback is a dedicated neutral org (e.g., `x402.org` style). Second choice, more setup cost.
- **UCP council gatekeeping:** the Shopping Tech Council is dominated by Web2 incumbents (Google, Shopify, Stripe). The pitch that lands: UCP merchants get a new payment rail with zero platform fees, agents get a payment method that works everywhere, no council member loses anything. Frame it as adoption-positive, not crypto-evangelism.

### 4.6 Authority binding makes hosting urgent (UCP 2026-08-25)

UCP 2026-08-25 makes namespace authority binding normative: platforms mechanically verify the payment handler `schema` URL host against the handler name and reject non-conforming handlers during negotiation. Hosting the `org.x402.payment` schema under `x402.org` is therefore a hard deployment requirement for conformant platforms, not only a governance nicety. The binding's discovery examples already point at the canonical location, `https://x402.org/schemas/ucp-payment-handler.json`.

## 5. The production incident behind the no-impersonation rule

During development, a production merchant plugin implemented signature forwarding: on receiving the agent's `complete` retry carrying `PAYMENT-SIGNATURE`, it relayed that signature server-side to the Monetization Gateway and treated the gateway's HTTP response as proof of payment. The gateway never settled anything; the order was marked paid with no funds received.

The lesson is now a normative rule ([02-payment-flows.md](02-payment-flows.md), no-impersonation): a merchant that proxies buyer signatures is a confused deputy. The merchant's job after the agent has paid is to observe settlement state, never to act as an x402 client on the buyer's behalf. The rule exists because the failure mode is real, not hypothetical.

# Prior Art and Landscape (verified, with sources)

Status: research complete as of 2026-08-20. Everything below was verified against primary sources (repo files, spec text, issue threads), not blog summaries. Re-verify before external use.

## 1. UCP: no x402 direction, by design

| Signal | Finding | Source |
|---|---|---|
| x402 mentions in UCP issues | 0 relevant (only #450, smart-account credential provider, zero comments) | github.com/Universal-Commerce-Protocol/ucp/issues |
| x402 in UCP discussions | 0 relevant | org discussions tab |
| `payment_handlers` in spec | Generic by design: namespace + id + version + spec + schema. Only real instances: Google Pay (`com.google.pay`), Shop Pay (`dev.shopify.shop_pay`) | UCP spec, discovery docs |
| Spec posture | "Built on Standards: leverages existing open standards for payments wherever applicable" | UCP README |
| Governance | Shopping Tech Council: Google (5 seats), Shopify (4), Amazon, Microsoft, Stripe, Meta, Etsy, Target, Salesforce, Wayfair | UCP governance docs |
| External implementation engagement | UCP discussion #297: "UCPReady" spec-complete WooCommerce implementation, live on 40k SKU store, council engaged via show-and-tell | github.com/Universal-Commerce-Protocol/ucp/discussions/297 |

UCP issue #450 (smart-account credential provider for agent-led commerce): zero comments. Decision: do not engage.

## 2. fd.xyz / Finance District / Prism: the real integration

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

## 3. ACP: live x402 proposal in the competing protocol

| Fact | Detail | Source |
|---|---|---|
| SEP #109/#111 | "Crypto Payment Method (x402-based)", open since Feb 2026, author icpay/BackTrack | github.com/agentic-commerce-protocol/agentic-commerce-protocol/issues |
| Mechanism | Reuses ACP's Shared Payment Token flow: agent signs x402 payload, PSP `delegate_payment` verifies via facilitator, settlement deferred until merchant executes | SEP text |
| Sponsor | Prasad Wangikar, Stripe's seat on the UCP Shopping Tech Council | SEP + council roster |
| Signal | The same people are watching this space across both protocols. A neutral UCP handler and a neutral ACP SEP are complementary, not competing | - |

## 4. x402 spec facts the binding depends on

| Fact | Source |
|---|---|
| v2 HTTP: 402 + `PAYMENT-REQUIRED` header (base64 `PaymentRequired`); payment in `PAYMENT-SIGNATURE`; settlement in `PAYMENT-RESPONSE`; CAIP-2 networks | coinbase/x402 `specs/` |
| v1 HTTP: 402 + `PaymentRequirementsResponse` body with `accepts[]`; `X-PAYMENT` / `X-PAYMENT-RESPONSE` headers | same |
| Amounts: integer base units as strings, never decimals | same |
| EVM exact scheme: EIP-3009 `transferWithAuthorization` (recommended) or Permit2 | same |
| offer-receipt extension: signed offer `{version, resourceUrl, scheme, network, asset, payTo, amount, validUntil?}` + signed receipt `{version, network, resourceUrl, payer, issuedAt, transaction?}`, EIP-712 chainId=1 or JWS | coinbase/x402 extension spec |
| payment-identifier extension: idempotency key 16-128 chars, UUID-v4-with-prefix recommended | coinbase/x402 extension spec |
| x402-foundation/x402 (6.5k stars): where issues and spec discussions live | github.com/x402-foundation/x402 |

## 5. Minor prior art (low signal)

- TRON-based UCP+x402 demo repo, 1 star, throwaway. No follow-up commits.
- Sandbox/landscape comparison repos (agentcommerce.xyz etc.) listing protocols side by side. No implementation work.
- Medium article "Building the Agentic Commerce Stack: connecting x402 with UCP" (iamanuragsaini): conceptually right direction, but contains fabricated wire formats (invented `ucp.cart.add`-style JSON-RPC methods, invented `WWW-Authenticate: x402` headers). Useful as misinformation reference, not as source. The fabricated markers are catalogued in the knowledge bank.

## 6. The opening

Nobody has shipped a vendor-neutral UCP x402 handler. fd.xyz built the proprietary version and proved the architecture. ACP has an open SEP doing the equivalent for their protocol. The neutral UCP handler spec is unclaimed, and it is the layer Ax402 can sit behind as one facilitator among several.

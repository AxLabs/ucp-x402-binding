# Namespace Governance: `org.x402` Ownership (B2)

Status: pre-draft.

## 1. The problem

UCP payment handlers are keyed by reverse-domain namespace (`com.google.pay`, `dev.shopify.shop_pay`, `xyz.fd.prism_payment`). Whoever owns the namespace owns the handler semantics. If AxLabs ships under `net.axlabs.x402`, we get an AxLabs-locked handler, which is exactly the fd.xyz mistake with our name on it. The goal is a neutral namespace owned by a standards body.

## 2. Proposed ownership

**The x402 Foundation should own `org.x402`.**

- `org.x402.payment` (this binding) would be the crypto-rail handler.
- The namespace leaves room for future handlers (`org.x402.mcp` variants, scheme-specific handlers) without new namespaces.
- AxLabs authors the spec and reference implementation, proposes it via the Discovery working group (where we are already active), and donates it. Authorship credit, not ownership.

Precedent: ACP's SEP process shows the pattern that works: an external company (icpay) proposes, a council member (Prasad Wangikar) sponsors, the standard becomes neutral. Our path into UCP is analogous: propose through the x402 Foundation, cross-post to UCP discussions once the handler spec is stable (see UCP discussion #297 for the show-and-tell pattern the UCP council responds to).

## 3. Migration story (why fd.xyz can join later)

`xyz.fd.prism_payment` and `org.x402.payment` can coexist in the same discovery profile: a merchant running Prism plugins advertises both, agents that understand `org.x402` prefer it. Prism adopting the neutral handler is a config change plus a gateway feature, not a rewrite. That is the point of designing compatible-by-construction.

## 4. Sequence

1. AxLabs publishes the handler spec + reference implementation (this repo, public once stable).
2. Socialize in the x402 Foundation Discovery WG (already active; the discovery work there is complementary: they define how x402 endpoints are found, we define how UCP merchants advertise x402).
3. Foundation adopts namespace governance, spec moves to the Foundation repo or stays here under Foundation stewardship.
4. UCP Shopping Tech Council submission: cross-post the handler spec as a UCP discussion item, citing the reference implementation.
5. fd.xyz engagement: direct outreach once the spec is public. "Prism behind org.x402" is the headline.

## 5. Risks

- **Namespace squatting:** if someone else registers a neutral-sounding x402 namespace in UCP before us, we fragment the space. This is the urgency argument: the ACP SEP and fd.xyz's head start mean the neutral spec should land within roughly a quarter.
- **Foundation disinterest:** if the x402 Foundation does not want namespace governance, fallback is a dedicated neutral org (e.g., `x402.org` style). Second choice, more setup cost.
- **UCP council gatekeeping:** the Shopping Tech Council is dominated by Web2 incumbents (Google, Shopify, Stripe). The pitch that lands: UCP merchants get a new payment rail with zero platform fees, agents get a payment method that works everywhere, no council member loses anything. Frame it as adoption-positive, not crypto-evangelism.

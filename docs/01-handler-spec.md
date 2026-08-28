# The `org.x402` UCP Payment Handler Spec (B1)

Status: pre-draft. Everything normative here is a proposal by AxLabs until adopted.

## 1. Position in UCP discovery

UCP discovery is `GET /.well-known/ucp` returning a profile. The relevant section:

```json
{
  "ucp": {
    "payment_handlers": {
      "org.x402.payment": [
        {
          "id": "org.x402.payment",
          "version": "2026-08-20",
          "spec": "https://github.com/AxLabs/ucp-x402-binding",
          "schema": "https://x402.org/schemas/ucp-payment-handler.json"
        }
      ]
    }
  }
}
```

Per UCP 2026-08-25, `payment_handlers` is a **map of arrays**: each key holds an array of handler entries. The four base fields (`id`, `version`, `spec`, `schema`) are exactly what UCP defines. We add one optional UCP-legal extension object, `x402`, carrying what a buying agent needs to decide whether it can pay here. Nothing else.

## 2. Handler entry fields

| Field | Required | Type | Purpose |
|---|---|---|---|
| `id` | yes | string | `org.x402.payment` (reverse-domain, x402 Foundation namespace) |
| `version` | yes | string | Handler spec version, `YYYY-MM-DD` (UCP entity versions are dates, not semver) |
| `spec` | yes | URL | Human-readable spec document |
| `schema` | yes | JSON Schema URL | Machine-readable schema for the extended fields |
| `x402.networks` | yes | array of CAIP-2 chain ids | Networks the merchant accepts for settlement. Any namespace allowed (`eip155:8453`, `neo:860833102`, `solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp`, `bip122:...`); support for a namespace is between merchant and facilitator |
| `x402.assets` | yes | array of objects | Settlement assets, each `{network, asset, decimals, symbol?}`. The `asset` identifier is chain-specific: EVM and Neo N3 contract addresses are `0x`+40 hex, Solana token mints are base58 pubkeys, other chains define their own notation. The shape is governed by per-network schemas (see `network_schemas`), not hardcoded in the core schema |
| `x402.max_amount` | no | string (base units) | Ceiling for a single payment, base units. Lets agents avoid wasting a signature on out-of-range quotes. |
| `x402.quote_window` | no | integer seconds | How long a checkout total is locked once quoted (default 600) |
| `x402.schemes` | no | array of open strings | Accepted x402 payment schemes in preference order. Open registry: today `exact`, `upto`, `batch-settlement`; new schemes land in x402 over time. Consumers MUST ignore unrecognized ids. Not an enum: closing it would break forward compatibility |
| `x402.network_schemas` | no | object (namespace -> schema URL) | Per-network asset schema registry. Maps each CAIP-2 namespace present in the handler to the JSON Schema that defines its asset identifier shape. Reference schemas ship in this repo under `schema/networks/`; chain communities can author and host their own. Keeps the core schema chain-agnostic and moves asset-shape governance to the chains themselves |

### Naming convention

**Namespace authority binding (UCP 2026-08-25).** Platforms verify that a business controls the reverse-DNS namespace of a payment handler by matching the handler `schema` URL host against the handler name. For `org.x402.payment`, the schema must be hosted at `x402.org` or a label-aligned subdomain (for example `payment.x402.org`). The canonical schema location is `https://x402.org/schemas/ucp-payment-handler.json`. Until the x402 Foundation hosts it there, deployments that point the `schema` field at this repository will fail authority verification on conformant platforms. The discovery examples in this repo show the canonical target.

**`map_order` (UCP 2026-08-25).** A business may publish a preferred ordering for registry maps such as `payment_handlers` via `map_order`. A merchant MAY use it to signal handler preference; agents MUST NOT rely on it for correctness.


UCP field names are snake_case throughout (`payment_handlers`, `available_instruments`, `handler_id`, `line_items`). Every field this binding defines follows the same convention: `max_amount`, `quote_window`, `network_schemas`. The one deliberate exception: camelCase appears **inside verbatim x402 wire payloads** (`PaymentRequired` with `maxAmountRequired`, `payTo`, `validUntil`, signed offers and receipts). Those are x402 objects quoted as-is across the wire, not UCP fields, and re-casing them would break x402 signature payloads.

### Design rationale

**`x402.assets` is capability, not a quote.** Discovery tells the agent which networks/assets the merchant may settle store-wide. It is not a promise that every asset is quotable on every checkout (FX source down, chain paused, per-checkout policy), and it MUST NOT be treated as the 402 catalog. Per-checkout payable assets live in the session offer (`payment.instruments[]` on a ready session) and the challenge (`accepts[]`); see `02-wire-binding.md` for the three-layer containment rules. Do not add per-checkout amounts to discovery. `available_instruments: [{"type": "x402"}]` at discovery is enough; per-asset rows belong on the checkout session, not the handler entry.

**No facilitator URL. Ever.** The facilitator is merchant-side configuration. The agent never learns which facilitator sits behind the merchant, and the binding works identically with Ax402, CDP, Prism, or any compliant facilitator. This is rule #1 and non-negotiable.

**Networks before assets.** An agent with a wallet on Base answers the network question first; asset selection comes second. Network ids are full CAIP-2 (`namespace:reference`), not just `eip155:<chain-id>`: the binding is chain-agnostic by design, and any namespace the merchant's facilitator supports is legal. Which namespaces are actually supported is merchant + facilitator concern, invisible to the agent in discovery.

**Asset identifiers are chain-native, governed per-network.** EVM and Neo N3 assets are `0x`+40 hex contract addresses; Solana assets are base58 mint pubkeys; other chains use whatever notation they define. The core schema deliberately does NOT hardcode these rules. Instead, `x402.networkSchemas` maps each CAIP-2 namespace to a JSON Schema that defines its asset shape (reference schemas for `eip155`, `neo`, `solana` ship in `schema/networks/`). Validators apply the registered schema per asset and fall back to a lenient opaque-string default for unregistered namespaces. This keeps asset-shape governance with the chain communities: a network that wants to change or extend its identifier notation updates its schema, not this spec.

**Amounts in base units, always.** `"135500000"` = 135.50 USD in 6-decimal USDC. Never decimals. Matches x402 core.

**`payTo` intentionally absent from discovery.** The `payTo` address is per-offer and delivered in the 402 challenge, signed by the merchant. It does not belong in discovery, where it would invite address-poisoning and spam discrimination.

**Compatible by construction with `xyz.fd.prism_payment`.** Their handler advertises Prism-specific fields. A merchant running their plugin could mint a `org.x402` entry alongside with no conflict; Prism itself can sit behind the neutral handler later. That is a stated goal, not a threat.

## 3. `schema/handler.schema.json`

See the JSON Schema in this repo. It validates the four UCP base fields plus the `x402` object. The schema is deliberately minimal: anything the buying agent does not need to select a payment method is out of scope.

## 4. Declared Action type: `org.x402.payment.challenge`

Per UCP 2026-08-25, an extension declares each Action type it contributes. This binding (the `org.x402.payment` handler extension) declares exactly one:

- **Key:** `org.x402.payment.challenge` (reverse-domain Action type under this binding's namespace; passes the UCP `reverse_domain_name` pattern).
- **Where it appears:** Checkout responses while payment is pending. Omitted in terminal states (`completed`, `expired`, `cancelled`).
- **`config` shape:** a single field, `instructions` (string, required). Text only. It tells the agent what to do next: fetch the 402 challenge from the session's complete URL and follow it.
- **Processing model:** advisory. A Platform that recognizes the type reads `instructions` and proceeds to the complete call. A Platform that does not recognize it MUST ignore it; payment succeeds without processing the Action (fallback = the bare 402 challenge, which is authoritative).
- **Trust:** the Action is merchant-asserted and carries **no payment data**. It never contains gateway URLs, addresses, amounts, or credentials. The signed x402 challenge remains the sole source of payment coordinates (no-leak rule, wire binding §3.1.2). Agents MUST NOT treat `instructions` as authoritative payment data.
- **Outcome:** the Action clears when the session reaches a terminal state; merchants SHOULD stop emitting it once the 402 has been fetched or the session is paid.
- **Ordering:** a single type, at most one outstanding instance in practice; array order has no processing semantics.

A merchant implementing this handler MAY emit the Action; nothing requires it, and its absence MUST NOT affect payment.

## 5. Open questions

1. ~~Handler id: `org.x402.crypto` vs `org.x402.payments` vs plain `org.x402`.~~ **RESOLVED (2026-08-20)**: `org.x402.payment`. Avoids the "crypto" connotation; reads as the payment rail handler in the x402 Foundation namespace.
2. Should `assets` entries carry a `verified` flag (issuer allow-list reference)? The dilemma: on-chain anyone can deploy a USDC-named token, so an agent trusting the handler's `symbol: "USDC"` alone could pay a worthless lookalike. Options: (a) do nothing and let agents do their own diligence, (b) require the handler to point at an issuer allow-list (a named, signed or curated list of legitimate issuer addresses, e.g. Circle's official USDC addresses), or (c) put a free-form `verified` boolean per asset and let the trust question be handled entirely merchant-side. The real question is whose claim the flag represents: the merchant's, the facilitator's, or a third-party list's, and who verifies the verifier. Deferred to working-group discussion.
3. ~~Single `maxAmount` vs per-asset ceilings.~~ **RESOLVED (2026-08-20)**: single `max_amount` in v1.
4. ~~Conditional asset-shape rules~~ **RESOLVED**: per-network schemas referenced via `x402.network_schemas` (see above). The core schema stays chain-agnostic; asset-shape rules live in `schema/networks/<namespace>.schema.json`, maintained with each chain community. A chain can register its schema by hosting it and adding the URL to its handler entries.
5. ~~`bip122` assets~~ **RESOLVED (design direction)**: delegated to the per-network schema. A `bip122` schema would define the native-asset convention, and the direction is that native assets use empty or omitted `asset` with `decimals: 0`. The core schema accepts both, and the decision ships with the first bip122 per-network schema rather than in the core spec.
6. Who hosts and governs the per-network schema registry long-term: this repo (AxLabs) until handover to the x402 Foundation or UCP, or the ChainAgnostic namespaces project, or each chain community individually? Open for governance discussion.
7. FX semantics. **RESOLVED (design direction, 2026-08-20)**: the merchant owns the quote. For any settlement asset whose value is not 1:1 with the checkout currency, the merchant converts using rates from an external provider (e.g. the Ax402 control plane's `/exchange-rates`) and **locks the converted asset amount in the signed offer**, together with the rate source and the timestamp the rate was fetched/established. The agent sees the full quote (checkout-currency total, asset, converted amount, rate, rate source, rate timestamp) inside the offer extension and can verify or reject it before signing. Slippage risk between quote and settlement is merchant-owned within the quote window. See `03-amount-semantics.md`.

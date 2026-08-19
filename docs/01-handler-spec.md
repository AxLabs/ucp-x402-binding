# The `org.x402` UCP Payment Handler Spec (B1)

Status: pre-draft. Everything normative here is a proposal by AxLabs until adopted.

## 1. Position in UCP discovery

UCP discovery is `GET /.well-known/ucp` returning a profile. The relevant section:

```json
{
  "ucp": {
    "payment_handlers": {
      "org.x402.crypto": {
        "id": "org.x402.crypto",
        "version": "1.0",
        "spec": "https://github.com/AxLabs/ucp-x402-binding",
        "schema": "https://github.com/AxLabs/ucp-x402-binding/blob/main/schema/handler.schema.json"
      }
    }
  }
}
```

The four base fields (`id`, `version`, `spec`, `schema`) are exactly what UCP defines today. We add one optional UCP-legal extension object, `x402`, carrying what a buying agent needs to decide whether it can pay here. Nothing else.

## 2. Handler entry fields

| Field | Required | Type | Purpose |
|---|---|---|---|
| `id` | yes | string | `org.x402.crypto` (reverse-domain, x402 Foundation namespace) |
| `version` | yes | string | Handler spec version, semver |
| `spec` | yes | URL | Human-readable spec document |
| `schema` | yes | JSON Schema URL | Machine-readable schema for the extended fields |
| `x402.networks` | yes | array of CAIP-2 chain ids | Networks the merchant accepts for settlement. Any namespace allowed (`eip155:8453`, `solana:5eykt4UsFv8P8NJdTREpY1vzqKqZKvdp`, `bip122:...`); support for a namespace is between merchant and facilitator |
| `x402.assets` | yes | array of objects | Settlement assets, each `{network, asset, decimals, symbol?}`. The `asset` identifier is chain-specific: EVM = `0x`+40 hex, SVM = base58 mint pubkey, others = the notation defined by the x402 scheme binding for that network. Schema enforces the shape per-asset via conditional rules |
| `x402.maxAmount` | no | string (base units) | Ceiling for a single payment, base units. Lets agents avoid wasting a signature on out-of-range quotes. |
| `x402.quoteWindow` | no | integer seconds | How long a checkout total is locked once quoted (default 600) |
| `x402.schemes` | no | array of open strings | Accepted x402 payment schemes in preference order. Open registry: today `exact`, `upto`, `batch-settlement`; new schemes land in x402 over time. Consumers MUST ignore unrecognized ids. Not an enum: closing it would break forward compatibility |

### Design rationale

**No facilitator URL. Ever.** The facilitator is merchant-side configuration. The agent never learns which facilitator sits behind the merchant, and the binding works identically with Ax402, CDP, Prism, or any compliant facilitator. This is rule #1 and non-negotiable.

**Networks before assets.** An agent with a wallet on Base answers the network question first; asset selection comes second. Network ids are full CAIP-2 (`namespace:reference`), not just `eip155:<chain-id>`: the binding is chain-agnostic by design, and any namespace the merchant's facilitator supports is legal. Which namespaces are actually supported is merchant + facilitator concern, invisible to the agent in discovery.

**Asset identifiers are chain-native.** EVM assets are `0x`+40 hex contract addresses; Solana assets are base58 mint pubkeys; other chains use whatever notation their x402 scheme binding defines. The JSON Schema enforces the shape per-asset with conditional (`if/then`) rules keyed on the CAIP-2 namespace, and is deliberately lenient for namespaces it does not know: unknown chains pass shape-validation and are governed by their scheme binding. The rules are also versioned: when x402 adds a network binding, the schema grows a matching conditional rule.

**Amounts in base units, always.** `"135500000"` = 135.50 USD in 6-decimal USDC. Never decimals. Matches x402 core.

**`payTo` intentionally absent from discovery.** The `payTo` address is per-offer and delivered in the 402 challenge, signed by the merchant. It does not belong in discovery, where it would invite address-poisoning and spam discrimination.

**Compatible by construction with `xyz.fd.prism_payment`.** Their handler advertises Prism-specific fields. A merchant running their plugin could mint a `org.x402` entry alongside with no conflict; Prism itself can sit behind the neutral handler later. That is a stated goal, not a threat.

## 3. `schema/handler.schema.json`

See the JSON Schema in this repo. It validates the four UCP base fields plus the `x402` object. The schema is deliberately minimal: anything the buying agent does not need to select a payment method is out of scope.

## 4. Open questions

1. Handler id: `org.x402.crypto` vs `org.x402.payments` vs plain `org.x402`. Leaning `org.x402.crypto` for clarity that this is the crypto-rail handler, leaving room for future stablecoin-specific or chain-specific handlers.
2. Should `assets` entries carry a `verified` flag (issuer allow-list reference)? Deferred to working-group discussion.
3. Single `maxAmount` vs per-asset ceilings. Leaning per-asset in v2, single in v1 for simplicity.
4. Conditional asset-shape rules: the schema currently knows `eip155` (0x+40 hex) and `solana` (base58 32-44). Each new x402 network binding should contribute its rule when adopted. Question for the working group: maintain the registry in the schema vs a separate per-network schema registry the handler schema references.
5. `bip122` assets: Bitcoin's native asset has no contract address. Whether `asset` is the genesis hash, empty, or omitted for native assets needs a decision if/when an x402 bip122 scheme binding exists.

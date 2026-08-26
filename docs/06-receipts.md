# Receipts (B7)

Status: pre-draft.

## 1. Offer and receipt, from the x402 offer-and-receipt extension

The x402 offer-receipt extension defines two merchant-signed artifacts (EIP-712, chainId hardcoded to 1 since these are off-chain commitments, or JWS for non-EVM):

- **Signed offer**, delivered in the 402 challenge next to `accepts[]`/`PaymentRequired`: payload `{version, resourceUrl, scheme, network, asset, payTo, amount, validUntil?}`. Simplest signer authorization: the `payTo` key signs.
- **Signed receipt**, returned in the SettlementResponse extensions: payload `{version, network, resourceUrl, payer, issuedAt, transaction?}`. Deliberately privacy-minimal: no amount, no order id.

This binding uses both as specified, no changes:

1. The signed offer is the **price lock** at the 402-at-complete seam (see `02-wire-binding.md`). The agent verifies it before signing the irreversible EIP-3009 transfer.
2. The signed receipt is the **portable proof of purchase**: verifiable by anyone, usable as dispute evidence, input for reputation systems (the extension's stated use cases).
3. `resourceUrl` binds both artifacts to the UCP checkout session URL, making them order-scoped without any UCP schema change.

## 2. Why the receipt matters for UCP specifically

UCP's Order capability tells the agent what the merchant says about an order. The signed receipt is what the agent can **verify independently**: the merchant signed it, it references the session, the tx hash is on-chain. Two different trust anchors, one artifact.

## 3. The gap, and the follow-up proposal

The receipt payload has no amount and no order id. For UCP order flows, a buyer agent wants to prove "I paid 135.50 for order #1001", not just "I paid something at this URL". That is a small extension of the extension: add optional `amount` and `orderId` fields to the receipt payload.

Plan: ship v1 of the binding with the receipt as-is (privacy-minimal is a feature for some merchants), and submit the **receipt order-binding** as a follow-up proposal to the x402 Foundation (it is protocol-level, not UCP-level). v1 merchants MAY already include order metadata in the settlement response body; the signed receipt stays minimal.

## 4. Verification guidance (agent-side)

Agents SHOULD verify, in order:

1. Receipt signature is by the `payTo` key from the challenge they answered.
2. `resourceUrl` equals the resource that was actually paid: in the ideal era the session's complete URL; in the adapter era the challenge's `resource.url` (the gateway URL). The UCP order binding comes from the session id carried by the reconcile `complete` call, not from the receipt's `resourceUrl`.
3. `payer` equals their own address.
4. `transaction` resolves on the advertised network to a transfer of the offered amount to `payTo`.
5. `issuedAt` is sane (not before the offer, not in the future).

Failure at any step: keep the artifacts, do not mark the purchase complete locally, surface to the user.

# st0x.attest

Sign and timestamp an HTTP API response so it can be verified on any EVM chain.

A signer fetches a response, checks it hard, converts the values it cares about
into 32-byte EVM words, and signs those words. A contract recovers the signer
with `ecrecover` and gets Rain Floats it can do arithmetic on. No JSON is parsed
on chain, no strings cross the boundary, and nothing in the signed preimage
names a chain.

Operators do not coordinate at runtime — no peer networking, no shared state,
no consensus round, no shared secret, no threshold scheme. Each answers a
request independently and returns a standalone signature. The party doing the
minting is the coordinator: it asks each operator separately and assembles the
bundle it submits.

Requiring several signatures buys one thing: **no single compromise yields a
valid mint.** That needs operators whose keys aren't reachable from one
another's infrastructure, which a small allowlisted set of contracted
organisations satisfies. It does not need an open or permissionless signer set,
and a rate limit — not the signer set — is what bounds the loss if the minimum
is met dishonestly. See `SPEC.md` §2.1 and §2.2.

**Deciding whether those signatures agree is deliberately not part of this
format.** There is no median, no mean, no unanimity rule and no required
aggregation. A consumer can take any signed value and check the others fall
within a tolerance of it — cheaper than sorting, and it doesn't stall on
ordinary noise. Leaving it open is what lets the policy live in a Rainlang
expression or a governed parameter, where it can change without redeploying
anything. See `SPEC.md` §7.4.

## Status

Specification only. No implementation yet.

- [`SPEC.md`](SPEC.md) — the core attestation format: word layout, preimage,
  signature encoding, value transforms, the gate, and the verifier contract.
- [`ALPACA.md`](ALPACA.md) — the first profile, pinning the Alpaca stock market
  data API: endpoint, schema, per-field transforms and reject conditions.

## Shape of it

```
w0     ENVELOPE     keccak256("st0x.attest.v1")
w1     PROFILE      keccak256(<profile id>)
w2     URL_HASH     keccak256(request URL, query string included)
w3     SIGNED_AT    uint256 unix seconds, signer's clock
w4     BODY_HASH    keccak256(raw response body)
w5..wN VALUES       profile-defined, one word each

inner  = keccak256(w0 ‖ w1 ‖ … ‖ wN)
digest = keccak256("\x19Ethereum Signed Message:\n32" ‖ inner)
```

Every member is a static 32-byte type, so the preimage is a plain
concatenation. Neither side needs an ABI encoder.

## What it proves

That the holder of a key asserts that a URL returned a body from which these
values follow, at a time they state themselves.

It does not prove the API said it. TLS produces nothing transferable to a third
party, so a signer who wants to lie can. The defence is several independent
signers, which is a social guarantee rather than a cryptographic one. Size the
quorum accordingly, and read section 2 of the spec before relying on this.

## Two things that decide whether it works

**Never let a float touch the pipeline.** Most JSON libraries, `serde_json`
included, parse numbers into `f64` by default. Two honest signers can then
produce different words from byte-identical input, and the quorum silently
never forms. Take the raw digit string and scale it to an integer yourself.

**Only attest to observations that are fixed by their URL.** An endpoint
meaning "the latest thing right now" is a function of when you called it, so
two signers milliseconds apart see different facts and never agree. Attest to
closed historical intervals or explicit sequence numbers instead.

## Licence

[DecentraLicense 1.0](LICENSE) (`LicenseRef-DCL-1.0`).

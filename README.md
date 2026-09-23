# st0x.attest

Sign and timestamp an HTTP API response so it can be verified on any EVM chain.

A signer fetches a response, checks it hard, converts the values it cares about
into 32-byte EVM words, and signs those words. A contract recovers the signer
with `ecrecover` and gets typed `uint256`s. No JSON is parsed on chain, no
strings cross the boundary, and nothing in the signed preimage names a chain.

Uncoordinated parties can each run this without talking to each other. There is
no registry, no ceremony, no shared secret and no threshold scheme. Every signer
emits a standalone signature; deciding how many of them to believe is the
consuming contract's job.

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

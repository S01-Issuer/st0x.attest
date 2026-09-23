# st0x.attest

Sign and timestamp an HTTP API response so it can be verified on any EVM chain.

A signer fetches a response, checks it, converts the values it cares about into
32-byte EVM words, and signs those words. A contract recovers the signer with
`ecrecover` and gets Rain Floats it can do arithmetic on. No JSON is parsed on
chain, no strings cross the boundary, and nothing in the signed preimage names
a chain.

Operators do not coordinate at runtime. Each answers a request independently
and returns a standalone signature. The party doing the minting is the
coordinator: it asks each operator separately and assembles the bundle it
submits.

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
values follow, at a time they state themselves. See `SPEC.md` §2 for what it
does not prove.

## Licence

[DecentraLicense 1.0](LICENSE) (`LicenseRef-DCL-1.0`).

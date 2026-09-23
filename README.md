# st0x.attest

Sign an HTTP API response so a contract can verify it on chain.

## Status

**Nothing here is decided.**

- [`SPEC.md`](SPEC.md) §1 is what was asked for. §2 lists the decisions that
  still have to be made. Everything after that is a proposal written to be
  argued with.
- [`ALPACA.md`](ALPACA.md) separates verified facts about the Alpaca Market
  Data API, transcribed from its OpenAPI source, from proposals about how to
  use it. Its §9 lists what Alpaca's documentation does not settle and what
  has to be measured.

## What was asked for

A Rust binary that signs and timestamps an HTTP API response so it verifies on
any EVM chain, with no JSON decoded on chain — the binary transforms the
response into signed EVM words, checks it first, and refuses to sign anything
it does not recognise. The API is Alpaca stock pricing.

A contract accepts a list of signed values and compares them numerically. There
is no aggregation: a consumer may take any of the signed values and accept it
if the others agree within a deviation, given a required number of values, both
set by the mint admin rather than fixed here.

Operators do not coordinate at runtime. Each answers a request independently
and returns a standalone signature. The party doing the minting is the
coordinator: it asks each operator separately and assembles the bundle it
submits.

The operators are a pool of N with a threshold of M < N, all equally difficult
to compromise, so one being down does not stop minting. One is the lead, whose
attestation is mandatory because it is the entity legally issuing the tokens;
the others are redundancy against the lead being compromised and do not
substitute for it.

`SPEC.md` §1 has the full list.

## Licence

[DecentraLicense 1.0](LICENSE) (`LicenseRef-DCL-1.0`).

# st0x.attest

The requirements as stated.

## 1. The binary

1. A Rust binary that uncoordinated parties can run to sign and timestamp an
   HTTP response from an API, verifiable on an EVM chain, chain agnostic.
2. No JSON decoded on chain. The binary transforms the response into signed EVM
   words and integrity-checks it before it signs. It refuses to sign weirdness.
3. The API is Alpaca stock pricing.

## 2. The on-chain check

4. A contract accepts a list of signed values and checks their equality on
   chain.
5. No aggregation is needed. Take any of the signed values, provided all the
   values are within a certain range of each other and there is a certain
   number of signed values — a 1%, 2% or 5% deviation, for example. This is for
   a leaky bucket and does not have to be exact. The mint admin decides how to
   set those limits. It is not predetermined.

## 3. The operators

6. The parties are uncoordinated in that they do not coordinate requests
   between each other. Whoever is doing the minting coordinates between the
   different parties, so there is no coordination at runtime. The parties are
   aware of each other in that there is some redundancy.
7. It does not need to be fully decentralised. What is needed is orthogonal
   operators — independent organisations that are not expected to be
   compromised at the same time — so that a compromise of the main ST0x or S01
   Issuer account does not grant minting. The requirement is redundancy in the
   case of the lead being compromised.
8. The operators are a pool, with the mint collecting a threshold M smaller
   than the pool — ten attestors with the mint needing three, for example.
   Setting M at the full set would mean one attestor being down stops the mint.
   All the attestors should be equally difficult to compromise. As many
   additional signers as wanted may be added for availability redundancy, and
   the minter does not have to contact all of them.
9. The lead is mandatory. S01 is the issuer, the entity legally issuing the
   share tokens and minting them. The other entities are not legally
   responsible.
10. To reach the signing threshold and make it possible to raise the mint cap,
    an attacker would have to compromise the signatory that does the requesting
    and the minting, **and** the lead, which is the S01 signer on the price
    feeds, **and** at least M of the individual signers.

## 4. The orchestrator

These concern the mint caps in `st0x.deploy`, not the binary above.

11. In place of global and per-token mappings holding raw token amounts, a
    Rainlang conversion between whatever inputs are needed — such as signed
    context, which could include prices — and the token amounts provided in the
    context. The Rainlang converts between the token amounts to produce a
    weighting, and the weighting is what increases the leaky bucket.
12. The per-token mappings are then not needed. Only a single global limit per
    address is needed, because the weightings can contribute towards the global
    limit in whatever way is wanted, and the signed context can be provided by
    different attestors.
13. Whether it is a median, what the aggregation logic is, and which oracle
    things come from do not have to be predetermined, because the mint admin
    sets them in the Rainlang itself. Deploying different algorithms and
    weightings is then something governance handles, without rewriting the
    smart contract logic.
14. The leaky bucket logic converts from Rain fixed point to Rain Floats.
15. Two storage slots is acceptable. Typical mints can be large — an incoming
    OTC mint requesting $2 million in a single mint — so the gas difference
    between one slot and two is irrelevant.
16. Zero values are not accepted. The leaky bucket library already rejects
    them.

## Licence

[DecentraLicense 1.0](LICENSE) (`LicenseRef-DCL-1.0`).

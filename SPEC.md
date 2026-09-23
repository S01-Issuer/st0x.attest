# st0x.attest

The requirements as stated.

## 1. The binary

1. A Rust binary that uncoordinated parties can run to sign and timestamp an
   HTTP response from an API, verifiable on an EVM chain, chain agnostic.
2. No JSON decoded on chain. The binary transforms the response into signed EVM
   words and integrity-checks it before it signs. It refuses to sign weirdness.
3. The API is Alpaca stock pricing.

## 2. The on-chain check

4. The on-chain check is a Rainlang expression. It takes the values available
   in context — such as signed context, and the token input amount being
   requested for minting — and converts them into a weighting, or potentially
   reverts.
5. What that expression checks is up to the mint admin, and there are many
   possible. Taking any of the signed values provided they are all within a
   certain range of each other, with a certain number of signed values and a
   1%, 2% or 5% deviation, is one expression a mint admin could write. It is an
   example of what is possible, not the required check.
6. No aggregation is required. Whether it is a median, what the aggregation
   logic is, and which oracle things come from do not have to be predetermined,
   because the mint admin sets them in the Rainlang itself.
7. A Rainlang subparser is included, so that expressions do not have to use
   awkward signed context positions.
8. Two words are added to Rainlang, because the `ensure` forms are awkward
   without them.
   - `in`, so an expression can say that a signer is in a list. One list at a
     time for the first implementation; two lists are possible later.
   - `unique`, to assert that all of the values passed to it are unique.
9. An `agree` word is added to Rainlang, because the tolerance logic is awkward
   too. It takes the tolerance as its first argument, as a fractional limit,
   and then all of the subsequent values. It checks the highest and the lowest,
   and makes sure the highest and the lowest are no more than the tolerance
   apart from each other.

### Example rendering of the item 5 expression

How the example in item 5 would look written out, using the subparser from item
7 and the words from items 8 and 9. It is one expression a mint admin could
write, not the required check. The subparser word names below are
illustrative; they are not decided.

```rainlang
#lead-signer !The mandatory lead signer, S01 as issuer.
#operator-1 !An allowlisted pool operator.
#operator-2 !An allowlisted pool operator.
#max-deviation !Fractional limit on how far apart the attested values may be. 0.01 is 1%.

#weighting
using-words-from st0x-attest-subparser

/* The lead is mandatory. Attestation 0 must come from the issuer's signer. */
:ensure(
  equal-to(attestor<0>() lead-signer)
  "Lead attestation missing"
),

/* Pool operators. This example collects M = 2 from the allowlist. */
:ensure(
  in(attestor<1>() operator-1 operator-2)
  "Attestor 1 not an allowlisted operator"
),
:ensure(
  in(attestor<2>() operator-1 operator-2)
  "Attestor 2 not an allowlisted operator"
),

/* No operator fills more than one seat, the lead included. */
:ensure(
  unique(attestor<0>() attestor<1>() attestor<2>())
  "Same operator twice"
),

/* The price each of them attested, by name rather than by position. */
lead-price: attested-price<0>(),
price-1: attested-price<1>(),
price-2: attested-price<2>(),

/* Highest and lowest no more than max-deviation apart. */
:ensure(
  agree(max-deviation lead-price price-1 price-2)
  "Attestors disagree"
),

/* Any of the values may be taken once they agree. This takes the lead's and
 * weights the requested mint amount by it. */
weighting: mul(mint-amount() lead-price);
```

## 3. The operators

10. The parties are uncoordinated in that they do not coordinate requests
    between each other. Whoever is doing the minting coordinates between the
    different parties, so there is no coordination at runtime. The parties are
    aware of each other in that there is some redundancy.
11. It does not need to be fully decentralised. What is needed is orthogonal
    operators — independent organisations that are not expected to be
    compromised at the same time — so that a compromise of the main ST0x or S01
    Issuer account does not grant minting. The requirement is redundancy in the
    case of the lead being compromised.
12. The operators are a pool, with the mint collecting a threshold M smaller
    than the pool — ten attestors with the mint needing three, for example.
    Setting M at the full set would mean one attestor being down stops the mint.
    All the attestors should be equally difficult to compromise. As many
    additional signers as wanted may be added for availability redundancy, and
    the minter does not have to contact all of them.
13. The lead is mandatory. S01 is the issuer, the entity legally issuing the
    share tokens and minting them. The other entities are not legally
    responsible.
14. To reach the signing threshold and make it possible to raise the mint cap,
    an attacker would have to compromise the signatory that does the requesting
    and the minting, **and** the lead, which is the S01 signer on the price
    feeds, **and** at least M of the individual signers.

## 4. The orchestrator

These concern the mint caps in `st0x.deploy`, not the binary above.

15. The weighting produced by the Rainlang in section 2 is what increases the
    leaky bucket, in place of global and per-token mappings holding raw token
    amounts.
16. The per-token mappings are then not needed. Only a single global limit per
    address is needed, because the weightings can contribute towards the global
    limit in whatever way is wanted, and the signed context can be provided by
    different attestors.
17. Deploying different algorithms and weightings is then something governance
    handles, without rewriting the smart contract logic.
18. The leaky bucket logic converts from Rain fixed point to Rain Floats.
19. Two storage slots is acceptable. Typical mints can be large — an incoming
    OTC mint requesting $2 million in a single mint — so the gas difference
    between one slot and two is irrelevant.
20. Zero values are not accepted. The leaky bucket library already rejects
    them.

## Licence

[DecentraLicense 1.0](LICENSE) (`LicenseRef-DCL-1.0`).

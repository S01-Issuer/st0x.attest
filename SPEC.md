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
   awkward signed context positions. It specifies `lead`, `attestor` and
   `lead-price` as words.
8. Two words are added to Rainlang, because the `ensure` forms are awkward
   without them.
   - `in`, so an expression can say that a signer is in a list. The operand
     specifies how many of the inputs are the things being checked: the first
     that many values are those things, and all subsequent values are the set
     they must be in. One list at a time for the first implementation; two
     lists are possible later.
   - `unique`, to assert that all of the values passed to it are unique.
9. An `agree` word is added to Rainlang, because the tolerance logic is awkward
   too. It takes the tolerance as its first argument, as a fractional limit,
   and then all of the subsequent values. It checks the highest and the lowest,
   and makes sure the highest and the lowest are no more than the tolerance
   apart from each other.
10. An absolute variant, `agree-absolute`, sets a number — seconds, or any
    other absolute value — that the values all have to agree within, rather
    than a proportional limit. Timestamps use it: the attested times have to
    agree within some threshold, and the lead time is then the timestamp used.
11. The expression checks the token symbol, so an attestation for one token
    cannot be used for a mint of another.
12. `equal-to` accepts more than two inputs, all of which have to be equal. It
    currently requires exactly two.
13. The expression checks the attested price against absolute minimum and
    maximum bounds. Attestors agreeing with each other does not catch a price
    they all got wrong.
14. The ordering comparisons are variadic the same way, following Clojure's
    `<`: each argument is compared to the next, so
    `less-than-or-equal-to(a b c)` holds when `a <= b <= c`. The bounds check
    is then a single call with the minimum first and the maximum last, and no
    new word is needed for it.
15. Signed context moves off the hash library and onto EIP-712 signed data,
    and the hash library is removed. This is in scope alongside the word
    changes above, since both modify Rainlang.
    `rainlanguage/rain.interpreter.interface` #133 already tracks it:
    `SignedContextV2` with a caller-chosen domain and `hashStruct` over the
    context words, replacing `personal_sign` over
    `LibHashNoAlloc.hashWords`.

### Example rendering of the item 5 expression

How the example in item 5 would look written out, using the subparser from item
7 and the words from items 8 to 14. It is one expression a mint admin
could write, not the required check. `lead`, `attestor` and `lead-price` are
the words from item 7; `attested-price`, `lead-time`, `attested-time`,
`lead-symbol`, `attested-symbol`, `mint-symbol` and `mint-amount` are
illustrative and not decided.

```rainlang
#lead-signer !The mandatory lead signer, S01 as issuer.
#operator-1 !An allowlisted pool operator.
#operator-2 !An allowlisted pool operator.
#operator-3 !An allowlisted pool operator.
#operator-4 !An allowlisted pool operator.
#operator-5 !An allowlisted pool operator.
#operator-6 !An allowlisted pool operator.
#max-deviation !Fractional limit on how far apart the attested values may be. 0.01 is 1%.
#max-time-spread !How far apart the attested times may be, in seconds.
#min-price !Absolute floor on the attested price.
#max-price !Absolute ceiling on the attested price.

#weighting
using-words-from st0x-attest-subparser

/* The lead is mandatory. */
:ensure(
  equal-to(lead() lead-signer)
  "Lead attestation missing"
),

/* Both pool attestations must come from the allowlist. The pool is six and the
 * mint collects two, so any four operators can be down without stopping it. */
:ensure(
  in<2>(
    attestor<0>() attestor<1>()
    operator-1 operator-2 operator-3 operator-4 operator-5 operator-6
  )
  "Attestor not an allowlisted operator"
),

/* No operator fills more than one seat, the lead included. */
:ensure(
  unique(lead() attestor<0>() attestor<1>())
  "Same operator twice"
),

/* Every attestation is for the token being minted. */
:ensure(
  equal-to(
    lead-symbol() attested-symbol<0>() attested-symbol<1>()
    mint-symbol()
  )
  "Attestation is for the wrong token"
),

/* The attested times and the chain clock all fall within max-time-spread of
 * each other. */
:ensure(
  agree-absolute(max-time-spread now() lead-time() attested-time<0>() attested-time<1>())
  "Times disagree"
),

/* Highest and lowest no more than max-deviation apart. */
:ensure(
  agree(max-deviation lead-price() attested-price<0>() attested-price<1>())
  "Attestors disagree"
),

/* Absolute bounds on the price that gets used. Agreement between the
 * attestors does not catch a price they all got wrong. The other two are
 * already within max-deviation of this one. */
:ensure(
  less-than-or-equal-to(min-price lead-price() max-price)
  "Price outside bounds"
),

/* Any of the values may be taken once they agree. This takes the lead's and
 * weights the requested mint amount by it. */
weighting: mul(mint-amount() lead-price());
```

## 3. The operators

16. The parties are uncoordinated in that they do not coordinate requests
    between each other. Whoever is doing the minting coordinates between the
    different parties, so there is no coordination at runtime. The parties are
    aware of each other in that there is some redundancy.
17. It does not need to be fully decentralised. What is needed is orthogonal
    operators — independent organisations that are not expected to be
    compromised at the same time — so that a compromise of the main ST0x or S01
    Issuer account does not grant minting. The requirement is redundancy in the
    case of the lead being compromised.
18. The operators are a pool, with the mint collecting a threshold M smaller
    than the pool — ten attestors with the mint needing three, for example.
    Setting M at the full set would mean one attestor being down stops the mint.
    All the attestors should be equally difficult to compromise. As many
    additional signers as wanted may be added for availability redundancy, and
    the minter does not have to contact all of them.
19. The lead is mandatory. S01 is the issuer, the entity legally issuing the
    share tokens and minting them. The other entities are not legally
    responsible.
20. To reach the signing threshold and make it possible to raise the mint cap,
    an attacker would have to compromise the signatory that does the requesting
    and the minting, **and** the lead, which is the S01 signer on the price
    feeds, **and** at least M of the individual signers.

## 4. The orchestrator

These concern the mint caps in `st0x.deploy`, not the binary above.

21. The weighting produced by the Rainlang in section 2 is what increases the
    leaky bucket, in place of mappings holding raw token amounts. The Rainlang
    is what converts amounts into values.
22. The per-token logic is removed from the orchestrator branch. That branch
    has a per-token limit and no limits for recipients. The per-token limit
    goes, and value-based limits per recipient and per minter take its place.
    Only those two are needed; the weightings can contribute towards them in
    whatever way is wanted, and the signed context can be provided by different
    attestors.
23. The corporate action logic is removed from the orchestrator branch
    altogether, since the weighting is value-based.
24. Deploying different algorithms and weightings is then something governance
    handles, without rewriting the smart contract logic.
25. The leaky bucket logic converts from Rain fixed point to Rain Floats.
26. The leaky bucket itself prevents negative numbers once it is on Floats.
27. Two storage slots is acceptable. Typical mints can be large — an incoming
    OTC mint requesting $2 million in a single mint — so the gas difference
    between one slot and two is irrelevant.
28. Zero values are not accepted. The leaky bucket library already rejects
    them.

## Licence

[DecentraLicense 1.0](LICENSE) (`LicenseRef-DCL-1.0`).

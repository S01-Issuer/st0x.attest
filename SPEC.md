# st0x.attest core specification

Version `st0x.attest.v1`.

The key words MUST, MUST NOT, SHOULD, SHOULD NOT and MAY are to be interpreted
as in RFC 2119.

## 1. What this is

A signer fetches an HTTP API response, checks it, converts the values it cares
about into EVM words, and signs those words. Anyone can verify the signature
on any EVM chain with `ecrecover` alone.

**Signers do not coordinate at runtime.** They do not talk to each other, share
state, run a consensus round, elect a leader, agree a nonce, or aggregate
anything. No shared secret, no ceremony, no threshold scheme. Each independently
answers a request and returns a standalone signature over its own words, and
nothing about verification requires two signers to have produced identical
bytes.

**The party doing the minting is the coordinator.** It requests an attestation
from each operator separately and assembles the bundle it submits. An operator
therefore needs no peer networking, no shared state, no knowledge of who else
was asked, and no liveness dependency on any other operator. An attestor is a
stateless request-response service that signs what it observes and returns.

Operators being a known roster is orthogonal to this. Knowing of each other for
redundancy planning is not runtime coordination, and it does not make the
system decentralised in any stronger sense — see 2.1.

Two consequences follow from the minter being the assembler. Availability risk
concentrates there: if an operator cannot be reached, the minter cannot meet a
required minimum and the mint fails, so the minimum is a liveness budget as
much as a security one. And because the minter chooses which attestations to
include, it also chooses which value serves as the reference in any tolerance
check — see 7.4.

Deciding how many attestations to believe, and on what basis, belongs to the
consuming contract and is out of scope here.

## 2. What it proves, and what it does not

An attestation proves exactly one thing: **the holder of private key `k`
asserts that at unix time `T` the URL `U` returned a body from which these
values follow.**

It does not prove:

- that the API actually said it. TLS authenticates the server to the client
  and produces nothing transferable to a third party. A signer that wants to
  lie can lie.
- that `T` is the real time. `T` is the signer's clock, self-reported. See
  section 8.
- that the signer's extraction from the body was honest. Word `w4` (section 4)
  makes a dishonest extraction *demonstrable after the fact*, off chain, by
  anyone holding the raw body. It does not prevent it.

### 2.1 The property that matters is independence, not decentralisation

Requiring several attestations is not a decentralisation measure and does not
need an open or permissionless signer set. The property being bought is that
**no single compromise yields a valid mint**, and it is bought by the signers
being operated by organisations whose keys are not reachable from one another's
infrastructure.

A small, known, allowlisted set of contracted operators satisfies this. An open
set of strangers does not satisfy it any better, and is harder to entitle,
contract and audit.

The signer set therefore SHOULD live in contract storage that the consuming
policy reads, rather than as constants inlined in expression bytecode, so that
who is trusted stays legible on chain and changing it is an observable event.

### 2.2 What co-signing does and does not contain

Consider an attacker holding both the right to mint and the primary attestor's
key — the realistic correlated compromise of one operator.

- They are stopped **only** because the policy requires a minimum number of
  distinct allowlisted attestors and they cannot produce the second signature.
  A policy that accepts one attestation gains nothing from the others existing.
- If that minimum is met dishonestly, they can still mint up to the rate
  limit's remaining headroom at an honest price. **The rate limit, not the
  attestor set, is the loss bound.**
- Co-signers bound how far the *price* can be misstated, to roughly the
  agreement tolerance. They do not bound *quantity* at all.

Those are orthogonal defences and a deployment needs both. Consumers MUST
enforce a minimum count of distinct recovered addresses; see 7.3 step 4.

### 2.3 Corroboration need not match the primary in provenance

A co-signer exists to confirm that the primary's value is not far wrong. It
does not have to observe through the same data source, provided the difference
between sources stays inside the agreement tolerance for the fields being
checked.

This matters because the primary's data entitlement is often the expensive
part. A profile MAY allow co-signers a cheaper or more restricted source, and
MUST then state which value words are comparable across sources and which are
not. See `ALPACA.md` §3.1 for a worked example where prices corroborate within
0.07% across feeds while volume differs by 98%.

## 3. Cryptographic primitives

| Purpose | Primitive | Why |
| --- | --- | --- |
| Hash | `keccak256` | Native to the EVM |
| Signature | secp256k1 ECDSA, recoverable | `ecrecover` at precompile `0x01` |
| Framing | EIP-191 `personal_sign` | Chain agnostic by construction |

`ecrecover` is the only signature verification primitive present on every EVM
chain. BN254 pairings are near-universal but need hash-to-curve and offer
roughly 100-bit security; BLS12-381 (EIP-2537) and secp256r1 (RIP-7212) exist
only on newer chains. Chain agnosticism therefore forces secp256k1.

EIP-712 MUST NOT be used. Its domain separator binds `chainId` and
`verifyingContract`, which is the opposite of the requirement. EIP-191 framing
is used instead, which also prevents a signature being replayed as an Ethereum
transaction.

## 4. Word layout

Every signed field is exactly one 32-byte word. Nothing variable-length ever
crosses into the preimage. Because every type is a static 32-byte type,
`abi.encode` of the tuple is plain concatenation, so no ABI encoder is needed
on either side.

```
w0     ENVELOPE     keccak256("st0x.attest.v1")
w1     PROFILE      keccak256(<profile id string>)
w2     URL_HASH     keccak256(request URL bytes, including query string)
w3     SIGNED_AT    uint256, unix seconds, signer's clock
w4     BODY_HASH    keccak256(raw response body bytes)
w5..wN VALUES       profile-defined, one word each

inner  = keccak256(w0 ‖ w1 ‖ w2 ‖ w3 ‖ w4 ‖ w5 ‖ … ‖ wN)
digest = keccak256("\x19Ethereum Signed Message:\n32" ‖ inner)
sig    = ecdsa_sign_recoverable(k, digest)
```

### 4.1 ENVELOPE

Pins this document. Any change to the word layout, to the transform rules in
section 6, or to the signature encoding in section 5, MUST change the envelope
string. Old signatures then cease to verify under the new rules, which is the
point.

### 4.2 PROFILE

Pins the meaning and arity of `w5..wN`. A profile is a separate document (see
`ALPACA.md`).

`PROFILE` is REQUIRED and MUST NOT be omitted even if only one profile exists.
Without it, two profiles that happen to have the same number of value words
would produce mutually verifiable signatures, and a consumer could be handed an
attestation about one thing and verify it as an attestation about another.

### 4.3 URL_HASH

The full request URL including the query string, hashed. Query parameters
routinely change what the response *means* — a data feed selector, a timeframe,
an adjustment mode — so they MUST be inside the commitment.

This gives consumers a useful lever: a contract that hardcodes an expected
`URL_HASH` constant is a contract that cannot be fed an attestation taken from
a different feed or a different timeframe, without needing to parse anything.

The URL MUST be byte-identical to the one actually requested, MUST be fully
qualified, and MUST NOT contain credentials. Profiles SHOULD pin parameter
order so that independent signers produce identical bytes.

### 4.4 SIGNED_AT

Unix seconds, from the signer's clock. See section 8.

### 4.5 BODY_HASH

`keccak256` over the raw response body exactly as received, before any parsing.

Nothing on chain ever inspects this word. It exists so that a signer's
extraction is falsifiable: if challenged, someone reveals the body, anyone
recomputes the hash, and either it matches and the values can be checked
against it, or the signer is caught. One word, no parser anywhere.

`BODY_HASH` is per-signer provenance and is **not** expected to match across
signers. Two signers fetching the same logical observation will differ in
whitespace, key order, or an embedded server timestamp. Consumers MUST NOT
require `BODY_HASH` to agree across a quorum.

## 5. Signature encoding

65 bytes, `r ‖ s ‖ v`, with `r` and `s` 32 bytes big-endian and `v` one byte.

- `v` MUST be 27 or 28.
- `s` MUST be less than or equal to
  `0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0`
  (the half order of the secp256k1 group).

Verifiers MUST enforce both. These are not ceremony. ECDSA admits two valid
`(r, s)` pairs for one message, so without the low-`s` rule a single signer can
present the same attestation twice under two distinct encodings, and an M-of-N
quorum that deduplicates on the signature bytes rather than the recovered
address can be satisfied by one party. Verifiers MUST also reject a recovered
address of `address(0)`.

## 6. Transforming values into words

### 6.1 The rule

Each extracted field MUST map into exactly one 32-byte word, and the mapping
MUST be total and injective. Two distinct field values MUST NOT produce the
same word.

Envelope words `w0..w4` are raw `bytes32` and `uint256`, because they are
consumed by the verifier contract itself rather than by on-chain math. Profile
value words `w5..wN` carry numbers as **Rain Floats**, matching what Rainlang
strategies and the rest of the ST0x oracle stack already read.

| Source | Word |
| --- | --- |
| Decimal number | Rain Float, section 6.3 |
| Integer | Rain Float with exponent 0, range-checked |
| Boolean | Rain Float 0 or 1 |
| Enumerated string | Rain Float via a closed match; unknown variant aborts |
| Free string | `keccak256` of its bytes, so length never matters |
| Hex address | `address`, checksum verified when the source is checksummed |
| RFC 3339 timestamp | Rain Float, whole unix seconds, section 6.4 |

A free string MUST NOT be truncated or padded into a `bytes32`. Hash it.

A Rain Float is `bytes32`: a signed `int32` exponent in the high 32 bits and a
signed `int224` coefficient in the low 224 bits, with value
`coefficient × 10^exponent`. Representations are non-canonical by design —
`(5, 0)`, `(50, -1)` and `(5000, -3)` all equal 5 and pack differently — which
section 7 addresses by comparing numerically rather than by byte.

### 6.2 No floating point, anywhere

No IEEE-754 value may exist anywhere between the response bytes and the word.

This is not stylistic. Most JSON libraries parse numbers into `f64` by default,
including `serde_json`. Values beyond 2^53, and ordinary decimal fractions that
have no exact binary representation, can round differently across platforms and
library versions. The result is two honest signers producing different words
from byte-identical input, a quorum that silently never forms, and a fault that
looks like a networking problem.

Implementations MUST obtain the raw digit string — `serde_json`'s
`arbitrary_precision` or `raw_value` feature, or equivalent — and convert it as
in 6.3.

The numeric comparison in section 7 does not relax this rule. Comparing Floats
numerically absorbs *representation* divergence: two signers encoding the same
number as `(5, 0)` and `(50, -1)` still agree. It does nothing about *value*
divergence: two signers whose float paths produced genuinely different numbers
compare unequal and the quorum correctly fails to form. A helper that routes a
JSON number through `f64` before parsing produces the second kind, and no
amount of on-chain comparison recovers it.

### 6.3 Decimal to Rain Float

Given source string `s`, taken verbatim from the wire per 6.2:

1. `s` MUST match `^-?(0|[1-9][0-9]*)(\.[0-9]+)?$`. This rejects a leading `+`,
   leading zeros, a bare trailing `.`, and exponent notation.
2. Parse `s` into a Rain Float by exact decimal arithmetic. The 224-bit signed
   coefficient carries roughly 67 significant digits, so any precision an HTTP
   API realistically emits is represented exactly.
3. If the value does not fit the coefficient or exponent range, **abort**.
   MUST NOT truncate or round. Silent precision loss is a signed falsehood.

Implementations MUST NOT force the result to a target exponent.
`withTargetExponent` truncates when it shrinks a coefficient, so
canonicalising by pinning an exponent reintroduces exactly the precision loss
step 3 forbids. Whatever representation exact parsing produces is the
representation that gets signed, and section 7 makes that safe.

Trailing zeros in the source are accepted. `181.18` and `181.180` may encode to
different `bytes32`, and that is not a divergence risk because agreement is
numeric — see 7.1.

Exponent notation is legal JSON and is rejected deliberately. An API that
begins emitting `1.8118e2` MUST break the signer loudly rather than be
mis-parsed quietly.

### 6.4 Timestamps in values

A timestamp signed from the response body is a Rain Float carrying **whole
unix seconds**, matching every signed timestamp in the ST0x oracle stack so
that a consumer never has to reconcile units across sources.

The parser MUST require the `Z` suffix and reject numeric UTC offsets, so that
two signers cannot disagree about the same instant. Sub-second precision MUST
abort rather than truncate, per 6.3 step 3. A profile whose observations do not
land on whole seconds MUST say so and declare its own unit explicitly.

Profiles MUST NOT assume the fractional-seconds component is fixed width, and
MUST accept its complete absence. RFC 3339 emitters commonly trim trailing
zeros — Go's `RFC3339Nano` does — so the same field can arrive with nine
digits, with eight, or with no decimal point at all. A parser MUST normalise by
right-padding to the declared unit rather than by slicing at a fixed offset.

## 7. Determinism and convergence

Uncoordinated signers can only form a quorum if they independently produce
identical value words. Two rules make that possible.

### 7.1 The value words MUST be a pure function of the raw body

`w5..wN` MUST depend on nothing but the response bytes and the profile. No
local clock, no locale, no environment, no IEEE-754, no retry state. Two
conforming signers handed the same body MUST produce **numerically equal**
values.

Numerically equal, not byte-identical. Signers are uncoordinated, so they may
run different builds pinned to different Rain Float library versions, and two
such builds may encode the same number under different `(coefficient,
exponent)` pairs. Requiring byte equality would make the quorum brittle against
version skew that no participant can observe or control. Consumers therefore
compare with `LibDecimalFloat.eq`, which rescales before comparing.

That comparison is exact. `compareRescale` grows the larger-exponent
coefficient rather than shrinking the smaller one, so it truncates nothing; it
detects overflow and saturates to unequal; exponent gaps beyond 76 saturate
likewise; and it skips rescaling altogether when the exponents already match,
which is the common case.

`SIGNED_AT`, `BODY_HASH`, the exact Float encodings and the signature are the
parts that legitimately differ between signers observing the same thing.

### 7.2 A profile MUST target a URL-addressed, immutable observation

This is the rule that decides whether the whole scheme works.

An endpoint meaning "the latest thing right now" is a function of *when you
called it*, not of its URL. Two uncoordinated signers calling it milliseconds
apart observe different facts, produce different words, and never form a
quorum — and the failure is intermittent and load-dependent, which is the worst
way to find out.

A profile MUST therefore address an observation that is fixed by the URL
itself: a closed historical interval, an explicit sequence number, a settled
identifier. Where the upstream data can still be revised after publication, the
profile MUST declare a settlement delay and MUST require signers to observe
only intervals older than it.

### 7.3 Forming a quorum

A consumer takes a list of attestations, recovers each independently, and then
decides whether they agree. Nothing about verification requires them to be
byte-identical — each signature covers that signer's own words.

1. Recover each attestation per section 11. Reject any that fails.
2. Require `ENVELOPE` and `PROFILE` to match the expected constants by byte,
   and `URL_HASH` to match whatever the consumer pins.
3. Require each `SIGNED_AT` to be within the consumer's freshness window of
   `block.timestamp`.
4. **Deduplicate on the recovered address, check it against the allowlist, and
   require a minimum count.** All three are REQUIRED.
   - A signer can legitimately produce two valid signatures over the same
     value under two different Float encodings, and both would pass a numeric
     agreement check. A consumer deduplicating on words, on `inner`, or on
     signature bytes can therefore let one party fill several seats.
     Deduplicating on the recovered address is the only sound rule.
   - The recovered address MUST be checked against the allowlisted operator
     set. Recovery alone proves a key signed, not that anyone trusts it.
   - The count of distinct allowlisted addresses MUST meet a configured
     minimum, and that minimum MUST be greater than one wherever the point of
     the exercise is surviving a single operator's compromise. This is the
     step that does the work; see 2.2.
5. Decide whether the surviving attestations agree. **How is out of scope for
   this specification** — see 7.4.

Steps 1 to 4 are envelope-level and are REQUIRED of every consumer. Step 5 is
the consumer's policy.

### 7.4 Agreement is the consumer's, not the format's

This specification defines no aggregation. It does not pick a median, a mean or
a unanimity rule, and a conforming consumer is not required to aggregate at
all.

Aggregation is usually unnecessary. A consumer that needs a number only good
enough for its purpose can take **any** of the signed values and check that the
others agree with it within a tolerance. A few percent is often ample for a
rate limit or a bound. That is `n - 1` comparisons and no sorting, against a
median's ordering pass, and it degrades gracefully where a unanimity rule
stalls on ordinary noise — including the bar restatement in the Alpaca
profile's open question 9.1.

Two things a consumer choosing that pattern should know.

**The tolerance is a leakage budget, not a precision parameter.** Whoever
submits the attestations chooses which one is the reference, so they will pick
the most favourable value inside the band every time. A 5% tolerance does not
mean "attestors agree to within 5%", it means "anyone may have up to 5% of
whatever this number protects". Size it on that basis, which is a tighter
constraint than reasoning from expected attestor noise would suggest.

**Deviation from a reference is not spread.** Requiring every value within X%
of one reference permits a total spread approaching 2X, since one value may sit
X below the reference and another X above. Bound `max - min` instead if the
spread itself is what matters.

Whatever the rule, comparisons MUST go through `LibDecimalFloat`. A Float's
exponent occupies the high 32 bits as a two's-complement `int32`, so a negative
exponent reads as an enormous unsigned value: a raw `bytes32` or `uint256`
comparison orders Floats incorrectly while looking entirely plausible on
review.

Leaving this open is what lets the policy live somewhere it can be changed — a
Rainlang expression, a governed parameter — rather than in a redeployment of
whatever contract consumes attestations.

## 8. On the timestamp

`SIGNED_AT` is a claim, enforced only by the consuming contract comparing it to
`block.timestamp` at submission and rejecting anything staler than its own
freshness window.

Nothing stronger is worth building. RFC 3161 timestamp tokens are RSA and are
not verifiable on the EVM at sane cost. Anchoring to a block hash pins the
attestation to one chain and destroys the chain-agnosticism requirement. More
importantly, **a timestamp can never be more trustworthy than the attestation
it is attached to**: a signer willing to lie about the response body is
willing to lie about their clock, and the scheme already depends on them not
doing the former. Spend the effort on the number of independent signers.

Where the response body itself carries an authoritative timestamp from the data
source, a profile SHOULD sign that as a value word. It is a far stronger signal
than `SIGNED_AT` and it is the one a consumer should generally gate on.

## 9. The gate

All of the following MUST pass, in order, before a single byte is signed. Every
failure is terminal.

1. **Transport.** TLS certificate validated against the system roots. Host
   pinned. Redirects to a different host MUST be refused; profiles SHOULD
   refuse redirects entirely. A bounded connect and read timeout.
2. **Status.** Exactly `200`. Not "2xx" — `204` carries no body and `206` is a
   fragment, and both are bugs here.
3. **Content type.** `application/json`, tolerating a charset parameter.
4. **Size.** Read with a byte cap applied *during* the read. Reading first and
   checking afterwards is a denial of service against the signer.
5. **Strict decode.** Unknown fields MUST be rejected — `deny_unknown_fields`
   on every struct. No defaults, no optional-by-accident fields. An upstream
   API that adds a field in a minor release MUST stop the signer, because the
   signer can no longer claim to understand what it is signing.
6. **Semantics.** Every field range-checked against what is physically
   possible for the profile.
7. **Freshness.** Any authoritative timestamp in the body checked against the
   local clock, within a profile-declared skew.
8. **Transform.** Every conversion in section 6 run, each fallible, any
   failure aborting.
9. **Sign.** Only now.

### 9.1 Fail closed

There are exactly two outcomes: a valid signature on stdout and exit 0, or
nothing on stdout and a non-zero exit.

Implementations MUST NOT emit a partial result, a best-effort result, a default
value, or a last-known-good value. A signer that degrades gracefully is a
signer that signs garbage precisely when something is attacking it.

The raw body SHOULD be written to stderr on failure, so that upstream schema
drift is diagnosable. It MUST NOT be signed.

### 9.2 Fetch once

A retry is not a repair. It is a new observation, with a new body and a new
timestamp, and it MUST re-enter the gate at step 1 or not happen at all.
Implementations MUST NOT merge, average or fall back across attempts.

## 10. Key handling

The private key MUST be read from an environment variable or standard input.
It MUST NOT be accepted as a command line argument, where it lands in the
process table and the shell history. Credentials for the upstream API MUST be
sent as headers, MUST NOT appear in the URL — which is committed to in `w2` and
published — and MUST NOT be logged, including in the stderr body dump of 9.1.

## 11. Verification

The happy path parses nothing and touches no storage.

```solidity
bytes32 constant ENVELOPE = keccak256("st0x.attest.v1");
bytes32 constant HALF_N =
    0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;

/// @return The address that attested to these words, or reverts.
function attestor(
    bytes32 profile,
    bytes32 urlHash,
    uint256 signedAt,
    bytes32 bodyHash,
    bytes32[] memory values,
    bytes32 r,
    bytes32 s,
    uint8 v
) internal pure returns (address) {
    require(uint256(s) <= uint256(HALF_N), "malleable s");
    require(v == 27 || v == 28, "bad v");
    bytes32 inner = keccak256(
        abi.encodePacked(ENVELOPE, profile, urlHash, signedAt, bodyHash, values)
    );
    bytes32 digest = keccak256(
        abi.encodePacked("\x19Ethereum Signed Message:\n32", inner)
    );
    address signer = ecrecover(digest, v, r, s);
    require(signer != address(0), "bad sig");
    return signer;
}
```

`abi.encodePacked` is correct here only because every element is a static
32-byte type, which makes the encoding a plain concatenation with no padding
and no ambiguity. Adding any dynamically sized member to the preimage would
break that and would be a change of envelope.

## 12. Cross-chain replay

The same signature verifies on every EVM chain. That is the requirement, not a
defect: an attestation is a claim about the world, not an action on a ledger,
and a claim does not stop being true on another chain.

Any consumer that *pays out* or otherwise takes an irreversible action on an
attestation MUST maintain its own per-chain replay protection, keyed on
whatever makes sense for it — the recovered address plus the value words,
typically. The attestation layer deliberately provides none.

## 13. Output format

One JSON object on stdout, one line, on success:

```json
{
  "envelope": "st0x.attest.v1",
  "profile": "<profile id string>",
  "url": "<full request URL>",
  "signedAt": 1758585600,
  "bodyHash": "0x…",
  "values": ["0x…", "0x…"],
  "signer": "0x…",
  "signature": "0x…"
}
```

`envelope`, `profile` and `url` are given in their preimage form rather than
hashed so that a consumer can recompute `w0`, `w1` and `w2` and check them,
rather than trusting the signer's hashing. `signer` is the address the producer
expects to be recovered, included for convenience; verifiers MUST recover it
themselves and MUST NOT trust the field.

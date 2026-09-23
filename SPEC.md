# st0x.attest

Sign an HTTP API response so a contract can verify it on chain.

**Status: requirements settled, mechanism not decided.** Section 1 is what was
asked for. Section 2 lists the decisions that have to be made to satisfy it and
have not been. Everything from section 3 onward is a proposal written to be
argued with, not a specification to build against. Nothing in it has been
approved.

## 1. What this needs to do

1. A Rust binary that signs and timestamps an HTTP API response, verifiable on
   an EVM chain, chain agnostic.
2. No JSON decoding on chain. The binary transforms the response into signed
   EVM words, integrity-checks it first, and refuses to sign anything it does
   not recognise.
3. The API is Alpaca stock pricing.
4. A contract accepts a list of signed values and compares them numerically on
   chain. Byte equality between signers is not required.
5. No aggregation. A consumer may take any of the signed values and accept it
   if the others agree within a deviation, given a required number of signed
   values. The deviation and the count are set by the mint admin, not
   predetermined here.
6. Operators do not coordinate at runtime. The party doing the minting is the
   coordinator: it requests from each operator separately and assembles the
   bundle it submits.
7. The operators form a pool of N with a threshold of M, where M is less than
   N, so one operator being down does not stop minting. Ten operators with a
   threshold of three is an illustrative shape. All operators in the pool must
   be equally difficult to compromise. Operators may be added purely for
   availability redundancy, and the minter does not have to contact all of
   them.
8. One operator is the **lead** and its attestation is mandatory. The lead is
   the entity legally issuing the tokens. The other operators are not legally
   responsible for the issuance; they are redundancy against the lead being
   compromised, and do not substitute for it.
9. To reach the signing threshold, an attacker must compromise the signatory
   that requests the attestations and performs the mint, **and** the lead,
   **and** at least M of the pool operators.
10. Values are carried as Rain Floats. The leaky bucket converts from Rain
    fixed point to Rain Floats; two storage slots is acceptable.
11. Zero values are rejected. The leaky bucket library already rejects them.

## 2. Decisions not yet made

Each of these was silently decided in an earlier draft and presented as a
requirement. None of them has been chosen.

1. **Signature framing.** EIP-191 or EIP-712 with a name-and-version-only
   domain. An earlier draft banned EIP-712 on the grounds that its domain binds
   `chainId` — but `st0x.price-publisher` already uses EIP-712 chain-agnostically
   by omitting `chainId` and `verifyingContract`, so the ban was wrong and the
   choice is open. Either satisfies requirement 1.
2. **What the preimage commits to.** An earlier draft invented five envelope
   words: a version tag, a profile tag, a hash of the request URL, the signer's
   clock, and a hash of the raw response body. Each is a separate decision, and
   none was asked for.
3. **Whether to commit the raw body at all.** It makes a dishonest extraction
   demonstrable off chain and costs one word. It has no on-chain consumer.
4. **Compatibility with `SignedContextV1`.** `st0x-oracle-server` already signs
   `keccak256` over packed `bytes32` under EIP-191, verified by Rain's
   `LibContext`. A format that is not a `SignedContextV1` cannot be read by
   existing Rainlang strategies.
5. **Which Alpaca endpoint.** Closed historical bars, latest trade, or latest
   quote. This determines whether two operators can agree at all.
6. **Which query parameters are pinned, and to what.** `feed`, `asof`,
   `adjustment`, `timeframe`. Section 5 of `ALPACA.md` records what each one
   does and why it matters; which values to pin is not decided.
7. **Settlement delay.** How old an observation must be before it is signed.
   Alpaca documents no finalisation guarantee, so this has no documented basis
   and must be measured.
8. **What the binary rejects.** An earlier draft proposed nine checks. Which of
   them are wanted is a decision.
9. **Signature malleability handling.** Whether the verifier enforces low-`s`
   and `v` in `{27, 28}`, or delegates to OpenZeppelin's `ECDSA`.
10. **Output format of the binary.**

## 3. Proposal: cryptographic primitives

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

## 4. Proposal: word layout

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

## 5. Proposal: signature encoding

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

## 6. Proposal: transforming values into words

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

## 7. Proposal: determinism and convergence

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

## 8. Proposal: the timestamp

`SIGNED_AT` is a claim, enforced only by the consuming contract comparing it to
`block.timestamp` at submission and rejecting anything staler than its own
freshness window.

## 9. Proposal: the gate

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

## 10. Proposal: key handling

The private key MUST be read from an environment variable or standard input.
It MUST NOT be accepted as a command line argument, where it lands in the
process table and the shell history. Credentials for the upstream API MUST be
sent as headers, MUST NOT appear in the URL — which is committed to in `w2` and
published — and MUST NOT be logged, including in the stderr body dump of 9.1.

## 11. Proposal: verification

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

## 12. Proposal: output format

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

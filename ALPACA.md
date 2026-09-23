# Profile: `alpaca.bar.1min.v1`

Attests to one closed one-minute stock bar from the Alpaca Market Data API.

```
PROFILE = keccak256("alpaca.bar.1min.v1")
```

This document is normative and sits under [`SPEC.md`](SPEC.md). RFC 2119 key
words apply. Everything asserted about Alpaca here is transcribed from the
OpenAPI source served by appending `.md` to a docs URL; anything the docs do
not settle is in section 9 as an open question rather than invented.

## 1. Why bars and not trades

`SPEC.md` §7.2 requires an observation fixed by its URL. `/trades/latest` and
`/quotes/latest` are functions of when you call them, so two uncoordinated
signers milliseconds apart observe different trades and never converge.

Alpaca gives a second, independent reason to avoid `/trades/latest`: it is
already a *filtered* endpoint — "Trades with any conditions that causes them to
not update the bar price are excluded" — but it does not state whether it
applies minute-bar or daily-bar exclusion rules. Six condition codes
(`G`, `P`, `T`, `Z`, `4`, `9`) resolve differently between the two, and `T`
(Extended Hours Trade) inverts outright: it updates a minute bar and does not
update a daily bar. The exclusion set is therefore ambiguous as documented, and
a signer cannot honestly claim to know what it is signing.

A closed historical minute bar has neither problem. Its aggregation rules are
fully documented, and it is addressed by its URL.

## 2. Request

### 2.1 Endpoint

The **single-symbol** endpoint MUST be used:

```
GET https://data.alpaca.markets/v2/stocks/{symbol}/bars
```

The multi-symbol variant MUST NOT be used. Its pagination is "sorted by symbol
first, then by bar timestamp", so a page is not a time-slice across symbols and
the response shape depends on how much data other symbols happened to have.

### 2.2 Pinned query string

Every parameter below MUST be sent explicitly, in exactly this order, with no
others added. The URL is committed to in `w2`, so parameter order and spelling
are part of the signature and every signer must produce identical bytes.

```
?timeframe=1Min&start={T}&end={T}&limit=1&adjustment=raw&feed=sip&asof=-&currency=USD&sort=asc
```

`{T}` is the bar's left-edge instant, formatted `YYYY-MM-DDTHH:MM:SSZ` with no
fractional part, percent-encoded as `%3A` for each `:` if the client encodes
the query string.

| Parameter | Value | Why pinned |
| --- | --- | --- |
| `timeframe` | `1Min` | Minute bars aggregate from trades directly. Hour and week bars aggregate *from bars*, which the docs state "no longer considers the actual trades", adding a layer this profile does not want. |
| `start`, `end` | both `{T}` | Both bounds are inclusive and a bar's `t` is the left edge of its interval, so an equal pair selects the single bar at `{T}`. See §9.3. |
| `limit` | `1` | Bounds the response. Combined with the arity check in §4.2 it makes an unexpected multi-bar response a hard failure rather than a silent first-element pick. |
| `adjustment` | `raw` | Anything else applies corporate actions retroactively, so the same query returns different numbers after a split or dividend. Alpaca additionally warns it "has no guarantees on the creation time of corporate actions". Only `raw` is a candidate for immutability. |
| `feed` | `sip` | See §3. This is the single most consequential parameter in the profile. |
| `asof` | `-` | See §2.3. |
| `currency` | `USD` | The default, pinned so it is inside the commitment. |
| `sort` | `asc` | Irrelevant for one bar, pinned so the byte string is fixed. |

### 2.3 `asof` MUST be `-`

`asof` is not a data-vintage selector. It is symbol-to-entity mapping, and its
default is **the current day**, which makes it a determinism hazard.

Alpaca's own worked example: Facebook renamed to Meta on 2022-06-09. Querying
`META` over 2022-06-06 to 2022-06-11 with the default `asof` returns five bars,
*including the pre-rename days, relabelled as META*. With `asof=-` it returns
two. With `asof=2022-06-06` and the symbol `FB`, five.

So a signer running today and a signer running tomorrow can receive different
data for the same historical minute, if a rename lands between them. The
default value of this parameter is a function of wall-clock time, which is
exactly what §7.2 of the core spec forbids.

`asof=-` skips mapping entirely and is the only value that is stable under
replay. The consequence — that a symbol attests to whatever entity carried that
ticker at the time, with no retroactive relabelling — is the correct semantics
for an attestation anyway.

### 2.4 Authentication

```
APCA-API-KEY-ID: <key id>
APCA-API-SECRET-KEY: <secret>
```

Note the spelling: `APCA-API-SECRET-KEY`, not `APCA-SECRET-KEY`. Per `SPEC.md`
§10 these are headers, are never in the URL, and are never logged.

## 3. The feed is the whole ballgame

**Different Alpaca subscription tiers return different prices for the same
symbol and the same minute.** This is not a subtlety, it is documented with a
worked example. AAPL, daily bar, 2023-09-29:

```
feed=sip : o 172.02   h 173.07  l 170.341  c 171.21  v 51861083  n 535134  vw 171.599691
feed=iex : o 172.015  h 173.06  l 170.36   c 171.29  v 923134    n 12630   vw 171.716432
```

Every single field differs. IEX is roughly 2.5% of market volume; SIP is 100%.

The `feed` parameter's default is **subscription-dependent** — "`sip` if the
user has the unlimited subscription, otherwise `iex`". The historical endpoint's
OpenAPI schema declares a flat `"default": "sip"`, which contradicts the prose;
the prose is authoritative. An implementation MUST NOT rely on the default for
either value.

Therefore:

1. `feed=sip` MUST be sent explicitly on every request.
2. A signer without SIP entitlement MUST fail. It MUST NOT retry with `iex`,
   MUST NOT fall back to `delayed_sip`, and MUST NOT downgrade in any other
   way. A silent downgrade produces a well-formed signature over a materially
   different price, which is the worst failure this design can have.
3. Because `feed=sip` is inside `URL_HASH`, a consuming contract that hardcodes
   the expected `URL_HASH` cannot be fed an IEX attestation at all. Consumers
   SHOULD do this.

A signer lacking entitlement receives an error body of the shape
`{"code":42210000,"message":"subscription does not permit querying recent SIP data"}`.
This requires no special handling: it does not match the expected response
struct, so the `deny_unknown_fields` decode in `SPEC.md` §9 step 5 rejects it
before any transform runs. Strict decoding is load-bearing here, not hygiene.

Note also that without a subscription, SIP data can only be queried when `end`
is at least 15 minutes old. This interacts with the settlement delay in §5.

## 4. Response

### 4.1 Shape

```json
{
  "bars": [
    {"t":"2022-01-03T09:00:00Z","o":178.26,"h":178.26,"l":178.21,"c":178.21,"v":1118,"n":65,"vw":178.235733}
  ],
  "symbol": "AAPL",
  "next_page_token": null
}
```

`stock_bars_resp_single` requires `bars`, `next_page_token` and `symbol`. Every
field of `stock_bar` is required: `t`, `o`, `h`, `l`, `c`, `v`, `n`, `vw`.

`next_page_token` is the only nullable field anywhere in the schema and is
therefore the only field that may legitimately be modelled as an optional. It
is not otherwise used by this profile.

### 4.2 Structural checks

All are terminal.

1. `bars` MUST decode as an array. A `null` or absent `bars` MUST abort — see
   §9.2, this is a live behaviour question, and aborting is correct under
   either answer.
2. `bars` MUST contain **exactly one** element. Zero means no bar exists for
   that minute and there is nothing to attest. More than one means the
   request's semantics are not what this profile believes.
3. `symbol` MUST equal the requested symbol, byte for byte.
4. `bars[0].t` MUST parse to exactly `{T}`. This is what proves the response
   answers the question the URL asked, rather than a neighbouring minute.

A bar's absence is normal and is not an error condition upstream: the docs
state "the bar is only emitted if none of its fields (open, high, low, close,
volume) are 0… if there's only a single `I` trade… then no bar is generated."
Bars are absent, never zero-filled. A minute with no eligible trades simply
cannot be attested, and the signer MUST exit non-zero rather than emit a zero
bar.

### 4.3 Semantic checks

All are terminal.

1. `o`, `h`, `l`, `c`, `vw` MUST each be strictly greater than zero.
2. `l <= o <= h` and `l <= c <= h` MUST hold.
3. `l <= vw <= h` MUST hold. VWAP accumulates only from trades that are
   eligible under *both* the high/low rule and the volume rule, so its
   contributing set is a subset of the set that determines `l` and `h`, and a
   weighted mean of that subset cannot escape the interval. If this check ever
   fires, the data is not what this profile models and MUST NOT be signed.
4. `v` and `n` MUST each be strictly greater than zero, consistent with the
   emission rule quoted above.
5. Each of `o`, `h`, `l`, `c`, `vw` MUST fall within a deployment-configured
   plausibility band for the symbol. A band is a policy choice, not a documented
   property, and MUST be declared per deployment.

`vw` MUST NOT be derived, checked against, or reconciled with `v` and the OHLC
values. The docs are explicit that VWAP's volume denominator "can be different
from the 'normal' volume field of the bar", so `vw` is not reconstructible from
the other fields. It is an independent observation and is signed as one.

## 5. Settlement delay

`{T}` MUST be at least `SETTLEMENT_DELAY` seconds before the signer's clock.
`SETTLEMENT_DELAY` is a required deployment parameter with no default.

It has no documented basis, and this must be stated plainly rather than papered
over. **Alpaca documents no finalisation guarantee for historical bars.** A
search of the market data documentation for settlement, finalisation, `T+n`,
restatement, immutability, backfill and "subject to change" returns nothing at
all. What the docs *do* establish is that corrections exist:

- Trades carry an optional `u` field taking `canceled`, `incorrect` or
  `corrected`, so a trade previously returned can later be marked invalid.
- The stream emits trade corrections (`T:"c"`) and cancels/errors (`T:"x"`).
- The stream emits `updatedBars` when a late trade arrives after the minute
  mark, "possibly updating the previous bar's closing price and volume".

Whether those corrections propagate into a subsequent historical REST query for
the same minute is **not documented either way**. Until measured (§9.1), a
deployment MUST treat historical bars as revisable without notice, and
`SETTLEMENT_DELAY` is a risk parameter chosen by the deployment, not a
guarantee obtained from Alpaca.

Note the interaction with §3: without a SIP subscription, `end` must already be
at least 15 minutes old, so `SETTLEMENT_DELAY` below 900 is unreachable for
those signers regardless.

## 6. Timestamp parsing

Alpaca returns RFC 3339 with a **variable-length** fractional-seconds
component, always UTC. Real documented values:

```
2022-08-17T09:53:16.845580544Z    9 fractional digits
2023-04-06T13:15:42.83540958Z     8 fractional digits
2022-01-03T09:00:00Z              no fractional part, no decimal point
```

The variability is consistent with Go's `RFC3339Nano` trimming trailing zeros.
A fixed-width parser expecting nine digits will fail on real responses, and one
expecting a decimal point will fail on every exact-minute bar — which is every
bar this profile reads.

Parsers MUST therefore:

1. Match `^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?Z$`.
2. Reject a numeric UTC offset. Alpaca accepts offsets like `-04:00` on
   *input*; output is always `Z`, and accepting anything else on output would
   let two signers disagree about one instant.
3. Right-pad the fractional digits with `0` to exactly nine, treating an absent
   fractional part as nine zeros.
4. Convert to unsigned nanoseconds since the unix epoch by integer arithmetic
   only. No floating point, no date library that round-trips through a float.

For this profile `bars[0].t` is additionally required to be exactly on a minute
boundary — nanoseconds since epoch MUST be an exact multiple of
`60 000 000 000` — because a one-minute bar's left edge always is.

## 7. Numbers

Alpaca returns prices as JSON **numbers**, never strings: `"c": 178.21`,
`"p": 172.6`, `"vw": 178.235733`. Sizes, volumes and counts are JSON integers.

This makes `SPEC.md` §6.2 mandatory rather than advisory. `serde_json` will
parse `178.235733` into an `f64` unless `arbitrary_precision` is enabled, and
two signers can then produce different words from byte-identical input. The raw
digit string MUST be taken from the number token and scaled by §6.3 of the core
spec.

There is **no fixed decimal precision**. Documented values from equivalent
fields range from one to seven significant decimal places — `172.6` (not
`172.60`), `178.21`, `170.341`, `39.1582`, `388.985`, `178.235733` — and
trailing zeros are not preserved. Any rule that assumes a fixed scale on the
wire is wrong.

`SCALE` for this profile is **18**, matching the conventional EVM fixed-point
denomination. At that scale the abort in §6.3 step 3 cannot trigger for any
precision Alpaca has been observed to emit, while still being a hard failure if
Alpaca ever exceeds it.

## 8. Value words

`PROFILE = keccak256("alpaca.bar.1min.v1")`, and `w5..w13` are:

| Word | Name | Source | Transform |
| --- | --- | --- | --- |
| `w5` | `SYMBOL` | requested symbol | `keccak256` of the uppercase ASCII bytes |
| `w6` | `BAR_TIME` | `bars[0].t` | `uint256` nanoseconds since epoch, §6 |
| `w7` | `OPEN` | `bars[0].o` | scaled `uint256`, `SCALE` 18 |
| `w8` | `HIGH` | `bars[0].h` | scaled `uint256`, `SCALE` 18 |
| `w9` | `LOW` | `bars[0].l` | scaled `uint256`, `SCALE` 18 |
| `w10` | `CLOSE` | `bars[0].c` | scaled `uint256`, `SCALE` 18 |
| `w11` | `VOLUME` | `bars[0].v` | `uint256`, shares |
| `w12` | `TRADE_COUNT` | `bars[0].n` | `uint256` |
| `w13` | `VWAP` | `bars[0].vw` | scaled `uint256`, `SCALE` 18 |

The symbol is hashed rather than packed into a `bytes32`, per `SPEC.md` §6.1,
so that ticker length is never a constraint and the mapping stays injective.

The whole bar is signed rather than just the close. It costs eight extra words
in calldata and it means the quorum in §7.1 of the core spec is taken over the
complete observation, so two signers agreeing on the close but disagreeing on
volume are correctly treated as disagreeing.

`feed` is deliberately *not* a value word. It is pinned inside `URL_HASH`,
which is the stronger mechanism: a contract comparing `URL_HASH` to a constant
rejects a wrong-feed attestation without reading, parsing or trusting anything.

### 8.1 Volume units

`v` is in shares. Alpaca changed quote size units from round lots to shares on
2025-11-03; bar volume is documented as "Bar volume" without a lot qualifier,
but any deployment attesting to bars dated before 2025-11-03 SHOULD confirm the
unit for that era before treating historical and current volume words as
comparable.

## 9. Open questions

These MUST be settled empirically against the live API, with the observed
bodies recorded, before an implementation is trusted. None of them can be
resolved from the documentation, and none may be guessed.

### 9.1 Are historical bars restated?

The question §5 depends on. Method: capture a minute bar immediately after its
close, re-query the identical URL at intervals over the following hours and
days, and diff. Do this across symbols and across volatile and quiet minutes,
and specifically over a minute known to contain a corrected or cancelled trade.
The output is a measured distribution of when a bar stops changing, which is
what `SETTLEMENT_DELAY` should be derived from.

### 9.2 What comes back for an unknown or dataless symbol?

Undocumented. No `404` is declared on any stocks endpoint; the declared error
responses are `400`, `401`, `403`, `429` and `500`. The single-symbol schema
declares `bars` as a non-nullable array, yet `"bars": null` is widely reported
in practice, which would contradict Alpaca's own schema.

Method: query an invalid ticker and a long-halted one across the single-symbol
endpoint, and record the exact bodies. §4.2 aborts under either answer, so this
does not block correctness — but it determines whether a legitimate no-data
minute is distinguishable from an operator typo, which matters for alerting.

### 9.3 Does `start == end` select exactly one bar?

Both bounds are documented as inclusive and a bar's `t` is its left edge, so an
equal pair should select the single bar at that instant. This is inference from
two separate documented facts, not a documented behaviour, and it is the
foundation of §2.2.

Method: request a known-active minute with `start == end` and confirm exactly
one bar whose `t` equals the requested value. The §4.2 arity and timestamp
checks fail closed if the inference is wrong, so a mistake here costs
availability rather than correctness — but it must be confirmed before
deployment, not discovered in production.

## 10. Operational notes

Rate limits are 200 requests per minute on the free Basic plan and 10,000 on
Algo Trader Plus. Responses carry `X-RateLimit-Limit`,
`X-RateLimit-Remaining` and `X-RateLimit-Reset` on `200`, `400` and `429`.

A `429` MUST be treated as a terminal failure for the attempt under `SPEC.md`
§9.2: a retry is a new observation and re-enters the gate from the top. Since
this profile's target is a *closed historical* minute, a retry for the same
`{T}` is in fact legitimate and will return the same bar — but it MUST be a
fresh run of the whole gate, not a resumption, and it MUST NOT reuse the
earlier `SIGNED_AT`.

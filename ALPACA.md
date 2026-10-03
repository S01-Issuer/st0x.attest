# The Alpaca stock pricing API

A characterisation of the upstream API, written so that the validation gate in
[`SPEC.md`](SPEC.md) item 2 can be derived from it rather than guessed at. No
code here. This document is the input to the pass that writes the gate.

## 0. Method, sources and how to read a claim

Every claim below is sourced from a document Alpaca publishes, retrieved on
**2026-09-24**. Appending `.md` to a `docs.alpaca.markets` URL returns the raw
source; the index is at <https://docs.alpaca.markets/us/llms.txt>.

Sources are not equally authoritative, so each claim is tagged:

- **[OAS]** — from the OpenAPI definition embedded in a
  `docs.alpaca.markets/us/reference/*.md` page. This is the machine-readable
  contract. `openapi: 3.1.2`, `info.version: 1.1`, title `Market Data API`.
  The reference pages carry `updatedAt: 2026-05-27T17:58:03.000Z`.
- **[PROSE]** — from a `docs.alpaca.markets/us/docs/*.md` page. Narrative, not
  a contract, and in at least one case (§2.2) it contradicts the OpenAPI.
  Recorded because the OpenAPI is silent, and flagged as such.
- **[OPEN]** — the documentation does not settle it. Recorded in §10 with the
  measurement that would settle it. Nothing in this document is filled in from
  recollection, and nothing tagged **[OPEN]** may be assumed by the gate.

Where the issue that commissioned this document asserted something, and the
documentation does not support it as stated, that is said plainly — see §3.4
and §10.4.

### 0.1 What the binary signs, and therefore what matters

`SPEC.md` items 4 to 6 fix the signed payload at exactly three values:

| Slot | Value  | Encoding               | Comes from |
| ---- | ------ | ---------------------- | ---------- |
| 0    | symbol | IntOrAString `bytes32` | §3.2       |
| 1    | price  | Rain Float             | §3.3       |
| 2    | time   | Rain Float             | §3.4       |

Nothing else is signed. That narrows what has to be characterised: the feed,
the currency, the adjustment, the trade conditions and the rate limits do not
appear in the payload, so **none of them are verifiable on chain from the
signature**. They are enforced, if at all, by the binary refusing to sign, and
by the operator being configured correctly. §8 states the consequence.

## 1. The endpoint

**`GET https://data.alpaca.markets/v2/stocks/{symbol}/trades/latest`**
— operation `StockLatestTradeSingle`. **[OAS]**
<https://docs.alpaca.markets/us/reference/stocklatesttradesingle-1.md>

Servers declared in the OpenAPI are `https://data.alpaca.markets`
(Production) and `https://data.sandbox.alpaca.markets` (Sandbox) **[OAS]**
(same page, `servers`). The sandbox host is described only as being "for
broker partners" **[PROSE]**
<https://docs.alpaca.markets/us/docs/historical-api.md>; what it actually
serves is not characterised by any document found, so pin production and
treat the sandbox as out of scope.

### 1.1 Why this one

The candidates are latest trade, latest bar, latest quote, snapshot, and
historical bars. The three signed values decide it.

**Against historical bars** (`/v2/stocks/{symbol}/bars`,
`/v2/stocks/bars`): the endpoint has eleven query parameters, of which
`timeframe`, `start`, `end`, `limit`, `adjustment`, `asof`, `feed`,
`currency`, `sort` and `page_token` all change what comes back **[OAS]**
<https://docs.alpaca.markets/us/reference/stockbarsingle-1.md>. `start` and
`end` are required in substance — each operator would have to choose an
interval — and uncoordinated operators cannot choose the same one without
coordinating, which `SPEC.md` item 22 forbids at runtime. It replaces one
problem with a harder one.

**Against latest bar** (`/v2/stocks/{symbol}/bars/latest`): the bar's `t` is
the *left edge of the aggregation interval*, not an event time — "The
timestamp of the bar is the left side of the interval" **[PROSE]**
<https://docs.alpaca.markets/us/docs/market-data-faq.md>. So `t` is quantised
to the minute. Two operators polling four seconds apart across a minute
boundary sign times 60 seconds apart while signing near-identical prices.
`SPEC.md` item 14 makes the attested times agree within an absolute threshold
and then *uses the lead's time*; a 60-second quantisation step forces that
threshold to at least 60 seconds for no gain in truth. A minute bar is also
mutable after it closes — see §7.2.

**Against latest quote** (`/v2/stocks/{symbol}/quotes/latest`): the response
carries `bp` and `ap`, two prices, not one **[OAS]**
<https://docs.alpaca.markets/us/reference/stocklatestquotesingle-1.md>. Slot 1
is a single price, so the binary would have to compute a mid or pick a side —
a derived number that is not in the response, which is exactly what `SPEC.md`
item 2 ("refuses to sign weirdness") is meant to avoid. Both fields are also
documented as taking the value `0` to mean "no active bid/ask", which is a
sentinel the gate would have to special-case.

**Against snapshot** (`/v2/stocks/{symbol}/snapshot`): it returns five
sub-objects — `latestTrade`, `latestQuote`, `minuteBar`, `dailyBar`,
`prevDailyBar` — **none of which are marked `required`** in the schema
**[OAS]** <https://docs.alpaca.markets/us/reference/stocksnapshotsingle.md>.
It is a superset of the latest-trade response with a weaker contract and a
larger refusal surface, and the binary would read exactly one field from it.

**For latest trade:**

1. `p` is a single price that was actually executed, not a derived or
   quantised figure.
2. `t` is the trade's own timestamp with nanosecond precision, so the signed
   time is an event time, not a bucket edge. The spread between two operators'
   attested times is then bounded by their polling skew plus the arrival rate
   of trades, which is what `agree-absolute` in `SPEC.md` item 14 is for.
3. The request surface is three parameters — `symbol` (path), `feed`,
   `currency` — and two of them are pinnable constants (§2). That is the
   smallest pinning surface of any candidate, which matters directly for item
   2.
4. Alpaca already filters the trades that would be misleading: "Trades with
   any conditions that causes them to not update the bar price are excluded.
   For example a trade with condition `I` (odd lot) will never appear on this
   endpoint." **[OAS]**
   <https://docs.alpaca.markets/us/reference/stocklatesttradesingle-1.md>

**What would overturn this.** If §10.6 measures the inter-operator price
spread on latest trade as materially worse than on latest bar close during
liquid hours, the 60-second time quantisation of the bar may be the cheaper
cost. That is a measurement, not a documentation question, and it is listed
as such.

## 2. The request surface

Three parameters. **[OAS]**
<https://docs.alpaca.markets/us/reference/stocklatesttradesingle-1.md>

| Parameter  | In    | Required | Declared schema                                                     | Declared default                  | Pin to       |
| ---------- | ----- | -------- | ------------------------------------------------------------------- | --------------------------------- | ------------ |
| `symbol`   | path  | yes      | `string`, no pattern, no `maxLength`                                 | —                                 | the subject  |
| `feed`     | query | no       | enum `delayed_sip`, `iex`, `otc`, `sip`, `boats`, `overnight`        | **none in the schema** — see §2.2 | `sip`        |
| `currency` | query | no       | `string` (ISO 4217)                                                  | "Default: USD" in the description | `USD`        |

There is no `adjustment`, no `asof`, no `sort`, no `limit` and no `page_token`
on this endpoint. That is a property of the *latest* endpoints specifically —
"the data is never manipulated in any way. These endpoints always return the
data as it was received at the time (this is also why there is no `adjustment`
parameter on the latest bars)" **[PROSE]**
<https://docs.alpaca.markets/us/docs/market-data-faq.md>. All five of those
parameters do exist on the historical bars endpoints and all five change the
values returned **[OAS]**
<https://docs.alpaca.markets/us/reference/stockbarsingle-1.md>, which is part
of why §1.1 rejects them.

### 2.1 `feed` changes the values

This is the single largest source of disagreement between two honest
operators. Alpaca publishes the comparison itself: the AAPL daily bar for
2023-09-29 differs in **every** OHLCV field between `sip` and `iex`.
**[PROSE]** <https://docs.alpaca.markets/us/docs/market-data-faq.md>

| Field | `feed=sip` | `feed=iex` |
| ----- | ---------- | ---------- |
| `o`   | 172.02     | 172.015    |
| `h`   | 173.07     | 173.06     |
| `l`   | 170.341    | 170.36     |
| `c`   | 171.21     | 171.29     |
| `v`   | 51 861 083 | 923 134    |
| `n`   | 535 134    | 12 630     |

`iex` is a single exchange carrying "approximately ~2.5% of the market
volume"; `sip` is the consolidated tape and "accounts for 100% of the market
volume" **[PROSE]**
<https://docs.alpaca.markets/us/docs/historical-stock-data-1.md>. `overnight`
is explicitly a derived, lower-accuracy feed: "The trades are 15 minutes
delayed and adjusted to fit the bid-ask spread" (same page). `delayed_sip` is
"SIP with a 15 minute delay" **[OAS]**.

The gate must pin `feed=sip` in the request. It cannot verify the feed from
the response — see §8.

### 2.2 The `feed` default is not what the OpenAPI says

Three Alpaca documents disagree, and the gate must not depend on any of them:

- The **latest**-endpoint parameter description, in the OpenAPI itself:
  "Default: `sip` if the user has the unlimited subscription, otherwise
  `iex`." The `stock_latest_feed` *schema* declares **no** `default` key.
  **[OAS]** <https://docs.alpaca.markets/us/reference/stocklatesttradesingle-1.md>
- The **historical** `stock_historical_feed` schema declares
  `"default": "sip"` flatly, with no subscription caveat anywhere in the
  parameter description. **[OAS]**
  <https://docs.alpaca.markets/us/reference/stockbarsingle-1.md>
- The FAQ: "The default value for `feed` is always the 'best' available feed
  based on the user's subscription." **[PROSE]**
  <https://docs.alpaca.markets/us/docs/market-data-faq.md>

So the historical OpenAPI's declared default is contradicted by Alpaca's own
prose, and the effective default on every endpoint is a function of the
caller's billing status. Two operators on different tiers, issuing
byte-identical requests, get different prices. **`feed` is never omitted.**

### 2.3 `currency` changes the values and the price's meaning

"The pricing information is converted from USD to the relevant local currency
on the fly **with the latest FX rate at the point in time of query**."
**[PROSE]** <https://docs.alpaca.markets/us/docs/local-currency-trading-lct.md>

A non-USD `currency` therefore makes the signed price a function of an FX rate
sampled at each operator's own request instant — a second, undisclosed price
feed folded into slot 1. Pin `currency=USD`.

The response echoes `currency` when it is set (the LCT example returns
`"currency": "JPY"`), but `currency` is **not** in the response's `required`
list (§3.1), so its absence does not prove USD. The conservative rule the gate
can actually justify: refuse if `currency` is present and is not exactly
`"USD"`; §10.3 records what to measure before treating absence as USD.

## 3. The response

### 3.1 Envelope — `stock_latest_trades_resp_single`

**[OAS]** <https://docs.alpaca.markets/us/reference/stocklatesttradesingle-1.md>

```json
{
  "symbol": "AAPL",
  "trade": {
    "c": ["@", "T"],
    "i": 689,
    "p": 172.6,
    "s": 100,
    "t": "2022-08-17T09:53:16.845580544Z",
    "x": "P",
    "z": "C"
  }
}
```

| Field      | Declared type | Required | Notes                        |
| ---------- | ------------- | -------- | ---------------------------- |
| `trade`    | `stock_trade` | **yes**  | §3.3                         |
| `symbol`   | `string`      | **yes**  | §3.2                         |
| `currency` | `string`      | no       | §2.3; absent from the OpenAPI's own example |

`required: ["trade", "symbol"]`. The schema does not set
`additionalProperties: false`, so **unknown top-level keys are permitted by
the contract**. The gate decides its own posture on unknown keys; the API does
not forbid them.

### 3.2 `symbol` → signed slot 0

Declared as `{"type": "string"}` with **no `pattern`, no `maxLength`, no
`enum`** **[OAS]**. Alpaca's master list of valid symbols is the assets
endpoint, `GET /v2/assets` — "the master list of assets available for trade
and data consumption from Alpaca"
<https://docs.alpaca.markets/us/reference/get-v2-assets-1.md> — which is on
the trading host `api.alpaca.markets`, not the data host **[PROSE]**
<https://docs.alpaca.markets/us/docs/market-data-faq.md>.

`SPEC.md` item 6 requires this to fit an IntOrAString `bytes32`, i.e. at most
32 bytes and comparable to a Rainlang string literal. The API guarantees
neither the length bound nor the character set. This is §10.1.

The response's `symbol` is an echo, not an independent fact, and there is a
documented case where it is *not* the symbol you asked for: on historical
endpoints the `asof` mapping returns data for a renamed predecessor ticker
labelled under the queried symbol — FB data returned as META **[PROSE]**
<https://docs.alpaca.markets/us/docs/market-data-faq.md>. The latest endpoints
have no `asof` parameter and are documented as never manipulating the data
(§2), so on this endpoint the echo should be the requested symbol; §10.2
records how to confirm it and what the gate does if it is not.

### 3.3 `stock_trade` — the price lives here

**[OAS]** <https://docs.alpaca.markets/us/reference/stocklatesttradesingle-1.md>

| Field | Declared type                   | Required | Description as declared                                                       |
| ----- | ------------------------------- | -------- | ----------------------------------------------------------------------------- |
| `t`   | `string`, `format: date-time`   | **yes**  | "Timestamp in RFC-3339 format with nanosecond precision." → §3.4              |
| `i`   | `integer`, `format: uint64`     | **yes**  | "Trade ID sent by the exchange."                                              |
| `x`   | `string`                        | **yes**  | "Exchange code. See `v2/stocks/meta/exchanges` for more details."             |
| `p`   | `number`, `format: double`      | **yes**  | "Trade price." → **signed slot 1**                                            |
| `s`   | `integer`, `format: uint32`     | **yes**  | "Trade size."                                                                 |
| `c`   | `array` of `string`             | **yes**  | "Condition flags. See `v2/stocks/meta/conditions/trade` for more details."    |
| `z`   | enum `A`,`B`,`C`,`N`,`O`        | **yes**  | Tape. A: NYSE; B: NYSE Arca/Bats/IEX and other regionals; C: Nasdaq; N: Overnight; O: OTC |
| `u`   | `string`                        | no       | Trade update — see below                                                       |

`required: ["t", "i", "x", "p", "s", "c", "z"]`. `u` is the only optional
member and its meaning is load-bearing:

> "Update to the trade. This field is optional, if it's missing, the trade is
> valid. Otherwise, it can have these values: `canceled` — indicates that the
> trade has been canceled; `incorrect` — indicates that the trade has been
> corrected and the given trade is no longer valid; `corrected` — indicates
> that this trade is the correction of a previous (incorrect) trade" **[OAS]**

A present `u` of `canceled` or `incorrect` is Alpaca stating that the price in
the same object is not a valid trade. Whether `u` can ever appear on the
*latest* trade endpoint (as opposed to the historical trades endpoint) is
§10.5.

There is **no declared minimum, maximum, or sign constraint on `p`**. The
OpenAPI permits `0` and permits a negative number. The only documented
statement that bears on it is about bars, not trades: "the bar is only emitted
if none of its fields (open, high, low, close, volume) are 0" **[PROSE]**
<https://docs.alpaca.markets/us/docs/market-data-faq.md>. That is why
`SPEC.md` item 18 puts absolute bounds in the on-chain expression rather than
trusting the feed.

`z: "N"` (Overnight) and `z: "O"` (OTC) are values the enum permits that a
`feed=sip` reader may not expect. The tape is the closest thing to a
provenance field the response has, and §8 shows it is not close enough.

### 3.4 `t` → signed slot 2

Declared as `{"type": "string", "format": "date-time", "description":
"Timestamp in RFC-3339 format with nanosecond precision."}` **[OAS]**. It is
the same `timestamp` schema used by every stock endpoint.

The declaration is the *whole* contract. RFC-3339 admits considerable
variation that the schema does not rule out, and Alpaca's own published
examples already exercise some of it:

| Observed rendering                | Fractional digits | Source                                                                 |
| --------------------------------- | ----------------- | ---------------------------------------------------------------------- |
| `2022-08-17T09:53:16.845580544Z`  | 9                 | latest trade example **[OAS]**                                          |
| `2021-02-06T13:35:08.946977536Z`  | 9                 | `stock_quote` example **[OAS]**                                         |
| `2023-09-29T19:59:59.246196362Z`  | 9                 | FAQ latest-trade response **[PROSE]**                                   |
| `2022-01-03T09:00:00Z`            | **0**             | `stock_bar` example **[OAS]**                                           |
| `2024-08-01T08:00:00Z`            | **0**             | LCT bars response **[PROSE]**                                           |

The zero-digit renderings are not a different type: Alpaca's own pagination
token for the *same instant* base64-decodes to the padded nanosecond form.
From <https://docs.alpaca.markets/us/reference/stockbarsingle-1.md> **[OAS]**,
`next_page_token` is `QUFQTHxNfDIwMjItMDEtMDNUMDk6MDA6MDAuMDAwMDAwMDAwWg==`,
which decodes to `AAPL|M|2022-01-03T09:00:00.000000000Z`, alongside a response
body rendering the same timestamp as `2022-01-03T09:00:00Z`. So the wire form
drops a fully-zero fractional part that the internal representation keeps.

That establishes that the fractional width varies, and establishes the two
endpoints of the range (0 and 9). It does **not** establish that Alpaca trims
*trailing* zeros generally — that no width between 1 and 8 occurs is not shown
by any document found, and the issue's assertion that "the same field arrives
with nine fractional digits, eight, or no decimal point at all" is
**unverified against the OpenAPI**. It is §10.4, with the measurement.

Also not settled by the schema, and each of them a parse that must either be
handled or refused: whether the offset is always literal `Z` rather than
`+00:00` or a non-UTC offset (the `start`/`end` *request* parameters document
`2024-01-04T09:30:00-04:00` as a legal form, so Alpaca's own RFC-3339 handling
accepts offsets on input); whether the date-time separator is always uppercase
`T`; whether leap seconds (`:60`) can appear. All §10.4.

**Consequence for the binary.** The signed value is a Rain Float, not a
string, so the binary must convert. The input carries up to nanosecond
resolution, i.e. up to 19 significant decimal digits if expressed as
nanoseconds since the epoch. Whatever the binary converts to, the conversion
has to be a function of the received bytes alone, and it has to be stable
across operators — two operators receiving the same `t` must produce the same
Float. That is the gate's problem, but it is bounded by the facts here.

### 3.5 Numbers on the wire

`p`, and every other price field on every stock endpoint, is declared
`{"type": "number", "format": "double"}` **[OAS]**. Consequences:

1. **It is a JSON number, not a string.** There is no quoted-decimal
   representation available on this API.
2. **`format: double`** is an OpenAPI format annotation. It states the
   intended target type; it does not constrain the JSON text, and JSON itself
   places no bound on the digits in a number literal.
3. **No fixed decimal precision is declared.** Alpaca's published examples
   span 0 to 6 decimal places on price-typed fields:

   | Example value | Decimal places | Field | Source                                    |
   | ------------- | -------------- | ----- | ----------------------------------------- |
   | `173`         | **0**          | `c`   | latest bar example **[OAS]**              |
   | `172.6`       | 1              | `p`   | latest trade example **[OAS]**            |
   | `178.26`      | 2              | `p`   | `stock_trade` example **[OAS]**           |
   | `170.341`     | 3              | `l`   | FAQ sip daily bar **[PROSE]**             |
   | `39.1582`     | 4              | `op`  | stream correction example **[PROSE]**     |
   | `171.599691`  | 6              | `vw`  | FAQ sip daily bar **[PROSE]**             |

   Note `"c": 173` in particular: a price field arriving as a **bare integer
   with no decimal point**. A parser that assumes a `.` in a price field is
   wrong against Alpaca's own example.
4. **Nothing in the documentation bounds the significant digits, the exponent,
   or rules out exponential notation.** §10.3.

The operational consequence, which is the point of recording all of this:
parsing `p` through an `f64` makes the signed value a function of the JSON
library's float parsing and re-rendering, not of the response bytes. Two
operators on different library versions can sign different values for
byte-identical responses. The conversion to Rain Float must be driven by the
decimal literal as received.

## 4. Errors

### 4.1 What the OpenAPI declares

The operation declares exactly these responses: `200`, `400`, `401`, `403`,
`429`, `500`. **There is no `404`** on this or on any of the stock endpoints
checked (latest trade, latest bar, historical bars, snapshot). **[OAS]**

| Status | Declared description                                                                                                  | Declares `content`? | Declares rate-limit headers? |
| ------ | --------------------------------------------------------------------------------------------------------------------- | ------------------- | ---------------------------- |
| 200    | "OK"                                                                                                                    | yes, JSON           | yes                          |
| 400    | "One of the request parameters is invalid. See the returned message for details."                                       | **no**              | yes                          |
| 401    | "Authentication headers are missing or invalid. Make sure you authenticate your request with a valid API key."           | **no**              | **no**                       |
| 403    | "The requested resource is forbidden."                                                                                  | **no**              | **no**                       |
| 429    | "Too many requests. You hit the rate limit. Use the X-RateLimit-... response headers to make sure you're under the rate limit." | **no** | yes             |
| 500    | "Internal server error. We recommend retrying these later."                                                             | **no**              | **no**                       |

**No error status declares a response body schema.** The 400 description
refers to "the returned message" without defining where the message is. The
error body shape is therefore not part of the contract.

### 4.2 What the prose shows

One concrete error body appears in the FAQ **[PROSE]**
<https://docs.alpaca.markets/us/docs/market-data-faq.md>, returned when
querying `feed=sip` without the entitlement:

```json
{"code":42210000,"message":"subscription does not permit querying recent SIP data"}
```

Two fields: a numeric `code` (here an 8-digit integer) and a `message` string.
The FAQ also enumerates the conditions behind 403 — request not authenticated,
credentials incorrect, or "the authenticated user has insufficient
permissions" — and instructs the reader to look for that message "in the HTTP
response body", which corroborates that errors carry a body.

No catalogue of `code` values is published anywhere in the index at
<https://docs.alpaca.markets/us/llms.txt>; `https://docs.alpaca.markets/us/docs/errors.md`
returns 404. §10.7.

### 4.3 The gate's position

A non-200 status is a refusal, and nothing has to be parsed out of it. That is
the only posture the documentation supports, because the error body is
undeclared. Any behaviour finer than "refuse on non-200" — retry classes,
distinguishing entitlement failures from rate limiting — rests on §10.7.

## 5. Empty and missing results

`trade` and `symbol` are both `required` on a 200 **[OAS]**, so a well-formed
200 always carries a price. What is **not** documented is what arrives instead
when there is no trade to return:

- An unknown or never-listed symbol. No `404` is declared (§4.1).
- A listed but inactive symbol, or one halted at the time of the query — the
  FAQ names both as reasons data is missing, and gives SVA as a symbol halted
  since 2019-02-22. **[PROSE]**
  <https://docs.alpaca.markets/us/docs/market-data-faq.md>
- An OTC symbol without the OTC entitlement: "Market data for OTC symbols can
  only be queried with a special subscription currently available only for
  broker partners." (same page)

These are §10.8. The multi-symbol variants make the shape of "nothing" visible
in one case — the historical multi-symbol schema has `bars` as an object
map keyed by symbol **[OAS]**
<https://docs.alpaca.markets/us/reference/stockbars.md> — but the single-symbol
latest endpoint's empty shape is nowhere given.

A related documented emptiness, which is why the latest-trade endpoint is
preferable to the latest-bar one on this axis too: "the bar is only emitted if
none of its fields (open, high, low, close, volume) are 0. So if there are no
trades in the bar's interval, or if there's only a single `I` trade ... then no
bar is generated." **[PROSE]** (same page). Bars can be simply absent for a
minute; trades cannot be absent in the same way, they are merely old (§7.1).

## 6. Rate limits and entitlements

### 6.1 Headers

Three, declared as `integer` **[OAS]**:

| Header                | Declared description                            | Example      |
| --------------------- | ----------------------------------------------- | ------------ |
| `X-RateLimit-Limit`   | "Request limit per minute."                     | `100`        |
| `X-RateLimit-Remaining` | "Request limit per minute remaining."         | `90`         |
| `X-RateLimit-Reset`   | "The UNIX epoch when the remaining quota changes." | `1674044551` |

They are declared on `200`, `400` and `429` only — **not** on `401`, `403` or
`500` (§4.1). Whether the window is a fixed calendar minute or a sliding one,
whether the counter is per API key or per account, and whether a `Retry-After`
header accompanies 429, are all undeclared: §10.9.

### 6.2 Published limits

**[PROSE]** <https://docs.alpaca.markets/us/docs/about-market-data-api.md>

Trading API (individual keys):

| Plan             | Price     | Real-time coverage     | Historical API calls |
| ---------------- | --------- | ---------------------- | -------------------- |
| Basic            | Free      | IEX only               | 200 / min            |
| Algo Trader Plus | $99/month | All US Stock Exchanges | 10 000 / min         |

Broker API (partner keys, `C`-prefixed):

| Plan              | RPM    | Equities price/month |
| ----------------- | ------ | -------------------- |
| Standard          | 1 000  | included             |
| StandardPlus3000  | 3 000  | $500                 |
| StandardPlus5000  | 5 000  | $1 000               |
| StandardPlus10000 | 10 000 | $2 000               |

### 6.3 The entitlement constraint on the operator pool

This is the finding with the largest operational consequence, and it follows
directly from pinning `feed=sip` (§2.1):

> "All the latest endpoints (including the snapshot endpoint), require a
> subscription to be used with the SIP feed." **[PROSE]**
> <https://docs.alpaca.markets/us/docs/market-data-faq.md>

and

> "similar to the free plan all the standard plans are real time IEX or 15 mins
> delayed SIP." **[PROSE]**
> <https://docs.alpaca.markets/us/docs/about-market-data-api.md>

So:

1. Every attestor in the `SPEC.md` §3 pool must independently hold a
   real-time SIP entitlement — Algo Trader Plus on the Trading API, or a
   Broker plan that includes real-time SIP. An operator without it gets, on
   every single request, the error body in §4.2 carrying
   `code 42210000, "subscription does not permit querying recent SIP data"` —
   which the FAQ's 403 checklist names as the insufficient-permission signal —
   and can never attest at all.
2. A Broker API partner on Standard or StandardPlus3000 **cannot** serve
   `feed=sip` on a latest endpoint at all, by the sentence above.
3. The Basic-plan escape used for historical queries — "the `end` parameter
   must be at least 15 minutes old to query SIP data without a subscription"
   **[PROSE]** (FAQ) — does not exist on the latest endpoints, which have no
   `end`.
4. Authentication differs by operator class: Trading API keys go in the
   `APCA-API-KEY-ID` / `APCA-API-SECRET-KEY` headers; Broker API uses a
   client-credentials bearer token from
   `https://authx.alpaca.markets/v1/oauth2/token` valid for 15 minutes
   **[PROSE]** (about-market-data-api). The OpenAPI declares the matching
   security schemes: `apiKey` + `apiSecret` headers, or `BasicAuth`
   **[OAS]**. The binary has to support at least the header pair.

Whether `delayed_sip` is entitlement-free — which would let an operator attest
against a uniformly 15-minute-delayed consolidated tape rather than a
2.5%-of-volume exchange — is not stated anywhere found. §10.10. It is worth
settling, because a delayed-but-consolidated feed is a materially different
trade-off for a pool than IEX.

## 7. Determinism between uncoordinated operators

`SPEC.md` item 22 forbids runtime coordination, and items 13 to 15 tolerate
disagreement within a stated tolerance. The following are the documented
reasons two honest operators will differ. This list is what the tolerances
have to be sized against.

### 7.1 Staleness is unbounded

A latest-trade response is the last trade *whenever it happened*. Alpaca's own
example returns the final FB trade, timestamped `2022-06-08T23:59:55Z`, to a
query made long after the ticker ceased to exist **[PROSE]**
<https://docs.alpaca.markets/us/docs/market-data-faq.md>. Outside market
hours, over a weekend, or on a halted symbol (§5), the endpoint keeps
returning the same old trade with a 200 and a valid schema.

Nothing in the response marks it stale. The only signal is `t` itself. The
binary therefore has to compare `t` against its own clock and refuse beyond a
threshold, and the expression compares the attested time against `now()`
independently (`SPEC.md` item 14). Neither check can be derived from the API;
the threshold is a policy choice this document cannot settle.

### 7.2 Prices are revised after the fact

Two documented mechanisms:

- **Trade corrections and cancellations.** The stream carries dedicated
  `corrections` and `cancelErrors` channels, auto-subscribed with the trade
  channel; a correction message carries the original id/price/size/conditions
  and the corrected ones **[PROSE]**
  <https://docs.alpaca.markets/us/docs/real-time-stock-pricing-data.md>. The
  REST counterpart is the `u` field (§3.3).
- **Bars are mutable after they close.** "Updated bars are emitted after each
  half-minute mark if a 'late' trade arrived after the previous minute mark.
  For example if a trade with a timestamp of `16:49:59.998` arrived right
  after `16:50:00`, just after `16:50:30` an updated bar with `t` set to
  `16:49:00` will be sent containing that trade, possibly updating the
  previous bar's closing price and volume." **[PROSE]** (same page)

The second is the decisive argument against treating any bar as immutable:
the tuple (symbol, minute) does not determine the bar. Whether the REST latest
and historical bar endpoints reflect these revisions, and with what delay, is
§10.11.

### 7.3 Ordinary polling skew

Distinct from the above and irreducible: operators poll at different instants,
so they see different trades. This is the intended residual that `agree` in
`SPEC.md` item 13 absorbs. Its magnitude is a measurement (§10.6), not a
documented fact.

### 7.4 Summary of what must be pinned

| Thing                | Pin                                      | Because |
| -------------------- | ---------------------------------------- | ------- |
| Host                 | `data.alpaca.markets`                    | §1      |
| Path                 | `/v2/stocks/{symbol}/trades/latest`      | §1.1    |
| `feed`               | `sip`, always explicit, never defaulted  | §2.1, §2.2 |
| `currency`           | `USD`, always explicit                   | §2.3    |
| Number parsing       | from the decimal literal, not via `f64`  | §3.5    |
| Non-200              | refuse                                   | §4.3    |
| `u` present          | refuse                                   | §3.3    |
| `currency` present and ≠ `USD` | refuse                         | §2.3    |
| Stale `t`            | refuse beyond a threshold                | §7.1    |

## 8. What the response cannot prove

The response body contains **no echo of `feed`**. There is no field for it in
`stock_latest_trades_resp_single` or in `stock_trade` **[OAS]**. Two fields
carry something adjacent to provenance, and neither is sufficient:

- `z`, the tape, identifies the **listing** market, not the execution venue
  and not the feed. Alpaca's own IEX-feed example makes this explicit: an AAPL
  trade fetched from the IEX feed returns `"x": "V"` (Alpaca annotates it in
  the FAQ as "IEX exchange code") with `"z": "C"` — Nasdaq's tape, because
  AAPL is Nasdaq-listed. **[PROSE]**
  <https://docs.alpaca.markets/us/docs/market-data-faq.md>. So `z` cannot
  distinguish `sip` from `iex` at all.
- `x`, the exchange code, identifies the execution venue, so an `iex`-feed
  response necessarily carries the IEX code. That is an inference from what
  the `iex` feed *is* (§2.1), not a documented guarantee, and it is only a
  negative test: it can sometimes reveal an IEX-only response, but a SIP
  response legitimately carries any venue's code, so `x` can never
  *establish* that a response came from `sip`, nor separate `sip` from
  `delayed_sip`. The code mapping itself lives at a separate endpoint,
  `v2/stocks/meta/exchanges` **[OAS]**.

Combined with §0.1 — only symbol, price and time are signed — this means:

- The chain cannot tell a SIP-sourced attestation from an IEX-sourced one.
- The binary cannot tell one from the other either, from the response alone.
- Correct feed selection is a property of the operator's configuration and
  entitlement, enforced only by `agree` in `SPEC.md` item 13 catching the
  resulting price divergence after the fact, and by §6.3 making an
  IEX-restricted operator's SIP request fail outright rather than silently
  downgrade.

That last point is the mitigation and it is worth stating explicitly: because
an unentitled operator pinning `feed=sip` receives the error in §4.2 rather
than an IEX price, explicit pinning converts a silent wrong answer into a loud
refusal. Omitting `feed` does the opposite — it silently downgrades that same
operator to IEX (§2.2). This is the whole reason §7.4 says "always explicit,
never defaulted".

## 9. Terms

The OpenAPI declares `termsOfService`
<https://s3.amazonaws.com/files.alpaca.markets/disclosures/library/TermsAndConditions.pdf>
and licenses the *documentation* under CC-BY-SA-4.0 **[OAS]**. Whether
redistributing Alpaca price data as a signed on-chain attestation is permitted
by those terms is a legal question this document does not address and does not
have the sources to address. It is flagged here because it is a gating
question for the pool, not a technical one, and nobody should assume it is
settled.

## 10. Open questions

None of these may be assumed by the gate. Each has the measurement that
settles it. All measurements are against production
`https://data.alpaca.markets` with a real-time SIP entitlement unless stated.

**10.1 — Symbol character set and maximum length.**
Needed for `SPEC.md` item 6 (IntOrAString `bytes32`, 32 bytes). The OpenAPI
declares `symbol` as an unconstrained `string` (§3.2).
*Measure:* fetch `GET /v2/assets?asset_class=us_equity&status=active` from
`api.alpaca.markets`, and compute the maximum byte length and the full
character set of the `symbol` field over the whole list. Record whether any
symbol exceeds 32 bytes, and whether any contains a character outside
`[A-Z0-9.]`. Re-measure with `status=inactive` included, since a delisted
symbol may still be queryable.

**10.2 — Does `symbol` in the response always equal the requested symbol?**
§3.2 shows the historical endpoints relabel predecessor tickers; the latest
endpoints are documented as not manipulating data, but the echo is not
specified.
*Measure:* query a symbol that has been renamed and a symbol that has not,
and compare the echo to the request. Also query a lowercase symbol
(`/v2/stocks/aapl/trades/latest`) and record whether the echo is normalised to
uppercase — which determines whether the gate compares the echo
case-sensitively.

**10.3 — The full numeric grammar of `p`.**
§3.5 shows 0 to 6 decimal places in examples, including a bare integer. Not
settled: the maximum number of significant digits, whether exponential
notation (`1.7e2`) ever appears, whether a price of exactly `0` or a negative
price can appear, and whether `currency` is ever absent on a non-USD response.
*Measure:* poll the endpoint across a wide symbol set — the highest-priced
symbols, sub-dollar symbols, and recently-listed ones, with spellings taken
from the assets list in 10.1 — capturing the **raw response bytes**, not a
parsed value. Over the corpus, record: the longest integer part, the longest
fractional part, any non-`[0-9.]` character inside a number token, and any
value ≤ 0. Run the same capture with `currency=USD` explicit and with it
omitted, and diff.

**10.4 — Fractional-digit widths actually emitted for `t`, and the offset
form.**
§3.4 establishes widths 0 and 9 from Alpaca's own examples. It does **not**
establish the issue's claim that intermediate widths (e.g. 8) occur, nor that
the offset is always literal `Z`, nor that the separator is always uppercase
`T`.
*Measure:* from the same raw-bytes corpus as 10.3, histogram the number of
characters between `.` and `Z` in every `t` field, and count the
zero-fractional cases separately. If no width between 1 and 8 appears in a
large corpus that includes trades whose true nanosecond value ends in zeros,
that is evidence against trimming; if width 8 appears, the issue's claim is
confirmed. Separately, grep the corpus for any `t` not matching
`^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?Z$` and record every
exception verbatim.

**10.5 — Can `u` appear on the latest-trade endpoint?**
The field is declared on the shared `stock_trade` schema (§3.3), which the
latest and historical trade endpoints both use. If a trade is canceled, does
the latest endpoint return it with `u: "canceled"`, return the prior valid
trade, or return the canceled trade unmarked?
*Measure:* capture a corpus of latest-trade responses across a full session
and count `u` occurrences. In parallel, subscribe to the `cancelErrors` and
`corrections` stream channels for the same symbols; when a cancellation
arrives, immediately poll the latest-trade endpoint for that symbol and record
what it returns and whether the canceled price is still being served.

**10.6 — The real inter-operator spread.**
Sizes the `agree` tolerance in `SPEC.md` item 13 and the `agree-absolute`
threshold in item 14, and is the measurement that could overturn §1.1.
*Measure:* run three independent clients, on separate hosts and separate API
keys, polling the same symbol at the same nominal cadence without
coordination. Record every triple of (price, time). Report the distribution of
max/min price ratio and of max−min time, split by liquid hours, the open, the
close, and extended hours. Repeat the whole exercise against
`/v2/stocks/{symbol}/bars/latest` and compare both distributions — this is
what decides latest trade versus latest bar close on evidence.

**10.7 — The error body contract.**
§4 shows it is undeclared and shows exactly one instance.
*Measure:* deliberately provoke each declared status and capture the raw body
and all headers: 400 by `feed=nonsense` and by `currency=nonsense`; 401 by
omitting credentials; 403 by requesting `feed=sip` on an unentitled key; 429
by exceeding the per-minute limit. Record whether every body is JSON with
`code` and `message`, whether `code` is always an integer, and collect the
`code` values seen. Note that 500 cannot be provoked and stays unknown.

**10.8 — The empty / not-found shape.**
§5.
*Measure:* query `/v2/stocks/{symbol}/trades/latest` for: a syntactically
valid but unlisted symbol (`ZZZZZZ`); a delisted symbol; a halted symbol (SVA
is named by the FAQ as halted since 2019-02-22); an OTC symbol (`CGRNQ` is
named by the FAQ) without the OTC entitlement; and an empty path segment.
Record the status code and the exact body for each.

**10.9 — Rate-limit window semantics.**
§6.1.
*Measure:* burst to the limit and record `X-RateLimit-Reset` against wall
clock to determine whether it lands on a calendar-minute boundary (fixed
window) or at request-time plus 60s (sliding). Run two keys on the same
account simultaneously to determine whether the counter is per key or per
account. Capture the full header set on the 429 to see whether `Retry-After`
is present.

**10.10 — Is `delayed_sip` entitlement-free, and what is its actual delay?**
§6.3. Bears on whether an operator without Algo Trader Plus can attest at all.
*Measure:* from a Basic-plan key, request `feed=delayed_sip` on the latest
trade endpoint and record the status. If 200, poll `delayed_sip` and `sip`
side by side from an entitled key for a session and report the distribution of
the difference in `t`, to establish whether the delay is exactly 15 minutes or
merely at least 15 minutes — the difference decides whether two operators on
`delayed_sip` can agree with each other at all.

**10.11 — Do the REST endpoints serve revised values?**
§7.2 documents that bars are revised and trades are corrected on the stream.
Whether REST reflects it, and after what delay, is not documented.
*Measure:* record a `next_page_token`-free historical minute bar for a fixed
past minute, then re-fetch the identical request — same `start`, `end`,
`timeframe`, `feed`, `adjustment`, `asof`, `currency` — at +1 minute, +1 hour,
+1 day and +1 week, and diff the bytes. Any difference proves the historical
endpoint is not immutable for a fixed request, which would rule out any scheme
that assumes two operators fetching the same past interval at different times
agree.

**10.12 — Which clock stamps `t`.**
The FAQ says bar aggregation uses "The (SIP) timestamp of the trade"
**[PROSE]** <https://docs.alpaca.markets/us/docs/market-data-faq.md>, but the
OpenAPI's `timestamp` schema says only "RFC-3339 format with nanosecond
precision" and never names the clock. Whether `t` on a `feed=iex`,
`feed=boats` or `feed=overnight` response is the same clock is unstated.
*Measure:* ask Alpaca support directly, since no measurement distinguishes a
SIP stamp from a low-latency venue stamp from the outside. Record the answer
as a citable source, or leave the question open and pin `feed=sip` so that
only one clock is ever in play.

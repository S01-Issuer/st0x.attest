// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {LibContext} from "rainlang-interface-0.2.9/src/lib/caller/LibContext.sol";
import {SignedContextV1} from "rainlang-interface-0.2.9/src/interface/IInterpreterCallerV4.sol";

// The context grid the subparser's words name. It is what `LibContext.build`
// produces for a caller that passes one column of its own, the mint, followed
// by the attestations as signed contexts with the lead first:
//
//   column 0  base          [sender, calling contract]
//   column 1  mint          [symbol, amount]
//   column 2  signers       [lead, attestor 0, attestor 1, ...]
//   column 3  lead          [symbol, price, time]
//   column 4  attestor 0    [symbol, price, time]
//   column 5  attestor 1    [symbol, price, time]
//   ...
//
// A caller that wants the words to mean what they say builds its context with
// `LibSt0xAttestContext.build`, or to this grid.

/// @dev The mint being requested is the single caller column. SPEC.md item 8.
uint256 constant CONTEXT_MINT_COLUMN = 1;

/// @dev The symbol of the token being minted, as an IntOrAString bytes32 so it
/// compares binary-equal to a Rainlang string literal and to the attested
/// symbols. SPEC.md items 6 and 15.
uint256 constant CONTEXT_MINT_ROW_SYMBOL = 0;

/// @dev The amount of the token being requested, as a Rain Float. SPEC.md
/// item 5.
uint256 constant CONTEXT_MINT_ROW_AMOUNT = 1;

/// @dev Rows in the mint column.
uint256 constant CONTEXT_MINT_ROWS = 2;

/// @dev The recovered signer of each attestation, one row per attestation in
/// the order of the attestation columns. The signer is never one of the
/// attested values (SPEC.md item 7), it is recovered from the signature.
uint256 constant CONTEXT_SIGNERS_COLUMN = 2;

/// @dev The lead signs first because the lead's attestation is mandatory.
/// SPEC.md item 24.
uint256 constant CONTEXT_SIGNERS_ROW_LEAD = 0;

/// @dev Pool attestor `N` signs row `CONTEXT_SIGNERS_ROW_ATTESTOR_0 + N`. The
/// pool indexes from zero separately from the lead.
uint256 constant CONTEXT_SIGNERS_ROW_ATTESTOR_0 = 1;

/// @dev The lead's attestation is the first signed context column.
uint256 constant CONTEXT_LEAD_COLUMN = 3;

/// @dev Pool attestor `N`'s attestation is column
/// `CONTEXT_ATTESTOR_0_COLUMN + N`.
uint256 constant CONTEXT_ATTESTOR_0_COLUMN = 4;

/// @dev Every attestation carries exactly three values in this order: the
/// symbol, the price, the time. SPEC.md item 4. The rows are the same for the
/// lead's column and every pool attestor's column.
uint256 constant CONTEXT_ATTESTATION_ROW_SYMBOL = 0;

/// @dev The attested price, as a Rain Float. SPEC.md item 5.
uint256 constant CONTEXT_ATTESTATION_ROW_PRICE = 1;

/// @dev The attested time, as a Rain Float comparable against `now()`.
/// SPEC.md item 5.
uint256 constant CONTEXT_ATTESTATION_ROW_TIME = 2;

/// @dev Rows in an attestation column.
uint256 constant CONTEXT_ATTESTATION_ROWS = 3;

/// @title LibSt0xAttestContext
/// @notice Builds the context grid that the words in `LibSt0xAttestSubParser`
/// name, so a caller and the subparser agree on where everything is by
/// construction rather than by convention.
library LibSt0xAttestContext {
    /// @notice Builds the grid for one mint request and its attestations.
    /// Signature checks are `LibContext.build`'s, which reverts on any invalid
    /// signature, so every signer in the grid signed the column beside it.
    /// @param mintSymbol The symbol of the token being minted, IntOrAString.
    /// @param mintAmount The amount being requested, a Rain Float.
    /// @param attestations The signed attestations, the lead's first. Each
    /// context is `[symbol, price, time]`; the layout is not checked here
    /// because what to do with a malformed attestation is the expression's
    /// decision, and a short column reverts when a word reads past it.
    /// @return The context grid.
    function build(bytes32 mintSymbol, bytes32 mintAmount, SignedContextV1[] memory attestations)
        internal
        view
        returns (bytes32[][] memory)
    {
        bytes32[] memory mint = new bytes32[](CONTEXT_MINT_ROWS);
        mint[CONTEXT_MINT_ROW_SYMBOL] = mintSymbol;
        mint[CONTEXT_MINT_ROW_AMOUNT] = mintAmount;
        bytes32[][] memory callerContext = new bytes32[][](1);
        callerContext[0] = mint;
        return LibContext.build(callerContext, attestations);
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity ^0.8.25;

import {AuthoringMetaV2} from "rainlang-interface-0.2.9/src/interface/ISubParserV4.sol";
import {OperandV2} from "rainlang-interface-0.2.9/src/interface/IInterpreterV4.sol";
import {LibSubParse} from "rainlang-0.2.11/src/lib/parse/LibSubParse.sol";

import {
    CONTEXT_ATTESTATION_ROW_PRICE,
    CONTEXT_ATTESTATION_ROW_SYMBOL,
    CONTEXT_ATTESTATION_ROW_TIME,
    CONTEXT_ATTESTOR_0_COLUMN,
    CONTEXT_LEAD_COLUMN,
    CONTEXT_MINT_COLUMN,
    CONTEXT_MINT_ROW_AMOUNT,
    CONTEXT_MINT_ROW_SYMBOL,
    CONTEXT_SIGNERS_COLUMN,
    CONTEXT_SIGNERS_ROW_ATTESTOR_0,
    CONTEXT_SIGNERS_ROW_LEAD
} from "./LibSt0xAttestContext.sol";

/// @dev The build depth of the parse meta. One layer of bloom filter is
/// enough for ten words; the build reverts if it is not.
uint8 constant PARSE_META_BUILD_DEPTH = 1;

/// @dev Index of `lead` in the word list.
uint256 constant SUB_PARSER_WORD_LEAD = 0;
/// @dev Index of `attestor` in the word list.
uint256 constant SUB_PARSER_WORD_ATTESTOR = 1;
/// @dev Index of `lead-symbol` in the word list.
uint256 constant SUB_PARSER_WORD_LEAD_SYMBOL = 2;
/// @dev Index of `lead-price` in the word list.
uint256 constant SUB_PARSER_WORD_LEAD_PRICE = 3;
/// @dev Index of `lead-time` in the word list.
uint256 constant SUB_PARSER_WORD_LEAD_TIME = 4;
/// @dev Index of `attested-symbol` in the word list.
uint256 constant SUB_PARSER_WORD_ATTESTED_SYMBOL = 5;
/// @dev Index of `attested-price` in the word list.
uint256 constant SUB_PARSER_WORD_ATTESTED_PRICE = 6;
/// @dev Index of `attested-time` in the word list.
uint256 constant SUB_PARSER_WORD_ATTESTED_TIME = 7;
/// @dev Index of `mint-symbol` in the word list.
uint256 constant SUB_PARSER_WORD_MINT_SYMBOL = 8;
/// @dev Index of `mint-amount` in the word list.
uint256 constant SUB_PARSER_WORD_MINT_AMOUNT = 9;

/// @dev The number of words. The parse meta, the word parsers and the operand
/// handlers are all indexed by the constants above, so all three are this
/// long.
uint256 constant SUB_PARSER_WORD_PARSERS_LENGTH = 10;

/// @title LibSt0xAttestSubParser
/// @notice The words of SPEC.md item 11. Each one names a cell of the grid in
/// `LibSt0xAttestContext` and subparses to a plain `context` opcode, so at
/// eval it costs exactly what the `context<column row>()` it replaces would.
///
/// `lead` and `attestor<N>` read the signers column, because the signer is
/// recovered from the signature rather than being an attested value. `lead`
/// is its own word rather than attestation zero of a uniform list because the
/// lead's attestation is mandatory while the pool is a threshold of
/// interchangeable operators, so the pool indexes from zero separately.
///
/// A word whose cell is not in the grid at eval, such as `attestor<3>` when
/// two pool attestations were provided, reverts there: the `context` opcode
/// bounds-checks its read. A missing attestation is a failed check, not a
/// zero.
library LibSt0xAttestSubParser {
    /// @notice `lead`: the address recovered from the lead's signature.
    /// @return Whether the sub parse succeeded.
    /// @return The bytecode for the context opcode.
    /// @return The constants for the context opcode, always empty.
    //slither-disable-next-line dead-code
    function subParserLead(uint256, uint256, OperandV2) internal pure returns (bool, bytes memory, bytes32[] memory) {
        //slither-disable-next-line unused-return
        return LibSubParse.subParserContext(CONTEXT_SIGNERS_COLUMN, CONTEXT_SIGNERS_ROW_LEAD);
    }

    /// @notice `attestor<N>`: the address recovered from pool attestation
    /// `N`'s signature.
    /// @param operand `N`, a uint16 from the operand handler. `subParserContext`
    /// reverts `ContextGridOverflow` past a byte, so the sum cannot overflow
    /// and an out of range `N` is a parse error rather than a wrong row.
    /// @return Whether the sub parse succeeded.
    /// @return The bytecode for the context opcode.
    /// @return The constants for the context opcode, always empty.
    //slither-disable-next-line dead-code
    function subParserAttestor(uint256, uint256, OperandV2 operand)
        internal
        pure
        returns (bool, bytes memory, bytes32[] memory)
    {
        //slither-disable-next-line unused-return
        return LibSubParse.subParserContext(
            CONTEXT_SIGNERS_COLUMN, CONTEXT_SIGNERS_ROW_ATTESTOR_0 + uint256(OperandV2.unwrap(operand))
        );
    }

    /// @notice `lead-symbol`: the symbol the lead attested.
    /// @return Whether the sub parse succeeded.
    /// @return The bytecode for the context opcode.
    /// @return The constants for the context opcode, always empty.
    //slither-disable-next-line dead-code
    function subParserLeadSymbol(uint256, uint256, OperandV2)
        internal
        pure
        returns (bool, bytes memory, bytes32[] memory)
    {
        //slither-disable-next-line unused-return
        return LibSubParse.subParserContext(CONTEXT_LEAD_COLUMN, CONTEXT_ATTESTATION_ROW_SYMBOL);
    }

    /// @notice `lead-price`: the price the lead attested.
    /// @return Whether the sub parse succeeded.
    /// @return The bytecode for the context opcode.
    /// @return The constants for the context opcode, always empty.
    //slither-disable-next-line dead-code
    function subParserLeadPrice(uint256, uint256, OperandV2)
        internal
        pure
        returns (bool, bytes memory, bytes32[] memory)
    {
        //slither-disable-next-line unused-return
        return LibSubParse.subParserContext(CONTEXT_LEAD_COLUMN, CONTEXT_ATTESTATION_ROW_PRICE);
    }

    /// @notice `lead-time`: the time the lead attested.
    /// @return Whether the sub parse succeeded.
    /// @return The bytecode for the context opcode.
    /// @return The constants for the context opcode, always empty.
    //slither-disable-next-line dead-code
    function subParserLeadTime(uint256, uint256, OperandV2)
        internal
        pure
        returns (bool, bytes memory, bytes32[] memory)
    {
        //slither-disable-next-line unused-return
        return LibSubParse.subParserContext(CONTEXT_LEAD_COLUMN, CONTEXT_ATTESTATION_ROW_TIME);
    }

    /// @notice `attested-symbol<N>`: the symbol pool attestor `N` attested.
    /// @param operand `N`.
    /// @return Whether the sub parse succeeded.
    /// @return The bytecode for the context opcode.
    /// @return The constants for the context opcode, always empty.
    //slither-disable-next-line dead-code
    function subParserAttestedSymbol(uint256, uint256, OperandV2 operand)
        internal
        pure
        returns (bool, bytes memory, bytes32[] memory)
    {
        //slither-disable-next-line unused-return
        return LibSubParse.subParserContext(
            CONTEXT_ATTESTOR_0_COLUMN + uint256(OperandV2.unwrap(operand)), CONTEXT_ATTESTATION_ROW_SYMBOL
        );
    }

    /// @notice `attested-price<N>`: the price pool attestor `N` attested.
    /// @param operand `N`.
    /// @return Whether the sub parse succeeded.
    /// @return The bytecode for the context opcode.
    /// @return The constants for the context opcode, always empty.
    //slither-disable-next-line dead-code
    function subParserAttestedPrice(uint256, uint256, OperandV2 operand)
        internal
        pure
        returns (bool, bytes memory, bytes32[] memory)
    {
        //slither-disable-next-line unused-return
        return LibSubParse.subParserContext(
            CONTEXT_ATTESTOR_0_COLUMN + uint256(OperandV2.unwrap(operand)), CONTEXT_ATTESTATION_ROW_PRICE
        );
    }

    /// @notice `attested-time<N>`: the time pool attestor `N` attested.
    /// @param operand `N`.
    /// @return Whether the sub parse succeeded.
    /// @return The bytecode for the context opcode.
    /// @return The constants for the context opcode, always empty.
    //slither-disable-next-line dead-code
    function subParserAttestedTime(uint256, uint256, OperandV2 operand)
        internal
        pure
        returns (bool, bytes memory, bytes32[] memory)
    {
        //slither-disable-next-line unused-return
        return LibSubParse.subParserContext(
            CONTEXT_ATTESTOR_0_COLUMN + uint256(OperandV2.unwrap(operand)), CONTEXT_ATTESTATION_ROW_TIME
        );
    }

    /// @notice `mint-symbol`: the symbol of the token being minted.
    /// @return Whether the sub parse succeeded.
    /// @return The bytecode for the context opcode.
    /// @return The constants for the context opcode, always empty.
    //slither-disable-next-line dead-code
    function subParserMintSymbol(uint256, uint256, OperandV2)
        internal
        pure
        returns (bool, bytes memory, bytes32[] memory)
    {
        //slither-disable-next-line unused-return
        return LibSubParse.subParserContext(CONTEXT_MINT_COLUMN, CONTEXT_MINT_ROW_SYMBOL);
    }

    /// @notice `mint-amount`: the amount the mint is requesting.
    /// @return Whether the sub parse succeeded.
    /// @return The bytecode for the context opcode.
    /// @return The constants for the context opcode, always empty.
    //slither-disable-next-line dead-code
    function subParserMintAmount(uint256, uint256, OperandV2)
        internal
        pure
        returns (bool, bytes memory, bytes32[] memory)
    {
        //slither-disable-next-line unused-return
        return LibSubParse.subParserContext(CONTEXT_MINT_COLUMN, CONTEXT_MINT_ROW_AMOUNT);
    }

    /// @notice The authoring meta for every word, in word index order. Tooling
    /// reads it to describe the words to an author and `script/Build.sol`
    /// builds the parse meta from it.
    /// @return The ABI encoded `AuthoringMetaV2[]`.
    //slither-disable-next-line dead-code
    function authoringMetaV2() internal pure returns (bytes memory) {
        AuthoringMetaV2[] memory meta = new AuthoringMetaV2[](SUB_PARSER_WORD_PARSERS_LENGTH);
        meta[SUB_PARSER_WORD_LEAD] = AuthoringMetaV2(
            "lead",
            "The address recovered from the lead attestation's signature. The lead's attestation is mandatory, so it is its own word and never attestor<0>. No operand. An identity: compare it with binary-equal-to, binary-in or binary-unique, never numerically."
        );
        meta[SUB_PARSER_WORD_ATTESTOR] = AuthoringMetaV2(
            "attestor",
            "The address recovered from pool attestation N's signature, where N is the operand and is required. The pool indexes from zero separately from the lead, so attestor<0> is the first pool attestor. An identity: compare it with binary-equal-to, binary-in or binary-unique, never numerically. Reverts at eval if fewer than N+1 pool attestations were provided."
        );
        meta[SUB_PARSER_WORD_LEAD_SYMBOL] = AuthoringMetaV2(
            "lead-symbol",
            "The token symbol the lead attested, as an IntOrAString bytes32, so a Rainlang string literal compares equal to it. No operand. A string: compare it with binary-equal-to, never numerically."
        );
        meta[SUB_PARSER_WORD_LEAD_PRICE] =
            AuthoringMetaV2("lead-price", "The price the lead attested, as a Rain Float. No operand.");
        meta[SUB_PARSER_WORD_LEAD_TIME] = AuthoringMetaV2(
            "lead-time", "The time the lead attested, as a Rain Float in seconds comparable against now(). No operand."
        );
        meta[SUB_PARSER_WORD_ATTESTED_SYMBOL] = AuthoringMetaV2(
            "attested-symbol",
            "The token symbol pool attestor N attested, as an IntOrAString bytes32, so a Rainlang string literal compares equal to it. N is the operand and is required. A string: compare it with binary-equal-to, never numerically. Reverts at eval if fewer than N+1 pool attestations were provided."
        );
        meta[SUB_PARSER_WORD_ATTESTED_PRICE] = AuthoringMetaV2(
            "attested-price",
            "The price pool attestor N attested, as a Rain Float. N is the operand and is required. Reverts at eval if fewer than N+1 pool attestations were provided."
        );
        meta[SUB_PARSER_WORD_ATTESTED_TIME] = AuthoringMetaV2(
            "attested-time",
            "The time pool attestor N attested, as a Rain Float in seconds comparable against now(). N is the operand and is required. Reverts at eval if fewer than N+1 pool attestations were provided."
        );
        meta[SUB_PARSER_WORD_MINT_SYMBOL] = AuthoringMetaV2(
            "mint-symbol",
            "The symbol of the token the mint is requested for, as an IntOrAString bytes32. Check every attested symbol against it so an attestation for one token cannot be used for a mint of another. No operand. A string: compare it with binary-equal-to, never numerically."
        );
        meta[SUB_PARSER_WORD_MINT_AMOUNT] = AuthoringMetaV2(
            "mint-amount", "The amount of the token being requested for the mint, as a Rain Float. No operand."
        );
        return abi.encode(meta);
    }
}

// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {AuthoringMetaV2} from "rainlang-interface-0.2.9/src/interface/ISubParserV4.sol";
import {LibGenParseMeta} from "rainlang-interface-0.2.9/src/lib/codegen/LibGenParseMeta.sol";

import {St0xAttestSubParser} from "src/concrete/St0xAttestSubParser.sol";
import {
    LibSt0xAttestSubParser,
    PARSE_META_BUILD_DEPTH,
    SUB_PARSER_WORD_PARSERS_LENGTH
} from "src/lib/LibSt0xAttestSubParser.sol";
import {
    BYTECODE_HASH,
    PARSE_META,
    PARSE_META_BUILD_DEPTH as GENERATED_PARSE_META_BUILD_DEPTH,
    SUB_PARSER_WORD_PARSERS,
    OPERAND_HANDLER_FUNCTION_POINTERS,
    LITERAL_PARSER_FUNCTION_POINTERS
} from "src/generated/St0xAttestSubParserPointers.sol";

/// Every table the subparser dispatches on is a committed constant. These
/// tests prove the constants are what `script/Build.sol` would generate from
/// the current source, because a stale table dispatches the wrong word.
contract St0xAttestSubParserPointersTest is Test {
    function testBytecodeHash() external {
        St0xAttestSubParser subParser = new St0xAttestSubParser();
        assertEq(address(subParser).codehash, BYTECODE_HASH);
    }

    function testParseMeta() external pure {
        AuthoringMetaV2[] memory authoringMeta =
            abi.decode(LibSt0xAttestSubParser.authoringMetaV2(), (AuthoringMetaV2[]));
        assertEq(authoringMeta.length, SUB_PARSER_WORD_PARSERS_LENGTH);
        assertEq(PARSE_META, LibGenParseMeta.buildParseMetaV2(authoringMeta, PARSE_META_BUILD_DEPTH));
        assertEq(GENERATED_PARSE_META_BUILD_DEPTH, PARSE_META_BUILD_DEPTH);
    }

    function testSubParserWordParsers() external {
        St0xAttestSubParser subParser = new St0xAttestSubParser();
        assertEq(SUB_PARSER_WORD_PARSERS, subParser.buildSubParserWordParsers());
        assertEq(SUB_PARSER_WORD_PARSERS.length, SUB_PARSER_WORD_PARSERS_LENGTH * 2);
    }

    function testOperandHandlerFunctionPointers() external {
        St0xAttestSubParser subParser = new St0xAttestSubParser();
        assertEq(OPERAND_HANDLER_FUNCTION_POINTERS, subParser.buildOperandHandlerFunctionPointers());
        assertEq(OPERAND_HANDLER_FUNCTION_POINTERS.length, SUB_PARSER_WORD_PARSERS_LENGTH * 2);
    }

    function testLiteralParserFunctionPointers() external {
        St0xAttestSubParser subParser = new St0xAttestSubParser();
        assertEq(LITERAL_PARSER_FUNCTION_POINTERS, subParser.buildLiteralParserFunctionPointers());
        assertEq(LITERAL_PARSER_FUNCTION_POINTERS.length, 0);
    }

    /// The word list is exactly SPEC.md item 11, in the index order the
    /// tables are built in.
    function testWordList() external pure {
        AuthoringMetaV2[] memory authoringMeta =
            abi.decode(LibSt0xAttestSubParser.authoringMetaV2(), (AuthoringMetaV2[]));
        string[10] memory expected = [
            "lead",
            "attestor",
            "lead-symbol",
            "lead-price",
            "lead-time",
            "attested-symbol",
            "attested-price",
            "attested-time",
            "mint-symbol",
            "mint-amount"
        ];
        assertEq(authoringMeta.length, expected.length);
        for (uint256 i = 0; i < expected.length; i++) {
            assertEq(authoringMeta[i].word, bytes32(bytes(expected[i])));
            assertGt(bytes(authoringMeta[i].description).length, 0);
        }
    }
}

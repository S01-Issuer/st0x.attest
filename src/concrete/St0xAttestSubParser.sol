// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {
    BaseRainlangSubParser,
    IParserToolingV1,
    ISubParserToolingV1,
    OperandV2
} from "rainlang-0.2.11/src/abstract/BaseRainlangSubParser.sol";
import {LibParseOperand} from "rainlang-0.2.11/src/lib/parse/LibParseOperand.sol";
import {BadDynamicLength} from "rainlang-0.2.11/src/error/ErrOpList.sol";
import {LibConvert} from "rain-lib-typecast-0.1.4/src/LibConvert.sol";
import {IDescribedByMetaV1} from "rain-metadata-0.1.7/src/interface/IDescribedByMetaV1.sol";

import {LibSt0xAttestSubParser, SUB_PARSER_WORD_PARSERS_LENGTH} from "../lib/LibSt0xAttestSubParser.sol";
import {
    DESCRIBED_BY_META_HASH,
    PARSE_META as SUB_PARSER_PARSE_META,
    SUB_PARSER_WORD_PARSERS,
    OPERAND_HANDLER_FUNCTION_POINTERS as SUB_PARSER_OPERAND_HANDLERS
} from "../generated/St0xAttestSubParserPointers.sol";

/// @title St0xAttestSubParser
/// @notice The subparser of SPEC.md item 11. Registered in an expression with
/// `using-words-from`, it provides `lead`, `attestor<N>`, `lead-symbol`,
/// `lead-price`, `lead-time`, `attested-symbol<N>`, `attested-price<N>`,
/// `attested-time<N>`, `mint-symbol` and `mint-amount`, each of which
/// compiles to a `context` read of the grid in `LibSt0xAttestContext`.
///
/// Every table the base contract dispatches on is a constant from
/// `src/generated/St0xAttestSubParserPointers.sol`, which `script/Build.sol`
/// regenerates from the `build*` functions below. The tests assert the two
/// agree, because a stale table dispatches the wrong word.
contract St0xAttestSubParser is BaseRainlangSubParser {
    /// @inheritdoc IDescribedByMetaV1
    function describedByMetaV1() external pure returns (bytes32) {
        return DESCRIBED_BY_META_HASH;
    }

    /// @inheritdoc BaseRainlangSubParser
    function subParserParseMeta() internal pure virtual override returns (bytes memory) {
        return SUB_PARSER_PARSE_META;
    }

    /// @inheritdoc BaseRainlangSubParser
    function subParserWordParsers() internal pure virtual override returns (bytes memory) {
        return SUB_PARSER_WORD_PARSERS;
    }

    /// @inheritdoc BaseRainlangSubParser
    function subParserOperandHandlers() internal pure virtual override returns (bytes memory) {
        return SUB_PARSER_OPERAND_HANDLERS;
    }

    /// @notice No literals. Every value an expression needs is a context cell
    /// named by a word, or a standard Rainlang literal.
    /// @inheritdoc IParserToolingV1
    function buildLiteralParserFunctionPointers() external pure override returns (bytes memory) {
        return "";
    }

    /// @notice One handler per word, in word index order. The words with an
    /// `<N>` take exactly one operand; the rest take none.
    /// @inheritdoc IParserToolingV1
    function buildOperandHandlerFunctionPointers() external pure override returns (bytes memory) {
        unchecked {
            function(bytes32[] memory) internal pure returns (OperandV2) lengthPointer;
            uint256 length = SUB_PARSER_WORD_PARSERS_LENGTH;
            assembly ("memory-safe") {
                lengthPointer := length
            }
            function(bytes32[] memory) internal pure returns (OperandV2)[SUB_PARSER_WORD_PARSERS_LENGTH + 1] memory
                handlersFixed = [
                    lengthPointer,
                    // lead
                    LibParseOperand.handleOperandDisallowed,
                    // attestor<N>
                    LibParseOperand.handleOperandSingleFullNoDefault,
                    // lead-symbol
                    LibParseOperand.handleOperandDisallowed,
                    // lead-price
                    LibParseOperand.handleOperandDisallowed,
                    // lead-time
                    LibParseOperand.handleOperandDisallowed,
                    // attested-symbol<N>
                    LibParseOperand.handleOperandSingleFullNoDefault,
                    // attested-price<N>
                    LibParseOperand.handleOperandSingleFullNoDefault,
                    // attested-time<N>
                    LibParseOperand.handleOperandSingleFullNoDefault,
                    // mint-symbol
                    LibParseOperand.handleOperandDisallowed,
                    // mint-amount
                    LibParseOperand.handleOperandDisallowed
                ];
            uint256[] memory handlersDynamic;
            assembly ("memory-safe") {
                handlersDynamic := handlersFixed
            }
            if (handlersDynamic.length != length) {
                revert BadDynamicLength(handlersDynamic.length, length);
            }
            return LibConvert.unsafeTo16BitBytes(handlersDynamic);
        }
    }

    /// @notice One parser per word, in word index order.
    /// @inheritdoc ISubParserToolingV1
    function buildSubParserWordParsers() external pure override returns (bytes memory) {
        unchecked {
            function(uint256, uint256, OperandV2) internal pure returns (bool, bytes memory, bytes32[] memory)
                lengthPointer;
            uint256 length = SUB_PARSER_WORD_PARSERS_LENGTH;
            assembly ("memory-safe") {
                lengthPointer := length
            }
            function(uint256, uint256, OperandV2)
                internal
                pure returns (bool, bytes memory, bytes32[] memory)[SUB_PARSER_WORD_PARSERS_LENGTH + 1] memory
                parsersFixed = [
                    lengthPointer,
                    LibSt0xAttestSubParser.subParserLead,
                    LibSt0xAttestSubParser.subParserAttestor,
                    LibSt0xAttestSubParser.subParserLeadSymbol,
                    LibSt0xAttestSubParser.subParserLeadPrice,
                    LibSt0xAttestSubParser.subParserLeadTime,
                    LibSt0xAttestSubParser.subParserAttestedSymbol,
                    LibSt0xAttestSubParser.subParserAttestedPrice,
                    LibSt0xAttestSubParser.subParserAttestedTime,
                    LibSt0xAttestSubParser.subParserMintSymbol,
                    LibSt0xAttestSubParser.subParserMintAmount
                ];
            uint256[] memory parsersDynamic;
            assembly ("memory-safe") {
                parsersDynamic := parsersFixed
            }
            if (parsersDynamic.length != length) {
                revert BadDynamicLength(parsersDynamic.length, length);
            }
            return LibConvert.unsafeTo16BitBytes(parsersDynamic);
        }
    }
}

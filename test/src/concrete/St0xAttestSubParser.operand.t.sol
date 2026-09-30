// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Strings} from "@openzeppelin-contracts-5.6.1/utils/Strings.sol";
import {
    ExpectedOperand,
    UnexpectedOperand,
    UnexpectedOperandValue,
    OperandOverflow,
    UnknownWord
} from "rainlang-0.2.11/src/error/ErrParse.sol";
import {ContextGridOverflow} from "rainlang-0.2.11/src/error/ErrSubParse.sol";

import {St0xAttestSubParserTest} from "test/abstract/St0xAttestSubParserTest.sol";
import {
    CONTEXT_SIGNERS_COLUMN,
    CONTEXT_SIGNERS_ROW_ATTESTOR_0,
    CONTEXT_ATTESTOR_0_COLUMN,
    CONTEXT_ATTESTATION_ROW_SYMBOL,
    CONTEXT_ATTESTATION_ROW_PRICE,
    CONTEXT_ATTESTATION_ROW_TIME
} from "src/lib/LibSt0xAttestContext.sol";

/// The operand rules: `<N>` words take exactly one `N`, the others take none,
/// and an `N` that does not fit the grid is a parse error.
contract St0xAttestSubParserOperandTest is St0xAttestSubParserTest {
    using Strings for uint256;

    function checkParseReverts(string memory word, bytes memory err) internal {
        checkUnhappyParse2(bytes(string.concat(usingWords(), "_: ", word, ";")), err);
    }

    function testUnknownWord() external {
        checkParseReverts("attestation()", abi.encodeWithSelector(UnknownWord.selector, "attestation"));
        checkParseReverts("lead-signer()", abi.encodeWithSelector(UnknownWord.selector, "lead-signer"));
    }

    /// The words without an `N` reject one.
    function testOperandDisallowed() external {
        checkParseReverts("lead<0>()", abi.encodeWithSelector(UnexpectedOperand.selector));
        checkParseReverts("lead-symbol<0>()", abi.encodeWithSelector(UnexpectedOperand.selector));
        checkParseReverts("lead-price<0>()", abi.encodeWithSelector(UnexpectedOperand.selector));
        checkParseReverts("lead-time<0>()", abi.encodeWithSelector(UnexpectedOperand.selector));
        checkParseReverts("mint-symbol<0>()", abi.encodeWithSelector(UnexpectedOperand.selector));
        checkParseReverts("mint-amount<0>()", abi.encodeWithSelector(UnexpectedOperand.selector));
    }

    /// The words with an `N` require it: there is no default pool attestor.
    function testOperandRequired() external {
        checkParseReverts("attestor()", abi.encodeWithSelector(ExpectedOperand.selector));
        checkParseReverts("attested-symbol()", abi.encodeWithSelector(ExpectedOperand.selector));
        checkParseReverts("attested-price()", abi.encodeWithSelector(ExpectedOperand.selector));
        checkParseReverts("attested-time()", abi.encodeWithSelector(ExpectedOperand.selector));
    }

    /// Exactly one `N`.
    function testOperandSingle() external {
        checkParseReverts("attestor<0 1>()", abi.encodeWithSelector(UnexpectedOperandValue.selector));
        checkParseReverts("attested-symbol<0 1>()", abi.encodeWithSelector(UnexpectedOperandValue.selector));
        checkParseReverts("attested-price<0 1>()", abi.encodeWithSelector(UnexpectedOperandValue.selector));
        checkParseReverts("attested-time<0 1>()", abi.encodeWithSelector(UnexpectedOperandValue.selector));
    }

    /// `N` past the operand's own width.
    function testOperandOverflow() external {
        checkParseReverts("attestor<65536>()", abi.encodeWithSelector(OperandOverflow.selector));
        checkParseReverts("attested-price<65536>()", abi.encodeWithSelector(OperandOverflow.selector));
    }

    /// `N` that fits the operand but not the context grid is caught at parse
    /// time by the grid's own byte-wide addressing, never wrapped.
    function testOperandPastGrid() external {
        uint256 lastSignerN = type(uint8).max - CONTEXT_SIGNERS_ROW_ATTESTOR_0;
        checkParseReverts(
            string.concat("attestor<", (lastSignerN + 1).toString(), ">()"),
            abi.encodeWithSelector(ContextGridOverflow.selector, CONTEXT_SIGNERS_COLUMN, uint256(type(uint8).max) + 1)
        );

        uint256 lastColumnN = type(uint8).max - CONTEXT_ATTESTOR_0_COLUMN;
        string memory operand = string.concat("<", (lastColumnN + 1).toString(), ">()");
        checkParseReverts(
            string.concat("attested-symbol", operand),
            abi.encodeWithSelector(
                ContextGridOverflow.selector, uint256(type(uint8).max) + 1, CONTEXT_ATTESTATION_ROW_SYMBOL
            )
        );
        checkParseReverts(
            string.concat("attested-price", operand),
            abi.encodeWithSelector(
                ContextGridOverflow.selector, uint256(type(uint8).max) + 1, CONTEXT_ATTESTATION_ROW_PRICE
            )
        );
        checkParseReverts(
            string.concat("attested-time", operand),
            abi.encodeWithSelector(
                ContextGridOverflow.selector, uint256(type(uint8).max) + 1, CONTEXT_ATTESTATION_ROW_TIME
            )
        );
    }

    /// The largest `N` the grid can address parses.
    function testOperandAtGridEdge() external view {
        uint256 lastSignerN = type(uint8).max - CONTEXT_SIGNERS_ROW_ATTESTOR_0;
        I_DEPLOYER.parse2(bytes(string.concat(usingWords(), "_: attestor<", lastSignerN.toString(), ">();")));

        uint256 lastColumnN = type(uint8).max - CONTEXT_ATTESTOR_0_COLUMN;
        I_DEPLOYER.parse2(bytes(string.concat(usingWords(), "_: attested-price<", lastColumnN.toString(), ">();")));
    }
}

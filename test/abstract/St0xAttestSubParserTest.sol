// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {OpTest} from "rainlang-0.2.11/test/abstract/OpTest.sol";
import {Strings} from "@openzeppelin-contracts-5.6.1/utils/Strings.sol";
import {MessageHashUtils} from "@openzeppelin-contracts-5.6.1/utils/cryptography/MessageHashUtils.sol";
import {LibHashNoAlloc} from "rain-lib-hash-0.1.0/src/LibHashNoAlloc.sol";
import {SignedContextV1} from "rainlang-interface-0.2.9/src/interface/IInterpreterCallerV4.sol";
import {
    EvalV4,
    SourceIndexV2,
    StackItem,
    FullyQualifiedNamespace
} from "rainlang-interface-0.2.9/src/interface/IInterpreterV4.sol";
import {LibDecimalFloat, Float} from "rain-math-float-0.2.4/src/lib/LibDecimalFloat.sol";
import {LibIntOrAString, IntOrAString} from "rain-intorastring-0.1.0/src/lib/LibIntOrAString.sol";

import {St0xAttestSubParser} from "src/concrete/St0xAttestSubParser.sol";
import {LibSt0xAttestContext, CONTEXT_ATTESTATION_ROWS} from "src/lib/LibSt0xAttestContext.sol";

/// @title St0xAttestSubParserTest
/// @notice Binds a `St0xAttestSubParser` beside the Rainlang that `OpTest`
/// deploys, and signs attestations the way a caller would, so the tests parse
/// and eval real expressions over a real grid.
abstract contract St0xAttestSubParserTest is OpTest {
    using Strings for address;

    /// @dev Private key of the lead signer.
    uint256 internal constant LEAD_KEY = 0x1EAD;
    /// @dev Private key of pool operator `i` is `OPERATOR_KEY_0 + i`.
    uint256 internal constant OPERATOR_KEY_0 = 0x0A00;

    //solhint-disable-next-line private-vars-leading-underscore
    St0xAttestSubParser internal immutable I_SUB_PARSER;

    constructor() {
        I_SUB_PARSER = new St0xAttestSubParser();
    }

    /// The `using-words-from` pragma for the subparser under test.
    function usingWords() internal view returns (string memory) {
        return string.concat("using-words-from ", address(I_SUB_PARSER).toHexString(), "\n");
    }

    /// A symbol as the grid holds it and as a Rainlang string literal parses.
    function symbol(string memory s) internal pure returns (bytes32) {
        return bytes32(IntOrAString.unwrap(LibIntOrAString.fromStringV3(s)));
    }

    /// An integer as a Rain Float.
    function float(int256 value) internal pure returns (bytes32) {
        return Float.unwrap(LibDecimalFloat.packLossless(value, 0));
    }

    /// The signers column encoding of an address.
    function signer(address account) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(account)));
    }

    /// An attestation of `[symbol, price, time]` signed by `key`, exactly as
    /// `LibContext.build` verifies it.
    function attest(uint256 key, bytes32 attestedSymbol, bytes32 price, bytes32 time)
        internal
        pure
        returns (SignedContextV1 memory)
    {
        bytes32[] memory context = new bytes32[](CONTEXT_ATTESTATION_ROWS);
        context[0] = attestedSymbol;
        context[1] = price;
        context[2] = time;
        return sign(key, context);
    }

    /// Signs an arbitrary column as an attestation, for the tests that need a
    /// malformed one.
    function sign(uint256 key, bytes32[] memory context) internal pure returns (SignedContextV1 memory) {
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(key, MessageHashUtils.toEthSignedMessageHash(LibHashNoAlloc.hashWords(context)));
        return SignedContextV1({signer: vm.addr(key), context: context, signature: abi.encodePacked(r, s, v)});
    }

    /// Evals `word` as the only stack item against `context`.
    function evalWord(string memory word, bytes32[][] memory context) internal view returns (bytes32) {
        (StackItem[] memory stack,) = parseAndEval(bytes(string.concat(usingWords(), "_: ", word, ";")), context);
        assertEq(stack.length, 1, word);
        return StackItem.unwrap(stack[0]);
    }

    /// Asserts `word` evals to `expected` against `context`.
    function checkWord(string memory word, bytes32[][] memory context, bytes32 expected) internal view {
        assertEq(evalWord(word, context), expected, word);
    }

    /// Asserts that evaluating `rainlang` against `context` reverts with
    /// `err`. Parsing is expected to succeed.
    function checkEvalReverts(bytes memory rainlang, bytes32[][] memory context, bytes memory err) internal {
        bytes memory bytecode = I_DEPLOYER.parse2(rainlang);
        vm.expectRevert(err);
        I_INTERPRETER.eval4(
            EvalV4({
                store: I_STORE,
                namespace: FullyQualifiedNamespace.wrap(0),
                bytecode: bytecode,
                sourceIndex: SourceIndexV2.wrap(0),
                context: context,
                inputs: new StackItem[](0),
                stateOverlay: new bytes32[](0)
            })
        );
    }

    /// Asserts that evaluating `word` against `context` reverts with `err`.
    function checkWordReverts(string memory word, bytes32[][] memory context, bytes memory err) internal {
        checkEvalReverts(bytes(string.concat(usingWords(), "_: ", word, ";")), context, err);
    }

    /// A grid with the lead and `poolSize` pool attestors all attesting the
    /// same `[symbol, price, time]`, and the given mint.
    function uniformGrid(
        bytes32 mintSymbol,
        bytes32 mintAmount,
        bytes32 attestedSymbol,
        bytes32 price,
        bytes32 time,
        uint256 poolSize
    ) internal view returns (bytes32[][] memory) {
        SignedContextV1[] memory attestations = new SignedContextV1[](poolSize + 1);
        attestations[0] = attest(LEAD_KEY, attestedSymbol, price, time);
        for (uint256 i = 0; i < poolSize; i++) {
            attestations[i + 1] = attest(OPERATOR_KEY_0 + i, attestedSymbol, price, time);
        }
        return LibSt0xAttestContext.build(mintSymbol, mintAmount, attestations);
    }
}

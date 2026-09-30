// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Strings} from "@openzeppelin-contracts-5.6.1/utils/Strings.sol";
import {stdError} from "forge-std-1.16.2/src/StdError.sol";
import {SignedContextV1} from "rainlang-interface-0.2.9/src/interface/IInterpreterCallerV4.sol";

import {St0xAttestSubParserTest} from "test/abstract/St0xAttestSubParserTest.sol";
import {LibSt0xAttestContext} from "src/lib/LibSt0xAttestContext.sol";

/// Every word reads the cell of the grid it names, and nothing else.
contract St0xAttestSubParserWordsTest is St0xAttestSubParserTest {
    using Strings for uint256;

    /// The lead and two distinct pool attestors, each attesting different
    /// values, so a word reading the wrong column or row is caught.
    function testWordsReadTheirCell() external view {
        SignedContextV1[] memory attestations = new SignedContextV1[](3);
        attestations[0] = attest(LEAD_KEY, symbol("AAPL"), float(150), float(1000));
        attestations[1] = attest(OPERATOR_KEY_0, symbol("AAPL-0"), float(151), float(1001));
        attestations[2] = attest(OPERATOR_KEY_0 + 1, symbol("AAPL-1"), float(152), float(1002));
        bytes32[][] memory context = LibSt0xAttestContext.build(symbol("MINT"), float(10), attestations);

        checkWord("lead()", context, signer(vm.addr(LEAD_KEY)));
        checkWord("attestor<0>()", context, signer(vm.addr(OPERATOR_KEY_0)));
        checkWord("attestor<1>()", context, signer(vm.addr(OPERATOR_KEY_0 + 1)));

        checkWord("lead-symbol()", context, symbol("AAPL"));
        checkWord("lead-price()", context, float(150));
        checkWord("lead-time()", context, float(1000));

        checkWord("attested-symbol<0>()", context, symbol("AAPL-0"));
        checkWord("attested-price<0>()", context, float(151));
        checkWord("attested-time<0>()", context, float(1001));

        checkWord("attested-symbol<1>()", context, symbol("AAPL-1"));
        checkWord("attested-price<1>()", context, float(152));
        checkWord("attested-time<1>()", context, float(1002));

        checkWord("mint-symbol()", context, symbol("MINT"));
        checkWord("mint-amount()", context, float(10));
    }

    /// The words are plain reads: whatever bytes were signed come back
    /// untouched, for any pool size the operand can address in a test.
    function testWordsFuzz(
        bytes32 mintSymbol,
        bytes32 mintAmount,
        bytes32[3] memory leadValues,
        bytes32[3] memory poolValues,
        uint8 poolSize,
        uint8 n
    ) external view {
        poolSize = uint8(bound(poolSize, 1, 8));
        n = uint8(bound(n, 0, poolSize - 1));

        SignedContextV1[] memory attestations = new SignedContextV1[](poolSize + 1);
        attestations[0] = attest(LEAD_KEY, leadValues[0], leadValues[1], leadValues[2]);
        for (uint256 i = 0; i < poolSize; i++) {
            // Each pool attestor signs its own index into the values so the
            // column read is distinguishable from its neighbours.
            attestations[i + 1] = attest(
                OPERATOR_KEY_0 + i, poolValues[0] ^ bytes32(i), poolValues[1] ^ bytes32(i), poolValues[2] ^ bytes32(i)
            );
        }
        bytes32[][] memory context = LibSt0xAttestContext.build(mintSymbol, mintAmount, attestations);

        checkWord("lead()", context, signer(vm.addr(LEAD_KEY)));
        checkWord("lead-symbol()", context, leadValues[0]);
        checkWord("lead-price()", context, leadValues[1]);
        checkWord("lead-time()", context, leadValues[2]);
        checkWord("mint-symbol()", context, mintSymbol);
        checkWord("mint-amount()", context, mintAmount);

        string memory operand = string.concat("<", uint256(n).toString(), ">()");
        checkWord(string.concat("attestor", operand), context, signer(vm.addr(OPERATOR_KEY_0 + n)));
        checkWord(string.concat("attested-symbol", operand), context, poolValues[0] ^ bytes32(uint256(n)));
        checkWord(string.concat("attested-price", operand), context, poolValues[1] ^ bytes32(uint256(n)));
        checkWord(string.concat("attested-time", operand), context, poolValues[2] ^ bytes32(uint256(n)));
    }

    /// A pool attestor that was not provided is an out of bounds context
    /// read, so the eval reverts rather than reading a zero.
    function testMissingPoolAttestorReverts(uint8 poolSize) external {
        poolSize = uint8(bound(poolSize, 0, 4));
        bytes32[][] memory context =
            uniformGrid(symbol("AAPL"), float(1), symbol("AAPL"), float(150), float(1000), poolSize);
        string memory operand = string.concat("<", uint256(poolSize).toString(), ">()");

        checkWordReverts(string.concat("attestor", operand), context, stdError.indexOOBError);
        checkWordReverts(string.concat("attested-symbol", operand), context, stdError.indexOOBError);
        checkWordReverts(string.concat("attested-price", operand), context, stdError.indexOOBError);
        checkWordReverts(string.concat("attested-time", operand), context, stdError.indexOOBError);
    }

    /// With no attestations at all there is no signers column and no lead
    /// column, so every attestation word reverts, the lead's included.
    function testNoAttestationsReverts() external {
        bytes32[][] memory context = LibSt0xAttestContext.build(symbol("AAPL"), float(1), new SignedContextV1[](0));

        checkWord("mint-symbol()", context, symbol("AAPL"));
        checkWord("mint-amount()", context, float(1));

        checkWordReverts("lead()", context, stdError.indexOOBError);
        checkWordReverts("lead-symbol()", context, stdError.indexOOBError);
        checkWordReverts("lead-price()", context, stdError.indexOOBError);
        checkWordReverts("lead-time()", context, stdError.indexOOBError);
        checkWordReverts("attestor<0>()", context, stdError.indexOOBError);
        checkWordReverts("attested-symbol<0>()", context, stdError.indexOOBError);
        checkWordReverts("attested-price<0>()", context, stdError.indexOOBError);
        checkWordReverts("attested-time<0>()", context, stdError.indexOOBError);
    }

    /// An attestation with fewer than three values is short at the rows the
    /// words read, and reverts there rather than reading a zero.
    function testShortAttestationReverts() external {
        SignedContextV1[] memory attestations = new SignedContextV1[](2);
        bytes32[] memory twoValues = new bytes32[](2);
        twoValues[0] = symbol("AAPL");
        twoValues[1] = float(150);
        attestations[0] = sign(LEAD_KEY, twoValues);
        attestations[1] = sign(OPERATOR_KEY_0, new bytes32[](0));
        bytes32[][] memory context = LibSt0xAttestContext.build(symbol("AAPL"), float(1), attestations);

        checkWord("lead()", context, signer(vm.addr(LEAD_KEY)));
        checkWord("lead-symbol()", context, symbol("AAPL"));
        checkWord("lead-price()", context, float(150));
        checkWordReverts("lead-time()", context, stdError.indexOOBError);

        checkWord("attestor<0>()", context, signer(vm.addr(OPERATOR_KEY_0)));
        checkWordReverts("attested-symbol<0>()", context, stdError.indexOOBError);
        checkWordReverts("attested-price<0>()", context, stdError.indexOOBError);
        checkWordReverts("attested-time<0>()", context, stdError.indexOOBError);
    }
}

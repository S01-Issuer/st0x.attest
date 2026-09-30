// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {LibMeta} from "rain-metadata-0.1.7/src/lib/LibMeta.sol";

import {St0xAttestSubParser} from "src/concrete/St0xAttestSubParser.sol";

contract St0xAttestSubParserDescribedByMetaV1Test is Test {
    /// The hash the contract reports is of the committed meta, which
    /// `script/build-meta.sh` builds from the same authoring meta that the
    /// parse meta is built from.
    function testDescribedByMetaV1() external {
        St0xAttestSubParser subParser = new St0xAttestSubParser();
        bytes memory meta = vm.readFileBinary("meta/St0xAttestSubParser.rain.meta");
        assertTrue(LibMeta.isRainMetaV1(meta));
        assertEq(keccak256(meta), subParser.describedByMetaV1());
    }
}

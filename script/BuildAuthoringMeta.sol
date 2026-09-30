// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.2/src/Script.sol";
import {LibSt0xAttestSubParser} from "../src/lib/LibSt0xAttestSubParser.sol";

/// @title BuildAuthoringMeta
/// @notice Writes the subparser's raw ABI encoded authoring meta to disk.
/// `script/build-meta.sh` wraps it in cbor and deflates it into the meta
/// whose hash the subparser reports from `describedByMetaV1`.
contract BuildAuthoringMeta is Script {
    function run() external {
        vm.writeFileBinary("meta/St0xAttestSubParserAuthoringMeta.rain.meta", LibSt0xAttestSubParser.authoringMetaV2());
    }
}

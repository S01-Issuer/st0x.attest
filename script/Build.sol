// SPDX-License-Identifier: LicenseRef-DCL-1.0
// SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd
pragma solidity =0.8.25;

import {Script} from "forge-std-1.16.2/src/Script.sol";
import {LibCodeGen} from "rain-sol-codegen-0.1.37/src/lib/LibCodeGen.sol";
import {LibFs} from "rain-sol-codegen-0.1.37/src/lib/LibFs.sol";
import {LibGenParseMeta} from "rainlang-interface-0.2.9/src/lib/codegen/LibGenParseMeta.sol";
import {St0xAttestSubParser} from "../src/concrete/St0xAttestSubParser.sol";
import {LibSt0xAttestSubParser, PARSE_META_BUILD_DEPTH} from "../src/lib/LibSt0xAttestSubParser.sol";

/// @title Build
/// @notice Generates `src/generated/St0xAttestSubParserPointers.sol`: the
/// described-by meta hash, the parse meta, and the word parser, operand
/// handler and literal parser pointer tables, read back off a fresh instance.
/// Run `script/build-meta.sh` first so the meta hash is of the current words.
contract Build is Script {
    function run() external {
        St0xAttestSubParser subParser = new St0xAttestSubParser();
        LibFs.buildFileForContract(
            vm,
            address(subParser),
            "St0xAttestSubParserPointers",
            string.concat(
                LibCodeGen.describedByMetaHashConstantString(vm, "St0xAttestSubParser"),
                LibGenParseMeta.parseMetaConstantString(
                    vm, LibSt0xAttestSubParser.authoringMetaV2(), PARSE_META_BUILD_DEPTH
                ),
                LibCodeGen.subParserWordParsersConstantString(vm, subParser),
                LibCodeGen.operandHandlerFunctionPointersConstantString(vm, subParser),
                LibCodeGen.literalParserFunctionPointersConstantString(vm, subParser)
            )
        );
    }
}

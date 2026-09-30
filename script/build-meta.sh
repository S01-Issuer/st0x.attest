#!/bin/bash
# SPDX-License-Identifier: LicenseRef-DCL-1.0
# SPDX-FileCopyrightText: Copyright (c) 2020 Rain Open Source Software Ltd

# Builds `meta/St0xAttestSubParser.rain.meta`, the authoring meta of the
# subparser's words as a deflated cbor document. `script/Build.sol` hashes it
# into the generated pointers file, so run this before that.

set -euxo pipefail

mkdir -p meta
forge script --silent ./script/BuildAuthoringMeta.sol
nix shell .#rain-cli -c rain meta build \
  -i <(cat ./meta/St0xAttestSubParserAuthoringMeta.rain.meta) \
  -m authoring-meta-v2 \
  -t cbor \
  -e deflate \
  -l none \
  -o meta/St0xAttestSubParser.rain.meta

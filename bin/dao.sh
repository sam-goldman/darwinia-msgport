#!/usr/bin/env bash

set -eo pipefail

c3=$PWD/script/input/c3.json

deployer=$(jq -r ".DEPLOYER" $c3)
dao=$(jq -r ".MSGDAO" $c3)
registry=$(jq -r ".LINEREGISTRY_ADDR" $c3)
ormp_line=$(jq -r ".ORMPLINE_ADDR" $c3)

seth send -F $deployer $registry "transferOwnership(address)" $dao --chain darwinia
seth send -F $deployer $registry "transferOwnership(address)" $dao --chain arbitrum

seth send -F $deployer $ormp_line "transferOwnership(address)" $dao --chain darwinia
seth send -F $deployer $ormp_line "transferOwnership(address)" $dao --chain arbitrum

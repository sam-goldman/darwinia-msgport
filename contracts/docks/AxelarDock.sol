// SPDX-License-Identifier: MIT

pragma solidity >=0.8.9;

import "../interfaces/BaseMessageDock.sol";
import {AxelarExecutable} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/executable/AxelarExecutable.sol";
import {IAxelarGateway} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGateway.sol";
import {IAxelarGasService} from "@axelar-network/axelar-gmp-sdk-solidity/contracts/interfaces/IAxelarGasService.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../utils/Utils.sol";

contract AxelarDock is BaseMessageDock, AxelarExecutable, Ownable {
    IAxelarGasService public immutable gasService;

    constructor(
        address _localMsgportAddress,
        address _chainIdConverter,
        address _gateway,
        address _gasReceiver
    )
        BaseMessageDock(_localMsgportAddress, _chainIdConverter)
        AxelarExecutable(_gateway)
    {
        gasService = IAxelarGasService(_gasReceiver);
    }

    function setChainIdConverter(address _chainIdConverter) external onlyOwner {
        setChainIdConverterInternal(_chainIdConverter);
    }

    function newOutboundLane(
        uint64 _toChainId,
        address _toDockAddress
    ) external onlyOwner {
        addOutboundLaneInternal(_toChainId, _toDockAddress);
    }

    function chainIdUp(string memory _chainId) public view returns (uint64) {
        return chainIdMapping.up(bytes(_chainId));
    }

    function chainIdDown(uint64 _chainId) public view returns (string memory) {
        return string(chainIdMapping.down(_chainId));
    }

    function approveToRecv(
        address _fromDappAddress,
        InboundLane memory _inboundLane,
        address _toDappAddress,
        bytes memory _messagePayload
    ) internal override returns (bool) {
        // because dock is called by low-level gateway, we need to check the sender is correct.
        if (msg.sender != address(gateway)) {
            return false;
        } else {
            return true;
        }
    }

    function callRemoteRecv(
        address _fromDappAddress,
        OutboundLane memory _outboundLane,
        address _toDappAddress,
        bytes memory _messagePayload,
        bytes memory _params
    ) internal override {
        bytes memory axelarMessage = abi.encode(
            _fromDappAddress,
            _toDappAddress,
            _messagePayload
        );

        string memory toChainId = chainIdDown(_outboundLane.toChainId);
        string memory toDockAddress = Utils.addressToHexString(
            _outboundLane.toDockAddress
        );

        if (msg.value > 0) {
            gasService.payNativeGasForContractCall{value: msg.value}(
                address(this),
                toChainId,
                toDockAddress,
                axelarMessage,
                msg.sender
            );
        }

        gateway.callContract(toChainId, toDockAddress, axelarMessage);
    }

    function _execute(
        string calldata sourceChain_,
        string calldata sourceAddress_,
        bytes calldata payload_
    ) internal override {
        (
            address fromDappAddress,
            address toDappAddress,
            bytes memory messagePayload
        ) = abi.decode(payload_, (address, address, bytes));

        InboundLane memory inboundLane = inboundLanes[chainIdUp(sourceChain_)];
        require(
            inboundLane.fromDockAddress ==
                Utils.hexStringToAddress(sourceAddress_),
            "invalid source dock address"
        );

        recv(fromDappAddress, inboundLane, toDappAddress, messagePayload);
    }
}

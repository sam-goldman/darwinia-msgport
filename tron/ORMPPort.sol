// This file is part of Darwinia.
// Copyright (C) 2018-2023 Darwinia Network
// SPDX-License-Identifier: GPL-3.0
//
// Darwinia is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Darwinia is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Darwinia. If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.17;


interface IMessagePort {
    error MessageFailure(bytes errorData);

    /// @dev Send a cross-chain message over the MessagePort.
    /// @notice Send a cross-chain message over the MessagePort.
    /// @param toChainId The message destination chain id. <https://eips.ethereum.org/EIPS/eip-155>
    /// @param toDapp The user application contract address which receive the message.
    /// @param message The calldata which encoded by ABI Encoding.
    /// @param params Extend parameters to adapt to different message protocols.
    function send(uint256 toChainId, address toDapp, bytes calldata message, bytes calldata params) external payable;

    /// @notice Get a quote in source native gas, for the amount that send() requires to pay for message delivery.
    ///         It should be noted that not all ports will implement this interface.
    /// @dev If the messaging protocol does not support on-chain fetch fee, then revert with "Unimplemented!".
    /// @param toChainId The message destination chain id. <https://eips.ethereum.org/EIPS/eip-155>
    /// @param toDapp The user application contract address which receive the message.
    /// @param message The calldata which encoded by ABI Encoding.
    /// @param params Extend parameters to adapt to different message protocols.
    function fee(uint256 toChainId, address toDapp, bytes calldata message, bytes calldata params)
        external
        view
        returns (uint256);
}


interface IPortMetadata {
    event URI(string uri);

    /// @notice Get the port name, it's globally unique and immutable.
    /// @return The MessagePort name.
    function name() external view returns (string memory);

    /// @return The port metadata uri.
    function uri() external view returns (string memory);
}

contract PortMetadata is IPortMetadata {
    string internal _name;
    string internal _uri;

    constructor(string memory name_) {
        _name = name_;
    }

    function _setURI(string memory uri_) internal virtual {
        _uri = uri_;
        emit URI(uri_);
    }

    function name() public view virtual returns (string memory) {
        return _name;
    }

    function uri() public view virtual returns (string memory) {
        return _uri;
    }
}

abstract contract BaseMessagePort is IMessagePort, PortMetadata {
    constructor(string memory name) PortMetadata(name) {}

    function LOCAL_CHAINID() public view returns (uint256) {
        return block.chainid;
    }

    /// @dev Send a cross-chain message over the MessagePort.
    ///      Port developer should implement this, then it will be called by `send`.
    /// @param fromDapp The real sender account who send the message.
    /// @param toChainId The message destination chain id. <https://eips.ethereum.org/EIPS/eip-155>
    /// @param toDapp The user application contract address which receive the message.
    /// @param message The calldata which encoded by ABI Encoding.
    /// @param params Extend parameters to adapt to different message protocols.
    function _send(address fromDapp, uint256 toChainId, address toDapp, bytes calldata message, bytes calldata params)
        internal
        virtual;

    function send(uint256 toChainId, address toDapp, bytes calldata message, bytes calldata params) public payable {
        _send(msg.sender, toChainId, toDapp, message, params);
    }

    /// @dev Make toDapp accept messages.
    ///      This should be called by message port when a message is received.
    /// @param fromChainId The source chainId, standard evm chainId.
    /// @param fromDapp The message sender in source chain.
    /// @param toDapp The message receiver in dest chain.
    /// @param message The message body.
    function _recv(uint256 fromChainId, address fromDapp, address toDapp, bytes memory message)
        internal
        returns (bytes memory)
    {
        (bool success, bytes memory returndata) =
            toDapp.call{value: msg.value}(abi.encodePacked(message, fromChainId, fromDapp));
        if (success) {
            return returndata;
        } else {
            revert MessageFailure(returndata);
        }
    }

    function fee(uint256, address, bytes calldata, bytes calldata) external view virtual returns (uint256) {
        revert("Unimplemented!");
    }
}


abstract contract FromPortLookup {
    event SetFromPort(uint256 fromChainId, address fromPort);

    // fromChainId => fromPortAddress
    mapping(uint256 => address) public fromPortLookup;

    function _setFromPort(uint256 fromChainId, address fromPort) internal virtual {
        fromPortLookup[fromChainId] = fromPort;
        emit SetFromPort(fromChainId, fromPort);
    }

    function _fromPort(uint256 fromChainId) internal view returns (address) {
        return fromPortLookup[fromChainId];
    }

    function _checkedFromPort(uint256 fromChainId) internal view returns (address l) {
        l = fromPortLookup[fromChainId];
        require(l != address(0), "!fromPort");
    }
}


abstract contract ToPortLookup {
    event SetToPort(uint256 toChainId, address toPort);

    // toChainId => toPortAddress
    mapping(uint256 => address) public toPortLookup;

    function _setToPort(uint256 toChainId, address toPort) internal virtual {
        toPortLookup[toChainId] = toPort;
        emit SetToPort(toChainId, toPort);
    }

    function _toPort(uint256 toChainId) internal view returns (address) {
        return toPortLookup[toChainId];
    }

    function _checkedToPort(uint256 toChainId) internal view returns (address l) {
        l = toPortLookup[toChainId];
        require(l != address(0), "!toPort");
    }
}

abstract contract PortLookup is FromPortLookup, ToPortLookup {}


/// @dev The block of control information and data for comminicate
/// between user applications. Messages are the exchange medium
/// used by channels to send and receive data through cross-chain networks.
/// A message is sent from a source chain to a destination chain.
/// @param index The leaf index lives in channel's incremental mekle tree.
/// @param fromChainId The message source chain id.
/// @param from User application contract address which send the message.
/// @param toChainId The message destination chain id.
/// @param to User application contract address which receive the message.
/// @param gasLimit Gas limit for destination UA used.
/// @param encoded The calldata which encoded by ABI Encoding.
struct Message {
    address channel;
    uint256 index;
    uint256 fromChainId;
    address from;
    uint256 toChainId;
    address to;
    uint256 gasLimit;
    bytes encoded; /*(abi.encodePacked(SELECTOR, PARAMS))*/
}

/// @dev User application custom configuration.
/// @param oracle Oracle contract address.
/// @param relayer Relayer contract address.
struct UC {
    address oracle;
    address relayer;
}

/// @dev Hash of the message.
function hash(Message memory message) pure returns (bytes32) {
    return keccak256(abi.encode(message));
}

interface IORMP {
    /// @dev Send a cross-chain message over the endpoint.
    /// @notice follow https://eips.ethereum.org/EIPS/eip-5750
    /// @param toChainId The Message destination chain id.
    /// @param to User application contract address which receive the message.
    /// @param gasLimit Gas limit for destination user application used.
    /// @param encoded The calldata which encoded by ABI Encoding.
    /// @param refund Return extra fee to refund address.
    /// @param params General extensibility for relayer to custom functionality.
    /// @return Return the hash of the message as message id.
    function send(
        uint256 toChainId,
        address to,
        uint256 gasLimit,
        bytes calldata encoded,
        address refund,
        bytes calldata params
    ) external payable returns (bytes32);

    /// @notice Get a quote in source native gas, for the amount that send() requires to pay for message delivery.
    /// @param toChainId The Message destination chain id.
    //  @param ua User application contract address which send the message.
    /// @param gasLimit Gas limit for destination user application used.
    /// @param encoded The calldata which encoded by ABI Encoding.
    /// @param params General extensibility for relayer to custom functionality.
    function fee(uint256 toChainId, address ua, uint256 gasLimit, bytes calldata encoded, bytes calldata params)
        external
        view
        returns (uint256);

    /// @dev Recv verified message and dispatch to destination user application address.
    /// @param message Verified receive message info.
    /// @param proof Message proof of this message.
    /// @return dispatchResult Result of the message dispatch.
    function recv(Message calldata message, bytes calldata proof) external returns (bool dispatchResult);

    function prove() external view returns (bytes32[32] memory);

    /// @dev Fetch user application config.
    /// @notice If user application has not configured, then the default config is used.
    /// @param ua User application contract address.
    /// @return user application config.
    function getAppConfig(address ua) external view returns (UC memory);

    /// @notice Set user application config.
    /// @param oracle Oracle which user application choose.
    /// @param relayer Relayer which user application choose.
    function setAppConfig(address oracle, address relayer) external;

    function defaultUC() external view returns (UC memory);

    /// @dev Check the msg if it is dispatched.
    /// @param msgHash Hash of the checked message.
    /// @return Return the dispatched result of the checked message.
    function dones(bytes32 msgHash) external view returns (bool);
}


// https://eips.ethereum.org/EIPS/eip-5164
abstract contract AppBase {
    function protocol() public view virtual returns (address);

    function _setAppConfig(address oracle, address relayer) internal virtual {
        IORMP(protocol()).setAppConfig(oracle, relayer);
    }

    modifier onlyORMP() {
        require(protocol() == msg.sender, "!ormp-recver");
        _;
    }

    function _messageId() internal pure returns (bytes32 _msgDataMessageId) {
        require(msg.data.length >= 84, "!messageId");
        assembly {
            _msgDataMessageId := calldataload(sub(calldatasize(), 84))
        }
    }

    function _fromChainId() internal pure returns (uint256 _msgDataFromChainId) {
        require(msg.data.length >= 52, "!fromChainId");
        assembly {
            _msgDataFromChainId := calldataload(sub(calldatasize(), 52))
        }
    }

    function _xmsgSender() internal pure returns (address payable _from) {
        require(msg.data.length >= 20, "!xmsgSender");
        assembly {
            _from := shr(96, calldataload(sub(calldatasize(), 20)))
        }
    }
}

abstract contract Application is AppBase {
    address private immutable _ORMP;

    constructor(address ormp) {
        _ORMP = ormp;
    }

    function protocol() public view virtual override returns (address) {
        return _ORMP;
    }
}

// OpenZeppelin Contracts (last updated v4.9.0) (access/Ownable2Step.sol)

// OpenZeppelin Contracts (last updated v4.9.0) (access/Ownable.sol)

// OpenZeppelin Contracts v4.4.1 (utils/Context.sol)

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _transferOwnership(_msgSender());
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby disabling any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

/**
 * @dev Contract module which provides access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership} and {acceptOwnership}.
 *
 * This module is used through inheritance. It will make available all functions
 * from parent (Ownable).
 */
abstract contract Ownable2Step is Ownable {
    address private _pendingOwner;

    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Returns the address of the pending owner.
     */
    function pendingOwner() public view virtual returns (address) {
        return _pendingOwner;
    }

    /**
     * @dev Starts the ownership transfer of the contract to a new account. Replaces the pending transfer if there is one.
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual override onlyOwner {
        _pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner(), newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`) and deletes any pending owner.
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual override {
        delete _pendingOwner;
        super._transferOwnership(newOwner);
    }

    /**
     * @dev The new owner accepts the ownership transfer.
     */
    function acceptOwnership() public virtual {
        address sender = _msgSender();
        require(pendingOwner() == sender, "Ownable2Step: caller is not the new owner");
        _transferOwnership(sender);
    }
}

contract ORMPPort is Ownable2Step, Application, BaseMessagePort, PortLookup {
    constructor(address dao, address ormp, string memory name) Application(ormp) BaseMessagePort(name) {
        _transferOwnership(dao);
    }

    function setURI(string calldata uri) external onlyOwner {
        _setURI(uri);
    }

    function setAppConfig(address oracle, address relayer) external onlyOwner {
        _setAppConfig(oracle, relayer);
    }

    function setToPort(uint256 _toChainId, address _toPortAddress) external onlyOwner {
        _setToPort(_toChainId, _toPortAddress);
    }

    function setFromPort(uint256 _fromChainId, address _fromPortAddress) external onlyOwner {
        _setFromPort(_fromChainId, _fromPortAddress);
    }

    function _send(address fromDapp, uint256 toChainId, address toDapp, bytes calldata message, bytes calldata params)
        internal
        override
    {
        (uint256 gasLimit, address refund, bytes memory ormpParams) = abi.decode(params, (uint256, address, bytes));
        bytes memory encoded = abi.encodeWithSelector(this.recv.selector, fromDapp, toDapp, message);
        IORMP(protocol()).send{value: msg.value}(
            toChainId, _checkedToPort(toChainId), gasLimit, encoded, refund, ormpParams
        );
    }

    function recv(address fromDapp, address toDapp, bytes calldata message) public payable virtual onlyORMP {
        uint256 fromChainId = _fromChainId();
        require(_xmsgSender() == _checkedFromPort(fromChainId), "!auth");
        _recv(fromChainId, fromDapp, toDapp, message);
    }

    function fee(uint256 toChainId, address toDapp, bytes calldata message, bytes calldata params)
        external
        view
        override
        returns (uint256)
    {
        (uint256 gasLimit,, bytes memory ormpParams) = abi.decode(params, (uint256, address, bytes));
        bytes memory encoded = abi.encodeWithSelector(this.recv.selector, msg.sender, toDapp, message);
        return IORMP(protocol()).fee(toChainId, address(this), gasLimit, encoded, ormpParams);
    }
}


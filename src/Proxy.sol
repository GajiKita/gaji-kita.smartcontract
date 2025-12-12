// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Proxy
 * @dev A simple proxy contract that delegates all calls to an implementation contract
 */
contract Proxy {
    // Storage slot for the implementation contract address
    bytes32 private constant IMPLEMENTATION_SLOT = 
        keccak256("org.gaji-kita.gaji-kita.smartcontract.proxy.implementation");

    // Storage slot for the admin address
    bytes32 private constant ADMIN_SLOT = 
        keccak256("org.gaji-kita.gaji-kita.smartcontract.proxy.admin");

    /**
     * @dev Constructor sets the initial implementation and admin addresses
     */
    constructor(address _implementation, address _admin) {
        assert(IMPLEMENTATION_SLOT == keccak256("org.gaji-kita.gaji-kita.smartcontract.proxy.implementation"));
        assert(ADMIN_SLOT == keccak256("org.gaji-kita.gaji-kita.smartcontract.proxy.admin"));

        _setImplementation(_implementation);
        _setAdmin(_admin);
    }

    /**
     * @dev Fallback function that delegates all calls to the implementation contract
     */
    fallback() external payable {
        _delegate(loadImplementation());
    }

    /**
     * @dev Receive function to accept ETH
     */
    receive() external payable {
        _delegate(loadImplementation());
    }

    /**
     * @dev Delegates the current call to the given implementation address
     */
    function _delegate(address implementation) internal virtual {
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    /**
     * @dev Loads the implementation address from storage
     */
    function loadImplementation() public view returns (address) {
        return _loadAddress(IMPLEMENTATION_SLOT);
    }

    /**
     * @dev Loads the admin address from storage
     */
    function loadAdmin() public view returns (address) {
        return _loadAddress(ADMIN_SLOT);
    }

    /**
     * @dev Stores the implementation address
     */
    function _setImplementation(address _newImpl) private {
        _storeAddress(IMPLEMENTATION_SLOT, _newImpl);
    }

    /**
     * @dev Stores the admin address
     */
    function _setAdmin(address _newAdmin) private {
        _storeAddress(ADMIN_SLOT, _newAdmin);
    }

    /**
     * @dev Helper function to load an address from a storage slot
     */
    function _loadAddress(bytes32 slot) private view returns (address addr) {
        assembly { addr := sload(slot) }
    }

    /**
     * @dev Helper function to store an address in a storage slot
     */
    function _storeAddress(bytes32 slot, address addr) private {
        assembly { sstore(slot, addr) }
    }
}
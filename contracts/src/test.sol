// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {UserOperation} from "@4337/contracts/interfaces/UserOperation.sol";
import {IERC165} from "@openzeppelin/utils/introspection/IERC165.sol";
import {ERC165} from "@openzeppelin/utils/introspection/ERC165.sol";

/**
X? USDC for Y? WETH, iff the gas fee is < G
Invariant: X USDC for Y ETH
Condition: gas fee < G
Condition2: I want to pay gas fee in USDC

As a user I have lot's of USDC.
I want to buy 10 ETH at market price, if gas fees are less than 50000 gas.

Calculation returns market rate data.

Generates:
xMinIn:  0
xMaxOut: 20000
yMinIn:  0
yMaxOut: 10
conditional contract: returns true or false


 */

interface GasIntent {
    // gas condition
    // gas in some token
    getGasPrice() external returns(uint256);
}

interface SwapTrasaction {}

interface UserBid {
    // 
}

// we cannot manage intents that can be used unless custodial
interface IIntent {
    handleIntent(address to, bytes data) external payable returns(bool);
}


contract intent_management {
    // we need to accept intents
    // one intent type per contract
    // intents cannot be duplicated per tx
    // txs need to be bundles of user operations only
    // user needs to pay bid in some asset


    // one mode: very inspecific data that the solver finds the solution to get the result
    // two mode: very specific data that has a condition that may be true at a future time

    enum solver_mode {
        SPECIFIC,
        INSPECIFIC
    }

    struct payment {
        address user;
        address asset;
        uint256 amount;
    }

    struct Hook {
        uint256 gasLimit;
        uint256 amount;
        address target;
        bytes data;
    }

    // need to create an intent
    // intent design:
    // user called intent_management contract > call intents and execution call on wallet

    function call_intent()
    // if the intent is call inside of callData then all the solver can do is decide when to call it

    function _executeHook(Hook[] calldata hook) internal {
        uint256 size = hook.length;
        bool success;
        bytes memory receipt;
        for(uint256 i; i<size; i++) {
            (success, receipt) = payable(hook[i].target).call{
                gas: hook[i].gasLimit,
                value: hook[i].amount
                }(hook[i].data);
        }
    }

    function executeWithHook(
        uint256 gasLimit,
        uint256 amount,
        address target,
        bytes calldata data, // 
        Hook[] calldata beforeExecute,
        Hook[] calldata afterExecute
        ) external payable returns(bool) {
            if(beforeExecute.length != 0) {
                _executeHook(beforeExecute);
            }
            (bool success,) = payable(target).call{
                gas: gasLimit,
                value: amount
                }(data);
            if(afterExecute.length != 0) {
                _executeHook(afterExecute);
            }
            return success;
    }

    function safeExecuteWithHook(
        uint256 gasLimit,
        uint256 amount,
        address target, 
        bytes calldata data, 
        Hook[] calldata beforeExecute,
        Hook[] calldata afterExecute
    ) external payable {
        if(beforeExecute.length != 0) {
                _executeHook(beforeExecute);
        }
        (bool success, bytes memory receipt) = payable(target).call{
            gas: gasLimit,
            value: amount
            }(data);
        if(afterExecute.length != 0) {
            _executeHook(afterExecute);
        }
        if(!success) {
            revert ExecuteFailed(target, receipt);
        }
    }

    error ExecuteFailed(address target, bytes data);
    error GasError(uint256 index);
    error HookReverted(uint256 index, bytes data);  
}

interface intent_hook {
    handleHook(bytes data) external payable returns(bool);
}

contract example_hook is intent_hook, EIP165 {
    handleHook(bytes data) external override virtual returns(bool) {
        // do stuff for intent
        returns true;
    }
}


// this proof shows how "extra" bytes outside the input data can be used for execution
contract extra_bytes_caller {
    function callData(address a) public {
        bytes memory payload_ = abi.encodePacked(
            abi.encodeWithSignature("called()"), 
            bytes32(uint256(5678))
            );
        assembly {
            pop(call(gas(), a, 0, add(payload_, 0x20), mload(payload_), 0,0))
        }
    }
}

contract extra_bytes_receiver {
    uint256 public time;

    function called() public {
        assembly {
            let mem := mload(0x40)
            let len := calldatasize()
            calldatacopy(mem, 0x4, sub(len, 0x4))
            sstore(time.slot, mload(mem))
        }
    }
}

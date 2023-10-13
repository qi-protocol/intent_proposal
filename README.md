---
eip: N/A
title: General Intents using exisitng AA infrastructure
description: A generalized intent specification for smart contract wallets, without modifiying existing entry point.
author: Charles Taylor (@FudgyDRS)
discussions-to: -
status: Draft
type: -
category: -
created: 2023-10-01
---

## Abstract

Generalized intent specificaion can be exectuted by current entry point paradigm as described in ERC4337. This is counter to emerging designed whereby executed intents are pre and post operation calls with a modified entry point (or account abstraction wallet hooks). Hooks as it may seem can be executed directly via 'extra' bytes or more canonically be implmented as an abstraction to the call data on the account abstraction wallet. Within our paradigm execution may occur within the parameters of `executeWithHooks` and `safeExecuteWithHook`. The only difference being that the former does not revert in the event the execution fails, in otherwords does not need the intents to be successful. Intents must inherit the `intent_hook` interface.

## Motivation

See also ["ERC-4337: Account Abstraction via Entry Point Contract specification"](./eip-4337.md) and the links therein for historical work and motivation.

This is not a proposal for a new standard rather a technical design approach for intent fulfillment without changes to exisitng infrastructure. As such it seeks to achieve the following goals:

- **Enabling intents for users**: allow users to use smart contract wallets containing arbitrary verification logic to specify intents as described and handled by various other intent standard contracts.
- **Scale exisitng infrastructure**: allow the current infrastructure of bundlers, entry point, and smart contract wallets to exist unimpeded
- **Decentralization**
  - Allow any MEV searcher to participate in the process of signing intents
  - Allow any developer to add their own intent stardard
- **Gas efficency**: gas usage for scaling must be considered as a key definition of efficency, as such the user can skip certain confirmations
- **Payment security**: solvers mining the intents must be paid if due, as such the payment must be deterministic

## More Details

An intent is solved by appending combining various hooks. 

Hooks are smart contracts that have contain the function `handleHook(bytes calldata data)` that only return a boolean for hook success, and a error string if the hook fails.

Rather than the smart wallet calling the swap with the router directly it calls `safeExecuteWithHooks` on our protocol. This enables the user to specify what hooks they want and in what order while being invarient to the actual transaction. Additionally, since this transaction is called from the smart wallets execution function, the user can still use any paymaster.

## Specification

Users package intents for their specific transaction by wrapping their core transaction callData, the ABI-encoded example is below for `executeWithHooks` and `safeExecuteWithHooks`:

| Field           | Type      | Description                                                                          |
| --------------- | --------- | ------------------------------------------------------------------------------------ |
| `gasLimit`      | `uint256` | Gas limiter to the execution of all intents                                          |
| `amount`        | `uint256` | The callData's amount sent                                                           |
| `dealine`       | `uint256` | Expiry time for the execution of the userop                                          |
| `target`        | `address` | The smart wallet's target for callData                                               |
| `data`          | `bytes`   | Raw callData to call the smart wallet                                                |
| `beforeExecute` | `Hook[]`  | Intents to be executed before the callData execution                                 |
| `afterExecute`  | `Hook[]`  | Intents to be executed after the callData execution                                  |



Users intent data for each hook is defined below for the `Hook`:

| Field           | Type      | Description                                                                          |
| --------------- | --------- | ------------------------------------------------------------------------------------ |
| `gasLimit`      | `uint256` | Gas limiter to the execution of the intents                                          |
| `amount`        | `uint256` | The amount sent to a specific intent                                                 |
| `target`        | `address` | The intent contract                                                                  |
| `data`          | `bytes`   | Any data desired to be sent to the intent contrcat                                   |

Users can use open data slot for hooks in place of normal intents by calling 
upgradeable contracts that can be upgraded by the solver. These intents use the same interface as above but additionally must implement our protocols `Iintent_hook` interface and add it to their `EIP165` `SupportsInterface` function.

    interface intent_hook {
        handleHook(bytes data) external payable returns(bool success, string error, bytes context);
    }

The above hook will enable the solver AND user the ability to have hooks into mingle for a more robust user experience.

The above 


## Let's take a look at a simple example

Goal: User wants to send USDC for a market value of WETH, if the gas price is less than 100k gwei for the entire transaction.

First step (the setup):
The call to the smart contracts execution function `IAccount(sender).execute(to, from, amount)` will call our protocol's function `IIntent_management(protocol).safeExecuteWithHooks()` loaded with bytecode for the correct hooks the user wants.

To make the intent simple the calldata will be `0x` and the hooks will use an upgradable swap hook, payment hook, swap invarient hook, and gas condition hook.

    // example intent for checking resulting asset value
    handleHook(bytes calldata data) public payable returns(bool, string memory) {
        address sender;
        address assetInputAddress;
        address assetOutputAddress;
        uint256 assetInputBalance;
        uint256 assetOutputBalance;

        if(msg.data.length >= (4+5*32)) {
            return(false, "data not filled");
        }
        
        (
            sender,
            assetInputAddress, 
            assetInputBalance,
            assetOutputAddress, 
            assetOutputBalance
        ) = abi.decode(data, (address, address, uint256, address, uint256));
        
        uint256 balance0 = IERC20(assetInputAddress).balanceOf(sender);
        uint256 balance1 = IERC20(assetOutputAddress).balanceOf(sender);

        if(balance0 <= assetInputBalanceAfter) {
            return(false, "insufficent min balance0");
        }
        if(balance1 <= assetOutBalanceAfter) {
            return(false, "insufficent min balance1");
        }

        return(true, '');
    }


    // example intent for payment
    handleHook(bytes calldata data) 
    public 
    payable 
    return(bool, string memory) {
        address sender;
        address to;
        address asset;
        uint256 amount;

        if(msg.data.length >= (4+3*32)) {
            return(false, "data not filled");
        }

        (sender, asset, amount) = abi.decode(data, (address, address, uint256))

        bool success;
        if(asset == address(0)) {
            (success,) = payable(to).call{value: msg.value}("");
        } else {
            (success,) = IERC20(asset).transferFrom(sender, to, amount);
        }

        if(!success) { return (false, "transfer failed"); }
        return (true, '');
    }


    // example intent for gas condition
    handleHook(bytes calldata data) 
    public 
    payable 
    return(bool, string memory, bytes memory) {
        uint256 gasUsed;
        uint256 maxGasUsed;

        if(msg.data.length >= (4+2*32)) {
            return(false, "data not filled",);
        }

        (
            gasUsed,
            maxGasUsed
        ) = abi.decode(data, (uint256, uint256));

        if(gasUsed >= gasUsed) {
            return (false, "gas condition failed",);
        }

        return (true, '',);
    }


    // example intent for make the swap from asset A to asset B 
    // this contract is likely a proxy that can be updated to add a new tx path for opitimal MEV
    // by the solver
    handleHook(bytes calldata data) public payable return(bool, string memory, bytes memory) {
        uint256 gas = gasleft();
        address to;
        address paymentAsset;
        address asset0;
        address asset1;
        uint256 paymentAmount; // cost of tx + gas
        uint256 amount0;
        uint256 amount1;

        if(msg.data.length >= (4+7*32)) {
            return(false, "data not filled");
        }

        (
            sender,
            paymentAsset,
            paymentAmount,
            asset0,
            amount0,
            asset1,
            amount1
        ) = abi.decode(data, (address,address,uint256,address,uint256,address,uint256));

        require(IERC20(payment.asset).balanceOf(address.this) >= paymentAmount, "insufficent assets");

        (success,) = IERC20(asset0).transferFrom(sender, address.this, asset0);
        require(success, "transfer failed");

        
        // although swaps are used to achieve the desired effect, the following tx can be anything 
        // just so long as the result condition is satisfied
        IUniswapRouterV3(routerUniswap).swap(
            asset0, 
            amount0, 
            trade10_asset1, 
            trade0_ammount1, 
            address.this);
        ISushiSwap(routerSushi).swap(
            asset0, 
            amount0, 
            trade1_asset1, 
            trade1_ammount1, 
            address.this);
        I1Inch(router1Inch).swap(
            asset0, 
            amount0, 
            trade2_asset1, 
            trade2_ammount1, 
            address.this);

        uint256 remainderAsset0 = IERC20(asset0).balanceOf(address.this);
        IERC20(asset0).transferFrom(address.this, sender, remainderAsset0);
        IERC20(asset1).transferFrom(address.this, sender, amount1);

        gas = gas - gasleft();
        IUniswapRouterV3(routerUniswap).swap(
            paymentAsset, 
            paymentAmount, 
            ETH, 
            0, // min
            address.this);

        (address.this).balance 

        bool success;
        (success,) = payable(owner).call{value: msg.value}("");
    }



buying NFT, that only accepts eth, with usdt

send funds to solver for purchase
send tip funds to sove to pickup tx
send request hook to get NFT

user needs to provide their address
user provides tip (includes purchase price of NFT + tip for solver)

solver can buy
solver can't buy

i want ot buy nft with condition
I don't want to buy if gas over X amount

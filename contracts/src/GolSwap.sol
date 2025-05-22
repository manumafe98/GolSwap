// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Gol} from "./Gol.sol";

contract GolSwap {
    error GolSwap__PoolAlreadyInitialized();
    error GolSwap__TransferFailed();
    error GolSwap__InvalidRatio();
    error GolSwap__InvalidLiquidityAmount();
    error GolSwap__UnsupportedTokenType();
    error GolSwap__InsufficientEthProvided();
    error GolSwap__InsufficientGolProvided();
    error GolSwap__LiquidityPoolNotInitialized();
    error GolSwap__NotEnoughLiquidity();
    error GolSwap__InvalidSwapValue();

    enum TokenType {
        GOL,
        ETH
    }

    Gol private immutable i_gol;
    address private immutable i_owner;
    uint256 private s_totalLiquidity;

    mapping(address => uint256) private liquidity;

    event Swap(address indexed user, uint256 inputAmount, uint256 outputAmount, bool ethToGol);
    event LiquidityAdded(address indexed provider, uint256 ethAmount, uint256 golAmount);
    event LiquidityRemoved(address indexed provider, uint256 amount);

    modifier liquidityPoolNotInitialized() {
        if (s_totalLiquidity == 0) {
            revert GolSwap__LiquidityPoolNotInitialized();
        }
        _;
    }

    modifier invalidSwapValue(uint256 _amount) {
        if (_amount == 0) {
            revert GolSwap__InvalidSwapValue();
        }
        _;
    }

    constructor(address _golAddress) {
        i_gol = Gol(_golAddress);
        i_owner = msg.sender;
    }

    function init(uint256 _golAmount) external payable {
        if (s_totalLiquidity > 0) {
            revert GolSwap__PoolAlreadyInitialized();
        }

        if (msg.value < 0.01 ether || _golAmount < 10e18) {
            revert GolSwap__InvalidRatio();
        }

        s_totalLiquidity = address(this).balance;
        liquidity[msg.sender] = s_totalLiquidity;

        bool success = i_gol.transferFrom(msg.sender, address(this), _golAmount);

        if (!success) {
            revert GolSwap__TransferFailed();
        }
    }

    function ethToGol() external payable invalidSwapValue(msg.value) {
        (uint256 ethReserve, uint256 golReserve) = getReserves();
        uint256 golToSend = calculatePrice(msg.value, ethReserve - msg.value, golReserve);

        bool success = i_gol.transfer(msg.sender, golToSend);
        if (!success) {
            revert GolSwap__TransferFailed();
        }

        emit Swap(msg.sender, msg.value, golToSend, true);
    }

    function golToEth(uint256 _golAmount) external invalidSwapValue(_golAmount) {
        (uint256 ethReserve, uint256 golReserve) = getReserves();
        uint256 ethToSend = calculatePrice(_golAmount, golReserve - _golAmount, ethReserve);

        bool golSent = i_gol.transferFrom(msg.sender, address(this), _golAmount);
        if (!golSent) {
            revert GolSwap__TransferFailed();
        }

        (bool ethSent,) = payable(msg.sender).call{value: ethToSend}("");
        if (!ethSent) {
            revert GolSwap__TransferFailed();
        }

        emit Swap(msg.sender, _golAmount, ethToSend, false);
    }

    function getOwner() external view returns (address) {
        return i_owner;
    }

    function getTotalLiquidity() external view returns (uint256) {
        return s_totalLiquidity;
    }

    function getProvidedLiquidityByUser(address _address) external view returns (uint256) {
        return liquidity[_address];
    }

    function addLiquidity(uint256 _golAmount) external payable liquidityPoolNotInitialized {
        (uint256 ethReserve, uint256 golReserve) = getReserves();
        ethReserve -= msg.value;

        uint256 minimumEthAccepted = quoteLiquidity(_golAmount, TokenType.GOL, ethReserve, golReserve);
        if (minimumEthAccepted > msg.value) {
            revert GolSwap__InsufficientEthProvided();
        }

        uint256 minimumGolAccepted = quoteLiquidity(msg.value, TokenType.ETH, ethReserve, golReserve);
        if (minimumGolAccepted > _golAmount) {
            revert GolSwap__InsufficientGolProvided();
        }

        bool success = i_gol.transferFrom(msg.sender, address(this), _golAmount);
        if (!success) {
            revert GolSwap__TransferFailed();
        }

        uint256 liquidityMinted = (msg.value * s_totalLiquidity) / ethReserve;
        liquidity[msg.sender] += liquidityMinted;
        s_totalLiquidity += liquidityMinted;

        emit LiquidityAdded(msg.sender, msg.value, _golAmount);
    }

    function removeLiquidity(uint256 _amount) external liquidityPoolNotInitialized {
        (uint256 ethReserve, uint256 golReserve) = getReserves();
        uint256 ethProvided = quoteLiquidity(_amount, TokenType.GOL, ethReserve, golReserve);

        if (liquidity[msg.sender] < ethProvided) {
            revert GolSwap__NotEnoughLiquidity();
        }

        liquidity[msg.sender] -= ethProvided;
        s_totalLiquidity -= ethProvided;

        bool golSent = i_gol.transfer(msg.sender, _amount);
        if (!golSent) {
            revert GolSwap__TransferFailed();
        }

        (bool ethSent,) = payable(msg.sender).call{value: ethProvided}("");
        if (!ethSent) {
            revert GolSwap__TransferFailed();
        }

        emit LiquidityRemoved(msg.sender, _amount);
    }

    function quoteLiquidity(uint256 _tokenAmount, TokenType _tokenType, uint256 ethReserve, uint256 golReserve)
        public
        pure
        returns (uint256)
    {
        if (_tokenAmount == 0) {
            revert GolSwap__InvalidLiquidityAmount();
        }

        if (_tokenType == TokenType.ETH) {
            return (_tokenAmount * golReserve) / ethReserve;
        } else if (_tokenType == TokenType.GOL) {
            return (_tokenAmount * ethReserve) / golReserve;
        } else {
            revert GolSwap__UnsupportedTokenType();
        }
    }

    function getReserves() public view returns (uint256, uint256) {
        uint256 ethReserve = address(this).balance;
        uint256 golReserve = i_gol.balanceOf(address(this));

        return (ethReserve, golReserve);
    }

    /**
     * @notice Calculates the amount of output tokens for a given input amount based on reserves.
     * @dev Implements the constant product formula (x * y = k) with a 0.3% swap fee.
     *
     * Constant product automated market maker:
     * Let x = inputReserve, y = outputReserve, a = inputAmount.
     * The invariant is: (x + a) * (y - Δy) = x * y
     * We solve for Δy (outputAmount):
     *
     * Step-by-step derivation:
     *   (x + a) * (y - outputAmount) = x * y
     *   => y - outputAmount = (x * y) / (x + a)
     *   => outputAmount = y - (x * y) / (x + a) -> passing y resting and then multiplying -1 in both sides
     *   => outputAmount = y * (1 - x / (x + a)) -> factor y
     *   => outputAmount = y * ((x + a - x) / (x + a)) -> 1 = (x + a) / (x + a) using (x + a) as base
     *   => outputAmount = y * (a / (x + a))
     *   => outputAmount = (a * y) / (x + a)
     *
     * Now apply a 0.3% fee (Uniswap-style fee mechanism):
     *   Instead of using `a`, we use `a * 997 / 1000` as the effective input amount.
     *   Final formula:
     *   outputAmount = (a * 997 * y) / (1000 * x + a * 997)
     *
     * @param _inputAmount The amount of input tokens sent to the pool (e.g., ETH or ERC20).
     * @param _inputReserve The current reserve of the input token in the pool.
     * @param _outputReserve The current reserve of the output token in the pool.
     * @return The amount of output tokens the user will receive after applying the swap fee.
     */
    function calculatePrice(uint256 _inputAmount, uint256 _inputReserve, uint256 _outputReserve)
        private
        pure
        returns (uint256)
    {
        uint256 inputAmountWithFee = _inputAmount * 997;
        uint256 numerator = inputAmountWithFee * _outputReserve;
        uint256 denominator = (_inputReserve * 1000) + inputAmountWithFee;
        return numerator / denominator;
    }
}

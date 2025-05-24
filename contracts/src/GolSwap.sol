// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Gol} from "./Gol.sol";

/**
 * @title Gol Swap DEX
 * @author Manuel Maxera
 * @notice It's a minimalistic DEX to swap GOL for ETH and provide liquidity GOL-ETH
 */
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

    uint256 private constant MINIMUM_ETHER = 0.01 ether;
    uint256 private constant MINIMUM_GOL = 10 ether;
    uint256 private constant PERCENTAGE_WITH_FEE = 997;
    uint256 private constant PERCENTAGE_WITHOUT_FEE = 1000;

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

    /**
     * @notice Initializes the GOL-ETH liquidity pool.
     * @dev Can only be called once; sets initial liquidity based on ETH and GOL amounts provided.
     * @param _golAmount The amount of GOL tokens to add to the pool.
     */
    function init(uint256 _golAmount) external payable {
        if (s_totalLiquidity > 0) {
            revert GolSwap__PoolAlreadyInitialized();
        }

        if (msg.value < MINIMUM_ETHER || _golAmount < MINIMUM_GOL) {
            revert GolSwap__InvalidRatio();
        }

        s_totalLiquidity = address(this).balance;
        liquidity[msg.sender] = s_totalLiquidity;

        bool success = i_gol.transferFrom(msg.sender, address(this), _golAmount);

        if (!success) {
            revert GolSwap__TransferFailed();
        }
    }

    /**
     * @notice Swaps ETH sent with the transaction for GOL tokens.
     * @dev Uses the constant product formula to calculate the amount of GOL to send.
     */
    function ethToGol() external payable invalidSwapValue(msg.value) {
        uint256 golToSend = _calculateSwapOutput(msg.value, TokenType.ETH);

        bool success = i_gol.transfer(msg.sender, golToSend);
        if (!success) {
            revert GolSwap__TransferFailed();
        }

        emit Swap(msg.sender, msg.value, golToSend, true);
    }

    /**
     * @notice Swaps GOL tokens for ETH.
     * @dev Uses the constant product formula to calculate the amount of ETH to send.
     * @param _golAmount The amount of GOL tokens to swap.
     */
    function golToEth(uint256 _golAmount) external invalidSwapValue(_golAmount) {
        uint256 ethToSend = _calculateSwapOutput(_golAmount, TokenType.GOL);

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

    /**
     * @notice Adds ETH and GOL tokens to the liquidity pool.
     * @dev Requires the correct GOL-ETH ratio based on existing reserves.
     * @param _golAmount The amount of GOL tokens to provide for liquidity.
     */
    function addLiquidity(uint256 _golAmount) external payable liquidityPoolNotInitialized {
        (uint256 ethReserve, uint256 golReserve) = _getReserves();
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

    /**
     * @notice Removes liquidity from the pool and returns ETH and GOL to the user.
     * @dev Calculates the proportionate share of the reserves based on liquidity tokens.
     * @param _amount The amount of GOL tokens the user wishes to redeem.
     */
    function removeLiquidity(uint256 _amount) external liquidityPoolNotInitialized {
        (uint256 ethReserve, uint256 golReserve) = _getReserves();
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

    /**
     * @notice Returns the current ETH and GOL reserves of the pool.
     * @return A tuple containing ETH reserve and GOL reserve respectively.
     */
    function _getReserves() private view returns (uint256, uint256) {
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
    function _calculatePrice(uint256 _inputAmount, uint256 _inputReserve, uint256 _outputReserve)
        private
        pure
        returns (uint256)
    {
        uint256 inputAmountWithFee = _inputAmount * PERCENTAGE_WITH_FEE;
        uint256 numerator = inputAmountWithFee * _outputReserve;
        uint256 denominator = (_inputReserve * PERCENTAGE_WITHOUT_FEE) + inputAmountWithFee;
        return numerator / denominator;
    }

    function _calculateSwapOutput(uint256 _swapAmount, TokenType _tokenToSwap)
        private
        view
        liquidityPoolNotInitialized
        returns (uint256)
    {
        (uint256 ethReserve, uint256 golReserve) = _getReserves();

        if (_tokenToSwap == TokenType.ETH) {
            return _calculatePrice(_swapAmount, ethReserve - _swapAmount, golReserve);
        } else if (_tokenToSwap == TokenType.GOL) {
            return _calculatePrice(_swapAmount, golReserve - _swapAmount, ethReserve);
        } else {
            revert GolSwap__UnsupportedTokenType();
        }
    }

    /**
     * @notice Returns the address of the contract owner.
     * @return The owner's address.
     */
    function getOwner() external view returns (address) {
        return i_owner;
    }

    /**
     * @notice Returns the total liquidity in the pool.
     * @return The total liquidity (in ETH).
     */
    function getTotalLiquidity() external view returns (uint256) {
        return s_totalLiquidity;
    }

    /**
     * @notice Returns the liquidity provided by a specific user.
     * @param _address The address of the user.
     * @return The amount of liquidity provided by the user.
     */
    function getProvidedLiquidityByUser(address _address) external view returns (uint256) {
        return liquidity[_address];
    }

    /**
     * @notice Adds a way to call get reserves externally
     * @return A tuple containing ETH reserve and GOL reserve respectively.
     */
    function getReserves() external view returns (uint256, uint256) {
        return _getReserves();
    }

    /**
     * @notice Calculates the amount of token B required when providing liquidity with token A.
     * @dev Useful for maintaining the correct ratio when adding liquidity.
     * @param _tokenAmount The amount of one token (ETH or GOL).
     * @param _tokenType The type of token provided (ETH or GOL).
     * @param ethReserve The current ETH reserve in the pool.
     * @param golReserve The current GOL reserve in the pool.
     * @return The required amount of the other token to maintain the pool ratio.
     */
    function quoteLiquidity(uint256 _tokenAmount, TokenType _tokenType, uint256 ethReserve, uint256 golReserve)
        public
        view
        liquidityPoolNotInitialized
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
}

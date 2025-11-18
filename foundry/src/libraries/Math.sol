// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.11;

library Math {
    /**
     * @notice Returns the smaller of two numbers
     * @param a First number
     * @param b Second number
     * @return The smaller of the two numbers
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @notice Calculate the square root of a number
     * @param y The number to calculate the square root of
     * @return z The square root of the number
     */
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    /**
     * @notice Calculate f(x0, y) = x0 * y^3 + x0^3 * y
     * @param x0 Parameter x0
     * @param y Parameter y
     * @return Result of the function
     */
    function _f(uint256 x0, uint256 y) internal pure returns (uint256) {
        return x0 * (y * y / 1e18 * y / 1e18) / 1e18 + (x0 * x0 / 1e18 * x0 / 1e18) * y / 1e18;
    }

    /**
     * @notice Calculate f'(x0, y) = 3 * x0 * y^2 + x0^3
     * @param x0 Parameter x0
     * @param y Parameter y
     * @return Result of the derivative
     */
    function _d(uint256 x0, uint256 y) internal pure returns (uint256) {
        return 3 * x0 * (y * y / 1e18) / 1e18 + (x0 * x0 / 1e18 * x0 / 1e18);
    }

    /**
     * @notice Given x0 and xy, compute y such that f(x0, y) = xy
     * @param x0 Parameter x0
     * @param xy Parameter xy
     * @param y Initial guess for y
     * @return y The computed value of y
     */
    function _get_y(uint256 x0, uint256 xy, uint256 y) internal pure returns (uint256) {
        for (uint256 i = 0; i < 255; i++) {
            uint256 y_prev = y;
            uint256 k = _f(x0, y);
            if (k < xy) {
                uint256 dy = (xy - k) * 1e18 / _d(x0, y);
                y = y + dy;
            } else {
                uint256 dy = (k - xy) * 1e18 / _d(x0, y);
                y = y - dy;
            }
            if (y > y_prev) {
                if (y - y_prev <= 1) {
                    return y;
                }
            } else {
                if (y_prev - y <= 1) {
                    return y;
                }
            }
        }
        return y;
    }
}

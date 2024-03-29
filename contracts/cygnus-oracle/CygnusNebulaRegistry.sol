//  SPDX-License-Identifier: AGPL-3.0-or-later
//
//  CygnusNebulaRegistry.sol
//
//  Copyright (C) 2023 CygnusDAO
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Affero General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Affero General Public License for more details.
//
//  You should have received a copy of the GNU Affero General Public License
//  along with this program.  If not, see <https://www.gnu.org/licenses/>.

/*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
    
           █████████                🛸         🛸                              🛸          .                    
     🛸   ███░░░░░███                                              📡                                     🌔   
         ███     ░░░  █████ ████  ███████ ████████   █████ ████  █████        ⠀
        ░███         ░░███ ░███  ███░░███░░███░░███ ░░███ ░███  ███░░      .     .⠀        🛰️   .             
        ░███          ░███ ░███ ░███ ░███ ░███ ░███  ░███ ░███ ░░█████       ⠀
        ░░███     ███ ░███ ░███ ░███ ░███ ░███ ░███  ░███ ░███  ░░░░███              .             .           
         ░░█████████  ░░███████ ░░███████ ████ █████ ░░████████ ██████       -----========*⠀
          ░░░░░░░░░    ░░░░░███  ░░░░░███░░░░ ░░░░░   ░░░░░░░░ ░░░░░░            .                            .
                       ███ ░███  ███ ░███                .                 .         🛸           ⠀             
         .    🛸*     ░░██████  ░░██████   .    🛸                     🛰️            -----=========*                 
                       ░░░░░░    ░░░░░░                                               🛸  ⠀
           .                            .       .             🛰️         .                          
    
        CYGNUS NEBULA REGISTRY - https://cygnusdao.finance                                                          .                     .
    ═══════════════════════════════════════════════════════════════════════════════════════════════════════════ */
pragma solidity >=0.8.17;

// Dependencies
import {ICygnusNebulaRegistry} from "./interfaces/ICygnusNebulaRegistry.sol";
import {ICygnusNebula} from "./interfaces/ICygnusNebula.sol";
import {ReentrancyGuard} from "./utils/ReentrancyGuard.sol";

// Libraries

// Interfaces
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";
import {IERC20} from "./interfaces/IERC20.sol";

/**
 *  @title  CygnusNebulaRegistry
 *  @author CygnusDAO
 *  @notice Registry of all nebulas deployed by CygnusDAO. A nebula is a contract which contains the logic to
 *          price specific Liquidity Tokens. For example, Balancer Weighted Pools requires different logic than
 *          UniswapV2 pairs to price the liquidity token, so we must deploy separate logic for each. A nebula
 *          oracle is a unique LP oracle within the nebula.
 *
 *          Each nebula we deploy must have this registry's address as the registry is the only one that can
 *          initialize a specific Liquidity Token in the nebula.
 *
 *          At the time of pool deployment, the hangar18 contract checks this contract to see if the liquidity
 *          token has been added to the registry via `getLPTokenNebulaAddress`. If it hasn't, then the pool cannot
 *          be deployed as the collateral cannot be priced.
 */
contract CygnusNebulaRegistry is ICygnusNebulaRegistry, ReentrancyGuard {
    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            2. STORAGE
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Storage mapping for LP Token => Nebula address
     */
    mapping(address => address) internal lpNebulas;

    /**
     *  @notice Storage mapping for Nebula address => Nebula struct
     */
    mapping(address => CygnusNebula) internal nebulas;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @inheritdoc ICygnusNebulaRegistry
     */
    CygnusNebula[] public override allNebulas;

    /**
     *  @inheritdoc ICygnusNebulaRegistry
     */
    address[] public allNebulaOracles;

    /**
     *  @inheritdoc ICygnusNebulaRegistry
     */
    string public override name = "Cygnus: Veil Nebula";

    /**
     *  @inheritdoc ICygnusNebulaRegistry
     */
    string public override version = "1.0.0";

    /**
     *  @inheritdoc ICygnusNebulaRegistry
     */
    address public override admin;

    /**
     *  @inheritdoc ICygnusNebulaRegistry
     */
    address public override pendingAdmin;

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            3. CONSTRUCTOR
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @notice Constructs the Oracle registry
     */
    constructor() {
        // Assign the admin
        admin = msg.sender;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            4. MODIFIERS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /**
     *  @custom:modifier cygnusAdmin Modifier for admin control only 👽
     */
    modifier cygnusAdmin() {
        isCygnusAdmin();
        _;
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            5. CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── Internal ───────────────────────────────────────────────  */

    /**
     *  @notice Internal check for admin control only 👽
     */
    function isCygnusAdmin() internal view {
        /// @custom:error MsgSenderNotAdmin Avoid unless caller is Cygnus Admin
        if (msg.sender != admin) revert CygnusNebula__SenderNotAdmin();
    }

    /**
     *  @notice Checks if the oracle has already been added, if it has then we revert the tx
     *  @param _nebula The address of the new nebula oracle
     */
    function isNebulaAlreadyAdded(address _nebula) internal view {
        // Gas savings
        CygnusNebula[] memory _allNebulas = allNebulas;

        // Check if oracle is already added
        for (uint256 i = 0; i < _allNebulas.length; i++) {
            /// @custom:error OracleAlreadyAdded
            if (_allNebulas[i].nebula == _nebula) revert CygnusNebula__OracleAlreadyAdded();
        }
    }

    /*  ─────────────────────────────────────────────── Public ────────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusNebulaRegistry
     */
    function totalNebulas() public view override returns (uint256) {
        // Total initialized nebulas
        return allNebulas.length;
    }

    /**
     *  @inheritdoc ICygnusNebulaRegistry
     */
    function totalNebulaOracles() public view override returns (uint256) {
        // Total initialized LP Token pairs
        return allNebulaOracles.length;
    }

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusNebulaRegistry
     */
    function getNebula(address _nebula) external view override returns (CygnusNebula memory) {
        // Return the nebula struct for this `_nebula`
        return nebulas[_nebula];
    }

    /**
     *  @inheritdoc ICygnusNebulaRegistry
     */
    function getLPTokenNebula(address lpTokenPair) external view override returns (CygnusNebula memory) {
        // Get the stored nebula for `lpTokenPair`
        address nebula = lpNebulas[lpTokenPair];

        // Return the nebula struct for this `lpTokenPair`
        return nebulas[nebula];
    }

    /**
     *  @inheritdoc ICygnusNebulaRegistry
     */
    function getLPTokenNebulaAddress(address lpTokenPair) external view override returns (address) {
        // Return the address of the nebula for this `lpTokenPair`
        // If not set then returns zero address
        return lpNebulas[lpTokenPair];
    }

    /**
     *  @inheritdoc ICygnusNebulaRegistry
     */
    function getLPTokenNebulaOracle(address lpTokenPair) external view override returns (ICygnusNebula.NebulaOracle memory) {
        // Get the stored nebula for the LP Token
        address nebula = lpNebulas[lpTokenPair];

        // Return the oracle struct
        return ICygnusNebula(nebula).getNebulaOracle(lpTokenPair);
    }

    /**
     *  @inheritdoc ICygnusNebulaRegistry
     */
    function getLPTokenPriceUsd(address lpTokenPair) external view override returns (uint256) {
        // Get the stored nebula for the LP Token
        address nebula = lpNebulas[lpTokenPair];

        // Return the price of the LP in the oracle`s denomination token (in our case USDC)
        // IMPORTANT: Do not use this in any important contract since the oracle never does safety checks,
        // such as assuring price != 0, etc.
        return ICygnusNebula(nebula).lpTokenPriceUsd(lpTokenPair);
    }

    /**
     *  @inheritdoc ICygnusNebulaRegistry
     */
    function getLPTokenInfo(
        address lpTokenPair
    ) external view override returns (IERC20[] memory, uint256[] memory, uint256[] memory, uint256[] memory, uint256[] memory) {
        // Get the stored nebula for the LP Token
        address nebula = lpNebulas[lpTokenPair];

        // Return the current info of the LP
        // IMPORTANT: Do not use this on-chain, this function is for convention and reporting purposes only
        return ICygnusNebula(nebula).lpTokenInfo(lpTokenPair);
    }

    /*  ═══════════════════════════════════════════════════════════════════════════════════════════════════════ 
            6. NON-CONSTANT FUNCTIONS
        ═══════════════════════════════════════════════════════════════════════════════════════════════════════  */

    /*  ────────────────────────────────────────────── External ───────────────────────────────────────────────  */

    /**
     *  @inheritdoc ICygnusNebulaRegistry
     *  @custom:security only-admin 👽
     */
    function createNebulaOracle(
        uint256 nebulaId,
        address lpTokenPair,
        AggregatorV3Interface[] calldata aggregators
    ) external override cygnusAdmin {
        // Get nebula address
        CygnusNebula storage nebula = allNebulas[nebulaId];

        // Initialize nebula. Will revert if it has already been initialized and we are outside grace period
        ICygnusNebula(nebula.nebula).initializeNebulaOracle(lpTokenPair, aggregators);

        // If this is the first time we initialize this oracle;
        // Account for cases where we modify the oracle during grace period
        if (lpNebulas[lpTokenPair] == address(0)) {
            // Increase total initialized oracles
            nebula.totalOracles++;

            // Add lp token to the array
            allNebulaOracles.push(lpTokenPair);
        }

        // Map LP Token => Nebula address
        lpNebulas[lpTokenPair] = nebula.nebula;

        // Map Nebula address => Nebula struct
        nebulas[nebula.nebula] = nebula;
    }

    /**
     *  @inheritdoc ICygnusNebulaRegistry
     *  @custom:security only-admin 👽
     */
    function createNebula(address _nebula) external override cygnusAdmin {
        // Check if oracle is already added, tx reverts if nebula has been added already
        isNebulaAlreadyAdded(_nebula);

        // Create new nebula since it passed checks
        CygnusNebula memory nebula = CygnusNebula({
            name: ICygnusNebula(_nebula).name(),
            nebula: _nebula,
            nebulaId: totalNebulas(),
            totalOracles: 0,
            createdAt: block.timestamp
        });

        // Add nebula to array
        allNebulas.push(nebula);

        // Add nebula to mapping
        nebulas[_nebula] = nebula;

        /// @custom:event NewNebulaOracle
        emit NewNebulaOracle(_nebula, nebula.nebulaId);
    }

    /**
     *  @inheritdoc ICygnusNebulaRegistry
     *  @custom:security only-admin 👽
     */
    function setRegistryPendingAdmin(address newPendingAdmin) external override cygnusAdmin {
        // Pending admin initial is always zero
        /// @custom:error PendingAdminAlreadySet Avoid setting the same pending admin twice
        if (newPendingAdmin == pendingAdmin) revert CygnusNebula__PendingAdminAlreadySet();

        // Assign address of the requested admin
        pendingAdmin = newPendingAdmin;

        /// @custom:event NewOraclePendingAdmin
        emit NewNebulaPendingAdmin(admin, newPendingAdmin);
    }

    /**
     *  @inheritdoc ICygnusNebulaRegistry
     *  @custom:security only-admin 👽
     */
    function setRegistryAdmin() external override cygnusAdmin {
        /// @custom:error AdminCantBeZero Avoid settings the admin to the zero address
        if (pendingAdmin == address(0)) revert CygnusNebula__AdminCantBeZero();

        // Address of the Admin up until now
        address oldAdmin = admin;

        // Assign new admin
        admin = pendingAdmin;

        // Gas refund
        delete pendingAdmin;

        // @custom:event NewOracleAdmin
        emit NewNebulaAdmin(oldAdmin, admin);
    }
}

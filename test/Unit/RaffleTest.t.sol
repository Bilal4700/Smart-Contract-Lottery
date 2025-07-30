//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract RaffleTest is Test {
    // Events
    event RaffleEntered(address indexed player);
    event RaffleWinnerPicked(address indexed winner);

    Raffle private raffle;
    HelperConfig private helperConfig;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_PLAYER_BALANCE = 10 ether;

    uint256 interval;
    uint256 entranceFee;
    address vrfCoordinator;
    bytes32 keyHash;
    uint32 callbackGasLimit;
    uint256 subscriptionId;

    function setUp() public {
        DeployRaffle deployer = new DeployRaffle();
        (raffle, helperConfig) = deployer.deployContract();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();
        entranceFee = config.entranceFee;
        interval = config.interval;
        vrfCoordinator = config.vrfCoordinator;
        keyHash = config.keyHash;
        callbackGasLimit = config.callbackGasLimit;
        subscriptionId = config.subscriptionId;

        vm.deal(PLAYER, STARTING_PLAYER_BALANCE);
    }

    function testRaffleInitialisesInOpenState() public view {
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    function testRaffleRevertsWhenDonotPayEnough() public {
        // Arrange
        vm.startPrank(PLAYER);
        // Act/Revert
        vm.expectRevert(Raffle.Raffle_SendMoreToEnterRafflel.selector);
        raffle.enterRaffle{value: entranceFee - 1}();
        vm.stopPrank();
    }

    function testRaffleRecordsPlayersUponEntry() public {
        // Arrange
        vm.startPrank(PLAYER);
        uint256 startingPlayerCount = raffle.getPlayersLength();
        // Act
        raffle.enterRaffle{value: entranceFee}();
        // Assert
        assert(raffle.getPlayersLength() == startingPlayerCount + 1);
        assert(raffle.getPlayers(0) == PLAYER);
        vm.stopPrank();
    }

    function testEnteringRaffleEmitsEvent() public {
        // Arrange
        vm.startPrank(PLAYER);
        // Act
        vm.expectEmit(true, false, false, false, address(raffle));
        emit RaffleEntered(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.stopPrank();
    }

    function testDontAllowPlayersToEnterWhileRaffleIsCalculating() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1); // to make sure enough time has passed
        vm.roll(block.number + 1); // Change the block number to ensure the upkeep is needed
        raffle.performUpkeep(""); // This will change the raffle state to CALCULATING

        // Act/Assert
        vm.expectRevert(Raffle.Raffle_RaffleNotOpen.selector);
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCheckUpkeepReturnsFalseIfItHasNoBalance() public {
        // Arrange
        vm.warp(block.timestamp + interval + 1); // to make sure enough time has passed
        vm.roll(block.number + 1); // Change the block number to ensure the upkeep is needed

        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // Assert
        assert(!upkeepNeeded);
    }

    function testCheckUpKeepReturnsFalseIfRaffleIsntOpen() public {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1); // to make sure enough time has passed
        vm.roll(block.number + 1); // Change the block number to ensure the upkeep is needed
        raffle.performUpkeep(""); // This will change the raffle state to CALCULATING

        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // Assert
        assert(!upkeepNeeded);
    }

    //Perfrom Upkeep Tests
}

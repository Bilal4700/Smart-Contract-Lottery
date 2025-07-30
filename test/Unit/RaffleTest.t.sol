//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployRaffle} from "../../script/DeployRaffle.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2_5Mock} from "../../lib/chainlink-brownie-contracts/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

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

    modifier raffleEntered() {
        // Arrange
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1); // to make sure enough time has passed
        vm.roll(block.number + 1); // Change the block number to ensure the upkeep is needed
        _;
    }

    modifier SkipTestOnSepolia() {
        if (block.chainid == 11155111) {
            // Sepolia testnet
            return;
        }
        _;
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

    function testDontAllowPlayersToEnterWhileRaffleIsCalculating()
        public
        raffleEntered
    {
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

    function testCheckUpKeepReturnsFalseIfRaffleIsntOpen()
        public
        raffleEntered
    {
        raffle.performUpkeep(""); // This will change the raffle state to CALCULATING

        // Act
        (bool upkeepNeeded, ) = raffle.checkUpkeep("");

        // Assert
        assert(!upkeepNeeded);
    }

    //Perfrom Upkeep Tests
    function testPerformUpkeepCanOnlyRunIfCheckUpKeepIsTrue()
        public
        raffleEntered
    {
        // Act/assert
        raffle.performUpkeep("");
    }

    function testPErformUpkeepRevertsIfCheckUpKeepIsFalse() public {
        // Arrange
        uint256 currentBalance = 0;
        uint256 numPlayer = 0;
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        vm.prank(PLAYER);
        raffle.enterRaffle{value: entranceFee}();
        currentBalance = currentBalance + entranceFee;
        numPlayer = numPlayer + 1;

        // Act/Assert
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle_UpkeepNotNeeded.selector,
                currentBalance,
                numPlayer,
                uint256(raffleState)
            )
        );
        raffle.performUpkeep("");
    }

    function testPerformUpKeepUpdateRaffleStateAndEmitsEvent()
        public
        raffleEntered
    {
        // Act
        vm.recordLogs(); // logs are events emited when performUpkeep is called
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs(); // Retrieve the logs
        bytes32 requestId = entries[1].topics[1]; // Get the requestId from the logs

        // Assert
        Raffle.RaffleState raffleState = raffle.getRaffleState();
        assert(uint256(requestId) > 0);
        assert(raffleState == Raffle.RaffleState.CALCULATING);
    }

    // Fulfill Random Words Tests

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(
        uint256 randomRequestId /* requestId (fuzz test)*/
    ) public raffleEntered SkipTestOnSepolia {
        vm.expectRevert(VRFCoordinatorV2_5Mock.InvalidRequest.selector);
        VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
    }

    // function testFulfillRandomWordsPickAWinnerresetsAndSendMoney()
    //     public
    //     raffleEntered
    // {
    //     // Arrange
    //     uint256 additionEnterants = 3; // 4 total
    //     uint256 startingIndex = 1;
    //     address expectedWinner = address(0);

    //     for (
    //         uint256 i = startingIndex;
    //         i < additionEnterants + startingIndex;
    //         i++
    //     ) {
    //         address newPlayer = vm.addr(uint160(i)); // convert anynumber to address
    //         hoax(newPlayer, STARTING_PLAYER_BALANCE); // give ethers and setsup a prank
    //         raffle.enterRaffle{value: entranceFee}();
    //     }
    //     uint256 startingTimestamp = raffle.getLastTimeStamp();
    //     uint256 winnerStartingBalance = expectedWinner.balance;

    //     // Act
    //     vm.recordLogs(); // logs are events emited when performUpkeep is called
    //     raffle.performUpkeep("");
    //     Vm.Log[] memory entries = vm.getRecordedLogs(); // Retrieve the logs
    //     bytes32 requestId = entries[1].topics[1]; // Get the requestId from the logs
    //     VRFCoordinatorV2_5Mock(vrfCoordinator).fulfillRandomWords(
    //         uint256(requestId),
    //         address(raffle)
    //     );

    //     // Assert
    //     address rexentWinner = raffle.getRecentWinner();
    //     Raffle.RaffleState raffleState = raffle.getRaffleState();
    //     uint256 winnerBalance = expectedWinner.balance;
    //     uint256 endingTimestamp = raffle.getLastTimeStamp();
    //     uint256 prize = entranceFee * (additionEnterants + 1);

    //     assertEq(rexentWinner, expectedWinner, " Wrong winner chosen");
    //     assertEq(uint256(raffleState), 0, "Raffle state not reset");
    //     assertEq(
    //         winnerBalance,
    //         winnerStartingBalance + prize,
    //         " Winner balance did not update correctly"
    //     );
    //     assertGt(
    //         endingTimestamp,
    //         startingTimestamp,
    //         " Timestamp did not update"
    //     );
    // }
}

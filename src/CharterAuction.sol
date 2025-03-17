// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Importing IERC20 and SafeERC20 from OpenZeppelin contracts for ERC20 token operations.
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { PRBMathUD60x18 } from "prb-math/PRBMathUD60x18.sol";

/// @title CharterAuction
/// @notice An auction contract with blind rounds where a position owner receives a reward each time their position is selected in a new round.
contract CharterAuction {
    // Using SafeERC20 for IERC20 to handle ERC20 token operations safely.
    using SafeERC20 for IERC20;

    // Using PRBMathUD60x18 for uint256 to handle uint256 operations safely.
    using PRBMathUD60x18 for uint256;

    // Variables to store the USDT token address, entry fee, current round number, minimum raised funds, total raised funds, and the winner of the auction.
    IERC20 public usdt; // The USDT token address.
    uint256 public entryFee; // The fixed fee required to buy a position.
    uint256 public currentRound; // The current round number.
    uint256 public minRaisedFundsAtBlindRound; // The minimum raised funds required to end the auction.
    uint256 public raisedFundAtBlindRound; // The total raised funds in the auction.
    uint256 public constant MIN_POSITIONS = 3; // Minimum number of positions required for the auction to end.
    address public broker; // The address of the broker.
    address public winner; // The address of the winner of the auction.

    // Mapping to store reward balances for each bidder.
    mapping(address => uint256) public rewards;

    // Struct to represent a position in the auction.
    struct Position {
        address[] rewarders; // Addresses of bidders who have selected this position.
        uint256 bidPrice; // The revealed bid price (position price).
    }

    // Struct to represent a bidder's information.
    struct BlindBidderInfo {
        address bidder; // The address of the bidder.
        bytes32[] bidInfos; // Array of bid infos submitted by the bidder.
    }

    // Struct to represent a round in the auction.
    struct BlindRound {
        BlindBidderInfo[] bidders; // Array of bidder information in the round.
        bool ended; // Flag to indicate if the round has ended.
    }

    // Struct to represent a bidder's information.
    struct BidderInfo {
        address bidder; // The address of the bidder.
        uint256[] bidPrices; // Array of bid prices submitted by the bidder.
    }

    // Struct to represent a round in the auction.
    struct Round {
        Position[] positions; // Array of positions in the round.
        BidderInfo[] bidders; // Array of bidder information in the round.
        bool ended; // Flag to indicate if the round has ended.
    }

    // Mapping to store rounds of the auction.
    mapping(uint256 => Round) public rounds;

    // Struct to represent a blind round in the auction.
    BlindRound public blindRound;

    // Auction created event.
    event AuctionCreated(address indexed broker, uint256 indexed round, address indexed usdt, uint256 entryFee, uint256 minRaisedFundsAtBlindRound);
    // Blind bid entered event.
    event BlindBidEntered(uint256 indexed round, address indexed bidder, bytes32 bidInfo);
    // New round started event.
    event NewRoundStarted(uint256 indexed round);
    // End auction event.
    event EndAuction(uint256 indexed round, uint256 targetPrice, address winner);
    // Reward withdrawn event.
    event RewardWithdrawn(address indexed rewarder, uint256 amount);
    // Bid position event.
    event BidPosition(uint256 indexed round, uint256 positionIndex, address indexed bidder, uint256 entryFee);

    // Errors that can be reverted.
    error InvalidUSDTAddress(); // Invalid USDT address.
    error InvalidBidInfo(); // Invalid bid info.
    error InvalidEntryFee(); // Invalid entry fee.
    error TransferFailed(); // Transfer failed.
    error InsufficientBalance(); // Insufficient balance.
    error RoundEnded(); // Round ended.
    error InvalidMinRaisedFundsAtBlindRound(); // Invalid minimum raised funds at blind round.
    error DoubleBid(); // Double bid.
    error DoubleBlindBid(); // Double blind bid.
    error RoundAlreadyEnded(); // Round already ended.
    error StillInBlindRound(); // Still in blind round.
    error CannotEndBlindRound(); // Cannot end blind round.
    error NoRewards(); // No rewards.
    error InvalidPositionIndex(); // Invalid position index.
    error BlindRoundEnded(); // Blind round ended.
    error InvalidValuesForGeometricMean(); // Invalid values for geometric mean.
    error ValueShouldBePositiveForGeometricMean(); // Value should be positive for geometric mean.
    error InvalidNumberOfPositions(); // Invalid number of positions.
    error BlindRoundStep(); // Blind round step.
    error NotBlindRoundStep(); // Not blind round step.
    error NotBroker(); // Not broker.

    /// @notice Initialize the auction with the USDT token address and entry fee.
    /// @dev The broker is the address of the broker who creates the auction.
    /// @param _usdt The address of the USDT token.
    /// @param _entryFee The entry fee for the auction.
    /// @param _minRaisedFundsAtBlindRound The minimum raised funds required to end the blind round.
    /// @param _broker The address of the broker.
    constructor(address _usdt, uint256 _entryFee, uint256 _minRaisedFundsAtBlindRound, address _broker) {
        // Validate the USDT token address, entry fee, and minimum raised funds.
        if (_usdt == address(0)) revert InvalidUSDTAddress();
        if (_entryFee == 0) revert InvalidEntryFee();
        if (_minRaisedFundsAtBlindRound == 0) revert InvalidMinRaisedFundsAtBlindRound();

        // Initialize contract variables.
        usdt = IERC20(_usdt);
        broker = _broker;
        entryFee = _entryFee;
        minRaisedFundsAtBlindRound = _minRaisedFundsAtBlindRound;

        currentRound = 0; // Initialize the current round to blind round.

        // Emit event to signal the creation of the auction.
        emit AuctionCreated(broker, currentRound, _usdt, _entryFee, _minRaisedFundsAtBlindRound);
    }

    /// @notice Check if the bidder has already bid with the same price in the current round.
    /// @param _bidInfo The hash of the bid price and the bidder's address.
    /// @param _bidder The address of the bidder.
    /// @return True if the bidder has already bid with the same price, false otherwise.
    function checkDoubleBlindBid(bytes32 _bidInfo, address _bidder) internal view returns (bool) {
      // Check if the bidder has already bid with the same price in the current round.
      uint256 bidderIndex = searchBlindBidder(_bidder); // Search for a bidder in the current round.
      if (bidderIndex < blindRound.bidders.length) { // Check if the bidder exists in the current round.
        for (uint256 i = 0; i < blindRound.bidders[bidderIndex].bidInfos.length; i++) { // Check if the bidder has already bid with the same price in the current round.
          if (blindRound.bidders[bidderIndex].bidInfos[i] == _bidInfo) { // Check if the bid info is valid.
            return true;
          }
        }
      }
      return false;
    }

    /// @notice Search for a bidder in the current round.
    /// @param _bidder The address of the bidder.
    /// @return The index of the bidder in the current round.
    function searchBlindBidder(address _bidder) internal view returns (uint256) {
      // Search for a bidder in the current round.
      uint256 i = 0;
      for (i = 0; i < blindRound.bidders.length; i++) {
        if (blindRound.bidders[i].bidder == _bidder) {
          break;
        }
      }
      return i;
    }

    /// @notice Sort the prices in descending order.
    /// @param _prices The array of prices to sort.
    /// @return The sorted array of prices.
    function sortPrices(uint256[] memory _prices) internal pure returns (uint256[] memory) {
      // Sort the prices in descending order.
      for (uint256 i = 0; i < MIN_POSITIONS; i++) {
        for (uint256 j = i + 1; j < _prices.length; j++) {
          if (_prices[i] < _prices[j]) {
            uint256 temp = _prices[i];
            _prices[i] = _prices[j];
            _prices[j] = temp;
          }
        }
      }
      return _prices;
    }

    /// @notice Enter the blind round by paying the entry fee.
    /// @dev This function is only available for the blind round.
    /// @param _bidInfo The hash of the bid price and the bidder's address.
    function bidAtBlindRound(bytes32 _bidInfo) external {
        // Check if the current round has ended.
        if (blindRound.ended) revert BlindRoundEnded();
        // Check if the bidder has sufficient balance.
        if(usdt.balanceOf(msg.sender) < entryFee) revert InsufficientBalance();
        // Transfer entry fee from bidder to the contract.
        usdt.safeTransferFrom(msg.sender, address(this), entryFee);  // SafeERC20 will revert on failure
        // Check if the bidder has already bid with the same price.
        if (checkDoubleBlindBid(_bidInfo, msg.sender)) revert DoubleBlindBid();

        // Check if the total raised funds exceed the minimum required.
        if (raisedFundAtBlindRound + entryFee > minRaisedFundsAtBlindRound) {
          revert BlindRoundEnded();
        }

        // Add the bid info to the bidder's information.
        uint256 bidderIndex = searchBlindBidder(msg.sender);
        if (bidderIndex < blindRound.bidders.length) {
            blindRound.bidders[bidderIndex].bidInfos.push(_bidInfo);
        } else {
            bytes32[] memory initialBidInfos = new bytes32[](1);
            initialBidInfos[0] = _bidInfo;
            blindRound.bidders.push(BlindBidderInfo({
                bidder: msg.sender,
                bidInfos: initialBidInfos
            }));
        }

        // Emit event to signal bid entry.
        emit BlindBidEntered(currentRound, msg.sender, _bidInfo);
    }

    /// @notice End the blind round and start a new one.
    /// @param _blindBidPrices The array of bid prices in the blind round.
    function endBlindRound(uint256[] memory _blindBidPrices) public {
      // End the current round and start a new one.
      if (blindRound.ended) revert BlindRoundEnded();
      // Check if the broker is the caller.
      if(msg.sender != broker) revert NotBroker();
      // Check if the raised funds are less than the minimum required.
      if(raisedFundAtBlindRound + entryFee < minRaisedFundsAtBlindRound) revert CannotEndBlindRound();

      uint256 prevPriceIndex; // The index of the previous price.
      uint256 priceIndex; // The index of the current price.
      uint256 newPrice; // The new price.
      bytes32 bidInfoWithPrice; // The bid info with price.
      uint256 positionIndex; // The index of the position.
      
      blindRound.ended = true;

      // Iterate through the bidders in the blind round.
      for (uint256 i = 0; i < blindRound.bidders.length; i++) {
        prevPriceIndex = priceIndex; // Set the previous price index to the current price index.
        for (uint256 j = 0; j < blindRound.bidders[i].bidInfos.length; j++) {
          // get the bid info with price
          bidInfoWithPrice = keccak256(abi.encodePacked(blindRound.bidders[i].bidder, _blindBidPrices[priceIndex]));
          if(blindRound.bidders[i].bidInfos[j] != bidInfoWithPrice) revert InvalidBidInfo(); // check if the bid info is valid
          priceIndex++; // Increment the price index.
        }

        // get the bid prices for the geometric mean
        uint256[] memory bidPricesForGeometricMean; // The array of bid prices for the geometric mean.
        for (uint256 k = prevPriceIndex; k < priceIndex; k++) {
            uint256 bidPrice = uint256(_blindBidPrices[k]); // Get the bid price.
            bidPricesForGeometricMean.push(bidPrice); // Add the bid price to the array.
        }

        newPrice = geometricMean(bidPricesForGeometricMean); // Calculate the geometric mean.

        positionIndex = searchPosition(newPrice); // Search for a position with the given bid price in the current round.

        if (positionIndex < rounds[currentRound].positions.length) {
            rounds[currentRound].positions[positionIndex].rewarders.push(blindround.bidders[i].bidder);
        } else {
            Position storage newPosition = rounds[currentRound].positions.push(); // Add a new position to the current round.
            newPosition.bidPrice = newPrice; // Set the bid price of the new position.
            newPosition.rewarders.push(blindRound.bidders[i].bidder); // Add the bidder to the position.
        }
      }

      // if the number of positions is less than the minimum required, end the auction
      if(rounds[currentRound].positions.length <= MIN_POSITIONS) {
        endAuction();
        return;
      }
      
      emit NewRoundStarted(currentRound);
    }

    /// @notice Check if the bidder has already bid with the same price in the current round.
    /// @param _bidPrice The bid price.
    /// @param _bidder The address of the bidder.
    /// @return True if the bidder has already bid with the same price, false otherwise.
    function checkDoubleBid(uint256 _bidPrice, address _bidder) internal view returns (bool) {
      // Check if the bidder has already bid with the same price in the current round.
      uint256 bidderIndex = searchBidder(_bidder);
      if (bidderIndex < rounds[currentRound].bidders.length) {
        for (uint256 i = 0; i < rounds[currentRound].bidders[bidderIndex].bidPrices.length; i++) {
          if (rounds[currentRound].bidders[bidderIndex].bidPrices[i] == _bidPrice) {
            return true;
          }
        }
      }
      return false;
    }

    /// @notice Search for a position with the given bid price in the current round.
    /// @param _bidPrice The bid price.
    /// @return The index of the position.  
    function searchPosition(uint256 _bidPrice) internal view returns (uint256) {
      // Search for a position with the given bid price in the current round.
      uint256 i = 0;
      for (i = 0; i < rounds[currentRound].positions.length; i++) {
        if (rounds[currentRound].positions[i].bidPrice == _bidPrice) {
          break;
        }
      }
      return i;
    }

    /// @notice Search for a bidder in the current round.
    /// @param _bidder The address of the bidder.
    /// @return The index of the bidder in the current round.
    function searchBidder(address _bidder) internal view returns (uint256) {
      // Search for a bidder in the current round.
      uint256 i = 0;
      for (i = 0; i < rounds[currentRound].bidders.length; i++) {
        if (rounds[currentRound].bidders[i].bidder == _bidder) {
          break;
        }
      }
      return i;
    }

    /// @notice Computes the geometric mean of an array of UD60x18 positive numbers.
    /// @dev GM = exp((log(x₁) + log(x₂) + … + log(xₙ)) / n)
    /// @param values An array of positive numbers in UD60x18 format.
    /// @return The geometric mean (in UD60x18 format).
    function geometricMean(uint256[] memory values) internal returns (uint256) {
        if(values.length > 0) revert InvalidValuesForGeometricMean();

        uint256 sumLog = 0;
        uint256 n = values.length;

        for (uint256 i = 0; i < n; i++) {
            if(values[i] == 0) revert ValueShouldBePositiveForGeometricMean();
            // Sum the natural logarithms of each value
            sumLog += PRBMathUD60x18.log(values[i]);
        }

        // Compute the average of the logarithms
        uint256 avgLog = sumLog / n;

        // The geometric mean is the exponentiation of the average logarithm
        return PRBMathUD60x18.exp(avgLog);
    }

    /// @notice Get the target price for the current round.
    /// @return The target price.
    function getTargetPrice() internal view returns (uint256) {
      // Calculate the target price for the current round.
      uint256[] memory prices = new uint256[](rounds[currentRound].positions.length);

      // Iterate through the positions in the current round.
      for (uint256 i = 0; i < rounds[currentRound].positions.length; i++) {
        prices[i] = rounds[currentRound].positions[i].bidPrice;
      }
      prices = sortPrices(prices);      
      // get the bid prices for the geometric mean
      uint256[] memory pricesForGeometricMean;  
      for (uint256 k = 0; k < MIN_POSITIONS; k++) {
          uint256 price = prices[k];
          pricesForGeometricMean.push(price);
      }

      return geometricMean(pricesForGeometricMean);
    }

    /// @notice End the auction.
    function endAuction() external {
      uint256 targetPrice; // The target price.
      uint256 minDeltaPrice = type(uint256).max; // Initialize to max value
      uint256 minDeltaPriceIndex; // The index of the position with the minimum delta price.
      uint256 deltaPrice; // The delta price.

      // Check if the number of positions is less than the minimum required.
      if(rounds[currentRound].positions.length > MIN_POSITIONS) {
        revert InvalidNumberOfPositions();
      }

      // Get the target price.
      targetPrice = getTargetPrice();

      // Iterate through the positions in the current round.
      for (uint256 i = 0; i < rounds[currentRound].positions.length; i++) {
          if (rounds[currentRound].positions[i].bidPrice >= targetPrice) {
              deltaPrice = rounds[currentRound].positions[i].bidPrice - targetPrice;
          } else {
              deltaPrice = targetPrice - rounds[currentRound].positions[i].bidPrice;
          }
          if (deltaPrice < minDeltaPrice) {
              minDeltaPrice = deltaPrice;
              minDeltaPriceIndex = i;
          }
      }

      winner = rounds[currentRound].positions[minDeltaPriceIndex].rewarders[0];

      emit EndAuction(currentRound, rounds[currentRound].positions[minDeltaPriceIndex].bidPrice, winner);
    }

    /// @notice Turn to the next round.
    function turnToNextRound() public {
      // End the current round and start a new one.
      if (rounds[currentRound].ended) revert RoundAlreadyEnded();

      if(!blindRound.ended) {
        revert BlindRoundStep();
      }

      rounds[currentRound].ended = true;

      // Iterate through the bidders in the current round.
      for (uint256 i = 0; i < rounds[currentRound].bidders.length; i++) {
        // Get the bid prices for the geometric mean.
        uint256[] memory bidPricesForGeometricMean;  
        for (uint256 k = 0; k < rounds[currentRound].bidders[i].bidPrices.length; k++) {
            uint256 bidPrice = rounds[currentRound].bidders[i].bidPrices[k];
            bidPricesForGeometricMean.push(bidPrice);
        }

        uint256 newPrice = geometricMean(bidPricesForGeometricMean); // Calculate the geometric mean.

        uint256 positionIndex = searchPosition(newPrice); // Search for a position with the given bid price in the current round.
        if (positionIndex < rounds[currentRound].positions.length) {
            rounds[currentRound].positions[positionIndex].rewarders.push(rounds[currentRound].bidders[i].bidder); 
        } else {
            Position storage newPosition = rounds[currentRound].positions.push();
            newPosition.bidPrice = newPrice;
            newPosition.rewarders.push(rounds[currentRound].bidders[i].bidder);
        }
      }

      currentRound++;

      // Check if the number of positions is less than the minimum required.
      if(rounds[currentRound].positions.length < MIN_POSITIONS) {
        endAuction();
        return;
      }
      emit NewRoundStarted(currentRound);
    }
    
    /// @notice In a new round, bidders can select a position from a previous round.
    /// Each time a position is selected, the owner of that position earns a reward equal to the entry fee.
    function bidPosition(uint256 positionIndex) external {
      uint256 _bidPrice = rounds[currentRound].positions[positionIndex].bidPrice;

      if (rounds[currentRound].ended) revert RoundEnded(); // Check if the current round has ended.
      if(!blindRound.ended) revert BlindRoundStep(); // Check if the blind round has ended.
      if(usdt.balanceOf(msg.sender) < entryFee) revert InsufficientBalance(); // Check if the bidder has sufficient balance.
      usdt.safeTransferFrom(msg.sender, address(this), entryFee);  // SafeERC20 will revert on failure
      if (checkDoubleBid(_bidPrice, msg.sender)) revert DoubleBid(); // Check if the bidder has already bid with the same price.
      if (positionIndex >= rounds[currentRound].positions.length) revert InvalidPositionIndex();

      address[] memory rewarders = rounds[currentRound].positions[positionIndex].rewarders;
      uint256 rewardAmount = entryFee / rewarders.length;
      for (uint256 i = 0; i < rewarders.length; i++) {
        rewards[rewarders[i]] += rewardAmount;
      }

      uint256 bidderIndex = searchBidder(msg.sender);
      if (bidderIndex < rounds[currentRound].bidders.length) {
          rounds[currentRound].bidders[bidderIndex].bidPrices.push(_bidPrice);
      } else {
        uint256[] memory initialBidPrices = new uint256[](1);
        initialBidPrices[0] = _bidPrice;
        rounds[currentRound].bidders.push(BidderInfo({
          bidder: msg.sender,
          bidPrices: initialBidPrices
        }));
      }

      emit BidPosition(currentRound, positionIndex, msg.sender, entryFee);
    }

    /// @notice Allows users to withdraw their accumulated rewards.
    function withdrawRewards() external {
        uint256 rewardAmount = rewards[msg.sender];
        if (rewardAmount == 0) revert NoRewards();
        rewards[msg.sender] = 0;
        usdt.safeTransfer(msg.sender, rewardAmount);  // SafeERC20 will revert on failure

        emit RewardWithdrawn(msg.sender, rewardAmount);
    }
}
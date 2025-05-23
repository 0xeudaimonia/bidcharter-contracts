// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Importing IERC20 and SafeERC20 from OpenZeppelin contracts for ERC20 token operations.
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { IERC721 } from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC721Receiver } from "openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";

import "forge-std/Test.sol";

/// @title CharterAuction
/// @notice An auction contract with blind rounds where a position owner receives a reward each time their position is selected in a new round.
contract CharterAuction is IERC721Receiver {
  // Using SafeERC20 for IERC20 to handle ERC20 token operations safely.
  using SafeERC20 for IERC20;
  uint256 constant GEOMETRIC_SCALE = 1e18; // Fixed-point scale factor
  
  // Variables to store the USDT token address, entry fee, current round number, minimum raised funds, total raised funds, and the winner of the auction.
  IERC20 public usdt; // The USDT token address.
  IERC721 public nft; // The NFT token address.
  uint256 public entryFee; // The fixed fee required to buy a position.
  uint256 public currentRound; // The current round number.
  uint256 public minRaisedFundsAtBlindRound; // The minimum raised funds required to end the auction.
  uint256 public raisedFundAtBlindRound; // The total raised funds in the auction.
  uint256 public constant MIN_POSITIONS = 3; // Minimum number of positions required for the auction to end.
  address public broker; // The address of the broker.
  address public winner; // The address of the winner of the auction.
  uint256 public nftId; // The ID of the NFT.
  uint256 public totalRewards; // The total rewards in the auction.
  // Mapping to store reward balances for each bidder.
  mapping(address => uint256) public rewards;

  // Struct to represent a position in the auction.
  struct Position {
      address[] rewarders; // Addresses of bidders who have selected this position.
      uint256 bidPrice; // The revealed bid price (position price).
  }

  // Struct to represent a round in the auction.
  struct BlindRound {
      address[] bidders; // Array of bidder information in the round.
      mapping(address => bytes32) bidInfos; // Mapping of the bid info for each bidder.
      mapping(bytes32 => bool) bidInfosUsed; // Mapping of the bid info used.
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
      mapping(address => uint256) nextBidPrice; // Mapping of the next bid price for each bidder.
      uint256 actionCount; // The number of actions in the round.
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
  event EndAuction(uint256 indexed round, uint256 winningPrice, address indexed winner);
  // Reward withdrawn event.
  event RewardWithdrawn(address indexed rewarder, uint256 amount);
  // Bid position event.
  event BidPosition(uint256 indexed round, uint256 positionIndex, address indexed bidder, uint256 entryFee);
  // NFT withdrawn event.
  event NFTWithdrawn(address indexed winner);
  // Rewards withdrawn event.
  event RewardsWithdrawn(address indexed broker, uint256 amount);

  // Bid positions event.
  event BidPositions(uint256 indexed round, uint256[] positionIndexes, address indexed bidder, uint256 entryFee);

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
  error ValueShouldBePositiveForGeometricMean(); // Value should be positive for geometric mean.
  error InvalidNumberOfPositions(); // Invalid number of positions.
  error BlindRoundStep(); // Blind round step.
  error NotBlindRoundStep(); // Not blind round step.
  error NotBroker(); // Not broker.
  error InvalidNumberOfValues(); // Invalid number of values.
  error AuctionAlreadyEnded(); // Auction already ended.
  error NoNFT(); // No NFT.
  error NotWinner(); // Not winner.
  error NoBidders(); // No bidders.
  error InvalidNumberOfBidPrices(); // Invalid number of bid prices.
  error EndedAuction(); // Ended auction.
  error InvalidMinPositions(); // Invalid minimum positions.
  error InvalidNFTAddress(); // Invalid NFT address.
  error MaliciousBidder(); // Malicious bidder.
  error OverflowBid(); // Overflow bid.

  modifier onlyBroker() {
    if (msg.sender != broker) revert NotBroker();
    _;
  }

  /// @notice Initialize the auction with the USDT token address and entry fee.
  /// @dev The broker is the address of the broker who creates the auction.
  /// @param _usdt The address of the USDT token.
  /// @param _entryFee The entry fee for the auction.
  /// @param _minRaisedFundsAtBlindRound The minimum raised funds required to end the blind round.
  /// @param _broker The address of the broker.
  /// @param _nft The address of the NFT token.
  /// @param _nftId The ID of the NFT.
  constructor(
    address _usdt,
    uint256 _entryFee,
    uint256 _minRaisedFundsAtBlindRound,
    address _broker,
    address _nft,
    uint256 _nftId
  ) {
      // Validate the USDT token address, entry fee, and minimum raised funds.
      if (_usdt == address(0)) revert InvalidUSDTAddress();
      if (_entryFee == 0) revert InvalidEntryFee();
      if (_minRaisedFundsAtBlindRound == 0) revert InvalidMinRaisedFundsAtBlindRound();
      if (_nft == address(0)) revert InvalidNFTAddress();
      // Initialize contract variables.
      usdt = IERC20(_usdt);
      nft = IERC721(_nft);
      broker = _broker;
      entryFee = _entryFee;
      minRaisedFundsAtBlindRound = _minRaisedFundsAtBlindRound;
      nftId = _nftId;
      currentRound = 0; // Initialize the current round to blind round.
      // Emit event to signal the creation of the auction.
      emit AuctionCreated(broker, currentRound, _usdt, _entryFee, _minRaisedFundsAtBlindRound);
  }

  
  /// @notice Get the bidder count in the blind round.
  /// @return The bidder count in the blind round.
  function getBlindBidderCount() external view returns (uint256) {
    return blindRound.bidders.length;
  }
  
  /// @notice Get the bidder in the blind round.
  /// @param index The index of the bidder.
  /// @return The bidder in the blind round.
  function getBlindBidder(uint256 index) external view returns (address) {
    return blindRound.bidders[index];
  }

  /// @notice Get the bid info of the bidder in the blind round.
  /// @param bidder The address of the bidder.
  /// @return The bid info of the bidder in the blind round.
  function getBlindRoundBidInfo(address bidder) external view returns (bytes32) {
      return blindRound.bidInfos[bidder];
  }

  function getBlindRoundBidInfoUsed(bytes32 bidInfo) external view returns (bool) {
    return blindRound.bidInfosUsed[bidInfo];
  }
  
  /// @notice Check if the blind round has ended.
  /// @return True if the blind round has ended, false otherwise.
  function isBlindRoundEnded() external view returns (bool) {
      return blindRound.ended;
  }

  /// @notice Check if the current round has ended.
  /// @return True if the current round has ended, false otherwise.
  function isRoundEnded() external view returns (bool) {
      return rounds[currentRound].ended;
  }

  /// @notice Get the bidders in the current round.
  /// @param round The round.
  /// @return The bidders in the current round.
  function getRoundBiddersCount(uint256 round) external view returns (uint256) {
      return rounds[round].bidders.length;
  }

  /// @notice Get the bidder in the current round.
  /// @param round The round.
  /// @param index The index of the bidder.
  /// @return The bidder in the current round.
  function getRoundBidder(uint256 round, uint256 index) external view returns (address) {
      return rounds[round].bidders[index].bidder;
  }

  /// @notice Get the bid prices for a bidder in the current round.
  /// @param round The round.
  /// @param index The index of the bidder.
  /// @return The bid prices for a bidder in the current round.
  function getRoundBidderBidPricesCount(uint256 round, uint256 index) external view returns (uint256) {
      return rounds[round].bidders[index].bidPrices.length;
  }

  /// @notice Get the bid price for a bidder in the current round.
  /// @param round The round.
  /// @param index The index of the bidder.
  /// @param positionIndex The index of the position.
  /// @return The bid price for a bidder in the current round.
  function getRoundBidderBidPrice(uint256 round, uint256 index, uint256 positionIndex) external view returns (uint256) {
      return rounds[round].bidders[index].bidPrices[positionIndex];
  }

  /// @notice Get the positions count in the current round.
  /// @param round The round.
  /// @return The positions count in the current round.
  function getRoundPositionsCount(uint256 round) external view returns (uint256) {
      return rounds[round].positions.length;
  }

  /// @notice Get the bid price of the position in the current round.
  /// @param round The round.
  /// @param index The index of the position.
  /// @return The bid price of the position in the current round.
  function getRoundPositionBidPrice(uint256 round, uint256 index) external view returns (uint256) {
      return rounds[round].positions[index].bidPrice;
  }

  /// @notice Get the rewarders count in the current round.
  /// @param round The round.
  /// @param index The index of the position.
  /// @return The rewarders count in the current round.
  function getRoundPositionsRewardersCount(uint256 round, uint256 index) external view returns (uint256) {
      return rounds[round].positions[index].rewarders.length;
  }

  /// @notice Get the highest value in the current round.
  /// @param round The round.
  /// @return The highest value in the current round.
  function getRoundHighestValue(uint256 round) external view returns (uint256) {
    uint256 highestValue = 0;
    if (rounds[round].positions.length == 0) {
      return 0;
    }
    for (uint256 i = 0; i < rounds[round].positions.length; i++) {
      if (rounds[round].positions[i].bidPrice > highestValue) {
        highestValue = rounds[round].positions[i].bidPrice;
      }
    }
    return highestValue;
  }

  /// @notice Get the lowest value in the current round.
  /// @param round The round.
  /// @return The lowest value in the current round.
  function getRoundLowestValue(uint256 round) external view returns (uint256) {
    uint256 lowestValue = type(uint256).max;
    if (rounds[round].positions.length == 0) {
      return 0;
    }
    for (uint256 i = 0; i < rounds[round].positions.length; i++) {
      if (rounds[round].positions[i].bidPrice < lowestValue) {
        lowestValue = rounds[round].positions[i].bidPrice;
      }
    }
    return lowestValue;
  }

  /// @notice Get the rewarder in the current round.
  /// @param round The round.
  /// @param index The index of the position.
  /// @param positionIndex The index of the position.
  /// @return The rewarder in the current round.
  function getRoundPositionsRewarder(uint256 round, uint256 index, uint256 positionIndex) external view returns (address) {
      return rounds[round].positions[index].rewarders[positionIndex];
  }

  /// @notice Get the next bid price for a bidder in the current round.
  /// @param round The round.
  /// @param bidder The address of the bidder.
  /// @return The next bid price for a bidder in the current round.
  function getRoundNextBidPrice(uint256 round, address bidder) external view returns (uint256) {
      return rounds[round].nextBidPrice[bidder];
  }

  function getActionCount(uint256 round) external view returns (uint256) {
    return rounds[round].actionCount;
  }

  /// @notice Sort the prices in descending order.
  /// @param _prices The array of prices to sort.
  /// @return The sorted array of prices.
  function sortPrices(uint256[] memory _prices) internal pure returns (uint256[] memory) {
    // Sort the prices in descending order.
    for (uint256 i = 0; i < _prices.length; i++) {
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
      // Check if the bidder has already bid with the same price.
      if (blindRound.bidInfos[msg.sender] != bytes32(0)) revert DoubleBlindBid();
      if (blindRound.bidInfosUsed[_bidInfo]) revert DoubleBlindBid();
      // Transfer entry fee from bidder to the contract.
      usdt.safeTransferFrom(msg.sender, address(this), entryFee);  // SafeERC20 will revert on failure

      blindRound.bidders.push(msg.sender);
      blindRound.bidInfos[msg.sender] = _bidInfo;
      blindRound.bidInfosUsed[_bidInfo] = true;

      raisedFundAtBlindRound += entryFee;

      // Emit event to signal bid entry.
      emit BlindBidEntered(currentRound, msg.sender, _bidInfo);
  }

  /// @notice End the blind round and start a new one.
  /// @param _blindBidPrices The array of bid prices in the blind round.
  function endBlindRound(uint256[] memory _blindBidPrices) public onlyBroker {
    // End the current round and start a new one.
    if (blindRound.ended) revert BlindRoundEnded();
    if(blindRound.bidders.length == 0) revert NoBidders();
    if(_blindBidPrices.length != blindRound.bidders.length) revert InvalidNumberOfBidPrices();
    // Check if the raised funds are less than the minimum required.
    if(raisedFundAtBlindRound < minRaisedFundsAtBlindRound) revert CannotEndBlindRound();

    bytes32 bidInfoWithPrice; // The bid info with price.
    
    blindRound.ended = true;

    // Iterate through the bidders in the blind round.
    for (uint256 i = 0; i < blindRound.bidders.length; i++) {
      bidInfoWithPrice = keccak256(abi.encodePacked(blindRound.bidders[i], _blindBidPrices[i]));
      if(blindRound.bidInfos[blindRound.bidders[i]] != bidInfoWithPrice) revert InvalidBidInfo(); // check if the bid info is valid
      
      Position storage newPosition = rounds[currentRound].positions.push(); // Add a new position to the current round.
      uint256 positionIndex = searchPosition(currentRound, _blindBidPrices[i]);
      if(positionIndex < rounds[currentRound].positions.length) {
        rounds[currentRound].positions[positionIndex].rewarders.push(blindRound.bidders[i]); // Add the bidder to the position.
      } else {
        newPosition.bidPrice = _blindBidPrices[i]; // Set the bid price of the new position.
        newPosition.rewarders.push(blindRound.bidders[i]); // Add the bidder to the position.
      }
      rounds[currentRound].nextBidPrice[blindRound.bidders[i]] = _blindBidPrices[i]; // Set the index of the new position.
    }

    emit NewRoundStarted(currentRound);
  }

  /// @notice Check if the bidder has already bid with the same price in the current round.
  /// @param _bidPrice The bid price.
  /// @param _bidder The address of the bidder.
  /// @return True if the bidder has already bid with the same price, false otherwise.
  function checkDoubleBid(uint256 _bidPrice, address _bidder) internal view returns (bool) {
    // Check if the bidder has already bid with the same price in the current round.
    uint256 bidderIndex = searchBidder(currentRound, _bidder);
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
  /// @param _round The round.
  /// @return The index of the position.  
  function searchPosition(uint256 _round, uint256 _bidPrice) internal view returns (uint256) {
    // Search for a position with the given bid price in the current round.
    uint256 i = 0;
    if(rounds[_round].positions.length == 0) {
      return 0;
    }

    for (i = 0; i < rounds[_round].positions.length; i++) {
      if (rounds[_round].positions[i].bidPrice == _bidPrice) {
        break;
      }
    }
    return i;
  }

  /// @notice Search for a bidder in the current round.
  /// @param _bidder The address of the bidder.
  /// @return The index of the bidder in the current round.
  function searchBidder(uint256 _round, address _bidder) internal view returns (uint256) {
    uint256 i = 0;
    if(rounds[_round].bidders.length == 0) {
      return 0;
    }

    for (i = 0; i < rounds[_round].bidders.length; i++) {
      if (rounds[_round].bidders[i].bidder == _bidder) {
        break;
      }
    }
    return i;
  }

  /// @notice Computes base^exp with fixed-point scaling.
  /// @param base The base in fixed-point (scaled by SCALE).
  /// @param exp The exponent.
  /// @return result The result in fixed-point (scaled by SCALE).
  function power(uint256 base, uint256 exp) internal pure returns (uint256 result) {
      result = GEOMETRIC_SCALE; // 1 in fixed-point
      for (uint256 i = 0; i < exp; i++) {
          // Multiply result * base, then divide by SCALE to maintain fixed-point precision.
          result = fullMulDiv(result, base, GEOMETRIC_SCALE);
      }
  }

  /// @notice Helper for fixed-point multiplication: computes (a * b) / scale.
  /// @dev Assumes that a * b does not overflow.
  function fullMulDiv(uint256 a, uint256 b, uint256 scale_) internal pure returns (uint256) {
      return (a * b) / scale_;
  }

  /// @notice Computes the nth root of A (in fixed-point with SCALE) using binary search.
  /// @param A The number in fixed-point.
  /// @param n The degree of the root.
  /// @return The nth root in fixed-point.
  function nthRoot(uint256 A, uint256 n) internal pure returns (uint256) {
      if (A == 0) return 0;
      // The root must be at least SCALE (i.e. 1.0 in fixed-point) and at most A.
      uint256 low = GEOMETRIC_SCALE;
      uint256 high = A;
      while (low < high) {
          uint256 mid = (low + high + 1) / 2;
          uint256 p = power(mid, n);
          if (p <= A) {
              low = mid;
          } else {
              high = mid - 1;
          }
      }
      return low;
  }

  /// @notice Computes the geometric mean of an array of positive numbers (uint256).
  /// @dev Uses normalization to avoid overflow: let a_min = min(xᵢ), and compute GM = a_min * (∏ (xᵢ / a_min))^(1/n).
  /// Each ratio is scaled by SCALE.
  /// @param values An array of positive uint256 numbers.
  /// @return The geometric mean as a uint256.
  function geometricMean(uint256[] memory values) public pure returns (uint256) {
      if (values.length == 0) revert InvalidNumberOfValues();
      uint256 n = values.length;

      // Find the minimum value a_min.
      uint256 aMin = values[0];
      if (aMin == 0) return 0;
      for (uint256 i = 1; i < n; i++) {
          if (values[i] == 0) return 0;
          if (values[i] < aMin) {
              aMin = values[i];
          }
      }

      // Compute the product of ratios: R = ∏ (xᵢ / a_min), computed in fixed-point.
      // We start with 1 in fixed point.
      uint256 productRatios = GEOMETRIC_SCALE;
      for (uint256 i = 0; i < n; i++) {
          // ratio_i = (values[i] * SCALE) / aMin.
          uint256 ratio = (values[i] * GEOMETRIC_SCALE) / aMin;
          productRatios = fullMulDiv(productRatios, ratio, GEOMETRIC_SCALE);
      }
      // Compute the nth root of the product (in fixed-point).
      uint256 root = nthRoot(productRatios, n);
      // Final geometric mean = aMin * root / GEOMETRIC_SCALE.
      return (aMin * root) / GEOMETRIC_SCALE;
  }

  /// @notice Computes the square root of a number (uint256).
  /// @dev Uses the Babylonian method to approximate the square root.
  /// @param x The number to compute the square root of.
  /// @return The square root as a uint256.
  function sqrt(uint256 x) internal pure returns (uint256) {
      if (x == 0) return 0;
      // The initial guess is the number itself.
      uint256 z = x;
      // The Babylonian method to approximate the square root.
      while (true) {
          uint256 y = (z + x / z) / 2;
          if (y >= z) return z;
          z = y;
      }
      return z;
  }

  /// @notice Get the target price for the current round.
  /// @return The target price.
  function getTargetPrice(uint256 _round) public view returns (uint256) {
    // Calculate the target price for the current round.
    uint256[] memory prices = new uint256[](rounds[_round].positions.length);
    uint256 targetStep = sqrt(rounds[_round].positions.length);
    
    if(targetStep == 0) {
      return 0;
    }

    // Iterate through the positions in the current round.
    for (uint256 i = 0; i < rounds[_round].positions.length; i++) {
      prices[i] = rounds[_round].positions[i].bidPrice;
    }
    prices = sortPrices(prices);      

    uint256 finalActionLength = prices.length / targetStep;
    if (prices.length % targetStep != 0) finalActionLength++;

    // Collect the prices as the step is targetStep
    uint256[] memory collectedPrices = new uint256[](finalActionLength);
    uint256 j = 0;
    for (uint256 i = 0; i < rounds[_round].positions.length; i += targetStep) {
        collectedPrices[j] = prices[i];
        j++;
    }

    return geometricMean(collectedPrices);
  }

  /// @notice Extract all bid prices for a bidder.
  /// @param index The index of the bidder.
  /// @return bidPrices The array of bid prices.
  function extractAllBidPrices(uint256 index) internal view returns (uint256[] memory) {
    uint256 totalBidPrices = 0;
    totalBidPrices = rounds[currentRound].bidders[index].bidPrices.length;
    uint256[] memory bidPrices = new uint256[](totalBidPrices + currentRound);
    for (uint256 k = 0; k < totalBidPrices; k++) {
      bidPrices[k] = rounds[currentRound].bidders[index].bidPrices[k];
    }

    for (uint256 i = 0; i < currentRound; i++) {
      bidPrices[totalBidPrices + i] = rounds[i].nextBidPrice[rounds[i].bidders[index].bidder];
    }

    return bidPrices;
  }

  /// @notice Get the next bid price for a bidder in a round.
  /// @param _bidder The address of the bidder.
  /// @param _round The round.
  /// @return The next bid price for a bidder in a round.
  function getRoundNextBidPrice(address _bidder, uint256 _round) public view returns (uint256) {
    return rounds[_round].nextBidPrice[_bidder];
  }

  /// @notice Get the next bid price for a bidder.
  /// @param _bidder The address of the bidder.
  /// @param _positionIndexes The array of position indexes.
  /// @return The next bid price for a bidder.
  function getNextPrice(address _bidder, uint256[] memory _positionIndexes) public view returns (uint256) {
    uint256 bidderIndex = searchBidder(currentRound, _bidder);
    uint256 totalBidPrices = bidderIndex < rounds[currentRound].bidders.length ? 
        rounds[currentRound].bidders[bidderIndex].bidPrices.length : 0;
    
    // Pre-allocate array with exact size needed
    uint256[] memory allPrices = new uint256[](totalBidPrices + currentRound + _positionIndexes.length);
    uint256 priceIndex = 0;

    // Add historical bid prices if bidder exists
    if (bidderIndex < rounds[currentRound].bidders.length) {
        for (uint256 k = 0; k < totalBidPrices; k++) {
            allPrices[priceIndex++] = rounds[currentRound].bidders[bidderIndex].bidPrices[k];
        }
    }

    // Add next bid prices from previous rounds
    if(currentRound > 0) {
      for (uint256 i = 0; i < currentRound; i++) {
          allPrices[priceIndex++] = rounds[i].nextBidPrice[_bidder];
      }
    }

    // Add current position prices
    for (uint256 i = 0; i < _positionIndexes.length; i++) {
      allPrices[priceIndex++] = rounds[currentRound].positions[_positionIndexes[i]].bidPrice;
    }

    return geometricMean(allPrices);
  }

  /// @notice Turn to the next round.
  function turnToNextRound() public {
    // End the current round and start a new one.
    if (rounds[currentRound].ended) revert RoundAlreadyEnded();
    if(winner != address(0)) revert AuctionAlreadyEnded();

    if(!blindRound.ended) {
      revert BlindRoundStep();
    }

    if(rounds[currentRound].bidders.length == 0) {
      revert NoBidders();
    }

    rounds[currentRound].ended = true;

    // Iterate through the bidders in the current round.
    for (uint256 i = 0; i < rounds[currentRound].bidders.length; i++) {
      // Get the bid prices for the geometric mean.
      uint256[] memory bidPricesForGeometricMean = extractAllBidPrices(i);

      uint256 newPrice = geometricMean(bidPricesForGeometricMean); // Calculate the geometric mean.

      uint256 positionIndex = searchPosition(currentRound + 1, newPrice); // Search for a position with the given bid price in the current round.

      if (positionIndex < rounds[currentRound + 1].positions.length) {
          rounds[currentRound + 1].positions[positionIndex].rewarders.push(rounds[currentRound].bidders[i].bidder);
          rounds[currentRound + 1].nextBidPrice[rounds[currentRound].bidders[i].bidder] = newPrice;
      } else {
          Position storage newPosition = rounds[currentRound + 1].positions.push();
          newPosition.bidPrice = newPrice;
          newPosition.rewarders.push(rounds[currentRound].bidders[i].bidder);
          rounds[currentRound + 1].nextBidPrice[rounds[currentRound].bidders[i].bidder] = newPrice;
      }
    }

    currentRound++;

    emit NewRoundStarted(currentRound);
  }
  
  /// @notice In a new round, bidders can select a position from a previous round.
  /// Each time a position is selected, the owner of that position earns a reward equal to the entry fee.
  function bidPosition(uint256 positionIndex) external {
    if (rounds[currentRound].ended) revert RoundEnded(); // Check if the current round has ended.
    if(!blindRound.ended) revert BlindRoundStep(); // Check if the blind round has ended.
    if(winner != address(0)) revert AuctionAlreadyEnded();
    if(usdt.balanceOf(msg.sender) < entryFee) revert InsufficientBalance(); // Check if the bidder has sufficient balance.
    // Check if the number of positions is less than the minimum required.
    if(rounds[currentRound].positions.length < MIN_POSITIONS) revert EndedAuction();
    usdt.safeTransferFrom(msg.sender, address(this), entryFee);  // SafeERC20 will revert on failure
    if (positionIndex >= rounds[currentRound].positions.length) revert InvalidPositionIndex();

    if (blindRound.bidInfos[msg.sender] == bytes32(0)) {
      revert MaliciousBidder();
    }

    uint256 bidIndex = 0;
    for (uint256 i = 0; i < currentRound; i++) {
      bidIndex = searchBidder(i, msg.sender);
      if (bidIndex >= rounds[i].bidders.length) {
        revert MaliciousBidder();
      }
    }

    if(rounds[currentRound].actionCount >= rounds[currentRound].positions.length) {
      revert OverflowBid();
    }

    uint256 _bidPrice = rounds[currentRound].positions[positionIndex].bidPrice;
    if (checkDoubleBid(_bidPrice, msg.sender)) revert DoubleBid(); // Check if the bidder has already bid with the same price.

    address[] memory rewarders = rounds[currentRound].positions[positionIndex].rewarders;
    uint256 rewardAmount = entryFee / rewarders.length;
    for (uint256 i = 0; i < rewarders.length; i++) {
      rewards[rewarders[i]] += rewardAmount;
      totalRewards += rewardAmount;
    }

    uint256 bidderIndex = searchBidder(currentRound, msg.sender);
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

    rounds[currentRound].actionCount++;

    emit BidPosition(currentRound, positionIndex, msg.sender, entryFee);
  }

  /// @notice In a new round, bidders can select a position from a previous round.
  /// Each time a position is selected, the owner of that position earns a reward equal to the entry fee.
  function bidPositions(uint256[] memory positionIndexes) external {
    if (rounds[currentRound].ended) revert RoundEnded(); // Check if the current round has ended.
    if(!blindRound.ended) revert BlindRoundStep(); // Check if the blind round has ended.
    if(winner != address(0)) revert AuctionAlreadyEnded();
    if(usdt.balanceOf(msg.sender) < entryFee * positionIndexes.length) revert InsufficientBalance(); // Check if the bidder has sufficient balance.

    if (blindRound.bidInfos[msg.sender] == bytes32(0)) {
      revert MaliciousBidder();
    }

    uint256 bidIndex = 0;
    for (uint256 i = 0; i < currentRound; i++) {
      bidIndex = searchBidder(i, msg.sender);
      if (bidIndex >= rounds[i].bidders.length) {
        revert MaliciousBidder();
      }
    }

    if(rounds[currentRound].actionCount >= rounds[currentRound].positions.length) {
      revert OverflowBid();
    }

    // Check if the number of positions is less than the minimum required.
    if(rounds[currentRound].positions.length < MIN_POSITIONS) revert EndedAuction();
    usdt.safeTransferFrom(msg.sender, address(this), entryFee * positionIndexes.length);  // SafeERC20 will revert on failure
    
    for (uint256 i = 0; i < positionIndexes.length; i++) {
      
      uint256 positionIndex = positionIndexes[i];
      if (positionIndex >= rounds[currentRound].positions.length) revert InvalidPositionIndex(); 

      uint256 _bidPrice = rounds[currentRound].positions[positionIndex].bidPrice;
      if (checkDoubleBid(_bidPrice, msg.sender)) revert DoubleBid(); // Check if the bidder has already bid with the same price.

      address[] memory rewarders = rounds[currentRound].positions[positionIndex].rewarders;
      uint256 rewardAmount = entryFee / rewarders.length;
      for (uint256 j = 0; j < rewarders.length; j++) {
        rewards[rewarders[j]] += rewardAmount;
        totalRewards += rewardAmount;
      }

      uint256 bidderIndex = searchBidder(currentRound, msg.sender);
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

      rounds[currentRound].actionCount++;

      emit BidPositions(currentRound, positionIndexes, msg.sender, entryFee);
    }
  }

  /// @notice End the auction.
  function endAuction() public {
    uint256 targetPrice; // The target price.
    uint256 minDeltaPrice = type(uint256).max; // Initialize to max value
    uint256 minDeltaPriceIndex; // The index of the position with the minimum delta price.
    uint256 deltaPrice; // The delta price.

    if(rounds[currentRound].ended) revert RoundAlreadyEnded();
    if(currentRound == 0) revert StillInBlindRound();
    if(winner != address(0)) revert AuctionAlreadyEnded();

    // Check if the number of positions is less than the minimum required.
    if((rounds[currentRound].positions.length > MIN_POSITIONS) && (msg.sender != broker)) {
      revert InvalidNumberOfPositions();
    }

    // Get the target price.
    targetPrice = getTargetPrice(currentRound);

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

  /// @notice Allows users to withdraw their accumulated rewards.
  /// @dev Only the broker can withdraw the rewards.
  function withdrawRewards() external {
      uint256 rewardAmount = rewards[msg.sender];
      if (rewardAmount == 0) revert NoRewards();
      rewards[msg.sender] = 0;
      usdt.safeTransfer(msg.sender, rewardAmount);  // SafeERC20 will revert on failure
      totalRewards -= rewardAmount;
      emit RewardWithdrawn(msg.sender, rewardAmount);
  }

  /// @notice Allows the broker to withdraw the NFT.
  /// @dev Only the broker can withdraw the NFT.
  function withdrawNFT() external {
    if (msg.sender != winner) revert NotWinner();
    if (nft.ownerOf(nftId) != address(this)) revert NoNFT();
    nft.transferFrom(address(this), msg.sender, nftId);  // SafeERC20 will revert on failure

    emit NFTWithdrawn(msg.sender);
  }

  /// @notice Allows the broker to withdraw the rewards.
  /// @dev Only the broker can withdraw the rewards.
  /// @param _amount The amount of rewards to withdraw.
  function withdrawRewards(uint256 _amount) external onlyBroker {
      usdt.safeTransfer(msg.sender, _amount);  // SafeERC20 will revert on failure

      emit RewardsWithdrawn(msg.sender, _amount);
  }

  /// @notice Implementation of IERC721Receiver
  function onERC721Received(
      address,  // operator
      address,  // from
      uint256,  // tokenId
      bytes calldata  // data
  ) external pure override returns (bytes4) {
      return IERC721Receiver.onERC721Received.selector;
  }
}
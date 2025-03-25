# Default target
all: test

# Test upgrade function
test:
	forge test

# Test endBlindRound function
test-endblind:
	forge test --match-path ./test/CharterAuction.t.sol -vvvv --match-test testEndBlindRound

test-bidposition:
	forge test --match-path ./test/CharterAuction.t.sol -vvvv --match-test testBidPositionInvalidIndex

test-withdrawrewards:
	forge test --match-path ./test/CharterAuction.t.sol -vvvv --match-test testWithdrawRewardsEmitsEvent

test-factory:
	forge test --match-path ./test/CharterFactory.t.sol -vvvv

test-factory-with-owner:
	forge test --match-path ./test/CharterFactory.t.sol -vvvv --match-test testFactoryWithOwner

deploy:
	forge script script/CharterFactory.s.sol:CharterFactoryScript --broadcast --rpc-url baseSepolia --slow --verify src/CharterFactory.sol --etherscan-api-key baseSepolia -vv

# You can also add other common commands
clean:
	forge clean

build:
	forge build
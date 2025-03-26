# Default target
all: test

# Test upgrade function
test:
	forge test

test-blindbid:
	forge test --match-path ./test/CharterAuction.t.sol -vvvv --match-test testEndBlindRoundInvalidBidInfo

test-endblind:
	forge test --match-path ./test/CharterAuction.t.sol -vvvv --match-test testEndBlindRound

test-bidposition:
	forge test --match-path ./test/CharterAuction.t.sol -vvvv --match-test testBidPositionInvalidIndex

test-withdrawrewards:
	forge test --match-path ./test/CharterAuction.t.sol -vvvv --match-test testWithdrawRewardsEmitsEvent

test-factory:
	forge test --match-path ./test/CharterFactory.t.sol

test-auction:
	forge test --match-path ./test/CharterAuction.t.sol

test-nft:
	forge test --match-path ./test/CharterNFT.t.sol

test-factory-with-owner:
	forge test --match-path ./test/CharterFactory.t.sol -vvvv --match-test testFactoryWithOwner

deploy:
	forge script script/CharterFactory.s.sol:CharterFactoryScript --broadcast --rpc-url baseSepolia --slow --verify src/CharterFactory.sol --etherscan-api-key baseSepolia -vv

verify-factory:
	@echo "Waiting 60 seconds for contract deployment to be indexed..."
	# @sleep 60
	forge verify-contract \
		--chain-id 84532 \
		--num-of-optimizations 200 \
		--compiler-version 0.8.25 \
		--constructor-args $$(cast abi-encode "constructor(address,address)" "0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359" "0x5f56eEBF7b6cC82750d41aC85376c9b2491e2F2e") \
		0x78d5BEF8f5488dfA247A41b0621213451B0dC07e \
		src/CharterFactory.sol:CharterFactory \
		--watch
		--retries 10 \
		# --delay 10

verify-nft:
	@echo "Waiting 60 seconds for contract deployment to be indexed..."
	# @sleep 60
	forge verify-contract \
    --chain-id 84532 \
    --num-of-optimizations 200 \
    --compiler-version 0.8.25 \
    --constructor-args $$(cast abi-encode "constructor(address,address,address)" "0x5f56eebf7b6cc82750d41ac85376c9b2491e2f2e" "0x78d5bef8f5488dfa247a41b0621213451b0dc07e" "0x5f56eebf7b6cc82750d41ac85376c9b2491e2f2e") \
    0xD93371D49cd51684f1aA4ea6AE8b3E9cbF388b3C \
    src/CharterNFT.sol:CharterNFT \
    --watch
		--retries 10 \
		# --delay 10

# You can also add other common commands
clean:
	forge clean

build:
	forge build
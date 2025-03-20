.PHONY: test-all test-endblind

# Default target
all: test-all

# Test upgrade function
test-all:
	forge test

# Test endBlindRound function
test-endblind:
	forge test --match-path ./test/CharterAuction.t.sol -vvvv --match-test testEndBlindRound

# You can also add other common commands
clean:
	forge clean

build:
	forge build

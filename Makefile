-include .env

.PHONY: all test clean deploy help install snapshot format anvil verify

DEFAULT_ANVIL_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

help:
	@echo "Usage:"
	@echo "  make deploy [ARGS=...]\n    example: make deploy ARGS=\"--network sepolia\""

all: clean remove install update build

# Clean the repo
clean  :; forge clean

# Remove modules
remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

install :; forge install openzeppelin/openzeppelin-contracts@v5.1.0 --no-commit && forge install smartcontractkit/chainlink-brownie-contracts@1.3.0 --no-commit && forge install uniswap-v3-core=Uniswap/v3-core --no-commit && forge install uniswap-v3-periphery=Uniswap/v3-periphery --no-commit && forge install balancer/scaffold-balancer-v3 --no-commit && forge install balancer/balancer-v3-monorepo --no-commit && forge install permit2=Uniswap/permit2 --no-commit

# Update Dependencies
update:; forge update

build:; forge build

test :; forge test 

snapshot :; forge snapshot

format :; forge fmt

anvil :; anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 2

NETWORK_ARGS := --rpc-url http://localhost:8545 --private-key $(DEFAULT_ANVIL_KEY) --broadcast

ifeq ($(findstring --network sepolia,$(ARGS)),--network sepolia)
	NETWORK_ARGS := --rpc-url $(SEPOLIA_RPC_URL) --private-key $(PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
endif

deployRegular:
	@forge script script/DeployRegularPresale.s.sol:DeployRegularPresale --via-ir $(NETWORK_ARGS)

deployERC20:
	@forge script script/DeployERC20Ownable.s.sol:DeployERC20Ownable --via-ir $(NETWORK_ARGS)

deployCPFactory:
	@forge script script/DeployConstantProductFactory.s.sol:DeployConstantProductFactory --via-ir $(NETWORK_ARGS)

deployBondingCurve:
	@forge script script/DeployBondingCurvePresale.s.sol:DeployBondingCurvePresale --optimize --optimizer-runs 50 --via-ir $(NETWORK_ARGS)

# cast send 0x8Bcb23452001B402f293CA17F3F18FEc11692358 "createPresale(uint256,uint256,uint256,uint8,string,string)" 10000000000000000000 1732981605 1732982905 0 sdf sdf  --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY
# cast call 0x8Bcb23452001B402f293CA17F3F18FEc11692358 "getBCPProject(uint256)" 1 --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY

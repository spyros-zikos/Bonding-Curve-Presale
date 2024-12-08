## Set-up
Create a .env file in the root directory with the following variables:

```
SEPOLIA_RPC_URL=https://...
PRIVATE_KEY=0x...
ETHERSCAN_API_KEY=...
FEE_COLLECTOR=0x...
PROJECT_CREATOR_ADDRESS=0x...
```
Notes  
1.The FEE_COLLECTOR is the address of the private key.  
2.The PROJECT_CREATOR_ADDRESS is used for forked testing and is the recepient address of the ERC20Ownable deployment script.

## Usage

### Build

```shell
$ make build
```

### Test

```shell
$ make test
```

### Deploy

```shell
$ make deployRegular ARGS="--network sepolia"
```

```shell
$ make deployBondingCurve ARGS="--network sepolia"
```

# Move Coin Pool

This is a single coin pool implemented with Move that allows you to borrow coins. At the same time users can supply their coins and get some revenue by providing liquidity.



## Single pool

[single_pool.move](./sources/single_pool.move) represents a general single-coin pool that satisfies the following characteristics:

1. Anyone can create a single coin pool of multiple coin types through `create_pool`
2. The single currency pool is hosted on the creator's account
3. The single currency pool represents root authority through `RootCapability`
4. The user recharges through the `supply` function and gets `WithdrawProof` as proof
5. Users can withdraw through the `withdraw` function, including through `RootCapability` and `WithdrawProof`
6. External programs can introduce `single_pool` and self-manage `RootCapability` and `WithdrawProof` for extension

# Omin pool

[omni_pool.move](./sources/omni_pool.move) represents the OminBTC cross-chain single currency pool, which has the following characteristics:

1. `omni_pool` is an extension based on `single_pool`
2. The owner of `omni_pool` is responsible for managing `RootCapability`, including root permission transfer and upgrade
3. The owner of `omni_pool` is responsible for managing the `whitelist`, and those in the whitelist can use `RootCapability` to withdraw
4. The user can initiate the `supply|withdraw|borrow|repay|cross` behavior, and the relayer is responsible for the response



## Development

### Compile

```shell
aptos move compile --named-addresses coin_pool=<deployer-address>
```

### Test

```shell
aptos move test
```

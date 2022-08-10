module CoinPool::Pool {
    use std::signer;
    use aptos_std::type_info;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin::{Self, Coin};

    const ENOT_ENOUGH_COIN: u64 = 1;
    const ENOT_EXIST_POOL: u64 = 2;
    const ENOT_OWNER: u64 = 3;
    const ENOT_RELAYER: u64 = 4;

    struct Pool has key {
        coin: Coin<AptosCoin>, 
    }

    /// deployer address
    fun pool_address(): address {
        type_info::account_address(&type_info::type_of<Pool>())
    }

    /// check relayer role
    fun check_relayer(relayer: &signer) {
        let relayer_addr = signer::address_of(relayer);
        assert!(pool_address() == relayer_addr, ENOT_RELAYER);
    }

    /// create pool at deployer address
    public entry fun initialize_pool(owner: &signer) {
        let addr = signer::address_of(owner);

        assert!(addr == pool_address(), ENOT_OWNER);
        if ( !exists<Pool>(addr) ) {
            let pool = Pool{
                coin: coin::zero<AptosCoin>(),
            };
            move_to(owner, pool);
        }
    }

    /// deposit aptos coins to pool
    public entry fun supply(user: &signer, amount: u64) acquires Pool {
        let addr = signer::address_of(user);
        assert!(coin::balance<AptosCoin>(addr) >= amount, ENOT_ENOUGH_COIN);

        let pool = borrow_global_mut<Pool>(pool_address());
        let coin = coin::withdraw<AptosCoin>(user, amount);
        coin::merge(&mut pool.coin, coin);
    }

    /// withdraw aptos coins from pool
    /// 
    /// call by relayer
    public entry fun withdraw(relayer: &signer, user: address, amount: u64) acquires Pool {
        check_relayer(relayer);

        let pool = borrow_global_mut<Pool>(pool_address());
        assert!(coin::value(&pool.coin) >= amount, ENOT_ENOUGH_COIN);

        coin::deposit(user, coin::extract(&mut pool.coin, amount));
    }

    /// borrow aptos coins to user
    /// 
    /// call by relayer
    public entry fun borrow(relayer: &signer, user: address, amount: u64) acquires Pool {
        check_relayer(relayer);

        let pool = borrow_global_mut<Pool>(pool_address());
        assert!(coin::value(&pool.coin) >= amount, ENOT_ENOUGH_COIN);

        coin::deposit(user, coin::extract(&mut pool.coin, amount));
    }

    /// repay debt
    public entry fun repay(user: &signer, amount: u64) acquires Pool {
        let addr = signer::address_of(user);
        assert!(coin::balance<AptosCoin>(addr) >= amount, ENOT_ENOUGH_COIN);

        let pool = borrow_global_mut<Pool>(pool_address());
        let coin = coin::withdraw<AptosCoin>(user, amount);
        coin::merge(&mut pool.coin, coin);
    }
}
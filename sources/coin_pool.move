module CoinPool::Pool {
    use std::signer;
    use std::vector;
    use aptos_std::type_info;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin::{Self, Coin};

    const ENOT_ENOUGH_COIN: u64 = 1;
    const ENOT_EXIST_POOL: u64 = 2;
    const ENOT_RELAYER_WHITELIST: u64 = 3;
    const ENOT_OWNER: u64 = 4;
    const ENOT_RELAYER: u64 = 5;
    const EALREADY_RELAYER: u64 = 6;

    struct Pool has key {
        coin: Coin<AptosCoin>, 
    }

    struct RelayerWhitelist has key, store {
        relayers: vector<address>,
    }

    /// deployer address
    fun pool_address(): address {
        type_info::account_address(&type_info::type_of<Pool>())
    }

    /// check owner
    fun check_owner(owner: &signer) {
        let owner_addr = signer::address_of(owner);
        assert!(pool_address() == owner_addr, ENOT_OWNER);
    }

    /// check relayer role
    fun check_relayer(user: &signer) acquires RelayerWhitelist{
        let addr = signer::address_of(user);
        let whitelist = borrow_global_mut<RelayerWhitelist>(pool_address());
        assert!(vector::contains(&mut whitelist.relayers, &addr), ENOT_RELAYER);
    }

    /// create pool and relayer whitelist at deployer address
    public entry fun initialize(owner: &signer) {
        check_owner(owner);
        let owner_addr = signer::address_of(owner);
        if ( !exists<Pool>(owner_addr) ) {
            let pool = Pool{
                coin: coin::zero<AptosCoin>(),
            };
            move_to(owner, pool);
        };

        if ( !exists<RelayerWhitelist>(owner_addr) ) {
            let whitelist = RelayerWhitelist{
                relayers: vector::empty()
            };
            move_to(owner, whitelist);
        }
    }

    /// add relayer 
    public entry fun add_relayer(owner: &signer, user: address) acquires RelayerWhitelist {
        check_owner(owner);
        let owner_addr = signer::address_of(owner);
        assert!(exists<RelayerWhitelist>(owner_addr), ENOT_RELAYER_WHITELIST);

        let whitelist = borrow_global_mut<RelayerWhitelist>(owner_addr);
        assert!(!vector::contains(&mut whitelist.relayers, &user), EALREADY_RELAYER);
        vector::push_back(&mut whitelist.relayers, user);
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
    public entry fun withdraw(relayer: &signer, user: address, amount: u64) acquires Pool, RelayerWhitelist {
        check_relayer(relayer);

        let pool = borrow_global_mut<Pool>(pool_address());
        assert!(coin::value(&pool.coin) >= amount, ENOT_ENOUGH_COIN);

        coin::deposit(user, coin::extract(&mut pool.coin, amount));
    }

    /// borrow aptos coins to user
    /// 
    /// call by relayer
    public entry fun borrow(relayer: &signer, user: address, amount: u64) acquires Pool, RelayerWhitelist {
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
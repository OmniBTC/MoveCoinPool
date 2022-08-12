module coin_pool::pool {
    use std::signer;
    use std::vector;
    use aptos_std::type_info;
    use aptos_std::event::{Self, EventHandle};
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::account::create_resource_account;

    /// Errors
    const ENOT_OWNER: u64 = 1;
    const ENOT_RELAYER: u64 = 2;
    const EDUPLICATE_WITHDRAW: u64 = 3;
    const EDUPLICATE_BORROW: u64 = 4;

    /// Constants
    const SOURCE_CHAIN_ID: u64 = 22;
    const REMOTE_CHAIN_ID: u64 = 1501;

    /// Resources
    /// There are no resources for users here, all the resources are in the pool.
    struct Pool<phantom CoinType> has key {
        coin: Coin<CoinType>,
        // authority management
        relayer: address,

        // event handler
        relayer_change_event: EventHandle<RelayerChangeEvent>,
        supply_nonce: u64,
        supply_event: EventHandle<SupplyEvent>,
        withdraw_nonce: u64,
        cached_withdraw: vector<u64>,
        withdraw_event: EventHandle<WithdrawEvent>,
        borrow_nonce: u64,
        cached_borrow: vector<u64>,
        borrow_event: EventHandle<BorrowEvent>,
        repay_nonce: u64,
        repay_event: EventHandle<RepayEvent>
    }

    /// Events
    struct RelayerChangeEvent has store, drop {
        old_relayer: address,
        new_relayer: address,
    } 
    
    struct SupplyEvent has store, drop {
        user: address,
        amount: u64,
        chain_id: u64,
        nonce: u64,
    }

    struct WithdrawEvent has store, drop {
        user: address,
        amount: u64,
        chain_id: u64,
        nonce: u64,
    }

    struct BorrowEvent has store, drop {
        user: address,
        amount: u64,
        chain_id: u64,
        nonce: u64,
    }

    struct RepayEvent has store, drop {
        user: address,
        amount: u64,
        chain_id: u64,
        nonce: u64,
    }

    struct PoolAccount<phantom CoinType> has key {
        pool_address: address,
    }

    /// Pool resource address
    fun pool_address<CoinType>(): address {
        type_info::account_address(&type_info::type_of<Pool<CoinType>>())
    }

    /// Check relayer role
    public fun check_relayer<CoinType>(user: &signer) acquires Pool {
        let addr = signer::address_of(user);
        let pool = borrow_global_mut<Pool<CoinType>>(pool_address<CoinType>());
        assert!(pool.relayer == addr, ENOT_RELAYER);
    }

    /// Create pool and relayer whitelist at deployer address
    public entry fun create_pool<CoinType>(creator: &signer, seed: vector<u8>) {
    	let (pool_signer, _) = create_resource_account(creator, seed);
        let pool = Pool<CoinType>{
            coin: coin::zero<CoinType>(),
            relayer: signer::address_of(creator),
            relayer_change_event: event::new_event_handle<RelayerChangeEvent>(&pool_signer),
            supply_nonce: 0,
            supply_event: event::new_event_handle<SupplyEvent>(&pool_signer),
            withdraw_nonce: 0,
            cached_withdraw: vector::empty(),
            withdraw_event: event::new_event_handle<WithdrawEvent>(&pool_signer),
            borrow_nonce: 0,
            cached_borrow: vector::empty(),
            borrow_event: event::new_event_handle<BorrowEvent>(&pool_signer),
            repay_nonce: 0,
            repay_event: event::new_event_handle<RepayEvent>(&pool_signer)
        };
        move_to(&pool_signer, pool);
        let pool_accout = PoolAccount<CoinType> { pool_address: signer::address_of(&pool_signer) };
        move_to(creator, pool_accout)
    }

    /// Set relayer 
    public entry fun set_relayer<CoinType>(creator: &signer, relayer: address) acquires Pool, PoolAccount {
        let creator_address = signer::address_of(creator);
        let pool_account = borrow_global<PoolAccount<CoinType>>(creator_address);
        let pool = borrow_global_mut<Pool<CoinType>>(pool_account.pool_address);
        
        event::emit_event<RelayerChangeEvent>(&mut pool.relayer_change_event, RelayerChangeEvent{
            old_relayer: pool.relayer,
            new_relayer: relayer
        });
        pool.relayer = relayer;
    }

    /// Deposit aptos coins to pool
    public entry fun supply<CoinType>(user: &signer, amount: u64) acquires Pool {
        let addr = signer::address_of(user);

        let pool = borrow_global_mut<Pool<CoinType>>(pool_address<CoinType>());

        event::emit_event<SupplyEvent>(&mut pool.supply_event, SupplyEvent{
            user: addr,
            amount: amount,
            chain_id: REMOTE_CHAIN_ID,
            nonce: pool.supply_nonce,
        });
        pool.supply_nonce = pool.supply_nonce + 1;

        let coin = coin::withdraw<CoinType>(user, amount);
        coin::merge(&mut pool.coin, coin);
    }

    /// Withdraw aptos coins from pool
    /// 
    /// only for relayer
    public entry fun withdraw<CoinType>(relayer: &signer, user: address, amount: u64, nonce: u64) acquires Pool {
        check_relayer<CoinType>(relayer);

        let pool = borrow_global_mut<Pool<CoinType>>(pool_address<CoinType>());
        
        if (nonce >= pool.withdraw_nonce) {
            let withdraw_nonce = pool.withdraw_nonce;
            while (nonce != withdraw_nonce) {
                vector::push_back(&mut pool.cached_withdraw, withdraw_nonce);
                withdraw_nonce = withdraw_nonce + 1;
            };
            pool.withdraw_nonce = nonce + 1;
        } else {
            assert!(vector::contains(&mut pool.cached_withdraw, &nonce), EDUPLICATE_WITHDRAW);
            let (_, index) = vector::index_of(&mut pool.cached_withdraw, &nonce);
            vector::remove(&mut pool.cached_withdraw, index);
        };

        event::emit_event<WithdrawEvent>(&mut pool.withdraw_event, WithdrawEvent{
            user: user,
            amount: amount,
            chain_id: SOURCE_CHAIN_ID,
            nonce: nonce,
        });
        coin::deposit(user, coin::extract(&mut pool.coin, amount));
    }

    /// Borrow aptos coins to user
    /// 
    /// only for relayer
    public entry fun borrow<CoinType>(relayer: &signer, user: address, amount: u64, nonce: u64) acquires Pool {
        check_relayer<CoinType>(relayer);

        let pool = borrow_global_mut<Pool<CoinType>>(pool_address<CoinType>());

        if (nonce >= pool.borrow_nonce) {
            let borrow_nonce = pool.borrow_nonce;
            while (nonce != borrow_nonce) {
                vector::push_back(&mut pool.cached_borrow, borrow_nonce);
                borrow_nonce = borrow_nonce + 1;
            };
            pool.borrow_nonce = nonce + 1;
        } else {
            assert!(vector::contains(&mut pool.cached_borrow, &nonce), EDUPLICATE_BORROW);
            let (_, index) = vector::index_of(&mut pool.cached_borrow, &nonce);
            vector::remove(&mut pool.cached_borrow, index);
        };

        event::emit_event<BorrowEvent>(&mut pool.borrow_event, BorrowEvent{
            user: user,
            amount: amount,
            chain_id: SOURCE_CHAIN_ID,
            nonce: nonce,
        });

        coin::deposit(user, coin::extract(&mut pool.coin, amount));
    }

    /// Repay debt
    public entry fun repay<CoinType>(user: &signer, amount: u64) acquires Pool {
        let addr = signer::address_of(user);

        let pool = borrow_global_mut<Pool<CoinType>>(pool_address<CoinType>());

        event::emit_event<RepayEvent>(&mut pool.repay_event, RepayEvent{
            user: addr,
            amount: amount,
            chain_id: REMOTE_CHAIN_ID,
            nonce: pool.repay_nonce,
        });
        pool.repay_nonce = pool.repay_nonce + 1;

        let coin = coin::withdraw<CoinType>(user, amount);
        coin::merge(&mut pool.coin, coin);
    }

    #[test_only]
    public fun pool_coins<CoinType>(): u64 acquires Pool {
        let token_pool = borrow_global_mut<Pool<CoinType>>(pool_address<CoinType>());
        coin::value(&token_pool.coin)
    }
}
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
    struct Pool<phantom CoinType> has key {
        coin: Coin<CoinType>,
    }

    struct Relayer has key {
        relayer_address: address,
        relayer_change_event: EventHandle<RelayerChangeEvent>
    }

    struct RelayerEventHandle has key{
        withdraw_nonce: u64,
        cached_withdraw: vector<u64>,
        withdraw_event: EventHandle<WithdrawEvent>,
        borrow_nonce: u64,
        cached_borrow: vector<u64>,
        borrow_event: EventHandle<BorrowEvent>
    }

    struct UserEventHandle has key {
        supply_nonce: u64,
        supply_event: EventHandle<SupplyEvent>,
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

    /// Deployer address
    fun deployer_address(): address {
        type_info::account_address(&type_info::type_of<Relayer>())
    }

    /// Pool resource address
    fun pool_address<CoinType>(): address acquires PoolAccount {
        let deployer_address = deployer_address();
        let pool_account = borrow_global<PoolAccount<CoinType>>(deployer_address);
        pool_account.pool_address
    }

    /// Check relayer role
    public fun check_relayer<CoinType>(user: &signer) acquires Relayer {
        let addr = signer::address_of(user);
        let relayer = borrow_global_mut<Relayer>(deployer_address());
        assert!(relayer.relayer_address == addr, ENOT_RELAYER);
    }

    /// Init module
    public entry fun init_module(deployer: &signer) {
        let addr = signer::address_of(deployer);
        let relayer = Relayer {
            relayer_address: addr,
            relayer_change_event: event::new_event_handle<RelayerChangeEvent>(deployer)
        };
        move_to(deployer, relayer);
        let relayer_event_handle = RelayerEventHandle {
            withdraw_nonce: 0,
            cached_withdraw: vector::empty(),
            withdraw_event: event::new_event_handle<WithdrawEvent>(deployer),
            borrow_nonce: 0,
            cached_borrow: vector::empty(),
            borrow_event: event::new_event_handle<BorrowEvent>(deployer)
        };
        move_to(deployer, relayer_event_handle);
        let user_event_handle = UserEventHandle {
            supply_nonce: 0,
            supply_event: event::new_event_handle<SupplyEvent>(deployer),
            repay_nonce: 0,
            repay_event: event::new_event_handle<RepayEvent>(deployer)
        };
        move_to(deployer, user_event_handle);

    }

    /// Create pool
    public entry fun create_pool<CoinType>(creator: &signer, seed: vector<u8>) {
        assert!(signer::address_of(creator) == deployer_address(), ENOT_OWNER);
    	let (pool_signer, _) = create_resource_account(creator, seed);
        let pool = Pool<CoinType>{
            coin: coin::zero<CoinType>(),
        };
        move_to(&pool_signer, pool);
        let pool_accout = PoolAccount<CoinType> { pool_address: signer::address_of(&pool_signer) };
        move_to(creator, pool_accout)
    }

    /// Set relayer 
    public entry fun set_relayer<CoinType>(deployer: &signer, relayer_address: address) acquires Relayer {
        let relayer = borrow_global_mut<Relayer>(signer::address_of(deployer));
        
        event::emit_event<RelayerChangeEvent>(&mut relayer.relayer_change_event, RelayerChangeEvent{
            old_relayer: relayer.relayer_address,
            new_relayer: relayer_address
        });
        relayer.relayer_address = relayer_address;
    }

    /// Deposit aptos coins to pool
    public entry fun supply<CoinType>(user: &signer, amount: u64) acquires Pool, PoolAccount, UserEventHandle {
        let addr = signer::address_of(user);

        let pool = borrow_global_mut<Pool<CoinType>>(pool_address<CoinType>());

        let event_handle = borrow_global_mut<UserEventHandle>(deployer_address());
        event::emit_event<SupplyEvent>(&mut event_handle.supply_event, SupplyEvent{
            user: addr,
            amount: amount,
            chain_id: REMOTE_CHAIN_ID,
            nonce: event_handle.supply_nonce,
        });
        event_handle.supply_nonce = event_handle.supply_nonce + 1;

        let coin = coin::withdraw<CoinType>(user, amount);
        coin::merge(&mut pool.coin, coin);
    }

    /// Withdraw aptos coins from pool
    /// 
    /// only for relayer
    public entry fun withdraw<CoinType>(relayer: &signer, user: address, amount: u64, nonce: u64) acquires Pool, PoolAccount, RelayerEventHandle, Relayer {
        check_relayer<CoinType>(relayer);

        let pool = borrow_global_mut<Pool<CoinType>>(pool_address<CoinType>());

        let event_handle = borrow_global_mut<RelayerEventHandle>(deployer_address());
        if (nonce >= event_handle.withdraw_nonce) {
            let withdraw_nonce = event_handle.withdraw_nonce;
            while (nonce != withdraw_nonce) {
                vector::push_back(&mut event_handle.cached_withdraw, withdraw_nonce);
                withdraw_nonce = withdraw_nonce + 1;
            };
            event_handle.withdraw_nonce = nonce + 1;
        } else {
            assert!(vector::contains(&mut event_handle.cached_withdraw, &nonce), EDUPLICATE_WITHDRAW);
            let (_, index) = vector::index_of(&mut event_handle.cached_withdraw, &nonce);
            vector::remove(&mut event_handle.cached_withdraw, index);
        };

        event::emit_event<WithdrawEvent>(&mut event_handle.withdraw_event, WithdrawEvent{
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
    public entry fun borrow<CoinType>(relayer: &signer, user: address, amount: u64, nonce: u64) acquires Pool, PoolAccount, Relayer, RelayerEventHandle {
        check_relayer<CoinType>(relayer);

        let pool = borrow_global_mut<Pool<CoinType>>(pool_address<CoinType>());

        let event_handle = borrow_global_mut<RelayerEventHandle>(deployer_address());
        if (nonce >= event_handle.borrow_nonce) {
            let borrow_nonce = event_handle.borrow_nonce;
            while (nonce != borrow_nonce) {
                vector::push_back(&mut event_handle.cached_borrow, borrow_nonce);
                borrow_nonce = borrow_nonce + 1;
            };
            event_handle.borrow_nonce = nonce + 1;
        } else {
            assert!(vector::contains(&mut event_handle.cached_borrow, &nonce), EDUPLICATE_BORROW);
            let (_, index) = vector::index_of(&mut event_handle.cached_borrow, &nonce);
            vector::remove(&mut event_handle.cached_borrow, index);
        };

        event::emit_event<BorrowEvent>(&mut event_handle.borrow_event, BorrowEvent{
            user: user,
            amount: amount,
            chain_id: SOURCE_CHAIN_ID,
            nonce: nonce,
        });

        coin::deposit(user, coin::extract(&mut pool.coin, amount));
    }

    /// Repay debt
    public entry fun repay<CoinType>(user: &signer, amount: u64) acquires Pool, PoolAccount, UserEventHandle {
        let addr = signer::address_of(user);

        let pool = borrow_global_mut<Pool<CoinType>>(pool_address<CoinType>());

        let event_handle = borrow_global_mut<UserEventHandle>(deployer_address());
        event::emit_event<RepayEvent>(&mut event_handle.repay_event, RepayEvent{
            user: addr,
            amount: amount,
            chain_id: REMOTE_CHAIN_ID,
            nonce: event_handle.repay_nonce,
        });
        event_handle.repay_nonce = event_handle.repay_nonce + 1;

        let coin = coin::withdraw<CoinType>(user, amount);
        coin::merge(&mut pool.coin, coin);
    }

    #[test_only]
    public fun pool_coins<CoinType>(): u64 acquires Pool, PoolAccount {
        let token_pool = borrow_global_mut<Pool<CoinType>>(pool_address<CoinType>());
        coin::value(&token_pool.coin)
    }
}
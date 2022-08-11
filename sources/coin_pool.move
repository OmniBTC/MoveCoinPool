module CoinPool::Pool {
    use std::signer;
    use std::vector;
    use aptos_std::type_info;
    use aptos_std::event::{Self, EventHandle};
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::coin::{Self, Coin};

    /// Errors
    const ENOT_ENOUGH_COIN: u64 = 1;
    const ENOT_EXIST_POOL: u64 = 2;
    const ENOT_RELAYER_WHITELIST: u64 = 3;
    const ENOT_OWNER: u64 = 4;
    const ENOT_RELAYER: u64 = 5;
    const EALREADY_RELAYER: u64 = 6;

    /// Constants
    const CHAIN_ID: u64 = 22;

    /// Storage
    struct Pool has key {
        coin: Coin<AptosCoin>, 
    }

    struct RelayerWhitelist has key, store {
        relayers: vector<address>,
    }

    /// Events
    struct SupplyEventHandle has key {
        counter: u64,
        supply_event: EventHandle<SupplyEvent>
    }

    struct SupplyEvent has store, drop {
        user: address,
        amount: u64,
        chain_id: u64,
        nonce: u64,
    }

    struct WithdrawEventHandle has key {
        counter: u64,
        withdraw_event: EventHandle<WithdrawEvent>
    }

    struct WithdrawEvent has store, drop {
        user: address,
        amount: u64,
        chain_id: u64,
        nonce: u64,
    }

    struct BorrowEventHandle has key {
        counter: u64,
        borrow_event: EventHandle<BorrowEvent>
    }

    struct BorrowEvent has store, drop {
        user: address,
        amount: u64,
        chain_id: u64,
        nonce: u64,
    }

    struct RepayEventHandle has key {
        counter: u64,
        repay_event: EventHandle<RepayEvent>
    }

    struct RepayEvent has store, drop {
        user: address,
        amount: u64,
        chain_id: u64,
        nonce: u64,
    }

    /// Deployer address
    fun pool_address(): address {
        type_info::account_address(&type_info::type_of<Pool>())
    }

    /// Check owner
    fun check_owner(owner: &signer) {
        let owner_addr = signer::address_of(owner);
        assert!(pool_address() == owner_addr, ENOT_OWNER);
    }

    /// Check relayer role
    fun check_relayer(user: &signer) acquires RelayerWhitelist{
        let addr = signer::address_of(user);
        let whitelist = borrow_global_mut<RelayerWhitelist>(pool_address());
        assert!(vector::contains(&mut whitelist.relayers, &addr), ENOT_RELAYER);
    }

    /// Create pool and relayer whitelist at deployer address
    public entry fun initialize(owner: &signer) {
        check_owner(owner);
        let pool = Pool{
            coin: coin::zero<AptosCoin>(),
        };
        move_to(owner, pool);

        let whitelist = RelayerWhitelist{
            relayers: vector::empty()
        };
        move_to(owner, whitelist);

        move_to(owner, SupplyEventHandle {
            counter: 0,
            supply_event: event::new_event_handle<SupplyEvent>(owner)
        });
        move_to(owner, WithdrawEventHandle {
            counter: 0,
            withdraw_event: event::new_event_handle<WithdrawEvent>(owner)
        });
        move_to(owner, BorrowEventHandle {
            counter: 0,
            borrow_event: event::new_event_handle<BorrowEvent>(owner)
        });
        move_to(owner, RepayEventHandle {
            counter: 0,
            repay_event: event::new_event_handle<RepayEvent>(owner)
        });
    }

    /// Add relayer 
    public entry fun add_relayer(owner: &signer, user: address) acquires RelayerWhitelist {
        check_owner(owner);
        let owner_addr = signer::address_of(owner);
        assert!(exists<RelayerWhitelist>(owner_addr), ENOT_RELAYER_WHITELIST);

        let whitelist = borrow_global_mut<RelayerWhitelist>(owner_addr);
        assert!(!vector::contains(&mut whitelist.relayers, &user), EALREADY_RELAYER);
        vector::push_back(&mut whitelist.relayers, user);
    }

    /// Deposit aptos coins to pool
    public entry fun supply(user: &signer, amount: u64) acquires Pool, SupplyEventHandle {
        let addr = signer::address_of(user);
        assert!(coin::balance<AptosCoin>(addr) >= amount, ENOT_ENOUGH_COIN);

        let pool = borrow_global_mut<Pool>(pool_address());
        let coin = coin::withdraw<AptosCoin>(user, amount);
        coin::merge(&mut pool.coin, coin);
        
        let event_handle = borrow_global_mut<SupplyEventHandle>(pool_address());
        event::emit_event<SupplyEvent>(&mut event_handle.supply_event, SupplyEvent{
            user: addr,
            amount: amount,
            chain_id: CHAIN_ID,
            nonce: event_handle.counter,
        });
        event_handle.counter = event_handle.counter + 1;
    }

    /// Withdraw aptos coins from pool
    /// 
    /// only for relayer
    public entry fun withdraw(relayer: &signer, user: address, amount: u64) acquires Pool, RelayerWhitelist, WithdrawEventHandle {
        check_relayer(relayer);

        let pool = borrow_global_mut<Pool>(pool_address());
        assert!(coin::value(&pool.coin) >= amount, ENOT_ENOUGH_COIN);

        coin::deposit(user, coin::extract(&mut pool.coin, amount));

        let event_handle = borrow_global_mut<WithdrawEventHandle>(pool_address());
        event::emit_event<WithdrawEvent>(&mut event_handle.withdraw_event, WithdrawEvent{
            user: user,
            amount: amount,
            chain_id: CHAIN_ID,
            nonce: event_handle.counter,
        });
        event_handle.counter = event_handle.counter + 1;
    }

    /// Borrow aptos coins to user
    /// 
    /// only for relayer
    public entry fun borrow(relayer: &signer, user: address, amount: u64) acquires Pool, RelayerWhitelist, BorrowEventHandle {
        check_relayer(relayer);

        let pool = borrow_global_mut<Pool>(pool_address());
        assert!(coin::value(&pool.coin) >= amount, ENOT_ENOUGH_COIN);

        coin::deposit(user, coin::extract(&mut pool.coin, amount));

        let event_handle = borrow_global_mut<BorrowEventHandle>(pool_address());
        event::emit_event<BorrowEvent>(&mut event_handle.borrow_event, BorrowEvent{
            user: user,
            amount: amount,
            chain_id: CHAIN_ID,
            nonce: event_handle.counter,
        });
        event_handle.counter = event_handle.counter + 1;
    }

    /// Repay debt
    public entry fun repay(user: &signer, amount: u64) acquires Pool, RepayEventHandle {
        let addr = signer::address_of(user);
        assert!(coin::balance<AptosCoin>(addr) >= amount, ENOT_ENOUGH_COIN);

        let pool = borrow_global_mut<Pool>(pool_address());
        let coin = coin::withdraw<AptosCoin>(user, amount);
        coin::merge(&mut pool.coin, coin);

        let event_handle = borrow_global_mut<RepayEventHandle>(pool_address());
        event::emit_event<RepayEvent>(&mut event_handle.repay_event, RepayEvent{
            user: addr,
            amount: amount,
            chain_id: CHAIN_ID,
            nonce: event_handle.counter,
        });
        event_handle.counter = event_handle.counter + 1;
    }
}
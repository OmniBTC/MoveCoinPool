module coin_pool::singel_pool {
    use aptos_framework::coin::{Coin, Self};
    use std::signer;
    use std::option::{Option, Self};
    use std::vector;
    use aptos_std::type_info::TypeInfo;
    use aptos_std::event::EventHandle;
    use aptos_std::type_info;
    use aptos_std::event;
    use aptos_framework::block::get_current_block_height;

    //
    // Errors.
    //

    /// When pool recorder has been initilized.
    const POOL_RECORDER_INITILIZED: u64 = 0;

    /// When pool recorder hasn't initilized.
    const POOL_RECORDER_NOT_INITILIZED: u64 = 1;

    /// When `Pool` is already created.
    const POOL_ALREADY_CREATED: u64 = 2;

    /// When `Pool` is not exist.
    const POOL_NOT_EXIST: u64 = 3;

    /// Not the same pool.
    const POOL_NOT_SAME: u64 = 4;

    /// When root is not exist.
    const POOL_ROOT_NOT_EXIST: u64 = 5;

    /// When `Pool` coin amount is not enough.
    const POOL_AMOUNT_NOT_ENOUGH: u64 = 6;

    /// When represent amount of proof is not enough.
    const PROOF_AMOUNT_NOT_ENOUGH: u64 = 7;

    /// When proof is not exist.
    const PROOF_NOT_EXIST: u64 = 8;

    /// Non-zero proof destruction.
    const DESTRUCTION_OF_NONZERO_PROOF: u64 = 9;

    /// Not deployed address
    const NOT_DEPLOYED_ADDRESS: u64 = 10;


    /// Single coin pool. Anyone can create a single coin pool.
    /// Use `RootCapability` to manage root permissions.
    /// Use `WithdrawProof` to manage the number of coins that can be withdrawn,
    struct Pool<phantom CoinType> has key {
        /// Managed coin.
        coin: Coin<CoinType>,
        /// Pool address.
        pool_address: address
    }

    /// Used to record the relevant information of the pool,
    /// where `(pool_type, pool_address)` can uniquely identify a single coin pool.
    struct PoolInfo has store {
        pool_type: TypeInfo,
        pool_address: address,
        block_height: u64
    }

    /// Create pool event.
    struct CreatePoolEvent has drop, store {
        pool_type: TypeInfo,
        pool_address: address,
    }

    /// Record all pools that have been created.
    struct PoolRecorder has key {
        pools: vector<PoolInfo>,
        create_pool_events: EventHandle<CreatePoolEvent>
    }


    /// Root privileges. The owner of RootCapability has root privileges to the pool represented by pool_address.
    /// You can manage RootCapability yourself in an external program,
    /// or you can manage it directly with RootCapabilityCollection
    struct RootCapability<phantom CoinType> has store {
        pool_address: address
    }

    /// root privilege collection.
    struct RootCapabilityCollection<phantom CoinType> has key, store {
        root_indexs: vector<address>,
        roots: vector<RootCapability<CoinType>>
    }

    /// Represents the number of coin that can be withdrawn.
    /// The owner of WithdrawProof can withdraw the amount of coins from the pool represented by pool_address.
    /// You can manage WithdrawProof yourself in an external program,
    /// or you can manage it directly with WithdrawProofCollection
    struct WithdrawProof<phantom CoinType> has store {
        pool_address: address,
        amount: u64
    }

    /// Proof collection
    struct WithdrawProofCollection<phantom CoinType> has key, store {
        proof_indexs: vector<address>,
        proofs: vector<WithdrawProof<CoinType>>
    }

    public fun deployed_address(): address {
        @coin_pool
    }

    public fun get_pool_address_by_root<CoinType>(root: &RootCapability<CoinType>): address {
        root.pool_address
    }

    /// Returns `true` if pool recoreder has been initialized.
    public entry fun pool_recorder_initialized(): bool {
        let deployed_addr = deployed_address();
        exists<PoolRecorder>(deployed_addr)
    }

    /// Returns `true` if `pool` has been created.
    public fun is_pool_created<CoinType>(pool_addess: address): bool {
        exists<Pool<CoinType>>(pool_addess)
    }

    /// Add root into collection. Note that it does not do root existence checks.
    public fun add_root_collection<CoinType>(account: &signer, root: RootCapability<CoinType>) acquires RootCapabilityCollection {
        let account_addr = signer::address_of(account);
        if (!exists<RootCapabilityCollection<CoinType>>(account_addr)) {
            move_to(account, RootCapabilityCollection<CoinType> {
                root_indexs: vector::empty(),
                roots: vector::empty()
            })
        };
        let root_collection = borrow_global_mut<RootCapabilityCollection<CoinType>>(account_addr);
        vector::push_back(&mut root_collection.root_indexs, root.pool_address);
        vector::push_back(&mut root_collection.roots, root);
    }

    /// Add proof into collection. Note that it does not do proof existence checks.
    public fun add_proof_collection<CoinType>(account: &signer, proof: WithdrawProof<CoinType>)acquires WithdrawProofCollection {
        let account_addr = signer::address_of(account);
        if (!exists<WithdrawProofCollection<CoinType>>(account_addr)) {
            move_to(account, WithdrawProofCollection<CoinType> {
                proof_indexs: vector::empty(),
                proofs: vector::empty()
            })
        };
        let proof_collection = borrow_global_mut<WithdrawProofCollection<CoinType>>(account_addr);
        vector::push_back(&mut proof_collection.proof_indexs, proof.pool_address);
        vector::push_back(&mut proof_collection.proofs, proof);
    }

    /// Find root in collection.
    fun find_root_collection<CoinType>(account: address, pool_address: address): Option<RootCapability<CoinType>> acquires RootCapabilityCollection {
        if (!exists<RootCapabilityCollection<CoinType>>(account)) {
            option::none()
        }else {
            let root_collection = borrow_global_mut<RootCapabilityCollection<CoinType>>(account);
            let (flag, index) = vector::index_of(&mut root_collection.root_indexs, &pool_address);
            if (flag) {
                option::some(vector::swap_remove(&mut root_collection.roots, index))
            } else {
                option::none()
            }
        }
    }

    /// Find proof in collection.
    fun find_proof_collection<CoinType>(account: address, pool_address: address): Option<WithdrawProof<CoinType>> acquires WithdrawProofCollection {
        if (!exists<WithdrawProofCollection<CoinType>>(account)) {
            option::none()
        }else {
            let proof_collection = borrow_global_mut<WithdrawProofCollection<CoinType>>(account);
            let (flag, index) = vector::index_of(&mut proof_collection.proof_indexs, &pool_address);
            if (flag) {
                option::some(vector::swap_remove(&mut proof_collection.proofs, index))
            } else {
                option::none()
            }
        }
    }

    /// Initialize the pool recorder
    public entry fun initialize(account: &signer) {
        assert!(deployed_address() == signer::address_of(account), NOT_DEPLOYED_ADDRESS);
        assert!(!pool_recorder_initialized(), POOL_RECORDER_INITILIZED);
        let recorder = PoolRecorder {
            pools: vector::empty(),
            create_pool_events: event::new_event_handle<CreatePoolEvent>(account)
        };
        move_to(account, recorder);
    }

    fun add_pool_recorder<CoinType>(pool_address: address) acquires PoolRecorder {
        let pool_recorder = borrow_global_mut<PoolRecorder>(deployed_address());
        let pool_type = type_info::type_of<Pool<CoinType>>();
        vector::push_back(&mut pool_recorder.pools, PoolInfo {
            pool_type,
            pool_address,
            block_height: get_current_block_height()
        });
        event::emit_event<CreatePoolEvent>(&mut pool_recorder.create_pool_events, CreatePoolEvent {
            pool_type,
            pool_address
        })
    }

    /// Creat pool.
    fun create_pool_internal<CoinType>(creater: &signer): RootCapability<CoinType> acquires PoolRecorder {
        assert!(pool_recorder_initialized(), POOL_RECORDER_NOT_INITILIZED);
        let creater_addr = signer::address_of(creater);
        assert!(!is_pool_created<CoinType>(creater_addr), POOL_ALREADY_CREATED);

        let pool = Pool<CoinType> {
            coin: coin::zero<CoinType>(),
            pool_address: creater_addr
        };
        move_to(creater, pool);

        add_pool_recorder<CoinType>(creater_addr);

        RootCapability<CoinType> {
            pool_address: creater_addr
        }
    }

    /// Create a token pool and return the root permission to external program management.
    public fun create_pool_program<CoinType>(creater: &signer): RootCapability<CoinType> acquires PoolRecorder {
        create_pool_internal<CoinType>(creater)
    }

    /// Create a pool of tokens and store root permissions directly in the creator's address.
    public entry fun create_pool<CoinType>(creater: &signer) acquires RootCapabilityCollection, PoolRecorder {
        add_root_collection(creater, create_pool_internal<CoinType>(creater));
    }

    /// Extract root privileges from owner.
    public fun extract_root<CoinType>(account: &signer, pool_address: address): Option<RootCapability<CoinType>> acquires RootCapabilityCollection {
        let account_addr = signer::address_of(account);
        find_root_collection<CoinType>(account_addr, pool_address)
    }

    /// Destroy root privileges by program
    public fun destroy_root_program<CoinType>(root: RootCapability<CoinType>) {
        let RootCapability<CoinType> { pool_address: _ } = root;
    }

    /// Destroy root privileges.
    public entry fun destroy_root<CoinType>(account: &signer, pool_address: address)  acquires RootCapabilityCollection {
        let account_addr = signer::address_of(account);
        let result = find_root_collection<CoinType>(account_addr, pool_address);
        assert!(option::is_some(&result), POOL_ROOT_NOT_EXIST);

        destroy_root_program(option::destroy_some(result));
    }

    /// Add coin to the pool.
    fun supply_internal<CoinType>(account: &signer, pool_address: address, amount: u64): WithdrawProof<CoinType> acquires Pool {
        assert!(is_pool_created<CoinType>(pool_address), POOL_NOT_EXIST);

        let account_addr = signer::address_of(account);
        let pool = borrow_global_mut<Pool<CoinType>>(account_addr);

        let account_coin = coin::withdraw<CoinType>(account, amount);
        coin::merge(&mut pool.coin, account_coin);

        WithdrawProof<CoinType> {
            pool_address,
            amount
        }
    }

    /// Account supply coin to the single currency pool represented by pool_address.
    /// WithdrawProof is managed by external program.
    public fun supply_program<CoinType>(account: &signer, pool_address: address, amount: u64): WithdrawProof<CoinType> acquires Pool {
        supply_internal<CoinType>(account, pool_address, amount)
    }

    /// Account supply coin to the single currency pool represented by pool_address.
    /// WithdrawProof is managed by WithdrawProofCollection.
    public entry fun supply<CoinType>(account: &signer, pool_address: address, amount: u64) acquires Pool, WithdrawProofCollection {
        let proof = supply_internal<CoinType>(account, pool_address, amount);

        let account_addr = signer::address_of(account);

        let result = find_proof_collection<CoinType>(account_addr, pool_address);
        if (option::is_none(&result)) {
            option::destroy_none(result);
            add_proof_collection(account, proof);
        }else {
            merge_proof(&mut proof, option::destroy_some(result));
            add_proof_collection(account, proof);
        };
    }

    /// Withdraw from coin.
    fun withdraw_internal<CoinType>(pool_address: address, amount: u64): Coin<CoinType> acquires Pool {
        assert!(is_pool_created<CoinType>(pool_address), POOL_NOT_EXIST);

        let pool = borrow_global_mut<Pool<CoinType>>(pool_address);

        assert!(coin::value<CoinType>(&pool.coin) >= amount, POOL_AMOUNT_NOT_ENOUGH);

        coin::extract<CoinType>(&mut pool.coin, amount)
    }

    /// External programs use root privileges to withdraw coin.
    public fun withdraw_root_program<CoinType>(root: &RootCapability<CoinType>, to: address, amount: u64) acquires Pool {
        coin::deposit<CoinType>(to, withdraw_internal(root.pool_address, amount));
    }

    /// The external program uses proof to withdraw coin.
    public fun withdraw_program<CoinType>(proof: &mut WithdrawProof<CoinType>, to: address, amount: u64) acquires Pool {
        coin::deposit(to, extract_proof<CoinType>(proof, amount));
    }

    /// Use the root stored in the account address to withdraw.
    public entry fun withdraw_root<CoinType>(account: &signer, pool_address: address, amount: u64) acquires Pool, RootCapabilityCollection {
        let account_addr = signer::address_of(account);
        let result = find_root_collection<CoinType>(account_addr, pool_address);
        assert!(option::is_some(&result), POOL_ROOT_NOT_EXIST);

        let root = option::destroy_some(result);

        withdraw_root_program(&root, account_addr, amount);

        add_root_collection(account, root);
    }


    /// Use the proof stored in the account address to withdraw.
    public entry fun withdraw<CoinType>(account: &signer, pool_address: address, amount: u64) acquires Pool, WithdrawProofCollection {
        let account_addr = signer::address_of(account);
        let result = find_proof_collection<CoinType>(account_addr, pool_address);
        assert!(option::is_some(&result), PROOF_NOT_EXIST);

        let proof = option::destroy_some(result);
        coin::deposit(account_addr, extract_proof<CoinType>(&mut proof, amount));
        if (proof.amount > 0 ) {
            add_proof_collection(account, proof);
        }else {
            destroy_proof_zero(proof);
        }
    }

    /// Destroys proof.
    public fun destroy_proof<CoinType>(withdraw_proof: WithdrawProof<CoinType>) {
        let WithdrawProof<CoinType> {
            pool_address: _,
            amount: _
        } = withdraw_proof;
    }

    /// Destroys a zero-value proof.
    public fun destroy_proof_zero<CoinType>(proof: WithdrawProof<CoinType>) {
        let WithdrawProof<CoinType> { pool_address: _, amount } = proof;
        assert!(amount == 0, DESTRUCTION_OF_NONZERO_PROOF)
    }

    /// Extracts `amount` from the proof.
    public fun extract_proof<CoinType>(proof: &mut WithdrawProof<CoinType>, amount: u64): Coin<CoinType> acquires Pool {
        assert!(proof.amount >= amount, POOL_AMOUNT_NOT_ENOUGH);
        proof.amount = proof.amount - amount;
        withdraw_internal<CoinType>(proof.pool_address, amount)
    }

    /// "Merges" the proof.
    public fun merge_proof<CoinType>(dst_proof: &mut WithdrawProof<CoinType>, source_proof: WithdrawProof<CoinType>) {
        assert!(dst_proof.pool_address == source_proof.pool_address, POOL_NOT_SAME);
        dst_proof.amount = dst_proof.amount + source_proof.amount;
        destroy_proof<CoinType>(source_proof);
    }
}

module coin_pool::omni_pool {
    use coin_pool::singel_pool::{RootCapability, Self};
    use std::vector;
    use aptos_std::type_info::TypeInfo;
    use std::signer;
    use aptos_std::type_info;
    use std::option::Option;
    use std::option;


    //
    // Errors.
    //

    /// Not deployed address
    const NOT_DEPLOYED_ADDRESS: u64 = 0;

    /// Exist same coin type
    const EXIST_SAME_COINTYPE: u64 = 0;

    /// Has been initialized
    const HAS_BEEN_INITIALIZED: u64 = 0;

    /// Must been initialized
    const MUST_BEEN_INITIALIZED: u64 = 0;

    /// Must been owner
    const MUST_BEEN_OWNER: u64 = 0;

    /// Not find creator
    const NOT_FIND_CREATOR: u64 = 0;

    /// Pool creator stores root permissions and whitelist.
    /// `root`: Pool root permissions
    /// `whitelist`: Whitelist members can use root privileges.
    struct RootInfo<phantom CoinType> has key {
        root: RootCapability<CoinType>,
        whitelist: vector<address>
    }

    /// Pool manager
    /// coin_types: All pool cointype that have been created.
    /// creators: All pool creators.
    /// owner: All pool owners.
    struct PoolManage has key {
        coin_types: vector<TypeInfo>,
        creators: vector<address>,
        owner: address
    }

    /// Has it been initialized.
    public fun is_initialize(): bool {
        exists<PoolManage>(@coin_pool)
    }

    /// Whether the owner of all pools
    public fun is_owner(account: &signer): bool acquires PoolManage {
        assert!(is_initialize(), MUST_BEEN_INITIALIZED);
        let account_addr = signer::address_of(account);
        borrow_global<PoolManage>(@coin_pool).owner == account_addr
    }

    /// The contract deployer initializes the pool manager.
    public entry fun initialize(account: &signer) {
        assert!(signer::address_of(account) == @coin_pool, NOT_DEPLOYED_ADDRESS);
        assert!(!is_initialize(), HAS_BEEN_INITIALIZED);

        move_to(account, PoolManage {
            coin_types: vector::empty(),
            creators: vector::empty(),
            owner: @coin_pool
        });
    }

    /// Search for already created `CoinType`.
    fun find_coin_types<CoinType>(): (bool, u64) acquires PoolManage {
        let coin_type = type_info::type_of<CoinType>();
        let coin_types = &borrow_global<PoolManage>(@coin_pool).coin_types;
        vector::index_of(coin_types, &coin_type)
    }

    /// Exist `CoinType`.
    public fun exist_coin_types<CoinType>(): bool acquires PoolManage {
        let (flag, _) = find_coin_types<CoinType>();
        flag
    }

    /// Find creator by CoinType
    fun find_creator<CoinType>(): Option<address> acquires PoolManage {
        let (flag, index) = find_coin_types<CoinType>();
        if (flag) {
            let creator = borrow_global<PoolManage>(@coin_pool).creators[index];
            option::some(creator)
        }else {
            option::none()
        }
    }

    /// Find out if the account is in the whitelist
    /// `creator`: `RootInfo` is stored under the pool creator account
    /// `account`: Account found
    fun find_whitelist<CoinType>(creator: address, account: address): (bool, u64) acquires RootInfo {
        let root_info = borrow_global<RootInfo<CoinType>>(creator);
        vector::index_of(&root_info.whitelist, &account)
    }

    /// Create pool.
    /// Only the owner can create pools.
    /// Can't create pools with the same CoinType.
    public entry fun create_pool<CoinType>(creater: &signer) acquires PoolManage {
        assert!(is_owner(creater), MUST_BEEN_OWNER);
        assert!(exist_coin_types<CoinType>(), EXIST_SAME_COINTYPE);

        let create_addr = signer::address_of(creater);

        let root = singel_pool::create_pool_program<CoinType>(creater);
        let root_info = RootInfo<CoinType> {
            root,
            whitelist: vector::singleton(create_addr)
        };
        move_to(creater, root_info);

        let pool_manager = borrow_global_mut<PoolManage>(@coin_pool);
        vector::push_back(&mut pool_manager.coin_types, type_info::type_of<CoinType>());
        vector::push_back(&mut pool_manager.creators, create_addr);
    }

    /// Transfer owner.
    public entry fun transfer_owner(from: &signer, to: address) acquires PoolManage {
        assert!(is_owner(from), MUST_BEEN_OWNER);

        let pool_manager = borrow_global_mut<PoolManage>(@coin_pool);
        pool_manager.owner = to;
    }

    /// Update whitelist
    /// `action`: 0 means add, 1 means remove
    public entry fun update_whitelist<CoinType>(from: &signer, account: address, action: u64) acquires PoolManage, RootInfo {
        assert!(is_owner(from), MUST_BEEN_OWNER);
        let result = find_creator<CoinType>();
        assert!(option::is_some(&result), NOT_FIND_CREATOR);
        let creator = option::destroy_some(result);
        let (flag, index) = find_whitelist<CoinType>(creator, account);
        if (!flag && action == 0) {
            let root_info = borrow_global_mut<RootInfo<CoinType>>(creator);
            vector::push_back(&mut root_info.whitelist, account);
        };
        if (flag && action == 1) {
            let root_info = borrow_global_mut<RootInfo<CoinType>>(creator);
            vector::swap_remove(&mut root_info.whitelist, index);
        }
    }

    /// Facilitate future contract upgrades.
    /// `CoinType`: results in multiple calls.
    /// Returns: root permissions and whitelisting
    public fun upgrade<CoinType>(from: &signer): (RootCapability<CoinType>, vector<address>) acquires PoolManage, RootInfo {
        assert!(is_owner(from), MUST_BEEN_OWNER);
        let result = find_creator<CoinType>();
        assert!(option::is_some(&result), NOT_FIND_CREATOR);
        let creator = option::destroy_some(result);


        let root_info = move_from<RootInfo<CoinType>>(creator);
        (root_info.root, root_info.whitelist)
    }
}

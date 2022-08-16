#[test_only]
module coin_pool::singel_pool_test {
    use std::signer;
    use coin_pool::singel_pool::{initialize, pool_recorder_initialized, create_pool, is_pool_created, create_pool_program, add_root_collection, has_root_collection, extract_root, RootCapability, supply, withdraw, withdraw_root, withdraw_proof_amount};
    use aptos_framework::coin::{FakeMoney, create_fake_money, transfer, balance, register_for_test};
    use aptos_framework::block::initialize_block_metadata;
    use std::option::{is_some, extract};

    #[test(deployer=@0x11)]
    fun test_initialize_pool_recorder(deployer: &signer) {
        initialize(deployer);
        assert!(pool_recorder_initialized(), 101);
    }

    // The dev-address set in move.toml is the deployer address
    #[test(deployer=@0x22)]
    #[expected_failure(abort_code=10)]
    fun test_not_deployer_initialize_pool_recorder(deployer: &signer) {
        initialize(deployer);
    }

    #[test(deployer=@0x11)]
    #[expected_failure(abort_code=0)]
    fun test_duplicate_initialize_pool_recorder(deployer: &signer) {
        initialize(deployer);
        assert!(pool_recorder_initialized(), 101);
        initialize(deployer);
    }

    #[test(aptos_framework=@aptos_framework, deployer=@0x11, user=@0x66)]
    fun test_create_pool(aptos_framework: &signer,deployer: &signer, user: &signer) {
        initialize_block_metadata(aptos_framework, 1);
        initialize(deployer);

        create_pool<FakeMoney>(user);
        let user_addr = signer::address_of(user);
        assert!(is_pool_created<FakeMoney>(user_addr), 101);
        assert!(has_root_collection<FakeMoney>(user_addr), 102);
    }

    #[test(aptos_framework=@aptos_framework, deployer=@0x11, program=@0x55, user=@0x66)]
    fun test_create_pool_program(aptos_framework: &signer,deployer: &signer, program: &signer, user: &signer) {
        initialize_block_metadata(aptos_framework, 1);
        initialize(deployer);

        let root_capacity = create_pool_program<FakeMoney>(program);
        let program_addr = signer::address_of(program);
        assert!(is_pool_created<FakeMoney>(program_addr), 101);
        add_root_collection(user, root_capacity);
        let user_addr = signer::address_of(user);
        assert!(has_root_collection<FakeMoney>(user_addr), 102);
    }

    #[test(aptos_framework=@aptos_framework, user=@0x66)]
    #[expected_failure(abort_code=0x1)]
    fun test_not_initialize_pool_recorder_create_pool(aptos_framework: &signer, user: &signer) {
        initialize_block_metadata(aptos_framework, 1);

        create_pool<FakeMoney>(user);
        let user_addr = signer::address_of(user);
        assert!(is_pool_created<FakeMoney>(user_addr), 101);
    }

    #[test(aptos_framework=@aptos_framework, deployer=@0x11, user=@0x66)]
    fun test_extract_root(aptos_framework: &signer,deployer: &signer, user: &signer) {
        initialize_block_metadata(aptos_framework, 1);
        initialize(deployer);

        create_pool<FakeMoney>(deployer);
        let pool_addr = signer::address_of(deployer);
        assert!(is_pool_created<FakeMoney>(pool_addr), 101);
        assert!(has_root_collection<FakeMoney>(pool_addr), 102);
        let root_capacity = extract_root<FakeMoney>(deployer, pool_addr);
        assert!(is_some<RootCapability<FakeMoney>>(&root_capacity), 103);
        let root_capacity = extract<RootCapability<FakeMoney>>(&mut root_capacity);
        add_root_collection(user, root_capacity);
        let user_addr = signer::address_of(user);
        assert!(has_root_collection<FakeMoney>(user_addr), 104)
    }

    #[test_only]
    fun setup_supply(aptos_framework: &signer, source: &signer, deployer: &signer, user: &signer, amount: u64) {
        initialize_block_metadata(aptos_framework, 1);
        initialize(deployer);

        create_pool<FakeMoney>(deployer);
        create_fake_money(source, user, 100);

        let user_addr = signer::address_of(user);
        transfer<FakeMoney>(source, user_addr, amount);
    }

    #[test(aptos_framework=@aptos_framework, source=@0x1, deployer=@0x11, user=@0x66)]
    fun test_supply(aptos_framework: &signer, source: &signer, deployer: &signer, user: &signer) {
        setup_supply(aptos_framework, source, deployer, user, 50);
        let user_addr = signer::address_of(user);
        assert!(balance<FakeMoney>(user_addr) == 50, 101);

        let pool_addr = signer::address_of(deployer);
        supply<FakeMoney>(user, pool_addr,50);
        assert!(withdraw_proof_amount<FakeMoney>(user_addr, pool_addr) == 50, 102);
        assert!(balance<FakeMoney>(user_addr) == 0, 103);
    }

    #[test_only]
    fun setup_withdraw(aptos_framework: &signer, source: &signer, deployer: &signer, user: &signer, amount: u64) {
        setup_supply(aptos_framework, source, deployer, user, amount);
        let pool_addr = signer::address_of(deployer);
        supply<FakeMoney>(user, pool_addr, amount);
    }

    #[test(aptos_framework=@aptos_framework, source=@0x1, deployer=@0x11, user=@0x66)]
    fun test_withdraw_root(aptos_framework: &signer, source: &signer, deployer: &signer, user: &signer) {
        setup_withdraw(aptos_framework, source, deployer, user, 50);
        let user_addr = signer::address_of(user);
        let pool_addr = signer::address_of(deployer);

        assert!(balance<FakeMoney>(user_addr) == 0, 104);
        let root_addr = signer::address_of(deployer);
        register_for_test<FakeMoney>(deployer);
        withdraw_root<FakeMoney>(deployer, pool_addr, 50);
        assert!(balance<FakeMoney>(root_addr) == 50, 105)
    }

    #[test(aptos_framework=@aptos_framework, source=@0x1, deployer=@0x11, user=@0x66)]
    fun test_withdraw(aptos_framework: &signer, source: &signer, deployer: &signer, user: &signer) {
        setup_withdraw(aptos_framework, source, deployer, user, 50);
        let user_addr = signer::address_of(user);
        let pool_addr = signer::address_of(deployer);

        assert!(balance<FakeMoney>(user_addr) == 0, 104);
        assert!(withdraw_proof_amount<FakeMoney>(user_addr, pool_addr) == 50, 105);
        withdraw<FakeMoney>(user, pool_addr, 50);
        assert!(balance<FakeMoney>(user_addr) == 50, 106)
    }
}
#[test_only]
module coin_pool::pool_test {
    use std::signer;
    use aptos_framework::aptos_coin::{Self, AptosCoin};
    use aptos_framework::coin;
    use coin_pool::pool::{initialize, supply, withdraw, borrow, repay, pool_coins, set_relayer, check_relayer};

    #[test_only]
    fun setup_test(
        aptos_framework: &signer,
        core_resources: &signer,
        account: &signer,
        balance: u64
    ) {
        let (mint_cap, burn_cap) = aptos_coin::initialize(aptos_framework, core_resources);

        let account_addr = signer::address_of(account);

        coin::register_for_test<AptosCoin>(account);
        aptos_coin::mint(aptos_framework, account_addr, balance);

        coin::destroy_mint_cap<AptosCoin>(mint_cap);
        coin::destroy_burn_cap<AptosCoin>(burn_cap);
    }

    #[test(owner = @0x11, user = @0x22)]
    fun test_set_relayer(owner: &signer, user: &signer) {
        initialize(owner);

        let user_addr = signer::address_of(user);
        set_relayer(owner, user_addr);

        check_relayer(user);
    }

    #[test(owner = @0x55, user = @0x22)]
    #[expected_failure(abort_code = 0x1)]
    fun add_relayer_not_owner(owner: &signer, user: &signer) {
        initialize(owner);

        let user_addr = signer::address_of(user);
        set_relayer(owner, user_addr);
    }

    #[test(
        core_resources = @core_resources,
        aptos_framework = @aptos_framework,
        owner = @0x11, 
        user = @0x22
    )]
    fun test_supply(
        core_resources: &signer,
        aptos_framework: &signer,
        owner: &signer, 
        user: &signer
    ) {
        let user_init_amount = 100;
        setup_test(aptos_framework, core_resources, user, user_init_amount);

        initialize(owner);

        let user_addr = signer::address_of(user);
        let user_supply_amount = 50;
        assert!(coin::balance<AptosCoin>(user_addr) == user_init_amount, 1);
        supply(user, user_supply_amount);
        assert!(coin::balance<AptosCoin>(user_addr) == user_init_amount - user_supply_amount, 2);

        assert!(pool_coins() == user_supply_amount, 3);
    }

    #[test(
        core_resources = @core_resources,
        aptos_framework = @aptos_framework,
        owner = @0x11,
        relayer = @0x22,
        user = @0x33
    )]
    fun test_withdraw(
        core_resources: &signer,
        aptos_framework: &signer,
        owner: &signer, 
        relayer: &signer,
        user: &signer
    ) {
        let user_init_amount = 100;
        let user_supply_amount = 50;
        let user_withdraw_amount = 50;
        let user_addr = signer::address_of(user);
        test_supply(core_resources, aptos_framework, owner, user);

        let relayer_addr = signer::address_of(relayer);
        set_relayer(owner, relayer_addr);

        assert!(coin::balance<AptosCoin>(user_addr) == user_init_amount - user_supply_amount, 1);
        assert!(pool_coins() == user_supply_amount, 2);
        withdraw(relayer, user_addr, user_withdraw_amount, 0);
        assert!(coin::balance<AptosCoin>(user_addr) == user_init_amount, 3);
        assert!(pool_coins() == 0, 4);
    }

    #[test_only]
    fun test_withdraw_nonce(
        relayer: &signer,
        user: &signer,
        nonce: u64,
    ) {
        let user_addr = signer::address_of(user);
        let user_withdraw_amount = 50;
        supply(user, user_withdraw_amount);
        withdraw(relayer, user_addr, user_withdraw_amount, nonce);
    }

    #[test(
        core_resources = @core_resources,
        aptos_framework = @aptos_framework,
        owner = @0x11,
        relayer = @0x22,
        user = @0x33
    )]
    #[expected_failure(abort_code = 0x3)]
    fun test_withdraw_duplicated_nonce(
        core_resources: &signer,
        aptos_framework: &signer,
        owner: &signer, 
        relayer: &signer,
        user: &signer
    ) {
        test_withdraw(core_resources, aptos_framework, owner, relayer, user);
        test_withdraw_nonce(relayer, user, 1);
        test_withdraw_nonce(relayer, user, 1);
    }

    #[test(
        core_resources = @core_resources,
        aptos_framework = @aptos_framework,
        owner = @0x11,
        relayer = @0x22,
        user = @0x33
    )]
    fun test_withdraw_cached_nonce(
        core_resources: &signer,
        aptos_framework: &signer,
        owner: &signer, 
        relayer: &signer,
        user: &signer
    ) {
        test_withdraw(core_resources, aptos_framework, owner, relayer, user);
        test_withdraw_nonce(relayer, user, 1);
        test_withdraw_nonce(relayer, user, 10);
        test_withdraw_nonce(relayer, user, 5);
    }

    #[test(
        core_resources = @core_resources,
        aptos_framework = @aptos_framework,
        owner = @0x11,
        relayer = @0x22,
        supply_user = @0x33,
        borrow_user = @0x44,
    )]
    fun test_borrow(
        core_resources: &signer,
        aptos_framework: &signer,
        owner: &signer, 
        relayer: &signer,
        supply_user: &signer,
        borrow_user: &signer,
    ) {
        let user_init_amount = 100;
        setup_test(aptos_framework, core_resources, supply_user, user_init_amount);

        initialize(owner);
        supply(supply_user, user_init_amount);

        let relayer_addr = signer::address_of(relayer);
        set_relayer(owner, relayer_addr);

        let user_borrow_amount = 50;
        let borrow_user_addr = signer::address_of(borrow_user);
        assert!(pool_coins() == user_init_amount, 1);
        coin::register_for_test<AptosCoin>(borrow_user);
        assert!(coin::balance<AptosCoin>(borrow_user_addr) == 0, 2);

        borrow(relayer, borrow_user_addr, user_borrow_amount, 0);
        assert!(pool_coins() == user_init_amount - user_borrow_amount, 3);
        assert!(coin::balance<AptosCoin>(borrow_user_addr) == user_borrow_amount, 4);
    }

    #[test(
        core_resources = @core_resources,
        aptos_framework = @aptos_framework,
        owner = @0x11,
        relayer = @0x22,
        user = @0x33,
    )]
    fun test_repay(
        core_resources: &signer,
        aptos_framework: &signer,
        owner: &signer, 
        user: &signer,
    ) {
        let user_init_amount = 100;
        setup_test(aptos_framework, core_resources, user, user_init_amount);

        initialize(owner);

        let user_repay_amount = 50;
        let user_addr = signer::address_of(user);
        assert!(pool_coins() == 0, 1);
        assert!(coin::balance<AptosCoin>(user_addr) == user_init_amount, 2);
        repay(user, user_repay_amount);
        assert!(pool_coins() == user_repay_amount, 3);
        assert!(coin::balance<AptosCoin>(user_addr) == user_init_amount - user_repay_amount, 4);
    }
}
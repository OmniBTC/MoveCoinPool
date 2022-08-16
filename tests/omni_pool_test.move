#[test_only]
module coin_pool::omni_pool_test {
    use coin_pool::omni_pool::{initialize, is_initialize, is_owner, transfer_owner, create_pool, find_creator, update_whitelist, find_whitelist, supply, supply_relayer, withdraw, withdraw_relayer, borrow, borrow_relayer, repay, repay_relayer, cross, cross_relayer};
    use coin_pool::singel_pool;
    use std::signer;
    use aptos_framework::coin::{FakeMoney, create_fake_money, transfer, balance};
    use aptos_framework::block::initialize_block_metadata;
    use std::option;

    #[test(deployer=@0x11)]
    fun test_initialize(deployer: &signer) {
        initialize(deployer);
        assert!(is_initialize(), 101);
    }

    #[test(user=@0x22)]
    #[expected_failure(abort_code=0)]
    fun test_not_deployer_initialize(user: &signer) {
        initialize(user);
    }

    #[test(deployer=@0x11)]
    #[expected_failure(abort_code=2)]
    fun test_has_been_initialized(deployer: &signer) {
        initialize(deployer);
        assert!(is_initialize(), 101);
        initialize(deployer);
    }

    #[test(owner=@0x11, new_owner=@0x22)]
    fun test_transfer_owner(owner: &signer, new_owner: &signer) {
        initialize(owner);
        assert!(is_owner(owner), 101);
        let new_owner_addr = signer::address_of(new_owner);
        transfer_owner(owner, new_owner_addr);
        assert!(is_owner(new_owner), 102);
    }

    #[test_only]
    fun setup_pool(aptos_framework: &signer, creator: &signer, chain_id: u64, token_id: u64) {
        initialize_block_metadata(aptos_framework, 1);
        singel_pool::initialize(creator);
        initialize(creator);
        create_pool<FakeMoney>(creator, chain_id, token_id);
    }

    #[test(aptos_framework=@aptos_framework, creator=@0x11)]
    fun test_create_pool(aptos_framework: &signer, creator: &signer) {
        setup_pool(aptos_framework, creator, 1, 1);
        let result = find_creator<FakeMoney>();
        assert!(option::is_some(&result), 101);
        assert!(option::extract(&mut result) == signer::address_of(creator), 102);
    }

    #[test(aptos_framework=@aptos_framework, creator=@0x11, relayer=@0x22)]
    fun test_update_whitelist(aptos_framework: &signer, creator: &signer, relayer: &signer) {
        setup_pool(aptos_framework, creator, 1, 1);
        let relayer_addr = signer::address_of(relayer);
        let creator_addr = signer::address_of(creator);
        // add relayer to whitelist
        update_whitelist<FakeMoney>(creator, relayer_addr, 0);
        let (exist_in_whitelist, _) = find_whitelist<FakeMoney>(creator_addr, relayer_addr);
        assert!(exist_in_whitelist, 103);
        // remove relayer from whitelist
        update_whitelist<FakeMoney>(creator, relayer_addr, 1);
        let (exist_in_whitelist, _) = find_whitelist<FakeMoney>(creator_addr, relayer_addr);
        assert!(!exist_in_whitelist, 104);
    }

    #[test_only]
    fun setup_relayer(creator: &signer, relayer: &signer) {
        update_whitelist<FakeMoney>(creator, signer::address_of(relayer), 0);
    }

    #[test_only]
    fun setup_supply(aptos_framework: &signer, source: &signer, creator: &signer, user: &signer, amount: u64) {
        setup_pool(aptos_framework, creator, 1, 1);
        create_fake_money(source, user, amount);

        let user_addr = signer::address_of(user);
        transfer<FakeMoney>(source, user_addr, amount);
    }

    #[test(aptos_framework=@aptos_framework, source=@0x1, creator=@0x11, user=@0x22)]
    fun test_supply(aptos_framework: &signer, source: &signer, creator: &signer, user: &signer) {
        setup_supply(aptos_framework, source, creator, user, 100);
        let user_addr = signer::address_of(user);
        assert!(balance<FakeMoney>(user_addr) == 100, 105);
        supply<FakeMoney>(user, 100);
        assert!(balance<FakeMoney>(user_addr) == 0, 106);
    }

    #[test(aptos_framework=@aptos_framework, source=@0x1, creator=@0x11, relayer=@0x22, user=@0x33)]
    fun test_supply_relayer(aptos_framework: &signer, source: &signer, creator: &signer, relayer: &signer, user: &signer) {
        setup_supply(aptos_framework, source, creator, user, 100);
        setup_relayer(creator, relayer);
        let user_addr = signer::address_of(user);
        assert!(balance<FakeMoney>(user_addr) == 100, 105);
        supply<FakeMoney>(user, 100);
        assert!(balance<FakeMoney>(user_addr) == 0, 106);

        // the user succeeded at the local supply, but failed to update the user liquidity remotely, and user supply is returned
        supply_relayer<FakeMoney>(relayer, user_addr, 100, 0);
        assert!(balance<FakeMoney>(user_addr) == 100, 107);
    }

    #[test_only]
    fun setup_withdraw(aptos_framework: &signer, source: &signer, creator: &signer, user: &signer, amount: u64) {
        setup_supply(aptos_framework, source, creator, user, amount);
        supply<FakeMoney>(user, amount);
    }

    #[test(aptos_framework=@aptos_framework, source=@0x1, creator=@0x11, user=@0x22)]
    fun test_withdraw(aptos_framework: &signer, source: &signer, creator: &signer, user: &signer) {
        setup_withdraw(aptos_framework, source, creator, user, 100);
        // just emit the event and let the relayer handle it
        withdraw<FakeMoney>(user, 100);
    }

    #[test(aptos_framework=@aptos_framework, source=@0x1, creator=@0x11, relayer=@0x22, user=@0x33)]
    fun test_withdraw_relayer(aptos_framework: &signer, source: &signer, creator: &signer, relayer: &signer, user: &signer) {
        setup_withdraw(aptos_framework, source, creator, user, 100);
        setup_relayer(creator, relayer);

        // relayer handles withdrawals from different chains in the current chain
        let user_addr = signer::address_of(user);
        withdraw_relayer<FakeMoney>(relayer, user_addr, 100, 0);
        assert!(balance<FakeMoney>(user_addr) == 100, 105);
    }

    #[test(aptos_framework=@aptos_framework, source=@0x1, creator=@0x11, user=@0x22)]
    fun test_borrow(aptos_framework: &signer, source: &signer, creator: &signer, user: &signer) {
        setup_withdraw(aptos_framework, source, creator, user, 100);
        // just emit the event and let the relayer handle it
        borrow<FakeMoney>(user, 100);
    }

    #[test(aptos_framework=@aptos_framework, source=@0x1, creator=@0x11, relayer=@0x22, user=@0x33)]
    fun test_borrow_relayer(aptos_framework: &signer, source: &signer, creator: &signer, relayer: &signer, user: &signer) {
        setup_withdraw(aptos_framework, source, creator, user, 100);
        setup_relayer(creator, relayer);

        let user_addr = signer::address_of(user);
        borrow_relayer<FakeMoney>(relayer, user_addr, 100, 0);
        assert!(balance<FakeMoney>(user_addr) == 100, 105);
    }

    #[test(aptos_framework=@aptos_framework, source=@0x1, creator=@0x11, user=@0x22)]
    fun test_repay(aptos_framework: &signer, source: &signer, creator: &signer, user: &signer) {
        setup_supply(aptos_framework, source, creator, user, 100);
        let user_addr = signer::address_of(user);
        assert!(balance<FakeMoney>(user_addr) == 100, 105);
        repay<FakeMoney>(user, 100);
        assert!(balance<FakeMoney>(user_addr) == 0, 106);
    }

    #[test(aptos_framework=@aptos_framework, source=@0x1, creator=@0x11, relayer=@0x22, user=@0x33)]
    fun test_repay_relayer(aptos_framework: &signer, source: &signer, creator: &signer, relayer: &signer, user: &signer) {
        setup_supply(aptos_framework, source, creator, user, 100);
        setup_relayer(creator, relayer);
        let user_addr = signer::address_of(user);
        assert!(balance<FakeMoney>(user_addr) == 100, 105);
        repay<FakeMoney>(user, 100);
        assert!(balance<FakeMoney>(user_addr) == 0, 106);

        // the local repay succeeds, but failed to update the user liquidity remotely, and user repay is returned
        repay_relayer<FakeMoney>(relayer, user_addr, 100, 0);
        assert!(balance<FakeMoney>(user_addr) == 100, 107);
    }

    #[test(aptos_framework=@aptos_framework, source=@0x1, creator=@0x11, user=@0x22)]
    fun test_cross(aptos_framework: &signer, source: &signer, creator: &signer, user: &signer) {
        setup_supply(aptos_framework, source, creator, user, 100);

        let user_addr = signer::address_of(user);
        assert!(balance<FakeMoney>(user_addr) == 100, 105);
        cross<FakeMoney>(user, 100, 1);
        assert!(balance<FakeMoney>(user_addr) == 0, 106);
    }

    #[test(aptos_framework=@aptos_framework, source=@0x1, creator=@0x11, relayer=@0x22, user=@0x33)]
    fun test_cross_relayer(aptos_framework: &signer, source: &signer, creator: &signer, relayer: &signer, user: &signer) {
        setup_withdraw(aptos_framework, source, creator, user, 100);
        setup_relayer(creator, relayer);

        let user_addr = signer::address_of(user);
        cross_relayer<FakeMoney>(relayer, user_addr, 100, 0, 1, 1);
        assert!(balance<FakeMoney>(user_addr) == 100, 105);
    }
}
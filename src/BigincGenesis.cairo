use starknet::ContractAddress;

// ============================================================================
// INTERFACE DEFINITION
// ============================================================================

#[starknet::interface]
pub trait IBigIncGenesis<TContractState> {
    // ========== CORE FUNCTIONALITY ==========
    fn mint_share(ref self: TContractState, token_address: ContractAddress);
    fn transfer_share(ref self: TContractState, to: ContractAddress, share_amount: u256);
    fn donate(ref self: TContractState, token_address: ContractAddress, amount: u256);

    // ========== VIEW FUNCTIONS ==========
    fn get_available_shares(self: @TContractState) -> u256;
    fn get_shares(self: @TContractState, addr: ContractAddress) -> u256;
    fn get_shareholder_count(self: @TContractState) -> u32;
    fn get_shareholder_at_index(self: @TContractState, index: u32) -> ContractAddress;
    fn is_shareholder(self: @TContractState, addr: ContractAddress) -> bool;
    fn get_usdt_address(self: @TContractState) -> ContractAddress;
    fn get_usdc_address(self: @TContractState) -> ContractAddress;
    fn get_total_share_valuation(self: @TContractState) -> u256;
    fn get_presale_share_valuation(self: @TContractState) -> u256;
    fn get_presale_shares(self: @TContractState) -> u256;
    fn get_shares_sold(self: @TContractState) -> u256;
    fn is_presale_active(self: @TContractState) -> bool;

    // ========== OWNER FUNCTIONS ==========
    fn withdraw(ref self: TContractState, token_address: ContractAddress, amount: u256);
    fn seize_shares(ref self: TContractState, shareholder: ContractAddress);
    fn set_partner_share_cap(ref self: TContractState, token_address: ContractAddress, cap: u256);
    fn remove_partner_share_cap(ref self: TContractState, token_address: ContractAddress);
    fn pause(ref self: TContractState);
    fn unpause(ref self: TContractState);

    // ========== PARTNER FUNCTIONS ==========
    fn get_partner_share_cap(self: @TContractState, token_address: ContractAddress) -> u256;
    fn get_shares_minted_by_partner(self: @TContractState, token_address: ContractAddress) -> u256;

    // ========== OWNERSHIP FUNCTIONS ==========
    fn get_owner(self: @TContractState) -> ContractAddress;
    fn transfer_owner(ref self: TContractState, new_owner: ContractAddress);
    fn renounce_owner(ref self: TContractState);
}

// ============================================================================
// MAIN CONTRACT
// ============================================================================

#[starknet::contract]
pub mod BigIncGenesis {
    use core::traits::Into;
    use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starknet::{ContractAddress, get_block_timestamp, get_caller_address, get_contract_address};
    use super::IBigIncGenesis;

    

    // ============================================================================
    // STORAGE STRUCTURE
    // ============================================================================

    #[storage]
    struct Storage {
        // ========== CONFIGURATION ==========
        usdt_address: ContractAddress,
        usdc_address: ContractAddress,
        owner: ContractAddress,
        paused: bool,

        // ========== SHARE ECONOMICS ==========
        total_share_valuation: u256,
        presale_share_valuation: u256,
        presale_shares: u256,
        shares_sold: u256,
        available_shares: u256,
        is_presale_active: bool,

        // ========== PARTNER MANAGEMENT ==========
        partner_share_cap: Map<ContractAddress, u256>,
        shares_minted_by_partner: Map<ContractAddress, u256>,

        // ========== SHAREHOLDER MANAGEMENT ==========
        shareholders: Map<ContractAddress, u256>,
        shareholder_addresses: Map<u32, ContractAddress>,
        shareholder_count: u32,
        shareholder_index: Map<ContractAddress, u32>,
    }

    // ============================================================================
    // EVENTS
    // ============================================================================

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        // ========== SHARE EVENTS ==========
        ShareMinted: ShareMinted,
        TransferShare: TransferShare,
        SharesSeized: SharesSeized,
        AllSharesSold: AllSharesSold,

        // ========== PRESALE EVENTS ==========
        PresaleEnded: PresaleEnded,

        // ========== FINANCIAL EVENTS ==========
        Donate: Donate,
        Withdrawn: Withdrawn,

        // ========== PARTNER EVENTS ==========
        PartnerShareCapSet: PartnerShareCapSet,

        // ========== ADMINISTRATIVE EVENTS ==========
        OwnershipTransferred: OwnershipTransferred,
        Paused: Paused,
        Unpaused: Unpaused,
    }

    #[derive(Drop, starknet::Event)]
    struct ShareMinted {
        #[key]
        buyer: ContractAddress,
        shares_bought: u256,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct TransferShare {
        #[key]
        from: ContractAddress,
        #[key]
        to: ContractAddress,
        share_amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct SharesSeized {
        #[key]
        shareholder: ContractAddress,
        share_amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct AllSharesSold {}

    #[derive(Drop, starknet::Event)]
    struct PresaleEnded {}

    #[derive(Drop, starknet::Event)]
    struct Donate {
        #[key]
        donor: ContractAddress,
        token_address: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Withdrawn {
        #[key]
        token_address: ContractAddress,
        amount: u256,
        owner: ContractAddress,
        timestamp: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct PartnerShareCapSet {
        #[key]
        token_address: ContractAddress,
        cap: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct OwnershipTransferred {
        #[key]
        previous_owner: ContractAddress,
        #[key]
        new_owner: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct Paused {
        #[key]
        account: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct Unpaused {
        #[key]
        account: ContractAddress,
    }

    // ============================================================================
    // CONSTRUCTOR
    // ============================================================================

    #[constructor]
    fn constructor(
        ref self: ContractState,
        usdt_address: ContractAddress,
        usdc_address: ContractAddress,
        owner: ContractAddress,
    ) {
        // Validate constructor parameters
        self._validate_constructor_params(usdt_address, usdc_address, owner);

        // Initialize configuration
        self.owner.write(owner);
        self.usdt_address.write(usdt_address);
        self.usdc_address.write(usdc_address);

        // Initialize share economics
        self._initialize_share_economics();

        // Assign initial shares to owner
        self._assign_owner_shares(owner);
    }

    // ============================================================================
    // EXTERNAL IMPLEMENTATION
    // ============================================================================

    #[abi(embed_v0)]
    impl BigIncGenesisImpl of IBigIncGenesis<ContractState> {
        // ========== CORE FUNCTIONALITY ==========

        fn mint_share(ref self: ContractState, token_address: ContractAddress) {
            self._assert_not_paused();
            self._validate_token(token_address);

            let caller = get_caller_address();
            let contract_address = get_contract_address();

            // Check if all shares are sold
            if self.available_shares.read() == 0 {
                self.emit(AllSharesSold {});
                return;
            }

            // Get token allowance and validate
            let token = IERC20Dispatcher { contract_address: token_address };
            let amount = token.allowance(caller, contract_address);
            self._validate_mint_amount(amount, caller, token);

            // Calculate shares to buy
            let current_price = self._get_current_share_price();
            let shares_bought = self._calculate_shares(amount, current_price);
            self._validate_shares_purchase(shares_bought);

            // Check partner share cap
            self._check_partner_share_cap(token_address, shares_bought);

            // Update share statistics
            self._update_share_statistics(shares_bought);

            // Check if presale should end
            self._check_presale_end();

            // Add shareholder if new
            self._add_shareholder_if_new(caller);

            // Update shareholder balance
            self._update_shareholder_balance(caller, shares_bought);

            // Transfer tokens
            token.transfer_from(caller, contract_address, amount);

            self.emit(ShareMinted { buyer: caller, shares_bought, amount });
        }

        fn transfer_share(ref self: ContractState, to: ContractAddress, share_amount: u256) {
            self._assert_not_paused();
            self._validate_transfer_params(to, share_amount);

            let caller = get_caller_address();
            let sender_shares = self.shareholders.read(caller);
            self._validate_sufficient_shares(sender_shares, share_amount);

            // Update sender balance
            self.shareholders.write(caller, sender_shares - share_amount);

            // Update recipient balance
            let recipient_shares = self.shareholders.read(to);
            self.shareholders.write(to, recipient_shares + share_amount);

            // Add recipient to shareholder list if new
            if recipient_shares == 0 {
                self._add_shareholder_to_list(to);
            }

            // Remove sender from shareholder list if no shares left
            if sender_shares == share_amount {
                self._remove_shareholder(caller);
            }

            self.emit(TransferShare { from: caller, to, share_amount });
        }

        fn donate(ref self: ContractState, token_address: ContractAddress, amount: u256) {
            self._validate_donation_params(amount, token_address);

            let caller = get_caller_address();
            let contract_address = get_contract_address();
            let token = IERC20Dispatcher { contract_address: token_address };

            // Validate balance and allowance
            assert(token.balance_of(caller) >= amount, 'Insufficient balance');
            assert(token.allowance(caller, contract_address) >= amount, 'Insufficient allowance');

            // Transfer tokens
            token.transfer_from(caller, contract_address, amount);

            self.emit(Donate { donor: caller, token_address, amount });
        }

        // ========== OWNER FUNCTIONS ==========

        fn withdraw(ref self: ContractState, token_address: ContractAddress, amount: u256) {
            self._assert_only_owner();
            self._validate_withdrawal_params(amount, token_address);

            let token = IERC20Dispatcher { contract_address: token_address };
            let contract_address = get_contract_address();
            let owner = self.owner.read();

            // Validate contract balance
            assert(token.balance_of(contract_address) >= amount, 'Insufficient balance');

            // Transfer tokens to owner
            token.transfer(owner, amount);

            let timestamp: u256 = get_block_timestamp().into();
            self.emit(Withdrawn { token_address, amount, owner, timestamp });
        }

        fn seize_shares(ref self: ContractState, shareholder: ContractAddress) {
            self._assert_only_owner();
            self._assert_not_paused();

            let shares_to_seize = self.shareholders.read(shareholder);
            assert(shares_to_seize > 0, 'No shares to seize');

            // Transfer shares to owner
            let owner = self.owner.read();
            let owner_shares = self.shareholders.read(owner);

            self.shareholders.write(shareholder, 0);
            self.shareholders.write(owner, owner_shares + shares_to_seize);

            // Remove from shareholder list
            self._remove_shareholder(shareholder);

            self.emit(SharesSeized { shareholder, share_amount: shares_to_seize });
        }

        fn set_partner_share_cap(
            ref self: ContractState, token_address: ContractAddress, cap: u256,
        ) {
            self._assert_only_owner();
            self._validate_token(token_address);

            self.partner_share_cap.write(token_address, cap);
            self.emit(PartnerShareCapSet { token_address, cap });
        }

        fn remove_partner_share_cap(ref self: ContractState, token_address: ContractAddress) {
            self._assert_only_owner();
            self._validate_token(token_address);

            self.partner_share_cap.write(token_address, 0);
            self.emit(PartnerShareCapSet { token_address, cap: 0 });
        }

        fn pause(ref self: ContractState) {
            self._assert_only_owner();
            self.paused.write(true);
            let caller = get_caller_address();
            self.emit(Paused { account: caller });
        }

        fn unpause(ref self: ContractState) {
            self._assert_only_owner();
            self.paused.write(false);
            let caller = get_caller_address();
            self.emit(Unpaused { account: caller });
        }

        // ========== VIEW FUNCTIONS ==========

        fn get_available_shares(self: @ContractState) -> u256 {
            self.available_shares.read()
        }

        fn get_shares(self: @ContractState, addr: ContractAddress) -> u256 {
            self.shareholders.read(addr)
        }

        fn get_shareholder_count(self: @ContractState) -> u32 {
            self.shareholder_count.read()
        }

        fn get_shareholder_at_index(self: @ContractState, index: u32) -> ContractAddress {
            let count = self.shareholder_count.read();
            assert(index < count, 'Index out of bounds');
            self.shareholder_addresses.read(index)
        }

        fn is_shareholder(self: @ContractState, addr: ContractAddress) -> bool {
            self.shareholders.read(addr) > 0
        }

        fn get_usdt_address(self: @ContractState) -> ContractAddress {
            self.usdt_address.read()
        }

        fn get_usdc_address(self: @ContractState) -> ContractAddress {
            self.usdc_address.read()
        }

        fn get_total_share_valuation(self: @ContractState) -> u256 {
            self.total_share_valuation.read()
        }

        fn get_presale_share_valuation(self: @ContractState) -> u256 {
            self.presale_share_valuation.read()
        }

        fn get_presale_shares(self: @ContractState) -> u256 {
            self.presale_shares.read()
        }

        fn get_shares_sold(self: @ContractState) -> u256 {
            self.shares_sold.read()
        }

        fn is_presale_active(self: @ContractState) -> bool {
            self.is_presale_active.read()
        }

        fn get_partner_share_cap(self: @ContractState, token_address: ContractAddress) -> u256 {
            self.partner_share_cap.read(token_address)
        }

        fn get_shares_minted_by_partner(
            self: @ContractState, token_address: ContractAddress,
        ) -> u256 {
            self.shares_minted_by_partner.read(token_address)
        }

        fn get_owner(self: @ContractState) -> ContractAddress {
            self.owner.read()
        }

        fn transfer_owner(ref self: ContractState, new_owner: ContractAddress) {
            self._assert_only_owner();
            self._validate_new_owner(new_owner);

            let previous_owner = self.owner.read();
            self.owner.write(new_owner);

            self.emit(OwnershipTransferred { previous_owner, new_owner });
        }

        fn renounce_owner(ref self: ContractState) {
            self._assert_only_owner();
            let previous_owner = self.owner.read();
            let zero_address: ContractAddress = 0.try_into().unwrap();
            self.owner.write(zero_address);

            self.emit(OwnershipTransferred { previous_owner, new_owner: zero_address });
        }
    }

    // ============================================================================
    // INTERNAL IMPLEMENTATION
    // ============================================================================

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        // ========== CONSTRUCTOR HELPERS ==========

        fn _validate_constructor_params(
            self: @ContractState,
            usdt_address: ContractAddress,
            usdc_address: ContractAddress,
            owner: ContractAddress,
        ) {
            let zero_address: ContractAddress = 0.try_into().unwrap();
            assert(usdt_address != zero_address, 'Invalid USDT address');
            assert(usdc_address != zero_address, 'Invalid USDC address');
            assert(owner != zero_address, 'Invalid owner address');
            assert(usdt_address != usdc_address, 'USDT and USDC must be different');
        }

        fn _initialize_share_economics(ref self: ContractState) {
            self.total_share_valuation.write(680000000000_u256); // $680k with 6 decimals
            self.presale_share_valuation.write(457143000000_u256); // $457k with 6 decimals
            self.presale_shares.write(21000000_u256); // 21% shares
            self.shares_sold.write(0_u256);
            self.available_shares.write(82000000_u256); // 82% available after 18% to owner
            self.is_presale_active.write(true);
        }

        fn _assign_owner_shares(ref self: ContractState, owner: ContractAddress) {
            let owner_shares = 18000000_u256; // 18% shares
            self.shareholders.write(owner, owner_shares);
            self.shareholder_addresses.write(0, owner);
            self.shareholder_index.write(owner, 0);
            self.shareholder_count.write(1);
        }

        // ========== VALIDATION HELPERS ==========

        fn _validate_token(self: @ContractState, token_address: ContractAddress) {
            let usdt = self.usdt_address.read();
            let usdc = self.usdc_address.read();
            assert(token_address == usdt || token_address == usdc, 'Invalid token address');
        }

        fn _validate_mint_amount(
            self: @ContractState,
            amount: u256,
            caller: ContractAddress,
            token: IERC20Dispatcher,
        ) {
            assert(amount > 0, 'Amount must be > 0');
            assert(token.balance_of(caller) >= amount, 'Insufficient token balance');
        }

        fn _validate_shares_purchase(self: @ContractState, shares_bought: u256) {
            assert(shares_bought > 0, 'No shares to buy');
            assert(shares_bought <= self.available_shares.read(), 'Exceeds available shares');
        }

        fn _validate_transfer_params(
            self: @ContractState,
            to: ContractAddress,
            share_amount: u256,
        ) {
            let zero_address: ContractAddress = 0.try_into().unwrap();
            assert(to != zero_address, 'Cannot transfer to zero address');
            assert(share_amount > 0, 'Share amount must be > 0');
        }

        fn _validate_sufficient_shares(
            self: @ContractState,
            sender_shares: u256,
            share_amount: u256,
        ) {
            assert(sender_shares >= share_amount, 'Insufficient shares');
        }

        fn _validate_donation_params(
            self: @ContractState,
            amount: u256,
            token_address: ContractAddress,
        ) {
            assert(amount > 0, 'Amount must be > 0');
            self._validate_token(token_address);
        }

        fn _validate_withdrawal_params(
            self: @ContractState,
            amount: u256,
            token_address: ContractAddress,
        ) {
            assert(amount > 0, 'Amount must be > 0');
            self._validate_token(token_address);
        }

        fn _validate_new_owner(self: @ContractState, new_owner: ContractAddress) {
            let zero_address: ContractAddress = 0.try_into().unwrap();
            assert(new_owner != zero_address, 'Invalid owner');
        }

        // ========== ACCESS CONTROL ==========

        fn _assert_only_owner(self: @ContractState) {
            let caller = get_caller_address();
            let owner = self.owner.read();
            assert(caller == owner, 'Caller is not the owner');
        }

        fn _assert_not_paused(self: @ContractState) {
            assert(!self.paused.read(), 'Contract is paused');
        }

        // ========== SHARE CALCULATION HELPERS ==========

        fn _get_current_share_price(self: @ContractState) -> u256 {
            if self.is_presale_active.read() {
                self.presale_share_valuation.read()
            } else {
                self.total_share_valuation.read()
            }
        }

        fn _calculate_shares(self: @ContractState, amount: u256, price: u256) -> u256 {
            let numerator = amount * 100000000_u256;
            numerator / price
        }

        // ========== PARTNER SHARE CAP HELPERS ==========

        fn _check_partner_share_cap(
            ref self: ContractState,
            token_address: ContractAddress,
            shares_bought: u256,
        ) {
            let partner_cap = self.partner_share_cap.read(token_address);
            if partner_cap > 0 {
                let current_partner_shares = self.shares_minted_by_partner.read(token_address);
                let new_partner_shares = current_partner_shares + shares_bought;
                assert(new_partner_shares <= partner_cap, 'Exceeds partner share cap');
                self.shares_minted_by_partner.write(token_address, new_partner_shares);
            }
        }

        // ========== SHARE STATISTICS HELPERS ==========

        fn _update_share_statistics(ref self: ContractState, shares_bought: u256) {
            let current_shares_sold = self.shares_sold.read();
            let new_shares_sold = current_shares_sold + shares_bought;
            self.shares_sold.write(new_shares_sold);

            let available = self.available_shares.read();
            self.available_shares.write(available - shares_bought);
        }

        fn _check_presale_end(ref self: ContractState) {
            if self.is_presale_active.read() {
                let new_shares_sold = self.shares_sold.read();
                let presale_shares = self.presale_shares.read();
                if new_shares_sold >= presale_shares {
                    self.is_presale_active.write(false);
                    self.emit(PresaleEnded {});
                }
            }
        }

        // ========== SHAREHOLDER MANAGEMENT HELPERS ==========

        fn _add_shareholder_if_new(ref self: ContractState, caller: ContractAddress) {
            if self.shareholders.read(caller) == 0 {
                self._add_shareholder_to_list(caller);
            }
        }

        fn _add_shareholder_to_list(ref self: ContractState, shareholder: ContractAddress) {
            let current_count = self.shareholder_count.read();
            self.shareholder_addresses.write(current_count, shareholder);
            self.shareholder_index.write(shareholder, current_count);
            self.shareholder_count.write(current_count + 1);
        }

        fn _update_shareholder_balance(
            ref self: ContractState,
            shareholder: ContractAddress,
            shares_bought: u256,
        ) {
            let current_shares = self.shareholders.read(shareholder);
            self.shareholders.write(shareholder, current_shares + shares_bought);
        }

        fn _remove_shareholder(ref self: ContractState, shareholder: ContractAddress) {
            let count = self.shareholder_count.read();
            let index = self.shareholder_index.read(shareholder);

            if index == count - 1 {
                // Last element, just decrement count
                self.shareholder_count.write(count - 1);
            } else {
                // Move last element to this position
                let last_shareholder = self.shareholder_addresses.read(count - 1);
                self.shareholder_addresses.write(index, last_shareholder);
                self.shareholder_index.write(last_shareholder, index);
                self.shareholder_count.write(count - 1);
            }

            // Clear the index for the removed shareholder
            self.shareholder_index.write(shareholder, 0);
        }
    }
}

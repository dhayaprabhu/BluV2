#![no_std]

#[allow(unused_imports)]
use multiversx_sc::imports::*;

/// An empty contract. To be used as a template when starting a new contract from scratch.
#[multiversx_sc::module]
pub trait BluV2 {
    #[payable("EGLD")]
    #[only_owner]
    #[endpoint(issueToken)]
    fn issue_token(
        &self,
        token_display_name: ManagedBuffer,
        token_ticker: ManagedBuffer,
        token_type: EsdtTokenType,
        opt_num_decimals: OptionalValue<usize>,
    ) {
        require!(self.token_id().is_empty(), "Token already issued");

        let issue_cost = self.call_value().egld_value().clone_value();
        let num_decimals = match opt_num_decimals {
            OptionalValue::Some(d) => d,
            OptionalValue::None => 0,
        };

        self.send()
            .esdt_system_sc_proxy()
            .issue_and_set_all_roles(
                issue_cost,
                token_display_name,
                token_ticker,
                token_type,
                num_decimals,
            )
            .async_call()
            .with_callback(self.callbacks().issue_callback())
            .call_and_exit()
    }

    #[callback]
    fn issue_callback(&self, #[call_result] result: ManagedAsyncCallResult<TokenIdentifier>) {
        match result {
            ManagedAsyncCallResult::Ok(token_id) => {
                self.token_id().set(&token_id);
            },
            ManagedAsyncCallResult::Err(_) => {
                // return payment to initial caller
                let initial_caller = self.blockchain().get_owner_address();
                let egld_returned = self.call_value().egld_value();
                self.tx()
                    .to(&initial_caller)
                    .egld(egld_returned)
                    .transfer_if_not_empty();
            },
        }
    }

    fn mint(&self, token_nonce: u64, amount: &BigUint) {
        let token_id = self.token_id().get();
        self.send().esdt_local_mint(&token_id, token_nonce, amount);
    }

    fn burn(&self, token_nonce: u64, amount: &BigUint) {
        let token_id = self.token_id().get();
        self.send().esdt_local_burn(&token_id, token_nonce, amount);
    }

    fn get_token_attributes<T: TopDecode>(&self, token_nonce: u64) -> T {
        let own_sc_address = self.blockchain().get_sc_address();
        let token_id = self.token_id().get();
        let token_data =
            self.blockchain()
                .get_esdt_token_data(&own_sc_address, &token_id, token_nonce);

        token_data.decode_attributes()
    }

    fn require_token_issued(&self) {
        require!(!self.token_id().is_empty(), "Token must be issued first");
    }

    // Note: to issue another token, you have to clear this storage
    #[storage_mapper("token_id")]
    fn token_id(&self) -> SingleValueMapper<TokenIdentifier>;
}

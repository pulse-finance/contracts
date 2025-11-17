use aiken/collection/list
use aiken/primitive/bytearray
use cardano/address.{Address, Script}
use cardano/assets.{PolicyId, flatten}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction,
}
use constants.{market_info_nft_tn, market_nft_tn, sy_vault_nft_tn}
use types.{MarketDatum, MarketInfoDatum, SYVaultDatum}

fn is_market_info_datum_valid(market_info_datum: MarketInfoDatum) -> Bool {
  expect bytearray.length(market_info_datum.underlying_asset.policy_id) > 0
  expect market_info_datum.expiry > 0
  expect market_info_datum.duration > 0
  expect market_info_datum.envelope_amount > 0
  expect market_info_datum.multiplier >= 0
  expect market_info_datum.min_liquidity >= 0
  expect market_info_datum.scalar_root > 0
  expect market_info_datum.initial_anchor > 0
  expect market_info_datum.ln_fee_rate_root >= 0
  expect market_info_datum.ln_borrow_fee_rate >= 0
  expect market_info_datum.init_py_index >= 0
  True
}

fn is_market_datum_valid(market_datum: MarketDatum) -> Bool {
  expect market_datum.total_sy == 0
  expect market_datum.total_pt == 0
  expect market_datum.total_lp == 0
  expect market_datum.reserved_lp == 0
  True
}

fn is_sy_vault_datum_valid(sy_vault_datum: SYVaultDatum) -> Bool {
  sy_vault_datum.total_sy == 0
}

pub type MintRedeemer {
  Mint {
    market_info_out_idx: Int,
    market_out_idx: Int,
    sy_vault_out_idx: Int,
    market_info_script_hash: ByteArray,
    market_script_hash: ByteArray,
    sy_script_hash: ByteArray,
  }
  Burn
}

pub type MarketAuthTokenParams {
  admin_pkh: ByteArray,
  market_id: OutputReference,
}

validator market_auth_token(params: MarketAuthTokenParams) {
  mint(redeemer: MintRedeemer, policy_id: PolicyId, self: Transaction) {
    let Transaction { inputs, outputs, mint, extra_signatories, .. } = self
    when redeemer is {
      Mint {
        market_info_out_idx,
        market_out_idx,
        sy_vault_out_idx,
        market_info_script_hash,
        market_script_hash,
        sy_script_hash,
      } -> {
        expect list.has(extra_signatories, params.admin_pkh)
        let market_info_nft =
          assets.from_asset(policy_id, market_info_nft_tn, 1)
        let market_nft = assets.from_asset(policy_id, market_nft_tn, 1)
        let sy_vault_nft = assets.from_asset(policy_id, sy_vault_nft_tn, 1)
        let merged_mint =
          assets.merge(market_info_nft, market_nft)
            |> assets.merge(sy_vault_nft)
        expect Some(market_info_output) = list.at(outputs, market_info_out_idx)
        expect Some(market_output) = list.at(outputs, market_out_idx)
        expect Some(sy_vault_output) = list.at(outputs, sy_vault_out_idx)
        let market_info_script_cred = Script(market_info_script_hash)
        let market_script_cred = Script(market_script_hash)
        let sy_script_cred = Script(sy_script_hash)
        let Output {
          address: Address {
            payment_credential: market_info_payment_credential,
            ..
          },
          ..
        } = market_info_output
        let Output {
          address: Address { payment_credential: market_payment_credential, .. },
          ..
        } = market_output
        let Output {
          address: Address {
            payment_credential: sy_vault_payment_credential,
            ..
          },
          ..
        } = sy_vault_output
        expect market_info_payment_credential == market_info_script_cred
        expect market_payment_credential == market_script_cred
        expect sy_vault_payment_credential == sy_script_cred
        expect
          assets.quantity_of(
            market_info_output.value,
            policy_id,
            market_info_nft_tn,
          ) == 1
        expect
          assets.quantity_of(market_output.value, policy_id, market_nft_tn) == 1
        expect
          assets.quantity_of(sy_vault_output.value, policy_id, sy_vault_nft_tn) == 1
        expect list.length(flatten(market_info_output.value)) == 2
        expect list.length(flatten(market_output.value)) == 2
        expect list.length(flatten(sy_vault_output.value)) == 2
        expect InlineDatum(market_info_inline_datum) = market_info_output.datum
        expect market_info_datum: MarketInfoDatum = market_info_inline_datum
        expect is_market_info_datum_valid(market_info_datum)
        expect InlineDatum(market_inline_datum) = market_output.datum
        expect market_datum: MarketDatum = market_inline_datum
        expect is_market_datum_valid(market_datum)
        expect InlineDatum(sy_vault_inline_datum) = sy_vault_output.datum
        expect sy_vault_datum: SYVaultDatum = sy_vault_inline_datum
        expect is_sy_vault_datum_valid(sy_vault_datum)
        expect sy_vault_datum.market_id == params.market_id
        expect market_datum.market_id == params.market_id
        expect market_info_datum.market_id == params.market_id
        expect
          list.any(
            inputs,
            fn(input) { input.output_reference == params.market_id },
          )
        expect merged_mint == mint
        True
      }
      Burn -> {
        expect
          list.foldl(
            flatten(mint),
            True,
            fn(curr, acc) {
              let (_, _, quantity) = curr
              acc && quantity < 0
            },
          )
        list.has(extra_signatories, params.admin_pkh)
      }
    }
  }

  else(_) {
    False
  }
}

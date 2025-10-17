use aiken/collection/list
use aiken/collection/pairs
use cardano/assets.{PolicyId}
use cardano/transaction.{InlineDatum, OutputReference, Spend, Transaction}
use constants.{ytstake_authtoken_tn}
use types.{
  Asset, MarketInfoDatum, OracleDatum, SYUnstakeYT, SYVaultAdminAction,
  SYVaultDatum, SYVaultRedeemer, YTStake, YTStakeAuthTokenRedeemer, YTStakeDatum,
  YTUnstake,
}

pub type YTStakeAuthTokenParams {
  admin_pkh: ByteArray,
  market_id: OutputReference,
  market_info_nft: Asset,
  sy_nft: Asset,
}

validator ytstake_authtoken(params: YTStakeAuthTokenParams) {
  mint(
    redeemer: YTStakeAuthTokenRedeemer,
    policy_id: PolicyId,
    self: Transaction,
  ) {
    let Transaction { inputs, reference_inputs, outputs, mint, redeemers, .. } =
      self
    when redeemer is {
      YTStake {
        yt_stake_output_idx,
        seed_input_idx,
        market_info_ref_idx,
        oracle_idx,
      } -> {
        expect Some(market_info_ref_input) =
          list.at(reference_inputs, market_info_ref_idx)
        expect
          assets.quantity_of(
            market_info_ref_input.output.value,
            params.market_info_nft.policy_id,
            params.market_info_nft.asset_name,
          ) == 1
        expect InlineDatum(market_info_inline_datum) =
          market_info_ref_input.output.datum
        expect market_info_datum: MarketInfoDatum = market_info_inline_datum
        expect market_info_datum.market_id == params.market_id
        expect Some(oracle_ref_input) = list.at(reference_inputs, oracle_idx)
        expect InlineDatum(oracle_inline_datum) = oracle_ref_input.output.datum
        expect oracle_datum: OracleDatum = oracle_inline_datum
        expect
          assets.quantity_of(
            oracle_ref_input.output.value,
            market_info_datum.oracle_nft.policy_id,
            market_info_datum.oracle_nft.asset_name,
          ) == 1
        expect oracle_datum.py_index > 0 && oracle_datum.based > 0
        expect Some(seed_input) = list.at(inputs, seed_input_idx)
        expect Some(yt_stake_output) = list.at(outputs, yt_stake_output_idx)
        expect InlineDatum(yt_stake_inline_datum) = yt_stake_output.datum
        expect yt_stake_datum: YTStakeDatum = yt_stake_inline_datum
        expect yt_stake_datum.market_id == params.market_id
        expect yt_stake_datum.stake_id == seed_input.output_reference
        expect yt_stake_datum.staked_yt_amount > 0
        expect yt_stake_datum.py_index == oracle_datum.py_index
        expect
          assets.match(
            yt_stake_output.value,
            assets.from_lovelace(market_info_datum.envelope_amount)
              |> assets.add(policy_id, ytstake_authtoken_tn, 1)
              |> assets.add(
                  market_info_datum.yield_tokenization_policy_id,
                  market_info_datum.yt_token_name,
                  yt_stake_datum.staked_yt_amount,
                ),
            >=,
          )
        expect assets.flatten(mint) == [(policy_id, ytstake_authtoken_tn, 1)]
        True
      }
      YTUnstake { sy_in_idx } -> {
        expect Some(sy_vault_input) = list.at(inputs, sy_in_idx)
        expect InlineDatum(sy_inline_datum) = sy_vault_input.output.datum
        expect sy_datum: SYVaultDatum = sy_inline_datum
        expect sy_datum.market_id == params.market_id
        expect Some(wrap_sy_redeemer) =
          pairs.get_first(redeemers, Spend(sy_vault_input.output_reference))
        expect sy_redeemer: SYVaultRedeemer = wrap_sy_redeemer
        expect
          assets.quantity_of(
            sy_vault_input.output.value,
            params.sy_nft.policy_id,
            params.sy_nft.asset_name,
          ) == 1
        when sy_redeemer is {
          SYUnstakeYT { .. } -> True
          SYVaultAdminAction -> True
          _ -> False
        }
      }
    }
  }

  else(_) {
    fail
  }
}

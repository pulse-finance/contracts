use aiken/collection/list
use aiken/collection/pairs
use cardano/assets
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Spend, Transaction,
}
use types.{
  Asset, SYUnstakeYT, SYVaultAdminAction, SYVaultDatum, SYVaultRedeemer,
  SYWithdrawYTReward, YTStakeDatum,
}

pub type YTStakeRedeemer {
  sy_in_idx: Int,
}

pub type YTStakeParams {
  admin_pkh: ByteArray,
  market_id: OutputReference,
  sy_nft: Asset,
}

validator yt_stake(params: YTStakeParams) {
  spend(
    _option_datum: Option<YTStakeDatum>,
    redeemer: YTStakeRedeemer,
    _own_ref: OutputReference,
    self: Transaction,
  ) {
    let Transaction { inputs, redeemers, .. } = self
    expect Some(sy_vault_input) = list.at(inputs, redeemer.sy_in_idx)
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
      SYWithdrawYTReward { .. } -> True
      SYVaultAdminAction -> True
      _ -> False
    }
  }

  else(_) {
    False
  }
}

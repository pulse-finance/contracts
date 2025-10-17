use aiken/collection/list
use aiken/collection/pairs
use cardano/assets
use cardano/transaction.{
  InlineDatum, Input, Mint, Output, OutputReference, Transaction,
}
use types.{
  Asset, MarketDatum, OBurnLP, OInitLP, OMergeSY, OMintLP, OSplitSY, OStakeYT,
  OSwapExactPTForSY, OSwapExactSYForPT, OSwapExactSYForYT, OSwapExactYTForSY,
  OUnstakeYT, OUnwrapSY, OWithdrawYTReward, OWrapSY, OrderDatum, SYVaultDatum,
}
use utils.{validate_market_info_ref}

pub type OrderRedeemer {
  Apply {
    order_in_idx: Int,
    market_info_idx: Int,
    option_market_idx: Option<Int>,
    option_sy_vault_idx: Option<Int>,
  }
  Cancel { order_in_idx: Int }
}

pub type OrderParams {
  market_id: OutputReference,
  market_nft: Asset,
  market_info_nft: Asset,
  sy_nft: Asset,
}

validator order(params: OrderParams) {
  spend(
    _datum: Option<OrderDatum>,
    redeemer: OrderRedeemer,
    own_ref: OutputReference,
    self: Transaction,
  ) {
    let Transaction {
      inputs,
      reference_inputs,
      extra_signatories,
      redeemers,
      ..
    } = self
    when redeemer is {
      Apply {
        order_in_idx,
        market_info_idx,
        option_market_idx,
        option_sy_vault_idx,
      } -> {
        let market_info_datum =
          validate_market_info_ref(
            reference_inputs,
            market_info_idx,
            params.market_info_nft,
            params.market_id,
          )
        expect Some(order_input) = list.at(inputs, order_in_idx)
        expect order_input.output_reference == own_ref
        expect InlineDatum(order_inline_datum) = order_input.output.datum
        expect order_datum: OrderDatum = order_inline_datum
        when order_datum is {
          OWrapSY { .. } -> {
            expect Some(wrap_yt_mint_redeemer) =
              pairs.get_first(
                redeemers,
                Mint(market_info_datum.yield_tokenization_policy_id),
              )
            expect yt_mint_redeemer: types.YieldTokenizationMintRedeemer =
              wrap_yt_mint_redeemer
            expect
              when yt_mint_redeemer is {
                types.YTWrapSY { .. } -> True
                types.YTRefTokenAction { .. } -> True
                _ -> False
              }
            True
          }
          OUnwrapSY { .. } -> {
            expect Some(wrap_yt_mint_redeemer) =
              pairs.get_first(
                redeemers,
                Mint(market_info_datum.yield_tokenization_policy_id),
              )
            expect yt_mint_redeemer: types.YieldTokenizationMintRedeemer =
              wrap_yt_mint_redeemer
            expect
              when yt_mint_redeemer is {
                types.YTUnwrapSY { .. } -> True
                types.YTRefTokenAction { .. } -> True
                _ -> False
              }
            True
          }
          OSplitSY { .. } -> {
            expect Some(wrap_yt_mint_redeemer) =
              pairs.get_first(
                redeemers,
                Mint(market_info_datum.yield_tokenization_policy_id),
              )
            expect yt_mint_redeemer: types.YieldTokenizationMintRedeemer =
              wrap_yt_mint_redeemer
            expect
              when yt_mint_redeemer is {
                types.YTSplitSY { .. } -> True
                types.YTRefTokenAction { .. } -> True
                _ -> False
              }
            True
          }
          OMergeSY { .. } -> {
            expect Some(wrap_yt_mint_redeemer) =
              pairs.get_first(
                redeemers,
                Mint(market_info_datum.yield_tokenization_policy_id),
              )
            expect yt_mint_redeemer: types.YieldTokenizationMintRedeemer =
              wrap_yt_mint_redeemer
            expect
              when yt_mint_redeemer is {
                types.YTMergeSY { .. } -> True
                types.YTRefTokenAction { .. } -> True
                _ -> False
              }
            True
          }
          OInitLP { .. } -> {
            expect Some(wrap_lp_mint_redeemer) =
              pairs.get_first(
                redeemers,
                Mint(market_info_datum.lp_token_asset.policy_id),
              )
            expect lp_mint_redeemer: types.LPTokenRedeemer =
              wrap_lp_mint_redeemer
            expect
              when lp_mint_redeemer is {
                types.LPInitLp { .. } -> True
                types.LPRefTokenAction { .. } -> True
                _ -> False
              }
            True
          }
          OMintLP { .. } -> {
            expect Some(wrap_lp_mint_redeemer) =
              pairs.get_first(
                redeemers,
                Mint(market_info_datum.lp_token_asset.policy_id),
              )
            expect lp_mint_redeemer: types.LPTokenRedeemer =
              wrap_lp_mint_redeemer
            expect
              when lp_mint_redeemer is {
                types.LPMintLp { .. } -> True
                types.LPRefTokenAction { .. } -> True
                _ -> False
              }
            True
          }
          OBurnLP { .. } -> {
            expect Some(wrap_lp_mint_redeemer) =
              pairs.get_first(
                redeemers,
                Mint(market_info_datum.lp_token_asset.policy_id),
              )
            expect lp_mint_redeemer: types.LPTokenRedeemer =
              wrap_lp_mint_redeemer
            expect
              when lp_mint_redeemer is {
                types.LPBurnLp { .. } -> True
                types.LPRefTokenAction { .. } -> True
                _ -> False
              }
            True
          }
          OSwapExactSYForPT { .. } -> {
            expect Some(market_input_idx) = option_market_idx
            expect Some(market_input) = list.at(inputs, market_input_idx)
            expect InlineDatum(market_inline_datum) = market_input.output.datum
            expect market_datum: MarketDatum = market_inline_datum
            expect market_datum.market_id == params.market_id
            assets.quantity_of(
              market_input.output.value,
              params.market_nft.policy_id,
              params.market_nft.asset_name,
            ) == 1
          }
          OSwapExactPTForSY { .. } -> {
            expect Some(market_input_idx) = option_market_idx
            expect Some(market_input) = list.at(inputs, market_input_idx)
            expect InlineDatum(market_inline_datum) = market_input.output.datum
            expect market_datum: MarketDatum = market_inline_datum
            expect market_datum.market_id == params.market_id
            assets.quantity_of(
              market_input.output.value,
              params.market_nft.policy_id,
              params.market_nft.asset_name,
            ) == 1
          }
          OSwapExactSYForYT { .. } -> {
            expect Some(wrap_yt_mint_redeemer) =
              pairs.get_first(
                redeemers,
                Mint(market_info_datum.yield_tokenization_policy_id),
              )
            expect yt_mint_redeemer: types.YieldTokenizationMintRedeemer =
              wrap_yt_mint_redeemer
            expect
              when yt_mint_redeemer is {
                types.YTSwapSYForYT { .. } -> True
                types.YTRefTokenAction { .. } -> True
                _ -> False
              }
            True
          }
          OSwapExactYTForSY { .. } -> {
            expect Some(wrap_yt_mint_redeemer) =
              pairs.get_first(
                redeemers,
                Mint(market_info_datum.yield_tokenization_policy_id),
              )
            expect yt_mint_redeemer: types.YieldTokenizationMintRedeemer =
              wrap_yt_mint_redeemer
            expect
              when yt_mint_redeemer is {
                types.YTSwapYTForSY { .. } -> True
                types.YTRefTokenAction { .. } -> True
                _ -> False
              }
            True
          }
          OStakeYT { .. } -> {
            expect Some(wrap_ytstake_authtoken_mint_redeemer) =
              pairs.get_first(
                redeemers,
                Mint(market_info_datum.ytstake_authtoken_policy_id),
              )
            expect ytstake_authtoken_mint_redeemer: types.YTStakeAuthTokenRedeemer =
              wrap_ytstake_authtoken_mint_redeemer
            expect
              when ytstake_authtoken_mint_redeemer is {
                types.YTStake { .. } -> True
                _ -> False
              }
            True
          }
          OWithdrawYTReward { .. } -> {
            expect Some(sy_vault_input_idx) = option_sy_vault_idx
            expect Some(sy_vault_input) = list.at(inputs, sy_vault_input_idx)
            expect InlineDatum(sy_vault_inline_datum) =
              sy_vault_input.output.datum
            expect sy_vault_datum: SYVaultDatum = sy_vault_inline_datum
            expect sy_vault_datum.market_id == params.market_id
            assets.quantity_of(
              sy_vault_input.output.value,
              params.sy_nft.policy_id,
              params.sy_nft.asset_name,
            ) == 1
          }
          OUnstakeYT { .. } -> {
            expect Some(wrap_ytstake_authtoken_mint_redeemer) =
              pairs.get_first(
                redeemers,
                Mint(market_info_datum.ytstake_authtoken_policy_id),
              )
            expect ytstake_authtoken_mint_redeemer: types.YTStakeAuthTokenRedeemer =
              wrap_ytstake_authtoken_mint_redeemer
            expect
              when ytstake_authtoken_mint_redeemer is {
                types.YTUnstake { .. } -> True
                _ -> False
              }
            True
          }
        }
      }
      Cancel { order_in_idx } -> {
        expect Some(order_input) = list.at(inputs, order_in_idx)
        expect order_input.output_reference == own_ref
        expect InlineDatum(order_inline_datum) = order_input.output.datum
        expect order_datum: OrderDatum = order_inline_datum
        when order_datum is {
          OWrapSY { o_market_id, o_owner_pkh, .. } -> {
            expect o_market_id == params.market_id
            list.has(extra_signatories, o_owner_pkh)
          }
          OUnwrapSY { o_market_id, o_owner_pkh, .. } -> {
            expect o_market_id == params.market_id
            list.has(extra_signatories, o_owner_pkh)
          }
          OSplitSY { o_market_id, o_owner_pkh, .. } -> {
            expect o_market_id == params.market_id
            list.has(extra_signatories, o_owner_pkh)
          }
          OMergeSY { o_market_id, o_owner_pkh, .. } -> {
            expect o_market_id == params.market_id
            list.has(extra_signatories, o_owner_pkh)
          }
          OInitLP { o_market_id, o_owner_pkh, .. } -> {
            expect o_market_id == params.market_id
            list.has(extra_signatories, o_owner_pkh)
          }
          OMintLP { o_market_id, o_owner_pkh, .. } -> {
            expect o_market_id == params.market_id
            list.has(extra_signatories, o_owner_pkh)
          }
          OBurnLP { o_market_id, o_owner_pkh, .. } -> {
            expect o_market_id == params.market_id
            list.has(extra_signatories, o_owner_pkh)
          }
          OSwapExactSYForPT { o_market_id, o_owner_pkh, .. } -> {
            expect o_market_id == params.market_id
            list.has(extra_signatories, o_owner_pkh)
          }
          OSwapExactPTForSY { o_market_id, o_owner_pkh, .. } -> {
            expect o_market_id == params.market_id
            list.has(extra_signatories, o_owner_pkh)
          }
          OSwapExactSYForYT { o_market_id, o_owner_pkh, .. } -> {
            expect o_market_id == params.market_id
            list.has(extra_signatories, o_owner_pkh)
          }
          OSwapExactYTForSY { o_market_id, o_owner_pkh, .. } -> {
            expect o_market_id == params.market_id
            list.has(extra_signatories, o_owner_pkh)
          }
          OStakeYT { o_market_id, o_owner_pkh, .. } -> {
            expect o_market_id == params.market_id
            list.has(extra_signatories, o_owner_pkh)
          }
          OWithdrawYTReward { o_market_id, o_owner_pkh, .. } -> {
            expect o_market_id == params.market_id
            list.has(extra_signatories, o_owner_pkh)
          }
          OUnstakeYT { o_market_id, o_owner_pkh, .. } -> {
            expect o_market_id == params.market_id
            list.has(extra_signatories, o_owner_pkh)
          }
        }
      }
    }
  }

  else(_) {
    False
  }
}

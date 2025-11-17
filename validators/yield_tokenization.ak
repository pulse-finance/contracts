use aiken/collection/dict
use aiken/collection/list
use aiken/collection/pairs
use cardano/assets.{PolicyId, flatten}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Spend, Transaction,
}
use pulse_math
use types.{
  Asset, MarketDatum, MarketInfoDatum, MarketRedeemer, OSwapExactSYForYT,
  OSwapExactYTForSY, OracleDatum, OrderDatum, PubKeyHash, SYVaultMergeSY,
  SYVaultRedeemer, SYVaultSplitSY, YTBurn, YTMergeSY, YTRefTokenAction,
  YTSplitSY, YTSwapSYForYT, YTSwapYTForSY, YieldTokenizationMintRedeemer,
}
use utils.{
  check_correct_input_payment_credential, count_input_orders,
  validate_license_and_expiry, validate_market_info_ref, validate_market_utxos,
  validate_oracle_ref,
}

pub type UnderlyingAssetVaultRedeemer {
  YAVaultWrapSY { own_input_idx: Int }
  YAVaultUnwrapSY { own_input_idx: Int }
  YAVaultAdminAction
}

pub type YieldTokenizationParams {
  admin_pkh: PubKeyHash,
  market_id: OutputReference,
  market_nft: Asset,
  market_info_nft: Asset,
  sy_nft: Asset,
}

validator yield_tokenization(params: YieldTokenizationParams) {
  mint(
    redeemer: YieldTokenizationMintRedeemer,
    policy_id: PolicyId,
    self: Transaction,
  ) {
    let Transaction {
      inputs,
      reference_inputs,
      outputs,
      mint,
      extra_signatories,
      validity_range,
      redeemers,
      ..
    } = self
    when redeemer is {
      YTSplitSY { sy_vault_input_idx } -> {
        expect Some(sy_vault_input) = list.at(inputs, sy_vault_input_idx)
        expect
          assets.quantity_of(
            sy_vault_input.output.value,
            params.sy_nft.policy_id,
            params.sy_nft.asset_name,
          ) == 1
        expect Some(wrap_mint_redeemer) =
          pairs.get_first(redeemers, Spend(sy_vault_input.output_reference))
        expect sy_vault_redeemer: SYVaultRedeemer = wrap_mint_redeemer
        when sy_vault_redeemer is {
          SYVaultSplitSY { .. } -> True
          _ -> False
        }
      }
      YTMergeSY { sy_vault_input_idx } -> {
        expect Some(sy_vault_input) = list.at(inputs, sy_vault_input_idx)
        expect
          assets.quantity_of(
            sy_vault_input.output.value,
            params.sy_nft.policy_id,
            params.sy_nft.asset_name,
          ) == 1
        expect Some(wrap_mint_redeemer) =
          pairs.get_first(redeemers, Spend(sy_vault_input.output_reference))
        expect sy_vault_redeemer: SYVaultRedeemer = wrap_mint_redeemer
        when sy_vault_redeemer is {
          SYVaultMergeSY { .. } -> True
          _ -> False
        }
      }
      YTSwapSYForYT {
        market_info_ref_idx,
        order_indices,
        oracle_idx,
        license_idx,
        market_input_idx,
        market_output_idx,
        borrowed_sy,
      } -> {
        let (
          market_input,
          market_output,
          market_input_datum,
          market_output_datum,
        ) =
          validate_market_utxos(
            inputs,
            outputs,
            market_input_idx,
            market_output_idx,
            params.market_nft,
            params.market_id,
          )
        expect Some(wrap_market_redeemer) =
          pairs.get_first(redeemers, Spend(market_input.output_reference))
        expect market_redeemer: MarketRedeemer = wrap_market_redeemer
        expect
          when market_redeemer is {
            types.MSwapExactSYForYT { .. } -> True
            types.MAdminOperation -> True
            _ -> False
          }
        let market_info_datum =
          validate_market_info_ref(
            reference_inputs,
            market_info_ref_idx,
            params.market_info_nft,
            params.market_id,
          )
        let end_valid_time_range =
          validate_license_and_expiry(
            inputs,
            license_idx,
            market_info_datum.batcher_policy_id,
            validity_range,
            market_info_datum.expiry,
          )
        let oracle_datum =
          validate_oracle_ref(
            reference_inputs,
            oracle_idx,
            market_info_datum.oracle_nft,
          )
        expect
          count_input_orders(inputs, market_info_datum.order_script_hash) == 1
        expect Some(in) = list.at(inputs, order_indices.1st)
        expect Some(out) = list.at(outputs, order_indices.2nd)
        expect
          check_correct_input_payment_credential(
            in,
            market_info_datum.order_script_hash,
          )
        expect InlineDatum(order_inline_datum) = in.output.datum
        expect order_datum: OrderDatum = order_inline_datum
        expect OSwapExactSYForYT {
          o_receive_addr,
          o_receive_datum,
          o_min_yt_out,
          ..
        } = order_datum
        expect out.address == o_receive_addr
        expect out.datum == o_receive_datum
        let sy_amount =
          assets.quantity_of(
            in.output.value,
            market_info_datum.underlying_asset.policy_id,
            market_info_datum.underlying_asset.asset_name,
          )
        expect list.length(assets.flatten(in.output.value)) == 2
        let yt_amount =
          assets.quantity_of(
            out.value,
            market_info_datum.yield_tokenization_policy_id,
            market_info_datum.yt_token_name,
          )
        expect yt_amount >= o_min_yt_out

        // Validate swap using new price model with fees/slippage (Section 2.5.3)
        expect
          pulse_math.validate_sy_to_yt_swap(
            sy_amount,
            borrowed_sy,
            yt_amount,
            market_input_datum.total_pt,
            market_input_datum.total_sy,
            oracle_datum.py_index,
            market_info_datum.init_py_index,
            market_info_datum.scalar_root,
            market_info_datum.initial_anchor,
            market_info_datum.ln_fee_rate_root,
            market_info_datum.ln_borrow_fee_rate,
            market_info_datum.expiry,
            end_valid_time_range,
            market_info_datum.duration,
            oracle_datum.based,
          )
        // Market state changes per spec Section 2.5.3:
        // - PT: gains yt_amount from split
        // - SY datum: -borrowed_sy
        // - SY assets: -borrowed_sy
        expect
          market_output_datum.total_pt == market_input_datum.total_pt + yt_amount
        expect
          market_output_datum.total_sy == market_input_datum.total_sy - borrowed_sy
        expect market_output_datum.total_lp == market_input_datum.total_lp
        expect market_output_datum.reserved_lp == market_input_datum.reserved_lp
        let num_token =
          mint |> assets.tokens(policy_id) |> dict.keys() |> list.length()
        expect num_token == 2
        let total_pt_minted = yt_amount
        expect total_pt_minted > 0
        expect
          assets.quantity_of(mint, policy_id, market_info_datum.pt_token_name) == total_pt_minted
        expect
          assets.quantity_of(mint, policy_id, market_info_datum.yt_token_name) == total_pt_minted
        expect
          assets.match(
            market_output.value,
            market_input.output.value
              |> assets.add(
                  market_info_datum.underlying_asset.policy_id,
                  market_info_datum.underlying_asset.asset_name,
                  -borrowed_sy,
                )
              |> assets.add(
                  policy_id,
                  market_info_datum.pt_token_name,
                  total_pt_minted,
                ),
            >=,
          )
        True
      }
      YTSwapYTForSY {
        market_info_ref_idx,
        order_indices,
        oracle_idx,
        license_idx,
        market_input_idx,
        market_output_idx,
        swapped_sy,
      } -> {
        let (
          market_input,
          market_output,
          market_input_datum,
          market_output_datum,
        ) =
          validate_market_utxos(
            inputs,
            outputs,
            market_input_idx,
            market_output_idx,
            params.market_nft,
            params.market_id,
          )
        expect Some(wrap_market_redeemer) =
          pairs.get_first(redeemers, Spend(market_input.output_reference))
        expect market_redeemer: MarketRedeemer = wrap_market_redeemer
        expect
          when market_redeemer is {
            types.MSwapExactYTForSY { .. } -> True
            types.MAdminOperation -> True
            _ -> False
          }
        let market_info_datum =
          validate_market_info_ref(
            reference_inputs,
            market_info_ref_idx,
            params.market_info_nft,
            params.market_id,
          )
        let end_valid_time_range =
          validate_license_and_expiry(
            inputs,
            license_idx,
            market_info_datum.batcher_policy_id,
            validity_range,
            market_info_datum.expiry,
          )
        let oracle_datum =
          validate_oracle_ref(
            reference_inputs,
            oracle_idx,
            market_info_datum.oracle_nft,
          )
        expect
          count_input_orders(inputs, market_info_datum.order_script_hash) == 1
        expect Some(in) = list.at(inputs, order_indices.1st)
        expect Some(out) = list.at(outputs, order_indices.2nd)
        expect
          check_correct_input_payment_credential(
            in,
            market_info_datum.order_script_hash,
          )
        expect InlineDatum(order_inline_datum) = in.output.datum
        expect order_datum: OrderDatum = order_inline_datum
        expect OSwapExactYTForSY {
          o_receive_addr,
          o_receive_datum,
          o_min_sy_out,
          ..
        } = order_datum
        expect out.address == o_receive_addr
        expect out.datum == o_receive_datum
        let yt_amount =
          assets.quantity_of(
            in.output.value,
            policy_id,
            market_info_datum.yt_token_name,
          )
        expect list.length(assets.flatten(in.output.value)) == 2
        let pt_amount = yt_amount

        let sy_out =
          assets.quantity_of(
            out.value,
            market_info_datum.underlying_asset.policy_id,
            market_info_datum.underlying_asset.asset_name,
          )

        expect sy_out >= o_min_sy_out

        // Validate swap using new price model with fees/slippage (Section 2.5.4)
        expect
          pulse_math.validate_yt_to_sy_swap(
            yt_amount,
            swapped_sy,
            sy_out,
            market_input_datum.total_pt,
            market_input_datum.total_sy,
            oracle_datum.py_index,
            market_info_datum.init_py_index,
            market_info_datum.scalar_root,
            market_info_datum.initial_anchor,
            market_info_datum.ln_fee_rate_root,
            market_info_datum.ln_borrow_fee_rate,
            market_info_datum.expiry,
            end_valid_time_range,
            market_info_datum.duration,
            oracle_datum.based,
          )
        // Market state changes per spec Section 2.5.4:
        // Logical: borrow PT, merge PT+YT→SY, swap some SY back
        // Physical: burn PT+YT, send SY to user
        // - PT datum: -pt_amount (burned with YT)
        // - PT assets: -pt_amount (burned)
        // - SY datum: +swapped_sy
        // - SY assets: +swapped_sy
        let output_datum_total_pt = market_input_datum.total_pt - pt_amount
        let output_datum_total_sy = market_input_datum.total_sy + swapped_sy
        expect market_output_datum.total_pt == output_datum_total_pt
        expect market_output_datum.total_sy == output_datum_total_sy
        expect market_output_datum.total_lp == market_input_datum.total_lp
        expect market_output_datum.reserved_lp == market_input_datum.reserved_lp
        let num_token =
          mint |> assets.tokens(policy_id) |> dict.keys() |> list.length()
        expect num_token == 2
        // Market must lose SY (send to user)
        let total_pt_burned = pt_amount
        expect total_pt_burned > 0
        expect
          assets.quantity_of(mint, policy_id, market_info_datum.pt_token_name) == -total_pt_burned
        expect
          assets.quantity_of(mint, policy_id, market_info_datum.yt_token_name) == -total_pt_burned
        expect
          assets.match(
            market_output.value,
            market_input.output.value
              |> assets.add(
                  market_info_datum.underlying_asset.policy_id,
                  market_info_datum.underlying_asset.asset_name,
                  swapped_sy,
                )
              |> assets.add(
                  policy_id,
                  market_info_datum.pt_token_name,
                  -total_pt_burned,
                ),
            >=,
          )
        True
      }
      YTBurn -> {
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
      YTRefTokenAction -> list.has(extra_signatories, params.admin_pkh)
    }
  }

  else(_) {
    False
  }
}

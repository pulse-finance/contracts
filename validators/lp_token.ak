use aiken/collection/list
use aiken/collection/pairs
use aiken/math
use cardano/address.{Script}
use cardano/assets.{PolicyId}
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Spend, Transaction,
}
use types.{
  Asset, LPBurnLp, LPInitLp, LPMintLp, LPRefTokenAction, LPTokenRedeemer,
  MarketDatum, MarketInfoDatum, MarketRedeemer, OBurnLP, OInitLP, OMintLP,
  OrderDatum,
}
use utils.{
  check_correct_input_payment_credential, construct_address, count_input_orders,
  validate_license_and_expiry, validate_market_info_ref, validate_market_utxos,
}

pub type LPTokenParams {
  admin_pkh: ByteArray,
  market_id: OutputReference,
  market_nft: Asset,
  market_info_nft: Asset,
}

validator lp_token(params: LPTokenParams) {
  mint(redeemer: LPTokenRedeemer, policy_id: PolicyId, self: Transaction) {
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
      LPInitLp {
        market_info_ref_idx,
        order_indices,
        license_idx,
        market_input_idx,
        market_output_idx,
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
        expect market_input_datum.total_lp == 0
        expect Some(wrap_market_redeemer) =
          pairs.get_first(redeemers, Spend(market_input.output_reference))
        expect market_redeemer: MarketRedeemer = wrap_market_redeemer
        expect
          when market_redeemer is {
            types.MInitLp { .. } -> True
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
        expect _end_valid_time_range =
          validate_license_and_expiry(
            inputs,
            license_idx,
            market_info_datum.batcher_policy_id,
            validity_range,
            market_info_datum.expiry,
          )
        expect
          count_input_orders(inputs, market_info_datum.order_script_hash) == 1
        expect Some(in) = list.at(inputs, order_indices.1st)
        expect Some(out) = list.at(outputs, order_indices.2nd)
        expect
          in.output.address.payment_credential == Script(
            market_info_datum.order_script_hash,
          )
        expect InlineDatum(order_input_inline_datum) = in.output.datum
        expect order_datum: OrderDatum = order_input_inline_datum
        expect OInitLP { o_owner_pkh, o_owner_stake_key } = order_datum
        let user_address = construct_address(o_owner_pkh, o_owner_stake_key)
        expect out.address == user_address
        let sy_amount =
          assets.quantity_of(
            in.output.value,
            market_info_datum.underlying_asset.policy_id,
            market_info_datum.underlying_asset.asset_name,
          )
        let pt_amount =
          assets.quantity_of(
            in.output.value,
            market_info_datum.yield_tokenization_policy_id,
            market_info_datum.pt_token_name,
          )
        expect list.length(assets.flatten(in.output.value)) == 3
        let lp_to_account =
          assets.quantity_of(
            out.value,
            policy_id,
            market_info_datum.lp_token_asset.asset_name,
          )
        expect
          math.is_sqrt(
            sy_amount * pt_amount,
            lp_to_account + market_info_datum.min_liquidity,
          )
        let lp_to_reserve = market_info_datum.min_liquidity
        expect
          market_output_datum.total_sy == market_input_datum.total_sy + sy_amount
        expect
          market_output_datum.total_pt == market_input_datum.total_pt + pt_amount
        expect market_output_datum.total_lp == lp_to_account + lp_to_reserve
        expect market_output_datum.reserved_lp == lp_to_reserve
        expect
          mint == assets.from_asset(
            policy_id,
            market_info_datum.lp_token_asset.asset_name,
            lp_to_account + lp_to_reserve,
          )
        expect
          assets.match(
            market_output.value,
            market_input.output.value
              |> assets.add(
                  market_info_datum.underlying_asset.policy_id,
                  market_info_datum.underlying_asset.asset_name,
                  sy_amount,
                )
              |> assets.add(
                  market_info_datum.yield_tokenization_policy_id,
                  market_info_datum.pt_token_name,
                  pt_amount,
                )
              |> assets.add(
                  policy_id,
                  market_info_datum.lp_token_asset.asset_name,
                  lp_to_reserve,
                ),
            >=,
          )
        True
      }
      LPMintLp {
        market_info_ref_idx,
        order_indices,
        license_idx,
        market_input_idx,
        market_output_idx,
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
        expect market_input_datum.total_lp > 0
        expect Some(wrap_market_redeemer) =
          pairs.get_first(redeemers, Spend(market_input.output_reference))
        expect market_redeemer: MarketRedeemer = wrap_market_redeemer
        expect
          when market_redeemer is {
            types.MMintLp { .. } -> True
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
        expect _end_valid_time_range =
          validate_license_and_expiry(
            inputs,
            license_idx,
            market_info_datum.batcher_policy_id,
            validity_range,
            market_info_datum.expiry,
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
        expect InlineDatum(order_input_inline_datum) = in.output.datum
        expect order_datum: OrderDatum = order_input_inline_datum
        expect OMintLP { o_owner_pkh: _, o_receive_addr, o_receive_datum } =
          order_datum
        expect out.address == o_receive_addr
        expect out.datum == o_receive_datum
        let sy_amount =
          assets.quantity_of(
            in.output.value,
            market_info_datum.underlying_asset.policy_id,
            market_info_datum.underlying_asset.asset_name,
          )
        let pt_amount =
          assets.quantity_of(
            in.output.value,
            market_info_datum.yield_tokenization_policy_id,
            market_info_datum.pt_token_name,
          )
        let net_lp_by_pt =
          pt_amount * market_input_datum.total_lp / market_input_datum.total_pt
        let net_lp_by_sy =
          sy_amount * market_input_datum.total_lp / market_input_datum.total_sy
        let (lp_to_account, sy_used, pt_used) =
          if net_lp_by_pt < net_lp_by_sy {
            (
              net_lp_by_pt,
              net_lp_by_pt * market_input_datum.total_sy / market_input_datum.total_lp,
              pt_amount,
            )
          } else {
            (
              net_lp_by_sy,
              sy_amount,
              net_lp_by_sy * market_input_datum.total_pt / market_input_datum.total_lp,
            )
          }
        expect
          assets.match(
            out.value,
            assets.zero
              |> assets.add(
                  policy_id,
                  market_info_datum.lp_token_asset.asset_name,
                  lp_to_account,
                )
              |> assets.add(
                  market_info_datum.underlying_asset.policy_id,
                  market_info_datum.underlying_asset.asset_name,
                  sy_amount - sy_used,
                )
              |> assets.add(
                  market_info_datum.yield_tokenization_policy_id,
                  market_info_datum.pt_token_name,
                  pt_amount - pt_used,
                ),
            >=,
          )
        expect
          market_output_datum.total_sy == market_input_datum.total_sy + sy_used
        expect
          market_output_datum.total_pt == market_input_datum.total_pt + pt_used
        expect
          market_output_datum.total_lp == market_input_datum.total_lp + lp_to_account
        expect market_output_datum.reserved_lp == market_input_datum.reserved_lp
        expect
          mint == assets.from_asset(
            policy_id,
            market_info_datum.lp_token_asset.asset_name,
            lp_to_account,
          )
        expect
          assets.match(
            market_output.value,
            market_input.output.value
              |> assets.add(
                  market_info_datum.underlying_asset.policy_id,
                  market_info_datum.underlying_asset.asset_name,
                  sy_used,
                )
              |> assets.add(
                  market_info_datum.yield_tokenization_policy_id,
                  market_info_datum.pt_token_name,
                  pt_used,
                ),
            >=,
          )
        True
      }
      LPBurnLp {
        market_info_ref_idx,
        order_indices,
        license_idx,
        market_input_idx,
        market_output_idx,
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
            types.MBurnLp { .. } -> True
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
        expect _end_valid_time_range =
          validate_license_and_expiry(
            inputs,
            license_idx,
            market_info_datum.batcher_policy_id,
            validity_range,
            market_info_datum.expiry,
          )
        expect
          count_input_orders(inputs, market_info_datum.order_script_hash) == 1
        expect Some(in) = list.at(inputs, order_indices.1st)
        expect Some(sy_out) = list.at(outputs, order_indices.2nd)
        expect Some(pt_out) = list.at(outputs, order_indices.3rd)
        expect
          check_correct_input_payment_credential(
            in,
            market_info_datum.order_script_hash,
          )
        expect InlineDatum(order_input_inline_datum) = in.output.datum
        expect order_datum: OrderDatum = order_input_inline_datum
        expect OBurnLP {
          o_owner_pkh: _,
          o_receive_sy_addr,
          o_receive_sy_datum,
          o_receive_pt_addr,
          o_receive_pt_datum,
        } = order_datum
        expect sy_out.address == o_receive_sy_addr
        expect sy_out.datum == o_receive_sy_datum
        expect pt_out.address == o_receive_pt_addr
        expect pt_out.datum == o_receive_pt_datum
        let lp_amount =
          assets.quantity_of(
            in.output.value,
            policy_id,
            market_info_datum.lp_token_asset.asset_name,
          )
        expect list.length(assets.flatten(in.output.value)) == 2
        let sy_to_account =
          lp_amount * market_input_datum.total_sy / market_input_datum.total_lp
        let pt_to_account =
          lp_amount * market_input_datum.total_pt / market_input_datum.total_lp
        expect sy_to_account > 0 && pt_to_account > 0
        expect
          assets.match(
            sy_out.value,
            assets.zero
              |> assets.add(
                  assets.ada_policy_id,
                  assets.ada_asset_name,
                  market_info_datum.envelope_amount,
                )
              |> assets.add(
                  market_info_datum.underlying_asset.policy_id,
                  market_info_datum.underlying_asset.asset_name,
                  sy_to_account,
                ),
            >=,
          )
        expect
          assets.match(
            pt_out.value,
            assets.zero
              |> assets.add(
                  assets.ada_policy_id,
                  assets.ada_asset_name,
                  market_info_datum.envelope_amount,
                )
              |> assets.add(
                  market_info_datum.yield_tokenization_policy_id,
                  market_info_datum.pt_token_name,
                  pt_to_account,
                ),
            >=,
          )
        let output_datum_total_pt = market_input_datum.total_pt - pt_to_account
        let output_datum_total_sy = market_input_datum.total_sy - sy_to_account
        let output_datum_total_lp = market_input_datum.total_lp - lp_amount
        expect output_datum_total_lp >= 0
        expect output_datum_total_sy >= 0
        expect output_datum_total_pt >= 0
        expect market_output_datum.total_sy == output_datum_total_sy
        expect market_output_datum.total_pt == output_datum_total_pt
        expect market_output_datum.total_lp == output_datum_total_lp
        expect market_output_datum.reserved_lp == market_input_datum.reserved_lp
        let total_burned_lp = lp_amount
        expect total_burned_lp > 0
        expect
          mint == assets.from_asset(
            policy_id,
            market_info_datum.lp_token_asset.asset_name,
            -total_burned_lp,
          )
        expect
          assets.match(
            market_output.value,
            market_input.output.value
              |> assets.add(
                  market_info_datum.underlying_asset.policy_id,
                  market_info_datum.underlying_asset.asset_name,
                  output_datum_total_sy - market_input_datum.total_sy,
                )
              |> assets.add(
                  market_info_datum.yield_tokenization_policy_id,
                  market_info_datum.pt_token_name,
                  output_datum_total_pt - market_input_datum.total_pt,
                ),
            >=,
          )
        True
      }
      LPRefTokenAction -> list.has(extra_signatories, params.admin_pkh)
    }
  }

  else(_) {
    fail
  }
}

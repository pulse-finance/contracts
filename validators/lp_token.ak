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
  validate_license_and_expiry, validate_market_info_ref,
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
        expect Some(market_input) = list.at(inputs, market_input_idx)
        expect Some(market_output) = list.at(outputs, market_output_idx)
        expect
          assets.quantity_of(
            market_input.output.value,
            params.market_nft.policy_id,
            params.market_nft.asset_name,
          ) == 1
        expect InlineDatum(market_input_inline_datum) =
          market_input.output.datum
        expect market_input_datum: MarketDatum = market_input_inline_datum
        expect market_input_datum.market_id == params.market_id
        expect InlineDatum(market_output_inline_datum) = market_output.datum
        expect market_output_datum: MarketDatum = market_output_inline_datum
        expect market_input_datum.market_id == market_output_datum.market_id
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
        expect Some(in) = list.at(inputs, order_indices.1st)
        expect Some(out) = list.at(outputs, order_indices.2nd)
        expect
          in.output.address.payment_credential == Script(
            market_info_datum.order_script_hash,
          )
        expect InlineDatum(order_input_inline_datum) = in.output.datum
        expect order_datum: OrderDatum = order_input_inline_datum
        expect OInitLP {
          o_market_id,
          o_owner_pkh,
          o_owner_stake_key,
          o_batcher_fee,
          o_sy_desired_amount,
          o_pt_desired_amount,
          o_lp_to_account,
        } = order_datum
        expect o_market_id == params.market_id
        let user_address = construct_address(o_owner_pkh, o_owner_stake_key)
        expect out.address == user_address
        expect
          o_sy_desired_amount > 0 && o_pt_desired_amount > 0 && o_lp_to_account > 0 && o_batcher_fee >= 0
        expect
          assets.quantity_of(
            in.output.value,
            market_info_datum.yield_tokenization_policy_id,
            market_info_datum.sy_token_name,
          ) >= o_sy_desired_amount
        expect
          assets.quantity_of(
            in.output.value,
            market_info_datum.yield_tokenization_policy_id,
            market_info_datum.pt_token_name,
          ) >= o_pt_desired_amount
        let in_lovelace = assets.lovelace_of(in.output.value)
        let min_lovelace = o_batcher_fee + market_info_datum.envelope_amount * 2
        expect in_lovelace >= min_lovelace
        expect list.length(assets.flatten(in.output.value)) == 3
        expect
          assets.flatten(out.value) == [
            (
              assets.ada_policy_id,
              assets.ada_asset_name,
              market_info_datum.envelope_amount,
            ),
            (
              policy_id,
              market_info_datum.lp_token_asset.asset_name,
              o_lp_to_account,
            ),
          ]
        expect
          math.is_sqrt(
            o_sy_desired_amount * o_pt_desired_amount,
            o_lp_to_account + market_info_datum.min_liquidity,
          )
        let lp_to_reserve = market_info_datum.min_liquidity
        let sy_used = o_sy_desired_amount
        let pt_used = o_pt_desired_amount
        expect
          market_output_datum.total_sy == market_input_datum.total_sy + sy_used
        expect
          market_output_datum.total_pt == market_input_datum.total_pt + pt_used
        expect market_output_datum.total_lp == o_lp_to_account + lp_to_reserve
        expect market_output_datum.reserved_lp == lp_to_reserve
        expect market_output_datum.total_fee == market_input_datum.total_fee
        expect
          market_output_datum.last_ln_implied_rate == market_info_datum.initial_anchor
        expect
          mint == assets.from_asset(
            policy_id,
            market_info_datum.lp_token_asset.asset_name,
            o_lp_to_account + lp_to_reserve,
          )
        expect
          assets.match(
            market_output.value,
            market_input.output.value
              |> assets.add(
                  market_info_datum.yield_tokenization_policy_id,
                  market_info_datum.sy_token_name,
                  sy_used,
                )
              |> assets.add(
                  market_info_datum.yield_tokenization_policy_id,
                  market_info_datum.pt_token_name,
                  pt_used,
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
        expect Some(market_input) = list.at(inputs, market_input_idx)
        expect Some(market_output) = list.at(outputs, market_output_idx)
        expect
          assets.quantity_of(
            market_input.output.value,
            params.market_nft.policy_id,
            params.market_nft.asset_name,
          ) == 1
        expect InlineDatum(market_input_inline_datum) =
          market_input.output.datum
        expect market_input_datum: MarketDatum = market_input_inline_datum
        expect market_input_datum.market_id == params.market_id
        expect market_input_datum.total_lp > 0
        expect InlineDatum(market_output_inline_datum) = market_output.datum
        expect market_output_datum: MarketDatum = market_output_inline_datum
        expect market_input_datum.market_id == market_output_datum.market_id
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
          count_input_orders(inputs, market_info_datum.order_script_hash) == list.length(
            order_indices,
          )
        let (
          output_datum_total_pt,
          output_datum_total_sy,
          output_datum_total_lp,
          _prev_in,
          _prev_out,
        ) =
          list.foldl(
            order_indices,
            (
              market_input_datum.total_pt,
              market_input_datum.total_sy,
              market_input_datum.total_lp,
              -1,
              -1,
            ),
            fn(
              (in_idx, out_idx),
              (acc_total_pt, acc_total_sy, acc_total_lp, prev_in, prev_out),
            ) {
              expect in_idx > prev_in
              expect out_idx > prev_out
              expect Some(in) = list.at(inputs, in_idx)
              expect
                check_correct_input_payment_credential(
                  in,
                  market_info_datum.order_script_hash,
                )
              expect Some(out) = list.at(outputs, out_idx)
              expect InlineDatum(order_input_inline_datum) = in.output.datum
              expect order_datum: OrderDatum = order_input_inline_datum
              expect OMintLP {
                o_market_id,
                o_owner_pkh,
                o_owner_stake_key,
                o_batcher_fee,
                o_sy_desired_amount,
                o_pt_desired_amount,
              } = order_datum
              expect o_market_id == params.market_id
              let user_address =
                construct_address(o_owner_pkh, o_owner_stake_key)
              expect out.address == user_address
              expect
                o_sy_desired_amount > 0 && o_pt_desired_amount > 0 && o_batcher_fee >= 0
              expect
                assets.quantity_of(
                  in.output.value,
                  market_info_datum.yield_tokenization_policy_id,
                  market_info_datum.sy_token_name,
                ) >= o_sy_desired_amount
              expect
                assets.quantity_of(
                  in.output.value,
                  market_info_datum.yield_tokenization_policy_id,
                  market_info_datum.pt_token_name,
                ) >= o_pt_desired_amount
              let in_lovelace = assets.lovelace_of(in.output.value)
              let min_lovelace =
                o_batcher_fee + market_info_datum.envelope_amount * 2
              expect in_lovelace >= min_lovelace
              expect list.length(assets.flatten(in.output.value)) == 3
              let net_lp_by_pt =
                o_pt_desired_amount * market_input_datum.total_lp / market_input_datum.total_pt
              let net_lp_by_sy =
                o_sy_desired_amount * market_input_datum.total_lp / market_input_datum.total_sy
              let (lp_to_account, sy_used, pt_used) =
                if net_lp_by_pt < net_lp_by_sy {
                  (
                    net_lp_by_pt,
                    net_lp_by_pt * market_input_datum.total_sy / market_input_datum.total_lp,
                    o_pt_desired_amount,
                  )
                } else {
                  (
                    net_lp_by_sy,
                    o_sy_desired_amount,
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
                        market_info_datum.yield_tokenization_policy_id,
                        market_info_datum.sy_token_name,
                        o_sy_desired_amount - sy_used,
                      )
                    |> assets.add(
                        market_info_datum.yield_tokenization_policy_id,
                        market_info_datum.pt_token_name,
                        o_pt_desired_amount - pt_used,
                      ),
                  >=,
                )
              (
                acc_total_lp + lp_to_account,
                acc_total_sy + sy_used,
                acc_total_pt + pt_used,
                in_idx,
                out_idx,
              )
            },
          )
        expect output_datum_total_lp >= market_input_datum.total_lp
        expect output_datum_total_sy >= market_input_datum.total_sy
        expect output_datum_total_pt >= market_input_datum.total_pt
        expect market_output_datum.total_sy == output_datum_total_sy
        expect market_output_datum.total_pt == output_datum_total_pt
        expect market_output_datum.total_lp == output_datum_total_lp
        expect market_output_datum.reserved_lp == market_input_datum.reserved_lp
        expect market_output_datum.total_fee == market_input_datum.total_fee
        expect
          market_output_datum.last_ln_implied_rate == market_input_datum.last_ln_implied_rate
        expect
          mint == assets.from_asset(
            policy_id,
            market_info_datum.lp_token_asset.asset_name,
            output_datum_total_lp - market_input_datum.total_lp,
          )
        expect
          assets.match(
            market_output.value,
            market_input.output.value
              |> assets.add(
                  market_info_datum.yield_tokenization_policy_id,
                  market_info_datum.sy_token_name,
                  output_datum_total_sy - market_input_datum.total_sy,
                )
              |> assets.add(
                  market_info_datum.yield_tokenization_policy_id,
                  market_info_datum.pt_token_name,
                  output_datum_total_pt - market_input_datum.total_pt,
                )
              |> assets.add(
                  policy_id,
                  market_info_datum.lp_token_asset.asset_name,
                  output_datum_total_lp - market_input_datum.total_lp,
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
        expect Some(market_input) = list.at(inputs, market_input_idx)
        expect Some(market_output) = list.at(outputs, market_output_idx)
        expect
          assets.quantity_of(
            market_input.output.value,
            params.market_nft.policy_id,
            params.market_nft.asset_name,
          ) == 1
        expect InlineDatum(market_input_inline_datum) =
          market_input.output.datum
        expect market_input_datum: MarketDatum = market_input_inline_datum
        expect market_input_datum.market_id == params.market_id
        expect InlineDatum(market_output_inline_datum) = market_output.datum
        expect market_output_datum: MarketDatum = market_output_inline_datum
        expect market_input_datum.market_id == market_output_datum.market_id
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
          count_input_orders(inputs, market_info_datum.order_script_hash) == list.length(
            order_indices,
          )
        let (
          output_datum_total_pt,
          output_datum_total_sy,
          output_datum_total_lp,
          _prev_in,
          _prev_sy_out,
          _prev_pt_out,
        ) =
          list.foldl(
            order_indices,
            (
              market_input_datum.total_pt,
              market_input_datum.total_sy,
              market_input_datum.total_lp,
              -1,
              -1,
              -1,
            ),
            fn(
              (in_idx, sy_out_idx, pt_out_idx),
              (
                acc_total_pt,
                acc_total_sy,
                acc_total_lp,
                prev_in,
                prev_sy_out,
                prev_pt_out,
              ),
            ) {
              expect in_idx > prev_in
              expect sy_out_idx > prev_sy_out
              expect pt_out_idx > prev_pt_out
              expect Some(in) = list.at(inputs, in_idx)
              expect
                check_correct_input_payment_credential(
                  in,
                  market_info_datum.order_script_hash,
                )
              expect Some(sy_out) = list.at(outputs, sy_out_idx)
              expect Some(pt_out) = list.at(outputs, pt_out_idx)
              expect InlineDatum(order_input_inline_datum) = in.output.datum
              expect order_datum: OrderDatum = order_input_inline_datum
              expect OBurnLP {
                o_market_id,
                o_owner_pkh: _,
                o_owner_stake_key: _,
                o_receive_sy_pkh,
                o_receive_sy_stake_key,
                o_receive_pt_pkh,
                o_receive_pt_stake_key,
                o_batcher_fee,
                o_lp_amount,
              } = order_datum
              expect o_lp_amount > 0 && o_batcher_fee >= 0
              expect o_market_id == params.market_id
              let user_sy_address =
                construct_address(o_receive_sy_pkh, o_receive_sy_stake_key)
              let user_pt_address =
                construct_address(o_receive_pt_pkh, o_receive_pt_stake_key)
              expect sy_out.address == user_sy_address
              expect pt_out.address == user_pt_address
              expect
                assets.quantity_of(
                  in.output.value,
                  policy_id,
                  market_info_datum.lp_token_asset.asset_name,
                ) >= o_lp_amount
              let in_lovelace = assets.lovelace_of(in.output.value)
              let min_lovelace =
                o_batcher_fee + market_info_datum.envelope_amount * 3
              expect in_lovelace >= min_lovelace
              expect list.length(assets.flatten(in.output.value)) == 2
              let sy_to_account =
                o_lp_amount * market_input_datum.total_sy / market_input_datum.total_lp
              let pt_to_account =
                o_lp_amount * market_input_datum.total_pt / market_input_datum.total_lp
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
                        market_info_datum.yield_tokenization_policy_id,
                        market_info_datum.sy_token_name,
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
              (
                acc_total_pt - pt_to_account,
                acc_total_sy - sy_to_account,
                acc_total_lp - o_lp_amount,
                in_idx,
                sy_out_idx,
                pt_out_idx,
              )
            },
          )
        expect output_datum_total_lp >= 0
        expect output_datum_total_sy >= 0
        expect output_datum_total_pt >= 0
        expect market_output_datum.total_sy == output_datum_total_sy
        expect market_output_datum.total_pt == output_datum_total_pt
        expect market_output_datum.total_lp == output_datum_total_lp
        expect market_output_datum.reserved_lp == market_input_datum.reserved_lp
        expect market_output_datum.total_fee == market_input_datum.total_fee
        expect
          market_output_datum.last_ln_implied_rate == market_input_datum.last_ln_implied_rate
        let total_burned_lp =
          market_input_datum.total_lp - output_datum_total_lp
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
                  market_info_datum.yield_tokenization_policy_id,
                  market_info_datum.sy_token_name,
                  output_datum_total_sy - market_input_datum.total_sy,
                )
              |> assets.add(
                  market_info_datum.yield_tokenization_policy_id,
                  market_info_datum.pt_token_name,
                  output_datum_total_pt - market_input_datum.total_pt,
                )
              |> assets.add(
                  policy_id,
                  market_info_datum.lp_token_asset.asset_name,
                  output_datum_total_lp - market_input_datum.total_lp,
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

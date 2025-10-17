use aiken/collection/list
use cardano/assets
use cardano/transaction.{
  InlineDatum, Input, Output, OutputReference, Transaction,
}
use pulse_math
use types.{
  Asset, MAdminOperation, MBurnLp, MInitLp, MMintLp, MSwapExactPTForSY,
  MSwapExactSYForPT, MSwapExactSYForYT, MSwapExactYTForSY, MarketDatum,
  MarketInfoDatum, MarketRedeemer, OSwapExactPTForSY, OSwapExactSYForPT,
  OracleDatum, OrderDatum, PubKeyHash,
}
use utils.{
  calculate_post_swap_rate, check_correct_input_payment_credential,
  construct_address, count_input_orders, validate_license_and_expiry,
  validate_lp_delegation, validate_market_info_ref, validate_market_own_utxos,
  validate_oracle_ref, validate_yt_delegation, verify_market_swap_output,
}

pub type MarketParams {
  admin_pkh: PubKeyHash,
  market_id: OutputReference,
  market_nft: Asset,
  market_info_nft: Asset,
}

validator market(params: MarketParams) {
  spend(
    option_datum: Option<MarketDatum>,
    redeemer: MarketRedeemer,
    own_outref: OutputReference,
    self: Transaction,
  ) {
    let Transaction {
      inputs,
      reference_inputs,
      outputs,
      extra_signatories,
      validity_range,
      redeemers,
      ..
    } = self
    when redeemer is {
      MInitLp { market_info_idx } ->
        validate_lp_delegation(
          reference_inputs,
          market_info_idx,
          params.market_info_nft,
          params.market_id,
          redeemers,
          types.LPInitLp {
            market_info_ref_idx: 0,
            order_indices: (0, 0),
            license_idx: 0,
            market_input_idx: 0,
            market_output_idx: 0,
          },
        )
      MMintLp { market_info_idx } ->
        validate_lp_delegation(
          reference_inputs,
          market_info_idx,
          params.market_info_nft,
          params.market_id,
          redeemers,
          types.LPMintLp {
            market_info_ref_idx: 0,
            order_indices: [],
            license_idx: 0,
            market_input_idx: 0,
            market_output_idx: 0,
          },
        )
      MBurnLp { market_info_idx } ->
        validate_lp_delegation(
          reference_inputs,
          market_info_idx,
          params.market_info_nft,
          params.market_id,
          redeemers,
          types.LPBurnLp {
            market_info_ref_idx: 0,
            order_indices: [],
            license_idx: 0,
            market_input_idx: 0,
            market_output_idx: 0,
          },
        )

      MSwapExactPTForSY {
        own_input_idx,
        own_output_idx,
        market_info_idx,
        oracle_idx,
        license_idx,
        order_indices,
      } -> {
        let (own_input, own_output, own_input_datum, own_output_datum) =
          validate_market_own_utxos(
            option_datum,
            inputs,
            outputs,
            own_input_idx,
            own_output_idx,
            own_outref,
            params.market_nft,
          )
        let market_info_datum =
          validate_market_info_ref(
            reference_inputs,
            market_info_idx,
            params.market_info_nft,
            own_input_datum.market_id,
          )
        let end_valid_time_range =
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
        let oracle_datum =
          validate_oracle_ref(
            reference_inputs,
            oracle_idx,
            market_info_datum.oracle_nft,
          )
        let (
          output_datum_total_pt,
          output_datum_total_sy,
          output_datum_total_fee,
          _prev_in,
          _prev_out,
        ) =
          list.foldl(
            order_indices,
            (
              own_input_datum.total_pt,
              own_input_datum.total_sy,
              own_input_datum.total_fee,
              -1,
              -1,
            ),
            fn(
              (in_idx, out_idx),
              (acc_total_pt, acc_total_sy, acc_total_fee, prev_in, prev_out),
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
              expect OSwapExactPTForSY {
                o_market_id,
                o_owner_pkh,
                o_owner_stake_key,
                o_batcher_fee,
                o_pt_amount,
                o_min_sy_out,
              } = order_datum
              expect o_market_id == params.market_id
              let user_address =
                construct_address(o_owner_pkh, o_owner_stake_key)
              expect out.address == user_address
              expect o_pt_amount > 0 && o_batcher_fee >= 0
              expect
                assets.quantity_of(
                  in.output.value,
                  market_info_datum.yield_tokenization_policy_id,
                  market_info_datum.pt_token_name,
                ) >= o_pt_amount
              let in_lovelace = assets.lovelace_of(in.output.value)
              let min_lovelace =
                o_batcher_fee + market_info_datum.envelope_amount
              expect in_lovelace >= min_lovelace
              expect list.length(assets.flatten(in.output.value)) == 2
              // Calculate SY output using Pendle AMM formula
              let (sy_out, sy_fee, sy_to_reserve) =
                pulse_math.calculate_sy_out_for_pt_in(
                  o_pt_amount,
                  acc_total_pt,
                  acc_total_sy,
                  oracle_datum.py_index,
                  market_info_datum.scalar_root,
                  own_input_datum.last_ln_implied_rate,
                  market_info_datum.ln_fee_rate_root,
                  market_info_datum.reserve_fee_percent,
                  market_info_datum.expiry,
                  end_valid_time_range,
                  oracle_datum.based,
                )
              // Check slippage protection
              expect sy_out >= o_min_sy_out
              // Validate output
              expect
                assets.match(
                  out.value,
                  assets.zero
                    |> assets.add(
                        assets.ada_policy_id,
                        assets.ada_asset_name,
                        market_info_datum.envelope_amount,
                      )
                    |> assets.add(
                        market_info_datum.yield_tokenization_policy_id,
                        market_info_datum.sy_token_name,
                        sy_out,
                      ),
                  ==,
                )
              (
                acc_total_pt + o_pt_amount,
                acc_total_sy - sy_out - sy_to_reserve,
                acc_total_fee + sy_fee + sy_to_reserve,
                in_idx,
                out_idx,
              )
            },
          )
        let new_ln_implied_rate =
          calculate_post_swap_rate(
            output_datum_total_sy,
            output_datum_total_pt,
            own_input_datum,
            oracle_datum,
            market_info_datum,
            end_valid_time_range,
          )
        verify_market_swap_output(
          own_output_datum,
          own_input_datum,
          output_datum_total_sy,
          output_datum_total_pt,
          output_datum_total_fee,
          new_ln_implied_rate,
          own_output,
          own_input,
          market_info_datum,
        )
      }
      MSwapExactSYForPT {
        own_input_idx,
        own_output_idx,
        market_info_idx,
        oracle_idx,
        license_idx,
        order_indices,
      } -> {
        let (own_input, own_output, own_input_datum, own_output_datum) =
          validate_market_own_utxos(
            option_datum,
            inputs,
            outputs,
            own_input_idx,
            own_output_idx,
            own_outref,
            params.market_nft,
          )
        let market_info_datum =
          validate_market_info_ref(
            reference_inputs,
            market_info_idx,
            params.market_info_nft,
            own_input_datum.market_id,
          )
        let end_valid_time_range =
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
        let oracle_datum =
          validate_oracle_ref(
            reference_inputs,
            oracle_idx,
            market_info_datum.oracle_nft,
          )
        let (
          output_datum_total_pt,
          output_datum_total_sy,
          output_datum_total_fee,
          _prev_in,
          _prev_out,
        ) =
          list.foldl(
            order_indices,
            (
              own_input_datum.total_pt,
              own_input_datum.total_sy,
              own_input_datum.total_fee,
              -1,
              -1,
            ),
            fn(
              (in_idx, out_idx),
              (acc_total_pt, acc_total_sy, acc_total_fee, prev_in, prev_out),
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
              expect OSwapExactSYForPT {
                o_market_id,
                o_owner_pkh,
                o_owner_stake_key,
                o_batcher_fee,
                o_sy_amount,
                o_min_pt_out,
              } = order_datum
              expect o_market_id == params.market_id
              let user_address =
                construct_address(o_owner_pkh, o_owner_stake_key)
              expect out.address == user_address
              expect o_sy_amount > 0 && o_batcher_fee >= 0
              expect
                assets.quantity_of(
                  in.output.value,
                  market_info_datum.yield_tokenization_policy_id,
                  market_info_datum.sy_token_name,
                ) >= o_sy_amount
              let in_lovelace = assets.lovelace_of(in.output.value)
              let min_lovelace =
                o_batcher_fee + market_info_datum.envelope_amount
              expect in_lovelace >= min_lovelace
              expect list.length(assets.flatten(in.output.value)) == 2
              // Calculate PT output using Pendle AMM formula
              let (pt_out, sy_fee, sy_to_reserve) =
                pulse_math.calculate_pt_out_for_sy_in(
                  o_sy_amount,
                  acc_total_pt,
                  acc_total_sy,
                  oracle_datum.py_index,
                  market_info_datum.scalar_root,
                  own_input_datum.last_ln_implied_rate,
                  market_info_datum.ln_fee_rate_root,
                  market_info_datum.reserve_fee_percent,
                  market_info_datum.expiry,
                  end_valid_time_range,
                  oracle_datum.based,
                )
              // Check slippage protection
              expect pt_out >= o_min_pt_out
              // Validate output
              expect
                assets.match(
                  out.value,
                  assets.zero
                    |> assets.add(
                        assets.ada_policy_id,
                        assets.ada_asset_name,
                        market_info_datum.envelope_amount,
                      )
                    |> assets.add(
                        market_info_datum.yield_tokenization_policy_id,
                        market_info_datum.pt_token_name,
                        pt_out,
                      ),
                  ==,
                )
              (
                acc_total_pt - pt_out,
                acc_total_sy + o_sy_amount - sy_to_reserve,
                acc_total_fee + sy_fee + sy_to_reserve,
                in_idx,
                out_idx,
              )
            },
          )
        let new_ln_implied_rate =
          calculate_post_swap_rate(
            output_datum_total_sy,
            output_datum_total_pt,
            own_input_datum,
            oracle_datum,
            market_info_datum,
            end_valid_time_range,
          )
        verify_market_swap_output(
          own_output_datum,
          own_input_datum,
          output_datum_total_sy,
          output_datum_total_pt,
          output_datum_total_fee,
          new_ln_implied_rate,
          own_output,
          own_input,
          market_info_datum,
        )
      }
      MSwapExactSYForYT { market_info_idx } ->
        validate_yt_delegation(
          reference_inputs,
          market_info_idx,
          params.market_info_nft,
          params.market_id,
          redeemers,
          types.YTSwapSYForYT {
            market_info_ref_idx: 0,
            order_indices: [],
            oracle_idx: 0,
            license_idx: 0,
            market_input_idx: 0,
            market_output_idx: 0,
            sy_vault_input_idx: 0,
            sy_vault_output_idx: 0,
          },
        )
      MSwapExactYTForSY { market_info_idx } ->
        validate_yt_delegation(
          reference_inputs,
          market_info_idx,
          params.market_info_nft,
          params.market_id,
          redeemers,
          types.YTSwapYTForSY {
            market_info_ref_idx: 0,
            order_indices: [],
            oracle_idx: 0,
            license_idx: 0,
            market_input_idx: 0,
            market_output_idx: 0,
            sy_vault_input_idx: 0,
            sy_vault_output_idx: 0,
          },
        )
      MAdminOperation -> list.has(extra_signatories, params.admin_pkh)
    }
  }

  else(_) {
    False
  }
}

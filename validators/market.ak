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
  check_correct_input_payment_credential, count_input_orders,
  validate_license_and_expiry, validate_lp_delegation, validate_market_info_ref,
  validate_market_own_utxos, validate_oracle_ref, validate_yt_delegation,
  verify_market_swap_output,
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
            order_indices: (0, 0),
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
            order_indices: (0, 0, 0),
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
        expect InlineDatum(order_input_inline_datum) = in.output.datum
        expect order_datum: OrderDatum = order_input_inline_datum
        expect OSwapExactPTForSY {
          o_receive_addr,
          o_receive_datum,
          o_min_sy_out,
          ..
        } = order_datum
        expect out.address == o_receive_addr
        expect out.datum == o_receive_datum
        let pt_amount =
          assets.quantity_of(
            in.output.value,
            market_info_datum.yield_tokenization_policy_id,
            market_info_datum.pt_token_name,
          )

        let sy_amount =
          assets.quantity_of(
            out.value,
            market_info_datum.underlying_asset.policy_id,
            market_info_datum.underlying_asset.asset_name,
          )

        expect list.length(assets.flatten(in.output.value)) == 2
        // Validate swap using new efficient formula (Section 2.5.2)
        expect
          pulse_math.validate_pt_to_sy_swap(
            pt_amount,
            sy_amount,
            own_input_datum.total_pt,
            own_input_datum.total_sy,
            oracle_datum.py_index,
            market_info_datum.init_py_index,
            market_info_datum.scalar_root,
            market_info_datum.initial_anchor,
            market_info_datum.ln_fee_rate_root,
            market_info_datum.expiry,
            end_valid_time_range,
            market_info_datum.duration,
            oracle_datum.based,
          )

        // Check slippage protection
        expect sy_amount >= o_min_sy_out
        let output_datum_total_pt = own_input_datum.total_pt + pt_amount
        let output_datum_total_sy = own_input_datum.total_sy - sy_amount
        verify_market_swap_output(
          own_output_datum,
          own_input_datum,
          output_datum_total_sy,
          output_datum_total_pt,
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
        expect InlineDatum(order_input_inline_datum) = in.output.datum
        expect order_datum: OrderDatum = order_input_inline_datum
        expect OSwapExactSYForPT {
          o_receive_addr,
          o_receive_datum,
          o_min_pt_out,
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
        expect sy_amount > 0
        expect list.length(assets.flatten(in.output.value)) == 2
        let pt_amount =
          assets.quantity_of(
            out.value,
            market_info_datum.yield_tokenization_policy_id,
            market_info_datum.pt_token_name,
          )

        // Validate swap using new efficient formula (Section 2.5.1)
        expect
          pulse_math.validate_sy_to_pt_swap(
            sy_amount,
            pt_amount,
            own_input_datum.total_pt,
            own_input_datum.total_sy,
            oracle_datum.py_index,
            market_info_datum.init_py_index,
            market_info_datum.scalar_root,
            market_info_datum.initial_anchor,
            market_info_datum.ln_fee_rate_root,
            market_info_datum.expiry,
            end_valid_time_range,
            market_info_datum.duration,
            oracle_datum.based,
          )
        // Check slippage protection
        expect pt_amount >= o_min_pt_out

        let output_datum_total_pt = own_input_datum.total_pt - pt_amount
        let output_datum_total_sy = own_input_datum.total_sy + sy_amount
        verify_market_swap_output(
          own_output_datum,
          own_input_datum,
          output_datum_total_sy,
          output_datum_total_pt,
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
            order_indices: (0, 0),
            oracle_idx: 0,
            license_idx: 0,
            market_input_idx: 0,
            market_output_idx: 0,
            borrowed_sy: 0,
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
            order_indices: (0, 0),
            oracle_idx: 0,
            license_idx: 0,
            market_input_idx: 0,
            market_output_idx: 0,
            swapped_sy: 0,
          },
        )
      MAdminOperation -> list.has(extra_signatories, params.admin_pkh)
    }
  }

  else(_) {
    False
  }
}

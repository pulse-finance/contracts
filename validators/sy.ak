use aiken/collection/dict
use aiken/collection/list
use aiken/collection/pairs
use cardano/assets
use cardano/transaction.{
  InlineDatum, Input, Mint, Output, OutputReference, Transaction,
}
use constants.{ytstake_authtoken_tn}
use types.{
  Asset, MarketInfoDatum, OMergeSY, OSplitSY, OUnstakeYT, OWithdrawYTReward,
  OracleDatum, OrderDatum, PubKeyHash, SYSwapSYForYT, SYSwapYTForSY, SYUnstakeYT,
  SYVaultAdminAction, SYVaultDatum, SYVaultMergeSY, SYVaultRedeemer,
  SYVaultSplitSY, SYWithdrawYTReward, YTStakeDatum,
}
use utils.{
  check_correct_input_payment_credential, construct_address, count_input_orders,
  validate_license, validate_market_info_ref, validate_oracle_ref,
  validate_sy_vault_own_utxos,
}

pub type SYParams {
  admin_pkh: PubKeyHash,
  market_id: OutputReference,
  market_nft: Asset,
  market_info_nft: Asset,
  sy_nft: Asset,
}

validator sy(params: SYParams) {
  spend(
    option_datum: Option<SYVaultDatum>,
    redeemer: SYVaultRedeemer,
    own_ref: OutputReference,
    self: Transaction,
  ) {
    let Transaction {
      inputs,
      reference_inputs,
      outputs,
      mint,
      validity_range,
      extra_signatories,
      redeemers,
      ..
    } = self
    when redeemer is {
      SYVaultSplitSY {
        own_input_idx,
        own_output_idx,
        market_info_ref_idx,
        order_indices,
        oracle_idx,
        license_idx,
      } -> {
        let (own_input, own_output, own_input_datum, own_output_datum) =
          validate_sy_vault_own_utxos(
            option_datum,
            inputs,
            outputs,
            own_input_idx,
            own_output_idx,
            own_ref,
            params.sy_nft,
          )
        let market_info_datum =
          validate_market_info_ref(
            reference_inputs,
            market_info_ref_idx,
            params.market_info_nft,
            params.market_id,
          )
        expect _end_valid_time_range =
          validate_license(
            inputs,
            license_idx,
            market_info_datum.batcher_policy_id,
            validity_range,
          )
        let num_orders = list.length(order_indices)
        expect num_orders > 0
        expect
          count_input_orders(inputs, market_info_datum.order_script_hash) == num_orders
        let oracle_datum =
          validate_oracle_ref(
            reference_inputs,
            oracle_idx,
            market_info_datum.oracle_nft,
          )
        let (total_sy, total_pt, _prev_in, _prev_pt_out, _prev_yt_out) =
          list.foldl(
            order_indices,
            (0, 0, -1, -1, -1),
            fn(
              (in_idx, out_pt_idx, out_yt_idx),
              (acc_sy, acc_pt, prev_in, prev_pt_out, prev_yt_out),
            ) {
              expect in_idx > prev_in
              expect out_pt_idx > prev_pt_out
              expect out_yt_idx > prev_yt_out
              expect Some(in) = list.at(inputs, in_idx)
              expect
                check_correct_input_payment_credential(
                  in,
                  market_info_datum.order_script_hash,
                )
              expect Some(pt_out) = list.at(outputs, out_pt_idx)
              expect Some(yt_out) = list.at(outputs, out_yt_idx)
              expect InlineDatum(order_inline_datum) = in.output.datum
              expect order_datum: OrderDatum = order_inline_datum
              expect OSplitSY {
                o_market_id,
                o_owner_pkh: _,
                o_owner_stake_key: _,
                o_receive_pt_pkh,
                o_receive_pt_stake_key,
                o_receive_yt_pkh,
                o_receive_yt_stake_key,
                o_batcher_fee,
                o_sy_amount,
              } = order_datum
              expect o_market_id == params.market_id
              let pt_address =
                construct_address(o_receive_pt_pkh, o_receive_pt_stake_key)
              let yt_address =
                construct_address(o_receive_yt_pkh, o_receive_yt_stake_key)
              expect pt_address == pt_out.address
              expect yt_address == yt_out.address
              expect o_sy_amount > 0 && o_batcher_fee >= 0
              expect
                assets.quantity_of(
                  in.output.value,
                  market_info_datum.yield_tokenization_policy_id,
                  market_info_datum.sy_token_name,
                ) >= o_sy_amount
              let in_lovelace = assets.lovelace_of(in.output.value)
              let min_lovelace =
                o_batcher_fee + market_info_datum.envelope_amount * 2
              expect in_lovelace >= min_lovelace
              expect list.length(assets.flatten(in.output.value)) == 2
              let pt_amount =
                o_sy_amount * oracle_datum.py_index / oracle_datum.based
              expect
                assets.flatten(pt_out.value) == [
                  (
                    assets.ada_policy_id,
                    assets.ada_asset_name,
                    market_info_datum.envelope_amount,
                  ),
                  (
                    market_info_datum.yield_tokenization_policy_id,
                    market_info_datum.pt_token_name,
                    pt_amount,
                  ),
                ]
              expect
                assets.flatten(yt_out.value) == [
                  (
                    assets.ada_policy_id,
                    assets.ada_asset_name,
                    market_info_datum.envelope_amount,
                  ),
                  (
                    market_info_datum.yield_tokenization_policy_id,
                    market_info_datum.yt_token_name,
                    pt_amount,
                  ),
                ]
              (
                acc_sy + o_sy_amount,
                acc_pt + pt_amount,
                in_idx,
                out_pt_idx,
                out_yt_idx,
              )
            },
          )
        let num_token =
          mint
            |> assets.tokens(market_info_datum.yield_tokenization_policy_id)
            |> dict.keys()
            |> list.length()
        expect num_token == 2
        expect
          assets.quantity_of(
            mint,
            market_info_datum.yield_tokenization_policy_id,
            market_info_datum.pt_token_name,
          ) == total_pt
        expect
          assets.quantity_of(
            mint,
            market_info_datum.yield_tokenization_policy_id,
            market_info_datum.yt_token_name,
          ) == total_pt
        expect own_input_datum.total_sy >= total_sy
        expect own_output_datum.total_sy == own_input_datum.total_sy - total_sy
        expect
          assets.match(
            own_input.output.value,
            own_output.value
              |> assets.add(
                  market_info_datum.yield_tokenization_policy_id,
                  market_info_datum.sy_token_name,
                  -total_sy,
                ),
            >=,
          )
        True
      }
      SYVaultMergeSY {
        own_input_idx,
        own_output_idx,
        market_info_ref_idx,
        order_indices,
        oracle_idx,
        license_idx,
      } -> {
        let (own_input, own_output, own_input_datum, own_output_datum) =
          validate_sy_vault_own_utxos(
            option_datum,
            inputs,
            outputs,
            own_input_idx,
            own_output_idx,
            own_ref,
            params.sy_nft,
          )
        let market_info_datum =
          validate_market_info_ref(
            reference_inputs,
            market_info_ref_idx,
            params.market_info_nft,
            params.market_id,
          )
        expect _end_valid_time_range =
          validate_license(
            inputs,
            license_idx,
            market_info_datum.batcher_policy_id,
            validity_range,
          )
        let num_orders = list.length(order_indices)
        expect num_orders > 0
        expect
          count_input_orders(inputs, market_info_datum.order_script_hash) == num_orders
        let oracle_datum =
          validate_oracle_ref(
            reference_inputs,
            oracle_idx,
            market_info_datum.oracle_nft,
          )
        let (total_pt, total_sy, _prev_in, _prev_out) =
          list.foldl(
            order_indices,
            (0, 0, -1, -1),
            fn((in_idx, out_idx), (acc_pt, acc_sy, prev_in, prev_out)) {
              expect in_idx > prev_in
              expect out_idx > prev_out
              expect Some(in) = list.at(inputs, in_idx)
              expect
                check_correct_input_payment_credential(
                  in,
                  market_info_datum.order_script_hash,
                )
              expect Some(out) = list.at(outputs, out_idx)
              expect InlineDatum(order_inline_datum) = in.output.datum
              expect order_datum: OrderDatum = order_inline_datum
              expect OMergeSY {
                o_market_id,
                o_owner_pkh,
                o_owner_stake_key,
                o_batcher_fee,
                o_pt_amount,
              } = order_datum
              expect o_market_id == params.market_id
              let user_address =
                construct_address(o_owner_pkh, o_owner_stake_key)
              expect user_address == out.address
              expect o_pt_amount > 0 && o_batcher_fee >= 0
              expect
                assets.quantity_of(
                  in.output.value,
                  market_info_datum.yield_tokenization_policy_id,
                  market_info_datum.pt_token_name,
                ) >= o_pt_amount
              expect
                assets.quantity_of(
                  in.output.value,
                  market_info_datum.yield_tokenization_policy_id,
                  market_info_datum.yt_token_name,
                ) >= o_pt_amount
              let in_lovelace = assets.lovelace_of(in.output.value)
              let min_lovelace =
                o_batcher_fee + market_info_datum.envelope_amount
              expect in_lovelace >= min_lovelace
              expect list.length(assets.flatten(in.output.value)) == 3
              let sy_amount =
                o_pt_amount * oracle_datum.based / oracle_datum.py_index
              expect
                assets.flatten(out.value) == [
                  (
                    assets.ada_policy_id,
                    assets.ada_asset_name,
                    market_info_datum.envelope_amount,
                  ),
                  (
                    market_info_datum.yield_tokenization_policy_id,
                    market_info_datum.pt_token_name,
                    sy_amount,
                  ),
                ]
              (acc_pt + o_pt_amount, acc_sy + sy_amount, in_idx, out_idx)
            },
          )
        let num_token =
          mint
            |> assets.tokens(market_info_datum.yield_tokenization_policy_id)
            |> dict.keys()
            |> list.length()
        expect num_token == 2
        expect
          assets.quantity_of(
            mint,
            market_info_datum.yield_tokenization_policy_id,
            market_info_datum.pt_token_name,
          ) == -total_pt
        expect
          assets.quantity_of(
            mint,
            market_info_datum.yield_tokenization_policy_id,
            market_info_datum.yt_token_name,
          ) == -total_pt
        expect own_output_datum.total_sy == own_input_datum.total_sy + total_sy
        expect
          assets.match(
            own_input.output.value,
            own_output.value
              |> assets.add(
                  market_info_datum.yield_tokenization_policy_id,
                  market_info_datum.sy_token_name,
                  total_sy,
                ),
            >=,
          )
        True
      }
      SYUnstakeYT {
        own_input_idx,
        own_output_idx,
        market_info_ref_idx,
        order_indices,
        oracle_idx,
        license_idx,
      } -> {
        let (own_input, own_output, own_input_datum, own_output_datum) =
          validate_sy_vault_own_utxos(
            option_datum,
            inputs,
            outputs,
            own_input_idx,
            own_output_idx,
            own_ref,
            params.sy_nft,
          )
        let market_info_datum =
          validate_market_info_ref(
            reference_inputs,
            market_info_ref_idx,
            params.market_info_nft,
            params.market_id,
          )
        expect _end_valid_time_range =
          validate_license(
            inputs,
            license_idx,
            market_info_datum.batcher_policy_id,
            validity_range,
          )
        let num_orders = list.length(order_indices)
        expect num_orders > 0
        expect
          count_input_orders(inputs, market_info_datum.order_script_hash) == num_orders
        let oracle_datum =
          validate_oracle_ref(
            reference_inputs,
            oracle_idx,
            market_info_datum.oracle_nft,
          )
        let (total_sy, _prev_in, _prev_out) =
          list.foldl(
            order_indices,
            (0, -1, -1),
            fn((in_idx, out_idx, yt_stake_idx), (acc_sy, prev_in, prev_out)) {
              expect in_idx > prev_in
              expect out_idx > prev_out
              expect Some(in) = list.at(inputs, in_idx)
              expect
                check_correct_input_payment_credential(
                  in,
                  market_info_datum.order_script_hash,
                )
              expect Some(out) = list.at(outputs, out_idx)
              expect Some(in_yt_stake) = list.at(inputs, yt_stake_idx)
              expect InlineDatum(yt_stake_inline_datum) =
                in_yt_stake.output.datum
              expect yt_stake_datum: YTStakeDatum = yt_stake_inline_datum
              expect InlineDatum(order_inline_datum) = in.output.datum
              expect order_datum: OrderDatum = order_inline_datum
              expect OUnstakeYT {
                o_market_id,
                o_owner_pkh,
                o_owner_stake_key,
                o_batcher_fee,
                o_stake_id,
              } = order_datum
              expect o_market_id == params.market_id
              expect yt_stake_datum.market_id == params.market_id
              expect yt_stake_datum.stake_id == o_stake_id
              expect yt_stake_datum.owner_pkh == o_owner_pkh
              let user_address =
                construct_address(o_owner_pkh, o_owner_stake_key)
              expect user_address == out.address
              expect o_batcher_fee >= 0
              let in_lovelace = assets.lovelace_of(in.output.value)
              let min_lovelace =
                o_batcher_fee + market_info_datum.envelope_amount
              expect in_lovelace >= min_lovelace
              expect list.length(assets.flatten(in.output.value)) == 1
              expect oracle_datum.py_index >= yt_stake_datum.py_index
              let sy_amount =
                yt_stake_datum.staked_yt_amount * (
                  oracle_datum.py_index - yt_stake_datum.py_index
                ) / yt_stake_datum.py_index
              expect
                assets.flatten(out.value) == [
                  (
                    assets.ada_policy_id,
                    assets.ada_asset_name,
                    market_info_datum.envelope_amount * 2,
                  ),
                  (
                    market_info_datum.yield_tokenization_policy_id,
                    market_info_datum.sy_token_name,
                    sy_amount,
                  ),
                  (
                    market_info_datum.yield_tokenization_policy_id,
                    market_info_datum.yt_token_name,
                    yt_stake_datum.staked_yt_amount,
                  ),
                ]
              (acc_sy + sy_amount, in_idx, out_idx)
            },
          )
        expect own_output_datum.total_sy == own_input_datum.total_sy - total_sy
        expect own_input_datum.total_sy >= total_sy
        expect
          assets.flatten(mint) == [
            (
              market_info_datum.ytstake_authtoken_policy_id,
              ytstake_authtoken_tn,
              -num_orders,
            ),
          ]
        expect
          assets.match(
            own_input.output.value,
            own_output.value
              |> assets.add(
                  market_info_datum.yield_tokenization_policy_id,
                  market_info_datum.sy_token_name,
                  -total_sy,
                ),
            >=,
          )
        True
      }
      SYWithdrawYTReward {
        own_input_idx,
        own_output_idx,
        market_info_ref_idx,
        order_indices,
        oracle_idx,
        license_idx,
      } -> {
        let (own_input, own_output, own_input_datum, own_output_datum) =
          validate_sy_vault_own_utxos(
            option_datum,
            inputs,
            outputs,
            own_input_idx,
            own_output_idx,
            own_ref,
            params.sy_nft,
          )
        let market_info_datum =
          validate_market_info_ref(
            reference_inputs,
            market_info_ref_idx,
            params.market_info_nft,
            params.market_id,
          )
        expect _end_valid_time_range =
          validate_license(
            inputs,
            license_idx,
            market_info_datum.batcher_policy_id,
            validity_range,
          )
        let num_orders = list.length(order_indices)
        expect num_orders > 0
        expect
          count_input_orders(inputs, market_info_datum.order_script_hash) == num_orders
        let oracle_datum =
          validate_oracle_ref(
            reference_inputs,
            oracle_idx,
            market_info_datum.oracle_nft,
          )
        let (total_sy, _prev_in, _prev_out) =
          list.foldl(
            order_indices,
            (0, -1, -1),
            fn(
              (in_idx, out_idx, yt_stake_in_idx, yt_stake_out_idx),
              (acc_sy, prev_in, prev_out),
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
              expect Some(in_yt_stake) = list.at(inputs, yt_stake_in_idx)
              expect Some(out_yt_stake) = list.at(outputs, yt_stake_out_idx)
              expect InlineDatum(in_yt_stake_inline_datum) =
                in_yt_stake.output.datum
              expect in_yt_stake_datum: YTStakeDatum = in_yt_stake_inline_datum
              expect InlineDatum(out_yt_stake_inline_datum) = out_yt_stake.datum
              expect out_yt_stake_datum: YTStakeDatum =
                out_yt_stake_inline_datum
              expect InlineDatum(order_inline_datum) = in.output.datum
              expect in_yt_stake_datum.market_id == params.market_id
              expect out_yt_stake_datum.market_id == params.market_id
              expect in_yt_stake_datum.stake_id == out_yt_stake_datum.stake_id
              expect in_yt_stake_datum.owner_pkh == out_yt_stake_datum.owner_pkh
              expect
                in_yt_stake_datum.staked_yt_amount == out_yt_stake_datum.staked_yt_amount
              expect out_yt_stake_datum.py_index == oracle_datum.py_index
              expect in_yt_stake.output.address == out_yt_stake.address
              expect in_yt_stake.output.value == out_yt_stake.value
              expect order_datum: OrderDatum = order_inline_datum
              expect OWithdrawYTReward {
                o_market_id,
                o_owner_pkh,
                o_owner_stake_key,
                o_batcher_fee,
                o_stake_id,
              } = order_datum
              expect o_market_id == params.market_id
              expect in_yt_stake_datum.stake_id == o_stake_id
              expect in_yt_stake_datum.owner_pkh == o_owner_pkh
              let user_address =
                construct_address(o_owner_pkh, o_owner_stake_key)
              expect user_address == out.address
              expect o_batcher_fee >= 0
              let in_lovelace = assets.lovelace_of(in.output.value)
              let min_lovelace =
                o_batcher_fee + market_info_datum.envelope_amount
              expect in_lovelace >= min_lovelace
              expect list.length(assets.flatten(in.output.value)) == 1
              expect oracle_datum.py_index >= in_yt_stake_datum.py_index
              let sy_amount =
                in_yt_stake_datum.staked_yt_amount * (
                  oracle_datum.py_index - in_yt_stake_datum.py_index
                ) / in_yt_stake_datum.py_index
              expect
                assets.flatten(out.value) == [
                  (
                    assets.ada_policy_id,
                    assets.ada_asset_name,
                    market_info_datum.envelope_amount,
                  ),
                  (
                    market_info_datum.yield_tokenization_policy_id,
                    market_info_datum.sy_token_name,
                    sy_amount,
                  ),
                ]
              (acc_sy + sy_amount, in_idx, out_idx)
            },
          )
        expect own_output_datum.total_sy == own_input_datum.total_sy - total_sy
        expect own_input_datum.total_sy >= total_sy
        expect
          assets.match(
            own_input.output.value,
            own_output.value
              |> assets.add(
                  market_info_datum.yield_tokenization_policy_id,
                  market_info_datum.sy_token_name,
                  -total_sy,
                ),
            >=,
          )
        True
      }
      SYSwapSYForYT { market_info_ref_idx } -> {
        let market_info_datum =
          validate_market_info_ref(
            reference_inputs,
            market_info_ref_idx,
            params.market_info_nft,
            params.market_id,
          )
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
      SYSwapYTForSY { market_info_ref_idx } -> {
        let market_info_datum =
          validate_market_info_ref(
            reference_inputs,
            market_info_ref_idx,
            params.market_info_nft,
            params.market_id,
          )
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
      SYVaultAdminAction -> list.has(extra_signatories, params.admin_pkh)
    }
  }

  else(_) {
    False
  }
}

use aiken/collection/dict
use aiken/collection/list
use aiken/collection/pairs
use cardano/address.{Script}
use cardano/assets.{PolicyId, flatten}
use cardano/transaction.{
  InlineDatum, Input, Mint, Output, OutputReference, Spend, Transaction,
}
use types.{
  Asset, MarketDatum, MarketInfoDatum, MarketRedeemer, OSwapExactSYForYT,
  OSwapExactYTForSY, OUnwrapSY, OWrapSY, OracleDatum, OrderDatum, PubKeyHash,
  SYVaultDatum, SYVaultMergeSY, SYVaultRedeemer, SYVaultSplitSY,
  UnderlyingAssetVaultDatum, YTBurn, YTMergeSY, YTRefTokenAction, YTSplitSY,
  YTSwapSYForYT, YTSwapYTForSY, YTUnwrapSY, YTWrapSY,
  YieldTokenizationMintRedeemer,
}
use utils.{
  check_correct_input_payment_credential, construct_address, count_input_orders,
  validate_license, validate_license_and_expiry, validate_market_info_ref,
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
  underlying_asset_vault_nft: Asset,
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
      YTWrapSY {
        market_info_ref_idx,
        order_indices,
        input_underlying_asset_vault_idx,
        output_underlying_asset_vault_idx,
        license_idx,
      } -> {
        expect Some(underlying_asset_vault_input) =
          list.at(inputs, input_underlying_asset_vault_idx)
        expect Some(underlying_asset_vault_output) =
          list.at(outputs, output_underlying_asset_vault_idx)
        expect
          assets.quantity_of(
            underlying_asset_vault_input.output.value,
            params.underlying_asset_vault_nft.policy_id,
            params.underlying_asset_vault_nft.asset_name,
          ) == 1
        expect
          assets.quantity_of(
            underlying_asset_vault_output.value,
            params.underlying_asset_vault_nft.policy_id,
            params.underlying_asset_vault_nft.asset_name,
          ) == 1
        expect
          underlying_asset_vault_input.output.address == underlying_asset_vault_output.address
        expect
          underlying_asset_vault_input.output.address.payment_credential == Script(
            policy_id,
          )
        expect InlineDatum(underlying_asset_vault_output_inline_datum) =
          underlying_asset_vault_output.datum
        expect underlying_asset_vault_output_datum: UnderlyingAssetVaultDatum =
          underlying_asset_vault_output_inline_datum
        expect InlineDatum(underlying_asset_vault_input_inline_datum) =
          underlying_asset_vault_input.output.datum
        expect underlying_asset_vault_input_datum: UnderlyingAssetVaultDatum =
          underlying_asset_vault_input_inline_datum
        expect
          underlying_asset_vault_input_datum.market_id == underlying_asset_vault_output_datum.market_id
        expect underlying_asset_vault_input_datum.market_id == params.market_id
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
        let (total_wrap, _prev_in, _prev_out) =
          list.foldl(
            order_indices,
            (0, -1, -1),
            fn((in_idx, out_idx), (acc_wrap, prev_in, prev_out)) {
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
              expect OWrapSY {
                o_market_id,
                o_owner_pkh,
                o_owner_stake_key,
                o_amount,
                o_batcher_fee,
              } = order_datum
              expect o_market_id == params.market_id
              let user_address =
                construct_address(o_owner_pkh, o_owner_stake_key)
              expect user_address == out.address
              expect o_amount > 0 && o_batcher_fee >= 0
              expect
                assets.quantity_of(
                  in.output.value,
                  market_info_datum.underlying_asset.policy_id,
                  market_info_datum.underlying_asset.asset_name,
                ) >= o_amount
              let in_lovelace = assets.lovelace_of(in.output.value)
              let min_lovelace =
                o_batcher_fee + market_info_datum.envelope_amount
              expect in_lovelace >= min_lovelace
              expect list.length(assets.flatten(in.output.value)) == 2
              expect
                assets.flatten(out.value) == [
                  (
                    assets.ada_policy_id,
                    assets.ada_asset_name,
                    market_info_datum.envelope_amount,
                  ),
                  (policy_id, market_info_datum.sy_token_name, o_amount),
                ]
              (acc_wrap + o_amount, in_idx, out_idx)
            },
          )
        expect
          assets.flatten(mint) == [
            (policy_id, market_info_datum.sy_token_name, total_wrap),
          ]
        expect
          underlying_asset_vault_input_datum.total_underlying_asset + total_wrap == underlying_asset_vault_output_datum.total_underlying_asset
        let expected_underlying_asset_vault_value =
          underlying_asset_vault_input.output.value
            |> assets.add(
                market_info_datum.underlying_asset.policy_id,
                market_info_datum.underlying_asset.asset_name,
                total_wrap,
              )
        underlying_asset_vault_output.value == expected_underlying_asset_vault_value
      }
      YTUnwrapSY {
        market_info_ref_idx,
        order_indices,
        input_underlying_asset_vault_idx,
        output_underlying_asset_vault_idx,
        license_idx,
      } -> {
        expect Some(underlying_asset_vault_input) =
          list.at(inputs, input_underlying_asset_vault_idx)
        expect Some(underlying_asset_vault_output) =
          list.at(outputs, output_underlying_asset_vault_idx)
        expect
          assets.quantity_of(
            underlying_asset_vault_input.output.value,
            params.underlying_asset_vault_nft.policy_id,
            params.underlying_asset_vault_nft.asset_name,
          ) == 1
        expect
          assets.quantity_of(
            underlying_asset_vault_output.value,
            params.underlying_asset_vault_nft.policy_id,
            params.underlying_asset_vault_nft.asset_name,
          ) == 1
        expect
          underlying_asset_vault_input.output.address == underlying_asset_vault_output.address
        expect
          underlying_asset_vault_input.output.address.payment_credential == Script(
            policy_id,
          )
        expect InlineDatum(underlying_asset_vault_output_inline_datum) =
          underlying_asset_vault_output.datum
        expect underlying_asset_vault_output_datum: UnderlyingAssetVaultDatum =
          underlying_asset_vault_output_inline_datum
        expect InlineDatum(underlying_asset_vault_input_inline_datum) =
          underlying_asset_vault_input.output.datum
        expect underlying_asset_vault_input_datum: UnderlyingAssetVaultDatum =
          underlying_asset_vault_input_inline_datum
        expect
          underlying_asset_vault_input_datum.market_id == underlying_asset_vault_output_datum.market_id
        expect underlying_asset_vault_input_datum.market_id == params.market_id
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
        let (total_unwrap, _prev_in, _prev_out) =
          list.foldl(
            order_indices,
            (0, -1, -1),
            fn((in_idx, out_idx), (acc_unwrap, prev_in, prev_out)) {
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
              expect OUnwrapSY {
                o_market_id,
                o_owner_pkh,
                o_owner_stake_key,
                o_amount,
                o_batcher_fee,
              } = order_datum
              expect o_market_id == params.market_id
              let user_address =
                construct_address(o_owner_pkh, o_owner_stake_key)
              expect user_address == out.address
              expect o_amount > 0 && o_batcher_fee >= 0
              expect
                assets.quantity_of(
                  in.output.value,
                  policy_id,
                  market_info_datum.sy_token_name,
                ) >= o_amount
              let in_lovelace = assets.lovelace_of(in.output.value)
              let min_lovelace =
                o_batcher_fee + market_info_datum.envelope_amount
              expect in_lovelace >= min_lovelace
              expect list.length(assets.flatten(in.output.value)) == 2
              expect
                assets.flatten(out.value) == [
                  (
                    assets.ada_policy_id,
                    assets.ada_asset_name,
                    market_info_datum.envelope_amount,
                  ),
                  (
                    market_info_datum.underlying_asset.policy_id,
                    market_info_datum.underlying_asset.asset_name,
                    o_amount,
                  ),
                ]
              (acc_unwrap + o_amount, in_idx, out_idx)
            },
          )
        expect
          assets.flatten(mint) == [
            (policy_id, market_info_datum.sy_token_name, -total_unwrap),
          ]
        expect
          underlying_asset_vault_input_datum.total_underlying_asset - total_unwrap == underlying_asset_vault_output_datum.total_underlying_asset
        let expected_underlying_asset_vault_value =
          underlying_asset_vault_input.output.value
            |> assets.add(
                market_info_datum.underlying_asset.policy_id,
                market_info_datum.underlying_asset.asset_name,
                -total_unwrap,
              )
        underlying_asset_vault_output.value == expected_underlying_asset_vault_value
      }
      YTSplitSY { sy_vault_input_idx } -> {
        expect Some(sy_vault_input) = list.at(inputs, sy_vault_input_idx)
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
        sy_vault_input_idx,
        sy_vault_output_idx,
      } -> {
        expect Some(market_input) = list.at(inputs, market_input_idx)
        expect Some(market_output) = list.at(outputs, market_output_idx)
        expect
          assets.quantity_of(
            market_input.output.value,
            params.market_nft.policy_id,
            params.market_nft.asset_name,
          ) == 1
        expect
          assets.quantity_of(
            market_output.value,
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
            types.MSwapExactSYForYT { .. } -> True
            types.MAdminOperation -> True
            _ -> False
          }
        expect Some(sy_vault_input) = list.at(inputs, sy_vault_input_idx)
        expect Some(sy_vault_output) = list.at(outputs, sy_vault_output_idx)
        expect
          assets.quantity_of(
            sy_vault_input.output.value,
            params.sy_nft.policy_id,
            params.sy_nft.asset_name,
          ) == 1
        expect
          assets.quantity_of(
            sy_vault_output.value,
            params.sy_nft.policy_id,
            params.sy_nft.asset_name,
          ) == 1
        expect InlineDatum(sy_vault_input_inline_datum) =
          sy_vault_input.output.datum
        expect sy_vault_input_datum: SYVaultDatum = sy_vault_input_inline_datum
        expect sy_vault_input_datum.market_id == params.market_id
        expect InlineDatum(sy_vault_output_inline_datum) = sy_vault_output.datum
        expect sy_vault_output_datum: SYVaultDatum =
          sy_vault_output_inline_datum
        expect sy_vault_input_datum.market_id == sy_vault_output_datum.market_id
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
              market_input_datum.total_pt,
              market_input_datum.total_sy,
              market_input_datum.total_fee,
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
              expect InlineDatum(order_inline_datum) = in.output.datum
              expect order_datum: OrderDatum = order_inline_datum
              expect OSwapExactSYForYT {
                o_market_id,
                o_owner_pkh,
                o_owner_stake_key,
                o_batcher_fee,
                o_sy_amount,
                o_min_yt_out,
              } = order_datum
              expect o_market_id == params.market_id
              let user_address =
                construct_address(o_owner_pkh, o_owner_stake_key)
              expect out.address == user_address
              expect o_sy_amount > 0 && o_batcher_fee >= 0
              expect
                assets.quantity_of(
                  in.output.value,
                  policy_id,
                  market_info_datum.sy_token_name,
                ) >= o_sy_amount
              let in_lovelace = assets.lovelace_of(in.output.value)
              let min_lovelace =
                o_batcher_fee + market_info_datum.envelope_amount
              expect in_lovelace >= min_lovelace
              expect list.length(assets.flatten(in.output.value)) == 2
              let pt_yt_amount =
                o_sy_amount * oracle_datum.py_index / oracle_datum.based
              expect pt_yt_amount >= o_min_yt_out
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
                        market_info_datum.yt_token_name,
                        pt_yt_amount,
                      ),
                  ==,
                )
              (
                acc_total_pt + pt_yt_amount,
                acc_total_sy + o_sy_amount,
                acc_total_fee,
                in_idx,
                out_idx,
              )
            },
          )
        expect market_output_datum.total_pt == output_datum_total_pt
        expect market_output_datum.total_sy == output_datum_total_sy
        expect market_output_datum.total_fee == output_datum_total_fee
        expect
          market_output_datum.last_ln_implied_rate == market_input_datum.last_ln_implied_rate
        expect market_output_datum.total_lp == market_input_datum.total_lp
        expect market_output_datum.reserved_lp == market_input_datum.reserved_lp
        let num_token =
          mint |> assets.tokens(policy_id) |> dict.keys() |> list.length()
        expect num_token == 2
        let total_sy_transfered =
          market_input_datum.total_sy - output_datum_total_sy
        expect total_sy_transfered > 0
        let total_pt_minted =
          output_datum_total_pt - market_input_datum.total_pt
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
                  policy_id,
                  market_info_datum.sy_token_name,
                  -total_sy_transfered,
                )
              |> assets.add(
                  policy_id,
                  market_info_datum.pt_token_name,
                  total_pt_minted,
                ),
            >=,
          )
        expect
          assets.match(
            sy_vault_output.value,
            sy_vault_input.output.value
              |> assets.add(
                  policy_id,
                  market_info_datum.sy_token_name,
                  total_sy_transfered,
                ),
            >=,
          )
        expect
          sy_vault_output_datum.total_sy == sy_vault_input_datum.total_sy + total_sy_transfered
        True
      }
      YTSwapYTForSY {
        market_info_ref_idx,
        order_indices,
        oracle_idx,
        license_idx,
        market_input_idx,
        market_output_idx,
        sy_vault_input_idx,
        sy_vault_output_idx,
      } -> {
        expect Some(market_input) = list.at(inputs, market_input_idx)
        expect Some(market_output) = list.at(outputs, market_output_idx)
        expect
          assets.quantity_of(
            market_input.output.value,
            params.market_nft.policy_id,
            params.market_nft.asset_name,
          ) == 1
        expect
          assets.quantity_of(
            market_output.value,
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
            types.MSwapExactYTForSY { .. } -> True
            types.MAdminOperation -> True
            _ -> False
          }
        expect Some(sy_vault_input) = list.at(inputs, sy_vault_input_idx)
        expect Some(sy_vault_output) = list.at(outputs, sy_vault_output_idx)
        expect
          assets.quantity_of(
            sy_vault_input.output.value,
            params.sy_nft.policy_id,
            params.sy_nft.asset_name,
          ) == 1
        expect
          assets.quantity_of(
            sy_vault_output.value,
            params.sy_nft.policy_id,
            params.sy_nft.asset_name,
          ) == 1
        expect InlineDatum(sy_vault_input_inline_datum) =
          sy_vault_input.output.datum
        expect sy_vault_input_datum: SYVaultDatum = sy_vault_input_inline_datum
        expect sy_vault_input_datum.market_id == params.market_id
        expect InlineDatum(sy_vault_output_inline_datum) = sy_vault_output.datum
        expect sy_vault_output_datum: SYVaultDatum =
          sy_vault_output_inline_datum
        expect sy_vault_input_datum.market_id == sy_vault_output_datum.market_id
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
              market_input_datum.total_pt,
              market_input_datum.total_sy,
              market_input_datum.total_fee,
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
              expect InlineDatum(order_inline_datum) = in.output.datum
              expect order_datum: OrderDatum = order_inline_datum
              expect OSwapExactYTForSY {
                o_market_id,
                o_owner_pkh,
                o_owner_stake_key,
                o_batcher_fee,
                o_yt_amount,
                o_min_sy_out,
              } = order_datum
              expect o_market_id == params.market_id
              let user_address =
                construct_address(o_owner_pkh, o_owner_stake_key)
              expect out.address == user_address
              expect o_yt_amount > 0 && o_batcher_fee >= 0
              expect
                assets.quantity_of(
                  in.output.value,
                  policy_id,
                  market_info_datum.yt_token_name,
                ) >= o_yt_amount
              let in_lovelace = assets.lovelace_of(in.output.value)
              let min_lovelace =
                o_batcher_fee + market_info_datum.envelope_amount
              expect in_lovelace >= min_lovelace
              expect list.length(assets.flatten(in.output.value)) == 2
              let pt_amount = o_yt_amount
              let sy_from_burn =
                pt_amount * oracle_datum.based / oracle_datum.py_index
              expect sy_from_burn >= o_min_sy_out
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
                        sy_from_burn,
                      ),
                  ==,
                )
              (
                acc_total_pt - pt_amount,
                acc_total_sy - sy_from_burn,
                acc_total_fee,
                in_idx,
                out_idx,
              )
            },
          )
        expect market_output_datum.total_pt == output_datum_total_pt
        expect market_output_datum.total_sy == output_datum_total_sy
        expect market_output_datum.total_fee == output_datum_total_fee
        expect
          market_output_datum.last_ln_implied_rate == market_input_datum.last_ln_implied_rate
        expect market_output_datum.total_lp == market_input_datum.total_lp
        expect market_output_datum.reserved_lp == market_input_datum.reserved_lp
        let num_token =
          mint |> assets.tokens(policy_id) |> dict.keys() |> list.length()
        expect num_token == 2
        let total_sy_transfered =
          output_datum_total_sy - market_input_datum.total_sy
        expect total_sy_transfered > 0
        let total_pt_burned =
          market_input_datum.total_pt - output_datum_total_pt
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
                  policy_id,
                  market_info_datum.sy_token_name,
                  total_sy_transfered,
                )
              |> assets.add(
                  policy_id,
                  market_info_datum.pt_token_name,
                  -total_pt_burned,
                ),
            >=,
          )
        expect
          assets.match(
            sy_vault_output.value,
            sy_vault_input.output.value
              |> assets.add(
                  policy_id,
                  market_info_datum.sy_token_name,
                  -total_sy_transfered,
                ),
            >=,
          )
        expect
          sy_vault_output_datum.total_sy == sy_vault_input_datum.total_sy - total_sy_transfered
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

  spend(
    _datum: Option<UnderlyingAssetVaultDatum>,
    redeemer: UnderlyingAssetVaultRedeemer,
    own_ref: OutputReference,
    self: Transaction,
  ) {
    let Transaction { inputs, redeemers, extra_signatories, .. } = self
    when redeemer is {
      YAVaultWrapSY { own_input_idx } -> {
        expect Some(own_input) = list.at(inputs, own_input_idx)
        expect own_input.output_reference == own_ref
        expect Script(policy_id) = own_input.output.address.payment_credential
        expect Some(wrap_mint_redeemer) =
          pairs.get_first(redeemers, Mint(policy_id))
        expect yield_tokenization_redeemer: YieldTokenizationMintRedeemer =
          wrap_mint_redeemer
        when yield_tokenization_redeemer is {
          YTWrapSY { .. } -> True
          _ -> False
        }
      }
      YAVaultUnwrapSY { own_input_idx } -> {
        expect Some(own_input) = list.at(inputs, own_input_idx)
        expect own_input.output_reference == own_ref
        expect Script(policy_id) = own_input.output.address.payment_credential
        expect Some(wrap_mint_redeemer) =
          pairs.get_first(redeemers, Mint(policy_id))
        expect yield_tokenization_redeemer: YieldTokenizationMintRedeemer =
          wrap_mint_redeemer
        when yield_tokenization_redeemer is {
          YTUnwrapSY { .. } -> True
          _ -> False
        }
      }
      YAVaultAdminAction -> list.has(extra_signatories, params.admin_pkh)
    }
  }

  else(_) {
    False
  }
}

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
  check_correct_input_payment_credential, count_input_orders, validate_license,
  validate_market_info_ref, validate_oracle_ref, validate_sy_vault_own_utxos,
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
        let oracle_datum =
          validate_oracle_ref(
            reference_inputs,
            oracle_idx,
            market_info_datum.oracle_nft,
          )
        expect
          count_input_orders(inputs, market_info_datum.order_script_hash) == 1
        expect Some(in) = list.at(inputs, order_indices.1st)
        expect Some(pt_out) = list.at(outputs, order_indices.2nd)
        expect Some(yt_out) = list.at(outputs, order_indices.3rd)
        expect
          check_correct_input_payment_credential(
            in,
            market_info_datum.order_script_hash,
          )
        expect InlineDatum(order_inline_datum) = in.output.datum
        expect order_datum: OrderDatum = order_inline_datum
        expect OSplitSY {
          o_owner_pkh: _,
          o_receive_pt_addr,
          o_receive_pt_datum,
          o_receive_yt_addr,
          o_receive_yt_datum,
        } = order_datum
        expect o_receive_pt_addr == pt_out.address
        expect o_receive_pt_datum == pt_out.datum
        expect o_receive_yt_addr == yt_out.address
        expect o_receive_yt_datum == yt_out.datum
        let sy_amount =
          assets.quantity_of(
            in.output.value,
            market_info_datum.underlying_asset.policy_id,
            market_info_datum.underlying_asset.asset_name,
          )
        expect list.length(assets.flatten(in.output.value)) == 2
        let pt_amount = sy_amount * oracle_datum.py_index / oracle_datum.based
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
        let total_sy = sy_amount
        let total_pt = pt_amount
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
        expect own_output_datum.total_sy == own_input_datum.total_sy + total_sy
        expect
          assets.match(
            own_output.value,
            own_input.output.value
              |> assets.add(
                  market_info_datum.underlying_asset.policy_id,
                  market_info_datum.underlying_asset.asset_name,
                  total_sy,
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
        expect OMergeSY { o_owner_pkh: _, o_receive_addr, o_receive_datum } =
          order_datum
        expect o_receive_addr == out.address
        expect o_receive_datum == out.datum
        let pt_amount =
          assets.quantity_of(
            in.output.value,
            market_info_datum.yield_tokenization_policy_id,
            market_info_datum.pt_token_name,
          )
        expect
          assets.quantity_of(
            in.output.value,
            market_info_datum.yield_tokenization_policy_id,
            market_info_datum.yt_token_name,
          ) >= pt_amount
        expect list.length(assets.flatten(in.output.value)) == 3
        let sy_amount = pt_amount * oracle_datum.based / oracle_datum.py_index
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
              sy_amount,
            ),
          ]
        let total_pt = pt_amount
        let total_sy = sy_amount
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
        expect own_input_datum.total_sy >= total_sy
        expect own_output_datum.total_sy == own_input_datum.total_sy - total_sy
        expect
          assets.match(
            own_input.output.value,
            own_output.value
              |> assets.add(
                  market_info_datum.underlying_asset.policy_id,
                  market_info_datum.underlying_asset.asset_name,
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
        expect Some(in_yt_stake) = list.at(inputs, order_indices.3rd)
        expect
          check_correct_input_payment_credential(
            in,
            market_info_datum.order_script_hash,
          )
        expect InlineDatum(yt_stake_inline_datum) = in_yt_stake.output.datum
        expect yt_stake_datum: YTStakeDatum = yt_stake_inline_datum
        expect InlineDatum(order_inline_datum) = in.output.datum
        expect order_datum: OrderDatum = order_inline_datum
        expect OUnstakeYT {
          o_owner_pkh,
          o_receive_addr,
          o_receive_datum,
          o_stake_id,
        } = order_datum
        expect yt_stake_datum.market_id == params.market_id
        expect yt_stake_datum.stake_id == o_stake_id
        expect yt_stake_datum.owner_pkh == o_owner_pkh
        expect o_receive_addr == out.address
        expect o_receive_datum == out.datum
        expect list.length(assets.flatten(in.output.value)) == 1
        expect oracle_datum.py_index >= yt_stake_datum.py_index
        let sy_amount =
          yt_stake_datum.staked_yt_amount * (
            oracle_datum.py_index - yt_stake_datum.py_index
          ) * oracle_datum.based / (
            yt_stake_datum.py_index * oracle_datum.py_index
          )
        trace @"out.value": out.value
        trace @"market_info_datum.underlying_asset.policy_id": market_info_datum.underlying_asset.policy_id
        trace @"market_info_datum.underlying_asset.asset_name": market_info_datum.underlying_asset.asset_name
        trace @"sy_amount": sy_amount
        trace @"market_info_datum.yield_tokenization_policy_id": market_info_datum.yield_tokenization_policy_id
        trace @"ytstake_authtoken_tn": ytstake_authtoken_tn
        trace @"yt_stake_datum.staked_yt_amount": yt_stake_datum.staked_yt_amount
        let expected_out_value =
          assets.zero
            |> assets.add(
                assets.ada_policy_id,
                assets.ada_asset_name,
                market_info_datum.envelope_amount,
              )
            |> assets.add(
                market_info_datum.underlying_asset.policy_id,
                market_info_datum.underlying_asset.asset_name,
                sy_amount,
              )
            |> assets.add(
                market_info_datum.yield_tokenization_policy_id,
                market_info_datum.yt_token_name,
                yt_stake_datum.staked_yt_amount,
              )
        expect out.value == expected_out_value
        let total_sy = sy_amount
        expect own_output_datum.total_sy == own_input_datum.total_sy - total_sy
        expect own_input_datum.total_sy >= total_sy
        expect
          assets.flatten(mint) == [
            (
              market_info_datum.ytstake_authtoken_policy_id,
              ytstake_authtoken_tn,
              -1,
            ),
          ]
        expect
          assets.match(
            own_output.value,
            own_input.output.value
              |> assets.add(
                  market_info_datum.underlying_asset.policy_id,
                  market_info_datum.underlying_asset.asset_name,
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
        expect Some(in_yt_stake) = list.at(inputs, order_indices.3rd)
        expect Some(out_yt_stake) = list.at(outputs, order_indices.4th)
        expect
          check_correct_input_payment_credential(
            in,
            market_info_datum.order_script_hash,
          )
        expect InlineDatum(in_yt_stake_inline_datum) = in_yt_stake.output.datum
        expect in_yt_stake_datum: YTStakeDatum = in_yt_stake_inline_datum
        expect InlineDatum(out_yt_stake_inline_datum) = out_yt_stake.datum
        expect out_yt_stake_datum: YTStakeDatum = out_yt_stake_inline_datum
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
          o_owner_pkh,
          o_receive_addr,
          o_receive_datum,
          o_stake_id,
        } = order_datum
        expect in_yt_stake_datum.stake_id == o_stake_id
        expect in_yt_stake_datum.owner_pkh == o_owner_pkh
        expect o_receive_addr == out.address
        expect o_receive_datum == out.datum
        expect list.length(assets.flatten(in.output.value)) == 1
        expect oracle_datum.py_index >= in_yt_stake_datum.py_index
        let sy_amount =
          in_yt_stake_datum.staked_yt_amount * (
            oracle_datum.py_index - in_yt_stake_datum.py_index
          ) * oracle_datum.based / (
            in_yt_stake_datum.py_index * oracle_datum.py_index
          )
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
              sy_amount,
            ),
          ]
        let total_sy = sy_amount
        expect own_output_datum.total_sy == own_input_datum.total_sy - total_sy
        expect own_input_datum.total_sy >= total_sy
        expect
          assets.match(
            own_output.value,
            own_input.output.value
              |> assets.add(
                  market_info_datum.underlying_asset.policy_id,
                  market_info_datum.underlying_asset.asset_name,
                  -total_sy,
                ),
            >=,
          )
        True
      }
      SYSwapSYForYT { own_input_idx, own_output_idx, market_info_ref_idx } -> {
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
        expect Some(wrap_yt_mint_redeemer) =
          pairs.get_first(
            redeemers,
            Mint(market_info_datum.yield_tokenization_policy_id),
          )
        expect yt_mint_redeemer: types.YieldTokenizationMintRedeemer =
          wrap_yt_mint_redeemer
        expect types.YTSwapSYForYT { borrowed_sy, order_indices, .. } =
          yt_mint_redeemer
        // Get SY amount from order input
        expect Some(order_in) = list.at(inputs, order_indices.1st)
        let sy_amount =
          assets.quantity_of(
            order_in.output.value,
            market_info_datum.underlying_asset.policy_id,
            market_info_datum.underlying_asset.asset_name,
          )
        // Validate vault datum update: total_sy increases by borrowed_sy + sy_amount
        expect
          own_output_datum.total_sy == own_input_datum.total_sy + borrowed_sy + sy_amount
        // Validate vault assets update: SY assets increase by borrowed_sy + sy_amount
        expect
          assets.match(
            own_output.value,
            own_input.output.value
              |> assets.add(
                  market_info_datum.underlying_asset.policy_id,
                  market_info_datum.underlying_asset.asset_name,
                  borrowed_sy + sy_amount,
                ),
            >=,
          )
        True
      }
      SYSwapYTForSY { own_input_idx, own_output_idx, market_info_ref_idx } -> {
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
        expect Some(wrap_yt_mint_redeemer) =
          pairs.get_first(
            redeemers,
            Mint(market_info_datum.yield_tokenization_policy_id),
          )
        expect yt_mint_redeemer: types.YieldTokenizationMintRedeemer =
          wrap_yt_mint_redeemer
        expect types.YTSwapYTForSY { swapped_sy, order_indices, .. } =
          yt_mint_redeemer
        expect Some(order_out) = list.at(outputs, order_indices.2nd)
        let sy_out =
          assets.quantity_of(
            order_out.value,
            market_info_datum.underlying_asset.policy_id,
            market_info_datum.underlying_asset.asset_name,
          )
        // Validate vault datum update: total_sy decreases by sy_out + swapped_sy
        // Vault loses: sy sent to user (sy_out) + sy swapped to market (swapped_sy)
        // But market sends back swapped_sy, so net vault loss is just sy_out
        // Actually, based on off-chain code line 223: vault loses syAmount + swappedSy
        expect
          own_output_datum.total_sy == own_input_datum.total_sy - sy_out - swapped_sy
        // Validate vault assets update
        expect
          assets.match(
            own_output.value,
            own_input.output.value
              |> assets.add(
                  market_info_datum.underlying_asset.policy_id,
                  market_info_datum.underlying_asset.asset_name,
                  -(sy_out + swapped_sy),
                ),
            >=,
          )
        True
      }
      SYVaultAdminAction -> list.has(extra_signatories, params.admin_pkh)
    }
  }

  else(_) {
    False
  }
}

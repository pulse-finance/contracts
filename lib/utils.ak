use aiken/builtin
use aiken/collection/dict
use aiken/collection/list
use aiken/collection/pairs
use aiken/interval.{Finite}
use aiken/math/rational
use aiken/primitive/bytearray
use aiken/primitive/string
use cardano/address.{Address, Script}
use cardano/assets.{PolicyId, Value}
use cardano/transaction.{
  InlineDatum, Input, Mint, Output, OutputReference, Redeemer, ScriptPurpose,
  ValidityRange,
}
use pulse_math
use types.{
  Asset, LPBurnLp, LPInitLp, LPMintLp, LPTokenRedeemer, MarketDatum,
  MarketInfoDatum, OracleDatum, PubKeyHash, SYVaultDatum,
  UnderlyingAssetVaultDatum, YTSwapSYForYT, YTSwapYTForSY,
  YieldTokenizationMintRedeemer,
}

pub const year_in_milliseconds = 31_536_000_000

const minus_ascii_code = 45

const zero_ascii_code = 48

pub fn check_correct_input_payment_credential(
  input: Input,
  expected_script_hash: ByteArray,
) -> Bool {
  when input.output.address.payment_credential is {
    Script(script_hash) -> script_hash == expected_script_hash
    _ -> False
  }
}

pub fn find_posix_time_range(time_rage: ValidityRange) -> (Int, Int) {
  expect Finite(t1) = time_rage.lower_bound.bound_type
  expect Finite(t2) = time_rage.upper_bound.bound_type
  (t1, t2)
}

pub fn find_license_deadline(license_symbol: PolicyId, val: Value) -> Int {
  expect [Pair(tn, am)] =
    val
      |> assets.tokens(license_symbol)
      |> dict.to_pairs()
  expect am == 1
  bytearray_to_int(tn)
}

pub fn bytearray_to_int(byte_arr: ByteArray) -> Int {
  let byte_len = bytearray.length(byte_arr)
  do_bytearray_to_int(byte_arr, 0, 0, byte_len)
}

pub fn do_bytearray_to_int(
  byte_arr: ByteArray,
  idx: Int,
  acc: Int,
  byte_len: Int,
) -> Int {
  if idx == byte_len {
    acc
  } else {
    let byte = builtin.index_bytearray(byte_arr, idx)
    if idx == 0 && byte == minus_ascii_code {
      do_bytearray_to_int(byte_arr, idx + 1, acc, byte_len) * -1
    } else if byte < zero_ascii_code || byte > zero_ascii_code + 9 {
      fail
    } else {
      do_bytearray_to_int(
        byte_arr,
        idx + 1,
        acc * 10 + ( byte - zero_ascii_code ),
        byte_len,
      )
    }
  }
}

test test_bytearray_to_int() {
  let r1 = bytearray_to_int(string.to_bytearray(@"123"))
  let r2 = bytearray_to_int(string.to_bytearray(@"111"))
  r1 == 123 && r2 == 111
}

pub fn count_input_orders(
  inputs: List<Input>,
  order_script_hash: ByteArray,
) -> Int {
  list.foldl(
    inputs,
    0,
    fn(input, acc) {
      when input.output.address.payment_credential is {
        Script(script_hash) ->
          if script_hash == order_script_hash {
            acc + 1
          } else {
            acc
          }
        _ -> acc
      }
    },
  )
}

pub fn construct_address(
  payment_key_hash: PubKeyHash,
  stake_key_hash: Option<PubKeyHash>,
) -> Address {
  when stake_key_hash is {
    Some(key) ->
      address.from_verification_key(payment_key_hash)
        |> address.with_delegation_key(key)
    None -> address.from_verification_key(payment_key_hash)
  }
}

/// Validates market info reference input and returns the market info datum
/// Checks NFT quantity and validates market_id match
pub fn validate_market_info_ref(
  reference_inputs: List<Input>,
  market_info_idx: Int,
  market_info_nft: Asset,
  expected_market_id: OutputReference,
) -> MarketInfoDatum {
  expect Some(market_info_ref_input) =
    list.at(reference_inputs, market_info_idx)
  expect
    assets.quantity_of(
      market_info_ref_input.output.value,
      market_info_nft.policy_id,
      market_info_nft.asset_name,
    ) == 1
  expect InlineDatum(market_info_inline_datum) =
    market_info_ref_input.output.datum
  expect market_info_datum: MarketInfoDatum = market_info_inline_datum
  expect market_info_datum.market_id == expected_market_id
  market_info_datum
}

/// Validates oracle reference input and returns the oracle datum
/// Checks NFT quantity and validates py_index and based are positive
pub fn validate_oracle_ref(
  reference_inputs: List<Input>,
  oracle_idx: Int,
  oracle_nft: Asset,
) -> OracleDatum {
  expect Some(oracle_ref_input) = list.at(reference_inputs, oracle_idx)
  expect InlineDatum(oracle_inline_datum) = oracle_ref_input.output.datum
  expect oracle_datum: OracleDatum = oracle_inline_datum
  expect
    assets.quantity_of(
      oracle_ref_input.output.value,
      oracle_nft.policy_id,
      oracle_nft.asset_name,
    ) == 1
  expect oracle_datum.py_index > 0 && oracle_datum.based > 0
  oracle_datum
}

/// Validates batcher license and time constraints
/// Returns the end of the validity time range
pub fn validate_license_and_expiry(
  inputs: List<Input>,
  license_idx: Int,
  batcher_policy_id: PolicyId,
  validity_range: ValidityRange,
  expiry: Int,
) -> Int {
  expect Some(Input { output: Output { value: batcher_value, .. }, .. }) =
    list.at(inputs, license_idx)
  let license_deadline = find_license_deadline(batcher_policy_id, batcher_value)
  let (_start_valid_time_range, end_valid_time_range) =
    find_posix_time_range(validity_range)
  expect license_deadline >= end_valid_time_range
  expect expiry > end_valid_time_range
  end_valid_time_range
}

/// Validates license without expiry check
/// Returns the end of the validity time range
pub fn validate_license(
  inputs: List<Input>,
  license_idx: Int,
  batcher_policy_id: PolicyId,
  validity_range: ValidityRange,
) -> Int {
  expect Some(Input { output: Output { value: batcher_value, .. }, .. }) =
    list.at(inputs, license_idx)
  let license_deadline = find_license_deadline(batcher_policy_id, batcher_value)
  let (_start_valid_time_range, end_valid_time_range) =
    find_posix_time_range(validity_range)
  expect license_deadline >= end_valid_time_range
  end_valid_time_range
}

/// Validates own input/output UTxOs for Market validator
/// Returns (own_input, own_output, own_input_datum, own_output_datum)
pub fn validate_market_own_utxos(
  option_datum: Option<MarketDatum>,
  inputs: List<Input>,
  outputs: List<Output>,
  own_input_idx: Int,
  own_output_idx: Int,
  own_outref: OutputReference,
  market_nft: Asset,
) -> (Input, Output, MarketDatum, MarketDatum) {
  expect Some(datum) = option_datum
  let own_input_datum: MarketDatum = datum
  expect Some(own_input) = list.at(inputs, own_input_idx)
  expect Some(own_output) = list.at(outputs, own_output_idx)
  expect own_input.output.address == own_output.address
  expect own_input.output_reference == own_outref
  expect InlineDatum(own_output_inline_datum) = own_output.datum
  expect own_output_datum: MarketDatum = own_output_inline_datum
  expect own_input_datum.market_id == own_output_datum.market_id
  expect
    assets.quantity_of(
      own_input.output.value,
      market_nft.policy_id,
      market_nft.asset_name,
    ) == 1
  (own_input, own_output, own_input_datum, own_output_datum)
}

/// Validates own input/output UTxOs for SY Vault validator
/// Returns (own_input, own_output, own_input_datum, own_output_datum)
pub fn validate_sy_vault_own_utxos(
  option_datum: Option<SYVaultDatum>,
  inputs: List<Input>,
  outputs: List<Output>,
  own_input_idx: Int,
  own_output_idx: Int,
  own_ref: OutputReference,
  sy_nft: Asset,
) -> (Input, Output, SYVaultDatum, SYVaultDatum) {
  expect Some(datum) = option_datum
  let own_input_datum: SYVaultDatum = datum
  expect Some(own_input) = list.at(inputs, own_input_idx)
  expect own_input.output_reference == own_ref
  expect Some(own_output) = list.at(outputs, own_output_idx)
  expect own_input.output.address == own_output.address
  expect InlineDatum(own_output_inline_datum) = own_output.datum
  expect own_output_datum: SYVaultDatum = own_output_inline_datum
  expect own_input_datum.market_id == own_output_datum.market_id
  expect
    assets.quantity_of(
      own_input.output.value,
      sy_nft.policy_id,
      sy_nft.asset_name,
    ) == 1
  (own_input, own_output, own_input_datum, own_output_datum)
}

/// Validates underlying asset vault input/output UTxOs
/// Returns (input, output, input_datum, output_datum)
pub fn validate_underlying_asset_vault_utxos(
  inputs: List<Input>,
  outputs: List<Output>,
  input_idx: Int,
  output_idx: Int,
  vault_nft: Asset,
  policy_id: PolicyId,
  expected_market_id: OutputReference,
) -> (Input, Output, UnderlyingAssetVaultDatum, UnderlyingAssetVaultDatum) {
  expect Some(vault_input) = list.at(inputs, input_idx)
  expect Some(vault_output) = list.at(outputs, output_idx)
  expect
    assets.quantity_of(
      vault_input.output.value,
      vault_nft.policy_id,
      vault_nft.asset_name,
    ) == 1
  expect
    assets.quantity_of(
      vault_output.value,
      vault_nft.policy_id,
      vault_nft.asset_name,
    ) == 1
  expect vault_input.output.address == vault_output.address
  expect vault_input.output.address.payment_credential == Script(policy_id)
  expect InlineDatum(vault_output_inline_datum) = vault_output.datum
  expect vault_output_datum: UnderlyingAssetVaultDatum =
    vault_output_inline_datum
  expect InlineDatum(vault_input_inline_datum) = vault_input.output.datum
  expect vault_input_datum: UnderlyingAssetVaultDatum = vault_input_inline_datum
  expect vault_input_datum.market_id == vault_output_datum.market_id
  expect vault_input_datum.market_id == expected_market_id
  (vault_input, vault_output, vault_input_datum, vault_output_datum)
}

/// Validates market input/output for yield tokenization swaps
/// Returns (market_input, market_output, market_input_datum, market_output_datum)
pub fn validate_yt_market_utxos(
  inputs: List<Input>,
  outputs: List<Output>,
  market_input_idx: Int,
  market_output_idx: Int,
  market_nft: Asset,
  expected_market_id: OutputReference,
) -> (Input, Output, MarketDatum, MarketDatum) {
  expect Some(market_input) = list.at(inputs, market_input_idx)
  expect Some(market_output) = list.at(outputs, market_output_idx)
  expect
    assets.quantity_of(
      market_input.output.value,
      market_nft.policy_id,
      market_nft.asset_name,
    ) == 1
  expect
    assets.quantity_of(
      market_output.value,
      market_nft.policy_id,
      market_nft.asset_name,
    ) == 1
  expect InlineDatum(market_input_inline_datum) = market_input.output.datum
  expect market_input_datum: MarketDatum = market_input_inline_datum
  expect market_input_datum.market_id == expected_market_id
  expect InlineDatum(market_output_inline_datum) = market_output.datum
  expect market_output_datum: MarketDatum = market_output_inline_datum
  expect market_input_datum.market_id == market_output_datum.market_id
  (market_input, market_output, market_input_datum, market_output_datum)
}

/// Validates LP token redeemer delegation
/// Used by MInitLp, MMintLp, MBurnLp
pub fn validate_lp_delegation(
  reference_inputs: List<Input>,
  market_info_idx: Int,
  market_info_nft: Asset,
  expected_market_id: OutputReference,
  redeemers: Pairs<ScriptPurpose, Redeemer>,
  expected_lp_redeemer_type: LPTokenRedeemer,
) -> Bool {
  let market_info_datum =
    validate_market_info_ref(
      reference_inputs,
      market_info_idx,
      market_info_nft,
      expected_market_id,
    )
  expect Some(lp_mint_redeemer) =
    pairs.get_first(redeemers, Mint(market_info_datum.lp_token_asset.policy_id))
  expect lp_redeemer: LPTokenRedeemer = lp_mint_redeemer
  when (lp_redeemer, expected_lp_redeemer_type) is {
    (LPInitLp { .. }, LPInitLp { .. }) -> True
    (LPMintLp { .. }, LPMintLp { .. }) -> True
    (LPBurnLp { .. }, LPBurnLp { .. }) -> True
    _ -> False
  }
}

/// Validates YT token redeemer delegation
/// Used by MSwapExactSYForYT, MSwapExactYTForSY
pub fn validate_yt_delegation(
  reference_inputs: List<Input>,
  market_info_idx: Int,
  market_info_nft: Asset,
  expected_market_id: OutputReference,
  redeemers: Pairs<ScriptPurpose, Redeemer>,
  expected_yt_redeemer_type: YieldTokenizationMintRedeemer,
) -> Bool {
  let market_info_datum =
    validate_market_info_ref(
      reference_inputs,
      market_info_idx,
      market_info_nft,
      expected_market_id,
    )
  expect Some(yt_mint_redeemer) =
    pairs.get_first(
      redeemers,
      Mint(market_info_datum.yield_tokenization_policy_id),
    )
  expect yt_redeemer: YieldTokenizationMintRedeemer = yt_mint_redeemer
  when (yt_redeemer, expected_yt_redeemer_type) is {
    (YTSwapSYForYT { .. }, YTSwapSYForYT { .. }) -> True
    (YTSwapYTForSY { .. }, YTSwapYTForSY { .. }) -> True
    _ -> False
  }
}

/// Calculates new ln implied rate after swap
/// Returns the new_ln_implied_rate
pub fn calculate_post_swap_rate(
  output_datum_total_sy: Int,
  output_datum_total_pt: Int,
  own_input_datum: MarketDatum,
  oracle_datum: OracleDatum,
  market_info_datum: MarketInfoDatum,
  end_valid_time_range: Int,
) -> Int {
  expect Some(output_sy_rational) = rational.new(output_datum_total_sy, 1)
  expect Some(py_index_rational) =
    rational.new(oracle_datum.py_index, oracle_datum.based)
  let total_asset_rational = rational.mul(output_sy_rational, py_index_rational)
  let total_asset = pulse_math.rational_to_int(total_asset_rational, 1)
  let time_to_expiry = market_info_datum.expiry - end_valid_time_range
  let rate_scalar =
    pulse_math.calculate_rate_scalar(
      market_info_datum.scalar_root,
      time_to_expiry,
    )
  expect Some(input_sy_rational) = rational.new(own_input_datum.total_sy, 1)
  let input_asset_rational = rational.mul(input_sy_rational, py_index_rational)
  let input_total_asset = pulse_math.rational_to_int(input_asset_rational, 1)
  let rate_anchor =
    pulse_math.calculate_rate_anchor(
      own_input_datum.last_ln_implied_rate,
      own_input_datum.total_pt,
      input_total_asset,
      rate_scalar,
      time_to_expiry,
      oracle_datum.based,
    )
  pulse_math.calculate_new_ln_implied_rate(
    output_datum_total_pt,
    total_asset,
    rate_scalar,
    rate_anchor,
    time_to_expiry,
    oracle_datum.based,
  )
}

/// Verifies market output datum and value after swap
/// Returns True if validation passes
pub fn verify_market_swap_output(
  own_output_datum: MarketDatum,
  own_input_datum: MarketDatum,
  output_datum_total_sy: Int,
  output_datum_total_pt: Int,
  output_datum_total_fee: Int,
  new_ln_implied_rate: Int,
  own_output: Output,
  own_input: Input,
  market_info_datum: MarketInfoDatum,
) -> Bool {
  expect own_output_datum.total_sy == output_datum_total_sy
  expect own_output_datum.total_pt == output_datum_total_pt
  expect own_output_datum.total_lp == own_input_datum.total_lp
  expect own_output_datum.reserved_lp == own_input_datum.reserved_lp
  expect own_output_datum.total_fee == output_datum_total_fee
  expect own_output_datum.last_ln_implied_rate == new_ln_implied_rate
  expect
    assets.match(
      own_output.value,
      own_input.output.value
        |> assets.add(
            market_info_datum.yield_tokenization_policy_id,
            market_info_datum.pt_token_name,
            output_datum_total_pt - own_input_datum.total_pt,
          )
        |> assets.add(
            market_info_datum.yield_tokenization_policy_id,
            market_info_datum.sy_token_name,
            output_datum_total_sy - own_input_datum.total_sy,
          ),
      >=,
    )
  True
}

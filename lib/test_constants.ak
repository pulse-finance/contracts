use cardano/address
use cardano/assets.{PolicyId}
use cardano/transaction.{InlineDatum, Input, Output, OutputReference}
use types.{Asset, MarketInfoDatum}

// Market constants
pub const t_market_id =
  OutputReference {
    transaction_id: #"a0e8c7cffe3c8f2b6b7d779788f50f4c9f9c4252d86702c2f4c2e49e6648c7cf",
    output_index: 0,
  }

pub const t_market_nft_policy_id: PolicyId =
  #"a0e8c7cffe3c8f2b6b7d779788f50f4c9f9c4252d86702c2f4c2e490"

pub const t_market_nft_asset_name: ByteArray = "market_nft"

pub const t_market_nft: Asset =
  Asset {
    policy_id: t_market_nft_policy_id,
    asset_name: t_market_nft_asset_name,
  }

// Market info NFT
pub const t_market_info_nft_policy_id: PolicyId =
  #"b0e8c7cffe3c8f2b6b7d779788f50f4c9f9c4252d86702c2f4c2e490"

pub const t_market_info_nft_asset_name: ByteArray = "market_info_nft"

pub const t_market_info_nft: Asset =
  Asset {
    policy_id: t_market_info_nft_policy_id,
    asset_name: t_market_info_nft_asset_name,
  }

// Yield tokenization policy
pub const t_yt_policy_id: PolicyId =
  #"c0e8c7cffe3c8f2b6b7d779788f50f4c9f9c4252d86702c2f4c2e490"

pub const t_ytstake_authtoken_policy_id: PolicyId =
  #"c4252d86702c2f4c2e490c0e8c7cffe3c8f2b6b7d779788f50f4c9f9"

// Token names
pub const t_sy_token_name: ByteArray = "SY"

pub const t_pt_token_name: ByteArray = "PT"

pub const t_yt_token_name: ByteArray = "YT"

// LP token
pub const t_lp_token_policy_id: PolicyId =
  #"d0e8c7cffe3c8f2b6b7d779788f50f4c9f9c4252d86702c2f4c2e490"

pub const t_lp_token_asset_name: ByteArray = "LP"

pub const t_lp_token_asset: Asset =
  Asset { policy_id: t_lp_token_policy_id, asset_name: t_lp_token_asset_name }

// Underlying asset
pub const t_underlying_asset_policy_id: PolicyId =
  #"e0e8c7cffe3c8f2b6b7d779788f50f4c9f9c4252d86702c2f4c2e490"

pub const t_underlying_asset_name: ByteArray = "USDC"

pub const t_underlying_asset: Asset =
  Asset {
    policy_id: t_underlying_asset_policy_id,
    asset_name: t_underlying_asset_name,
  }

// Oracle NFT
pub const t_oracle_nft_policy_id: PolicyId =
  #"f0e8c7cffe3c8f2b6b7d779788f50f4c9f9c4252d86702c2f4c2e490"

pub const t_oracle_nft_asset_name: ByteArray = "oracle_nft"

pub const t_oracle_nft: Asset =
  Asset {
    policy_id: t_oracle_nft_policy_id,
    asset_name: t_oracle_nft_asset_name,
  }

// Auth token policy
pub const t_auth_token_policy_id: PolicyId =
  #"99e8c7cffe3c8f2b6b7d779788f50f4c9f9c4252d86702c2f4c2e490"

// Batcher policy
pub const t_batcher_policy_id: ByteArray =
  #"00e8c7cffe3c8f2b6b7d779788f50f4c9f9c4252d86702c2f4c2e490"

// Order script hash
pub const t_order_script_hash: ByteArray =
  #"11e8c7cffe3c8f2b6b7d779788f50f4c9f9c4252d86702c2f4c2e490"

// SY script hash
pub const t_sy_script_hash: ByteArray =
  #"f2b6b7d779788f50f4c9f9c4252d86702c2f4c2e49011e8c7cffe3c8"

// User PKH
pub const t_user_pkh: ByteArray =
  #"6b7d779788f50f4c9f9c4252d86702c2f4c2e49e6648c7cffe3c8f00"

pub const t_user_stake_key: Option<ByteArray> =
  Some(#"c8f2b6b7d779788f50f4c9f9c4252d86702c2f4c2e49e6648c7cffe300")

// Admin PKH
pub const t_admin_pkh: ByteArray =
  #"8b7d779788f50f4c9f9c4252d86702c2f4c2e49e6648c7cffe3c8f00"

// Script hashes
pub const t_market_info_script_hash: ByteArray =
  #"33e8c7cffe3c8f2b6b7d779788f50f4c9f9c4252d86702c2f4c2e490"

pub const t_market_script_hash: ByteArray =
  #"44e8c7cffe3c8f2b6b7d779788f50f4c9f9c4252d86702c2f4c2e490"

pub const t_underlying_asset_vault_script_hash: ByteArray =
  #"55e8c7cffe3c8f2b6b7d779788f50f4c9f9c4252d86702c2f4c2e490"

// Timestamps
pub const t_expiry: Int = 1767453227635

pub const t_start_time: Int = 1727453227635

pub const t_end_time: Int = 1737453227635

// Oracle NFT
pub const t_oracle_nft_asset: Asset =
  Asset {
    policy_id: t_oracle_nft_policy_id,
    asset_name: t_oracle_nft_asset_name,
  }

// Envelope amount
pub const t_envelope_amount: Int = 2000000

// AMM parameters
pub const t_scalar_root: Int = 1000

pub const t_initial_anchor: Int = 5000

pub const t_ln_fee_rate_root: Int = 100

pub const t_min_liquidity: Int = 100

pub const t_reserve_fee_percent: Int = 500

pub const t_multiplier: Int = 10000

// Helper functions for tests

pub fn test_get_market_info() -> (Input, MarketInfoDatum) {
  let market_info_datum =
    MarketInfoDatum {
      market_id: t_market_id,
      underlying_asset: t_underlying_asset,
      min_liquidity: t_min_liquidity,
      sy_token_name: t_sy_token_name,
      pt_token_name: t_pt_token_name,
      yt_token_name: t_yt_token_name,
      expiry: t_expiry,
      reserve_fee_percent: t_reserve_fee_percent,
      multiplier: t_multiplier,
      batcher_policy_id: t_batcher_policy_id,
      order_script_hash: t_order_script_hash,
      sy_script_hash: t_sy_script_hash,
      ytstake_authtoken_policy_id: t_ytstake_authtoken_policy_id,
      yield_tokenization_policy_id: t_yt_policy_id,
      lp_token_asset: t_lp_token_asset,
      oracle_nft: t_oracle_nft_asset,
      envelope_amount: t_envelope_amount,
      scalar_root: t_scalar_root,
      initial_anchor: t_initial_anchor,
      ln_fee_rate_root: t_ln_fee_rate_root,
    }
  let market_info_input =
    Input {
      output_reference: OutputReference {
        transaction_id: #"2222222222222222222222222222222222222222222222222222222222222222",
        output_index: 0,
      },
      output: Output {
        address: address.from_script(t_market_info_script_hash),
        value: assets.from_asset(
          t_market_info_nft.policy_id,
          t_market_info_nft.asset_name,
          1,
        ),
        datum: InlineDatum(market_info_datum),
        reference_script: None,
      },
    }
  (market_info_input, market_info_datum)
}

pub fn get_license_input_output() -> (Input, Output) {
  expect Some(stake_key) = t_user_stake_key
  let user_address =
    address.from_verification_key(t_user_pkh)
      |> address.with_delegation_key(stake_key)
  let license_input =
    Input {
      output_reference: OutputReference {
        transaction_id: #"3333333333333333333333333333333333333333333333333333333333333333",
        output_index: 0,
      },
      output: Output {
        address: user_address,
        value: assets.from_lovelace(5000000)
          |> assets.add(t_batcher_policy_id, #"0000000000000002", 1),
        datum: InlineDatum(Void),
        reference_script: None,
      },
    }
  let license_output =
    Output {
      address: user_address,
      value: assets.from_lovelace(5000000)
        |> assets.add(t_batcher_policy_id, #"0000000000000002", 1),
      datum: InlineDatum(Void),
      reference_script: None,
    }
  (license_input, license_output)
}

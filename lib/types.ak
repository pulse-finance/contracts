use aiken/crypto.{Blake2b_224, Hash, VerificationKey}
use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{OutputReference}

pub type PubKeyHash =
  Hash<Blake2b_224, VerificationKey>

pub type Asset {
  policy_id: PolicyId,
  asset_name: AssetName,
}

pub type MarketInfoDatum {
  market_id: OutputReference,
  underlying_asset: Asset,
  min_liquidity: Int,
  sy_token_name: AssetName,
  pt_token_name: AssetName,
  yt_token_name: AssetName,
  expiry: Int,
  reserve_fee_percent: Int,
  // based multiplier, default 10_000
  multiplier: Int,
  batcher_policy_id: ByteArray,
  order_script_hash: ByteArray,
  sy_script_hash: ByteArray,
  ytstake_authtoken_policy_id: PolicyId,
  yield_tokenization_policy_id: PolicyId,
  lp_token_asset: Asset,
  oracle_nft: Asset,
  envelope_amount: Int,
  // AMM parameters (Pendle V2 formula)
  scalar_root: Int,
  initial_anchor: Int,
  ln_fee_rate_root: Int,
}

pub type MarketDatum {
  market_id: OutputReference,
  total_sy: Int,
  total_pt: Int,
  total_lp: Int,
  total_fee: Int,
  reserved_lp: Int,
  last_ln_implied_rate: Int,
}

pub type OrderDatum {
  OWrapSY {
    o_market_id: OutputReference,
    o_owner_pkh: PubKeyHash,
    o_owner_stake_key: Option<PubKeyHash>,
    o_batcher_fee: Int,
    o_amount: Int,
  }
  OUnwrapSY {
    o_market_id: OutputReference,
    o_owner_pkh: PubKeyHash,
    o_owner_stake_key: Option<PubKeyHash>,
    o_batcher_fee: Int,
    o_amount: Int,
  }
  OSplitSY {
    o_market_id: OutputReference,
    o_owner_pkh: PubKeyHash,
    o_owner_stake_key: Option<PubKeyHash>,
    o_receive_pt_pkh: PubKeyHash,
    o_receive_pt_stake_key: Option<PubKeyHash>,
    o_receive_yt_pkh: PubKeyHash,
    o_receive_yt_stake_key: Option<PubKeyHash>,
    o_batcher_fee: Int,
    o_sy_amount: Int,
  }
  OMergeSY {
    o_market_id: OutputReference,
    o_owner_pkh: PubKeyHash,
    o_owner_stake_key: Option<PubKeyHash>,
    o_batcher_fee: Int,
    o_pt_amount: Int,
  }
  OInitLP {
    o_market_id: OutputReference,
    o_owner_pkh: PubKeyHash,
    o_owner_stake_key: Option<PubKeyHash>,
    o_batcher_fee: Int,
    o_sy_desired_amount: Int,
    o_pt_desired_amount: Int,
    o_lp_to_account: Int,
  }
  OMintLP {
    o_market_id: OutputReference,
    o_owner_pkh: PubKeyHash,
    o_owner_stake_key: Option<PubKeyHash>,
    o_batcher_fee: Int,
    o_sy_desired_amount: Int,
    o_pt_desired_amount: Int,
  }
  OBurnLP {
    o_market_id: OutputReference,
    o_owner_pkh: PubKeyHash,
    o_owner_stake_key: Option<PubKeyHash>,
    o_receive_sy_pkh: PubKeyHash,
    o_receive_sy_stake_key: Option<PubKeyHash>,
    o_receive_pt_pkh: PubKeyHash,
    o_receive_pt_stake_key: Option<PubKeyHash>,
    o_batcher_fee: Int,
    o_lp_amount: Int,
  }
  OSwapExactSYForPT {
    o_market_id: OutputReference,
    o_owner_pkh: PubKeyHash,
    o_owner_stake_key: Option<PubKeyHash>,
    o_batcher_fee: Int,
    o_sy_amount: Int,
    o_min_pt_out: Int,
  }
  OSwapExactPTForSY {
    o_market_id: OutputReference,
    o_owner_pkh: PubKeyHash,
    o_owner_stake_key: Option<PubKeyHash>,
    o_batcher_fee: Int,
    o_pt_amount: Int,
    o_min_sy_out: Int,
  }
  OSwapExactYTForSY {
    o_market_id: OutputReference,
    o_owner_pkh: PubKeyHash,
    o_owner_stake_key: Option<PubKeyHash>,
    o_batcher_fee: Int,
    o_yt_amount: Int,
    o_min_sy_out: Int,
  }
  OSwapExactSYForYT {
    o_market_id: OutputReference,
    o_owner_pkh: PubKeyHash,
    o_owner_stake_key: Option<PubKeyHash>,
    o_batcher_fee: Int,
    o_sy_amount: Int,
    o_min_yt_out: Int,
  }
  OStakeYT {
    o_market_id: OutputReference,
    o_owner_pkh: PubKeyHash,
    o_owner_stake_key: Option<PubKeyHash>,
    o_batcher_fee: Int,
    o_yt_amount: Int,
  }
  OWithdrawYTReward {
    o_market_id: OutputReference,
    o_owner_pkh: PubKeyHash,
    o_owner_stake_key: Option<PubKeyHash>,
    o_batcher_fee: Int,
    o_stake_id: OutputReference,
  }
  OUnstakeYT {
    o_market_id: OutputReference,
    o_owner_pkh: PubKeyHash,
    o_owner_stake_key: Option<PubKeyHash>,
    o_batcher_fee: Int,
    o_stake_id: OutputReference,
  }
}

pub type UnderlyingAssetVaultDatum {
  market_id: OutputReference,
  total_underlying_asset: Int,
}

pub type SYVaultDatum {
  market_id: OutputReference,
  total_sy: Int,
}

pub type OracleDatum {
  py_index: Int,
  based: Int,
  updated_at: Int,
}

// Market Redeemer
pub type MarketRedeemer {
  // Initializes liquidity pool (delegates to lp_token)
  MInitLp { market_info_idx: Int }
  // Adds liquidity (delegates to lp_token)
  MMintLp { market_info_idx: Int }
  // Removes liquidity (delegates to lp_token)
  MBurnLp { market_info_idx: Int }
  //Swaps an exact amount of PT for SY.
  MSwapExactPTForSY {
    own_input_idx: Int,
    own_output_idx: Int,
    market_info_idx: Int,
    oracle_idx: Int,
    license_idx: Int,
    order_indices: List<(Int, Int)>,
  }
  //Swaps an exact amount of SY for PT.
  MSwapExactSYForPT {
    own_input_idx: Int,
    own_output_idx: Int,
    market_info_idx: Int,
    oracle_idx: Int,
    license_idx: Int,
    order_indices: List<(Int, Int)>,
  }
  //Swaps an exact amount of SY for YT (delegates to yield_tokenization)
  MSwapExactSYForYT { market_info_idx: Int }
  //Swaps an exact amount of YT for SY (delegates to yield_tokenization)
  MSwapExactYTForSY { market_info_idx: Int }
  MAdminOperation
}

// LP Token Redeemer
pub type LPTokenRedeemer {
  LPInitLp {
    market_info_ref_idx: Int,
    order_indices: (Int, Int),
    license_idx: Int,
    market_input_idx: Int,
    market_output_idx: Int,
  }
  LPMintLp {
    market_info_ref_idx: Int,
    order_indices: List<(Int, Int)>,
    license_idx: Int,
    market_input_idx: Int,
    market_output_idx: Int,
  }
  LPBurnLp {
    market_info_ref_idx: Int,
    order_indices: List<(Int, Int, Int)>,
    license_idx: Int,
    market_input_idx: Int,
    market_output_idx: Int,
  }
  LPRefTokenAction
}

// Yield Tokenization Redeemer
pub type YieldTokenizationMintRedeemer {
  YTWrapSY {
    market_info_ref_idx: Int,
    order_indices: List<(Int, Int)>,
    input_underlying_asset_vault_idx: Int,
    output_underlying_asset_vault_idx: Int,
    license_idx: Int,
  }
  YTUnwrapSY {
    market_info_ref_idx: Int,
    order_indices: List<(Int, Int)>,
    input_underlying_asset_vault_idx: Int,
    output_underlying_asset_vault_idx: Int,
    license_idx: Int,
  }
  YTSplitSY { sy_vault_input_idx: Int }
  YTMergeSY { sy_vault_input_idx: Int }
  YTSwapSYForYT {
    market_info_ref_idx: Int,
    order_indices: List<(Int, Int)>,
    oracle_idx: Int,
    license_idx: Int,
    market_input_idx: Int,
    market_output_idx: Int,
    sy_vault_input_idx: Int,
    sy_vault_output_idx: Int,
  }
  YTSwapYTForSY {
    market_info_ref_idx: Int,
    order_indices: List<(Int, Int)>,
    oracle_idx: Int,
    license_idx: Int,
    market_input_idx: Int,
    market_output_idx: Int,
    sy_vault_input_idx: Int,
    sy_vault_output_idx: Int,
  }
  YTBurn
  YTRefTokenAction
}

pub type SYVaultRedeemer {
  SYVaultSplitSY {
    own_input_idx: Int,
    own_output_idx: Int,
    market_info_ref_idx: Int,
    order_indices: List<(Int, Int, Int)>,
    oracle_idx: Int,
    license_idx: Int,
  }
  SYVaultMergeSY {
    own_input_idx: Int,
    own_output_idx: Int,
    market_info_ref_idx: Int,
    order_indices: List<(Int, Int)>,
    oracle_idx: Int,
    license_idx: Int,
  }
  SYUnstakeYT {
    own_input_idx: Int,
    own_output_idx: Int,
    market_info_ref_idx: Int,
    order_indices: List<(Int, Int, Int)>,
    oracle_idx: Int,
    license_idx: Int,
  }
  SYWithdrawYTReward {
    own_input_idx: Int,
    own_output_idx: Int,
    market_info_ref_idx: Int,
    order_indices: List<(Int, Int, Int, Int)>,
    oracle_idx: Int,
    license_idx: Int,
  }
  SYSwapSYForYT { market_info_ref_idx: Int }
  SYSwapYTForSY { market_info_ref_idx: Int }
  SYVaultAdminAction
}

pub type YTStakeDatum {
  market_id: OutputReference,
  stake_id: OutputReference,
  owner_pkh: PubKeyHash,
  staked_yt_amount: Int,
  py_index: Int,
}

pub type YTStakeAuthTokenRedeemer {
  YTStake {
    yt_stake_output_idx: Int,
    seed_input_idx: Int,
    market_info_ref_idx: Int,
    oracle_idx: Int,
  }
  YTUnstake { sy_in_idx: Int }
}

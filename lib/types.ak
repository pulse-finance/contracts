use aiken/crypto.{Blake2b_224, Hash, VerificationKey}
use cardano/address.{Address}
use cardano/assets.{AssetName, PolicyId}
use cardano/transaction.{Datum, OutputReference}

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
  pt_token_name: AssetName,
  yt_token_name: AssetName,
  // milliseconds since 1970
  expiry: Int,
  // milliseconds
  duration: Int,
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
  init_py_index: Int,
  // Borrow fee for YT swaps (f_borrow in Section 2.5.3/2.5.4)
  ln_borrow_fee_rate: Int,
}

pub type MarketDatum {
  market_id: OutputReference,
  total_sy: Int,
  total_pt: Int,
  total_lp: Int,
  reserved_lp: Int,
}

pub type OrderDatum {
  OSplitSY {
    o_owner_pkh: PubKeyHash,
    o_receive_pt_addr: Address,
    o_receive_pt_datum: Datum,
    o_receive_yt_addr: Address,
    o_receive_yt_datum: Datum,
  }
  OMergeSY {
    o_owner_pkh: PubKeyHash,
    o_receive_addr: Address,
    o_receive_datum: Datum,
  }
  OInitLP { o_owner_pkh: PubKeyHash, o_owner_stake_key: Option<PubKeyHash> }
  OMintLP {
    o_owner_pkh: PubKeyHash,
    o_receive_addr: Address,
    o_receive_datum: Datum,
  }
  OBurnLP {
    o_owner_pkh: PubKeyHash,
    o_receive_sy_addr: Address,
    o_receive_sy_datum: Datum,
    o_receive_pt_addr: Address,
    o_receive_pt_datum: Datum,
  }
  // slippage protection is useful for when batcher handles order much later than submission
  OSwapExactSYForPT {
    o_owner_pkh: PubKeyHash,
    o_receive_addr: Address,
    o_receive_datum: Datum,
    o_min_pt_out: Int,
  }
  OSwapExactPTForSY {
    o_owner_pkh: PubKeyHash,
    o_receive_addr: Address,
    o_receive_datum: Datum,
    o_min_sy_out: Int,
  }
  OSwapExactYTForSY {
    o_owner_pkh: PubKeyHash,
    o_receive_addr: Address,
    o_receive_datum: Datum,
    o_min_sy_out: Int,
  }
  OSwapExactSYForYT {
    o_owner_pkh: PubKeyHash,
    o_receive_addr: Address,
    o_receive_datum: Datum,
    o_min_yt_out: Int,
  }
  OWithdrawYTReward {
    o_owner_pkh: PubKeyHash,
    o_receive_addr: Address,
    o_receive_datum: Datum,
    o_stake_id: OutputReference,
  }
  OUnstakeYT {
    o_owner_pkh: PubKeyHash,
    o_receive_addr: Address,
    o_receive_datum: Datum,
    o_stake_id: OutputReference,
  }
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
    order_indices: (Int, Int),
  }
  //Swaps an exact amount of SY for PT.
  MSwapExactSYForPT {
    own_input_idx: Int,
    own_output_idx: Int,
    market_info_idx: Int,
    oracle_idx: Int,
    license_idx: Int,
    order_indices: (Int, Int),
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
    order_indices: (Int, Int),
    license_idx: Int,
    market_input_idx: Int,
    market_output_idx: Int,
  }
  LPBurnLp {
    market_info_ref_idx: Int,
    order_indices: (Int, Int, Int),
    license_idx: Int,
    market_input_idx: Int,
    market_output_idx: Int,
  }
  LPRefTokenAction
}

// Yield Tokenization Redeemer
pub type YieldTokenizationMintRedeemer {
  YTSplitSY { sy_vault_input_idx: Int }
  YTMergeSY { sy_vault_input_idx: Int }
  YTSwapSYForYT {
    market_info_ref_idx: Int,
    order_indices: (Int, Int),
    oracle_idx: Int,
    license_idx: Int,
    market_input_idx: Int,
    market_output_idx: Int,
    borrowed_sy: Int,
  }
  YTSwapYTForSY {
    market_info_ref_idx: Int,
    order_indices: (Int, Int),
    oracle_idx: Int,
    license_idx: Int,
    market_input_idx: Int,
    market_output_idx: Int,
    swapped_sy: Int,
  }
  YTBurn
  YTRefTokenAction
}

pub type SYVaultRedeemer {
  SYVaultSplitSY {
    own_input_idx: Int,
    own_output_idx: Int,
    market_info_ref_idx: Int,
    order_indices: (Int, Int, Int),
    oracle_idx: Int,
    license_idx: Int,
  }
  SYVaultMergeSY {
    own_input_idx: Int,
    own_output_idx: Int,
    market_info_ref_idx: Int,
    order_indices: (Int, Int),
    oracle_idx: Int,
    license_idx: Int,
  }
  SYUnstakeYT {
    own_input_idx: Int,
    own_output_idx: Int,
    market_info_ref_idx: Int,
    order_indices: (Int, Int, Int),
    oracle_idx: Int,
    license_idx: Int,
  }
  SYWithdrawYTReward {
    own_input_idx: Int,
    own_output_idx: Int,
    market_info_ref_idx: Int,
    order_indices: (Int, Int, Int, Int),
    oracle_idx: Int,
    license_idx: Int,
  }
  SYSwapSYForYT {
    own_input_idx: Int,
    own_output_idx: Int,
    market_info_ref_idx: Int,
  }
  SYSwapYTForSY {
    own_input_idx: Int,
    own_output_idx: Int,
    market_info_ref_idx: Int,
  }
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

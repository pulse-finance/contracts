use aiken/primitive/string

pub const market_info_nft_tn = string.to_bytearray(@"MARKET_INFO_NFT")

pub const market_nft_tn = string.to_bytearray(@"MARKET_NFT")

pub const sy_vault_nft_tn = string.to_bytearray(@"SY_VAULT_NFT")

pub const ytstake_authtoken_tn = string.to_bytearray(@"YTSTAKE_AUTHTOKEN")

// used by ln-related math (ln, logit, phi, pi, epsilon)
pub const precision = 1_000_000

pub const precision_sq = 1_000_000_000_000

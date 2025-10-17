use aiken/collection/dict
use aiken/collection/list
use aiken/interval.{Finite, Interval, IntervalBound}
use cardano/address.{Credential}
use cardano/assets.{flatten}
use cardano/transaction.{OutputReference, Transaction}
use test_constants.{t_admin_pkh, t_batcher_policy_id, t_market_id}

pub type LicenseRedeemer {
  Mint { dead_line: ByteArray }
  Burn
}

pub type BatcherParams {
  admin_pkh: ByteArray,
  market_id: OutputReference,
}

validator batcher(params: BatcherParams) {
  mint(redeemer: LicenseRedeemer, policy_id: ByteArray, self: Transaction) {
    let Transaction { extra_signatories, mint, .. } = self
    expect list.has(extra_signatories, params.admin_pkh)
    when redeemer is {
      Mint { dead_line } -> flatten(mint) == [(policy_id, dead_line, 1)]
      Burn ->
        list.foldl(
          flatten(mint),
          True,
          fn(curr, acc) {
            let (_, _, quantity) = curr
            acc && quantity < 0
          },
        )
    }
  }

  withdraw(_redeemer: Data, _account: Credential, self: Transaction) {
    let Transaction { extra_signatories, .. } = self
    list.has(extra_signatories, params.admin_pkh)
  }

  publish(_redeemer: Data, _account: Credential, self: Transaction) {
    let Transaction { extra_signatories, .. } = self
    list.has(extra_signatories, params.admin_pkh)
  }

  else(_) {
    fail
  }
}

// Test: Successful mint of license token with deadline
test batcher_mint_license_success() {
  let policy_id = t_batcher_policy_id
  let deadline = #"0000000000000001"
  let tx =
    Transaction {
      inputs: [],
      reference_inputs: [],
      outputs: [],
      fee: 0,
      mint: assets.from_asset(policy_id, deadline, 1),
      certificates: [],
      withdrawals: [],
      validity_range: Interval {
        lower_bound: IntervalBound {
          bound_type: Finite(1727453227635),
          is_inclusive: False,
        },
        upper_bound: IntervalBound {
          bound_type: Finite(1737453227635),
          is_inclusive: False,
        },
      },
      extra_signatories: [t_admin_pkh],
      redeemers: [],
      datums: dict.empty,
      id: #"0000000000000000000000000000000000000000000000000000000000000000",
      votes: [],
      proposal_procedures: [],
      current_treasury_amount: None,
      treasury_donation: None,
    }
  let redeemer = Mint { dead_line: deadline }
  let params = BatcherParams { admin_pkh: t_admin_pkh, market_id: t_market_id }
  batcher.mint(params, redeemer, policy_id, tx)
}

// Test: Mint without admin signature should fail
test batcher_mint_license_no_admin_fail() fail {
  let policy_id = t_batcher_policy_id
  let deadline = #"0000000000000001"
  let tx =
    Transaction {
      inputs: [],
      reference_inputs: [],
      outputs: [],
      fee: 0,
      mint: assets.from_asset(policy_id, deadline, 1),
      certificates: [],
      withdrawals: [],
      validity_range: Interval {
        lower_bound: IntervalBound {
          bound_type: Finite(1727453227635),
          is_inclusive: False,
        },
        upper_bound: IntervalBound {
          bound_type: Finite(1737453227635),
          is_inclusive: False,
        },
      },
      extra_signatories: [],
      redeemers: [],
      datums: dict.empty,
      id: #"0000000000000000000000000000000000000000000000000000000000000000",
      votes: [],
      proposal_procedures: [],
      current_treasury_amount: None,
      treasury_donation: None,
    }
  let redeemer = Mint { dead_line: deadline }
  let params = BatcherParams { admin_pkh: t_admin_pkh, market_id: t_market_id }
  batcher.mint(params, redeemer, policy_id, tx)
}

// Test: Mint with multiple tokens should fail
test batcher_mint_multiple_tokens_fail() fail {
  let policy_id = t_batcher_policy_id
  let deadline = #"0000000000000001"
  let tx =
    Transaction {
      inputs: [],
      reference_inputs: [],
      outputs: [],
      fee: 0,
      mint: assets.from_asset(policy_id, deadline, 1)
        |> assets.add(policy_id, #"0000000000000002", 1),
      certificates: [],
      withdrawals: [],
      validity_range: Interval {
        lower_bound: IntervalBound {
          bound_type: Finite(1727453227635),
          is_inclusive: False,
        },
        upper_bound: IntervalBound {
          bound_type: Finite(1737453227635),
          is_inclusive: False,
        },
      },
      extra_signatories: [t_admin_pkh],
      redeemers: [],
      datums: dict.empty,
      id: #"0000000000000000000000000000000000000000000000000000000000000000",
      votes: [],
      proposal_procedures: [],
      current_treasury_amount: None,
      treasury_donation: None,
    }
  let redeemer = Mint { dead_line: deadline }
  let params = BatcherParams { admin_pkh: t_admin_pkh, market_id: t_market_id }
  batcher.mint(params, redeemer, policy_id, tx)
}

// Test: Mint with wrong quantity should fail
test batcher_mint_wrong_quantity_fail() fail {
  let policy_id = t_batcher_policy_id
  let deadline = #"0000000000000001"
  let tx =
    Transaction {
      inputs: [],
      reference_inputs: [],
      outputs: [],
      fee: 0,
      mint: assets.from_asset(policy_id, deadline, 2),
      certificates: [],
      withdrawals: [],
      validity_range: Interval {
        lower_bound: IntervalBound {
          bound_type: Finite(1727453227635),
          is_inclusive: False,
        },
        upper_bound: IntervalBound {
          bound_type: Finite(1737453227635),
          is_inclusive: False,
        },
      },
      extra_signatories: [t_admin_pkh],
      redeemers: [],
      datums: dict.empty,
      id: #"0000000000000000000000000000000000000000000000000000000000000000",
      votes: [],
      proposal_procedures: [],
      current_treasury_amount: None,
      treasury_donation: None,
    }
  let redeemer = Mint { dead_line: deadline }
  let params = BatcherParams { admin_pkh: t_admin_pkh, market_id: t_market_id }
  batcher.mint(params, redeemer, policy_id, tx)
}

// Test: Successful burn of license tokens
test batcher_burn_license_success() {
  let policy_id = t_batcher_policy_id
  let deadline1 = #"0000000000000001"
  let deadline2 = #"0000000000000002"
  let tx =
    Transaction {
      inputs: [],
      reference_inputs: [],
      outputs: [],
      fee: 0,
      mint: assets.from_asset(policy_id, deadline1, -1)
        |> assets.add(policy_id, deadline2, -2),
      certificates: [],
      withdrawals: [],
      validity_range: Interval {
        lower_bound: IntervalBound {
          bound_type: Finite(1727453227635),
          is_inclusive: False,
        },
        upper_bound: IntervalBound {
          bound_type: Finite(1737453227635),
          is_inclusive: False,
        },
      },
      extra_signatories: [t_admin_pkh],
      redeemers: [],
      datums: dict.empty,
      id: #"0000000000000000000000000000000000000000000000000000000000000000",
      votes: [],
      proposal_procedures: [],
      current_treasury_amount: None,
      treasury_donation: None,
    }
  let redeemer = Burn
  let params = BatcherParams { admin_pkh: t_admin_pkh, market_id: t_market_id }
  batcher.mint(params, redeemer, policy_id, tx)
}

// Test: Burn without admin signature should fail
test batcher_burn_no_admin_fail() fail {
  let policy_id = t_batcher_policy_id
  let deadline = #"0000000000000001"
  let tx =
    Transaction {
      inputs: [],
      reference_inputs: [],
      outputs: [],
      fee: 0,
      mint: assets.from_asset(policy_id, deadline, -1),
      certificates: [],
      withdrawals: [],
      validity_range: Interval {
        lower_bound: IntervalBound {
          bound_type: Finite(1727453227635),
          is_inclusive: False,
        },
        upper_bound: IntervalBound {
          bound_type: Finite(1737453227635),
          is_inclusive: False,
        },
      },
      extra_signatories: [],
      redeemers: [],
      datums: dict.empty,
      id: #"0000000000000000000000000000000000000000000000000000000000000000",
      votes: [],
      proposal_procedures: [],
      current_treasury_amount: None,
      treasury_donation: None,
    }
  let redeemer = Burn
  let params = BatcherParams { admin_pkh: t_admin_pkh, market_id: t_market_id }
  batcher.mint(params, redeemer, policy_id, tx)
}

// Test: Burn with positive quantity should fail
test batcher_burn_positive_quantity_fail() fail {
  let policy_id = t_batcher_policy_id
  let deadline = #"0000000000000001"
  let tx =
    Transaction {
      inputs: [],
      reference_inputs: [],
      outputs: [],
      fee: 0,
      mint: assets.from_asset(policy_id, deadline, 1),
      certificates: [],
      withdrawals: [],
      validity_range: Interval {
        lower_bound: IntervalBound {
          bound_type: Finite(1727453227635),
          is_inclusive: False,
        },
        upper_bound: IntervalBound {
          bound_type: Finite(1737453227635),
          is_inclusive: False,
        },
      },
      extra_signatories: [t_admin_pkh],
      redeemers: [],
      datums: dict.empty,
      id: #"0000000000000000000000000000000000000000000000000000000000000000",
      votes: [],
      proposal_procedures: [],
      current_treasury_amount: None,
      treasury_donation: None,
    }
  let redeemer = Burn
  let params = BatcherParams { admin_pkh: t_admin_pkh, market_id: t_market_id }
  batcher.mint(params, redeemer, policy_id, tx)
}

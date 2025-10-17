use aiken/collection/list
use cardano/transaction.{OutputReference, Transaction}
use types.{MarketInfoDatum, PubKeyHash}

pub type MarketInfoParams {
  admin_pkh: PubKeyHash,
  market_id: OutputReference,
}

validator market_info(params: MarketInfoParams) {
  spend(
    _datum: Option<MarketInfoDatum>,
    _redeemer: Data,
    _utxo: OutputReference,
    self: Transaction,
  ) {
    let Transaction { extra_signatories, .. } = self
    list.has(extra_signatories, params.admin_pkh)
  }

  else(_) {
    fail
  }
}

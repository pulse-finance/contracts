use constants.{precision, precision_sq}
use epsilon.{calc_epsilon}

fn r_accent_from_scalar_root(scalar_root: Int, based: Int) -> Int {
  based * precision / scalar_root
}

fn r_expected_from_initial_anchor(initial_anchor: Int, based: Int) -> Int {
  initial_anchor * precision / based
}

fn f_amm_from_ln_fee_rate_root(ln_fee_rate_root: Int, based: Int) -> Int {
  ln_fee_rate_root * precision / based
}

fn p_split_from_py_index(py_index: Int, based: Int) -> Int {
  py_index * precision / based
}

/// Calculate normalized time to maturity 
///
/// Parameters:
/// - current_time: milliseconds since 1970
/// - expiry: milliseconds since 1970
/// - duration: milliseconds
///
/// Returns: a number from 1 to 0, scaled by `precision`
fn calc_t(current_time: Int, expiry: Int, duration: Int) -> Int {
  ( expiry - current_time ) * precision / duration
}

// ============================================================================
// NEW SWAP VALIDATION FUNCTIONS (Efficient - Section 2.5 of whitepaper)
// ============================================================================

/// Validates PT→SY swap (selling PT for SY)
/// Formula from section 2.5.2: -Δy/Δx ≥ (p_split,t / (1 - f_AMM)) * π(x + Δx, y + Δy, t)
/// With PT→SY swap: Δy = +pt_in (pool gains PT), Δx = -sy_out (pool loses SY)
/// So: -Δy/Δx = -pt_in/(-sy_out) = pt_in/sy_out
/// Rearranging for validation: pt_in/sy_out ≤ (1 - f_AMM) * p_split,t / π = inverse of formula
///
/// Parameters:
/// - pt_in: amount of PT being sold (positive)
/// - sy_out: amount of SY to receive (positive, calculated off-chain)
/// - total_pt: current PT in pool (before swap)
/// - total_sy: current SY in pool (before swap)
/// - py_index: scaled by `based`
/// - init_py_index: scaled by `based`
/// - scalar_root: scaled by `based`
/// - initial_anchor: scaled by `based`
/// - ln_fee_rate_root: scaled by `based`
/// - expiry: milliseconds since 1970
/// - current_time: milliseconds since 1970
/// - based: precision of py_index, scalar_root, initial_anchor and ln_fee_rate_root
///
/// Returns: true if the swap satisfies the price constraint
pub fn validate_pt_to_sy_swap(
  pt_in: Int,
  sy_out: Int,
  total_pt: Int,
  total_sy: Int,
  py_index: Int,
  init_py_index: Int,
  scalar_root: Int,
  initial_anchor: Int,
  ln_fee_rate_root: Int,
  expiry: Int,
  current_time: Int,
  duration: Int,
  based: Int,
) -> Bool {
  // Whitepaper Section 2.4.3: PT → SY with fees
  // Uses epsilon (residual) validation with dual checks
  // Δx = -sy_out (negative because SY decreases)
  // Δy = pt_in (positive because PT increases)

  // Fee factor f = 1/(1 - f_AMM), scaled by `precision`
  let f_amm = f_amm_from_ln_fee_rate_root(ln_fee_rate_root, based)
  let f = precision_sq / ( precision - f_amm )

  let t = calc_t(current_time, expiry, duration)
  let p_split = p_split_from_py_index(py_index, based)
  let p_split_ref = p_split_from_py_index(init_py_index, based)

  let r_expected = r_expected_from_initial_anchor(initial_anchor, based)
  let r_accent = r_accent_from_scalar_root(scalar_root, based)

  // 1. Protect the market: ε(Δx, Δy, 1/(1-f_AMM)) ≥ 0
  // where Δx = -sy_out, Δy = pt_in
  let dx = -sy_out
  let dy = pt_in
  let residual_market =
    calc_epsilon(
      total_sy,
      dx,
      total_pt,
      dy,
      t,
      f,
      p_split,
      p_split_ref,
      r_expected,
      r_accent,
    )
  trace @"residual_market": residual_market

  let market_protected = residual_market >= 0

  // 2. Protect the user: ε(Δx - 1, Δy, 1/(1-f_AMM)) ≤ 0
  // Δx - 1 = -sy_out - 1 (prefer Δx closer to 0, i.e., sy_out smaller)
  let residual_user =
    calc_epsilon(
      total_sy,
      dx - 1,
      total_pt,
      dy,
      t,
      f,
      p_split,
      p_split_ref,
      r_expected,
      r_accent,
    )
  trace @"residual_user": residual_user

  let user_protected = residual_user <= 0

  market_protected && user_protected
}

/// Validates SY→PT swap (buying PT with SY)
/// Formula from section 2.5.1: -Δy/Δx ≤ (1 - f_AMM) * p_split,t * π(x + Δx, y + Δy, t)
/// where π(x, y, t) = 1 + (r̄ - 1 + r' * ln(y/(p_split,ref * x))) * t
///
/// Parameters:
/// - sy_in: amount of SY being sold (positive)
/// - pt_out: amount of PT to receive (positive, calculated off-chain)
/// - total_pt: current PT in pool
/// - total_sy: current SY in pool
/// - py_index: scaled by `based`
/// - init_py_index: scaled by `based`
/// - scalar_root, scaled by `based`
/// - initial_anchor, scaled by `based`
/// - ln_fee_rate_root, scaled by `based`
/// - expiry: milliseconds since 1970
/// - current_time: milliseconds since 1970
/// - based: precision of py_index, scalar_root, initial_anchor and ln_fee_rate_root
///
/// Returns: true if the swap satisfies the price constraint
pub fn validate_sy_to_pt_swap(
  sy_in: Int,
  pt_out: Int,
  total_pt: Int,
  total_sy: Int,
  py_index: Int,
  init_py_index: Int,
  scalar_root: Int,
  initial_anchor: Int,
  ln_fee_rate_root: Int,
  expiry: Int,
  current_time: Int,
  duration: Int,
  based: Int,
) -> Bool {
  // Whitepaper Section 2.4.2: SY → PT with fees
  // Uses epsilon (residual) validation with dual checks
  // Δx = sy_in (positive because SY increases)
  // Δy = -pt_out (negative because PT decreases)

  // Fee factor f = 1 - f_AMM, scaled by `precision`
  let f_amm = f_amm_from_ln_fee_rate_root(ln_fee_rate_root, based)
  let f = precision - f_amm
  let t = calc_t(current_time, expiry, duration)
  let p_split = p_split_from_py_index(py_index, based)
  let p_split_ref = p_split_from_py_index(init_py_index, based)

  let r_expected = r_expected_from_initial_anchor(initial_anchor, based)
  let r_accent = r_accent_from_scalar_root(scalar_root, based)

  // 1. Protect the market: ε(Δx, Δy, 1 - f_AMM) ≤ 0
  // where Δx = sy_in, Δy = -pt_out
  let dx = sy_in
  let dy = -pt_out
  let residual_market =
    calc_epsilon(
      total_sy,
      dx,
      total_pt,
      dy,
      t,
      f,
      p_split,
      p_split_ref,
      r_expected,
      r_accent,
    )
  trace @"residual_market": residual_market

  let market_protected = residual_market <= 0

  // 2. Protect the user: ε(Δx, Δy - 1, 1 - f_AMM) ≥ 0
  // Δy - 1 = -pt_out - 1 (prefer Δy closer to 0, i.e., pt_out larger in magnitude)
  let residual_user =
    calc_epsilon(
      total_sy,
      dx,
      total_pt,
      dy - 1,
      t,
      f,
      p_split,
      p_split_ref,
      r_expected,
      r_accent,
    )
  trace @"residual_user": residual_user

  let user_protected = residual_user >= 0

  market_protected && user_protected
}

/// Validates SY→YT swap with fees and slippage (Section 2.5.3)
/// Formula: (n+m)p_split,t / m = [(1+f_borrow)/(1-f_AMM)] * p_split,t * π(x-m, y+p_split,t(n+m), t)
///
/// This implements the borrow-split-swap-repay mechanism:
/// 1. User provides n SY
/// 2. Borrow m SY from faucet
/// 3. Split (n+m) SY into (n+m)p_split PT and YT
/// 4. Swap (n+m)p_split PT for SY via AMM
/// 5. Repay m(1+f_borrow) SY to faucet
/// 6. User receives (n+m)p_split YT
///
/// Parameters:
/// - sy_in: amount of SY provided by user (n)
/// - borrowed_sy: amount of SY borrowed (m, calculated off-chain)
/// - yt_out: amount of YT to receive (should equal pt_out)
/// - total_pt: current PT in pool before swap
/// - total_sy: current SY in pool before swap
/// - py_index: scaled by `based`
/// - init_py_index: scaled by `based`
/// - scalar_root: scaled by `based`
/// - initial_anchor: scaled by `based`
/// - ln_fee_rate_root: scaled by `based`
/// - ln_borrow_fee_rate: scaled by `based`
/// - expiry: milliseconds since 1970
/// - current_time: milliseconds since 1970
/// - based: precision of py_index, scalar_root, initial_anchor, ln_fee_rate_root, ln_borrow_fee_rate
///
/// Returns: true if the swap satisfies the price constraint with proper bounds
pub fn validate_sy_to_yt_swap(
  sy_in: Int,
  borrowed_sy: Int,
  yt_out: Int,
  total_pt: Int,
  total_sy: Int,
  py_index: Int,
  init_py_index: Int,
  scalar_root: Int,
  initial_anchor: Int,
  ln_fee_rate_root: Int,
  ln_borrow_fee_rate: Int,
  expiry: Int,
  current_time: Int,
  duration: Int,
  based: Int,
) -> Bool {
  // Calculate fee factor: (1 + f_borrow) / (1 - f_AMM)
  let f_amm = f_amm_from_ln_fee_rate_root(ln_fee_rate_root, based)
  let f_borrow = f_amm_from_ln_fee_rate_root(ln_borrow_fee_rate, based)
  let f = precision * ( precision + f_borrow ) / ( precision - f_amm )

  let t = calc_t(current_time, expiry, duration)
  let p_split = p_split_from_py_index(py_index, based)
  let p_split_ref = p_split_from_py_index(init_py_index, based)

  let r_expected = r_expected_from_initial_anchor(initial_anchor, based)
  let r_accent = r_accent_from_scalar_root(scalar_root, based)

  // After swap: Δx = -borrowed_sy (pool loses SY), Δy = +pt_out (pool gains PT)
  // Validation per Section 2.5.3:
  // 1. Protect the market: ε(-m, (n+m)p_split,t, fee_factor) ≥ 0
  // 2. Protect the user: ε(-(m+1), (n+m+1)p_split,t, fee_factor) ≤ 0
  let dx = -borrowed_sy
  let dy = p_split * ( sy_in + borrowed_sy ) / precision

  let residual_market =
    calc_epsilon(
      total_sy,
      dx,
      total_pt,
      dy,
      t,
      f,
      p_split,
      p_split_ref,
      r_expected,
      r_accent,
    )
  trace @"residual_market": residual_market

  let market_protected = residual_market >= 0

  let received_expected = yt_out == dy

  let dx_user = -borrowed_sy - 1
  let dy_user = p_split * ( sy_in + borrowed_sy + 1 ) / precision
  let residual_user =
    calc_epsilon(
      total_sy,
      dx_user,
      total_pt,
      dy_user,
      t,
      f,
      p_split,
      p_split_ref,
      r_expected,
      r_accent,
    )
  trace @"residual_user": residual_user

  let user_protected = residual_user <= 0

  received_expected && market_protected && user_protected
}

/// Validates YT→SY swap with fees and slippage (Section 2.5.4)
/// Formula: n / m = [(1-f_AMM)/(1+f_borrow)] * p_split,t * π(x+m, y-n, t)
///
/// This implements the borrow-merge-swap-repay mechanism:
/// 1. User provides n YT
/// 2. Borrow n PT from faucet
/// 3. Merge n YT + n PT into n/p_split SY
/// 4. Swap m SY for PT via AMM
/// 5. Repay n(1+f_borrow) PT to faucet
/// 6. User receives (n/p_split - m) SY
///
/// Parameters:
/// - yt_in: amount of YT provided by user (n YT = n PT after merge)
/// - swapped_sy: amount of SY swapped for PT (m, calculated off-chain)
/// - sy_out: amount of SY to receive
/// - total_pt: current PT in pool before swap
/// - total_sy: current SY in pool before swap
/// - py_index: scaled by `based`
/// - init_py_index: scaled by `based`
/// - scalar_root: scaled by `based`
/// - initial_anchor: scaled by `based`
/// - ln_fee_rate_root: scaled by `based`
/// - ln_borrow_fee_rate: scaled by `based`
/// - expiry: milliseconds since 1970
/// - current_time: milliseconds since 1970
/// - based: precision of py_index, scalar_root, initial_anchor, ln_fee_rate_root, ln_borrow_fee_rate
///
/// Returns: true if the swap satisfies the price constraint with proper bounds
pub fn validate_yt_to_sy_swap(
  yt_in: Int,
  swapped_sy: Int,
  sy_out: Int,
  total_pt: Int,
  total_sy: Int,
  py_index: Int,
  init_py_index: Int,
  scalar_root: Int,
  initial_anchor: Int,
  ln_fee_rate_root: Int,
  ln_borrow_fee_rate: Int,
  expiry: Int,
  current_time: Int,
  duration: Int,
  based: Int,
) -> Bool {
  // Calculate fee factor: (1 - f_AMM) / (1 + f_borrow)
  let f_amm = f_amm_from_ln_fee_rate_root(ln_fee_rate_root, based)
  let f_borrow = f_amm_from_ln_fee_rate_root(ln_borrow_fee_rate, based)
  let f = precision * ( precision - f_amm ) / ( precision + f_borrow )

  let t = calc_t(current_time, expiry, duration)
  let p_split = p_split_from_py_index(py_index, based)
  let p_split_ref = p_split_from_py_index(init_py_index, based)

  let r_expected = r_expected_from_initial_anchor(initial_anchor, based)
  let r_accent = r_accent_from_scalar_root(scalar_root, based)

  let received_expected = sy_out == yt_in * precision / p_split - swapped_sy

  // After swap: Δx = +swapped_sy (pool gains SY), Δy = -pt_in (pool loses PT that was borrowed)
  // Validation per Section 2.5.4:
  // 1. Protect the market: ε(m, -n, fee_factor) ≤ 0
  // 2. Protect the user: ε(m-1, -n, fee_factor) ≥ 0
  let dx = swapped_sy
  let dy = -yt_in

  let residual_market =
    calc_epsilon(
      total_sy,
      dx,
      total_pt,
      dy,
      t,
      f,
      p_split,
      p_split_ref,
      r_expected,
      r_accent,
    )
  trace @"residual_market": residual_market

  let market_protected = residual_market <= 0

  let dx_user = swapped_sy - 1
  let dy_user = dy

  let residual_user =
    calc_epsilon(
      total_sy,
      dx_user,
      total_pt,
      dy_user,
      t,
      f,
      p_split,
      p_split_ref,
      r_expected,
      r_accent,
    )
  trace @"residual_user": residual_user

  let user_protected = residual_user >= 0

  received_expected && market_protected && user_protected
}

// ============================================================================
// TESTS
// ============================================================================

test py_to_sy_swap_1() {
  let pt_in = 10000
  let sy_out = 4807

  let total_sy = 3010051
  let total_pt = 1505026
  let based = 10000
  let py_index = 25000
  let init_py_index = 10000
  let scalar_root = 24413
  let initial_anchor = 11000
  let ln_fee_rate_root = 150
  let expiry = 1794283134749
  let current_time = 1762753074749
  let duration = 31536000000

  validate_pt_to_sy_swap(
    pt_in,
    sy_out,
    total_pt,
    total_sy,
    py_index,
    init_py_index,
    scalar_root,
    initial_anchor,
    ln_fee_rate_root,
    expiry,
    current_time,
    duration,
    based,
  )
}

test py_to_sy_swap_2() {
  let pt_in = 10000
  let sy_out = 3231

  let total_sy = 3010051
  let total_pt = 1505026
  let based = 10000
  let py_index = 25000
  let init_py_index = 10000
  let scalar_root = 24413
  let initial_anchor = 15000
  let ln_fee_rate_root = 150
  let expiry = 1794381034442
  let current_time = 1762851174442
  let duration = 31536000000

  validate_pt_to_sy_swap(
    pt_in,
    sy_out,
    total_pt,
    total_sy,
    py_index,
    init_py_index,
    scalar_root,
    initial_anchor,
    ln_fee_rate_root,
    expiry,
    current_time,
    duration,
    based,
  )
}

test sy_to_pt_swap_1() {
  let sy_in = 10000
  let pt_out = 19928

  let total_sy = 3010051
  let total_pt = 1505026
  let based = 10000
  let py_index = 25000
  let init_py_index = 10000
  let scalar_root = 24413
  let initial_anchor = 11000
  let ln_fee_rate_root = 150
  let expiry = 1794283134749
  let current_time = 1762753074749
  let duration = 31536000000

  validate_sy_to_pt_swap(
    sy_in,
    pt_out,
    total_pt,
    total_sy,
    py_index,
    init_py_index,
    scalar_root,
    initial_anchor,
    ln_fee_rate_root,
    expiry,
    current_time,
    duration,
    based,
  )
}

test yt_to_sy_swap_1() {
  let yt_in = 10000
  let sy_swapped = 3349
  let sy_out = 651

  let total_sy = 3010051
  let total_pt = 1505026
  let based = 10000
  let py_index = 25000
  let init_py_index = 10000
  let scalar_root = 24413
  let initial_anchor = 15000
  let ln_fee_rate_root = 150
  let ln_borrow_fee_rate = 0
  let expiry = 1794283134749
  let current_time = 1762753074749
  let duration = 31536000000

  validate_yt_to_sy_swap(
    yt_in,
    sy_swapped,
    sy_out,
    total_pt,
    total_sy,
    py_index,
    init_py_index,
    scalar_root,
    initial_anchor,
    ln_fee_rate_root,
    ln_borrow_fee_rate,
    expiry,
    current_time,
    duration,
    based,
  )
}

test sy_to_yt_swap_1() {
  let sy_in = 651
  let sy_borrowed = 2743
  let yt_out = 8485

  let total_sy = 3010051
  let total_pt = 1505026
  let based = 10000
  let py_index = 25000
  let init_py_index = 10000
  let scalar_root = 24413
  let initial_anchor = 15000
  let ln_fee_rate_root = 150
  let ln_borrow_fee_rate = 0
  let expiry = 1794283134749
  let current_time = 1762753074749
  let duration = 31536000000

  validate_sy_to_yt_swap(
    sy_in,
    sy_borrowed,
    yt_out,
    total_pt,
    total_sy,
    py_index,
    init_py_index,
    scalar_root,
    initial_anchor,
    ln_fee_rate_root,
    ln_borrow_fee_rate,
    expiry,
    current_time,
    duration,
    based,
  )
}

test sy_to_yt_swap_2() {
  let sy_in = 50_000
  let sy_borrowed = 136_084
  let yt_out = 465_210

  let total_sy = 3016795
  let total_pt = 1485316
  let based = 10000
  let py_index = 25000
  let init_py_index = 10000
  let scalar_root = 24413
  let initial_anchor = 15000
  let ln_fee_rate_root = 150
  let ln_borrow_fee_rate = 50
  let expiry = 1794382210864
  let current_time = 1762852390864
  let duration = 31536000000

  validate_sy_to_yt_swap(
    sy_in,
    sy_borrowed,
    yt_out,
    total_pt,
    total_sy,
    py_index,
    init_py_index,
    scalar_root,
    initial_anchor,
    ln_fee_rate_root,
    ln_borrow_fee_rate,
    expiry,
    current_time,
    duration,
    based,
  )
}

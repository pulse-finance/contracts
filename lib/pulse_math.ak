use aiken/collection/list
use aiken/math
use aiken/math/rational

pub const max_term_ln = 10

pub const max_term_rational_ln = 10

pub const max_term_exp = 10

pub fn ln2() -> rational.Rational {
  expect Some(ln2) = rational.new(693147181, 1_000_000_000)
  ln2
}

/// Computes the exponential function for rational numbers.
/// Uses exponentiation by squaring for the integer part
/// and a second-order Taylor series for the fractional part.
pub fn rational_exp(x: rational.Rational) -> rational.Rational {
  expect Some(e) = rational.new(2718281829, 1_000_000_000)
  let (n, f) = rational.proper_fraction(x)
  expect Some(base_exp) = rational.pow(e, n)
  approx_exp_taylor(f, max_term_exp)
    |> rational.mul(base_exp)
}

pub fn rational_to_int(x: rational.Rational, base: Int) -> Int {
  rational.numerator(x) * base / rational.denominator(x)
}

fn factorial(n: Int) -> Int {
  if n <= 1 {
    1
  } else {
    n * factorial(n - 1)
  }
}

/// Approximates the exponential function using a second-order Taylor series expansion.
/// exp(x) ≈ 1 + x + (x^2 / 2) + (x^3 / 6) + (x^4 / 24)
fn approx_exp_taylor(f: rational.Rational, maxTerm: Int) -> rational.Rational {
  let terms = list.range(1, maxTerm)

  let (sum, _) =
    list.foldl(
      terms,
      (rational.from_int(1), rational.from_int(1)),
      fn(i, acc) {
        let (sum, xPower) = acc
        let xPowerNext = rational.mul(xPower, f)
        expect Some(term) =
          rational.div(xPowerNext, rational.from_int(factorial(i)))

        (rational.add(sum, term), xPowerNext)
      },
    )
  sum
}

//ln(a + x) = ln(a) + x/a - x²/(2a²) + x³/(3a³) - x⁴/(4a⁴) + ...
fn approx_log(n: Int, maxTerm: Int) -> rational.Rational {
  if n <= 0 {
    fail @"log2 undefined for non-positive"
  } else {
    // Calculate k such that 2^k <= n < 2^(k+1)
    let k = math.log2(n)
    let pow2 = math.pow(2, k)
    let fracNum = n
    let fracDen = pow2

    expect Some(frac) = rational.new(fracNum, fracDen)

    // Define onePointFive = 3/2
    expect Some(onePointFive) = rational.new(3, 2)
    // Adjust k if frac >= 1.5
    let (k, frac) =
      if rational.compare(frac, onePointFive) == Greater {
        let k1 = k + 1
        let pow2_1 = pow2 * 2
        expect Some(f) = rational.new(n, pow2_1)
        (k1, f)
      } else {
        (k, frac)
      }

    // Choose expansion based on frac
    let (_, taylor) =
      if rational.compare(frac, rational.from_int(1)) == Greater {
        // frac >= 1 → ln(1+x)
        let x = rational.sub(frac, rational.from_int(1))
        let terms = list.range(2, maxTerm)
        let (sum, _) =
          list.foldl(
            terms,
            (x, x),
            fn(i, acc) {
              let (sum, xPower) = acc
              let xPowerNext = rational.mul(xPower, x)
              expect Some(term) = rational.div(xPowerNext, rational.from_int(i))
              let updatedSum =
                if i % 2 == 0 {
                  rational.sub(sum, term)
                } else {
                  rational.add(sum, term)
                }
              (updatedSum, xPowerNext)
            },
          )
        (x, sum)
      } else {
        // frac < 1 → ln(1-x)
        let x = rational.sub(rational.from_int(1), frac)
        let terms = list.range(2, maxTerm)
        let (sum, _) =
          list.foldl(
            terms,
            (x, x),
            fn(i, acc) {
              let (sum, xPower) = acc
              let xPowerNext = rational.mul(xPower, x)
              expect Some(term) = rational.div(xPowerNext, rational.from_int(i))
              let updatedSum = rational.add(sum, term)
              // all positive
              (updatedSum, xPowerNext)
            },
          )
        (x, rational.negate(sum))
      }

    // ln(1-x) = -sum
    let kLn2 = rational.mul(rational.from_int(k), ln2())
    expect Some(result) = rational.div(rational.add(kLn2, taylor), ln2())
    result
  }
}

pub fn approx_ln(a: Int) -> rational.Rational {
  let log2a = approx_log(a, max_term_ln)
  rational.mul(log2a, ln2())
}

pub fn rational_ln(x: rational.Rational) -> rational.Rational {
  expect rational.numerator(x) > rational.denominator(x)

  let (n, f) = rational.proper_fraction(x)
  let base = approx_ln(n)
  let nf = rational.from_int(n)
  expect Some(term1) = rational.div(f, nf)
  let terms = list.range(2, max_term_rational_ln)
  let (result, _, _) =
    list.foldl(
      terms,
      (rational.add(base, term1), f, nf),
      fn(k, acc) {
        let (result, f_power, n_power) = acc
        let f_power_next = rational.mul(f_power, f)
        let n_power_next = rational.mul(n_power, nf)
        expect Some(temp) = rational.div(f_power_next, n_power_next)
        expect Some(scaled) = rational.div(temp, rational.from_int(k))
        let updated_result =
          if k % 2 == 0 {
            rational.sub(result, scaled)
          } else {
            rational.add(result, scaled)
          }
        (updated_result, f_power_next, n_power_next)
      },
    )

  result
}

// Constants for fixed-point arithmetic (18 decimals precision)
pub const precision = 1_000_000_000_000_000_000

pub const one_year_in_seconds = 31_536_000

/// Calculate rate scalar: scalarRoot / yearsToExpiry
/// Returns rational for precise calculation
pub fn calculate_rate_scalar(
  scalar_root: Int,
  time_to_expiry: Int,
) -> rational.Rational {
  expect Some(scalar_rational) = rational.new(scalar_root, 1)
  expect Some(years_to_expiry) =
    rational.new(time_to_expiry, one_year_in_seconds)
  expect Some(result) = rational.div(scalar_rational, years_to_expiry)
  result
}

/// Calculate ln(p / (1-p)) where p is the proportion
/// Returns rational for precise calculation
/// Handles cases where p/(1-p) <= 1 by using ln(a/b) = ln(a) - ln(b)
pub fn ln_proportion(
  proportion_num: Int,
  proportion_den: Int,
) -> rational.Rational {
  // p = proportion_num / proportion_den
  // ln(p/(1-p)) = ln(proportion_num / (proportion_den - proportion_num))

  let denominator_part = proportion_den - proportion_num

  // If proportion_num > denominator_part, we can use rational_ln directly
  // Otherwise, we use: ln(a/b) = -ln(b/a)
  if proportion_num > denominator_part {
    expect Some(p_ratio) = rational.new(proportion_num, denominator_part)
    rational_ln(p_ratio)
  } else if proportion_num == denominator_part {
    // ln(1) = 0
    rational.from_int(0)
  } else {
    // proportion_num < denominator_part, so p/(1-p) < 1
    // Use: ln(a/b) = -ln(b/a)
    expect Some(p_ratio_inverse) =
      rational.new(denominator_part, proportion_num)
    let ln_inverse = rational_ln(p_ratio_inverse)
    rational.negate(ln_inverse)
  }
}

/// Calculate exchange rate without fees
/// exchangeRate = ln(p/(1-p)) / rateScalar + rateAnchor
pub fn calculate_exchange_rate_no_fee(
  total_pt: Int,
  total_asset: Int,
  pt_to_account: Int,
  rate_scalar: rational.Rational,
  rate_anchor: rational.Rational,
) -> rational.Rational {
  let pt_after = total_pt - pt_to_account
  let ln_prop = ln_proportion(pt_after, pt_after + total_asset)
  // exchangeRate = ln_prop / rate_scalar + rate_anchor
  expect Some(ln_over_scalar) = rational.div(ln_prop, rate_scalar)
  rational.add(ln_over_scalar, rate_anchor)
}

/// Calculate exchange rate with fee for PT->SY swap
/// When selling PT: exchangeRate = exchangeRateNoFee * exp(lnFeeRate * yearsToExpiry)
pub fn calculate_exchange_rate_with_fee(
  exchange_rate_no_fee: rational.Rational,
  ln_fee_rate_root: Int,
  time_to_expiry: Int,
  based: Int,
) -> rational.Rational {
  // feeRate^yearsToExpiry = exp(lnFeeRate * yearsToExpiry)
  expect Some(years_to_expiry_rational) =
    rational.new(time_to_expiry, one_year_in_seconds)
  expect Some(ln_fee_rational) = rational.new(ln_fee_rate_root, based)
  let exp_arg = rational.mul(ln_fee_rational, years_to_expiry_rational)
  let fee_multiplier = rational_exp(exp_arg)
  rational.mul(exchange_rate_no_fee, fee_multiplier)
}

/// Calculate rate anchor for interest rate continuity
/// rateAnchor = lastImpliedRate^yearsToExpiry - ln(p/(1-p)) / rateScalar
pub fn calculate_rate_anchor(
  last_ln_implied_rate: Int,
  total_pt: Int,
  total_asset: Int,
  rate_scalar: rational.Rational,
  time_to_expiry: Int,
  based: Int,
) -> rational.Rational {
  // exp(lastLnImpliedRate * yearsToExpiry)
  expect Some(years_to_expiry_rational) =
    rational.new(time_to_expiry, one_year_in_seconds)
  expect Some(ln_rate_rational) = rational.new(last_ln_implied_rate, based)
  let exp_arg = rational.mul(ln_rate_rational, years_to_expiry_rational)
  let exchange_rate_star = rational_exp(exp_arg)

  // ln(p/(1-p)) / rateScalar
  let ln_prop = ln_proportion(total_pt, total_pt + total_asset)
  expect Some(ln_prop_over_scalar) = rational.div(ln_prop, rate_scalar)

  rational.sub(exchange_rate_star, ln_prop_over_scalar)
}

/// Core trade execution function (like Pendle's calcTrade)
/// net_pt_to_account: positive = PT goes to user (buying PT), negative = PT comes from user (selling PT)
/// Returns (net_sy_to_account, sy_fee, sy_to_reserve)
/// - If buying PT: net_sy_to_account is negative (user pays SY)
/// - If selling PT: net_sy_to_account is positive (user receives SY)
pub fn execute_trade_core(
  net_pt_to_account: Int,
  total_pt: Int,
  total_asset: Int,
  py_index: Int,
  rate_scalar: rational.Rational,
  rate_anchor: rational.Rational,
  ln_fee_rate_root: Int,
  reserve_fee_percent: Int,
  time_to_expiry: Int,
  based: Int,
) -> (Int, Int, Int) {
  // Calculate exchange rate without fee
  let pre_fee_exchange_rate =
    calculate_exchange_rate_no_fee(
      total_pt,
      total_asset,
      net_pt_to_account,
      rate_scalar,
      rate_anchor,
    )

  // Pre-fee asset calculation: (netPt / exchangeRate).neg()
  // This makes preFeeAsset negative when buying PT, positive when selling PT
  expect Some(net_pt_rational) = rational.new(net_pt_to_account, 1)
  expect Some(pre_fee_asset_rational) =
    rational.div(net_pt_rational, pre_fee_exchange_rate)
  let pre_fee_asset_rational_neg = rational.negate(pre_fee_asset_rational)
  let pre_fee_asset_to_account = rational_to_int(pre_fee_asset_rational_neg, 1)

  // Calculate fee (always negative to reduce user's received amount)
  let fee_asset =
    if net_pt_to_account > 0 {
      // Buying PT: fee = preFeeAsset * (1 - feeRate)
      // preFeeAsset is negative, so fee is negative
      let fee_multiplier =
        calculate_fee_multiplier(ln_fee_rate_root, time_to_expiry, based)
      // (1 - feeRate)
      let one_rational = rational.from_int(1)
      let one_minus_fee = rational.sub(one_rational, fee_multiplier)
      let fee_rational = rational.mul(pre_fee_asset_rational_neg, one_minus_fee)
      rational_to_int(fee_rational, 1)
    } else {
      // Selling PT: fee = ((preFeeAsset * (1 - feeRate)) / feeRate).neg()
      // preFeeAsset is positive, result is negated to make fee negative
      let fee_multiplier =
        calculate_fee_multiplier(ln_fee_rate_root, time_to_expiry, based)
      let one_rational = rational.from_int(1)
      let one_minus_fee = rational.sub(one_rational, fee_multiplier)
      let numerator = rational.mul(pre_fee_asset_rational_neg, one_minus_fee)
      expect Some(fee_before_neg) = rational.div(numerator, fee_multiplier)
      let fee_rational = rational.negate(fee_before_neg)
      rational_to_int(fee_rational, 1)
    }

  // netAssetToAccount = preFeeAsset - fee
  let net_asset_to_account = pre_fee_asset_to_account - fee_asset

  // Calculate reserve fee (always positive)
  let abs_fee =
    if fee_asset < 0 {
      -fee_asset
    } else {
      fee_asset
    }
  expect Some(abs_fee_rational) = rational.new(abs_fee, 1)
  expect Some(reserve_percent_rational) = rational.new(reserve_fee_percent, 100)
  let asset_to_reserve_rational =
    rational.mul(abs_fee_rational, reserve_percent_rational)
  let asset_to_reserve = rational_to_int(asset_to_reserve_rational, 1)

  // Convert to SY
  expect Some(net_asset_rational) = rational.new(net_asset_to_account, 1)
  expect Some(sy_index_rational) = rational.new(based, py_index)
  let net_sy_to_account_rational =
    rational.mul(net_asset_rational, sy_index_rational)
  let net_sy_to_account = rational_to_int(net_sy_to_account_rational, 1)

  expect Some(abs_fee_asset_rational) = rational.new(abs_fee, 1)
  let sy_fee_rational = rational.mul(abs_fee_asset_rational, sy_index_rational)
  let sy_fee = rational_to_int(sy_fee_rational, 1)

  expect Some(asset_reserve_rational) = rational.new(asset_to_reserve, 1)
  let sy_reserve_rational =
    rational.mul(asset_reserve_rational, sy_index_rational)
  let sy_to_reserve = rational_to_int(sy_reserve_rational, 1)

  (net_sy_to_account, sy_fee, sy_to_reserve)
}

/// Calculate SY output for exact PT input
/// Returns (sy_out, sy_fee, sy_to_reserve)
pub fn calculate_sy_out_for_pt_in(
  exact_pt_in: Int,
  total_pt: Int,
  total_sy: Int,
  py_index: Int,
  scalar_root: Int,
  last_ln_implied_rate: Int,
  ln_fee_rate_root: Int,
  reserve_fee_percent: Int,
  expiry: Int,
  current_time: Int,
  based: Int,
) -> (Int, Int, Int) {
  let time_to_expiry = expiry - current_time

  // Calculate total asset (SY in asset terms)
  expect Some(total_sy_rational) = rational.new(total_sy, 1)
  expect Some(py_index_rational) = rational.new(py_index, based)
  let total_asset_rational = rational.mul(total_sy_rational, py_index_rational)
  let total_asset = rational_to_int(total_asset_rational, 1)

  // Calculate rate scalar
  let rate_scalar = calculate_rate_scalar(scalar_root, time_to_expiry)

  // Calculate rate anchor (for interest rate continuity)
  let rate_anchor =
    calculate_rate_anchor(
      last_ln_implied_rate,
      total_pt,
      total_asset,
      rate_scalar,
      time_to_expiry,
      based,
    )

  // Pass negative PT amount (PT comes from user)
  let (net_sy_to_account, sy_fee, sy_to_reserve) =
    execute_trade_core(
      -exact_pt_in,
      total_pt,
      total_asset,
      py_index,
      rate_scalar,
      rate_anchor,
      ln_fee_rate_root,
      reserve_fee_percent,
      time_to_expiry,
      based,
    )

  // net_sy_to_account is positive (user receives SY)
  (net_sy_to_account, sy_fee, sy_to_reserve)
}

/// Calculate PT output for exact SY input using binary search
/// Returns (pt_out, sy_fee, sy_to_reserve)
pub fn calculate_pt_out_for_sy_in(
  exact_sy_in: Int,
  total_pt: Int,
  total_sy: Int,
  py_index: Int,
  scalar_root: Int,
  last_ln_implied_rate: Int,
  ln_fee_rate_root: Int,
  reserve_fee_percent: Int,
  expiry: Int,
  current_time: Int,
  based: Int,
) -> (Int, Int, Int) {
  let time_to_expiry = expiry - current_time

  // Calculate total asset (SY in asset terms)
  expect Some(total_sy_rational) = rational.new(total_sy, 1)
  expect Some(py_index_rational) = rational.new(py_index, based)
  let total_asset_rational = rational.mul(total_sy_rational, py_index_rational)
  let total_asset = rational_to_int(total_asset_rational, 1)

  // Convert exact_sy_in to target_asset_in (negative because user pays)
  expect Some(exact_sy_rational) = rational.new(exact_sy_in, 1)
  let target_asset_in_rational =
    rational.mul(exact_sy_rational, py_index_rational)
  let target_asset_in = -rational_to_int(target_asset_in_rational, 1)

  // Calculate rate scalar
  let rate_scalar = calculate_rate_scalar(scalar_root, time_to_expiry)

  // Calculate rate anchor (for interest rate continuity)
  let rate_anchor =
    calculate_rate_anchor(
      last_ln_implied_rate,
      total_pt,
      total_asset,
      rate_scalar,
      time_to_expiry,
      based,
    )

  // Binary search for pt_out (positive, goes to user)
  let pt_out =
    binary_search_pt_for_sy(
      target_asset_in,
      total_pt,
      total_asset,
      py_index,
      rate_scalar,
      rate_anchor,
      ln_fee_rate_root,
      reserve_fee_percent,
      time_to_expiry,
      based,
    )

  // Call execute_trade_core to get exact fees
  let (_net_sy_to_account, sy_fee, sy_to_reserve) =
    execute_trade_core(
      pt_out,
      total_pt,
      total_asset,
      py_index,
      rate_scalar,
      rate_anchor,
      ln_fee_rate_root,
      reserve_fee_percent,
      time_to_expiry,
      based,
    )

  // _net_sy_to_account is negative (user pays SY), we just return fees
  (pt_out, sy_fee, sy_to_reserve)
}

/// Binary search to find pt_out that results in the target SY in
fn binary_search_pt_for_sy(
  target_sy_in: Int,
  total_pt: Int,
  total_asset: Int,
  py_index: Int,
  rate_scalar: rational.Rational,
  rate_anchor: rational.Rational,
  ln_fee_rate_root: Int,
  reserve_fee_percent: Int,
  time_to_expiry: Int,
  based: Int,
) -> Int {
  // Binary search bounds
  let mut_low = 0
  let mut_high = total_pt - 1
  // Can't take all PT
  let mut_result = 0

  // 50 iterations should be enough for convergence
  let mut_iterations = 50

  binary_search_loop(
    mut_low,
    mut_high,
    mut_result,
    mut_iterations,
    target_sy_in,
    total_pt,
    total_asset,
    py_index,
    rate_scalar,
    rate_anchor,
    ln_fee_rate_root,
    reserve_fee_percent,
    time_to_expiry,
    based,
  )
}

fn binary_search_loop(
  low: Int,
  high: Int,
  result: Int,
  iterations: Int,
  target_sy_in: Int,
  total_pt: Int,
  total_asset: Int,
  py_index: Int,
  rate_scalar: rational.Rational,
  rate_anchor: rational.Rational,
  ln_fee_rate_root: Int,
  reserve_fee_percent: Int,
  time_to_expiry: Int,
  based: Int,
) -> Int {
  if iterations == 0 || low >= high {
    result
  } else {
    let mid = ( low + high ) / 2

    // Calculate SY in for this pt_out guess using execute_trade_core
    let (net_sy_to_account, _fee, _reserve) =
      execute_trade_core(
        mid,
        total_pt,
        total_asset,
        py_index,
        rate_scalar,
        rate_anchor,
        ln_fee_rate_root,
        reserve_fee_percent,
        time_to_expiry,
        based,
      )

    // net_sy_to_account is negative (user pays SY)
    // target_sy_in is also negative
    if net_sy_to_account > target_sy_in {
      // Need more PT out, search higher
      binary_search_loop(
        mid + 1,
        high,
        mid,
        iterations - 1,
        target_sy_in,
        total_pt,
        total_asset,
        py_index,
        rate_scalar,
        rate_anchor,
        ln_fee_rate_root,
        reserve_fee_percent,
        time_to_expiry,
        based,
      )
    } else if net_sy_to_account < target_sy_in {
      // Need less PT out, search lower
      binary_search_loop(
        low,
        mid - 1,
        result,
        iterations - 1,
        target_sy_in,
        total_pt,
        total_asset,
        py_index,
        rate_scalar,
        rate_anchor,
        ln_fee_rate_root,
        reserve_fee_percent,
        time_to_expiry,
        based,
      )
    } else {
      // Exact match
      mid
    }
  }
}

/// Calculate fee multiplier: exp(ln_fee_rate * years_to_expiry)
fn calculate_fee_multiplier(
  ln_fee_rate_root: Int,
  time_to_expiry: Int,
  based: Int,
) -> rational.Rational {
  expect Some(ln_fee_rational) = rational.new(ln_fee_rate_root, based)
  expect Some(years_to_expiry_rational) =
    rational.new(time_to_expiry, one_year_in_seconds)
  let exp_arg = rational.mul(ln_fee_rational, years_to_expiry_rational)
  rational_exp(exp_arg)
}

/// Calculate new ln(implied rate) after swap
pub fn calculate_new_ln_implied_rate(
  total_pt: Int,
  total_asset: Int,
  rate_scalar: rational.Rational,
  rate_anchor: rational.Rational,
  time_to_expiry: Int,
  based: Int,
) -> Int {
  // exchangeRate at new state (pt_to_account = 0)
  let exchange_rate =
    calculate_exchange_rate_no_fee(
      total_pt,
      total_asset,
      0,
      rate_scalar,
      rate_anchor,
    )

  // ln(exchangeRate)
  let ln_exchange_rate = rational_ln(exchange_rate)

  // lnImpliedRate = lnRate * oneYear / timeToExpiry
  expect Some(one_year_rational) = rational.new(one_year_in_seconds, 1)
  expect Some(time_to_expiry_rational) = rational.new(time_to_expiry, 1)
  expect Some(annualization_factor) =
    rational.div(one_year_rational, time_to_expiry_rational)
  let ln_implied_rate_rational =
    rational.mul(ln_exchange_rate, annualization_factor)
  rational_to_int(ln_implied_rate_rational, based)
}

// ============================================================================
// TESTS
// ============================================================================

test test_calculate_rate_scalar() {
  // Test: scalarRoot=100, timeToExpiry=1 year
  let rate_scalar = calculate_rate_scalar(100, one_year_in_seconds)
  let result = rational_to_int(rate_scalar, 1)
  // Expected: 100 / 1 = 100
  result == 100
}

test test_calculate_rate_scalar_half_year() {
  // Test: scalarRoot=100, timeToExpiry=6 months (half year)
  let half_year = one_year_in_seconds / 2
  let rate_scalar = calculate_rate_scalar(100, half_year)
  let result = rational_to_int(rate_scalar, 1)
  // Expected: 100 / 0.5 = 200
  result == 200
}

test test_ln_proportion_equal() {
  // Test: p = 0.5 (equal proportions)
  // ln(0.5/(1-0.5)) = ln(1) = 0
  let ln_p = ln_proportion(50, 100)
  let result = rational_to_int(ln_p, precision)
  // Should be close to 0
  result >= -1000 && result <= 1000
}

test test_ln_proportion_high() {
  // Test: p = 0.9 (high proportion)
  // ln(0.9/0.1) = ln(9) ≈ 2.197
  let ln_p = ln_proportion(90, 100)
  let result = rational_to_int(ln_p, precision)
  // Expected: ~2.197 * 10^18
  let expected = 2_197_000_000_000_000_000
  let tolerance = 100_000_000_000_000_000
  result > expected - tolerance && result < expected + tolerance
}

test test_calculate_exchange_rate_no_fee_simple() {
  // Test simple case: totalPt=1000, totalAsset=1000, ptToAccount=0
  // p = 1000/2000 = 0.5
  // ln(p/(1-p)) = ln(1) = 0
  // exchangeRate = 0/rateScalar + rateAnchor = rateAnchor
  let based = 1_000_000_000_000_000_000

  expect Some(rate_scalar) = rational.new(10, 1)
  expect Some(rate_anchor) = rational.new(1, 1)

  // rate_anchor = 1.0
  let exchange_rate =
    calculate_exchange_rate_no_fee(1000, 1000, 0, rate_scalar, rate_anchor)
  let result = rational_to_int(exchange_rate, based)

  // Should equal rate_anchor = 1 * based
  result == based
}

test test_calculate_sy_out_for_pt_in_basic() {
  // Scenario: Small swap in balanced pool
  // totalPt = 1_000_000, totalSy = 1_000_000
  // pyIndex = 1 (1:1), exact_pt_in = 1000
  // With no fees and balanced pool, should get ~1000 SY back
  let based = 1_000_000_000_000_000_000
  let total_pt = 1_000_000
  let total_sy = 1_000_000
  let py_index = based
  let exact_pt_in = 1000
  let scalar_root = 50
  let last_ln_implied_rate = 0
  let ln_fee_rate_root = 0
  // 0% fee
  let reserve_fee_percent = 0
  let expiry = 31_536_000 * 2
  // 2 years from now
  let current_time = 0

  let (sy_out, sy_fee, sy_to_reserve) =
    calculate_sy_out_for_pt_in(
      exact_pt_in,
      total_pt,
      total_sy,
      py_index,
      scalar_root,
      last_ln_implied_rate,
      ln_fee_rate_root,
      reserve_fee_percent,
      expiry,
      current_time,
      based,
    )

  // With no fees and balanced pool, output should be close to input
  // Allow 10% tolerance for AMM slippage
  sy_out > 900 && sy_out < 1100 && sy_fee == 0 && sy_to_reserve == 0
}

test test_calculate_sy_out_with_fee() {
  // Scenario: Swap with fees
  // totalPt = 1_000_000, totalSy = 1_000_000
  // pyIndex = 1 (1:1), exact_pt_in = 10000
  // ln_fee_rate_root represents ln(1.003) ≈ 0.003 (0.3% fee)
  let based = 1_000_000_000_000_000_000
  let total_pt = 1_000_000
  let total_sy = 1_000_000
  let py_index = based
  let exact_pt_in = 10_000
  let scalar_root = 50
  let last_ln_implied_rate = 0
  // ln(1.003) ≈ 0.002995 * based
  let ln_fee_rate_root = 2_995_000_000_000_000
  let reserve_fee_percent = 20
  // 20% of fees go to reserve
  let expiry = 31_536_000
  // 1 year from now
  let current_time = 0

  let (sy_out, sy_fee, sy_to_reserve) =
    calculate_sy_out_for_pt_in(
      exact_pt_in,
      total_pt,
      total_sy,
      py_index,
      scalar_root,
      last_ln_implied_rate,
      ln_fee_rate_root,
      reserve_fee_percent,
      expiry,
      current_time,
      based,
    )

  // sy_out should be less than exact_pt_in due to fees
  // sy_fee should be > 0
  // sy_to_reserve should be ~20% of sy_fee
  sy_out < exact_pt_in && sy_out > 9_500 && sy_fee > 0 && sy_to_reserve > 0
}

test test_calculate_new_ln_implied_rate() {
  // Test that we can calculate ln implied rate
  let based = 1_000_000_000_000_000_000
  let total_pt = 1_000_000
  let total_asset = 1_000_000

  expect Some(rate_scalar) = rational.new(50, 1)
  // Set rate_anchor > 1 so exchangeRate > 1 and ln(exchangeRate) > 0
  expect Some(rate_anchor) = rational.new(2, 1)

  // rate_anchor = 2.0
  let time_to_expiry = one_year_in_seconds

  let ln_implied_rate =
    calculate_new_ln_implied_rate(
      total_pt,
      total_asset,
      rate_scalar,
      rate_anchor,
      time_to_expiry,
      based,
    )

  // Should return a reasonable implied rate (can be negative or positive)
  // Just check it's not extremely high
  ln_implied_rate > -based && ln_implied_rate < based
}

test test_rational_exp_zero() {
  // exp(0) = 1
  expect Some(zero) = rational.new(0, 1)
  let result = rational_exp(zero)
  let result_int = rational_to_int(result, 1_000_000_000)
  // Expected: 1 * 10^9
  result_int > 999_000_000 && result_int < 1_001_000_000
}

test test_rational_exp_one() {
  // exp(1) ≈ 2.718281828
  expect Some(one) = rational.new(1, 1)
  let result = rational_exp(one)
  let result_int = rational_to_int(result, 1_000_000_000)
  // Expected: 2.718281828 * 10^9 = 2_718_281_828
  let expected = 2_718_281_828
  let tolerance = 50_000_000
  result_int > expected - tolerance && result_int < expected + tolerance
}

test test_rational_ln_e() {
  // ln(e) = 1, where e ≈ 2.718281828
  expect Some(e) = rational.new(2718281829, 1_000_000_000)
  let result = rational_ln(e)
  let result_int = rational_to_int(result, 1_000_000_000)
  // Expected: 1 * 10^9 = 1_000_000_000
  let expected = 1_000_000_000
  let tolerance = 10_000_000
  result_int > expected - tolerance && result_int < expected + tolerance
}

test test_rational_ln_two() {
  // ln(2) ≈ 0.693147181
  expect Some(two) = rational.new(2, 1)
  let result = rational_ln(two)
  let result_int = rational_to_int(result, 1_000_000_000)
  // Expected: 0.693147181 * 10^9 = 693_147_181
  let expected = 693_147_181
  let tolerance = 10_000_000
  result_int > expected - tolerance && result_int < expected + tolerance
}

test test_swap_maintains_liquidity() {
  // Test that swapping doesn't create/destroy value
  // Initial state: 1M PT, 1M SY
  // After swap of 1000 PT for SY:
  // PT increases by 1000, SY decreases by some amount
  // The product (totalPt * totalSy) should roughly maintain (AMM invariant)
  let based = 1_000_000_000_000_000_000
  let total_pt = 1_000_000
  let total_sy = 1_000_000
  let py_index = based
  let exact_pt_in = 1000
  let scalar_root = 50
  let last_ln_implied_rate = 0
  let ln_fee_rate_root = 0
  let reserve_fee_percent = 0
  let expiry = 31_536_000
  let current_time = 0

  let initial_product = total_pt * total_sy

  let (sy_out, _sy_fee, _sy_to_reserve) =
    calculate_sy_out_for_pt_in(
      exact_pt_in,
      total_pt,
      total_sy,
      py_index,
      scalar_root,
      last_ln_implied_rate,
      ln_fee_rate_root,
      reserve_fee_percent,
      expiry,
      current_time,
      based,
    )

  let new_total_pt = total_pt + exact_pt_in
  let new_total_sy = total_sy - sy_out
  let new_product = new_total_pt * new_total_sy

  // For Pendle AMM, the product doesn't stay constant like Uniswap
  // but should increase slightly (due to fees) or stay similar
  // Allow 5% variation
  let tolerance = initial_product / 20
  new_product > initial_product - tolerance && new_product < initial_product + tolerance * 3
}

test test_exchange_rate_changes_with_pt_swap() {
  // When selling PT (swapping PT for SY), proportion of PT increases
  // Exchange rate represents asset/PT (how much asset per PT)
  let based = 1_000_000_000_000_000_000

  expect Some(rate_scalar) = rational.new(50, 1)
  expect Some(rate_anchor) = rational.new(2, 1)

  let total_pt = 1_000_000
  let total_asset = 1_000_000

  // Initial exchange rate (pt_to_account = 0)
  let exchange_rate_before =
    calculate_exchange_rate_no_fee(
      total_pt,
      total_asset,
      0,
      rate_scalar,
      rate_anchor,
    )
  let rate_before = rational_to_int(exchange_rate_before, based)

  // Exchange rate when buying SY with PT (PT goes into pool, so -pt_to_account)
  // After swap: totalPt increases, proportion p increases
  let exchange_rate_after =
    calculate_exchange_rate_no_fee(
      total_pt,
      total_asset,
      -10_000,
      // Negative because PT is coming into pool
      rate_scalar,
      rate_anchor,
    )
  let rate_after = rational_to_int(exchange_rate_after, based)

  // Exchange rate changes (we just verify it's different and reasonable)
  rate_after != rate_before && rate_after > 0
}

test test_calculate_pt_out_for_sy_in_basic() {
  // Scenario: Small swap in balanced pool - buying PT with SY
  // totalPt = 1_000_000, totalSy = 1_000_000
  // pyIndex = 1 (1:1), exact_sy_in = 1000
  // With no fees and balanced pool, should get ~1000 PT back
  let based = 1_000_000_000_000_000_000
  let total_pt = 1_000_000
  let total_sy = 1_000_000
  let py_index = based
  let exact_sy_in = 1000
  let scalar_root = 50
  let last_ln_implied_rate = 0
  let ln_fee_rate_root = 0
  // 0% fee
  let reserve_fee_percent = 0
  let expiry = 31_536_000 * 2
  // 2 years
  let current_time = 0

  let (pt_out, _sy_fee, _sy_to_reserve) =
    calculate_pt_out_for_sy_in(
      exact_sy_in,
      total_pt,
      total_sy,
      py_index,
      scalar_root,
      last_ln_implied_rate,
      ln_fee_rate_root,
      reserve_fee_percent,
      expiry,
      current_time,
      based,
    )

  // With no fees, PT out should be close to SY in (allowing for price impact)
  // In a balanced pool, small swap should have minimal impact
  let tolerance = 50
  // Allow ~5% slippage for small swap
  pt_out > exact_sy_in - tolerance && pt_out < exact_sy_in + tolerance
}

test test_calculate_pt_out_with_fee() {
  // Scenario: Swap with fees enabled
  let based = 1_000_000_000_000_000_000
  let total_pt = 1_000_000
  let total_sy = 1_000_000
  let py_index = based
  let exact_sy_in = 10_000
  let scalar_root = 50
  let last_ln_implied_rate = 0
  // ln(1.01) ≈ 0.00995 ≈ 0.01 * 10^18 for 1% fee
  let ln_fee_rate_root = 10_000_000_000_000_000
  let reserve_fee_percent = 10
  let expiry = 31_536_000 * 2
  let current_time = 0

  let (pt_out_with_fee, sy_fee, sy_to_reserve) =
    calculate_pt_out_for_sy_in(
      exact_sy_in,
      total_pt,
      total_sy,
      py_index,
      scalar_root,
      last_ln_implied_rate,
      ln_fee_rate_root,
      reserve_fee_percent,
      expiry,
      current_time,
      based,
    )

  // Calculate without fee for comparison
  let (pt_out_no_fee, _fee2, _res2) =
    calculate_pt_out_for_sy_in(
      exact_sy_in,
      total_pt,
      total_sy,
      py_index,
      scalar_root,
      last_ln_implied_rate,
      0,
      // No fee
      reserve_fee_percent,
      expiry,
      current_time,
      based,
    )

  // With fee, PT out should be less than without fee
  // Fee and reserve should be positive
  pt_out_with_fee < pt_out_no_fee && sy_fee > 0 && sy_to_reserve > 0
}

test test_sy_to_pt_inverse_of_pt_to_sy() {
  // Test that swapping SY for PT and then PT back to SY returns approximately the same amount
  let based = 1_000_000_000_000_000_000
  let total_pt = 1_000_000
  let total_sy = 1_000_000
  let py_index = based
  let exact_sy_in = 5000
  let scalar_root = 50
  let last_ln_implied_rate = 0
  let ln_fee_rate_root = 0
  // 0% fee for simpler comparison
  let reserve_fee_percent = 0
  let expiry = 31_536_000 * 2
  let current_time = 0

  // First swap: SY -> PT
  let (pt_out, _fee1, _res1) =
    calculate_pt_out_for_sy_in(
      exact_sy_in,
      total_pt,
      total_sy,
      py_index,
      scalar_root,
      last_ln_implied_rate,
      ln_fee_rate_root,
      reserve_fee_percent,
      expiry,
      current_time,
      based,
    )

  // Update pool state
  let new_total_pt = total_pt - pt_out
  let new_total_sy = total_sy + exact_sy_in

  // Second swap: PT -> SY (reverse)
  let (sy_out, _fee2, _res2) =
    calculate_sy_out_for_pt_in(
      pt_out,
      new_total_pt,
      new_total_sy,
      py_index,
      scalar_root,
      last_ln_implied_rate,
      ln_fee_rate_root,
      reserve_fee_percent,
      expiry,
      current_time,
      based,
    )

  // Should get approximately the same amount of SY back
  // Allow 1% tolerance due to AMM curve
  let tolerance = exact_sy_in / 100
  sy_out > exact_sy_in - tolerance && sy_out < exact_sy_in + tolerance
}

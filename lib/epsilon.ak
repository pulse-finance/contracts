use constants.{precision, precision_sq}
use phi.{calc_phi}
use pi.{calc_pi}

/// Parameters:
/// - x: total number of SY tokens in market
/// - dx: number of SY tokens added to market (negative if removed)
/// - y: total number of PTs in market
/// - dy: number of PTs added to market (negative if removed)
/// - t: normalized time until maturity (0 at maturity), scaled by `precision`
/// - f: fee factor, scaled by `precision`
/// - p_split: current split price, scaled by `precision`
/// - p_split_ref: reference split price, scaled by `precision`
/// - r_expected: expected rate over period, scaled by `precision`
/// - r_accent: rate sensitivity, scaled by `precision`
///
/// Returns: residual of actual execution price minus AMM required execution price
pub fn calc_epsilon(
  x: Int,
  dx: Int,
  y: Int,
  dy: Int,
  t: Int,
  f: Int,
  p_split: Int,
  p_split_ref: Int,
  r_expected: Int,
  r_accent: Int,
) -> Int {
  let phi = calc_phi(x + dx, y + dy, p_split_ref)
  let pi = calc_pi(phi, t, r_expected, r_accent)

  -dy * precision / dx - f * p_split * pi / precision_sq
}

const accuracy = 10

fn equals(actual: Int, expected: Int) -> Bool {
  actual >= expected - accuracy && actual <= expected + accuracy
}

test epsilon_1000_1_1000_m1_1_1_1_1_1p1_2() {
  let x = 1000
  let dx = 1
  let y = 1000
  let dy = -1

  // 1.0
  let t = precision
  // 1.0
  let f = precision
  // 1.0
  let p_split = precision
  // 1.0
  let p_split_ref = precision
  // 1.1
  let r_expected = precision + precision / 10
  // 2.0
  let r_accent = 2 * precision

  let result =
    calc_epsilon(x, dx, y, dy, t, f, p_split, p_split_ref, r_expected, r_accent)

  // -0.096
  equals(result, -96_000)
}

test epsilon_1000_500_1000_m500_1_1_1_1_1p1_2() {
  let x = 1000
  let dx = 500
  let y = 1000
  let dy = -500

  // 1.0
  let t = precision
  // 1.0
  let f = precision
  // 1.0
  let p_split = precision
  // 1.0
  let p_split_ref = precision
  // 1.1
  let r_expected = precision + precision / 10
  // 2.0
  let r_accent = 2 * precision

  let result =
    calc_epsilon(x, dx, y, dy, t, f, p_split, p_split_ref, r_expected, r_accent)

  // 2.097225
  equals(result, 2_097_225)
}

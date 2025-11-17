use constants.{precision, precision_sq}
use logit.{logit}

pub fn calc_pi(phi: Int, t: Int, r_expected: Int, r_accent: Int) -> Int {
  precision + ( r_expected * precision - precision_sq + r_accent * logit(phi) ) * t / precision_sq
}

const accuracy = 10

fn equals(actual: Int, expected: Int) -> Bool {
  actual >= expected - accuracy && actual <= expected + accuracy
}

test pi_of_0point5_1_1p1_2() {
  let phi = precision / 2
  // 0.5
  let t = 1 * precision
  // 1.0
  let r_expected = precision + precision / 10
  // 1.1
  let r_accent = 2 * precision

  // 2.0
  let result = calc_pi(phi, t, r_expected, r_accent)
  result == r_expected
}

test pi_of_0p4995_1_1p1_2() {
  let phi = 499_500
  // 0.4995
  let t = 1 * precision
  // 1.0
  let r_expected = precision + precision / 10
  // 1.1
  let r_accent = 2 * precision

  // 2.0
  let result = calc_pi(phi, t, r_expected, r_accent)

  equals(result, 1_096_000)
}

test pi_of_0p25_1_1p1_2() {
  let phi = 250_000
  // 0.25
  let t = 1 * precision
  // 1.0
  let r_expected = precision + precision / 10
  // 1.1
  let r_accent = 2 * precision

  // 2.0
  let result = calc_pi(phi, t, r_expected, r_accent)

  equals(result, -1_097_225)
}

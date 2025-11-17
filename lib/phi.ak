use constants.{precision, precision_sq}

// y/(p_split_ref*x + y)
pub fn calc_phi(x: Int, y: Int, p_split_ref: Int) -> Int {
  y * precision_sq / ( x * p_split_ref + y * precision )
}

test phi_1000_1000_1() {
  let x = 1000
  let y = 1000
  let p_split_ref = precision

  // 1.0
  let result = calc_phi(x, y, p_split_ref)

  result == 500_000
  // 0.5
}

test phi_1000_2000_2() {
  let x = 1000
  let y = 2000
  let p_split_ref = 2 * precision

  // 2.0
  let result = calc_phi(x, y, p_split_ref)

  result == 500_000
  // 0.5
}

test phi_1000_1000_2() {
  let x = 1000
  let y = 1000
  let p_split_ref = 2 * precision

  // 2.0
  let result = calc_phi(x, y, p_split_ref)

  result == 333_333
}

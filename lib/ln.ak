use constants.{precision}

const reduction1_x = 500_000

const reduction1_inv_x = 2_000_000

const reduction1_ln_inv_x = 693_147

const reduction2_x = 800_000

const reduction2_inv_x = 1_250_000

const reduction2_ln_inv_x = 223_144

const reduction3_x = 900_000

const reduction3_inv_x = 1_111_111

const reduction3_ln_inv_x = 105_360

fn reduce(x: Int, count: Int, xl: Int, inv_xl: Int) -> (Int, Int) {
  if x <= xl {
    reduce(x * inv_xl / precision, count + 1, xl, inv_xl)
  } else {
    (x, count)
  }
}

// x is a number scaled by `precision`
pub fn ln(x: Int) -> Int {
  if x <= 0 {
    fail @"ln undefined for non-positive"
  } else {
    let (x, c1) = reduce(x, 0, reduction1_x, reduction1_inv_x)
    let (x, c2) = reduce(x, 0, reduction2_x, reduction2_inv_x)
    let (x, c3) = reduce(x, 0, reduction3_x, reduction3_inv_x)

    let xm = x - precision
    let xm2 = xm * xm
    let xm3 = xm2 * xm
    let xp = x + precision
    let xp2 = xp * xp
    let xp3 = xp2 * xp

    let s = ( xm * xp2 * precision * 3 + xm3 * precision ) * 2 / ( xp3 * 3 )
    let s = s - c1 * reduction1_ln_inv_x
    let s = s - c2 * reduction2_ln_inv_x
    let s = s - c3 * reduction3_ln_inv_x

    s
  }
}

const accuracy = 10

fn equals(actual: Int, expected: Int) -> Bool {
  actual >= expected - accuracy && actual <= expected + accuracy
}

test reduce1_0p01() {
  let (result, c) = reduce(10_000, 0, reduction1_x, reduction1_inv_x)

  result == 640_000 && c == 6
}

test ln_0p01() {
  let result = ln(10_000)
  equals(result, -4605170) && result == -4605170
}

test ln_0p1() {
  let result = ln(100_000)
  equals(result, -2302585) && result == -2302585
}

test ln_0p2() {
  let result = ln(200_000)
  equals(result, -1609438)
}

test ln_0p3() {
  let result = ln(300_000)
  equals(result, -1203973)
}

test ln_0p4() {
  let result = ln(400_000)
  equals(result, -916291)
}

test ln_0p5() {
  let result = ln(500_000)
  equals(result, -693147)
}

test ln_0p6() {
  let result = ln(600_000)
  equals(result, -510826)
}

test ln_0p7() {
  let result = ln(700_000)
  equals(result, -356675)
}

test ln_0p8() {
  let result = ln(800_000)
  equals(result, -223144)
}

test ln_0p9() {
  let result = ln(900_000)
  equals(result, -105361)
}

test ln_0p99() {
  let result = ln(990_000)
  equals(result, -10050)
}

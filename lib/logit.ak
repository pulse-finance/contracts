use constants.{precision}
use ln.{ln}

// phi is a number between 0 and 1_000_000
pub fn logit(phi: Int) -> Int {
  ln(phi) - ln(precision - phi)
}

const accuracy = 10

fn equals(actual: Int, expected: Int) -> Bool {
  actual >= expected - accuracy && actual <= expected + accuracy
}

test logit_0p01() {
  let result = logit(10_000)
  equals(result, -4595120)
}

test logit_0p1() {
  let result = logit(100_000)
  equals(result, -2197225)
}

test logit_0p2() {
  let result = logit(200_000)
  equals(result, -1386294)
}

test logit_0p3() {
  let result = logit(300_000)
  equals(result, -847298)
}

test logit_0p4() {
  let result = logit(400_000)
  equals(result, -405465)
}

test logit_0p4995() {
  let result = logit(499_500)
  equals(result, -2000)
}

test logit_0p5() {
  let result = logit(500_000)
  result == 0
}

test logit_0p6() {
  let result = logit(600_000)
  equals(result, 405465)
}

test logit_0p7() {
  let result = logit(700_000)
  equals(result, 847298)
}

test logit_0p8() {
  let result = logit(800_000)
  equals(result, 1386294)
}

test logit_0p9() {
  let result = logit(900_000)
  equals(result, 2197225)
}

test logit_0p99() {
  let result = logit(990_000)
  equals(result, 4595120)
}

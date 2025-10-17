import gleam/float
import gleam/list
import gleam/io
import gleam/string
import gleam/time/duration
import gleam/time/timestamp

type Thing {
  Thing(Int)
}

const outer_list_length = 100
const max_inner_list_length = 21
const num_iterations = 2000

fn first_n_natural_numbers(n: Int) -> List(Int) {
  list.repeat(Nil, n)
  |> list.index_map(fn(_, i) { i + 1 })
}

fn test_map(i: Int) -> List(Thing) {
  list.repeat(Nil, i % {max_inner_list_length + 1})
  |> list.index_map(fn(_, i) { Thing(i + 1) })
}

fn perform_stdlib_flat_map() -> List(Thing) {
  first_n_natural_numbers(outer_list_length)
  |> list.flat_map(test_map)
}

fn handrolled_flat_map(l: List(a), map: fn(a) -> List(b)) {
  list.fold(
    l,
    [],
    fn(acc, x) {
      list.fold(
        map(x),
        acc,
        fn(acc2, x) { [x, ..acc2] },
      )
    }
  )
  |> list.reverse
}

fn perform_handrolled_flat_map() -> List(Thing) {
  first_n_natural_numbers(outer_list_length)
  |> handrolled_flat_map(test_map)
}

fn repeat(f: fn() -> a, n: Int) -> Nil {
  case n > 0 {
    True -> {
      f()
      repeat(f, n - 1)
    }
    False -> Nil
  }
}

fn measure_once_each(g: fn() -> a, h: fn() -> a) -> #(Float, Float) {
  let t0 = timestamp.system_time()
  g()
  let t1 = timestamp.system_time()
  h()
  let t2 = timestamp.system_time()
  #(
    timestamp.difference(t0, t1) |> duration.to_seconds,
    timestamp.difference(t1, t2) |> duration.to_seconds,
  )
}

pub fn main() {
  assert perform_handrolled_flat_map() == perform_stdlib_flat_map()

  let #(d1, d2) = measure_once_each(
    fn() { repeat(perform_handrolled_flat_map, num_iterations) },
    fn() { repeat(perform_stdlib_flat_map, num_iterations) },
  )

  let #(d3, d4) = measure_once_each(
    fn() { repeat(perform_stdlib_flat_map, num_iterations) },
    fn() { repeat(perform_handrolled_flat_map, num_iterations) },
  )

  let #(d5, d6) = measure_once_each(
    fn() { repeat(perform_handrolled_flat_map, num_iterations) },
    fn() { repeat(perform_stdlib_flat_map, num_iterations) },
  )

  io.println("")
  io.println("stdlib total:     " <> string.inspect({d2 +. d3 +. d6} |> float.to_precision(3)) <> "s")
  io.println("handrolled total: " <> string.inspect({d1 +. d4 +. d5} |> float.to_precision(3)) <> "s")
}
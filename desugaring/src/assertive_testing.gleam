import io_lines.{OutputLine} as io_l
import gleam/list
import gleam/result
import gleam/string.{inspect as ins}
import gleam/io
import infrastructure.{
  type AssertiveTest,
  type AssertiveTestCollection,
  type AssertiveTestError,
  InequalityError,
  NonMatchingDesugarerName,
  TestDesugaringError,
  VXMLParseError,
}
import desugarer_library as dl
import colours
import vxml
import on

fn first_different_line(
  c: Int,
  l1: List(String),
  l2: List(String),
) -> #(Int, String, String) {
  case l1, l2 {
    [], [] -> panic
    [], [l2_first, ..] -> #(c, "--", l2_first)
    [l1_first, ..], [] -> #(c, l1_first, "--")
    [l1_first, ..l1], [l2_first, ..l2] -> case l1_first != l2_first {
      True -> #(c, l1_first, l2_first)
      False -> first_different_line(c + 1, l1, l2)
    }
  }
}

pub fn run_assertive_test(name: String, tst: AssertiveTest) -> Result(Nil, AssertiveTestError) {
  let desugarer = tst.constructor()
  use <- on.true_false(
    name != desugarer.name,
    Error(NonMatchingDesugarerName(desugarer.name)),
  )
  use vxmls <- on.ok(vxml.parse_string(tst.source, "tst.source") |> result.map_error(fn(e) { VXMLParseError(e) }))
  let assert [input] = vxmls
  use vxmls <- on.ok(vxml.parse_string(tst.expected, "tst.expect") |> result.map_error(fn(e) { VXMLParseError(e) }))
  let assert [expected] = vxmls
  use #(output, _) <- on.ok(
    desugarer.transform(input)
    |> result.map_error(fn(e) { TestDesugaringError(e) })
  )
  let output_string = vxml.vxml_to_string(output)
  let expected_string = vxml.vxml_to_string(expected)
  case output_string == expected_string {
    True -> Ok(Nil)
    False -> Error(
      InequalityError(
        desugarer.name,
        output,
        expected,
        first_different_line(0, output_string |> string.split("\n"), expected_string |> string.split("\n"))
      )
    )
  }
}

pub fn run_and_announce_results(
  test_group: AssertiveTestCollection,
  tst: AssertiveTest,
  number: Int,
  total: Int,
) -> Int {
  case run_assertive_test(test_group.desugarer_name, tst) {
    Ok(Nil) -> {
      io.print("✅")
      0
    }
    Error(error) -> {
      io.print("\n❌ test " <> ins(number) <> " of " <> ins(total) <> " failed:")
      case error {
        InequalityError(_, obtained, expected, first_different) -> {
          let line_no = first_different.0
          let obtained =
            vxml.vxml_to_output_lines(obtained)
            |> list.index_map(fn(l, i) {
              case i >= line_no {
                False -> l
                True -> OutputLine(..l, suffix: colours.fgred(l.suffix))
              }
            })
          let expected =
            vxml.vxml_to_output_lines(expected)
            |> list.index_map(fn(l, i) {
              case i >= line_no {
                False -> l
                True -> OutputLine(..l, suffix: colours.fgred(l.suffix))
              }
            })
          io.println(" obtained != expected:")
          obtained |> io_l.echo_output_lines("obtained")
          expected |> io_l.echo_output_lines("expected")
          io.println(ins(first_different))
          Nil
        }
        _ -> io.println(ins(error))
      }
      1
    }
  }
}

fn run_assertive_test_collection(test_group: AssertiveTestCollection) -> #(Int, Int) {
  let tests = test_group.tests()
  let total = list.length(tests)
  use <- on.false_true(
    total > 0,
    #(0, 0),
  )
  io.print(test_group.desugarer_name <> " ")
  let #(num_success, num_failures) = list.fold(
    tests,
    #(0, 0),
    fn (acc, tst) {
      let failure = run_and_announce_results(test_group, tst, acc.0 + acc.1 + 1, total)
      #(acc.0 + 1 - failure, acc.1 + failure)
    }
  )
  case list.length(tests) == 1 {
    True -> io.println(" (1 assertive test)")
    False -> io.println(" (" <> ins(num_success) <> " assertive tests)")
  }
  #(num_success, num_failures)
}

pub fn run_assertive_desugarer_tests_on(
  desugarer_names names: List(String),
) {
  let colls = list.map(dl.assertive_tests, fn(constructor){constructor()})
  let #(all, dont_have_tests) =
    list.fold(
      colls,
      #([], []),
      fn(acc, coll) {
        case list.length(coll.tests()) > 0 {
          True -> #(
            [coll.desugarer_name, ..acc.0],
            acc.1,
          )
          False -> #(
            [coll.desugarer_name, ..acc.0],
            [coll.desugarer_name, ..acc.1],
          )
        }
      }
    )

  let names = case list.is_empty(names) {
    True -> all
    False -> names
  }

  let dont_have_tests = list.filter(dont_have_tests, list.contains(names, _))

  case list.is_empty(dont_have_tests) {
    True -> Nil
    False -> {
      io.println("")
      io.println("the following desugarers have empty test data:")
      list.each(
        dont_have_tests |> list.reverse,
        fn(name) { io.println(" - " <> name)}
      )
    }
  }

  io.println("")
  let #(num_performed, num_failed) =
    list.fold(
      colls,
      #(0, 0),
      fn(acc, coll) {
        case {
          list.contains(names, coll.desugarer_name) &&
          list.length(coll.tests()) > 0
        } {
          False -> acc
          True -> {
            let #(_, num_failed) = run_assertive_test_collection(coll)
            case num_failed > 0 {
              True -> #(acc.0 + 1, acc.1 + 1)
              False -> #(acc.0 + 1, acc.1)
            }
          }
        }
      }
    )

  io.println("")
  io.println(
    ins(num_performed)
    <> case num_performed == 1 {
      True -> " desugarer tested, "
      False -> " desugarers tested, "
    }
    <> ins(num_failed)
    <> case num_failed == 1 {
      True -> " failed"
      False -> " failures"
    }
  )

  let desugarers_with_no_test_group = list.filter(names, fn(name) { !list.contains(all, name)})
  case list.is_empty(desugarers_with_no_test_group) {
    True -> Nil
    False -> {
      io.println("")
      io.println("could not find any test data for the following desugarers:")
      list.each(
        desugarers_with_no_test_group,
        fn(name) { io.println(" - " <> name)}
      )
    }
  }

  Nil
}
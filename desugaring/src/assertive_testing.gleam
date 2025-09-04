import gleam/list
import gleam/result
import gleam/string.{inspect as ins}
import gleam/io
import infrastructure.{
  type AssertiveTest,
  type AssertiveTestCollection,
  type AssertiveTestError,
  AssertiveTestError,
  NonMatchingDesugarerName,
  TestDesugaringError,
  VXMLParseError,
}
import desugarer_library as dl
import vxml
import on

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
  case vxml.vxml_to_string(output) == vxml.vxml_to_string(expected) {
    True -> Ok(Nil)
    False -> Error(
      AssertiveTestError(
        desugarer.name,
        output,
        expected,
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
        AssertiveTestError(_, obtained, expected) -> {
          io.println(" obtained != expected:")
          vxml.echo_vxml(obtained, "obtained")
          vxml.echo_vxml(expected, "expected")
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
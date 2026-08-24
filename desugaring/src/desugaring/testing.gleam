import desugaring/assertive_testing
import desugaring/core
import gleam/list

pub type AssertiveTest =
  core.AssertiveTest

pub type AssertiveTestCollection =
  core.AssertiveTestCollection

pub type AssertiveTestData(a) =
  core.AssertiveTestData(a)

pub type AssertiveTestDataNoParam =
  core.AssertiveTestDataNoParam

pub type AssertiveTestDataWithOutside(a) =
  core.AssertiveTestDataWithOutside(a)

pub type AssertiveTestDataNoParamWithOutside =
  core.AssertiveTestDataNoParamWithOutside

pub type AssertiveTestError =
  core.AssertiveTestError

pub type AssertiveTestResults {
  AssertiveTestResults(
    desugarer_name: String,
    results: List(Result(Nil, AssertiveTestError)),
  )
}

pub fn data(param: a, source: String, expected: String) {
  core.AssertiveTestData(param, source, expected)
}

pub fn data_no_param(source: String, expected: String) {
  core.AssertiveTestDataNoParam(source, expected)
}

pub fn data_with_outside(
  param: a,
  outside: List(String),
  source: String,
  expected: String,
) {
  core.AssertiveTestDataWithOutside(param, outside, source, expected)
}

pub fn data_no_param_with_outside(
  outside: List(String),
  source: String,
  expected: String,
) {
  core.AssertiveTestDataNoParamWithOutside(outside, source, expected)
}

pub fn collection(
  name: String,
  data: List(AssertiveTestData(a)),
  constructor: fn(a) -> core.Desugarer,
) {
  core.assertive_test_collection_from_data(name, data, constructor)
}

pub fn collection_no_param(
  name: String,
  data: List(AssertiveTestDataNoParam),
  constructor: fn() -> core.Desugarer,
) {
  core.assertive_test_collection_from_data_no_param(name, data, constructor)
}

pub fn collection_with_outside(
  name: String,
  data: List(AssertiveTestDataWithOutside(a)),
  constructor: fn(a, List(String)) -> core.Desugarer,
) {
  core.assertive_test_collection_from_data_with_outside(name, data, constructor)
}

pub fn collection_no_param_with_outside(
  name: String,
  data: List(AssertiveTestDataNoParamWithOutside),
  constructor: fn(List(String)) -> core.Desugarer,
) {
  core.assertive_test_collection_from_data_no_param_with_outside(
    name,
    data,
    constructor,
  )
}

pub fn run_test(name: String, assertive_test: AssertiveTest) {
  assertive_testing.run_assertive_test(name, assertive_test)
}

pub fn run(
  collections: List(AssertiveTestCollection),
) -> List(AssertiveTestResults) {
  list.map(collections, fn(collection) {
    AssertiveTestResults(
      collection.desugarer_name,
      collection.tests()
        |> list.map(run_test(collection.desugarer_name, _)),
    )
  })
}

pub fn all_passed(results: List(AssertiveTestResults)) -> Bool {
  list.all(results, fn(group) {
    list.all(group.results, fn(result) {
      case result {
        Ok(Nil) -> True
        Error(_) -> False
      }
    })
  })
}

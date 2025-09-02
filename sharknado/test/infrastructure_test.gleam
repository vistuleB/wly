import gleeunit
import gleeunit/should
import gleam/list
import infrastructure as infra
import vxml.{V, T, Attribute}
import blame.{Src}

pub fn main() {
  gleeunit.main()
}

pub fn kabob_case_to_camel_case_test() {
  // test basic kabob case to camel case conversion
  infra.kabob_case_to_camel_case("hello-world")
  |> should.equal("helloWorld")
  
  // test single word
  infra.kabob_case_to_camel_case("hello")
  |> should.equal("hello")
  
  // test multiple dashes
  infra.kabob_case_to_camel_case("my-long-attribute-name")
  |> should.equal("myLongAttributeName")
  
  // test empty string
  infra.kabob_case_to_camel_case("")
  |> should.equal("")
  
  // test single dash
  infra.kabob_case_to_camel_case("-")
  |> should.equal("")
  
  // test leading dash
  infra.kabob_case_to_camel_case("-hello-world")
  |> should.equal("HelloWorld")
  
  // test trailing dash
  infra.kabob_case_to_camel_case("hello-world-")
  |> should.equal("helloWorld")
  
  // test multiple consecutive dashes
  infra.kabob_case_to_camel_case("hello--world")
  |> should.equal("helloWorld")
  
  // test single character words
  infra.kabob_case_to_camel_case("a-b-c")
  |> should.equal("aBC")
  
  // test numbers
  infra.kabob_case_to_camel_case("data-2-test")
  |> should.equal("data2Test")
  
  // test edge cases specific to optimized version
  
  // test with empty parts (consecutive dashes) - now keeps empty strings
  infra.kabob_case_to_camel_case("hello--world")
  |> should.equal("helloWorld")
  
  // test leading dash creates empty first part
  infra.kabob_case_to_camel_case("-hello")
  |> should.equal("Hello")
  
  // test trailing dash creates empty last part
  infra.kabob_case_to_camel_case("hello-")
  |> should.equal("hello")
  
  // test multiple leading dashes
  infra.kabob_case_to_camel_case("--hello-world")
  |> should.equal("HelloWorld")
}

pub fn has_class_test() {
  let blame = Src([], "test", 1, 0)
  
  // test node with single class that matches
  let node_with_class = V(
    blame,
    "div",
    [Attribute(blame, "class", "my-class")],
    []
  )
  infra.has_class(node_with_class, "my-class")
  |> should.equal(True)
  
  // test node with multiple classes, one matches
  let node_with_multiple_classes = V(
    blame,
    "div", 
    [Attribute(blame, "class", "first-class my-class last-class")],
    []
  )
  infra.has_class(node_with_multiple_classes, "my-class")
  |> should.equal(True)
  
  // test node with classes but none match
  let node_with_other_classes = V(
    blame,
    "div",
    [Attribute(blame, "class", "other-class different-class")],
    []
  )
  infra.has_class(node_with_other_classes, "my-class")
  |> should.equal(False)
  
  // test node with no class attribute
  let node_without_class = V(
    blame,
    "div",
    [Attribute(blame, "id", "some-id")],
    []
  )
  infra.has_class(node_without_class, "my-class")
  |> should.equal(False)
  
  // test node with empty class attribute
  let node_with_empty_class = V(
    blame,
    "div",
    [Attribute(blame, "class", "")],
    []
  )
  infra.has_class(node_with_empty_class, "my-class")
  |> should.equal(False)
  
  // test partial class name match (should return false)
  let node_with_partial_match = V(
    blame,
    "div",
    [Attribute(blame, "class", "my-class-extended")],
    []
  )
  infra.has_class(node_with_partial_match, "my-class")
  |> should.equal(False)
}

pub fn filter_descendants_test() {
  let blame = Src([], "test", 1, 0)
  
  // create a nested structure for testing
  // <div class="parent">
  //   <span class="child">text</span>
  //   <div class="nested">
  //     <p class="deep">deep content</p>
  //     <span class="deeper">deeper content</span>
  //   </div>
  //   <p class="sibling">sibling content</p>
  // </div>
  
  let deep_p = V(
    blame,
    "p",
    [Attribute(blame, "class", "deep")],
    []
  )
  
  let deeper_span = V(
    blame,
    "span", 
    [Attribute(blame, "class", "deeper")],
    []
  )
  
  let nested_div = V(
    blame,
    "div",
    [Attribute(blame, "class", "nested")],
    [deep_p, deeper_span]
  )
  
  let child_span = V(
    blame,
    "span",
    [Attribute(blame, "class", "child")],
    []
  )
  
  let sibling_p = V(
    blame,
    "p",
    [Attribute(blame, "class", "sibling")],
    []
  )
  
  let parent_div = V(
    blame,
    "div",
    [Attribute(blame, "class", "parent")],
    [child_span, nested_div, sibling_p]
  )
  
  // test filtering by tag - should find all p tags in descendants
  let p_tags = infra.filter_descendants(parent_div, fn(node) {
    infra.is_v_and_tag_equals(node, "p")
  })
  p_tags |> list.length |> should.equal(2)
  
  // test filtering by tag - should find all span tags in descendants
  let span_tags = infra.filter_descendants(parent_div, fn(node) {
    infra.is_v_and_tag_equals(node, "span")
  })
  span_tags |> list.length |> should.equal(2)
  
  // test filtering by class - should find nodes with "deep" class
  let deep_nodes = infra.filter_descendants(parent_div, fn(node) {
    infra.has_class(node, "deep")
  })
  deep_nodes |> list.length |> should.equal(1)
  
  // test that root is not included - filter for "parent" class should return empty
  let parent_nodes = infra.filter_descendants(parent_div, fn(node) {
    infra.has_class(node, "parent")
  })
  parent_nodes |> list.length |> should.equal(0)
  
  // test with text node - should return empty list
  let text_node = T(blame, [])
  let text_results = infra.filter_descendants(text_node, fn(_) { True })
  text_results |> list.length |> should.equal(0)
  
  // test with condition that matches nothing
  let no_matches = infra.filter_descendants(parent_div, fn(node) {
    infra.has_class(node, "nonexistent")
  })
  no_matches |> list.length |> should.equal(0)
}

pub fn descendants_with_key_value_test() {
  let blame = Src([], "test", 1, 0)
  
  // create a nested structure for testing
  // <div class="parent">
  //   <span data-id="child1">text</span>
  //   <div data-id="nested">
  //     <p data-id="deep">deep content</p>
  //     <span data-id="child1">deeper content</span>
  //   </div>
  //   <p data-id="sibling">sibling content</p>
  // </div>
  
  let deep_p = V(
    blame,
    "p",
    [Attribute(blame, "data-id", "deep")],
    []
  )
  
  let deeper_span = V(
    blame,
    "span", 
    [Attribute(blame, "data-id", "child1")],
    []
  )
  
  let nested_div = V(
    blame,
    "div",
    [Attribute(blame, "data-id", "nested")],
    [deep_p, deeper_span]
  )
  
  let child_span = V(
    blame,
    "span",
    [Attribute(blame, "data-id", "child1")],
    []
  )
  
  let sibling_p = V(
    blame,
    "p",
    [Attribute(blame, "data-id", "sibling")],
    []
  )
  
  let parent_div = V(
    blame,
    "div",
    [Attribute(blame, "class", "parent")],
    [child_span, nested_div, sibling_p]
  )
  
  // test finding descendants with specific key-value pair
  let child1_nodes = infra.descendants_with_key_value(parent_div, "data-id", "child1")
  child1_nodes |> list.length |> should.equal(2)
  
  // test finding single descendant
  let deep_nodes = infra.descendants_with_key_value(parent_div, "data-id", "deep")
  deep_nodes |> list.length |> should.equal(1)
  
  // test finding no matches
  let no_matches = infra.descendants_with_key_value(parent_div, "data-id", "nonexistent")
  no_matches |> list.length |> should.equal(0)
  
  // test that root is not included - parent div has class="parent", not data-id
  let parent_matches = infra.descendants_with_key_value(parent_div, "class", "parent")
  parent_matches |> list.length |> should.equal(0)
  
  // test with text node - should return empty list
  let text_node = T(blame, [])
  let text_results = infra.descendants_with_key_value(text_node, "data-id", "anything")
  text_results |> list.length |> should.equal(0)
}

pub fn descendants_with_tag_test() {
  let blame = Src([], "test", 1, 0)
  
  // create a nested structure for testing
  // <div class="parent">
  //   <span>text</span>
  //   <div class="nested">
  //     <p>deep content</p>
  //     <span>deeper content</span>
  //   </div>
  //   <p>sibling content</p>
  // </div>
  
  let deep_p = V(
    blame,
    "p",
    [Attribute(blame, "class", "deep")],
    []
  )
  
  let deeper_span = V(
    blame,
    "span", 
    [Attribute(blame, "class", "deeper")],
    []
  )
  
  let nested_div = V(
    blame,
    "div",
    [Attribute(blame, "class", "nested")],
    [deep_p, deeper_span]
  )
  
  let child_span = V(
    blame,
    "span",
    [Attribute(blame, "class", "child")],
    []
  )
  
  let sibling_p = V(
    blame,
    "p",
    [Attribute(blame, "class", "sibling")],
    []
  )
  
  let parent_div = V(
    blame,
    "div",
    [Attribute(blame, "class", "parent")],
    [child_span, nested_div, sibling_p]
  )
  
  // test finding descendants with specific tag
  let p_tags = infra.descendants_with_tag(parent_div, "p")
  p_tags |> list.length |> should.equal(2)
  
  // test finding all span tags in descendants
  let span_tags = infra.descendants_with_tag(parent_div, "span")
  span_tags |> list.length |> should.equal(2)
  
  // test finding single tag type
  let div_tags = infra.descendants_with_tag(parent_div, "div")
  div_tags |> list.length |> should.equal(1)
  
  // test finding no matches
  let no_matches = infra.descendants_with_tag(parent_div, "article")
  no_matches |> list.length |> should.equal(0)
  
  // test that root is not included - parent div should not be in results
  let root_tags = infra.descendants_with_tag(parent_div, "div")
  root_tags |> list.length |> should.equal(1) // only the nested div, not the parent
  
  // test with text node - should return empty list
  let text_node = T(blame, [])
  let text_results = infra.descendants_with_tag(text_node, "p")
  text_results |> list.length |> should.equal(0)
}

pub fn children_with_class_test() {
  let blame = Src([], "test", 1, 0)
  
  // create a parent with children having different classes
  // <div class="parent">
  //   <span class="special">text</span>
  //   <div class="special nested">content</div>
  //   <p class="normal">paragraph</p>
  //   <span class="special highlight">another span</span>
  //   <div class="normal">normal div</div>
  // </div>
  
  let special_span1 = V(
    blame,
    "span",
    [Attribute(blame, "class", "special")],
    []
  )
  
  let special_div = V(
    blame,
    "div",
    [Attribute(blame, "class", "special nested")],
    []
  )
  
  let normal_p = V(
    blame,
    "p",
    [Attribute(blame, "class", "normal")],
    []
  )
  
  let special_span2 = V(
    blame,
    "span",
    [Attribute(blame, "class", "special highlight")],
    []
  )
  
  let normal_div = V(
    blame,
    "div",
    [Attribute(blame, "class", "normal")],
    []
  )
  
  let parent_div = V(
    blame,
    "div",
    [Attribute(blame, "class", "parent")],
    [special_span1, special_div, normal_p, special_span2, normal_div]
  )
  
  // test finding children with "special" class
  let special_children = infra.v_children_with_class(parent_div, "special")
  special_children |> list.length |> should.equal(3)
  
  // test finding children with "normal" class
  let normal_children = infra.v_children_with_class(parent_div, "normal")
  normal_children |> list.length |> should.equal(2)
  
  // test finding children with "nested" class (appears in multi-class attribute)
  let nested_children = infra.v_children_with_class(parent_div, "nested")
  nested_children |> list.length |> should.equal(1)
  
  // test finding children with "highlight" class
  let highlight_children = infra.v_children_with_class(parent_div, "highlight")
  highlight_children |> list.length |> should.equal(1)
  
  // test finding children with non-existent class
  let no_matches = infra.v_children_with_class(parent_div, "nonexistent")
  no_matches |> list.length |> should.equal(0)
  
  // test finding children with "parent" class (should be 0 since we're looking at children, not the parent itself)
  let parent_class_children = infra.v_children_with_class(parent_div, "parent")
  parent_class_children |> list.length |> should.equal(0)
  
  // test with element that has no children
  let childless_element = V(
    blame,
    "span",
    [Attribute(blame, "class", "childless")],
    []
  )
  let no_children = infra.v_children_with_class(childless_element, "any")
  no_children |> list.length |> should.equal(0)
}

pub fn descendants_with_class_test() {
  let blame = Src([], "test", 1, 0)
  
  // create a nested structure for testing
  // <div class="parent">
  //   <span class="special">text</span>
  //   <div class="normal">
  //     <p class="special">deep content</p>
  //     <span class="highlight">deeper content</span>
  //   </div>
  //   <p class="special normal">sibling content</p>
  // </div>
  
  let deep_p = V(
    blame,
    "p",
    [Attribute(blame, "class", "special")],
    []
  )
  
  let deeper_span = V(
    blame,
    "span", 
    [Attribute(blame, "class", "highlight")],
    []
  )
  
  let nested_div = V(
    blame,
    "div",
    [Attribute(blame, "class", "normal")],
    [deep_p, deeper_span]
  )
  
  let child_span = V(
    blame,
    "span",
    [Attribute(blame, "class", "special")],
    []
  )
  
  let sibling_p = V(
    blame,
    "p",
    [Attribute(blame, "class", "special normal")],
    []
  )
  
  let parent_div = V(
    blame,
    "div",
    [Attribute(blame, "class", "parent")],
    [child_span, nested_div, sibling_p]
  )
  
  // test finding descendants with "special" class
  let special_descendants = infra.descendants_with_class(parent_div, "special")
  special_descendants |> list.length |> should.equal(3)
  
  // test finding descendants with "normal" class
  let normal_descendants = infra.descendants_with_class(parent_div, "normal")
  normal_descendants |> list.length |> should.equal(2)
  
  // test finding descendants with "highlight" class (single match)
  let highlight_descendants = infra.descendants_with_class(parent_div, "highlight")
  highlight_descendants |> list.length |> should.equal(1)
  
  // test finding descendants with non-existent class
  let no_matches = infra.descendants_with_class(parent_div, "nonexistent")
  no_matches |> list.length |> should.equal(0)
  
  // test that root is not included - parent div has "parent" class
  let parent_class_descendants = infra.descendants_with_class(parent_div, "parent")
  parent_class_descendants |> list.length |> should.equal(0)
  
  // test with text node - should return empty list
  let text_node = T(blame, [])
  let text_results = infra.descendants_with_class(text_node, "special")
  text_results |> list.length |> should.equal(0)
  
  // test with element that has no descendants
  let childless_element = V(
    blame,
    "span",
    [Attribute(blame, "class", "childless")],
    []
  )
  let no_descendants = infra.descendants_with_class(childless_element, "any")
  no_descendants |> list.length |> should.equal(0)
}


pub fn extract_children_test() {
  let blame = Src([], "test", 1, 0)
  
  // create a parent with multiple children
  // <div class="parent">
  //   <span class="remove">text1</span>
  //   <div class="keep">content1</div>
  //   <p class="remove">text2</p>
  //   <span class="keep">content2</span>
  //   <div class="remove">content3</div>
  // </div>
  
  let span1 = V(
    blame,
    "span",
    [Attribute(blame, "class", "remove")],
    []
  )
  
  let div1 = V(
    blame,
    "div",
    [Attribute(blame, "class", "keep")],
    []
  )
  
  let p1 = V(
    blame,
    "p",
    [Attribute(blame, "class", "remove")],
    []
  )
  
  let span2 = V(
    blame,
    "span",
    [Attribute(blame, "class", "keep")],
    []
  )
  
  let div2 = V(
    blame,
    "div",
    [Attribute(blame, "class", "remove")],
    []
  )
  
  let parent_div = V(
    blame,
    "div",
    [Attribute(blame, "class", "parent")],
    [span1, div1, p1, span2, div2]
  )
  
  // test excising children with "remove" class
  let #(new_node, excised) = infra.v_extract_children(parent_div, fn(child) {
    infra.has_class(child, "remove")
  })
  
  // check that 3 children were excised
  excised |> list.length |> should.equal(3)
  
  // check that the new node has only 2 remaining children
  let remaining_children = infra.v_get_children(new_node)
  remaining_children |> list.length |> should.equal(2)
  
  // check that remaining children all have "keep" class
  let keep_count = remaining_children
    |> list.filter(infra.has_class(_, "keep"))
    |> list.length
  keep_count |> should.equal(2)
  
  // test excising children by tag
  let #(new_node2, excised2) = infra.v_extract_children(parent_div, fn(child) {
    infra.is_v_and_tag_equals(child, "span")
  })
  
  // check that 2 span children were excised
  excised2 |> list.length |> should.equal(2)
  
  // check that the new node has 3 remaining children
  let remaining_children2 = infra.v_get_children(new_node2)
  remaining_children2 |> list.length |> should.equal(3)
  
  // test excising all children
  let #(new_node3, excised3) = infra.v_extract_children(parent_div, fn(_) { True })
  
  // check that all 5 children were excised
  excised3 |> list.length |> should.equal(5)
  
  // check that the new node has no children
  let remaining_children3 = infra.v_get_children(new_node3)
  remaining_children3 |> list.length |> should.equal(0)
  
  // test excising no children
  let #(new_node4, excised4) = infra.v_extract_children(parent_div, fn(_) { False })
  
  // check that no children were excised
  excised4 |> list.length |> should.equal(0)
  
  // check that the new node has all original children
  let remaining_children4 = infra.v_get_children(new_node4)
  remaining_children4 |> list.length |> should.equal(5)
  
  // test with element that has no children
  let childless_element = V(
    blame,
    "span",
    [Attribute(blame, "class", "childless")],
    []
  )
  let #(new_childless, excised_childless) = infra.v_extract_children(childless_element, fn(_) { True })
  
  // check that no children were excised and node remains unchanged
  excised_childless |> list.length |> should.equal(0)
  let remaining_childless = infra.v_get_children(new_childless)
  remaining_childless |> list.length |> should.equal(0)
}

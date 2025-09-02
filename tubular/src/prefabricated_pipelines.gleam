import gleam/list
import group_replacement_splitting as grs
import infrastructure.{
  type Desugarer,
  type LatexDelimiterPair,
  type LatexDelimiterSingleton,
  DoubleDollarSingleton,
  SingleDollarSingleton,
  BackslashOpeningParenthesis,
  BackslashClosingParenthesis,
  BackslashOpeningSquareBracket,
  BackslashClosingSquareBracket,
  BeginAlign,
  EndAlign,
  BeginAlignStar,
  EndAlignStar,
} as infra
import desugarer_library as dl

//******************
// math delimiter stuff
//******************

fn closing_equals_opening(
  pair: LatexDelimiterPair
) -> Bool {
  let z = infra.opening_and_closing_singletons_for_pair(pair)
  z.0 == z.1
}

fn split_pair_fold_data(
  which: LatexDelimiterSingleton
) -> #(grs.RegexpWithGroupReplacementInstructions, String, String) {
  case which {
    DoubleDollarSingleton -> #(grs.unescaped_suffix_replacement_splitter("\\$\\$", "DoubleDollar"), "DoubleDollar", "$$")
    SingleDollarSingleton -> #(grs.unescaped_suffix_replacement_splitter("\\$", "SingleDollar"), "SingleDollar", "$")
    BackslashOpeningParenthesis -> #(grs.unescaped_suffix_replacement_splitter("\\\\\\(", "LatexOpeningPar"), "LatexOpeningPar", "\\(")
    BackslashClosingParenthesis -> #(grs.unescaped_suffix_replacement_splitter("\\\\\\)", "LatexClosingPar"), "LatexClosingPar", "\\)")
    BackslashOpeningSquareBracket -> #(grs.unescaped_suffix_replacement_splitter("\\\\\\[", "LatexOpeningBra"), "LatexOpeningBra", "\\[")
    BackslashClosingSquareBracket -> #(grs.unescaped_suffix_replacement_splitter("\\\\\\]", "LatexClosingBra"), "LatexClosingBra", "\\]")
    BeginAlign -> #(grs.for_groups([#("\\\\begin{align}", grs.TagFwdText("BeginAlign", "\\begin{align}"))]), "BeginAlign", "\\begin{align}")
    EndAlign -> #(grs.for_groups([#("\\\\end{align}", grs.TagBwdText("EndAlign", "\\end{align}"))]), "EndAlign", "\\end{align}")
    BeginAlignStar -> #(grs.for_groups([#("\\\\begin{align\\*}", grs.TagFwdText("BeginAlignStar", "\\begin{align*}"))]), "BeginAlignStar", "\\begin{align*}")
    EndAlignStar -> #(grs.for_groups([#("\\\\end{align\\*}", grs.TagBwdText("EndAlignStar", "\\end{align*}"))]), "EndAlignStar", "\\end{align*}")
  }
}

fn split_pair_fold_for_delimiter_pair(
  pair: LatexDelimiterPair,
  wrapper: String,
  forbidden: List(String),
) -> List(Desugarer) {
  let #(d1, d2) = infra.opening_and_closing_singletons_for_pair(pair)
  case closing_equals_opening(pair) {
    True -> {
      let #(g, tag, original) = split_pair_fold_data(d1)
      [
        dl.regex_split_and_replace__outside(g, forbidden),
        dl.pair(#(tag, tag, wrapper)),
        dl.fold_into_text(#(tag, original))
      ]
    }
    False -> {
      let #(g1, tag1, replacement1) = split_pair_fold_data(d1)
      let #(g2, tag2, replacement2) = split_pair_fold_data(d2)
      [
        dl.regex_split_and_replace__outside(g1, forbidden),
        dl.regex_split_and_replace__outside(g2, forbidden),
        dl.pair(#(tag1, tag2, wrapper)),
        dl.fold_into_text(#(tag1, replacement1)),
        dl.fold_into_text(#(tag2, replacement2)),
      ]
    }
  }
}

fn create_math_or_mathblock_elements(
  parsed: List(LatexDelimiterPair),
  produced: LatexDelimiterPair,
  backup: LatexDelimiterPair,
  which: String,
) -> List(Desugarer) {
  let produced = infra.opening_and_closing_string_for_pair(produced)
  let backup = infra.opening_and_closing_string_for_pair(backup)

  let delims = case which {
    "MathBlock" -> infra.latex_strippable_display_delimiters()
    "Math" -> infra.latex_inline_delimiters()
    _ -> panic as "was expecting 'Math' or 'MathBlock'"
  }

  let strip_existing = [dl.strip_delimiters_inside(#(which, delims))]

  let create_tags =
    parsed
    |> list.map(split_pair_fold_for_delimiter_pair(_, which, ["Math", "MathBlock"]))
    |> list.flatten

  let reinsert = case which {
    "MathBlock" -> [
      dl.trim("MathBlock"),
      dl.insert_line_start_end(#("MathBlock", produced)),
    ]
    "Math" -> [
      dl.trim("Math"),
      dl.insert_text_start_end_if_else(#("Math", produced, backup, infra.descendant_text_does_not_contain(_, produced.0))),
    ]
    _ -> panic as "was expecting 'Math' or 'MathBlock'"
  }

  [
    strip_existing,
    create_tags,
    reinsert,
  ]
  |> list.flatten
}

pub fn create_mathblock_elements(
  parsed: List(LatexDelimiterPair),
  produced: LatexDelimiterPair,
) -> List(Desugarer) {
  create_math_or_mathblock_elements(parsed, produced, produced, "MathBlock")
}

pub fn create_math_elements(
  parsed: List(LatexDelimiterPair),
  produced: LatexDelimiterPair,
  backup: LatexDelimiterPair,
) -> List(Desugarer) {
  create_math_or_mathblock_elements(parsed, produced, backup, "Math")
}

//***************
// generic symmetric & asymmetric delim splitting
//***************

pub fn symmetric_delim_splitting(
  delim_regex_form: String,
  delim_ordinary_form: String,
  tag: String,
  forbidden: List(String),
) -> List(Desugarer) {
  let opening_grs = grs.for_groups([
    #("[\\s]", grs.Keep),
    #(delim_regex_form, grs.Tag("OpeningSymmetricDelim")),
    #("[^\\s\\]})]|$", grs.Keep),
  ])

  let opening_or_closing_grs = grs.for_groups([
    #("[^\\s]|^", grs.Keep),
    #(grs.unescaped_suffix(delim_regex_form), grs.Tag("OpeningOrClosingSymmetricDelim")),
    #("[^\\s\\]})]|$", grs.Keep),
  ])

  let closing_grs = grs.for_groups([
    #("[^\\s\\[{(]|^", grs.Keep),
    #(grs.unescaped_suffix(delim_regex_form), grs.Tag("ClosingSymmetricDelim")),
    #("[\\s\\]})]", grs.Keep),
  ])

  [
    dl.identity(),
    dl.regex_split_and_replace__outside(opening_or_closing_grs, forbidden),
    dl.regex_split_and_replace__outside(opening_grs, forbidden),
    dl.regex_split_and_replace__outside(closing_grs, forbidden),
    dl.pair_list_list(#(
      ["OpeningSymmetricDelim", "OpeningOrClosingSymmetricDelim"],
      ["ClosingSymmetricDelim", "OpeningOrClosingSymmetricDelim"],
      tag,
    )),
    dl.fold_into_text(#("OpeningSymmetricDelim", delim_ordinary_form)),
    dl.fold_into_text(#("ClosingSymmetricDelim", delim_ordinary_form)),
    dl.fold_into_text(#("OpeningOrClosingSymmetricDelim", delim_ordinary_form)),
  ]
}

pub fn asymmetric_delim_splitting(
  opening_regex_form: String,
  closing_regex_form: String,
  opening_ordinary_form: String,
  closing_ordinary_form: String,
  tag: String,
  forbidden: List(String),
) -> List(Desugarer) {
  let opening_grs = grs.for_groups([
    #("[\\s]|^", grs.Keep),
    #(opening_regex_form, grs.Tag("OpeningAsymmetricDelim")),
    #("[^\\s]|$", grs.Keep),
  ])

  let closing_grs = grs.for_groups([
    #("[^\\s]|^", grs.Keep),
    #(closing_regex_form, grs.Tag("ClosingAsymmetricDelim")),
    #("[\\s]|$", grs.Keep),
  ])

  [
    dl.regex_split_and_replace__outside(opening_grs, forbidden),
    dl.regex_split_and_replace__outside(closing_grs, forbidden),
    dl.pair(#("OpeningAsymmetricDelim", "ClosingAsymmetricDelim", tag)),
    dl.fold_into_text(#("OpeningAsymmetricDelim", opening_ordinary_form)),
    dl.fold_into_text(#("ClosingAsymmetricDelim", closing_ordinary_form)),
  ]
}

//***************
// barbaric symmetric & asymmetric delim splitting
//***************

pub fn barbaric_symmetric_delim_splitting(
  delim_regex_form: String,
  delim_ordinary_form: String,
  tag: String,
  forbidden: List(String),
) -> List(Desugarer) {
  let opening_or_closing_grs = grs.unescaped_suffix_replacement_splitter(delim_regex_form, "OpeningOrClosingSymmetricDelim")
  [
    dl.regex_split_and_replace__outside(opening_or_closing_grs, forbidden),
    dl.pair(#("OpeningOrClosingSymmetricDelim", "OpeningOrClosingSymmetricDelim", tag)),
    dl.fold_into_text(#("OpeningOrClosingSymmetricDelim", delim_ordinary_form))
  ]
}

//***************
// clean up after splitting
//***************

pub fn splitting_empty_lines_cleanup() -> List(Desugarer) {
  [
    dl.concatenate_text_nodes(),
    dl.delete_text_nodes_with_singleton_empty_line(),
  ]
}

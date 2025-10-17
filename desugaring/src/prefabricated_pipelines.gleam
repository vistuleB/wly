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
import vxml.{type VXML, V, Attr}
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

type NaiveUnescapedSplitPairFoldData {
  NaiveUnescapedSplitPairFoldData(
    splitter: String,
    escaped_splitter_replacement: String,
    replacement: grs.SplitReplacementInstruction,
    tag: String,
  )
}

fn naive_unescaped_split_pair_fold_data(
  which: LatexDelimiterSingleton
) -> NaiveUnescapedSplitPairFoldData {
  case which {
    DoubleDollarSingleton -> NaiveUnescapedSplitPairFoldData(
      splitter: "$$",
      escaped_splitter_replacement: "\\$$",
      replacement: grs.Tag("DoubleDollar"),
      tag: "DoubleDollar",
    )

    SingleDollarSingleton -> NaiveUnescapedSplitPairFoldData(
      splitter: "$",
      escaped_splitter_replacement: "\\$",
      replacement: grs.Tag("SingleDollar"),
      tag: "SingleDollar",
    )

    BackslashOpeningParenthesis -> NaiveUnescapedSplitPairFoldData(
      splitter: "\\(",
      escaped_splitter_replacement: "\\\\(",
      replacement: grs.Tag("LatexOpeningPar"),
      tag: "LatexOpeningPar",
    )

    BackslashClosingParenthesis -> NaiveUnescapedSplitPairFoldData(
      splitter: "\\)",
      escaped_splitter_replacement: "\\\\)",
      replacement: grs.Tag("LatexClosingPar"),
      tag: "LatexClosingPar",
    )

    BackslashOpeningSquareBracket -> NaiveUnescapedSplitPairFoldData(
      splitter: "\\[",
      escaped_splitter_replacement: "\\\\[",
      replacement: grs.Tag("LatexOpeningBra"),
      tag: "LatexOpeningBra",
    )

    BackslashClosingSquareBracket -> NaiveUnescapedSplitPairFoldData(
      splitter: "\\]",
      escaped_splitter_replacement: "\\\\]",
      replacement: grs.Tag("LatexClosingBra"),
      tag: "LatexClosingBra",
    )

    BeginAlign -> NaiveUnescapedSplitPairFoldData(
      splitter: "\\begin{align}",
      escaped_splitter_replacement: "\\\\begin{align}",
      replacement: grs.TagAndText("BeginAlign", "\\begin{align}"),
      tag: "BeginAlign",
    )

    EndAlign -> NaiveUnescapedSplitPairFoldData(
      splitter: "\\end{align}",
      escaped_splitter_replacement: "\\\\end{align}",
      replacement: grs.TagAndText("EndAlign", "\\end{align}"),
      tag: "EndAlign",
    )

    BeginAlignStar -> NaiveUnescapedSplitPairFoldData(
      splitter: "\\begin{align*}",
      escaped_splitter_replacement: "\\\\begin{align*}",
      replacement: grs.TagAndText("BeginAlignStar", "\\begin{align*}"),
      tag: "BeginAlignStar",
    )

    EndAlignStar -> NaiveUnescapedSplitPairFoldData(
      splitter: "\\end{align*}",
      escaped_splitter_replacement: "\\\\end{align*}",
      replacement: grs.TagAndText("EndAlignStar", "\\end{align*}"),
      tag: "EndAlignStar",
    )
  }
}

type RRSSplitPairFoldData {
  RRSSplitPairFoldData(
    splitter: grs.RegexpReplacementerSplitter,
    tag: String,
    original: String,
  )
}

fn rrs_split_pair_fold_data(
  which: LatexDelimiterSingleton
) -> RRSSplitPairFoldData {
  case which {
    DoubleDollarSingleton -> RRSSplitPairFoldData(
      grs.unescaped_suffix_rr_splitter(re_suffix: "\\$\\$", replacement: grs.Tag("DoubleDollar")),
      "DoubleDollar",
      "$$",
    )

    SingleDollarSingleton -> RRSSplitPairFoldData(
      grs.unescaped_suffix_rr_splitter(re_suffix: "\\$", replacement: grs.Tag("SingleDollar")),
      "SingleDollar",
      "$",
    )

    BackslashOpeningParenthesis -> RRSSplitPairFoldData(
      grs.unescaped_suffix_rr_splitter(re_suffix: "\\\\\\(", replacement: grs.Tag("LatexOpeningPar")),
        "LatexOpeningPar",
        "\\(",
      )

    BackslashClosingParenthesis -> RRSSplitPairFoldData(
      grs.unescaped_suffix_rr_splitter(re_suffix: "\\\\\\)", replacement: grs.Tag("LatexClosingPar")),
      "LatexClosingPar",
      "\\)",
    )

    BackslashOpeningSquareBracket -> RRSSplitPairFoldData(
      grs.unescaped_suffix_rr_splitter(re_suffix: "\\\\\\[", replacement: grs.Tag("LatexOpeningBra")),
      "LatexOpeningBra",
      "\\[",
    )

    BackslashClosingSquareBracket -> RRSSplitPairFoldData(
      grs.unescaped_suffix_rr_splitter(re_suffix: "\\\\\\]", replacement: grs.Tag("LatexClosingBra")),
      "LatexClosingBra",
      "\\]",
    )

    BeginAlign -> RRSSplitPairFoldData(
      grs.rr_splitter(re_string: "\\\\begin{align}", replacement: grs.TagAndText("BeginAlign", "\\begin{align}")),
      "BeginAlign",
      "\\begin{align}",
    )

    EndAlign -> RRSSplitPairFoldData(
      grs.rr_splitter(re_string: "\\\\end{align}", replacement: grs.TextAndTag("EndAlign", "\\end{align}")),
      "EndAlign",
      "\\end{align}",
    )

    BeginAlignStar -> RRSSplitPairFoldData(
      grs.rr_splitter(re_string: "\\\\begin{align\\*}", replacement: grs.TagAndText("BeginAlignStar", "\\begin{align*}")),
      "BeginAlignStar",
      "\\begin{align*}",
    )

    EndAlignStar -> RRSSplitPairFoldData(
      grs.rr_splitter(re_string: "\\\\end{align\\*}", replacement: grs.TextAndTag("EndAlignStar", "\\end{align*}")),
      "EndAlignStar",
      "\\end{align*}",
    )
  }
}

fn split_pair_fold_for_delimiter_pair(
  pair: LatexDelimiterPair,
  wrapper: String,
  unbridgeable: List(String),
  forbidden: List(String),
) -> List(Desugarer) {
  let #(d1, d2) = infra.opening_and_closing_singletons_for_pair(pair)
  case closing_equals_opening(pair) {
    True -> {
      // let RRSSplitPairFoldData(rrs, tag, original) = rrs_split_pair_fold_data(d1)
      // [
      //   dl.regex_split_and_replace__outside(rrs, forbidden),
      //   dl.pair(#(tag, tag, wrapper, unbridgeable)),
      //   dl.fold_into_text(#(tag, original))
      // ]
      let NaiveUnescapedSplitPairFoldData(s, e, r, tag) = naive_unescaped_split_pair_fold_data(d1)
      [
        dl.naive_unsecaped_split_and_replace__outside(#(s, e, r), forbidden),
        dl.pair(#(tag, tag, wrapper, unbridgeable)),
        dl.fold_into_text(#(tag, s))
      ]
    }
    False -> {
      let RRSSplitPairFoldData(rrs1, tag1, replacement1) = rrs_split_pair_fold_data(d1)
      let RRSSplitPairFoldData(rrs2, tag2, replacement2) = rrs_split_pair_fold_data(d2)
      [
        dl.regex_split_and_replace__outside(rrs1, forbidden),
        dl.regex_split_and_replace__outside(rrs2, forbidden),
        dl.pair(#(tag1, tag2, wrapper, unbridgeable)),
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
  unbridgeable: List(String),
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
    |> list.map(split_pair_fold_for_delimiter_pair(_, which, unbridgeable, ["Math", "MathBlock"]))
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
  create_math_or_mathblock_elements(parsed, produced, produced, "MathBlock", ["WriterlyBlankLine"])
}

pub fn create_math_elements(
  parsed: List(LatexDelimiterPair),
  produced: LatexDelimiterPair,
  backup: LatexDelimiterPair,
) -> List(Desugarer) {
  create_math_or_mathblock_elements(parsed, produced, backup, "Math", ["WriterlyBlankLine"])
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
  let opening_grs = grs.rr_splitter_for_groups([
    #("[\\s]", grs.Keep),
    #(delim_regex_form, grs.Tag("OpeningSymmetricDelim")),
    #("[^\\s\\]})]|$", grs.Keep),
  ])

  let opening_or_closing_grs = grs.rr_splitter_for_groups([
    #("[^\\s]|^", grs.Keep),
    #(grs.unescaped_suffix(delim_regex_form), grs.Tag("OpeningOrClosingSymmetricDelim")),
    #("[^\\s\\]})]|$", grs.Keep),
  ])

  let closing_grs = grs.rr_splitter_for_groups([
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
  let opening_grs = grs.rr_splitter_for_groups([
    #("[\\s]|^", grs.Keep),
    #(opening_regex_form, grs.Tag("OpeningAsymmetricDelim")),
    #("[^\\s]|$", grs.Keep),
  ])

  let closing_grs = grs.rr_splitter_for_groups([
    #("[^\\s]|^", grs.Keep),
    #(closing_regex_form, grs.Tag("ClosingAsymmetricDelim")),
    #("[\\s]|$", grs.Keep),
  ])

  [
    dl.regex_split_and_replace__outside(opening_grs, forbidden),
    dl.regex_split_and_replace__outside(closing_grs, forbidden),
    dl.pair(#("OpeningAsymmetricDelim", "ClosingAsymmetricDelim", tag, ["WriterlyBlankLine"])),
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
  let opening_or_closing_grs = grs.unescaped_suffix_rr_splitter(
    re_suffix: delim_regex_form,
    replacement: grs.Tag("OpeningOrClosingSymmetricDelim")
  )
  [
    dl.regex_split_and_replace__outside(opening_or_closing_grs, forbidden),
    dl.pair(#("OpeningOrClosingSymmetricDelim", "OpeningOrClosingSymmetricDelim", tag, ["WriterlyBlankLine"])),
    dl.fold_into_text(#("OpeningOrClosingSymmetricDelim", delim_ordinary_form)),
  ]
}

// **************
// annotated backticks
// **************

pub fn annotated_backtick_splitting(
  tag: String,
  annotation_key: String,
  forbidden: List(String),
) -> List(Desugarer) {
  let text_folder = fn(v: VXML) -> String {
    let assert V(_, _, [Attr(_, z, value)], _) = v
    assert z == annotation_key
    "`{" <> value <> "}"
  }
  let start_tag = "AnnotatedBackticksOpening"
  let end_tag = "AnnotatedBackticksClosing"
  let start_splitter = grs.unescaped_suffix_rr_splitter("`", grs.Tag(start_tag))
  let end_splitter = grs.rr_splitter_for_groups([
    #("`{", grs.Trash),
    #("[a-zA-Z0-9\\-\\.#_]*", grs.TagWithSplitAsVal(end_tag, annotation_key)),
    #("}", grs.Trash),
  ])
  [
    [
      dl.regex_split_and_replace__outside(end_splitter, forbidden),
      dl.regex_split_and_replace__outside(start_splitter, forbidden),
      dl.pair(#(start_tag, end_tag, "AnnotatedBackticks", ["WriterlyBlankLine"])),
      dl.fold_into_text(#("AnnotatedBackticksOpening", "`")),
      dl.fold_custom_into_text(#("AnnotatedBackticksClosing", text_folder)),
    ],
    case tag == "AnnotatedBackticks" {
      True -> []
      False -> [dl.rename(#("AnnotatedBackticks", tag))]
    }
  ]
  |> list.flatten
}

// **************
// markdown-style links
// **************

pub fn markdown_link_splitting(
  forbidden: List(String),
) -> List(Desugarer) {
  let text_folder = fn(v: VXML) -> String {
    let assert V(_, _, [Attr(_, "href", value)], _) = v
    "]aaa\\(" <> value <> "\\)"
  }
  let start_tag = "MDLinkOpening"
  let end_tag = "MDLinkClosing"
  let start_splitter = grs.unescaped_suffix_rr_splitter("\\[", grs.Tag(start_tag))
  [
    dl.markdown_link_closing_handrolled_splitter(end_tag, forbidden),
    dl.regex_split_and_replace__outside(start_splitter, forbidden),
    dl.pair(#(start_tag, end_tag, "MDLink", ["WriterlyBlankLine"])),
    dl.fold_into_text(#("MDLinkOpening", "[")),
    dl.fold_custom_into_text(#("MDLinkClosing", text_folder)),
    dl.rename(#("MDLink", "a")),
  ]
}

//***************
// clean up after splitting
//***************

pub fn splitting_empty_lines_cleanup() -> List(Desugarer) {
  [
    dl.concatenate_text_nodes(),
    dl.timer(),
    dl.delete_text_nodes_with_singleton_empty_line(),
    dl.timer(),
  ]
}

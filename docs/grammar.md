# Doctrine DSL grammar

This document defines surface-language syntax version 1 for Milestone 1. The
parser accepts the grammar below; name resolution, type rules, capabilities,
and pipeline desugaring remain later milestones.

## Source coordinates

The lexer preserves the original source bytes. Every token has a half-open
span `{ start_byte, end_byte, start_line, start_column, end_line, end_column }`.
Byte offsets are zero-based; lines and byte columns are one-based. A node span
starts at its first syntactic token and ends after its last syntactic token.
`\r\n` is one line break, `\n` is one line break, and a bare `\r` produces
`invalid_line_ending`. Synthetic layout tokens have a zero-length span at the
first non-indentation byte of their line.

## Lexical grammar

```ebnf
lower_identifier = ( "a"…"z" | "_" ), { "a"…"z" | "A"…"Z" | "0"…"9" | "_" } ;
upper_identifier = "A"…"Z", { "a"…"z" | "A"…"Z" | "0"…"9" | "_" } ;
identifier       = lower_identifier | upper_identifier ;
integer          = "0" | ( "1"…"9" ), { "0"…"9" } ;
float            = integer, ".", "0"…"9", { "0"…"9" } ;
quantity         = ( integer | float ), ( "ms" | "m" | "deg" ) ;
string           = '"', { string_character | escape }, '"' ;
escape           = "\\", ( '"' | "\\" | "n" | "r" | "t" ) ;
comment          = "--", { any byte except line break } ;
```

`true`, `false`, `module`, `expose`, `let`, `in`, `if`, `then`, `else`,
`case`, and `of` are reserved keywords. `true` and `false` are boolean
literals. The lexer rejects tabs in leading indentation with
`invalid_indentation`; indentation uses spaces only. Blank and comment-only
lines do not change indentation. A non-blank line must either indent farther
than its parent or match a previous indentation depth; otherwise the lexer
emits `inconsistent_indentation`.

The punctuation tokens are `(`, `)`, `[`, `]`, `{`, `}`, `,`, `.`, `=`,
`->`, and `|>`. The operator tokens are `<`, `<=`, `==`, `!=`, `>=`, `>`,
`+`, `-`, `*`, and `/`. An unknown byte, unterminated string, invalid escape,
or malformed quantity produces one structured lexical diagnostic and consumes
at least one byte.

## Layout

Newlines separate declarations and case alternatives. `NEWLINE`, `INDENT`, and
`DEDENT` below are lexer tokens; `INDENT` and `DEDENT` are emitted by comparing
each non-blank line's leading-space count with the active indentation stack.

Within an expression, a newline is whitespace only immediately after `=`,
`->`, `then`, `else`, `in`, `of`, an infix operator, `|>`, `(`, `[`, `{`, or
`,`; it is also whitespace immediately before `then`, `else`, `in`, an infix
operator, or `|>`. Elsewhere it terminates the current expression. This keeps
ordinary function application on one line and makes case alternatives
unambiguous without punctuation.

## Concrete grammar

```ebnf
program          = { NEWLINE }, [ module_header, NEWLINE ],
                   { expose_declaration, NEWLINE },
                   declaration, { NEWLINE, declaration }, { NEWLINE }, EOF ;
module_header    = "module", upper_identifier ;
expose_declaration = "expose", lower_identifier,
                     { ",", lower_identifier } ;
declaration      = lower_identifier, { lower_identifier }, "=", expression ;

expression       = let_expression | if_expression | case_expression | pipeline ;
let_expression   = "let", lower_identifier, "=", expression, "in", expression ;
if_expression    = "if", expression, "then", expression, "else", expression ;
case_expression  = "case", expression, "of", NEWLINE, INDENT,
                   case_alternative, { NEWLINE, case_alternative }, DEDENT ;
case_alternative  = pattern, "->", expression ;

pipeline         = comparison, { "|>", comparison } ;
comparison       = addition, { ( "<" | "<=" | "==" | "!=" | ">=" | ">" ), addition } ;
addition          = multiplication, { ( "+" | "-" ), multiplication } ;
multiplication    = application, { ( "*" | "/" ), application } ;
application       = postfix, { postfix } ;
postfix           = primary, { ".", lower_identifier } ;
primary           = literal | identifier | record | list | parenthesised ;
parenthesised     = "(", expression, [ ",", expression, { ",", expression } ], ")"
                   | "(" , ")" ;
record            = "{", [ record_field, { ",", record_field }, [ "," ] ], "}" ;
record_field      = lower_identifier, "=", expression ;
list              = "[", [ expression, { ",", expression }, [ "," ] ], "]" ;
literal           = integer | float | quantity | string | "true" | "false" ;

pattern           = "_" | literal | upper_identifier, { pattern_atom }
                   | lower_identifier | tuple_pattern | list_pattern ;
pattern_atom      = literal | upper_identifier | lower_identifier | tuple_pattern | list_pattern ;
tuple_pattern     = "(", pattern, ",", pattern, { ",", pattern }, ")" ;
list_pattern      = "[", [ pattern, { ",", pattern } ], "]" ;
```

Function application associates left, infix operators associate left, and
field access binds tighter than application. A constructor is an uppercase
identifier; whether a constructor or an operator is valid in context is a
later name-resolution and type-checking concern. A parenthesised expression is
not a tuple unless it contains a comma. `()` is the unit literal.

`case` alternatives must occupy the same indentation depth. A nested
expression can span further-indented lines. The canonical example is:

```text
act view memory =
  let danger = dangerScore view
  in
  case nearestCasualty view of
    Some ally ->
      if danger < 0.60
      then (memory, moveAndStabilise view ally)
      else (memory, requestCover ally.position)
    None ->
      engageOrAdvance view memory
```

## Parser recovery

The parser reports structured diagnostics with `{ code, message, span,
expected }`. At a failed top-level declaration it synchronizes at the next
top-level `NEWLINE` or `EOF`; inside a case expression it synchronizes at the
next alternative indentation or its closing `DEDENT`. Recovery never invents
source spans and must make forward progress.

## Deferred surface syntax

Type signatures, `requires` manifests, lambdas, record patterns, record
updates, user-defined operators, and semicolon-separated alternatives are not
part of syntax version 1. They must be documented before becoming accepted
syntax.

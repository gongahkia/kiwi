# Functional DSL Specification

## 1. Purpose

The Kiwi language lets players define how squads and operatives transform incomplete observations into explicit memory and tactical intentions. It is designed for gameplay, causal explanation, deterministic execution, and progressive learning—not for general-purpose computing.

The language should feel functional and compact without requiring prior Haskell, OCaml, or Elm experience. It may borrow familiar concepts, but syntax and diagnostics should favour readability in a small bitmap-font terminal.

## 2. Governing principles

1. **Pure by construction.** Programs cannot mutate the world or hidden global state.
2. **Explicit state.** Persistent state is passed in and returned as memory.
3. **Small core.** Add library functions before syntax.
4. **Total where practical.** Missing data and failures use tagged values rather than null or exceptions.
5. **Bounded execution.** All programs have deterministic instruction, stack, and allocation budgets.
6. **Typed tactical values.** Distances, durations, probabilities, positions, contacts, and intentions are not interchangeable numbers.
7. **Source provenance.** Every executable expression maps back to source.
8. **Stable semantics.** Language and bytecode versions are explicit.

## 3. Conceptual execution model

An operative policy has the conceptual form:

```text
step : Observation -> Memory -> Decision

Decision = {
  memory : Memory,
  intentions : List Intent
}
```

The runtime:

1. receives immutable observation and memory values;
2. evaluates the function under deterministic budgets;
3. obtains a decision value;
4. validates the returned memory shape and intentions;
5. gives intentions to the simulation;
6. records evaluation provenance.

The language cannot directly observe Python, pygame, files, network, wall time, or unrecorded randomness.

At the policy boundary, a caller supplies a closed nominal memory schema with
lexically ordered field names and data types. `Decision` is a closed record
with exactly `memory` and `intentions` fields: `memory` must validate against
that schema and `intentions` must be a bounded list. Function values are not
valid persistent-memory fields. Capability-specific intention variants are
validated by the simulation layer once they exist; this language boundary does
not resolve or execute an intention.

## 4. Language layers

### 4.1 Surface language

Player-authored syntax with names, indentation or delimiters, friendly diagnostics, pipelines, records, variants, and pattern matching.

### 4.2 Resolved and typed tree

All names point to stable definitions, all expressions have checked types, patterns are validated, and source spans remain attached.

### 4.3 Core IR

A small desugared functional representation containing:

- constants;
- local references;
- global function references;
- function application;
- let binding;
- conditional;
- variant construction;
- case selection;
- record construction and field access;
- list construction;
- intrinsic calls.

Pipelines, syntactic sugar, and convenience declarations lower into this core.

### 4.4 Bytecode

A versioned deterministic instruction stream plus constants, functions, type metadata, source map, and capability manifest.

## 5. Proposed surface syntax

The exact syntax may be refined through parser fixtures, but the initial target is:

```text
policy cautious(view: Observation, memory: Memory) -> Decision =
  let threats =
    view.contacts
    |> List.filter(Contact.is_hostile)
    |> List.filter(fn contact -> contact.confidence >= 70%)

  match List.nearest_by(threats, fn contact -> contact.position) with
  | Some(target) ->
      if Threat.danger(view.self, target) >= memory.retreat_threshold then
        Decision {
          memory = memory,
          intentions = [Cover.seek_from(target.position)]
        }
      else
        Decision {
          memory = memory,
          intentions = [Move.toward(view.objective.position, Cautious)]
        }

  | None ->
      Decision {
        memory = memory,
        intentions = [Move.toward(view.objective.position, Normal)]
      }
```

Surface goals:

- readable left-to-right data flow;
- explicit variants;
- visible units;
- minimal punctuation noise;
- no semicolons;
- source that remains legible in 8×12 bitmap text.

## 6. Lexical rules

### 6.1 Identifiers

- Lower snake case for values and functions.
- Upper camel case for types and variant constructors.
- ASCII identifiers in MVP.
- Reserved words cannot be rebound.

### 6.2 Comments

```text
# line comment
```

Block comments are deferred unless clearly needed.

### 6.3 Literals

MVP literals:

```text
42
-7
true
false
"alpha"
250ms
3s
8m
45deg
70%
```

Floating-point decimal literals are not required in canonical semantics. Decimal surface values may lower into rational or fixed-point quantities with exact validation.

Milestone 4 implements double-quoted strings and integer-magnitude quantity
literals. Strings decode `\\`, `\"`, `\n`, `\r`, and `\t`; raw newlines and
other escapes are lexer errors. Decoded strings are bounded to 65,536 UTF-8
bytes. Quantity literals normalize exactly: `ms` to seconds, `s` to seconds,
`m` to metres, `deg` to turns, and `%` to fractions. Their stored form is a
dimension tag plus a reduced signed rational with a positive denominator;
surface probability magnitudes are restricted to `0` through `100`.

## 7. Core expressions

### 7.1 Bindings

```text
let score = Threat.score(view, target) in score
```

Bindings are immutable and lexically scoped.

Milestone 1 uses the explicit `let name = value in body` form. Layout-sensitive binding syntax remains deferred until a parser grammar defines it.

### 7.2 Functions

Named functions:

```text
fn danger(contact: Contact) -> Probability =
  contact.confidence * contact.threat
```

Anonymous functions:

```text
fn contact -> contact.confidence >= 60%
```

The implemented form also permits `fn (first, second) -> body` and `fn () -> body`.
Anonymous functions require an expected function type; their parameters receive
those expected types. A closure captures distinct immutable lexical values by
first source reference, at most 64 values. Capturing costs one allocation unit
per capture plus one closure container unit.

### 7.3 Application

```text
Threat.score(view.self, target)
```

No implicit method dispatch. Module-qualified standard-library names are normal functions, though field-access syntax is permitted for records.

### 7.4 Pipeline

```text
view.contacts
|> List.filter(Contact.is_hostile)
|> List.sort_by(Contact.distance)
```

`value |> function(args...)` desugars to `function(value, args...)`. Bare callable
stages desugar to `function(value)`. Stages associate left to right, and the
desugared call retains the full pipeline span for diagnostics and provenance.

### 7.5 Conditional

```text
if condition then expression_a else expression_b
```

Both branches must have compatible types.

### 7.6 Pattern matching

```text
match value with
| Some(item) -> use(item)
| None -> fallback
```

Patterns include:

- variant constructor;
- literal;
- wildcard;
- bound name;
- record pattern in a later version.

Matches over closed variants must be exhaustive. Redundant arms produce warnings or errors according to policy.

Milestone 4 first implements the closed built-in `Option<T>` constructors:

```text
Some(value)
None
```

`Some(value)` has type `Option<T>` when `value` has type `T`. `None` has no
payload and must occur where an `Option<T>` is already expected: a declared
return type, a function parameter, a record field, or the corresponding branch
of a typed conditional. It cannot be inferred for an unannotated `let` value.
The current match grammar is intentionally limited to `Option<T>`:

```text
match value with
| Some(item) -> expression
| None -> expression
```

Each arm must appear exactly once. `Some(item)` binds `item` only in its arm;
both arm expressions must have the same type. Literal, wildcard, and record
patterns remain deferred until their source variants exist.

### 7.7 Records

```text
type Memory = { retreat_threshold: Probability, label: String }
Memory { retreat_threshold = 65%, label = "cautious" }
```

Field access:

```text
memory.retreat_threshold
```

Milestone 4 records are nominal, immutable, and closed by their declared
schema. Construction must supply every declared field exactly once; field values
are checked against their declarations. Field expressions evaluate in source
order, while the runtime representation stores fields in lexical field-name
order so equal records have one canonical value layout. Field access uses a
statically named field and is rejected for non-record values or unknown fields.

Record update syntax may be added later:

```text
memory with { retreat_threshold = 55% }
```

The MVP may instead require explicit constructors if update syntax complicates implementation.

### 7.8 Lists

```text
[Move.toward(position, Normal), Emit.radio(message)]
```

Lists are immutable, contain at most 1,024 values, and are bounded by runtime allocation limits.

The current list literal is source ordered:

```text
[first, second]
```

All elements must have one type. A nonempty literal infers `List<T>` from its
first element; `[]` requires an expected `List<T>` type. Runtime lists contain
at most 1,024 values. Constructing a list charges one allocation unit per
element plus one for its immutable container.

## 8. Declarations

### 8.1 Type aliases

```text
type ContactId = Id<Contact>
```

May be internal-only in MVP.

### 8.2 Record types

```text
type Memory = {
  retreat_threshold: Probability,
  last_target: Option<ContactId>
}
```

### 8.3 Variant types

```text
type Mode = Advance | Hold | Extract
```

User-defined variants may be deferred until the compiler core is stable. Built-in variants such as `Option` are mandatory.

### 8.4 Policy declaration

```text
policy cautious(view: Observation, memory: Memory) -> Decision = ...
```

A module may export only explicitly declared policy entry points.

## 9. Type system

## 9.1 Primitive types

- `Int`
- `Bool`
- `String`
- `Unit`

### 9.2 Domain quantities

- `Tick`
- `Duration`
- `Distance`
- `Speed`
- `Angle`
- `Probability`
- `Confidence`
- `Health`
- `Suppression`
- `Position`
- `Vector`

Milestone 4 resolves `Duration`, `Distance`, `Angle`, and `Probability` as
built-in types for the corresponding literals. It also reserves the closed
nominal records `Position { x: Distance, y: Distance }` and
`Vector { dx: Distance, dy: Distance }`; user declarations cannot redefine
them. Other nominal record types use `type Name = { field: Type, ... }`.

The checked binary operator matrix is deliberately closed:

```text
Duration +/- Duration -> Duration
Distance +/- Distance -> Distance
Duration, Distance, Probability < <= > >= same type -> Bool
Position + Vector -> Position
Position - Vector -> Position
Position - Position -> Vector
Vector +/- Vector -> Vector
```

Quantity and coordinate arithmetic use exact normalized rationals. Probability
has comparisons only; angle arithmetic, multiplication, division, mixed
dimensions, reversed coordinate operands, and all other combinations are type
errors. Simulation conversion remains outside the DSL: exact `Distance` values
become signed 64-bit millimetres at the simulation boundary (1 metre = 1,000
millimetres, nearest rounding with half ties away from zero). Elevation remains
simulation state, not a DSL coordinate field.

Examples:

```text
Distance / Duration -> Speed
Position - Position -> Vector
Probability * Probability -> Probability  # only if explicitly defined
Distance + Duration -> type error
```

### 9.3 Tactical types

- `Observation`
- `SelfObservation`
- `Contact`
- `CoverPoint`
- `Objective`
- `Signal`
- `Intent`
- `Decision`
- `Message<T>` or closed message types in MVP

### 9.4 Parametric built-ins

- `Option<T>`
- `List<T>`
- `Result<T, E>` may be added after MVP if needed

The implemented `Option<T>` is a closed one-argument type constructor. Its only
values are `Some(value)` and contextually typed `None`; it has no null value or
implicit conversion.

The implemented `List<T>` is a closed one-argument immutable sequence type.
Only list literals construct it until bounded collection intrinsics are added.

### 9.5 Function types

```text
Contact -> Probability
Observation -> Memory -> Decision
```

Functions are first-class within budget and representation limits.

The Milestone 4 parser and compiler support immutable primitive, named, list,
option, and ordered function types. Function types use `() -> A` for no
parameters, `A -> B` for one parameter, `(A, B) -> C` for multiple parameters,
parentheses for a function-typed parameter, and right-associative returns.

### 9.6 Type inference

MVP inference policy:

- entry-point parameters and returns require annotations;
- named public functions require parameter and return annotations;
- local binding types are inferred;
- anonymous function parameter types are inferred from context where unambiguous;
- literals are checked against expected domain types;
- no generalisation of arbitrary local bindings unless explicitly implemented and tested.

This keeps the checker tractable while preserving concise policy code.

### 9.7 Equality and ordering

Only types with explicitly defined equality or ordering support those operations. Functions are never comparable. Records and variants derive equality only when all contained types support it.

## 10. Explicit memory

Memory is the only policy-persistent state. It is:

- immutable during evaluation;
- returned explicitly;
- type checked;
- serialisable;
- bounded;
- included in replay state;
- visible to the debugger.

Example:

```text
type Memory = {
  mode: Mode,
  last_contact: Option<ContactId>,
  caution: Probability
}
```

The runtime validates that returned memory matches the declared schema. A runtime fault triggers a deterministic fallback and does not corrupt simulation state.

## 11. Observation API

Observations are values constructed by the simulation. Policies cannot enumerate hidden entities.

Example fields:

```text
Observation {
  self: SelfObservation,
  contacts: List<Contact>,
  allies: List<AllyObservation>,
  visible_cover: List<CoverPoint>,
  objective: ObjectiveObservation,
  signals: List<Signal>,
  messages: List<Message>,
  tick: Tick
}
```

Fields must encode uncertainty explicitly. A missing value is `None`, not a sentinel.

Observation reads are instrumented. The VM trace can record that a branch depended on `target.confidence`, `view.self.suppression`, or `cover.exposure`.

The current runtime observation ABI is version `5`. It exposes
`Observation { inbox, nearest_contact, self, signals, tick, visible_covers }`, where `self` is
`SelfObservation { entity_id, position }`, `position` is the existing
`Position { x: Distance, y: Distance }` record, and `inbox` is
`InboxObservation { messages: List<Message> }`. The observation builder derives
this inbox from the authoritative delivered-message ledger and never exposes
another entity's inbox. `signals` is the owner-local current-tick
`List<Signal>`, where `Signal { name: String, tick: Int }`; squad signals are
visible to every policy and targeted signals only to their target.
`nearest_contact` is `Option<Contact>` selected from the owner's contact store
by exact planar squared distance, then ascending contact ID. `Contact` is
`{ age_ticks: Int, confidence_basis_points: Int, contact_id: Int,
estimated_position: Position, uncertainty_radius: Distance }`; it exposes no
target entity ID, owner identity, elevation, true state, or provenance IDs. A
`ContactReport` in the inbox is raw message data and does not implicitly become
a contact. These immutable values contain no hidden entity state, renderer data,
or writable references. Adding observable fields requires an ABI version and
policy-compatibility update.

`visible_covers` is a `List<Cover>` in ascending cover ID order. `Cover` is
`{ cover_id: Int, end: Position, height: String, integrity_basis_points: Int,
slots: List<CoverSlot>, start: Position }`, and `CoverSlot` is
`{ position: Position, side: String, slot_index: Int }`. This projection has no
occupancy or reservation state.

## 12. Intention API

Core intent variants:

```text
Intent =
  MoveToward(Position, Stance)
  | TakeCover(CoverId, CoverSide)
  | Aim(TargetEstimate)
  | Fire(WeaponId, TargetEstimate)
  | Stabilise(OperativeId)
  | Use(ItemId, Target)
  | Emit(ChannelId, Message)
  | Wait(Duration)
```

The exact constructors exposed to players may be wrapped by standard-library functions. Keep the VM representation closed and versioned.

The initial simulation boundary accepts `Wait { duration: Duration }` with a
strictly positive duration, `MoveToward { target: Position }`, and
`TakeCover { cover_id: Int, side: String }`. TakeCover requires a positive cover
ID and `left` or `right` side string. It reserves the first eligible slot of
that side in ascending slot-index order; occupancy and physical movement remain
separate authority phases. Other named core kinds remain unavailable until their
domain payload models are implemented; they produce a structured simulation
validation failure rather than being reinterpreted as another request.

## 13. Standard library

### 13.1 Design rule

The standard library should provide safe reusable tactics without adding hidden authority. Every function is pure and traceable.

### 13.2 Initial modules

#### `List`

- `map`
- `filter`
- `fold`
- `any`
- `all`
- `find`
- `first`
- `length`
- `sort_by` with deterministic tie-breaking
- `min_by`
- `max_by`

All traversals consume predictable budget proportional to list length.

Milestone 4 provides these direct, closed calls; `List.map` and its siblings
are not first-class values:

```text
List.map(list, callback)       : List<T> × (T -> U) -> List<U>
List.filter(list, predicate)   : List<T> × (T -> Bool) -> List<T>
List.fold(list, initial, step) : List<T> × A × (A, T -> A) -> A
List.find(list, predicate)     : List<T> × (T -> Bool) -> Option<T>
List.min_by(list, key)         : List<T> × (T -> K) -> Option<T>
List.sort_by(list, key)        : List<T> × (T -> K) -> List<T>
```

Callbacks run left to right. `filter` preserves retained input order, `find`
returns the first matching item, and `fold` applies `step` from the initial
accumulator through input order. `min_by` and `sort_by` accept only `Int`,
`Bool`, `String`, `Duration`, `Distance`, `Angle`, or `Probability` keys;
booleans order `false < true`, strings use Unicode code-point order, and
quantities compare only within one dimension. Equal keys preserve input order:
`min_by` selects the first minimum and `sort_by` is stable. Each input and
output list remains bounded to 1,024 items.

#### `Option`

- `map`
- `with_default`
- `is_some`

#### `Math`

- integer and quantity operations;
- clamp;
- min and max;
- absolute value.

#### `Geometry`

- distance;
- direction;
- angle difference;
- line intersection queries over observed geometry only.

#### `Contact`

- hostile predicate;
- age;
- estimated distance;
- confidence threshold;
- threat estimate.

#### `Cover`

- visible candidates;
- exposure estimate;
- nearest safe;
- route cost;
- seek intention.

#### `Movement`

- move toward;
- maintain distance;
- follow assignment;
- avoid region.

#### `Squad`

- assigned role;
- assigned target;
- nearest ally;
- casualty selection.

#### `Intent`

- constructors and compatibility helpers.

### 13.3 Standard-library traceability

A standard-library function may emit summarised trace nodes, but the debugger must allow expansion to relevant internal decisions where needed. Do not hide decisive thresholds inside opaque native functions.

## 14. Restrictions

MVP restrictions:

- no mutation;
- no loops;
- no user recursion;
- no exceptions;
- no null;
- no reflection;
- no dynamic field names;
- no runtime module loading;
- no filesystem or network;
- no system time;
- no implicit random function;
- no unbounded collection creation;
- no polymorphic recursion;
- no operator overloading by users;
- no Python interoperability.

## 15. Compiler pipeline

### 15.1 Tokenisation

Produce tokens with:

- kind;
- lexeme or decoded value;
- byte offset;
- line and column;
- source-file identifier;
- span.

Source offsets are zero-based UTF-8 byte offsets. Lines and columns are one-based, with columns counted in Unicode code points. Spans are half-open `[start, end)` ranges whose boundaries must fall on UTF-8 code-point boundaries.

The filesystem loader reads at most 1,048,576 bytes, decodes strict UTF-8, and returns a structured source-load failure for unreadable, oversized, or invalid-encoding input.

Invalid characters and unterminated literals produce recoverable diagnostics where possible.

Integer magnitudes are limited to 1,024 decimal digits. The lexer reports and
skips longer integer or quantity magnitudes so a bounded source file cannot
create an unbounded host-integer allocation. String errors are
`E102_UNTERMINATED_STRING`, `E103_INVALID_STRING_ESCAPE`, and
`E104_STRING_TOO_LONG`; invalid units and probability magnitudes are
`E105_INVALID_QUANTITY_UNIT` and `E106_INVALID_PROBABILITY`.

### 15.2 Parsing

Use a hand-written recursive-descent or Pratt parser with explicit precedence. Avoid a parser-generator dependency unless demonstrated to improve diagnostics and maintenance.

The implemented Milestone 4 recursive-descent grammar is:

```text
module      := declaration* EOF
declaration := value_declaration | record_declaration
value_declaration := ("policy" | "fn") identifier "(" parameters? ")" "->" type "=" expression
record_declaration := "type" identifier "=" "{" record_type_fields? "}"
record_type_fields := record_type_field ("," record_type_field)*
record_type_field := identifier ":" type
parameters  := parameter ("," parameter)*
parameter   := identifier ":" type
type        := type_atom ("->" type)?
type_atom   := identifier ("<" type ("," type)* ">")? | "(" type_list? ")" "->" type
type_list   := type ("," type)*
expression  := let | conditional | match | pipeline
let         := "let" identifier "=" expression "in" expression
conditional := "if" expression "then" expression "else" expression
match       := "match" expression "with" match_arm+
match_arm   := "|" match_pattern "->" expression
match_pattern := "Some" "(" identifier ")" | "None"
application := unary (("(" arguments? ")") | ("." identifier))*
pipeline    := application ("|>" application)*
arguments   := expression ("," expression)*
unary       := "-" unary | primary
primary     := integer | boolean | string | quantity | record | list | lambda | "Some" "(" expression ")" | "None" | identifier | "(" expression ")"
record      := identifier "{" record_fields? "}"
record_fields := record_field ("," record_field)*
record_field := identifier "=" expression
list        := "[" arguments? "]"
lambda      := "fn" identifier "->" expression | "fn" "(" identifiers? ")" "->" expression
identifiers := identifier ("," identifier)*
```

Parser output is immutable surface AST. Error recovery should support multiple diagnostics per compile without fabricating misleading trees.

### 15.3 Name resolution

Resolve local, module, type, constructor, and standard-library names. Detect:

- duplicate declarations;
- unknown names;
- shadowing according to policy;
- inaccessible exports;
- invalid constructor use.

The compiler assigns non-negative, typed `DefinitionId` values to top-level
definitions and `SymbolId` values to resolved lexical bindings. These are
value identifiers assigned by canonical traversal, never Python object
identities.

Milestone 2 resolves value names in source order: all top-level declarations
are visible to declaration bodies; parameters are then bound left to right;
and a `let` binding is visible only in its body. A name may not shadow any
active binding. On a duplicate declaration or parameter, the first valid
binder remains visible for recovery. Resolver diagnostics are
`E300_DUPLICATE_DEFINITION`, `E301_UNKNOWN_NAME`,
`E302_DUPLICATE_PARAMETER`, `E303_PROHIBITED_SHADOWING`, and
`E304_INVALID_ARITY`. The last applies only to directly named top-level calls;
the type checker diagnoses all other invalid calls.

### 15.4 Type checking

Check:

- function calls;
- branch compatibility;
- field access;
- variants and match exhaustiveness;
- list element types;
- quantity operations;
- entry-point signatures;
- memory shape;
- intent availability.

For the Milestone 2 subset, `Int`, `Bool`, and `Unit` annotations resolve to
the primitive type algebra. Milestone 4 additionally resolves `String`,
`Duration`, `Distance`, `Angle`, and `Probability`, and gives matching literals
their exact types. `let` values are inferred, direct application checks function
arity and argument types, negation requires `Int`, and `if` requires a `Bool`
condition with equal branch types. The checker emits `E400_UNKNOWN_TYPE`,
`E401_TYPE_MISMATCH`, `E402_BRANCH_TYPE_MISMATCH`, and `E403_INVALID_CALL`;
each diagnostic has a source span and uses the `checker` stage.

Record schema failures are `E404_DUPLICATE_RECORD_TYPE`,
`E405_DUPLICATE_RECORD_FIELD`, `E406_UNKNOWN_RECORD_TYPE`,
`E407_DUPLICATE_RECORD_VALUE`, `E408_UNKNOWN_RECORD_FIELD`,
`E409_MISSING_RECORD_FIELD`, and `E410_INVALID_FIELD_ACCESS`.

`Option` annotation arity is `E411_INVALID_OPTION_TYPE`; a payload-free `None`
without an expected `Option<T>` is `E412_AMBIGUOUS_NONE`. `Some` payloads and
all expected option values use `E401_TYPE_MISMATCH` when their types differ.
Option match failures are `E413_INVALID_MATCH_SUBJECT`,
`E414_DUPLICATE_MATCH_ARM`, `E415_INCOMPLETE_MATCH`, and
`E416_MATCH_BRANCH_TYPE`.
List annotation arity is `E417_INVALID_LIST_TYPE`; an uncontextual `[]` is
`E418_AMBIGUOUS_EMPTY_LIST`; differing element types are
`E419_LIST_ELEMENT_TYPE`; a literal over 1,024 items is `E420_LIST_ITEM_LIMIT`.
An anonymous function without an expected function type is
`E421_AMBIGUOUS_LAMBDA`; an arity mismatch is `E422_LAMBDA_ARITY`; more than
64 captures is `E423_CLOSURE_CAPTURE_LIMIT`.

List intrinsic diagnostics are `E424_INTRINSIC_CALL` for a non-direct intrinsic
reference, `E425_INTRINSIC_ARITY`, `E426_INTRINSIC_LIST`,
`E427_INTRINSIC_CALLBACK`, and `E428_INTRINSIC_ORDER_KEY`.

`E429_INVALID_DOMAIN_OPERATION` reports an unsupported or dimensionally invalid
binary operation at the operator span.

### 15.5 Capability checking

Each entry point has a capability environment. The compiler rejects impossible
intentions where static information suffices.

Milestone 4 exposes a separate immutable `CapabilityManifest` compiler artifact.
It has manifest version `1`, policy entry points in ascending `FunctionId`
order, and source-linked, lexically ordered capability requirements. Milestone
6 begins recording direct intention constructions; `wait`, `move_toward`, and
`take_cover` each require their matching capability. The simulation repeats this
check for decoded requests, including values returned through helpers, before
accepting an intention. This manifest is deliberately outside the raw
`KWI-BC\0` bytecode payload; later compiled-policy bundles carry it with their
tactical API version.

### 15.6 Cost analysis

Static analysis estimates obvious collection and call costs. Runtime budgets remain authoritative. The compiler should warn about clearly excessive operations over bounded input sizes.

### 15.7 Lowering

Lower surface conveniences into a minimal core with stable expression IDs and source maps.

Core retains integer, boolean, string, quantity, record construction, `Some`,
`None`, and list literals, source-ordered exhaustive `Option` matches, resolved
references, field access, negation, calls, `let`, and `if`.
Expression IDs start at zero and follow definition source order then expression
pre-order. Each ID has one `SourceMapEntry` containing its enclosing
`DefinitionId` and source span. Parentheses do not create core nodes because
they have no runtime semantics. The `format_lower_result` debug renderer is a
stable inspection format for core golden fixtures, not a bytecode format.

### 15.8 Bytecode generation

Compile to deterministic bytecode. Constant-pool and function ordering must be canonical.

For the initial core, definitions compile by ascending `DefinitionId`.
Parameters occupy local slots from zero in parameter order; each `let` receives
the next slot on its explicit pre-order visit. Core conditionals emit a
`JUMP_IF_FALSE` over their then branch and a `JUMP` over their else branch.
The compiler emits `TRACE_EXPRESSION` immediately before each core expression.
Every instruction, including generated control-flow and `RETURN` instructions,
has one ordered source-map entry containing its function ID, instruction index,
expression ID, and source span. Generated instructions use the enclosing core
expression; the final `RETURN` uses the definition body. Source-map spans must
belong to the module header's source file.

## 16. Bytecode model

Every bytecode module begins with immutable compatibility metadata: its source
file ID, source-language version, core-IR version, and bytecode version.
Milestone 4 emits the compatible version triple `(2, 2, 2)`. The decoder also
accepts the legacy `(1, 1, 1)` triple; a version 1 module cannot contain version
2 values or types and is never reinterpreted with version 2 semantics.

The constant pool interns integer, boolean, unit, string, and exact quantity
values. It uses first encounter during the compiler's explicit definition-order,
expression-pre-order traversal; repeated equal constants reuse their original
index. Functions are ordered by ascending `DefinitionId` and receive contiguous
`FunctionId` values from zero. Function references are never constants.

Candidate instructions:

```text
PUSH_CONSTANT constant_id
PUSH_FUNCTION function_id
LOAD_LOCAL slot
STORE_LOCAL slot
NEGATE
CALL argument_count
BUILD_RECORD type_name field_names
LOAD_FIELD field_name
BUILD_SOME
PUSH_NONE
JUMP_IF_NONE target
UNWRAP_SOME
POP
BUILD_LIST element_count
BUILD_CLOSURE function_id capture_count
PUSH_INTRINSIC intrinsic_kind
BINARY_OPERATION operator
JUMP target
JUMP_IF_FALSE target
RETURN
TRACE_EXPRESSION expr_id
```

`CALL` consumes a function value followed by source-ordered arguments and pushes
the result. `BUILD_RECORD` consumes its source-ordered field values and pushes
one canonically ordered immutable record; `LOAD_FIELD` replaces a record with
the named field. `BUILD_SOME` consumes a payload and pushes a new immutable
`Some` value; `PUSH_NONE` pushes a new payload-free immutable `Option` value.
`JUMP_IF_NONE` tests an `Option` without removing it; the Some arm uses
`UNWRAP_SOME` to replace it with the payload and the None arm uses `POP` to
discard it. `STORE_LOCAL` consumes its value; conditional branches consume a
boolean. The validator defines stack, local-slot, and in-range jump rules
before execution. The exact set should remain small. Instructions must not
contain Python callables or mutable arbitrary objects.

`BUILD_LIST` consumes source-ordered element values and pushes one immutable
list in that same order. It is rejected when the encoded count exceeds the
runtime list bound.

Anonymous functions compile to synthetic function-table entries after named
definitions in source-expression order. `BUILD_CLOSURE` consumes the stated
number of source-ordered captured values and pushes a closure targeting that
entry. A closure call prepends its captures to explicit call arguments.

`PUSH_INTRINSIC` pushes one closed standard-library identifier. It has no host
callable, import path, or dynamic lookup; `CALL` dispatches it only to the
documented bounded List operations.

`BINARY_OPERATION` consumes a left and right value and pushes the statically
checked exact domain result. Its closed one-byte operator tag is `+`, `-`, `<`,
`<=`, `>`, or `>=`; the VM still rejects incompatible corrupted runtime values.

The bytecode validator returns ordered structured errors instead of executing
corrupt modules. Version 1 uses `B001_FUNCTION_TABLE_MISMATCH` through
`B011_RETURN_STACK_HEIGHT` for structural, operand, and reachable
control-flow rejection.

### 16.1 Canonical byte encoding

`encode_bytecode` serialises validator-clean modules as bounded binary bytes;
`decode_bytecode` returns either a validated module or a structured `C001`
through `C010` decode failure without execution. Version 1 begins with the
seven-byte format identifier `KWI-BC\0`, then a one-byte encoding version
(`1`). Unsigned fields are four-byte big-endian integers. UTF-8 text is a
length-prefixed byte sequence. The header, constants, function table,
functions, instructions, and source-map entries follow in that order; each
collection has an explicit count. The header is source-file ID, source-language
version, core-IR version, and bytecode version. A function-table entry is
function ID, definition ID, name, and arity; a function additionally contains
local-slot count, return type, and ordered instructions.

Integer constants use a sign byte (`0` non-negative, `1` negative), a
four-byte magnitude length, and a minimal unsigned big-endian magnitude. Zero
has an empty, non-negative magnitude; leading zero magnitude bytes are
invalid. Constant, type, and instruction tags are fixed numeric tags. Source
map entries store function ID, instruction index, expression ID, start offset,
and end offset; their file ID is the header source file ID.

Version 1 constant tags are integer `1`, boolean `2`, and unit `3`; type tags
are `Int` `1`, `Bool` `2`, `Unit` `3`, named `4`, and function `5`. Version 2
adds string constant `4`, quantity constant `5`, and type tags `String` `6`,
`Duration` `7`, `Distance` `8`, `Angle` `9`, and `Probability` `10`. A quantity
is its dimension tag (`Duration` `1`, `Distance` `2`, `Angle` `3`,
`Probability` `4`), then a canonical signed numerator and positive minimal
unsigned denominator. Function types encode their parameter count, parameters,
then return type. Version 2 additionally defines instruction tag
`BUILD_RECORD` `11`, encoded as type-name text followed by an ordered count and
field-name texts, and `LOAD_FIELD` `12`, encoded as its field-name text.
`BINARY_OPERATION` `21` is encoded as its closed one-byte operator tag.
Instruction tags are the numeric `Opcode` values in section 16; operands are
their unsigned fields in instruction order. Instructions without an operand
have no following field.

The decoder accepts at most 16 MiB, 65,536 entries per collection, 65,536
UTF-8 bytes per text value, 512 integer-magnitude bytes, and 64 nested type
levels. It rejects unknown tags, non-canonical integers, invalid UTF-8,
truncation, trailing bytes, invalid module structure, and validator-rejected
bytecode. `pickle`, `marshal`, and Python object serialisation are not part of
this format.

The headless disassembler renders header versions, pool and table entries, then
function instructions in function-table and instruction-index order. It is a
stable inspection format, not the bytecode encoding.

## 17. Runtime values

Closed value algebra:

- integer;
- boolean;
- string;
- quantity;
- record;
- variant;
- list;
- function closure;
- tactical opaque identifier;
- intention.

Runtime values have deterministic equality, hashing where permitted, serialisation rules, and allocation costs.

Milestone 4 adds immutable bounded strings, exact quantities, immutable nominal
records, closed `Option` values, lists, and closures to the integer, boolean,
unit, and `FunctionId` reference value algebra. Record fields are stored by
lexical field name, never in a host dictionary. A named function value is only
an index into the module function table; a closure additionally stores at most
64 source-ordered closed runtime captures. Neither contains a Python callable
or code object. Lists store a tuple in source order and reject more than 1,024
values.

## 18. VM budgets

Per invocation budgets include:

- instruction count;
- call depth;
- stack size;
- allocated value units;
- list length;
- string size;
- trace nodes according to trace mode.

Milestone 3 enforces instruction, global value-stack, call-depth, and allocated
runtime-value limits. A pushed function or intrinsic reference, a negated
integer, record construction, `BUILD_SOME`, and `PUSH_NONE` each allocate one
value; immutable constants and frame slots do not. Exhaustion is checked before
the operation that would exceed its limit.

Option-match control instructions do not allocate values.

`BUILD_LIST` charges its element count plus one container allocation unit before
creating the immutable list.

`BUILD_CLOSURE` charges its capture count plus one container allocation unit
before creating the immutable closure.

`BINARY_OPERATION` charges one allocation unit for a quantity or boolean result
and three for a coordinate result (two quantities plus its record), before any
result is created.

Each List callback scheduling step charges one instruction unit in addition to
the callback's own bytecode. `min_by` charges one additional unit for each key
comparison after its first candidate; `sort_by` uses stable insertion order
and charges one unit for every key comparison (at most `n * (n - 1) / 2` for
`n` items). `map`, `filter`, and `sort_by` charge their output length plus one
container allocation unit; `find` and `min_by` charge one `Option` allocation
unit; `fold` adds no intrinsic result allocation. These checks occur before
the result is created and share the invocation's VM budgets with callbacks.

Budget exhaustion yields a structured fault and deterministic fallback policy.

## 19. Runtime faults

Examples:

- `R001_INVALID_BYTECODE`
- `R002_INSTRUCTION_BUDGET`
- `R003_ALLOCATION_BUDGET`
- `R004_STACK_BUDGET`
- `R005_INVALID_FIELD`
- `R006_INVALID_INTRINSIC_ARGUMENT`
- `R007_MEMORY_SHAPE`
- `R008_INTENTION_SHAPE`

The initial VM also reports `R009_CALL_DEPTH_BUDGET`, `R010_TYPE`,
`R011_CALL`, `R012_UNINITIALIZED_LOCAL`, and `R013_ENTRY`. A bytecode
validation failure returns `R001_INVALID_BYTECODE` before any instruction runs.
Every fault raised after execution begins carries its function ID, instruction
index, and immutable instruction source-map entry. Instruction-budget exhaustion
links to the next instruction that would run; other execution faults link to
the instruction being executed. Entry and pre-execution validation faults have
no instruction source entry.

Normal well-typed source should make most faults impossible. Faults remain necessary for corrupted bytecode, content mismatch, or implementation defects.

`R007_MEMORY_SHAPE` identifies a memory record with a wrong nominal type,
field set, or field value. `R008_INTENTION_SHAPE` identifies a non-`Decision`
result, a decision field-set mismatch, or a non-list `intentions` field. Both
return a deterministic field path where one is available.

## 20. Fallback behaviour

Each policy entry point has a deterministic fallback, such as:

```text
Decision {
  memory = previous_memory,
  intentions = [Wait(1 tick)]
}
```

The initial simulation boundary uses a narrower `hold` fallback: it preserves
the policy's input memory and emits no intentions for that evaluation tick.
It applies to VM and policy-result validation failures alike.

Fallback use is visible in mission UI and trace output. It must not silently continue as if the policy succeeded.

The VM accepts an explicit immutable fallback value at its caller boundary. A
fallback result retains the original structured VM fault so simulation and trace
layers can make the failure visible.

## 21. Source maps and instrumentation

Every core expression has a stable expression ID associated with:

- source module;
- source span;
- enclosing function;
- expression kind;
- optional semantic label.

VM trace hooks record:

- invocation ID;
- expression ID;
- selected value summary;
- observation provenance IDs;
- branch result;
- intention construction;
- cost.

Full values may be redacted or interned according to trace level.

## 22. Diagnostics

A diagnostic contains:

- stable code;
- severity;
- message;
- primary span;
- zero or more labelled secondary spans;
- notes;
- optional suggested edit;
- compiler stage.

Example:

```text
E204: this match does not handle `None`

  12 | match view.nearest_hostile with
     | ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

The value has type `Option<Contact>`.
Add a `| None -> ...` branch.
```

Diagnostics must be tested as structured data and optionally as golden rendered text.

## 23. Module and package model

MVP source may consist of one module per policy bundle. Later versions may support explicit imports from a curated project package. No arbitrary filesystem import traversal.

Module hashes include normalised source and language version. Bytecode bundles embed dependency hashes.

## 24. Versioning

Track separately:

- surface language version;
- core IR version;
- bytecode version;
- standard-library version;
- tactical API version.

A compiler may support several source versions while producing one current bytecode version. Replays record bytecode and API versions.

The implemented M4 language emits `(2, 2, 2)` for source, core, and bytecode.
There is currently no source-header syntax, so all accepted `.dtr` source uses
the current version `2`. The decoder preserves historical `(1, 1, 1)` bytecode
without reinterpretation; it is not an alternate source-language mode.

## 25. MVP acceptance criteria

The language MVP is complete when:

- a policy using `let`, `if`, a variant match, a list operation, a domain quantity, and an intention compiles;
- invalid code produces stable source diagnostics;
- the type checker rejects dimension errors and incomplete matches;
- bytecode is deterministic for identical source and compiler version;
- the VM executes without Python evaluation;
- budgets are enforced;
- output memory and intentions are validated;
- a trace links a decisive expression to an emitted intention;
- golden and property tests pass.

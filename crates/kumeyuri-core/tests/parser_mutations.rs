use kumeyuri_core::parser::Parser;

const CASES: &[MutationCase] = &[
    MutationCase {
        name: "flowchart",
        valid: "graph TD\nA --> B",
        invalid: "A[B[C]]",
    },
    MutationCase {
        name: "sequence",
        valid: "sequenceDiagram\nAlice->>Bob: hello",
        invalid: "Alice->>kumeyuri_mutation",
    },
    MutationCase {
        name: "state",
        valid: "stateDiagram-v2\n[*] --> Idle",
        invalid: "[*] --> kumeyuri_mutation -->",
    },
    MutationCase {
        name: "class",
        valid: "classDiagram\nclass Animal\nclass Dog\nAnimal <|-- Dog",
        invalid: "Animal <|--",
    },
    MutationCase {
        name: "er",
        valid: "erDiagram\nCUSTOMER ||--o{ ORDER : places",
        invalid: "CUSTOMER ||--|| : kumeyuri_mutation",
    },
    MutationCase {
        name: "gantt",
        valid: "gantt\ntitle Release Plan\nsection Build\nDesign API :done, api, 2026-01-01, 3d",
        invalid: "kumeyuri_mutation :",
    },
    MutationCase {
        name: "pie",
        valid: "pie title Pets\n\"Dogs\" : 386",
        invalid: "\"kumeyuri_mutation\" : nope",
    },
    MutationCase {
        name: "quadrant",
        valid: "quadrantChart\nx-axis Low --> High\ny-axis Risk --> Reward\nAPI: [0.25, 0.75]",
        invalid: "kumeyuri_mutation: [nope, 0.5]",
    },
    MutationCase {
        name: "zenuml",
        valid: "zenuml\nAlice->Bob: hello",
        invalid: "kumeyuri_mutation->",
    },
    MutationCase {
        name: "sankey",
        valid: "sankey-beta\nA,B,1",
        invalid: "kumeyuri_mutation,B,not-a-number",
    },
    MutationCase {
        name: "xychart",
        valid: "xychart-beta\nx-axis [Jan, Feb]\ny-axis 0 --> 100\nbar [42, 58]",
        invalid: "line [kumeyuri_mutation]",
    },
    MutationCase {
        name: "block",
        valid: "block\nA B\nA --> B",
        invalid: "kumeyuri_mutation -->",
    },
    MutationCase {
        name: "packet",
        valid: "packet\n+16: \"Source Port\"",
        invalid: "kumeyuri_mutation: \"bad\"",
    },
    MutationCase {
        name: "kanban",
        valid: "kanban\n  todo[Todo]\n    docs[Create Documentation]",
        invalid: "    kumeyuri_mutation@{ ticket: }",
    },
    MutationCase {
        name: "architecture",
        valid: "architecture-beta\nservice api(server)[API]\nservice db(database)[Database]\napi:R --> L:db",
        invalid: "api:X --> L:db",
    },
    MutationCase {
        name: "radar",
        valid: "radar-beta\naxis A, B, C\ncurve c1{1, 2, 3}",
        invalid: "curve kumeyuri_mutation{nope}",
    },
    MutationCase {
        name: "event_modeling",
        valid: "eventmodeling\ntf 01 ui CartUI\ntf 02 cmd AddItem",
        invalid: "tf kumeyuri_mutation",
    },
    MutationCase {
        name: "treemap",
        valid: "treemap-beta\n\"Sales\"\n  \"Product A\": 40",
        invalid: "\"kumeyuri_mutation\": nope",
    },
    MutationCase {
        name: "venn",
        valid: "venn-beta\nset A[\"Alpha\"]:20\nset B[\"Beta\"]:12\nunion A,B[\"AB\"]:3",
        invalid: "set kumeyuri_mutation[\"Bad\"]: nope",
    },
    MutationCase {
        name: "ishikawa",
        valid: "ishikawa-beta\nBlurry Photo\n  Process\n    Out of focus",
        invalid: "%%{ kumeyuri_mutation",
    },
    MutationCase {
        name: "wardley",
        valid: "wardley-beta\nanchor User [0.95,0.1]\ncomponent Website [0.8,0.35]\nUser -> Website",
        invalid: "component kumeyuri_mutation",
    },
    MutationCase {
        name: "tree_view",
        valid: "treeView-beta\nmy-project/\n  src/\n    index.js",
        invalid: "%%{ kumeyuri_mutation",
    },
    MutationCase {
        name: "mindmap",
        valid: "mindmap\n  Root\n    Branch",
        invalid: "    %%{ kumeyuri_mutation",
    },
    MutationCase {
        name: "journey",
        valid: "journey\nsection Work\nMake tea: 5: Me",
        invalid: "kumeyuri_mutation: nope: Me",
    },
    MutationCase {
        name: "gitgraph",
        valid: "gitGraph:\ncommit id: \"base\"",
        invalid: "commit type: kumeyuri_mutation",
    },
    MutationCase {
        name: "timeline",
        valid: "timeline\nsection Alpha\n2024 Q1 : Design",
        invalid: "kumeyuri_mutation :",
    },
    MutationCase {
        name: "requirement",
        valid: "requirementDiagram\nrequirement req1 {\nid: 1\ntext: pass\nrisk: low\nverifymethod: test\n}",
        invalid: "requirement kumeyuri_mutation {\ntext: fail\nrisk: impossible\nverifymethod: test\n}",
    },
    MutationCase {
        name: "c4",
        valid: "C4Context\nPerson(customer, \"Customer\")\nSystem(system, \"System\")\nRel(customer, system, \"Uses\")",
        invalid: "Rel(customer, )",
    },
];

#[derive(Debug)]
struct MutationCase {
    name: &'static str,
    valid: &'static str,
    invalid: &'static str,
}

#[test]
fn supported_root_parser_mutations_fail_fast() {
    for case in CASES {
        Parser::parse_diagram(case.valid)
            .unwrap_or_else(|error| panic!("valid seed failed for {}: {:?}", case.name, error));
        let source = format!("{}\n{}", case.valid.trim_end(), case.invalid);
        let mutation_start = case.valid.trim_end().len() + 1;
        let error = match Parser::parse_diagram(&source) {
            Ok(_) => panic!("mutated source parsed for {}", case.name),
            Err(error) => error,
        };

        assert!(
            error.span.start >= mutation_start && error.span.end <= source.len(),
            "{} error span {}..{} did not point at mutation starting at {}\n{}",
            case.name,
            error.span.start,
            error.span.end,
            mutation_start,
            source,
        );
    }
}

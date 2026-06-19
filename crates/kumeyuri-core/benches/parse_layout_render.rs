use criterion::{Criterion, criterion_group, criterion_main};
use kumeyuri_core::ast::DiagramKind;
use kumeyuri_core::frame::StaticFrameRenderer;
use kumeyuri_core::layout::FlowLayoutEngine;
use kumeyuri_core::parser::Parser;
use std::hint::black_box;

const FLOWCHART: &str = r#"graph TD
    Cart[Cart] --> Auth{Signed in?}
    Auth -->|Yes| Address[Address]
    Auth -->|No| Login[Login]
    Login --> Address
    Address --> Payment[Payment]
    Payment --> Review[Review order]
    Review --> Confirm[Confirmation]
"#;

const SEQUENCE: &str = r#"sequenceDiagram
    autonumber
    participant Browser
    participant API
    participant Worker
    Browser->>API: submit order
    API->>Worker: enqueue fulfillment
    Worker-->>API: accepted
    API-->>Browser: confirmation
"#;

const STATE: &str = r#"stateDiagram-v2
    [*] --> Idle
    Idle --> Loading: submit
    Loading --> Success: ok
    Loading --> Error: fail
    Error --> Loading: retry
    Success --> [*]
"#;

fn bench_parse(c: &mut Criterion) {
    let mut group = c.benchmark_group("parse");

    group.bench_function("flowchart", |b| {
        b.iter(|| Parser::parse_diagram(black_box(FLOWCHART)).expect("flowchart parses"));
    });
    group.bench_function("sequence", |b| {
        b.iter(|| Parser::parse_diagram(black_box(SEQUENCE)).expect("sequence parses"));
    });
    group.bench_function("state", |b| {
        b.iter(|| Parser::parse_diagram(black_box(STATE)).expect("state parses"));
    });

    group.finish();
}

fn bench_layout(c: &mut Criterion) {
    let diagram = Parser::parse_diagram(FLOWCHART).expect("flowchart parses");
    let DiagramKind::Flowchart(flowchart) = &diagram.kind else {
        panic!("expected flowchart");
    };
    let engine = FlowLayoutEngine::default();

    c.bench_function("layout/flowchart", |b| {
        b.iter(|| engine.layout(black_box(flowchart)));
    });
}

fn bench_render(c: &mut Criterion) {
    let flowchart = Parser::parse_diagram(FLOWCHART).expect("flowchart parses");
    let sequence = Parser::parse_diagram(SEQUENCE).expect("sequence parses");
    let state = Parser::parse_diagram(STATE).expect("state parses");
    let renderer = StaticFrameRenderer::default();
    let mut group = c.benchmark_group("render");

    group.bench_function("flowchart", |b| {
        b.iter(|| renderer.render_diagram(black_box(&flowchart)));
    });
    group.bench_function("sequence", |b| {
        b.iter(|| renderer.render_diagram(black_box(&sequence)));
    });
    group.bench_function("state", |b| {
        b.iter(|| renderer.render_diagram(black_box(&state)));
    });

    group.finish();
}

criterion_group!(benches, bench_parse, bench_layout, bench_render);
criterion_main!(benches);

use criterion::{Criterion, criterion_group, criterion_main};
use kumeyuri_core::{ast::DiagramKind, layout::FlowLayoutEngine, parser::Parser};
use layout::{
    backends::svg::SVGWriter,
    core::{base::Orientation, geometry::Point, style::*},
    std_shapes::shapes::*,
    topo::layout::VisualGraph,
};
use std::hint::black_box;

fn bench_layout_engines(c: &mut Criterion) {
    let source = generated_flowchart_source();
    let diagram = Parser::parse_diagram(&source).expect("generated flowchart parses");
    let DiagramKind::Flowchart(flowchart) = &diagram.kind else {
        panic!("expected flowchart");
    };
    let edges = generated_edges();
    let engine = FlowLayoutEngine::default();
    let mut group = c.benchmark_group("layout-engine/100-node-flowchart");

    group.bench_function("kumeyuri-sugiyama", |b| {
        b.iter(|| engine.layout(black_box(flowchart)));
    });
    group.bench_function("layout-rs", |b| {
        b.iter(|| render_layout_rs_graph(black_box(&edges)));
    });

    group.finish();
}

fn generated_flowchart_source() -> String {
    let mut source = String::from("graph TD\n");
    for (from, to) in generated_edges() {
        source.push_str(&format!("N{from} --> N{to}\n"));
    }
    source
}

fn generated_edges() -> Vec<(usize, usize)> {
    let mut edges = Vec::new();
    for node in 0..100 {
        let left = (node * 2) + 1;
        let right = left + 1;
        if left < 100 {
            edges.push((node, left));
        }
        if right < 100 {
            edges.push((node, right));
        }
    }
    edges
}

fn render_layout_rs_graph(edges: &[(usize, usize)]) -> String {
    let mut graph = VisualGraph::new(Orientation::TopToBottom);
    let handles = (0..100)
        .map(|node| {
            let shape = ShapeKind::new_box(&format!("N{node}"));
            let style = StyleAttr::simple();
            graph.add_node(Element::create(
                shape,
                style,
                Orientation::TopToBottom,
                Point::new(64.0, 32.0),
            ))
        })
        .collect::<Vec<_>>();
    for (from, to) in edges {
        graph.add_edge(Arrow::simple(""), handles[*from], handles[*to]);
    }

    let mut svg = SVGWriter::new();
    graph.do_it(false, false, false, &mut svg);
    svg.finalize()
}

criterion_group!(benches, bench_layout_engines);
criterion_main!(benches);

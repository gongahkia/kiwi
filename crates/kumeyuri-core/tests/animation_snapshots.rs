use std::{fmt::Write as _, fs, path::Path};

use kumeyuri_core::{
    animator::{Animator, Timeline},
    ast::{Diagram, DiagramKind},
    frame::{Frame, KeyFrameMarkerKind},
    parser::Parser,
};

const FLOWCHART_NAMES: [&str; 20] = [
    "01_single_node",
    "02_two_nodes_linked",
    "03_three_node_chain",
    "04_fan_out",
    "05_fan_in",
    "06_left_right_chain",
    "07_bottom_top_chain",
    "08_right_left_chain",
    "09_labelled_edge",
    "10_pipe_label",
    "11_dotted_edge",
    "12_thick_edge",
    "13_bidirectional_edge",
    "14_mixed_shapes",
    "15_round_and_stadium",
    "16_subgraph_simple",
    "17_nested_subgraph",
    "18_class_styles",
    "19_directive_comment",
    "20_disconnected_roots",
];

const SEQUENCE_NAMES: [&str; 15] = [
    "01_single_message",
    "02_declared_participants",
    "03_multiple_messages",
    "04_self_message",
    "05_note_over",
    "06_note_left",
    "07_note_right",
    "08_loop_block",
    "09_alt_block",
    "10_opt_block",
    "11_par_block",
    "12_dotted_line",
    "13_cross_and_open",
    "14_bidirectional",
    "15_three_participants",
];

const STATE_NAMES: [&str; 10] = [
    "01_start_to_idle",
    "02_left_right_direction",
    "03_three_state_chain",
    "04_transition_labels",
    "05_state_alias",
    "06_choice_state",
    "07_fork_state",
    "08_directive_comment",
    "09_state_declarations",
    "10_composite_opening",
];

const CLASS_NAMES: [&str; 4] = [
    "01_basic_class",
    "02_inheritance_members",
    "03_relationship_kinds",
    "04_direction_lr",
];

const ER_NAMES: [&str; 3] = [
    "01_basic_relationship",
    "02_attributes",
    "03_non_identifying",
];

const GANTT_NAMES: [&str; 3] = [
    "01_basic_schedule",
    "02_sections_until",
    "03_config_comments",
];

const PIE_NAMES: [&str; 3] = ["01_basic", "02_show_data", "03_comments_directive"];

const MINDMAP_NAMES: [&str; 3] = ["01_basic_tree", "02_shapes_icons", "03_directive_comment"];

const JOURNEY_NAMES: [&str; 3] = ["01_basic", "02_sections_actors", "03_directive_comment"];

#[test]
fn animation_timeline_hashes_match() {
    assert_timeline_hashes("flowchart", &FLOWCHART_NAMES);
    assert_timeline_hashes("sequence", &SEQUENCE_NAMES);
    assert_timeline_hashes("state", &STATE_NAMES);
    assert_timeline_hashes("class", &CLASS_NAMES);
    assert_timeline_hashes("er", &ER_NAMES);
    assert_timeline_hashes("gantt", &GANTT_NAMES);
    assert_timeline_hashes("pie", &PIE_NAMES);
    assert_timeline_hashes("mindmap", &MINDMAP_NAMES);
    assert_timeline_hashes("journey", &JOURNEY_NAMES);
}

fn assert_timeline_hashes(kind: &str, names: &[&str]) {
    let root = Path::new(env!("CARGO_MANIFEST_DIR")).join("../..");
    let actual = timeline_hashes(&root, kind, names);
    let expected_path = root
        .join("tests/golden/kumeyuri-animation")
        .join(format!("{kind}.txt"));
    let expected = fs::read_to_string(&expected_path).unwrap_or_else(|error| {
        panic!(
            "failed to read {}: {error}\nexpected contents:\n{actual}",
            expected_path.display(),
        )
    });

    assert_eq!(actual, expected, "animation snapshot mismatch for {kind}");
}

fn timeline_hashes(root: &Path, kind: &str, names: &[&str]) -> String {
    let mut output = String::new();
    for name in names {
        let source_path = root
            .join("tests/snapshots")
            .join(kind)
            .join("input")
            .join(format!("{name}.mmd"));
        let source = read_source(&source_path);
        let diagram = parse_diagram(&source_path, &source);
        let timeline = Animator::animate_diagram(&diagram).unwrap_or_else(|error| {
            panic!("failed to animate {}: {error:?}", source_path.display())
        });
        let hash = timeline_hash(&diagram, &timeline);
        writeln!(&mut output, "{name} {hash:016x}").expect("failed to write hash line");
    }
    output
}

fn read_source(path: &Path) -> String {
    fs::read_to_string(path)
        .unwrap_or_else(|error| panic!("failed to read {}: {error}", path.display()))
}

fn parse_diagram(path: &Path, source: &str) -> Diagram {
    Parser::parse_diagram(source).unwrap_or_else(|error| {
        panic!(
            "failed to parse {}: {:?} at {}..{}",
            path.display(),
            error.kind,
            error.span.start,
            error.span.end,
        )
    })
}

fn timeline_hash(diagram: &Diagram, timeline: &Timeline) -> u64 {
    fnv1a64(timeline_fingerprint(diagram, timeline).as_bytes())
}

fn timeline_fingerprint(diagram: &Diagram, timeline: &Timeline) -> String {
    let (kind, mode) = animation_identity(diagram);
    let mut output = String::new();
    writeln!(&mut output, "kind:{kind}").expect("failed to write kind");
    writeln!(&mut output, "mode:{mode}").expect("failed to write mode");
    writeln!(&mut output, "keyframes:{}", timeline.len()).expect("failed to write count");
    for (index, keyframe) in timeline.keyframes().iter().enumerate() {
        writeln!(
            &mut output,
            "frame:{index}:duration_ms:{}",
            keyframe.duration().as_millis()
        )
        .expect("failed to write duration");
        append_frame(&mut output, keyframe.frame());
    }
    output
}

fn animation_identity(diagram: &Diagram) -> (&'static str, &'static str) {
    match diagram.kind {
        DiagramKind::Flowchart(_) => ("flowchart", "trace"),
        DiagramKind::Sequence(_) => ("sequence", "playback"),
        DiagramKind::State(_) => ("state", "transitions"),
        DiagramKind::Class(_) => ("class", "trace"),
        DiagramKind::Er(_) => ("er", "trace"),
        DiagramKind::Gantt(_) => ("gantt", "trace"),
        DiagramKind::Pie(_) => ("pie", "trace"),
        DiagramKind::Mindmap(_) => ("mindmap", "trace"),
        DiagramKind::Journey(_) => ("journey", "trace"),
    }
}

fn append_frame(output: &mut String, frame: &Frame) {
    writeln!(output, "size:{}x{}", frame.width(), frame.height()).expect("failed to write size");
    for line in frame.to_lines() {
        writeln!(output, "glyphs:{}:{line}", line.len()).expect("failed to write glyphs");
    }
    writeln!(output, "markers:{}", frame.markers().len()).expect("failed to write marker count");
    for marker in frame.markers() {
        writeln!(
            output,
            "marker:{}:{}:{}:{}:{}:{}",
            marker.id,
            marker_kind(marker.kind),
            marker.region.x,
            marker.region.y,
            marker.region.width,
            marker.region.height,
        )
        .expect("failed to write marker");
    }
}

fn marker_kind(kind: KeyFrameMarkerKind) -> &'static str {
    match kind {
        KeyFrameMarkerKind::Enter => "enter",
        KeyFrameMarkerKind::Active => "active",
        KeyFrameMarkerKind::Exit => "exit",
        KeyFrameMarkerKind::Hold => "hold",
    }
}

fn fnv1a64(bytes: &[u8]) -> u64 {
    let mut hash = 0xcbf29ce484222325u64;
    for byte in bytes {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    hash
}

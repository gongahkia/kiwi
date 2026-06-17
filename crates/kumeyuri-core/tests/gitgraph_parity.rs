use kumeyuri_core::{
    ast::{DiagramKind, GitGraphAst, GitGraphCommitKind, GitGraphOrientation, GitGraphStatement},
    layout::GitGraphLayoutEngine,
    parser::Parser,
};

const BRANCH_ORDER_ALIASES: &str =
    include_str!("../../../tests/fuzz/gitgraph-parity/branch_order_aliases.mmd");
const MERGE_CHERRY_OPTIONS: &str =
    include_str!("../../../tests/fuzz/gitgraph-parity/merge_cherry_options.mmd");
const ORIENTATION_THEME_CONFIG: &str =
    include_str!("../../../tests/fuzz/gitgraph-parity/orientation_theme_config.mmd");

#[test]
fn gitgraph_branch_order_and_checkout_switch_aliases_are_preserved() {
    let ast = parse_gitgraph(BRANCH_ORDER_ALIASES);
    let checkout_targets = ast
        .statements
        .iter()
        .filter_map(|statement| match statement {
            GitGraphStatement::Checkout(target) => Some(target.value.as_str()),
            _ => None,
        })
        .collect::<Vec<_>>();
    let layout = GitGraphLayoutEngine::default().layout(&ast);
    let main = branch_lane(&layout, "main");
    let beta = branch_lane(&layout, "beta");
    let alpha = branch_lane(&layout, "alpha");

    assert_eq!(checkout_targets, ["main", "alpha"]);
    assert!(main < beta);
    assert!(beta < alpha);
}

#[test]
fn gitgraph_merge_cherry_pick_commit_tags_and_types_parse() {
    let ast = parse_gitgraph(MERGE_CHERRY_OPTIONS);

    assert_eq!(ast.commits[0].id.as_ref().unwrap().value, "A");
    assert_eq!(ast.commits[0].tag.as_ref().unwrap().value, "v0");
    assert_eq!(ast.commits[0].kind.value, GitGraphCommitKind::Normal);
    assert_eq!(ast.commits[1].kind.value, GitGraphCommitKind::Highlight);
    assert_eq!(ast.commits[1].tag.as_ref().unwrap().value, "feat");
    assert_eq!(ast.merges[0].id.as_ref().unwrap().value, "M");
    assert_eq!(ast.merges[0].tag.as_ref().unwrap().value, "merged");
    assert_eq!(ast.merges[0].kind.value, GitGraphCommitKind::Reverse);
    assert_eq!(ast.cherry_picks[0].id.value, "B");
    assert_eq!(ast.cherry_picks[0].parent.as_ref().unwrap().value, "A");
}

#[test]
fn gitgraph_orientation_and_theme_config_fixture_is_accepted() {
    let diagram = Parser::parse_diagram(ORIENTATION_THEME_CONFIG).unwrap();
    let DiagramKind::GitGraph(ast) = &diagram.kind else {
        panic!("expected gitgraph");
    };

    assert_eq!(diagram.directives.len(), 1);
    assert_eq!(ast.header.orientation.value, GitGraphOrientation::BottomTop);
    assert_eq!(ast.merges[0].kind.value, GitGraphCommitKind::Highlight);
}

fn parse_gitgraph(source: &str) -> Box<GitGraphAst> {
    let diagram = Parser::parse_diagram(source).unwrap();
    let DiagramKind::GitGraph(ast) = diagram.kind else {
        panic!("expected gitgraph");
    };
    ast
}

fn branch_lane(layout: &kumeyuri_core::layout::GitGraphLayout, name: &str) -> usize {
    layout
        .branches
        .iter()
        .find(|branch| branch.name == name)
        .unwrap()
        .lane
}

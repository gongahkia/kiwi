(function () {
  const playgroundUrl = "https://kumeyuri.dev/";
  const roots = [
    "graph",
    "flowchart",
    "sequenceDiagram",
    "stateDiagram",
    "stateDiagram-v2",
    "classDiagram",
    "erDiagram",
    "journey",
    "gantt",
    "pie",
    "quadrantChart",
    "requirementDiagram",
    "gitGraph",
    "C4Context",
    "C4Container",
    "C4Component",
    "C4Dynamic",
    "C4Deployment",
    "mindmap",
    "timeline",
    "zenuml",
    "sankey",
    "sankey-beta",
    "xychart",
    "xychart-beta",
    "block",
    "packet",
    "packet-beta",
    "kanban",
    "architecture-beta",
    "radar-beta",
    "eventmodeling",
    "treemap-beta",
    "venn-beta",
    "ishikawa-beta",
    "wardley-beta",
    "treeView-beta",
  ];

  document.addEventListener("DOMContentLoaded", () => {
    for (const code of document.querySelectorAll("pre > code")) {
      const pre = code.parentElement;
      if (!pre || pre.dataset.kumeyuriCta === "true") {
        continue;
      }
      pre.dataset.kumeyuriCta = "true";
      pre.insertAdjacentElement("afterend", buildCta(code.textContent || ""));
    }
  });

  function buildCta(source) {
    const wrapper = document.createElement("div");
    const link = document.createElement("a");
    wrapper.className = "kumeyuri-code-cta";
    link.href = buildHref(source);
    link.textContent = "Try in playground";
    link.rel = "noopener";
    wrapper.append(link);
    return wrapper;
  }

  function buildHref(source) {
    const clean = source.trim();
    const url = new URL(playgroundUrl);
    if (looksLikeMermaid(clean)) {
      url.searchParams.set("source", clean);
    }
    url.hash = "playground";
    return url.href;
  }

  function looksLikeMermaid(source) {
    const body = source
      .replace(/^%%\{[\s\S]*?\}%%\s*/u, "")
      .replace(/^(?:%%.*\n|\s)+/u, "")
      .trimStart();
    return roots.some((root) => body.startsWith(root));
  }
})();

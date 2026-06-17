import { tool, type Plugin } from "@opencode-ai/plugin"
import { renderMarkdown } from "../scripts/render-mermaid-blocks.mjs"

export const KumeyuriRenderPlugin: Plugin = async () => {
  return {
    tool: {
      kumeyuri_render: tool({
        description:
          "Render Mermaid source or Markdown Mermaid fences inline with kumeyuri. Returns Markdown with rendered text or SVG output.",
        args: {
          source: tool.schema.string().describe("Raw Mermaid source or Markdown containing Mermaid fenced code blocks."),
          format: tool.schema.enum(["text", "svg"]).optional().describe("Render format. Defaults to text."),
          replace: tool.schema.boolean().optional().describe("Replace Mermaid fences instead of appending rendered output."),
          kumeyuri: tool.schema.string().optional().describe("Optional path to the kumeyuri binary."),
        },
        async execute(args) {
          return renderMarkdown(normalizeSource(args.source), {
            format: args.format ?? "text",
            replace: args.replace === true,
            kumeyuri: args.kumeyuri || process.env.KUMEYURI_BIN || "kumeyuri",
          })
        },
      }),
    },
  }
}

export default KumeyuriRenderPlugin

function normalizeSource(source: string): string {
  if (/```\s*(mermaid|mmd)\b/i.test(source)) {
    return source
  }
  return `\`\`\`mermaid\n${source.trimEnd()}\n\`\`\`\n`
}

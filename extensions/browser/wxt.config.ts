import { defineConfig } from "wxt";

export default defineConfig({
  manifest: {
    action: {
      default_title: "wat"
    },
    description: "Look up tech acronyms and team jargon from the browser.",
    name: "wat",
    permissions: ["activeTab", "storage", "contextMenus", "scripting", "sidePanel"]
  }
});

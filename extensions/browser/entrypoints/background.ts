import { defineBackground } from "wxt/utils/define-background";

import { isLookupMessage, sidePanelQueryStorageKey, type SidePanelQuery } from "../src/messages.js";
import { handleLookup } from "../src/lookup-service.js";
import { defaultOptions, optionsStorageKey } from "../src/options.js";

type BrowserTab = Awaited<ReturnType<typeof browser.tabs.query>>[number];
interface ContextMenuClickInfo {
  menuItemId: number | string;
  selectionText?: string;
}

const contextMenuId = "wat.lookup.selection";

function tabContext(tab: BrowserTab): string {
  if (!tab.url) return "";
  try {
    const url = new URL(tab.url);
    return url.hostname || tab.url;
  } catch {
    return tab.url;
  }
}

function openSidePanel(tab: BrowserTab) {
  if (tab.id == null || !browser.sidePanel) return;
  void browser.sidePanel.open({ tabId: tab.id });
}

function ensureContextMenu() {
  void browser.contextMenus.removeAll().then(() => {
    browser.contextMenus.create({
      contexts: ["selection"],
      id: contextMenuId,
      title: 'Look up "%s" in wat'
    });
  });
}

async function queueSidePanelLookup(tab: BrowserTab, term: string) {
  const query: SidePanelQuery = {
    context: tabContext(tab),
    createdAt: new Date().toISOString(),
    term: term.trim()
  };

  await browser.storage.local.set({ [sidePanelQueryStorageKey]: query });
  openSidePanel(tab);
}

export default defineBackground(() => {
  ensureContextMenu();

  browser.runtime.onInstalled.addListener(() => {
    void browser.storage.local.get(optionsStorageKey).then((stored: Record<string, unknown>) => {
      if (!stored[optionsStorageKey]) {
        void browser.storage.local.set({ [optionsStorageKey]: defaultOptions });
      }
    });
    void browser.storage.local.set({ watInstalledAt: new Date().toISOString() });
  });

  browser.runtime.onMessage.addListener((message: unknown) => {
    if (!isLookupMessage(message)) return undefined;
    return handleLookup(message);
  });

  browser.contextMenus.onClicked.addListener((info: ContextMenuClickInfo, tab?: BrowserTab) => {
    if (info.menuItemId !== contextMenuId || !info.selectionText?.trim() || !tab) return;
    void queueSidePanelLookup(tab, info.selectionText);
  });

  browser.action.onClicked.addListener((tab: BrowserTab) => {
    openSidePanel(tab);
  });
});

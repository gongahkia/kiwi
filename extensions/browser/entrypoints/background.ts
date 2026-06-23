import { defineBackground } from "wxt/utils/define-background";

import {
  isLookupMessage,
  isOptionsMessage,
  isSaveCustomEntryMessage,
  sidePanelCustomEntryStorageKey,
  sidePanelQueryStorageKey,
  type SidePanelCustomEntryDraft,
  type SidePanelQuery
} from "../src/messages.js";
import { handleLookup } from "../src/lookup-service.js";
import { handleSaveCustomEntry } from "../src/save-entry-service.js";
import { defaultOptions, loadWatOptions, optionsStorageKey } from "../src/options.js";

type BrowserTab = Awaited<ReturnType<typeof browser.tabs.query>>[number];
interface ContextMenuClickInfo {
  menuItemId: number | string;
  selectionText?: string;
}

const lookupContextMenuId = "wat.lookup.selection";
const saveContextMenuId = "wat.save.selection";

function tabContext(tab: BrowserTab): string {
  if (!tab.url) return "";
  try {
    const url = new URL(tab.url);
    return url.hostname || tab.url;
  } catch {
    return tab.url;
  }
}

function tabSourceUrl(tab: BrowserTab): string | undefined {
  if (!tab.url || tab.url.startsWith("chrome://") || tab.url.startsWith("chrome-extension://")) {
    return undefined;
  }

  return tab.url;
}

function openSidePanel(tab: BrowserTab) {
  if (tab.id == null || !browser.sidePanel) return;
  void browser.sidePanel.open({ tabId: tab.id });
}

function ensureContextMenu() {
  void browser.contextMenus.removeAll().then(() => {
    browser.contextMenus.create({
      contexts: ["selection"],
      id: lookupContextMenuId,
      title: 'Look up "%s" in wat'
    });
    browser.contextMenus.create({
      contexts: ["selection"],
      id: saveContextMenuId,
      title: 'Save "%s" as custom acronym'
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

async function queueCustomEntryDraft(tab: BrowserTab, term: string) {
  const draft: SidePanelCustomEntryDraft = {
    context: tabContext(tab),
    createdAt: new Date().toISOString(),
    sourceTitle: tab.title,
    sourceUrl: tabSourceUrl(tab),
    term: term.trim()
  };

  await browser.storage.local.set({ [sidePanelCustomEntryStorageKey]: draft });
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
    if (isOptionsMessage(message)) return loadWatOptions();
    if (isLookupMessage(message)) return handleLookup(message);
    if (isSaveCustomEntryMessage(message)) return handleSaveCustomEntry(message);
    return undefined;
  });

  browser.contextMenus.onClicked.addListener((info: ContextMenuClickInfo, tab?: BrowserTab) => {
    if (!info.selectionText?.trim() || !tab) return;
    if (info.menuItemId === lookupContextMenuId) {
      void queueSidePanelLookup(tab, info.selectionText);
    }
    if (info.menuItemId === saveContextMenuId) {
      void queueCustomEntryDraft(tab, info.selectionText);
    }
  });

  browser.action.onClicked.addListener((tab: BrowserTab) => {
    openSidePanel(tab);
  });
});

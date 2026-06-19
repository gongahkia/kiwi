import { defineBackground } from "wxt/utils/define-background";

export default defineBackground(() => {
  browser.runtime.onInstalled.addListener(() => {
    void browser.storage.local.set({ watInstalledAt: new Date().toISOString() });
  });
});

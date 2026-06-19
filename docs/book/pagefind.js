(function () {
  const searchbar = document.getElementById("mdbook-searchbar");
  if (!searchbar) {
    return;
  }

  const mount = document.createElement("div");
  mount.id = "pagefind-search";
  mount.setAttribute("role", "search");
  mount.hidden = true;
  searchbar.insertAdjacentElement("afterend", mount);

  const link = document.createElement("link");
  link.rel = "stylesheet";
  link.href = new URL("pagefind/pagefind-ui.css", document.baseURI).href;
  document.head.append(link);

  const script = document.createElement("script");
  script.src = new URL("pagefind/pagefind-ui.js", document.baseURI).href;
  script.onload = function () {
    if (typeof window.PagefindUI !== "function") {
      return;
    }
    mount.hidden = false;
    searchbar.hidden = true;
    new window.PagefindUI({
      element: "#pagefind-search",
      showSubResults: true,
      resetStyles: false,
    });
  };
  document.head.append(script);
})();

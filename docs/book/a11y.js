(function () {
  function patchSearch() {
    const input = document.getElementById("mdbook-searchbar");
    if (input && !input.hasAttribute("aria-label")) {
      input.setAttribute("aria-label", "Search this book");
    }

    const form = document.getElementById("mdbook-searchbar-outer");
    if (!form || form.querySelector("button[type='submit']")) {
      return;
    }

    const submit = document.createElement("button");
    submit.type = "submit";
    submit.textContent = "Search";
    submit.style.cssText =
      "position:absolute;width:1px;height:1px;padding:0;margin:-1px;overflow:hidden;clip:rect(0 0 0 0);white-space:nowrap;border:0;";
    form.append(submit);
    form.addEventListener("submit", function (event) {
      event.preventDefault();
      input?.focus();
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", patchSearch, { once: true });
  } else {
    patchSearch();
  }
})();

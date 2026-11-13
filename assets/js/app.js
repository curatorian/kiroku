// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html";
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix";
import { hooks as colocatedHooks } from "phoenix-colocated/kiroku";
import { LiveSocket } from "phoenix_live_view";
import topbar from "../vendor/topbar";

const csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");

// ── PDF reader (modal) ───────────────────────────────────────────────────────
// Fetches the bitstream bytes (same-origin; the server enforces access
// control) and renders them in an <embed> via a blob URL, so the direct file
// URL is never rendered as a link or opened in a new tab. The blob URL is
// revoked when the modal closes.
const PdfReader = {
  mounted() {
    this.load();
  },
  updated() {
    if (this.el.dataset.bitstreamId !== this.loadedId) {
      this.load();
    }
  },
  destroyed() {
    this.revoke();
  },
  load() {
    this.loadedId = this.el.dataset.bitstreamId;
    this.revoke();
    // The bitstream route is keyed on the item's ID (not its handle).
    // NOTE: no Accept header — the :browser pipeline only accepts html, and
    // a custom Accept would make the accepts plug answer 406.
    // ?reader=1 → the controller relays the bytes through the app. Required
    // for :s3/:url files whose direct serving redirects cross-origin — a
    // same-origin fetch cannot follow those redirects (CORS).
    const { itemId, bitstreamId } = this.el.dataset;

    fetch(`/items/${itemId}/bitstreams/${bitstreamId}?reader=1`)
      .then((res) => {
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        return res.blob();
      })
      .then((blob) => {
        if (!this.el.isConnected) return; // modal was closed mid-fetch
        this.objectUrl = URL.createObjectURL(blob);
        const frame = document.createElement("embed");
        frame.src = this.objectUrl;
        frame.type = "application/pdf";
        frame.setAttribute("class", "w-full h-full");
        this.el.replaceChildren(frame);
      })
      .catch(() => {
        if (this.el.isConnected) {
          this.el.innerHTML =
            "<p class='p-6 text-sm text-center' style='color: var(--color-quill);'>Gagal memuat dokumen.</p>";
        }
      });
  },
  revoke() {
    if (this.objectUrl) {
      URL.revokeObjectURL(this.objectUrl);
      this.objectUrl = null;
    }
  },
};

const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: { _csrf_token: csrfToken },
  hooks: { PdfReader, ...colocatedHooks },
});

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" });
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

// ── Theme toggle ─────────────────────────────────────────────────────────────
// Supported daisyUI theme names defined in app.css
const THEMES = { light: "kiroku-light", dark: "kiroku-dark" };
const systemTheme = () =>
  window.matchMedia("(prefers-color-scheme: dark)").matches
    ? THEMES.dark
    : THEMES.light;

function applyTheme(pref) {
  const html = document.documentElement;
  const theme =
    pref === "system" || !THEMES[pref] ? systemTheme() : THEMES[pref];
  html.setAttribute("data-theme", theme);
  if (pref && pref !== "system") {
    html.setAttribute("data-theme-pref", pref);
    localStorage.setItem("theme-pref", pref);
  } else {
    html.removeAttribute("data-theme-pref");
    localStorage.removeItem("theme-pref");
  }
}

// Handle clicks from <.theme_toggle />
window.addEventListener("phx:set-theme", (e) => {
  applyTheme(e.target.dataset.phxTheme || "system");
});

// Re-apply system theme if OS preference changes and user has no explicit pref
window
  .matchMedia("(prefers-color-scheme: dark)")
  .addEventListener("change", () => {
    if (!localStorage.getItem("theme-pref")) applyTheme("system");
  });

// connect if there are any LiveViews on the page
liveSocket.connect();

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket;

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener(
    "phx:live_reload:attached",
    ({ detail: reloader }) => {
      // Enable server log streaming to client.
      // Disable with reloader.disableServerLogs()
      reloader.enableServerLogs();

      // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
      //
      //   * click with "c" key pressed to open at caller location
      //   * click with "d" key pressed to open at function component definition location
      let keyDown;
      window.addEventListener("keydown", (e) => (keyDown = e.key));
      window.addEventListener("keyup", (_e) => (keyDown = null));
      window.addEventListener(
        "click",
        (e) => {
          if (keyDown === "c") {
            e.preventDefault();
            e.stopImmediatePropagation();
            reloader.openEditorAtCaller(e.target);
          } else if (keyDown === "d") {
            e.preventDefault();
            e.stopImmediatePropagation();
            reloader.openEditorAtDef(e.target);
          }
        },
        true,
      );

      window.liveReloader = reloader;
    },
  );
}

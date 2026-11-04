// Pont entre les pages web et l'app mobile Vitriin (coquille Expo, voir src/shell/).
// Sans effet dans un navigateur : rien ne s'exécute hors de l'app, ni dans l'aperçu en iframe.
(() => {
  if (!/\bVitriinApp\//.test(navigator.userAgent) || window.top !== window) return;

  const N = (window.VitriinNative = window.VitriinNative || {});
  const root = document.documentElement;
  const $ = (s) => document.querySelector(s);
  const post = (m) => {
    if (window.ReactNativeWebView) window.ReactNativeWebView.postMessage(JSON.stringify(m));
    else setTimeout(() => post(m), 50);
  };

  // La barre d'onglets native remplace le menu web, à la même place et à la même hauteur.
  root.classList.add("in-app");
  const css = document.createElement("style");
  css.textContent = "html.in-app #nav,html.in-app #tabs{visibility:hidden;pointer-events:none}";
  root.appendChild(css);
  // Android ne donne pas les marges de l'écran à la page : l'app les fournit.
  if (Number.isFinite(N.top)) root.style.setProperty("--sat", N.top + "px");
  if (Number.isFinite(N.bottom)) root.style.setProperty("--sab", N.bottom + "px");

  N.inApp = true;
  N.openAuth = (url) => post({ t: "auth", url });
  try {
    Object.defineProperty(navigator, "share", {
      configurable: true,
      value: async (d) => post({ t: "share", title: d?.title || "", text: d?.text || "", url: d?.url || "" }),
    });
  } catch {}

  document.addEventListener("click", (e) => {
    const b = e.target.closest?.("[data-space]");
    if (b) post({ t: "space", to: b.dataset.space });
  });

  /* ---------- État de la page, envoyé à l'app quand il change ---------- */
  const typing = () => {
    const a = document.activeElement;
    return !!a && (a.tagName === "TEXTAREA" || (a.tagName === "INPUT" && !/^(checkbox|radio|file|button)$/.test(a.type)));
  };
  let last = "", pushAsked = false;
  function report() {
    const nav = $("#nav") || $("#tabs");
    const covered = $("#nav") ? $("#layer > *, #subsheet") : $("#reels, body > .ov, body > .onb, body > .done");
    const bd = $("#nav-bd");
    const state = {
      t: "state",
      tabs: !!nav && !nav.classList.contains("hidden") && !covered && !typing(),
      tab: nav?.querySelector(".on")?.dataset.tab || null,
      badge: bd && !bd.classList.contains("hidden") ? parseInt(bd.textContent, 10) || 0 : 0,
      dark: !!$("#reels"),
    };
    const s = JSON.stringify(state);
    if (s !== last) { last = s; post(state); }
    if (state.tabs && !pushAsked) { pushAsked = true; askPush(); }
  }
  let queued = false;
  const schedule = () => { if (queued) return; queued = true; requestAnimationFrame(() => { queued = false; report(); }); };
  new MutationObserver(schedule).observe(root, { subtree: true, childList: true, attributes: true, attributeFilter: ["class"] });
  addEventListener("focusin", schedule);
  addEventListener("focusout", schedule);

  /* ---------- Notifications : le jeton est rattaché au compte connecté ---------- */
  const SPACE = location.pathname.startsWith("/magasin") ? "magasin" : "client";
  const TOKEN_KEY = "vitriin-push-" + SPACE;
  const client = () => (typeof sb === "undefined" ? null : sb);
  const stored = { get() { try { return localStorage.getItem(TOKEN_KEY); } catch { return null; } }, set(v) { try { v ? localStorage.setItem(TOKEN_KEY, v) : localStorage.removeItem(TOKEN_KEY); } catch {} } };
  async function askPush() {
    const c = client(); if (!c) return;
    const { data } = await c.auth.getSession();
    if (data.session) return post({ t: "push" });
    // Déconnecté : le téléphone ne doit plus recevoir les notifications de ce compte.
    const old = stored.get();
    if (old) { await c.rpc("unregister_device", { p_token: old, p_space: SPACE }); stored.set(null); }
  }

  /* ---------- Appels de l'app vers la page ---------- */
  window.VitriinShell = {
    tab(id) {
      if (/^[a-z]+$/.test(id)) $(`#nav [data-tab="${id}"], #tabs [data-tab="${id}"]`)?.click();
    },
    back() {
      if (typeof closeLayer === "function" && $("#layer > *, #subsheet")) return closeLayer();
      const ov = [...document.querySelectorAll("body > .ov")].pop();
      if (ov) return ov.click();
      post({ t: "back-unhandled" });
    },
    async pushToken(token) {
      const { error } = await client().rpc("register_device", { p_token: token, p_platform: N.platform, p_space: SPACE });
      if (!error) stored.set(token);
    },
  };
})();

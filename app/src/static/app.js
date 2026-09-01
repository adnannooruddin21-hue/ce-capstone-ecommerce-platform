(function () {
  "use strict";
  const $ = (id) => document.getElementById(id);
  const euro = (n) => "€" + Number(n).toFixed(2);
  const store = {
    get(k, f) { try { return JSON.parse(localStorage.getItem(k)) ?? f; } catch (e) { return f; } },
    set(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) {} }
  };
  const esc = (v) => String(v).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

  async function api(url, opts) {
    const r = await fetch(url, opts);
    const data = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(data.error || ("Request failed (" + r.status + ")"));
    return data;
  }

  const state = {
    products: [],
    cart: store.get("cloudcart-cart", []),
    category: "All",
    search: ""
  };

  /* ---- theme ---- */
  const savedTheme = store.get("cloudcart-theme", null);
  if (savedTheme) document.documentElement.setAttribute("data-theme", savedTheme);
  $("themeBtn").addEventListener("click", () => {
    const cur = document.documentElement.getAttribute("data-theme")
      || (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
    const next = cur === "dark" ? "light" : "dark";
    document.documentElement.setAttribute("data-theme", next);
    store.set("cloudcart-theme", next);
  });

  /* ---- categories ---- */
  async function loadCategories() {
    const cats = await api("/api/categories");
    $("chips").innerHTML = cats.map((c) =>
      `<button class="chip" aria-pressed="${c === state.category}" data-cat="${esc(c)}">${esc(c)}</button>`
    ).join("");
  }
  $("chips").addEventListener("click", (e) => {
    const b = e.target.closest(".chip");
    if (!b) return;
    state.category = b.dataset.cat;
    loadCategories();
    loadProducts();
  });

  /* ---- products ---- */
  function skeletons() {
    $("grid").innerHTML = Array.from({ length: 8 }).map(() =>
      `<div class="card sk"><div class="tile"></div><div class="l t1"></div><div class="l t2"></div><div class="l t3"></div><div class="l t4"></div></div>`
    ).join("");
  }
  async function loadProducts() {
    const params = new URLSearchParams();
    if (state.category !== "All") params.set("category", state.category);
    if (state.search) params.set("search", state.search);
    try {
      state.products = await api("/api/products?" + params.toString());
      renderGrid();
    } catch (err) {
      $("grid").innerHTML = `<div class="empty"><div class="big">⚠️</div>Could not load the catalogue: ${esc(err.message)}</div>`;
    }
  }
  function renderGrid() {
    if (!state.products.length) {
      $("grid").innerHTML = `<div class="empty"><div class="big">🔍</div>No products match that.</div>`;
      return;
    }
    $("grid").innerHTML = state.products.map((p) => `
      <article class="card">
        <div class="tile" data-cat="${esc(p.category)}">
          ${p.badge ? `<span class="badge">${esc(p.badge)}</span>` : ""}
          <span>${esc(p.emoji)}</span>
        </div>
        <div class="body">
          <h3>${esc(p.name)}</h3>
          <p>${esc(p.description)}</p>
          <div class="row">
            <span class="price">${euro(p.price)}</span>
            <button class="add" data-add="${p.id}" ${p.stock < 1 ? "disabled" : ""}>${p.stock < 1 ? "Sold out" : "Add"}</button>
          </div>
          <div class="stock">${p.stock} in stock</div>
        </div>
      </article>`).join("");
  }
  $("grid").addEventListener("click", (e) => {
    const b = e.target.closest("[data-add]");
    if (b) addToCart(Number(b.dataset.add));
  });

  /* ---- search (debounced) ---- */
  let searchTimer;
  $("search").addEventListener("input", (e) => {
    clearTimeout(searchTimer);
    searchTimer = setTimeout(() => { state.search = e.target.value.trim(); loadProducts(); }, 240);
  });

  /* ---- cart ---- */
  function saveCart() { store.set("cloudcart-cart", state.cart); renderCart(); }
  function addToCart(id) {
    const p = state.products.find((x) => x.id === id);
    if (!p) return;
    const line = state.cart.find((x) => x.id === id);
    if (line) { if (line.quantity < p.stock) line.quantity++; }
    else state.cart.push({ id: p.id, name: p.name, price: p.price, emoji: p.emoji, category: p.category, quantity: 1 });
    saveCart();
    bumpCount();
    toast("Added to cart");
  }
  function changeQty(id, d) {
    const line = state.cart.find((x) => x.id === id);
    if (!line) return;
    line.quantity += d;
    if (line.quantity <= 0) state.cart = state.cart.filter((x) => x.id !== id);
    saveCart();
  }
  function renderCart() {
    const count = state.cart.reduce((s, x) => s + x.quantity, 0);
    const total = state.cart.reduce((s, x) => s + Number(x.price) * x.quantity, 0);
    $("cartCount").textContent = count;
    $("drawerTotal").textContent = euro(total);
    $("checkoutBtn").disabled = count === 0;
    $("drawerItems").innerHTML = state.cart.length ? state.cart.map((x) => `
      <div class="line">
        <div class="thumb" style="background:var(--tile-${String(x.category).toLowerCase()})">${esc(x.emoji)}</div>
        <div>
          <strong>${esc(x.name)}</strong><br><small>${euro(x.price)}</small>
          <div class="qty">
            <button data-q="-1" data-id="${x.id}" aria-label="Decrease quantity">−</button>
            <span>${x.quantity}</span>
            <button data-q="1" data-id="${x.id}" aria-label="Increase quantity">+</button>
          </div>
        </div>
        <span class="amt">${euro(Number(x.price) * x.quantity)}</span>
      </div>`).join("") : `<div class="empty"><div class="big">🛒</div>Your cart is empty.</div>`;
  }
  $("drawerItems").addEventListener("click", (e) => {
    const b = e.target.closest("[data-q]");
    if (b) changeQty(Number(b.dataset.id), Number(b.dataset.q));
  });
  let bumpT;
  function bumpCount() {
    const el = $("cartCount");
    el.classList.add("bump");
    clearTimeout(bumpT);
    bumpT = setTimeout(() => el.classList.remove("bump"), 200);
  }

  /* ---- drawer ---- */
  let lastFocus = null;
  function openDrawer() {
    lastFocus = document.activeElement;
    $("drawer").classList.add("open");
    $("drawer").setAttribute("aria-hidden", "false");
    $("overlay").classList.add("show");
    $("closeDrawer").focus();
  }
  function closeDrawer() {
    $("drawer").classList.remove("open");
    $("drawer").setAttribute("aria-hidden", "true");
    $("overlay").classList.remove("show");
    if (lastFocus) lastFocus.focus();
  }
  $("cartBtn").addEventListener("click", openDrawer);
  $("closeDrawer").addEventListener("click", closeDrawer);
  $("overlay").addEventListener("click", closeDrawer);

  /* ---- checkout ---- */
  const MODAL_FORM = $("modalBody").innerHTML;
  function openModal() { $("modalBg").classList.add("show"); $("cName").focus(); }
  function closeModal() { $("modalBg").classList.remove("show"); $("modalBody").innerHTML = MODAL_FORM; wireForm(); }
  $("checkoutBtn").addEventListener("click", () => { if (state.cart.length) openModal(); });
  $("closeModal").addEventListener("click", closeModal);

  function wireForm() {
    const f = $("checkoutForm");
    if (!f) return;
    f.addEventListener("submit", async (e) => {
      e.preventDefault();
      try {
        const data = await api("/api/orders", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            customer: { name: $("cName").value, email: $("cEmail").value },
            items: state.cart.map((x) => ({ id: x.id, quantity: x.quantity }))
          })
        });
        const name = $("cName").value.trim().split(" ")[0];
        state.cart = [];
        saveCart();
        $("modalBody").innerHTML = `
          <div class="done">
            <div class="check">✓</div>
            <div class="eyebrow">Order confirmed</div>
            <h2>Thanks, ${esc(name)}!</h2>
            <p class="muted">This is a demonstration checkout. No payment was processed.</p>
            <div class="oid">${esc(data.order_id)} &middot; €${esc(data.total)}</div>
          </div>`;
      } catch (err) {
        toast(err.message);
      }
    });
  }

  /* ---- Esc closes whatever is open ---- */
  document.addEventListener("keydown", (e) => {
    if (e.key !== "Escape") return;
    if ($("modalBg").classList.contains("show")) closeModal();
    else if ($("drawer").classList.contains("open")) closeDrawer();
  });

  /* ---- toast ---- */
  let toastT;
  function toast(msg) {
    const t = $("toast");
    t.innerHTML = `<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3"><path d="M5 13l4 4L19 7"/></svg>${esc(msg)}`;
    t.classList.add("show");
    clearTimeout(toastT);
    toastT = setTimeout(() => t.classList.remove("show"), 1800);
  }

  /* ---- infra chip: which ASG instance served this page ---- */
  async function loadInfra() {
    try {
      const d = await api("/api/infra");
      const id = String(d.instance_id || "unknown");
      $("infraId").textContent = id.length > 13 ? id.slice(0, 12) + "…" : id;
      $("infraId").title = id;
      $("infraAz").textContent = d.availability_zone ? "· " + d.availability_zone : "";
      $("infra").hidden = false;
    } catch (e) { /* leave hidden */ }
  }

  /* ---- boot ---- */
  skeletons();
  renderCart();
  wireForm();
  loadInfra();
  loadCategories().then(loadProducts).catch(() => {
    $("grid").innerHTML = `<div class="empty"><div class="big">⚠️</div>Could not reach the API.</div>`;
  });
})();

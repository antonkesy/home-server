// the system panel: /stats is a fresh lab-stats snapshot (scripts/lab-stats.sh),
// which takes a second to measure; asked again 5s after each answer, and not
// while the tab is hidden
(function () {
  var panel = document.querySelector(".monitor");
  if (!panel) return;
  var GiB = 1024 * 1024 * 1024;
  var sortBy = "mem";
  var showAll = false;
  var last = null;
  var timer = null;
  var asking = false;

  function bytes(b) {
    if (b >= GiB) return (b / GiB).toFixed(1) + " GiB";
    return Math.round(b / 1024 / 1024) + " MiB";
  }
  function rate(b) {
    if (b >= 1e6) return (b / 1e6).toFixed(1) + " MB/s";
    return Math.round(b / 1e3) + " kB/s";
  }
  function pct(p) {
    return (p < 10 ? p.toFixed(1) : Math.round(p)) + " %";
  }
  function since(s) {
    var d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600);
    if (d > 0) return d + " d " + h + " h";
    return h + " h " + Math.floor((s % 3600) / 60) + " min";
  }
  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined) e.textContent = text;
    return e;
  }

  // the fill turns amber, then red, near full; the word says so too
  function meter(key, label, p, value, sub) {
    var m = panel.querySelector('[data-m="' + key + '"]');
    if (!m) return;
    m.hidden = false;
    var level = p >= 95 ? "crit" : p >= 80 ? "warn" : "";
    m.querySelector(".label").textContent = label;
    m.querySelector(".value").textContent = value;
    var flag = m.querySelector(".flag");
    flag.textContent = level === "crit" ? "▲ full" : level === "warn" ? "▲ high" : "";
    flag.className = "flag " + level;
    var fill = m.querySelector(".fill");
    fill.style.width = Math.min(100, Math.max(0, p)) + "%";
    fill.className = "fill " + level;
    m.querySelector(".track").setAttribute("aria-valuenow", Math.round(p));
    m.querySelector(".sub").textContent = sub || "";
  }

  function render(s) {
    var c = s.cpu;
    meter("cpu", "CPU", c.pct, pct(c.pct),
      "load " + c.load.map(function (l) { return l.toFixed(2); }).join(" ") +
      " · " + c.cores + " cores" + (c.temp !== null ? " · " + c.temp + " °C" : ""));
    meter("mem", "Memory", 100 * s.mem.used / s.mem.total,
      bytes(s.mem.used) + " of " + bytes(s.mem.total));
    if (s.swap.total > 0) {
      meter("swap", "Swap (zram)", 100 * s.swap.used / s.swap.total,
        bytes(s.swap.used) + " of " + bytes(s.swap.total));
    }
    s.disks.forEach(function (d, i) {
      meter("disk" + i, "Disk " + d.mount, 100 * d.used / d.size,
        bytes(d.used) + " of " + bytes(d.size));
    });
    panel.querySelector(".net").textContent = s.net.iface
      ? s.net.iface + "  ↓ " + rate(s.net.rx) + "  ↑ " + rate(s.net.tx) : "no route";
    panel.querySelector(".uptime").textContent = since(s.uptime);
    panel.querySelector(".state").textContent = "";
    last = s;
    rows();
  }

  // who takes how much: sorted by the chosen column, bars against its top row
  function rows() {
    if (!last) return;
    var units = last.units.slice().sort(function (a, b) { return b[sortBy] - a[sortBy]; });
    var shown = showAll ? units : units.slice(0, 10);
    var maxCpu = Math.max.apply(null, units.map(function (u) { return u.cpu; }).concat([0.1]));
    var maxMem = Math.max.apply(null, units.map(function (u) { return u.mem; }).concat([1]));
    var body = panel.querySelector("tbody");
    body.textContent = "";
    shown.forEach(function (u) {
      var tr = el("tr");
      tr.appendChild(el("td", "unit", u.name));
      [["cpu", pct(u.cpu), u.cpu / maxCpu], ["mem", bytes(u.mem), u.mem / maxMem]].forEach(function (col) {
        var td = el("td", "num");
        td.appendChild(el("span", "", col[1]));
        var bar = el("span", "bar");
        var fill = el("span");
        // a sliver for anything above zero, so a small user still shows
        fill.style.width = (col[2] > 0 ? Math.max(2, 100 * col[2]) : 0) + "%";
        bar.appendChild(fill);
        td.appendChild(bar);
        tr.appendChild(td);
      });
      body.appendChild(tr);
    });
    panel.querySelectorAll("th button").forEach(function (b) {
      var on = b.dataset.sort === sortBy;
      b.parentNode.setAttribute("aria-sort", on ? "descending" : "none");
      b.textContent = b.dataset.label + (on ? " ▾" : "");
    });
    var more = panel.querySelector(".more");
    more.hidden = units.length <= 10;
    more.textContent = showAll ? "Show top 10" : "Show all " + units.length;
  }

  panel.querySelectorAll("th button").forEach(function (b) {
    b.addEventListener("click", function () { sortBy = b.dataset.sort; rows(); });
  });
  panel.querySelector(".more").addEventListener("click", function () {
    showAll = !showAll;
    rows();
  });

  function poll() {
    clearTimeout(timer);
    if (asking || document.hidden) return;
    asking = true;
    fetch("/stats", { cache: "no-store" })
      .then(function (r) {
        if (!r.ok) throw new Error(r.status);
        return r.json();
      })
      .then(render)
      .catch(function () { panel.querySelector(".state").textContent = "no answer"; })
      .then(function () {
        asking = false;
        timer = setTimeout(poll, 5000);
      });
  }
  document.addEventListener("visibilitychange", function () { if (!document.hidden) poll(); });
  poll();
})();

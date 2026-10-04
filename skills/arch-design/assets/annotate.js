/* annotate.js — review annotations that live inside design.html.
 *
 * Constraints this is built around:
 *  - No network, no server, no dependency. The file is emailed and opened by double-click.
 *  - A file:// page cannot overwrite itself, so "save" writes a new annotated copy: the File
 *    System Access API when the browser has it (a real save over the same file), a download
 *    otherwise.
 *  - JavaScript cannot read the OS username or environment. The document author is baked in at
 *    render time; each reviewer identifies themselves once and the answer is cached locally.
 *
 * Comments are stored twice on purpose: embedded in the HTML so they survive being emailed to
 * someone else, and in localStorage so an accidental close does not lose unsaved work. On load the
 * two are merged by id, newest wins.
 */
(function () {
  "use strict";

  var CONFIG = window.__DESIGN_ANNOTATE__ || {};
  var DATA_ID = "design-comments";
  var STORE_KEY = "design-comments:" + (CONFIG.documentId || location.pathname);
  // Deliberately NOT per-document: every file:// page shares one localStorage origin in Chrome,
  // Edge and Firefox, so one global key means every design file you open already knows who you
  // are. (Safari blocks file:// localStorage unless local-file restrictions are disabled; there
  // the identity lasts for the session only, and the panel says so.)
  var IDENTITY_KEY = "design-review:identity";
  var PREFS_KEY = "design-review:prefs";
  // Common reviewer roles, offered as suggestions — the field stays free text so nobody is
  // forced into a label that does not describe them.
  var ROLES = [
    "Product", "R&D", "Architecture", "Security", "QA", "DevOps", "Design", "Data", "Support"
  ];
  var CONTEXT = 40;
  var AUTOSAVE_DELAY = 1200;
  var HANDLE_DB = "design-review";
  var HANDLE_STORE = "handles";

  // `orphans` is view state, kept off the comment records: anything stamped onto a record after
  // the save would make the saved copy differ from memory and trip the unsaved-changes guard.
  var state = {
    comments: [], orphans: {}, activeId: null, panelOpen: false, identity: null, storage: true,
    savedSnapshot: null, prefs: { theme: "light", readOnly: false },
    fileHandle: null, autosaveTimer: null, autosaveState: "off", lastSavedAt: null,
    autosaveDeclined: false
  };
  var els = {};

  // --- storage ------------------------------------------------------------

  function readEmbedded() {
    var node = document.getElementById(DATA_ID);
    if (!node) { return []; }
    try {
      var parsed = JSON.parse(node.textContent || "[]");
      return Array.isArray(parsed) ? parsed : [];
    } catch (err) {
      console.warn("design annotations: embedded comment block is not valid JSON", err);
      return [];
    }
  }

  function storageWorks() {
    try {
      var probe = "design-review:probe";
      localStorage.setItem(probe, "1");
      localStorage.removeItem(probe);
      return true;
    } catch (err) {
      return false;
    }
  }

  function readLocal() {
    try {
      return JSON.parse(localStorage.getItem(STORE_KEY) || "[]");
    } catch (err) {
      return [];
    }
  }

  function writeLocal() {
    try {
      localStorage.setItem(STORE_KEY, JSON.stringify(state.comments));
    } catch (err) {
      /* private browsing or quota — the embedded copy is still the source of truth */
    }
  }

  /* Merge by id so a file that came back from another reviewer keeps both sides. */
  function merge(a, b) {
    var byId = {};
    a.concat(b).forEach(function (comment) {
      if (!comment || !comment.id) { return; }
      var existing = byId[comment.id];
      if (!existing || (comment.updated || "") >= (existing.updated || "")) {
        byId[comment.id] = comment;
      }
    });
    return Object.keys(byId).map(function (key) { return byId[key]; }).sort(function (x, y) {
      return (x.created || "").localeCompare(y.created || "");
    });
  }

  function loadPrefs() {
    try {
      var parsed = JSON.parse(localStorage.getItem(PREFS_KEY) || "{}");
      return {
        theme: parsed.theme === "dark" ? "dark" : "light",
        readOnly: parsed.readOnly === true
      };
    } catch (err) {
      return { theme: "light", readOnly: false };
    }
  }

  function savePrefs() {
    try {
      localStorage.setItem(PREFS_KEY, JSON.stringify(state.prefs));
    } catch (err) {
      /* session-only */
    }
  }

  function applyPrefs() {
    document.body.classList.toggle("theme-dark", state.prefs.theme === "dark");
    document.body.classList.toggle("anno-readonly", state.prefs.readOnly);
    if (state.prefs.readOnly && state.panelOpen) { togglePanel(); }
  }

  function toggleTheme() {
    state.prefs.theme = state.prefs.theme === "dark" ? "light" : "dark";
    savePrefs();
    applyPrefs();
    render();
  }

  /* Read-only is Word's "No Markup" view: the document with every annotation out of the way. */
  function toggleReadOnly() {
    state.prefs.readOnly = !state.prefs.readOnly;
    savePrefs();
    hideTip();
    hideComposer();
    applyPrefs();
    paint();
    render();
    renderQuestions();
    updateToc();
  }

  // --- identity -----------------------------------------------------------
  // A browser cannot read $USER or any environment variable, so the reviewer tells us once and
  // the answer is kept under a global key shared by every design file on this machine.

  function loadIdentity() {
    try {
      var raw = localStorage.getItem(IDENTITY_KEY);
      if (!raw) { return null; }
      var parsed = JSON.parse(raw);
      return parsed && parsed.name ? parsed : null;
    } catch (err) {
      return null;
    }
  }

  function saveIdentity(identity) {
    state.identity = identity;
    try {
      localStorage.setItem(IDENTITY_KEY, JSON.stringify(identity));
    } catch (err) {
      /* session-only; the panel already warns that this browser blocks local storage */
    }
  }

  /* "yossi   cohen" -> "Yossi Cohen"; leaves already-styled names like "McCoy" alone. */
  function titleCase(value) {
    return (value || "").trim().replace(/\s+/g, " ").split(" ").map(function (word) {
      if (!word) { return word; }
      if (word !== word.toLowerCase()) { return word; }
      return word.charAt(0).toUpperCase() + word.slice(1);
    }).join(" ");
  }

  function isFullName(value) {
    var parts = (value || "").trim().split(/\s+/).filter(Boolean);
    return parts.length >= 2 && parts.every(function (part) { return part.length >= 2; });
  }

  function authorLabel() {
    if (!state.identity) { return "Anonymous"; }
    return state.identity.role
      ? state.identity.name + " (" + state.identity.role + ")"
      : state.identity.name;
  }

  /* Resolve identity before the first comment; returns false when the reviewer cancels. */
  function ensureIdentity(onReady) {
    if (state.identity && state.identity.name) { onReady(); return; }
    openSettings(onReady);
  }

  /* One modal implementation for every dialog: native alert/confirm/prompt are blocking, cannot
     be styled, and are suppressed outright in some embedded viewers. */
  function openModal(options) {
    var backdrop = document.createElement("div");
    backdrop.className = "anno-modal-backdrop";
    var panel = document.createElement("div");
    panel.className = "anno-modal";
    panel.setAttribute("role", "dialog");
    panel.setAttribute("aria-label", options.title || "Dialog");
    panel.innerHTML = "<h3></h3>" + (options.bodyHtml || "") +
      '<div class="anno-row">' +
      '<button type="button" class="anno-btn" data-act="cancel"></button>' +
      '<button type="button" class="anno-btn primary" data-act="confirm"></button>' +
      "</div>";
    panel.querySelector("h3").textContent = options.title || "";
    panel.querySelector('[data-act="cancel"]').textContent = options.cancelLabel || "Cancel";
    var confirmButton = panel.querySelector('[data-act="confirm"]');
    confirmButton.textContent = options.confirmLabel || "Save";
    if (options.danger) { confirmButton.classList.add("danger"); }
    backdrop.appendChild(panel);
    document.body.appendChild(backdrop);

    function close() { backdrop.remove(); }
    function submit() { if (options.onConfirm(panel, close) !== false) { close(); } }

    backdrop.addEventListener("click", function (event) {
      if (event.target === backdrop) { close(); }
    });
    panel.querySelector('[data-act="cancel"]').addEventListener("click", close);
    confirmButton.addEventListener("click", submit);
    backdrop.addEventListener("keydown", function (event) {
      if (event.key === "Escape") { close(); }
      if (event.key === "Enter" && event.target.tagName !== "TEXTAREA") { submit(); }
    });
    if (options.onOpen) { options.onOpen(panel, close); }
    return { panel: panel, close: close };
  }

  function confirmModal(title, message, confirmLabel, onYes) {
    openModal({
      title: title,
      bodyHtml: '<p class="anno-modal-note" data-message></p>',
      confirmLabel: confirmLabel,
      danger: true,
      onOpen: function (panel) { panel.querySelector("[data-message]").textContent = message; },
      onConfirm: function () { onYes(); }
    });
  }

  function markSelectedRole(container, value) {
    Array.prototype.slice.call(container.querySelectorAll(".anno-role-chip")).forEach(
      function (chip) {
        chip.classList.toggle("is-on", chip.textContent === value);
      }
    );
  }

  function openSettings(onSaved) {
    var current = state.identity || { name: "", role: "" };
    openModal({
      title: "Who is commenting?",
      confirmLabel: "Save",
      bodyHtml:
        '<p class="anno-modal-note">Saved in this browser and reused for every design file you ' +
        "open on this machine. Your browser cannot read your computer account, so this is asked " +
        "once.</p>" +
        "<label>Full name" +
        '<input type="text" data-field="name" autocomplete="name" placeholder="Yossi Cohen">' +
        '<span class="anno-hint">First and last name, each capitalised — e.g. Yossi Cohen</span>' +
        '<span class="anno-error" hidden>Enter a first and last name, e.g. Yossi Cohen</span>' +
        "</label>" +
        '<label>Role <span class="anno-optional">(optional)</span>' +
        '<input type="text" data-field="role" list="anno-roles" placeholder="Product">' +
        '<datalist id="anno-roles">' +
        ROLES.map(function (role) {
          return '<option value="' + role.replace(/&/g, "&amp;") + '"></option>';
        }).join("") +
        "</datalist>" +
        '<span class="anno-roles" data-roles></span>' +
        "</label>" +
        '<p class="anno-modal-warn" hidden>This browser will not remember the name between ' +
        "windows, because it blocks local storage for files opened from disk.</p>",
      onOpen: function (panel) {
        var nameInput = panel.querySelector('[data-field="name"]');
        var error = panel.querySelector(".anno-error");
        nameInput.value = current.name || "";
        panel.querySelector('[data-field="role"]').value = current.role || "";
        if (!state.storage) { panel.querySelector(".anno-modal-warn").hidden = false; }
        nameInput.addEventListener("input", function () { error.hidden = true; });
        nameInput.addEventListener("blur", function () {
          nameInput.value = titleCase(nameInput.value);
        });
        var roleInput = panel.querySelector('[data-field="role"]');
        var chips = panel.querySelector("[data-roles]");
        ROLES.forEach(function (role) {
          var chip = document.createElement("button");
          chip.type = "button";
          chip.className = "anno-role-chip";
          chip.textContent = role;
          chip.addEventListener("click", function () {
            roleInput.value = roleInput.value === role ? "" : role;
            markSelectedRole(chips, roleInput.value);
          });
          chips.appendChild(chip);
        });
        roleInput.addEventListener("input", function () {
          markSelectedRole(chips, roleInput.value);
        });
        markSelectedRole(chips, current.role || "");
        nameInput.focus();
        nameInput.select();
      },
      onConfirm: function (panel) {
        var nameInput = panel.querySelector('[data-field="name"]');
        var name = titleCase(nameInput.value);
        if (!isFullName(name)) {
          panel.querySelector(".anno-error").hidden = false;
          nameInput.focus();
          return false;
        }
        saveIdentity({ name: name, role: titleCase(panel.querySelector('[data-field="role"]').value) });
        render();
        if (onSaved) { onSaved(); }
      }
    });
  }

  // --- anchoring ----------------------------------------------------------
  // Quote + surrounding context, in the spirit of the W3C TextQuoteSelector: robust when the
  // document is re-rendered and offsets shift.

  function documentRoot() { return document.querySelector("main.doc") || document.body; }

  function textNodes(root) {
    var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode: function (node) {
        if (!node.nodeValue) { return NodeFilter.FILTER_REJECT; }
        var parent = node.parentElement;
        while (parent && parent !== root) {
          var tag = parent.tagName;
          if (tag === "SCRIPT" || tag === "STYLE" || parent.classList.contains("anno-panel")) {
            return NodeFilter.FILTER_REJECT;
          }
          parent = parent.parentElement;
        }
        return NodeFilter.FILTER_ACCEPT;
      }
    });
    var nodes = [];
    var current;
    while ((current = walker.nextNode())) { nodes.push(current); }
    return nodes;
  }

  function flatten(root) {
    var nodes = textNodes(root);
    var text = "";
    var map = [];
    nodes.forEach(function (node) {
      map.push({ node: node, start: text.length });
      text += node.nodeValue;
    });
    return { text: text, map: map, nodes: nodes };
  }

  /* Character offset of a range boundary from the start of the document body.
     Measured with a Range rather than by looking the node up in the text-node map: a selection
     boundary is often an *element* (triple-click, double-click, selectNodeContents), which never
     appears in that map. */
  function offsetOf(root, container, offset) {
    try {
      var probe = document.createRange();
      probe.setStart(root, 0);
      probe.setEnd(container, offset);
      return probe.toString().length;
    } catch (err) {
      return -1;
    }
  }

  function locate(flat, anchor) {
    if (!anchor || !anchor.quote) { return null; }
    var quote = anchor.quote;
    var candidates = [];
    var from = 0;
    var found;
    while ((found = flat.text.indexOf(quote, from)) !== -1) {
      candidates.push(found);
      from = found + 1;
      if (candidates.length > 64) { break; }
    }
    if (!candidates.length) { return null; }
    if (candidates.length === 1) { return { start: candidates[0], end: candidates[0] + quote.length }; }
    // Several identical strings: pick the one whose surrounding text matches best.
    var best = candidates[0];
    var bestScore = -1;
    candidates.forEach(function (index) {
      var prefix = flat.text.slice(Math.max(0, index - CONTEXT), index);
      var suffix = flat.text.slice(index + quote.length, index + quote.length + CONTEXT);
      var score = commonTail(prefix, anchor.prefix || "") + commonHead(suffix, anchor.suffix || "");
      if (score > bestScore) { bestScore = score; best = index; }
    });
    return { start: best, end: best + quote.length };
  }

  function commonTail(a, b) {
    var n = 0;
    while (n < a.length && n < b.length && a[a.length - 1 - n] === b[b.length - 1 - n]) { n++; }
    return n;
  }

  function commonHead(a, b) {
    var n = 0;
    while (n < a.length && n < b.length && a[n] === b[n]) { n++; }
    return n;
  }

  function rangeFor(flat, span) {
    var range = document.createRange();
    var startSet = false;
    for (var i = 0; i < flat.map.length; i++) {
      var entry = flat.map[i];
      var end = entry.start + entry.node.nodeValue.length;
      if (!startSet && span.start >= entry.start && span.start <= end) {
        range.setStart(entry.node, span.start - entry.start);
        startSet = true;
      }
      if (startSet && span.end >= entry.start && span.end <= end) {
        range.setEnd(entry.node, span.end - entry.start);
        return range;
      }
    }
    return null;
  }

  // --- highlight painting -------------------------------------------------

  function clearHighlights() {
    Array.prototype.slice.call(document.querySelectorAll("mark.anno")).forEach(function (mark) {
      var parent = mark.parentNode;
      while (mark.firstChild) {
        if (mark.firstChild.classList && mark.firstChild.classList.contains("anno-count")) {
          mark.removeChild(mark.firstChild);
          continue;
        }
        parent.insertBefore(mark.firstChild, mark);
      }
      parent.removeChild(mark);
      parent.normalize();
    });
  }

  function paint() {
    clearHighlights();
    if (state.prefs.readOnly) { return; }
    var root = documentRoot();
    // Paint from the end backwards: wrapping text changes the DOM, and later offsets stay valid
    // only while everything before them is untouched.
    var located = [];
    var flat = flatten(root);
    state.comments.forEach(function (comment) {
      var span = locate(flat, comment.anchor);
      state.orphans[comment.id] = !span;
      if (span) { located.push({ comment: comment, span: span }); }
    });
    located.sort(function (a, b) { return b.span.start - a.span.start; });
    located.forEach(function (entry) {
      wrapSpan(flatten(root), entry.span, entry.comment);
    });
  }

  /* Wrap each intersecting text node in its own <mark>. Wrapping the whole range in one element
     breaks as soon as the selection covers a block: an inline <mark> around an <h2> detaches the
     heading and leaves the badge floating on its own line. */
  function wrapSpan(flat, span, comment) {
    var marks = [];
    flat.map.forEach(function (entry) {
      var nodeStart = entry.start;
      var nodeEnd = nodeStart + entry.node.nodeValue.length;
      var from = Math.max(span.start, nodeStart);
      var to = Math.min(span.end, nodeEnd);
      if (to <= from) { return; }
      var range = document.createRange();
      range.setStart(entry.node, from - nodeStart);
      range.setEnd(entry.node, to - nodeStart);
      var mark = document.createElement("mark");
      mark.className = "anno";
      mark.dataset.commentId = comment.id;
      mark.dataset.status = comment.status || "open";
      mark.tabIndex = 0;
      // Always a single text node, so this never throws.
      range.surroundContents(mark);
      mark.addEventListener("click", function (event) {
        event.stopPropagation();
        select(comment.id);
      });
      mark.addEventListener("keydown", function (event) {
        if (event.key === "Enter" || event.key === " ") {
          event.preventDefault();
          select(comment.id);
        }
      });
      marks.push(mark);
    });
    if (!marks.length) { return; }
    var badge = document.createElement("span");
    badge.className = "anno-count";
    badge.textContent = String(1 + (comment.replies || []).length);
    marks[marks.length - 1].appendChild(badge);
  }

  // --- open questions -------------------------------------------------------
  // `Q:` lines are the document's own unresolved decisions. They are not comments — nobody wrote
  // them in the browser — but a reviewer needs the same two things from both: a count per section
  // and a way to jump straight to them.

  function questionNodes() {
    return Array.prototype.slice.call(document.querySelectorAll("p.open-question"));
  }

  function renderQuestions() {
    var nodes = questionNodes();

    var host = els.questions;
    host.innerHTML = "";
    if (!nodes.length) { host.hidden = true; return; }
    host.hidden = false;

    var heading = document.createElement("h3");
    heading.className = "anno-group-title";
    heading.innerHTML = 'Open questions <span class="anno-badge">' + nodes.length + "</span>";
    host.appendChild(heading);

    nodes.forEach(function (node) {
      var item = document.createElement("div");
      item.className = "anno-question-item";
      item.dataset.target = node.id;

      var jump = document.createElement("button");
      jump.type = "button";
      jump.className = "anno-question-jump";

      var label = document.createElement("span");
      label.className = "anno-qnum";
      label.textContent = "Q" + (node.dataset.question || "");
      jump.appendChild(label);

      var text = document.createElement("span");
      text.className = "anno-question-text";
      text.textContent = node.textContent.replace(/^Q\d*\s*/, "");
      jump.appendChild(text);

      jump.addEventListener("click", function () { jumpToQuestion(node.id); });
      item.appendChild(jump);

      if (!state.prefs.readOnly) {
        var answer = document.createElement("button");
        answer.type = "button";
        answer.className = "anno-question-answer";
        answer.textContent = "Answer";
        answer.addEventListener("click", function (event) {
          event.stopPropagation();
          answerQuestion(node);
        });
        item.appendChild(answer);
      }

      host.appendChild(item);
    });
  }

  /* Answering a question is the commonest reason to comment, and hunting for the sentence to
     select made it the hardest. This selects the whole question — minus its "Q1" badge, which is
     chrome rather than text the author wrote — and opens the composer on it. */
  function answerQuestion(node) {
    jumpToQuestion(node.id);
    var range = document.createRange();
    range.selectNodeContents(node);
    var badge = node.querySelector(".q-label");
    var after = badge && badge.nextSibling;
    if (after && after.nodeType === 3) { range.setStart(after, 0); }
    var selection = window.getSelection();
    selection.removeAllRanges();
    selection.addRange(range);
    openComposer(range);
  }

  function jumpToQuestion(id) {
    var node = document.getElementById(id);
    if (!node) { return; }
    questionNodes().forEach(function (other) { other.classList.remove("is-target"); });
    node.classList.add("is-target");
    node.scrollIntoView({ block: "center" });
    state.activeQuestion = id;
    highlightQuestionItem(id);
  }

  function highlightQuestionItem(id) {
    Array.prototype.slice.call(els.questions.querySelectorAll(".anno-question-item")).forEach(
      function (item) { item.classList.toggle("is-active", item.dataset.target === id); }
    );
  }

  function stepQuestion(delta) {
    var nodes = questionNodes();
    if (!nodes.length) { return; }
    var index = nodes.findIndex(function (n) { return n.id === state.activeQuestion; });
    if (index === -1) {
      // No current target: start from whichever question is nearest below the reading line.
      index = nodes.findIndex(function (n) { return n.getBoundingClientRect().top > 120; });
      if (index === -1) { index = 0; }
    } else {
      index = (index + delta + nodes.length) % nodes.length;
    }
    if (!state.panelOpen && !state.prefs.readOnly) { togglePanel(); }
    jumpToQuestion(nodes[index].id);
  }

  // --- table of contents ---------------------------------------------------

  /* The contents list is the only persistent map of the document, so it carries two live signals:
     where you are, and which sections already have comments on them. */
  function updateToc() {
    var toc = document.querySelector("nav.toc");
    if (!toc) { return; }
    var counts = {};
    state.comments.forEach(function (comment) {
      var section = comment.anchor && comment.anchor.section;
      if (!section || comment.status === "resolved") { return; }
      counts[section] = (counts[section] || 0) + 1;
    });
    var questions = {};
    questionNodes().forEach(function (node) {
      var section = node.dataset.section;
      if (section) { questions[section] = (questions[section] || 0) + 1; }
    });
    Array.prototype.slice.call(toc.querySelectorAll("a[href^='#']")).forEach(function (link) {
      var id = decodeURIComponent(link.getAttribute("href").slice(1));
      setTocBadge(link, "anno-toc-badge", state.prefs.readOnly ? 0 : (counts[id] || 0),
        " comment", " comments");
      // Open questions belong to the document, so they stay visible in reading mode.
      setTocBadge(link, "anno-toc-qbadge", questions[id] || 0,
        " open question", " open questions");
    });
  }

  /* Scroll spy: the current section is the last heading whose top has passed the reading line.
     Picking the first *intersecting* heading instead biases upward and reports the section you
     just left. */
  function setTocBadge(link, className, count, singular, plural) {
    var badge = link.querySelector("." + className);
    if (!count) {
      if (badge) { badge.remove(); }
      return;
    }
    if (!badge) {
      badge = document.createElement("span");
      badge.className = className;
      link.appendChild(badge);
    }
    badge.textContent = String(count);
    badge.title = count + (count === 1 ? singular : plural) + " in this section";
  }

  function watchScroll() {
    var toc = document.querySelector("nav.toc");
    if (!toc) { return; }
    var entries = Array.prototype.slice.call(toc.querySelectorAll("a[href^='#']"))
      .map(function (link) {
        var id = decodeURIComponent(link.getAttribute("href").slice(1));
        return { link: link, heading: document.getElementById(id) };
      })
      .filter(function (entry) { return entry.heading; });
    if (!entries.length) { return; }

    var READING_LINE = 140;
    var ticking = false;

    function highlight() {
      ticking = false;
      var current = entries[0];
      entries.forEach(function (entry) {
        if (entry.heading.getBoundingClientRect().top <= READING_LINE) { current = entry; }
      });
      entries.forEach(function (entry) {
        entry.link.classList.toggle("is-current", entry === current);
      });
      if (current.link.scrollIntoView && isOutsideToc(toc, current.link)) {
        current.link.scrollIntoView({ block: "nearest" });
      }
    }

    function onScroll() {
      if (ticking) { return; }
      ticking = true;
      window.requestAnimationFrame(highlight);
    }

    window.addEventListener("scroll", onScroll, { passive: true });
    window.addEventListener("resize", onScroll, { passive: true });
    highlight();
  }

  function isOutsideToc(toc, link) {
    var box = toc.getBoundingClientRect();
    var item = link.getBoundingClientRect();
    return item.top < box.top || item.bottom > box.bottom;
  }

  // --- composer -----------------------------------------------------------

  /* Rightmost x a floating element may occupy: the review panel sits over the right edge when
     open, and a tip or composer placed under it becomes unclickable. */
  function rightBound(width) {
    var panelWidth = state.panelOpen && els.panel ? els.panel.offsetWidth : 0;
    if (!panelWidth && els.launcher && !els.launcher.hidden) { panelWidth = 0; }
    return window.scrollX + Math.max(8, window.innerWidth - panelWidth - width - 12);
  }

  function hideTip() { if (els.tip) { els.tip.remove(); els.tip = null; } }
  function hideComposer() { if (els.composer) { els.composer.remove(); els.composer = null; } }
  function hideMenu() { if (els.menu) { els.menu.remove(); els.menu = null; } }

  /* The usable selection, or null. Two characters is the floor: a stray click-drag selects one
     character and should not be read as an intent to annotate. */
  function selectedRange() {
    var selection = window.getSelection();
    if (!selection || selection.isCollapsed) { return null; }
    var range = selection.getRangeAt(0);
    if (!documentRoot().contains(range.commonAncestorContainer)) { return null; }
    if (selection.toString().trim().length < 2) { return null; }
    return range;
  }

  /* Right-clicking a selection offers Comment and Copy instead of opening the composer outright.
     Selecting text to re-read or to quote it is at least as common as selecting it to annotate,
     and a composer that appeared on every selection interrupted both. With no selection under the
     cursor, the browser's own menu is left alone. */
  function onContextMenu(event) {
    if (event.target.closest && event.target.closest(
      ".anno-menu, .anno-composer, .anno-panel, .anno-toggle, .anno-modal-backdrop"
    )) { return; }
    var range = selectedRange();
    if (!range) { return; }
    event.preventDefault();
    openMenu(event.pageX, event.pageY, range);
  }

  function openMenu(x, y, range) {
    hideMenu();
    hideComposer();
    var quote = range.toString();
    var menu = document.createElement("div");
    menu.className = "anno-menu";
    menu.setAttribute("role", "menu");
    menu.innerHTML =
      (state.prefs.readOnly
        ? ""
        : '<button type="button" role="menuitem" data-act="comment">Comment</button>') +
      '<button type="button" role="menuitem" data-act="copy">Copy</button>';
    document.body.appendChild(menu);
    menu.style.top = y + "px";
    menu.style.left = Math.min(x, rightBound(menu.offsetWidth)) + "px";
    els.menu = menu;

    menu.addEventListener("click", function (event) { event.stopPropagation(); });
    menu.addEventListener("keydown", function (event) {
      if (event.key === "Escape") { hideMenu(); }
    });
    var commentButton = menu.querySelector('[data-act="comment"]');
    if (commentButton) {
      commentButton.addEventListener("click", function () {
        hideMenu();
        openComposer(range);
      });
    }
    var copyButton = menu.querySelector('[data-act="copy"]');
    copyButton.addEventListener("click", function () {
      hideMenu();
      copySelectionText(quote);
    });
    (commentButton || copyButton).focus();
  }

  /* execCommand is the fallback rather than an afterthought: the reviewer's text is still
     selected here, and a file:// page in a browser that refuses the async clipboard would
     otherwise leave Copy doing nothing at all. */
  function copySelectionText(text) {
    copyText(text).then(function () {
      toast("Copied");
    }).catch(function () {
      var ok = false;
      try { ok = document.execCommand("copy"); } catch (err) { ok = false; }
      toast(ok ? "Copied" : "Your browser blocked copying — use the browser's own menu");
    });
  }

  function anchorFrom(range) {
    var root = documentRoot();
    var flat = flatten(root);
    var start = offsetOf(root, range.startContainer, range.startOffset);
    var end = offsetOf(root, range.endContainer, range.endOffset);
    if (start < 0 || end < 0 || end <= start) { return null; }
    var section = sectionFor(range.startContainer);
    return {
      quote: flat.text.slice(start, end),
      prefix: flat.text.slice(Math.max(0, start - CONTEXT), start),
      suffix: flat.text.slice(end, end + CONTEXT),
      section: section
    };
  }

  function sectionFor(node) {
    var element = node.nodeType === 1 ? node : node.parentElement;
    var self = element && element.closest ? element.closest("h1,h2,h3,h4,h5,h6") : null;
    if (self && self.id) { return self.id; }
    while (element) {
      var heading = element.previousElementSibling;
      while (heading) {
        if (/^H[1-6]$/.test(heading.tagName) && heading.id) { return heading.id; }
        heading = heading.previousElementSibling;
      }
      element = element.parentElement;
    }
    return "";
  }

  function openComposer(range) {
    hideTip();
    var anchor = anchorFrom(range);
    if (!anchor) { return; }
    var rect = range.getBoundingClientRect();

    hideComposer();
    var composer = document.createElement("div");
    composer.className = "anno-composer";
    composer.innerHTML =
      '<button type="button" class="anno-close" data-act="cancel" aria-label="Close">&times;</button>' +
      "<blockquote></blockquote>" +
      '<textarea placeholder="What should change here?"></textarea>' +
      '<div class="anno-row">' +
      '<button type="button" class="anno-btn" data-act="cancel">Cancel</button>' +
      '<button type="button" class="anno-btn primary" data-act="save">Add comment</button>' +
      "</div>";
    composer.querySelector("blockquote").textContent = anchor.quote;
    composer.style.top = (window.scrollY + rect.bottom + 8) + "px";
    document.body.appendChild(composer);
    composer.style.left =
      Math.min(window.scrollX + rect.left, rightBound(composer.offsetWidth)) + "px";
    els.composer = composer;

    var textarea = composer.querySelector("textarea");
    textarea.focus();
    composer.addEventListener("click", function (event) { event.stopPropagation(); });
    Array.prototype.slice.call(composer.querySelectorAll('[data-act="cancel"]')).forEach(
      function (button) { button.addEventListener("click", hideComposer); }
    );
    composer.querySelector('[data-act="save"]').addEventListener("click", function () {
      var body = textarea.value.trim();
      if (!body) { return; }
      ensureIdentity(function () {
        addComment(anchor, body);
        hideComposer();
        window.getSelection().removeAllRanges();
      });
    });
    textarea.addEventListener("keydown", function (event) {
      if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) {
        composer.querySelector('[data-act="save"]').click();
      }
      if (event.key === "Escape") { hideComposer(); }
    });
  }

  function addComment(anchor, body) {
    var now = new Date().toISOString();
    state.comments.push({
      id: "c-" + Math.random().toString(36).slice(2, 10),
      author: authorLabel(),
      created: now,
      updated: now,
      status: "open",
      anchor: anchor,
      body: body,
      replies: []
    });
    persist();
    // Show the panel the first time, so the reviewer sees where comments live.
    if (!state.panelOpen) { togglePanel(); }
    if (state.autosaveState === "on") { toast("Comment added"); } else { beginAutosave(); }
  }

  // --- panel --------------------------------------------------------------

  /* Lucide-style inline SVG, stroke 1.5, currentColor — no emoji or text glyphs as icons. */
  var ICONS = {
    chevronUp: '<path d="m18 15-6-6-6 6"/>',
    help: '<circle cx="12" cy="12" r="10"/><path d="M9.1 9a3 3 0 0 1 5.8 1c0 2-3 3-3 3"/>' +
      '<path d="M12 17h.01"/>',
    moon: '<path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"/>',
    sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4' +
      'M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>',
    eye: '<path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7-10-7-10-7Z"/><circle cx="12" cy="12" r="3"/>',
    pencil: '<path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z"/>',
    user: '<path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/>',
    close: '<path d="M18 6 6 18M6 6l12 12"/>',
    message: '<path d="M21 11.5a8.4 8.4 0 0 1-9 8.4 8.4 8.4 0 0 1-3.8-.9L3 21l1.9-5.2A8.4 8.4 0 0 1 4 11.5' +
      'a8.4 8.4 0 0 1 8.5-8.4h.5a8.4 8.4 0 0 1 8 8Z"/>'
  };

  function icon(name) {
    return '<svg class="anno-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" ' +
      'stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
      ICONS[name] + "</svg>";
  }

  function buildChrome() {
    // The launcher only exists while the panel is closed, and the same controls live in the panel
    // header while it is open. Two hosts, never both on screen — a floating bar layered over the
    // panel header is what covered the title before.
    var launcher = document.createElement("div");
    launcher.className = "anno-launcher";
    launcher.innerHTML =
      '<button type="button" class="anno-btn anno-icon-btn" data-act="theme" ' +
      'aria-label="Toggle dark mode"></button>' +
      '<button type="button" class="anno-btn anno-icon-btn" data-act="readonly" ' +
      'aria-label="Toggle reading mode"></button>' +
      '<button type="button" class="anno-btn primary anno-launch" data-act="toggle">' +
      icon("message") + "<span>Review</span><span class=\"anno-badge\" data-count>0</span></button>";
    document.body.appendChild(launcher);
    els.launcher = launcher;

    var panel = document.createElement("aside");
    panel.className = "anno-panel";
    panel.setAttribute("aria-label", "Review: open questions and comments");
    panel.innerHTML =
      '<header class="anno-panel-head">' +
      '<h2>Review <span class="anno-badge" data-count>0</span></h2>' +
      '<button type="button" class="anno-btn anno-icon-btn" data-act="theme" ' +
      'aria-label="Toggle dark mode"></button>' +
      '<button type="button" class="anno-btn anno-icon-btn" data-act="readonly" ' +
      'aria-label="Toggle reading mode"></button>' +
      '<button type="button" class="anno-btn anno-icon-btn" data-act="close" ' +
      'aria-label="Close panel">' + icon("close") + "</button>" +
      "</header>" +
      '<div class="anno-panel-list">' +
      '<section class="anno-questions" hidden></section>' +
      '<h3 class="anno-group-title">Comments</h3>' +
      '<div class="anno-comment-list"></div>' +
      "</div>" +
      '<footer class="anno-panel-foot">' +
      '<button type="button" class="anno-identity" data-act="identity" ' +
      'aria-label="Change your name">' + icon("user") + "<span data-who>Set your name</span></button>" +
      '<div class="anno-actions">' +
      '<button type="button" class="anno-btn primary" data-act="save">Save file</button>' +
      '<button type="button" class="anno-btn" data-act="send">Copy for agent</button>' +
      '<button type="button" class="anno-btn" data-act="export">Export JSON</button>' +
      "</div>" +
      '<button type="button" class="anno-autosave" data-act="autosave"></button>' +
      '<p class="anno-storage-warn" hidden>This browser will not remember your name between ' +
      "windows.</p>" +
      "</footer>";
    document.body.appendChild(panel);
    els.panel = panel;
    els.list = panel.querySelector(".anno-comment-list");
    els.questions = panel.querySelector(".anno-questions");

    eachAction("theme", toggleTheme);
    eachAction("readonly", toggleReadOnly);
    eachAction("toggle", togglePanel);
    eachAction("close", togglePanel);
    eachAction("identity", function () { openSettings(null); });
    eachAction("save", saveAnnotatedFile);
    eachAction("send", copyForAgent);
    eachAction("export", exportJson);
    eachAction("autosave", function () {
      if (state.autosaveState === "on") { return; }
      if (state.autosaveState === "blocked") { resumeAutosave(); return; }
      state.autosaveDeclined = false;
      beginAutosave();
    });
  }

  function eachAction(name, handler) {
    Array.prototype.slice.call(
      document.querySelectorAll('.anno-launcher [data-act="' + name + '"], ' +
        '.anno-panel [data-act="' + name + '"]')
    ).forEach(function (button) { button.addEventListener("click", handler); });
  }

  function togglePanel() {
    state.panelOpen = !state.panelOpen;
    els.panel.classList.toggle("is-open", state.panelOpen);
    document.body.classList.toggle("anno-panel-open", state.panelOpen);
    els.launcher.hidden = state.panelOpen;
  }

  function select(id) {
    state.activeId = id;
    if (!state.panelOpen) { togglePanel(); }
    render();
    var mark = document.querySelector('mark.anno[data-comment-id="' + id + '"]');
    if (mark) { mark.scrollIntoView({ block: "center", behavior: "smooth" }); }
    var item = els.list.querySelector('[data-comment-id="' + id + '"]');
    if (item) { item.scrollIntoView({ block: "nearest" }); }
  }

  function render() {
    // The badge sits on a button labelled "Review", which opens a panel holding both the
    // document's open questions and the reviewer comments. Counting only one of them would make
    // a 0 appear next to a panel that still has items in it.
    var open = state.comments.filter(function (c) { return c.status === "open"; }).length;
    var total = open + questionNodes().length;
    Array.prototype.slice.call(document.querySelectorAll("[data-count]")).forEach(function (node) {
      node.textContent = String(total);
    });

    var dark = state.prefs.theme === "dark";
    Array.prototype.slice.call(document.querySelectorAll('[data-act="theme"]')).forEach(
      function (button) {
        button.innerHTML = icon(dark ? "sun" : "moon");
        button.setAttribute("aria-pressed", String(dark));
        button.title = dark ? "Switch to light mode" : "Switch to dark mode";
      }
    );
    Array.prototype.slice.call(document.querySelectorAll('[data-act="readonly"]')).forEach(
      function (button) {
        button.innerHTML = icon(state.prefs.readOnly ? "pencil" : "eye");
        button.setAttribute("aria-pressed", String(state.prefs.readOnly));
        button.title = state.prefs.readOnly
          ? "Back to reviewing — show comments"
          : "Reading mode — hide all comments";
        button.classList.toggle("is-on", state.prefs.readOnly);
      }
    );

    var saveButton = els.panel.querySelector('[data-act="save"]');
    saveButton.textContent = hasUnsavedChanges() ? "Save file •" : "Save file";
    saveButton.classList.toggle("is-dirty", hasUnsavedChanges());

    var who = els.panel.querySelector("[data-who]");
    who.textContent = state.identity ? authorLabel() : "Set your name";
    els.panel.querySelector('[data-act="identity"]').classList.toggle("is-unset", !state.identity);
    els.panel.querySelector(".anno-storage-warn").hidden = state.storage;
    var autosave = els.panel.querySelector('[data-act="autosave"]');
    autosave.textContent = autosaveLabel();
    autosave.dataset.state = state.autosaveState;
    autosave.disabled = state.autosaveState === "unsupported";

    els.list.innerHTML = "";
    if (!state.comments.length) {
      els.list.innerHTML = '<p class="anno-empty">Select text, then right-click it to comment. '
        + 'Open questions below have an <strong>Answer</strong> button.</p>';
      return;
    }
    state.comments.forEach(function (comment) {
      els.list.appendChild(renderItem(comment));
    });
  }

  function renderItem(comment) {
    var item = document.createElement("article");
    item.className = "anno-item" + (comment.id === state.activeId ? " is-active" : "");
    item.dataset.status = comment.status || "open";
    item.dataset.commentId = comment.id;

    var meta = document.createElement("div");
    meta.className = "anno-item-meta";
    var chip = document.createElement("span");
    chip.className = "anno-chip";
    chip.dataset.status = comment.status || "open";
    chip.textContent = comment.status || "open";
    meta.appendChild(chip);
    var byline = document.createElement("span");
    byline.textContent = comment.author + " · " + shortDate(comment.created);
    meta.appendChild(byline);
    if (state.orphans[comment.id]) {
      var orphan = document.createElement("span");
      orphan.className = "anno-orphan";
      orphan.textContent = "text not found";
      orphan.title = "The quoted text changed since this comment was written.";
      meta.appendChild(orphan);
    }
    item.appendChild(meta);

    if (comment.anchor && comment.anchor.quote) {
      var quote = document.createElement("p");
      quote.className = "anno-item-quote";
      quote.textContent = truncate(comment.anchor.quote, 120);
      item.appendChild(quote);
    }

    var body = document.createElement("div");
    body.className = "anno-item-body";
    body.textContent = comment.body;
    item.appendChild(body);

    (comment.replies || []).forEach(function (reply) {
      var node = document.createElement("div");
      node.className = "anno-reply";
      node.textContent = reply.author + ": " + reply.body;
      item.appendChild(node);
    });

    var actions = document.createElement("div");
    actions.className = "anno-item-actions";
    actions.appendChild(action("Reply", function () { replyTo(comment); }));
    actions.appendChild(action(
      comment.status === "resolved" ? "Reopen" : "Resolve",
      function () { setStatus(comment, comment.status === "resolved" ? "open" : "resolved"); }
    ));
    var remove = action("Delete", function () {
      confirmModal(
        "Delete this comment?",
        "This removes it from the file the next time you save. It cannot be undone.",
        "Delete",
        function () {
          state.comments = state.comments.filter(function (c) { return c.id !== comment.id; });
          persist();
        }
      );
    });
    remove.classList.add("danger");
    actions.appendChild(remove);
    item.appendChild(actions);

    item.addEventListener("click", function () { select(comment.id); });
    return item;
  }

  function action(label, handler) {
    var button = document.createElement("button");
    button.type = "button";
    button.className = "anno-btn";
    button.textContent = label;
    button.addEventListener("click", function (event) { event.stopPropagation(); handler(); });
    return button;
  }

  function replyTo(comment) {
    ensureIdentity(function () {
      openModal({
        title: "Reply to " + comment.author,
        bodyHtml: '<label>Your reply<textarea data-field="reply" rows="4"></textarea></label>',
        confirmLabel: "Add reply",
        onOpen: function (panel) { panel.querySelector("[data-field=reply]").focus(); },
        onConfirm: function (panel) {
          var body = panel.querySelector("[data-field=reply]").value.trim();
          if (!body) { return false; }
          comment.replies = comment.replies || [];
          comment.replies.push({
            author: authorLabel(), created: new Date().toISOString(), body: body
          });
          comment.updated = new Date().toISOString();
          persist();
        }
      });
    });
  }

  function setStatus(comment, status) {
    comment.status = status;
    comment.updated = new Date().toISOString();
    persist();
  }

  // --- autosave -----------------------------------------------------------
  // A file:// page cannot write to itself, but Chromium can hand back a writable handle after one
  // explicit save. That handle survives in IndexedDB, so from then on every change writes straight
  // to the file the reviewer was sent. Everywhere else, autosave keeps the browser copy and the
  // footer says plainly that the file itself still needs an explicit save.

  function openHandleDb() {
    return new Promise(function (resolve, reject) {
      if (!window.indexedDB) { reject(new Error("no indexedDB")); return; }
      var request = indexedDB.open(HANDLE_DB, 1);
      request.onupgradeneeded = function () {
        request.result.createObjectStore(HANDLE_STORE);
      };
      request.onsuccess = function () { resolve(request.result); };
      request.onerror = function () { reject(request.error); };
    });
  }

  /* Keyed by URL, not filename. `design.html` occurs once per agent-spec slug, so a filename key
     made every design document share one handle and autosave into whichever file was picked last. */
  function handleKey() { return "handle:" + location.origin + location.pathname; }

  function storeHandle(handle) {
    return openHandleDb().then(function (db) {
      var tx = db.transaction(HANDLE_STORE, "readwrite");
      tx.objectStore(HANDLE_STORE).put(handle, handleKey());
      return new Promise(function (resolve) { tx.oncomplete = resolve; });
    }).catch(function () { /* autosave-to-file simply stays unavailable */ });
  }

  function loadHandle() {
    return openHandleDb().then(function (db) {
      return new Promise(function (resolve) {
        var request = db.transaction(HANDLE_STORE, "readonly")
          .objectStore(HANDLE_STORE).get(handleKey());
        request.onsuccess = function () { resolve(request.result || null); };
        request.onerror = function () { resolve(null); };
      });
    }).catch(function () { return null; });
  }

  function adoptHandle(handle, silent) {
    state.fileHandle = handle;
    storeHandle(handle);
    setAutosaveState("on");
    if (!silent) { toast("Autosave on — changes now write straight to the file"); }
  }

  function setAutosaveState(value) {
    state.autosaveState = value;
    render();
  }

  function scheduleAutosave() {
    writeLocal();
    if (state.autosaveTimer) { clearTimeout(state.autosaveTimer); }
    state.autosaveTimer = setTimeout(runAutosave, AUTOSAVE_DELAY);
  }

  function runAutosave() {
    state.autosaveTimer = null;
    if (!state.fileHandle || !hasUnsavedChanges()) { return; }
    state.fileHandle.createWritable().then(function (writable) {
      return writable.write(annotatedHtml()).then(function () { return writable.close(); });
    }).then(function () {
      state.lastSavedAt = new Date();
      markSaved();
    }).catch(function () {
      // Permission lapsed (a new session, or the file moved) — stop claiming it is saving.
      state.fileHandle = null;
      setAutosaveState("blocked");
    });
  }

  function resumeAutosave() {
    loadHandle().then(function (handle) {
      if (!handle || !handle.requestPermission) { return; }
      handle.requestPermission({ mode: "readwrite" }).then(function (result) {
        if (result === "granted") { adoptHandle(handle, false); runAutosave(); }
      });
    });
  }

  function restoreAutosave() {
    if (!window.showSaveFilePicker) { setAutosaveState("unsupported"); return; }
    loadHandle().then(function (handle) {
      if (!handle || !handle.queryPermission) { setAutosaveState("off"); return; }
      handle.queryPermission({ mode: "readwrite" }).then(function (result) {
        if (result === "granted") { adoptHandle(handle, true); return; }
        // A stored handle whose permission lapsed needs a user gesture to renew, and only that.
        // Taking the reviewer's next click means autosave just resumes; no button to find.
        setAutosaveState("blocked");
        armPermissionResume(handle);
      }).catch(function () { setAutosaveState("off"); });
    });
  }

  function armPermissionResume(handle) {
    var once = function () {
      document.removeEventListener("click", once, true);
      document.removeEventListener("keydown", once, true);
      handle.requestPermission({ mode: "readwrite" }).then(function (result) {
        if (result === "granted") { adoptHandle(handle, true); runAutosave(); }
      }).catch(function () { /* stays blocked; the status line says so */ });
    };
    document.addEventListener("click", once, true);
    document.addEventListener("keydown", once, true);
  }

  /* The first comment is when autosave should start, and it is already a user gesture — which is
     the one thing the file picker requires. Asking for a separate "save once" click first added a
     step that taught the reviewer nothing. Declining is remembered for the session so the picker
     does not reappear on every comment. */
  function beginAutosave() {
    if (state.autosaveState !== "off" || state.autosaveDeclined) { return; }
    if (!window.showSaveFilePicker) { return; }
    window.showSaveFilePicker({
      suggestedName: fileName(),
      types: [{ description: "HTML", accept: { "text/html": [".html"] } }]
    }).then(function (handle) {
      adoptHandle(handle, true);
      runAutosave();
      toast("Autosave on — comments now write straight into this file");
    }).catch(function () {
      state.autosaveDeclined = true;
      setAutosaveState("off");
    });
  }

  function autosaveLabel() {
    if (state.autosaveState === "on") {
      return state.lastSavedAt
        ? "Autosaving to this file · saved " + clockTime(state.lastSavedAt)
        : "Autosaving to this file";
    }
    if (state.autosaveState === "blocked") {
      return "Autosave resumes on your next click";
    }
    if (state.autosaveState === "unsupported") {
      return "Changes are kept in this browser. Use Save file to update the document.";
    }
    if (state.autosaveDeclined) {
      return "Autosave off — click to write to this file";
    }
    return "Autosave starts with your first comment";
  }

  function clockTime(date) {
    return String(date.getHours()).padStart(2, "0") + ":" +
      String(date.getMinutes()).padStart(2, "0");
  }

  // --- outputs ------------------------------------------------------------

  function serialize() { return JSON.stringify(state.comments, null, 2); }

  function hasUnsavedChanges() {
    if (!state.comments.length) { return false; }
    return serialize() !== state.savedSnapshot;
  }

  /* Write the current comments into a copy of this document and hand it back as a file. */
  function annotatedHtml() {
    var clone = document.documentElement.cloneNode(true);
    Array.prototype.slice.call(clone.querySelectorAll(
      "mark.anno, .anno-panel, .anno-toggle, .anno-composer, .anno-menu, .anno-tip, .anno-toast"
    )).forEach(function (node) {
      if (node.tagName === "MARK") {
        var badge = node.querySelector(".anno-count");
        if (badge) { badge.remove(); }
        while (node.firstChild) { node.parentNode.insertBefore(node.firstChild, node); }
      }
      node.remove();
    });
    var store = clone.querySelector("#" + DATA_ID);
    if (!store) {
      store = clone.ownerDocument.createElement("script");
      store.type = "application/json";
      store.id = DATA_ID;
      clone.querySelector("body").appendChild(store);
    }
    store.textContent = serialize();
    return "<!doctype html>\n" + clone.outerHTML;
  }

  function download(name, text, mime) {
    var blob = new Blob([text], { type: mime });
    var url = URL.createObjectURL(blob);
    var link = document.createElement("a");
    link.href = url;
    link.download = name;
    document.body.appendChild(link);
    link.click();
    link.remove();
    setTimeout(function () { URL.revokeObjectURL(url); }, 2000);
  }

  function baseName() {
    var file = decodeURIComponent((location.pathname.split("/").pop() || "design.html"));
    return file.replace(/\.html?$/i, "");
  }

  function saveAnnotatedFile() {
    var text = annotatedHtml();
    var name = fileName();
    // Chromium exposes a real save dialog, so a reviewer can overwrite the file they were sent.
    if (window.showSaveFilePicker) {
      window.showSaveFilePicker({
        suggestedName: name,
        types: [{ description: "HTML", accept: { "text/html": [".html"] } }]
      }).then(function (handle) {
        return handle.createWritable().then(function (writable) {
          return writable.write(text).then(function () { return writable.close(); });
        }).then(function () { adoptHandle(handle, true); });
      }).then(function () {
        state.lastSavedAt = new Date();
        markSaved();
        toast("Saved — autosave is on for this file from now on.");
      }).catch(function (err) {
        // Never fail silently: AbortError covers both "reviewer closed the dialog" and "this
        // browser refused the picker", and the second case would otherwise lose the comments.
        download(name, text, "text/html");
        markSaved();
        toast(
          err && err.name === "AbortError"
            ? "Save dialog closed — downloaded " + name + " instead"
            : "Downloaded " + name
        );
      });
      return;
    }
    download(name, text, "text/html");
    markSaved();
    toast("Downloaded " + name + " — send that file back");
  }

  function markSaved() {
    state.savedSnapshot = serialize();
    render();
  }

  function exportJson() {
    download(baseName() + ".comments.json", serialize(), "application/json");
  }

  /* The page cannot reach the agent (no network, by design), so the button produces a prompt that
     stands entirely on its own: an agent receiving only this text knows which document to edit,
     that the markdown is the source of truth, and exactly what each reviewer asked for. */
  function agentPrompt(pending) {
    var title = CONFIG.title || document.title;
    var lines = [
      "Apply the review comments below to the design document \"" + title + "\".",
      ""
    ];
    if (CONFIG.jira) { lines.push("Jira: " + CONFIG.jira); }
    if (CONFIG.sourcePath) { lines.push("Markdown source: " + CONFIG.sourcePath); }
    lines.push("Rendered file the comments came from: " + fileName());
    lines.push("");
    lines.push("How to apply them:");
    lines.push(
      "1. The markdown file is the source of truth. Edit it — never hand-edit the HTML."
    );
    lines.push(
      "2. Re-render afterwards so the HTML matches, carrying the existing comments over:"
    );
    lines.push(
      "   python3 <arch-design-skill>/scripts/render_design_html.py <design.md> --comments " +
      fileName()
    );
    lines.push(
      "3. Keep the design document free of any plan: no task IDs, checkboxes, phases or ordering."
    );
    lines.push(
      "4. Where a comment asks a question rather than a change, answer it in the document as a " +
      "`Q:` line or resolve it in the relevant section."
    );
    lines.push(
      "5. Report back per comment: what you changed, or why you did not."
    );
    lines.push("");
    lines.push("Comments (" + pending.length + "):");
    lines.push("");

    pending.forEach(function (comment, index) {
      var anchor = comment.anchor || {};
      lines.push("### " + (index + 1) + ". " + comment.author +
        (anchor.section ? " — section `#" + anchor.section + "`" : ""));
      if (anchor.quote) {
        lines.push("Quoted text: " + JSON.stringify(truncate(anchor.quote, 300)));
      }
      lines.push("Comment: " + comment.body);
      (comment.replies || []).forEach(function (reply) {
        lines.push("Reply from " + reply.author + ": " + reply.body);
      });
      lines.push("");
    });
    return lines.join("\n");
  }

  function fileName() {
    return decodeURIComponent(location.pathname.split("/").pop() || "design.html");
  }

  function copyForAgent() {
    var pending = state.comments.filter(function (c) { return c.status === "open"; });
    if (!pending.length) { toast("No open comments to send"); return; }
    var payload = agentPrompt(pending);

    copyText(payload).then(function () {
      markSent(pending);
      toast("Copied a ready-to-paste prompt for " + pending.length + " comment(s)");
    }).catch(function () {
      openModal({
        title: "Copy this prompt for the agent",
        bodyHtml: '<p class="anno-modal-note">Your browser blocked clipboard access. Select all ' +
          "and copy, then paste it to the agent.</p>" +
          '<label><textarea data-field="payload" rows="12"></textarea></label>',
        confirmLabel: "Done",
        onOpen: function (panel) {
          var box = panel.querySelector("[data-field=payload]");
          box.value = payload;
          box.focus();
          box.select();
        },
        onConfirm: function () { markSent(pending); }
      });
    });
  }

  function markSent(pending) {
    pending.forEach(function (comment) {
      comment.status = "sent";
      comment.updated = new Date().toISOString();
    });
    persist();
  }

  function copyText(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(text);
    }
    return Promise.reject(new Error("clipboard unavailable"));
  }

  // --- helpers ------------------------------------------------------------

  function truncate(text, max) {
    return text.length > max ? text.slice(0, max - 1) + "…" : text;
  }

  function shortDate(iso) {
    if (!iso) { return ""; }
    return iso.slice(0, 10);
  }

  function toast(message) {
    var existing = document.querySelector(".anno-toast");
    if (existing) { existing.remove(); }
    var node = document.createElement("div");
    node.className = "anno-toast";
    node.textContent = message;
    document.body.appendChild(node);
    setTimeout(function () { node.remove(); }, 3200);
  }

  function persist() {
    scheduleAutosave();
    paint();
    render();
    updateToc();
  }

  // --- boot ---------------------------------------------------------------

  function init() {
    state.storage = storageWorks();
    state.prefs = loadPrefs();
    state.comments = merge(readEmbedded(), readLocal());
    state.identity = loadIdentity();
    state.savedSnapshot = JSON.stringify(readEmbedded(), null, 2);
    buildChrome();
    applyPrefs();
    paint();
    render();
    renderQuestions();
    updateToc();
    watchScroll();
    restoreAutosave();
    document.addEventListener("keydown", function (event) {
      if (event.key === "Escape" && els.menu) { hideMenu(); return; }
      if (event.target.matches("input, textarea")) { return; }
      // Right-click has no keyboard equivalent, so the composer keeps a direct shortcut.
      if (event.key.toLowerCase() === "m" && (event.metaKey || event.ctrlKey) && event.altKey) {
        var selected = selectedRange();
        if (selected && !state.prefs.readOnly) { event.preventDefault(); openComposer(selected); }
        return;
      }
      // The launcher buttons are gone; [ and ] are now the only way to step between questions.
      if (event.key === "]") { stepQuestion(1); }
      if (event.key === "[") { stepQuestion(-1); }
    });
    if (state.comments.length && !state.prefs.readOnly) { togglePanel(); }
    // Ask up front so a reviewer is never mid-thought when the dialog appears.
    if (!state.identity && !state.prefs.readOnly) { openSettings(null); }

    document.addEventListener("contextmenu", onContextMenu);
    document.addEventListener("click", function (event) {
      if (els.menu && !els.menu.contains(event.target)) { hideMenu(); }
      if (els.tip && !els.tip.contains(event.target)) { hideTip(); }
      if (els.composer && !els.composer.contains(event.target)) { hideComposer(); }
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();

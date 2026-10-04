// Parse every mermaid block of a design.md with the same vendored mermaid the HTML uses.
// A diagram that fails here renders as "Syntax error in text" in the browser, so this is the
// only way to catch it without opening the file. Requires jsdom (DOMPurify needs a real DOM).
// Usage: node check_mermaid.mjs <blocks.json>   — blocks.json is a JSON array of sources.
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { createRequire } from "module";

const here = path.dirname(fileURLToPath(import.meta.url));
// jsdom is installed into <skill>/.mermaid-check, which is not on this file's resolution
// path, so require it from there explicitly rather than as a bare specifier.
const require = createRequire(path.join(here, "..", ".mermaid-check", "package.json"));
const { JSDOM } = require("jsdom");
const dom = new JSDOM("<!doctype html><body></body>", { pretendToBeVisual: true });
for (const key of ["window", "document", "navigator", "Node", "Element", "HTMLElement",
                   "SVGElement", "DOMParser", "NodeFilter", "getComputedStyle",
                   "MutationObserver", "trustedTypes"]) {
  try { globalThis[key] = dom.window[key]; } catch { /* getter-only in newer node */ }
}

const bundle = fs.readFileSync(path.join(here, "..", "assets", "mermaid.min.js"), "utf8");
// The bundle is a strict-mode script, so its top-level `var` never reaches globalThis under
// indirect eval. Seed the namespace and drop the declaration so the bundle's own final line works.
globalThis.__esbuild_esm_mermaid_nm = {};
(0, eval)(bundle.replace("var __esbuild_esm_mermaid_nm;", ""));

const blocks = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
let failed = 0;
for (const [i, source] of blocks.entries()) {
  try {
    await globalThis.mermaid.parse(source);
  } catch (err) {
    failed++;
    const msg = String(err?.message ?? err).split("\n").slice(0, 8).join("\n");
    console.error(`mermaid block ${i + 1} failed to parse:\n${msg}\n`);
  }
}
if (failed) console.error(`${failed} of ${blocks.length} mermaid blocks are invalid.`);
process.exit(failed ? 1 : 0);

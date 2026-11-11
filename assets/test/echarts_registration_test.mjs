// The app bundles a trimmed ECharts (assets/js/echarts.mjs). A series type or
// component missing from that file does not raise an error; the chart just draws
// without it. This test renders every option shape the app uses with both the
// full library and the trimmed build and requires identical SVG output.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const fixture = join(dirname(fileURLToPath(import.meta.url)), "fixtures", "echarts_render.mjs");

const render = (build) =>
  JSON.parse(execFileSync(process.execPath, [fixture, build], { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }));

const full = render("full");
const trimmed = render("trimmed");

test("the trimmed build exposes the API the app calls", () => {
  for (const [name, type] of trimmed.api) {
    assert.equal(type, "function", `echarts.${name} is missing from the trimmed build`);
  }
});

test("rendering with the trimmed build produces no ECharts warnings", () => {
  assert.deepEqual(trimmed.warnings, []);
  assert.deepEqual(full.warnings, []);
});

for (const name of Object.keys(full.rendered)) {
  test(`${name} renders the same with the trimmed build`, () => {
    assert.ok(full.rendered[name].includes("<path"), "fixture drew nothing with the full build");
    assert.equal(trimmed.rendered[name], full.rendered[name]);
  });
}

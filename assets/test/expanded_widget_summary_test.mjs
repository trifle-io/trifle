import assert from 'node:assert/strict';
import test from 'node:test';
import {execFileSync} from 'node:child_process';
import {mkdtempSync, rmSync} from 'node:fs';
import {createRequire} from 'node:module';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';

// Exercise the browser hook itself. Bundle its browser-style imports with the
// same esbuild binary installed by Mix, then load it without mounting a DOM.
const root = fileURLToPath(new URL('../../', import.meta.url));
const architecture = process.arch === 'x64' ? '64' : process.arch;
const esbuild = join(root, '_build', `esbuild-${process.platform}-${architecture}`);
const temporary = mkdtempSync(join(tmpdir(), 'trifle-summary-test-'));
let registerExpandedWidgetViewHook;
try {
  const bundle = join(temporary, 'hook.cjs');
  execFileSync(esbuild, [
    join(root, 'assets/js/widgets/dashboard_runtime/expanded_widget_view_hook.js'),
    '--bundle', '--platform=node', '--format=cjs', '--log-level=error', `--outfile=${bundle}`
  ]);
  ({registerExpandedWidgetViewHook} = createRequire(import.meta.url)(bundle));
} finally {
  rmSync(temporary, {recursive: true, force: true});
}

const hook = () => {
  const hooks = {};
  registerExpandedWidgetViewHook(hooks, {});
  return {...hooks.ExpandedWidgetView, tableRoot: {}, resolveSeriesColor: () => '#000'};
};

test('normalized summaries use percentages only for primary-axis series', () => {
  const view = hook();
  let rows;
  view.renderSummaryGrid = result => { rows = result; };
  const series = [
    {name: 'Count', data: [[1, 25], [2, 75]], unit: 'events'},
    {name: 'Other', y_axis: 'primary', data: [[1, 50]]},
    {name: 'Duration', y_axis: 'secondary', unit: 'ms', data: [[1, 200]]}
  ];
  view.renderTimeseriesTable({normalized: true, series});
  assert.deepEqual(rows.map(row => row.unit), ['%', '%', 'ms']);
  assert.deepEqual(rows.map(row => row.mean), [50, 50, 200]);
  view.renderTimeseriesTable({normalized: false, series});
  assert.deepEqual(rows.map(row => row.unit), ['events', undefined, 'ms']);
});

test('summary cells and tooltips attach percent signs without a space', () => {
  const column = hook().summaryNumericColumn('mean', 'Mean');
  for (const format of [column.valueFormatter, column.tooltipValueGetter]) {
    assert.equal(format({value: 12.5, data: {unit: '%'}}), '12.5%');
    assert.equal(format({value: 0, data: {unit: '%'}}), '0%');
    assert.equal(format({value: 12.5, data: {unit: 'ms'}}), '12.5 ms');
    assert.equal(format({value: 12.5, data: {}}), '12.5');
  }
  for (const value of [null, undefined, NaN, Infinity]) {
    assert.equal(column.valueFormatter({value, data: {unit: '%'}}), '—');
    assert.equal(column.tooltipValueGetter({value, data: {unit: '%'}}), '');
  }
});

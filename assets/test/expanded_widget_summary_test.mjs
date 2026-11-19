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
// CI runs these tests outside the app image, where Mix has installed nothing;
// it points ESBUILD_BIN at the same esbuild version instead.
const esbuild = process.env.ESBUILD_BIN ||
  join(root, '_build', `esbuild-${process.platform}-${architecture}`);
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

test('trace overview uses the shared summary columns for every measurement', () => {
  const view = hook();
  view.seriesColor = () => '#000';
  let rows, columns;
  view.renderSummaryGrid = (data, defs) => { rows = data; columns = defs; };
  view.renderTimeseriesTable({
    presentation: 'trace_overview', timezone: 'Asia/Dubai', states: ['success', 'error'],
    points: [
      {at: 0, count: 5, states: {success: 4, error: 1}, duration: 12.3456789, lines: 0},
      {at: 3600000, count: 0, states: {success: 0, error: 0}, duration: null, lines: null}
    ]
  });
  assert.deepEqual(columns.map(column => column.headerName),
    ['Path', 'Mean', 'Sum', 'Max', 'Min', 'Oldest', 'Latest']);
  assert.deepEqual(columns.map(column => column.field),
    ['path', 'mean', 'sum', 'max', 'min', 'oldest', 'latest']);
  assert.equal(columns[0].pinned, 'left');
  assert.deepEqual(rows.find(row => row.path === 'Traces'), {
    path: 'Traces', color: '#000', unit: undefined,
    mean: 2.5, sum: 5, max: 5, min: 0, oldest: 5, latest: 0
  });
  assert.equal(rows.find(row => row.path === 'Success').sum, 4);
  assert.equal(rows.find(row => row.path === 'Error').sum, 1);
  assert.deepEqual(rows.find(row => row.path === 'Avg lines'), {
    path: 'Avg lines', color: '#000', unit: undefined,
    mean: 0, sum: 0, max: 0, min: 0, oldest: 0, latest: 0
  });
  const duration = rows.find(row => row.path === 'Avg duration (ms)');
  for (const field of ['mean', 'sum', 'max', 'min', 'oldest', 'latest']) {
    assert.equal(duration[field], 12.3456789, `missing duration buckets are skipped for ${field}`);
    assert.equal(rows.find(row => row.path === 'Duration samples')[field], null);
  }
});

test('trace summaries cover the entire timeframe with a fixed number of columns', () => {
  const view = hook();
  view.seriesColor = () => '#000';
  let rows, columns;
  view.renderSummaryGrid = (data, defs) => { rows = data; columns = defs; };
  const data = {presentation: 'trace_overview', states: [],
    points: Array.from({length: 1440}, (_, index) => ({at: index * 600000, count: index}))};
  view.renderTimeseriesTable(data);
  assert.equal(columns.length, 7);
  assert.deepEqual(rows.find(row => row.path === 'Traces'), {
    path: 'Traces', color: '#000', unit: undefined,
    mean: 719.5, sum: 1036080, max: 1439, min: 0, oldest: 0, latest: 1439
  });

  view.renderTimeseriesTable({...data, points: data.points.slice(0, 3)});
  assert.equal(columns.length, 7);
  assert.deepEqual(rows.find(row => row.path === 'Traces'), {
    path: 'Traces', color: '#000', unit: undefined,
    mean: 1, sum: 3, max: 2, min: 0, oldest: 0, latest: 2
  });
});

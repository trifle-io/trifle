import assert from 'node:assert/strict';
import test from 'node:test';
import {
  createTraceOverviewPreferencesHook,
  readTraceOverviewRows,
  writeTraceOverviewRows
} from '../js/hooks/trace_overview_preferences_hook.mjs';

test('row preferences default to three and restore valid browser cookies', () => {
  assert.equal(readTraceOverviewRows('other=value; trifle_trace_overview_rows=5'), 5);
  for (const value of ['', 'bad', '0', '-1', '3.5', '101']) {
    assert.equal(readTraceOverviewRows(`trifle_trace_overview_rows=${value}`), 3);
  }
  assert.equal(readTraceOverviewRows(''), 3);
});

test('row changes persist in a year-long browser cookie and survive another read', () => {
  const document = {};
  writeTraceOverviewRows(4, document);
  assert.equal(document.cookie, 'trifle_trace_overview_rows=4; Max-Age=31536000; Path=/; SameSite=Lax');
  assert.equal(readTraceOverviewRows(document.cookie), 4);
  assert.doesNotThrow(() => writeTraceOverviewRows(4, {
    set cookie(_) { throw new Error('Cookies unavailable'); }
  }));
});

test('responsive layout changes send only new column counts and keep row preferences', () => {
  const document = {}, handlers = {}, events = [];
  let resize, disconnected = false, columns = '100px 100px 100px';
  const grid = {clientWidth: 300};
  const view = {
    ...createTraceOverviewPreferencesHook({
      document,
      getComputedStyle: () => ({gridTemplateColumns: columns}),
      ResizeObserver: class {
        constructor(callback) { resize = callback; }
        observe() {}
        disconnect() { disconnected = true; }
      }
    }),
    el: {dataset: {overviewColumns: '3'}, querySelector: () => grid},
    handleEvent: (name, handler) => { handlers[name] = handler; },
    pushEvent: (name, payload) => { events.push([name, payload]); }
  };

  view.mounted();
  assert.deepEqual(events, []);
  columns = '100px 100px';
  resize();
  view.updated();
  assert.deepEqual(events, [['overview_columns', {columns: 2}]]);

  columns = '100px';
  resize();
  assert.deepEqual(events[1], ['overview_columns', {columns: 1}]);
  assert.equal(document.cookie, undefined);
  handlers.trace_overview_rows({rows: 5});
  assert.equal(readTraceOverviewRows(document.cookie), 5);

  grid.clientWidth = 0;
  columns = '100px 100px 100px';
  resize();
  assert.equal(events.length, 2);
  view.destroyed();
  assert.equal(disconnected, true);
});

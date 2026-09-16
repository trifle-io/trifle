import assert from 'node:assert/strict';
import test from 'node:test';
import {createGridPageLoadingHandlers} from '../js/widgets/dashboard_runtime/shared/grid_page_loading.mjs';

const event = (kind) => ({detail: {kind}});

const setup = (hideOnPatch) => {
  const classes = new Set(['opacity-100']);
  const calls = [];
  const hook = {
    el: {
      dataset: {hideOnPatch},
      classList: {
        add: (...values) => values.forEach(value => classes.add(value)),
        remove: (...values) => values.forEach(value => classes.delete(value))
      }
    },
    _suppressSave: false,
    _gridHiddenForLoading: false,
    syncServerRenderedItems: () => calls.push('sync'),
    _applyResponsiveGrid: () => calls.push('responsive'),
    _scheduleDeferredResize: () => calls.push('resize')
  };
  const handlers = createGridPageLoadingHandlers(hook, callback => callback());
  return {hook, classes, calls, handlers};
};

test('trace reference and layout patches never hide or redraw the existing activity grid', () => {
  const {hook, classes, calls, handlers} = setup('false');
  for (let index = 0; index < 3; index++) {
    handlers.start(event('patch'));
    assert.deepEqual([...classes], ['opacity-100']);
    assert.equal(hook._gridHiddenForLoading, false);
    handlers.stop(event('patch'));
  }
  assert.deepEqual([...classes], ['opacity-100']);
  assert.equal(hook._suppressSave, false);
  assert.deepEqual(calls, []);
});

test('ordinary dashboard grids keep their existing patch loading behavior', () => {
  for (const setting of [undefined, 'true']) {
    const {hook, classes, calls, handlers} = setup(setting);
    handlers.start(event('patch'));
    assert.ok(classes.has('opacity-0') && classes.has('pointer-events-none'));
    assert.equal(hook._suppressSave, true);
    handlers.stop(event('patch'));
    assert.deepEqual([...classes], ['opacity-100']);
    assert.equal(hook._suppressSave, false);
    assert.deepEqual(calls, ['sync', 'responsive', 'resize']);
  }
});

test('redirects still hide the traces grid and restore it on completion', () => {
  const {hook, classes, calls, handlers} = setup('false');
  handlers.start(event('redirect'));
  assert.ok(classes.has('opacity-0'));
  assert.equal(hook._gridHiddenForLoading, true);
  handlers.stop(event('redirect'));
  assert.deepEqual([...classes], ['opacity-100']);
  assert.deepEqual(calls, ['sync', 'responsive', 'resize']);
});

test('unrelated loading events do not hide or resync charts', () => {
  for (const setting of [undefined, 'false']) {
    const {classes, calls, handlers} = setup(setting);
    handlers.start(event('element'));
    handlers.stop(event('element'));
    assert.deepEqual([...classes], ['opacity-100']);
    assert.deepEqual(calls, []);
  }
});

test('a grid already hidden for navigation is restored even on a different stop kind', () => {
  const {hook, classes, handlers} = setup('false');
  handlers.start(event('redirect'));
  handlers.stop(event('patch'));
  assert.deepEqual([...classes], ['opacity-100']);
  assert.equal(hook._gridHiddenForLoading, false);
  assert.equal(hook._suppressSave, false);
});

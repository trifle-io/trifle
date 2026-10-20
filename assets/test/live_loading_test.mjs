import assert from 'node:assert/strict';
import test from 'node:test';
import {registerLiveLoading} from '../js/live_loading.mjs';

const setup = () => {
  const listeners = new Map();
  const calls = [];
  const socket = {
    onClose(callback) { this.close = callback; },
    onError(callback) { this.error = callback; }
  };
  const window = {addEventListener: (name, callback) => listeners.set(name, callback)};
  registerLiveLoading({
    window,
    liveSocket: {getSocket: () => socket},
    topbar: {show: delay => calls.push(['show', delay]), hide: () => calls.push(['hide'])}
  });
  const dispatch = (name, event = {}) => listeners.get(name)?.(event);
  const push = (eventType = 'click', target = {isConnected: true}) => {
    let resolve, reject;
    const loadingComplete = new Promise((ok, error) => { resolve = ok; reject = error; });
    const event = {target, detail: {eventType, loadingComplete}};
    dispatch('phx:push', event);
    return {
      event, target,
      complete: async () => { resolve(); await loadingComplete; },
      fail: async () => { reject(); await loadingComplete.catch(() => {}); }
    };
  };
  return {calls, socket, dispatch, push};
};

test('clicks, form events, and hook pushes share the delayed global bar until their reply completes', async () => {
  for (const type of ['click', 'change', 'submit', 'hook']) {
    const {calls, push} = setup();
    const action = push(type);
    assert.deepEqual(calls, [['show', 300]]);
    await action.complete();
    assert.deepEqual(calls, [['show', 300], ['hide']]);
  }
});

test('overlapping actions keep the bar active until all have completed', async () => {
  const {calls, push, dispatch} = setup();
  const first = push(), second = push('hook');
  // A bubbled duplicate must not count the same promise twice.
  dispatch('phx:push', first.event);
  await second.complete();
  assert.deepEqual(calls, [['show', 300]]);
  await first.complete();
  assert.deepEqual(calls, [['show', 300], ['hide']]);
});

test('navigation and actions cannot hide each other\'s progress bar early', async () => {
  for (const navigationFinishesFirst of [true, false]) {
    const {calls, push, dispatch} = setup();
    dispatch('phx:page-loading-start');
    const action = push();
    if (navigationFinishesFirst) dispatch('phx:page-loading-stop');
    else await action.complete();
    assert.deepEqual(calls, [['show', 300]]);
    if (navigationFinishesFirst) await action.complete();
    else dispatch('phx:page-loading-stop');
    assert.deepEqual(calls, [['show', 300], ['hide']]);
  }
});

test('navigation discards actions whose elements were removed before a reply', () => {
  const {calls, push, dispatch} = setup();
  const action = push();
  dispatch('phx:page-loading-start');
  action.target.isConnected = false;
  dispatch('phx:page-loading-stop');
  assert.deepEqual(calls, [['show', 300], ['hide']]);
});

test('disconnects and page exit clear stale actions without affecting later requests', async () => {
  for (const reset of [state => state.socket.close(), state => state.socket.error(),
    state => state.dispatch('pagehide')]) {
    const state = setup();
    const old = state.push();
    reset(state);
    assert.deepEqual(state.calls, [['show', 300], ['hide']]);
    const current = state.push();
    await old.complete();
    assert.deepEqual(state.calls, [['show', 300], ['hide'], ['show', 300]]);
    await current.complete();
    assert.deepEqual(state.calls.at(-1), ['hide']);
  }
});

test('rejected completions clear progress and unrelated events are ignored', async () => {
  const {calls, push, dispatch} = setup();
  dispatch('phx:push', {});
  dispatch('phx:page-loading-stop');
  assert.deepEqual(calls, []);
  await push().fail();
  assert.deepEqual(calls, [['show', 300], ['hide']]);
});

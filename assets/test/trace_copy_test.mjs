import assert from 'node:assert/strict';
import test from 'node:test';
import {createTraceCopyHook} from '../js/hooks/trace_copy_hook.mjs';

const element = () => {
  const classes = new Set();
  return {
    dataset: {}, attributes: {}, listeners: {}, textContent: '', className: '',
    classList: {toggle: (name, on) => on ? classes.add(name) : classes.delete(name), contains: name => classes.has(name)},
    setAttribute(name, value) { this.attributes[name] = value; },
    addEventListener(name, handler) { this.listeners[name] = handler; },
    removeEventListener(name) { delete this.listeners[name]; }
  };
};

const setup = (writeText = async () => {}) => {
  const button = element(), icon = element(), success = element(), status = element(), content = element();
  const timers = new Map();
  const writes = [];
  content.textContent = 'Trace: jobs/Worker\nLoaded parts: 1/2\n[success/raw] ↳ 東京';
  status.dataset.copyErrorClass = 'error-popover';
  button.querySelector = () => icon;
  const targets = {'[data-copy-button]': button, '[data-copy-success]': success,
    '[data-copy-status]': status, '[data-copy-text]': content};
  const hook = {...createTraceCopyHook({
    getClipboard: () => ({writeText: text => { writes.push(text); return writeText(text); }}),
    setTimer: callback => { const id = timers.size + 1; timers.set(id, callback); return id; },
    clearTimer: id => timers.delete(id)
  }), el: {dataset: {copyReady: 'true'}, querySelector: selector => targets[selector]}};
  hook.mounted();
  return {hook, button, icon, success, status, content, writes, timers};
};

test('copies exact loaded text immediately and shows success only after clipboard completion', async () => {
  let complete;
  const state = setup(() => new Promise(resolve => { complete = resolve; }));
  const pending = state.button.listeners.click();
  assert.deepEqual(state.writes, [state.content.textContent]);
  assert.equal(state.button.disabled, true);
  assert.equal(state.icon.classList.contains('opacity-0'), false);
  assert.equal(state.status.textContent, '');
  complete();
  await pending;
  assert.equal(state.button.disabled, false);
  assert.equal(state.status.textContent, 'Trace copied.');
  assert.equal(state.icon.classList.contains('opacity-0'), true);
  assert.equal(state.success.classList.contains('hidden'), false);
  [...state.timers.values()][0]();
  assert.equal(state.icon.classList.contains('opacity-0'), false);
});

test('newly loaded content is read afresh on each click, without fetching additional parts', async () => {
  const state = setup();
  await state.hook.copyLoadedTrace();
  state.content.textContent += '\nLoaded second part';
  state.hook.updated();
  await state.hook.copyLoadedTrace();
  assert.equal(state.writes.length, 2);
  assert.equal(state.writes[1], state.content.textContent);
  assert.ok(!state.writes[0].includes('Loaded second part'));
});

test('reference control copies only its ID with independent labels and copied feedback', async () => {
  let complete;
  const state = setup(() => new Promise(resolve => { complete = resolve; }));
  state.hook.el.dataset.copyKind = 'reference';
  state.content.textContent = '01M2GF4HFJEPPRWCY4VW3GMBJN';
  state.hook.updated();
  assert.equal(state.button.attributes['aria-label'], 'Copy trace reference');
  const pending = state.button.listeners.click();
  assert.deepEqual(state.writes, ['01M2GF4HFJEPPRWCY4VW3GMBJN']);
  assert.equal(state.button.attributes['aria-label'], 'Copying trace reference…');
  complete();
  await pending;
  assert.equal(state.button.attributes.title, 'Trace reference copied');
  assert.equal(state.status.textContent, 'Trace reference copied.');
  assert.equal(state.success.classList.contains('hidden'), false);
  [...state.timers.values()][0]();
  assert.equal(state.button.attributes['aria-label'], 'Copy trace reference');
  assert.equal(state.status.textContent, '');
});

test('clipboard failure never claims success and permits a retry', async () => {
  let fail = true;
  const state = setup(async () => { if (fail) throw new Error('denied'); });
  await state.hook.copyLoadedTrace();
  assert.equal(state.success.classList.contains('hidden'), true);
  assert.match(state.status.textContent, /Could not copy/);
  assert.equal(state.status.className, 'error-popover');
  assert.equal(state.button.disabled, false);
  fail = false;
  await state.hook.copyLoadedTrace();
  assert.equal(state.status.textContent, 'Trace copied.');
});

test('unready views do not copy and late completions cannot update a destroyed trace', async () => {
  let complete;
  const state = setup(() => new Promise(resolve => { complete = resolve; }));
  state.hook.el.dataset.copyReady = 'false';
  state.hook.updated();
  await state.hook.copyLoadedTrace();
  assert.equal(state.button.disabled, true);
  assert.equal(state.writes.length, 0);
  state.hook.el.dataset.copyReady = 'true';
  const pending = state.hook.copyLoadedTrace();
  await state.hook.copyLoadedTrace();
  assert.equal(state.writes.length, 1);
  state.hook.destroyed();
  complete();
  await pending;
  assert.equal(state.status.textContent, '');
  assert.equal(state.timers.size, 0);
  assert.equal(state.button.listeners.click, undefined);
});

test('unsupported clipboard access reports an error instead of throwing out of the click handler', async () => {
  const state = setup(() => { throw new TypeError('clipboard unavailable'); });
  await state.hook.copyLoadedTrace();
  assert.match(state.status.textContent, /Could not copy/);
  assert.equal(state.icon.classList.contains('opacity-0'), false);
});

import assert from 'node:assert/strict';
import test from 'node:test';
import {createTraceMediaHook} from '../js/hooks/trace_media_hook.mjs';

const element = () => ({
  attributes: {}, listeners: {}, classes: new Set(), textContent: '',
  setAttribute(name, value) { this.attributes[name] = value; },
  removeAttribute(name) { delete this.attributes[name]; },
  addEventListener(name, handler) { this.listeners[name] = handler; },
  removeEventListener(name) { delete this.listeners[name]; },
  get classList() { return {toggle: (name, on) => on ? this.classes.add(name) : this.classes.delete(name)}; }
});

const setup = (kind = 'image', properties = {}) => {
  const media = element(), toggle = element(), preview = element(), status = element();
  let loads = 0, pauses = 0;
  Object.assign(media, {load: () => loads++, pause: () => pauses++, complete: false, readyState: 0}, properties);
  const url = '/traces/attachment?source_id=org&reference=trace&part=1&row=2&inline=true';
  media.setAttribute('src', url); // Server-rendered by default.
  const targets = {'[data-media-element]': media, '[data-media-toggle]': toggle,
    '[data-media-preview]': preview, '[data-media-status]': status};
  const hook = {...createTraceMediaHook(), el: {
    dataset: {mediaKind: kind, mediaUrl: url}, querySelector: name => targets[name]
  }};
  hook.mounted();
  return {hook, media, toggle, preview, status, url, get loads() { return loads; }, get pauses() { return pauses; }};
};

test('images are visible by default; mounting does not request them a second time', () => {
  const s = setup();
  assert.equal(s.hook.state, 'loading');
  assert.equal(s.media.attributes.src, s.url);
  assert.equal(s.loads, 0);
  assert.equal(s.preview.classes.has('hidden'), false);
  assert.equal(s.toggle.textContent, 'Hide image');
  assert.equal(s.status.textContent, 'Loading image…');
  s.media.listeners.load();
  assert.equal(s.status.textContent, '');
  assert.equal(s.preview.attributes['aria-busy'], 'false');
  s.toggle.listeners.click();
  assert.equal(s.media.attributes.src, undefined);
  assert.equal(s.preview.classes.has('hidden'), true);
  assert.equal(s.toggle.attributes['aria-expanded'], 'false');
  s.toggle.listeners.click();
  assert.equal(s.media.attributes.src, s.url);
  assert.equal(s.toggle.textContent, 'Hide image');
});

test('videos do not autoplay and hiding/unmounting releases playback and loading', () => {
  const s = setup('video');
  assert.equal(s.loads, 0);
  assert.equal(s.toggle.textContent, 'Hide video');
  assert.equal(s.media.attributes.autoplay, undefined);
  s.media.listeners.loadedmetadata();
  assert.equal(s.hook.state, 'ready');
  s.toggle.listeners.click();
  assert.equal(s.pauses, 1);
  assert.equal(s.media.attributes.src, undefined);
  assert.equal(s.media.preload, 'none');
  s.toggle.listeners.click();
  assert.equal(s.media.preload, 'metadata');
  assert.equal(s.media.attributes.src, s.url);
  const onReady = s.media.listeners.loadedmetadata;
  s.hook.destroyed();
  assert.equal(s.pauses, 2);
  assert.equal(s.media.attributes.src, undefined);
  assert.deepEqual(s.media.listeners, {});
  assert.deepEqual(s.toggle.listeners, {});
  onReady();
  assert.equal(s.hook.state, 'destroyed');
});

test('failed requests or unsupported codecs show a recoverable error and release the media', () => {
  for (const kind of ['image', 'video']) {
    const s = setup(kind);
    s.media.listeners.error();
    assert.equal(s.hook.state, 'error');
    assert.equal(s.media.attributes.src, undefined);
    assert.equal(s.preview.classes.has('hidden'), true);
    assert.match(s.status.textContent, /Retry or download/);
    assert.equal(s.toggle.textContent, `Retry ${kind}`);
    s.toggle.listeners.click();
    assert.equal(s.hook.state, 'loading');
    assert.equal(s.media.attributes.src, s.url);
    s.media.listeners[kind === 'video' ? 'loadedmetadata' : 'load']();
    assert.equal(s.hook.state, 'ready');
  }
});

test('media that loads or fails before mount does not get stuck loading', () => {
  assert.equal(setup('image', {complete: true, naturalWidth: 960}).hook.state, 'ready');
  assert.equal(setup('image', {complete: true, naturalWidth: 0}).hook.state, 'error');
  assert.equal(setup('video', {readyState: 1}).hook.state, 'ready');
  assert.equal(setup('video', {error: {code: 4}}).hook.state, 'error');
});

test('late load/error events cannot reopen a hidden preview', () => {
  const s = setup();
  s.toggle.listeners.click();
  s.media.listeners.load();
  s.media.listeners.error();
  assert.equal(s.hook.state, 'closed');
  assert.equal(s.preview.classes.has('hidden'), true);
  assert.equal(s.status.textContent, '');
});

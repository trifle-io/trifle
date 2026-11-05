import assert from 'node:assert/strict';
import test from 'node:test';
import {completeFunction, createFunctionAutocompleteHook, functionCompletionContext} from '../js/hooks/function_autocomplete_hook.mjs';

const functions = [
  {name: 'moving_avg', signature: 'moving_avg(a, n)', description: 'Trailing mean.'},
  {name: 'moving_median', signature: 'moving_median(a, n)', description: 'Trailing median.'},
  {name: 'sqrt', signature: 'sqrt(a)', description: 'Square root.'}
];

test('completion preserves surrounding and nested expressions and places the caret inside the call', () => {
  for (const [value, at, name, expected, caret] of [
    ['', 0, 'moving_avg', 'moving_avg()', 11],
    ['a + mov / b', 7, 'moving_avg', 'a + moving_avg() / b', 15],
    ['sqrt(mov)', 8, 'moving_median', 'sqrt(moving_median())', 19],
    ['a + moving_median', 7, 'moving_avg', 'a + moving_avg()', 15],
    ['mov(a, 5) + b', 3, 'moving_avg', 'moving_avg(a, 5) + b', 11],
    ['mov  (a, 5)', 3, 'moving_avg', 'moving_avg  (a, 5)', 13]
  ]) {
    assert.deepEqual(completeFunction(value, functionCompletionContext(value, at), name), {value: expected, caret});
  }
});

test('only identifiers in expression positions are completed', () => {
  for (const value of ['a ', '123', '1mov', 'a.mov', 'a)', 'moving_avg(a, 5)']) {
    assert.equal(functionCompletionContext(value, value.length), null, value);
  }
  assert.equal(functionCompletionContext('moving', 0, 6), null);
  assert.equal(functionCompletionContext('moving', null), null);
  assert.equal(functionCompletionContext('a * MOV', 7).query, 'mov');
  assert.equal(functionCompletionContext('moving_avg(a, ', 14).query, '');
});

const element = () => {
  const classes = new Set(['hidden']);
  return {
    children: [], attributes: {}, listeners: {}, value: '', id: '', textContent: '',
    classList: {
      add: name => classes.add(name), remove: name => classes.delete(name),
      toggle: (name, on) => on ? classes.add(name) : classes.delete(name),
      contains: name => classes.has(name)
    },
    setAttribute(name, value) { this.attributes[name] = value; },
    removeAttribute(name) { delete this.attributes[name]; },
    addEventListener(name, handler) { this.listeners[name] = handler; },
    removeEventListener(name) { delete this.listeners[name]; },
    append(...children) { this.children.push(...children); },
    appendChild(child) { this.children.push(child); },
    replaceChildren() { this.children = []; },
    scrollIntoView() {}
  };
};

const setup = (value = '') => {
  let input = element();
  const box = element();
  box.id = 'functions-list';
  const doc = {createElement: () => element(), activeElement: input};
  const events = [];
  const prepareInput = (target, value) => {
    target.value = value;
    target.selectionStart = target.selectionEnd = value.length;
    target.focus = () => { doc.activeElement = target; target.listeners.focus?.(); };
    target.setSelectionRange = (start, end) => { target.selectionStart = start; target.selectionEnd = end; };
    target.dispatchEvent = event => { events.push(event); target.listeners[event.type]?.(event); };
    return target;
  };
  prepareInput(input, value);
  const hook = {...createFunctionAutocompleteHook({getDocument: () => doc}), el: {
    dataset: {functions: JSON.stringify(functions)},
    querySelector: selector => selector.includes('series-expression') ? input : box
  }};
  hook.mounted();
  const key = (key, extra = {}) => {
    const event = {key, prevented: false, stopped: false,
      preventDefault() { this.prevented = true; }, stopPropagation() { this.stopped = true; }, ...extra};
    input.listeners.keydown(event);
    return event;
  };
  return {hook, input, box, doc, events, key, replaceInput(value) {
    input = prepareInput(element(), value);
    return input;
  }};
};

test('focus lists signatures and descriptions, filtering by the token at the caret', () => {
  const {hook, input, box} = setup();
  input.listeners.focus();
  assert.equal(box.children.length, 3);
  assert.equal(input.attributes['aria-expanded'], 'true');
  assert.equal(box.children[0].children[0].textContent, 'moving_avg(a, n)');
  assert.equal(box.children[0].children[1].textContent, 'Trailing mean.');
  input.value = 'a + mov';
  input.setSelectionRange(7, 7);
  input.listeners.input({});
  assert.deepEqual(hook.matches.map(item => item.name), ['moving_avg', 'moving_median']);
  input.value = 'a + unknown';
  input.setSelectionRange(11, 11);
  input.listeners.input({});
  assert.equal(hook.visible, false);
  assert.equal(input.attributes['aria-expanded'], 'false');
});

test('arrow navigation and Enter insert the active function and notify the series editor', () => {
  const {hook, input, key, events, box} = setup('a + mov');
  assert.equal(key('ArrowUp').prevented, true);
  assert.equal(input.attributes['aria-activedescendant'], 'functions-list-1');
  assert.equal(box.children[1].attributes['aria-selected'], 'true');
  key('ArrowDown');
  assert.equal(hook.activeIndex, 0);
  const enter = key('Enter');
  assert.equal(enter.prevented, true);
  assert.equal(enter.stopped, true);
  assert.equal(input.value, 'a + moving_avg()');
  assert.equal(input.selectionStart, 15);
  assert.deepEqual(events.map(event => [event.type, event.bubbles]), [['input', true], ['change', true]]);
  assert.equal(hook.visible, false);
  assert.equal(input.attributes['aria-activedescendant'], undefined);
  hook.updated();
  assert.equal(hook.visible, false);
});

test('Tab accepts a highlighted option and otherwise preserves normal focus navigation', () => {
  const {input, key} = setup('sq');
  input.listeners.focus();
  assert.equal(key('Tab').prevented, false);
  key('ArrowDown');
  assert.equal(key('Tab').prevented, true);
  assert.equal(input.value, 'sqrt()');
});

test('Escape and blur close the list, without a preview patch reopening it', () => {
  const {hook, input, key, doc} = setup('mov');
  input.listeners.focus();
  assert.equal(key('Escape').stopped, true);
  hook.updated();
  assert.equal(hook.visible, false);
  input.listeners.focus();
  doc.activeElement = null;
  input.listeners.blur();
  assert.equal(hook.visible, false);
  assert.equal(input.value, 'mov');
});

test('mouse selection retains focus and does not duplicate existing parentheses', () => {
  const {hook, input, box, doc} = setup('mov(a, 5)');
  input.setSelectionRange(3, 3);
  input.listeners.click();
  let prevented = false;
  box.children[0].listeners.mousedown({preventDefault() { prevented = true; }});
  assert.equal(prevented, true);
  box.children[0].listeners.click({preventDefault() {}, stopPropagation() {}});
  assert.equal(input.value, 'moving_avg(a, 5)');
  assert.equal(input.selectionStart, 11);
  assert.equal(doc.activeElement, input);
  assert.equal(hook.visible, false);
});

test('LiveView patches refresh functions and listeners; destruction detaches all listeners', () => {
  const state = setup('mov');
  state.input.listeners.focus();
  const next = state.replaceInput('sqrt');
  state.doc.activeElement = next;
  state.hook.el.dataset.functions = JSON.stringify([functions[2]]);
  state.hook.updated();
  assert.deepEqual(Object.keys(state.input.listeners), []);
  assert.equal(state.hook.matches[0].name, 'sqrt');
  state.hook.destroyed();
  assert.deepEqual(Object.keys(next.listeners), []);
  assert.equal(next.attributes['aria-expanded'], 'false');
});

test('IME input never accepts a function mid-composition', () => {
  const {hook, input, key} = setup('mov');
  input.listeners.focus();
  input.listeners.compositionstart();
  assert.equal(key('ArrowDown', {isComposing: true}).prevented, false);
  input.listeners.input({isComposing: true});
  assert.equal(hook.visible, false);
  input.listeners.compositionend();
  assert.equal(hook.matches.length, 2);
});

test('malformed or unavailable function metadata gives no suggestions', () => {
  const {hook, input} = setup();
  for (const metadata of ['{bad json', '{}', '[]']) {
    hook.el.dataset.functions = metadata;
    hook.updated();
    input.listeners.focus();
    assert.equal(hook.visible, false);
  }
});

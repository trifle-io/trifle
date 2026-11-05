// Completion replaces only the identifier at the caret, including when the
// caret is in the middle of a name or inside a nested formula.
export const functionCompletionContext = (value, start, end = start) => {
  if (start == null || start !== end) return null;
  let from = start, to = start;
  while (from > 0 && /[a-zA-Z0-9_]/.test(value[from - 1])) from--;
  while (to < value.length && /[a-zA-Z0-9_]/.test(value[to])) to++;
  const token = value.slice(from, to);
  if (token && !/^[a-zA-Z_]/.test(token)) return null;
  const before = value.slice(0, from).trimEnd();
  if (before && !/[+\-*/(,]$/.test(before)) return null;
  const suffix = value.slice(to);
  const opening = /^\s*\(/.exec(suffix);
  return {from, to, query: value.slice(from, start).toLowerCase(), openingLength: opening?.[0].length || 0};
};

export const completeFunction = (value, context, name) => {
  const insertion = context.openingLength ? name : `${name}()`;
  return {
    value: value.slice(0, context.from) + insertion + value.slice(context.to),
    caret: context.from + name.length + (context.openingLength || 1)
  };
};

export const createFunctionAutocompleteHook = ({getDocument = () => document} = {}) => ({
  mounted() {
    this.doc = getDocument();
    this.matches = [];
    this.activeIndex = -1;
    this.visible = false;
    this.composing = false;
    this.suppressInput = false;
    this.onInput = (event) => {
      if (!this.suppressInput && !event.isComposing && !this.composing) this.filterSuggestions();
    };
    this.onFocus = () => this.filterSuggestions();
    this.onBlur = () => this.hideSuggestions();
    this.onClick = () => this.filterSuggestions();
    this.onKeydown = (event) => this.handleKeydown(event);
    this.onKeyup = (event) => {
      if (['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) this.filterSuggestions();
    };
    this.onCompositionStart = () => { this.composing = true; this.hideSuggestions(); };
    this.onCompositionEnd = () => { this.composing = false; this.filterSuggestions(); };
    this.refresh();
  },

  updated() {
    const wasVisible = this.visible;
    this.refresh();
    // A validation/preview patch must not reopen a list dismissed with Escape
    // or immediately after accepting a completion.
    if (wasVisible) this.filterSuggestions();
    else this.hideSuggestions();
  },

  destroyed() {
    this.detach();
    this.hideSuggestions();
  },

  refresh() {
    try {
      const functions = JSON.parse(this.el.dataset.functions || '[]');
      this.functions = Array.isArray(functions) ? functions : [];
    } catch (_) {
      this.functions = [];
    }
    const input = this.el.querySelector('[data-role="series-expression"]');
    const box = this.el.querySelector('[data-role="function-suggestions"]');
    if (input === this.input && box === this.box) return;
    this.detach();
    this.input = input;
    this.box = box;
    this.inputEvents = {
      input: this.onInput, focus: this.onFocus, blur: this.onBlur,
      click: this.onClick, keydown: this.onKeydown, keyup: this.onKeyup,
      compositionstart: this.onCompositionStart, compositionend: this.onCompositionEnd
    };
    if (this.input) {
      Object.entries(this.inputEvents).forEach(([name, handler]) => this.input.addEventListener(name, handler));
    }
  },

  detach() {
    if (!this.input) return;
    Object.entries(this.inputEvents).forEach(([name, handler]) => this.input.removeEventListener(name, handler));
  },

  filterSuggestions() {
    if (!this.input || !this.box || this.composing || this.doc.activeElement !== this.input) {
      this.hideSuggestions();
      return;
    }
    this.context = functionCompletionContext(this.input.value, this.input.selectionStart, this.input.selectionEnd);
    const matches = this.context ? this.functions.filter(item => item.name.startsWith(this.context.query)) : [];
    if (!matches.length) { this.hideSuggestions(); return; }
    this.renderSuggestions(matches);
  },

  renderSuggestions(matches) {
    const previousName = this.matches[this.activeIndex]?.name;
    this.matches = matches;
    this.box.replaceChildren();
    matches.forEach((item, index) => {
      const option = this.doc.createElement('button');
      option.type = 'button';
      option.tabIndex = -1;
      option.id = `${this.box.id}-${index}`;
      option.setAttribute('role', 'option');
      option.className = 'block w-full px-3 py-2 text-left text-sm text-slate-700 hover:bg-teal-50 dark:text-slate-200 dark:hover:bg-slate-700';
      const signature = this.doc.createElement('span');
      signature.className = 'block font-mono text-xs font-medium';
      signature.textContent = item.signature;
      const description = this.doc.createElement('span');
      description.className = 'mt-1 block text-xs text-slate-500 dark:text-slate-400';
      description.textContent = item.description;
      option.append(signature, description);
      // Retain input focus so selecting a suggestion cannot submit the form or
      // lose the insertion position. Click also supports touch and AT activation.
      option.addEventListener('mousedown', event => event.preventDefault());
      option.addEventListener('click', event => {
        event.preventDefault();
        event.stopPropagation();
        this.selectOption(index);
      });
      this.box.appendChild(option);
    });
    this.box.classList.remove('hidden');
    this.visible = true;
    this.input.setAttribute('aria-expanded', 'true');
    this.setActive(matches.findIndex(item => item.name === previousName));
  },

  hideSuggestions() {
    this.box?.classList.add('hidden');
    this.box?.replaceChildren();
    this.visible = false;
    this.matches = [];
    this.activeIndex = -1;
    this.input?.setAttribute('aria-expanded', 'false');
    this.input?.removeAttribute('aria-activedescendant');
  },

  setActive(index) {
    this.activeIndex = index;
    Array.from(this.box.children).forEach((option, i) => {
      option.setAttribute('aria-selected', String(i === index));
      option.classList.toggle('bg-teal-100', i === index);
      option.classList.toggle('dark:bg-slate-600', i === index);
    });
    const active = this.box.children[index];
    if (active) {
      this.input.setAttribute('aria-activedescendant', active.id);
      active.scrollIntoView({block: 'nearest'});
    } else {
      this.input.removeAttribute('aria-activedescendant');
    }
  },

  handleKeydown(event) {
    if (event.isComposing || this.composing) return;
    if (['ArrowDown', 'ArrowUp'].includes(event.key)) {
      if (!this.visible) this.filterSuggestions();
      if (!this.visible) return;
      event.preventDefault();
      event.stopPropagation();
      const next = this.activeIndex < 0
        ? (event.key === 'ArrowDown' ? 0 : this.matches.length - 1)
        : (this.activeIndex + (event.key === 'ArrowDown' ? 1 : -1) + this.matches.length) % this.matches.length;
      this.setActive(next);
    } else if (this.visible && (event.key === 'Enter' || event.key === 'Tab') && this.activeIndex >= 0) {
      event.preventDefault();
      event.stopPropagation();
      this.selectOption(this.activeIndex);
    } else if (this.visible && event.key === 'Escape') {
      event.preventDefault();
      event.stopPropagation();
      this.hideSuggestions();
    } else if (event.key === 'Tab') {
      this.hideSuggestions();
    }
  },

  selectOption(index) {
    const item = this.matches[index];
    const context = functionCompletionContext(this.input.value, this.input.selectionStart, this.input.selectionEnd);
    if (!item || !context) return;
    const completed = completeFunction(this.input.value, context, item.name);
    this.input.value = completed.value;
    this.input.focus();
    this.input.setSelectionRange(completed.caret, completed.caret);
    this.hideSuggestions();
    this.suppressInput = true;
    // Bubble through WidgetSeriesRows so preview updates and persistence follow
    // exactly the same path as ordinary formula edits.
    this.input.dispatchEvent(new Event('input', {bubbles: true}));
    this.input.dispatchEvent(new Event('change', {bubbles: true}));
    this.suppressInput = false;
  }
});

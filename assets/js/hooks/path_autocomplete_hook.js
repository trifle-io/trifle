export const registerPathAutocompleteHook = (Hooks, deps = {}) => {
const PATH_PREVIEW_COLORS = [
  '#14b8a6',
  '#f59e0b',
  '#ef4444',
  '#8b5cf6',
  '#06b6d4',
  '#10b981',
  '#f97316',
  '#ec4899',
  '#3b82f6',
  '#84cc16',
  '#f43f5e',
  '#6366f1'
];

const escapePathPreviewHtml = (value) =>
  String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');

const pathPreviewColorForIndex = (index) => {
  const safeIndex = Number.isFinite(index) && index >= 0 ? index : 0;
  return PATH_PREVIEW_COLORS[safeIndex % PATH_PREVIEW_COLORS.length] || PATH_PREVIEW_COLORS[0];
};

const pathPreviewSiblingComponents = (paths, pathSoFar) => {
  const prefix = pathSoFar.length > 0 ? `${pathSoFar.join('.')}.` : '';

  return Array.from(
    new Set(
      (Array.isArray(paths) ? paths : [])
        .filter((path) => {
          if (typeof path !== 'string') return false;

          return (
            path.startsWith(prefix) &&
            path.split('.').length > pathSoFar.length
          );
        })
        .map((path) => path.split('.').slice(pathSoFar.length)[0] || '')
    )
  ).sort((left, right) => left.localeCompare(right, undefined, { numeric: true }));
};

const formatAnnotatedPathPreview = (value, allPaths) => {
  const displayPath = String(value ?? '');
  if (!displayPath) return '';

  const components = displayPath.split('.');
  const pathSoFar = [];

  return components
    .map((component) => {
      const siblings = pathPreviewSiblingComponents(allPaths, pathSoFar);
      const index = Math.max(siblings.indexOf(component), 0);
      const color = pathPreviewColorForIndex(index);

      pathSoFar.push(component);

      return `<span style="color: ${color} !important">${escapePathPreviewHtml(component)}</span>`;
    })
    .join('<span class="text-slate-400 dark:text-slate-500">.</span>');
};

Hooks.PathAutocomplete = {
  mounted() {
    this.input = null;
    this.pathPreview = null;
    this.suggestionBox = null;
    this.matches = [];
    this.activeIndex = -1;
    this.visible = false;
    this.suppressNextFilter = false;

    this.handleInput = () => {
      this.syncPathPreview();
      this.filterSuggestions();
    };
    this.handleFocus = () => {
      this.syncPathPreview();
      this.openSuggestions();
    };
    this.handleBlur = () => {
      this._blurTimer = setTimeout(() => this.hideSuggestions(), 100);
    };
    this.handleKeydown = (event) => this.onKeydown(event);

    this.loadOptions();
    this.refreshElements();
    this.syncPathPreview();

    // Show initial matches if input already has a value
    if (document.activeElement === this.input) {
      this.filterSuggestions();
    }
  },

  updated() {
    const previous = JSON.stringify(this.options || []);
    this.loadOptions();

    const elementsChanged = this.refreshElements();
    this.syncPathPreview();
    if (elementsChanged) {
      if (document.activeElement === this.input) {
        this.filterSuggestions();
      } else {
        this.hideSuggestions();
      }
      return;
    }

    if (document.activeElement === this.input || JSON.stringify(this.options) !== previous) {
      this.filterSuggestions();
    }
  },

  destroyed() {
    this.detachInputListeners();
    if (this.input) {
      this.input.style.removeProperty('color');
      this.input.style.removeProperty('caret-color');
    }
    if (this._blurTimer) clearTimeout(this._blurTimer);
  },

  refreshElements() {
    const nextInput =
      this.el.querySelector('[data-path-autocomplete-input="true"]') ||
      this.el.querySelector('[data-role="path-input"]');
    const nextPathPreview = this.el.querySelector('[data-role="path-preview"]');
    const nextSuggestionBox = this.el.querySelector('[data-role="suggestions"]');

    if (
      nextInput === this.input &&
      nextPathPreview === this.pathPreview &&
      nextSuggestionBox === this.suggestionBox
    ) {
      return false;
    }

    this.detachInputListeners();
    this.input = nextInput;
    this.pathPreview = nextPathPreview;
    this.suggestionBox = nextSuggestionBox;
    this.attachInputListeners();

    return true;
  },

  attachInputListeners() {
    if (!this.input || !this.suggestionBox) return;
    this.input.addEventListener('input', this.handleInput);
    this.input.addEventListener('focus', this.handleFocus);
    this.input.addEventListener('blur', this.handleBlur);
    this.input.addEventListener('keydown', this.handleKeydown);
  },

  detachInputListeners() {
    if (!this.input) return;
    this.input.removeEventListener('input', this.handleInput);
    this.input.removeEventListener('focus', this.handleFocus);
    this.input.removeEventListener('blur', this.handleBlur);
    this.input.removeEventListener('keydown', this.handleKeydown);
  },

  loadOptions() {
    const raw = this.el.dataset.paths || '[]';
    let parsed;
    try {
      parsed = JSON.parse(raw);
    } catch (_) {
      parsed = [];
    }

    if (!Array.isArray(parsed)) parsed = [];

    this.options = parsed
      .map((item) => {
        if (typeof item === 'string') {
          return { value: item, label: item };
        }

        if (item && typeof item.value === 'string') {
          return {
            value: item.value,
            label: typeof item.label === 'string' ? item.label : item.value
          };
        }

        return null;
      })
      .filter(Boolean);

    this.optionValues = this.options.map((item) => item.value);
  },

  filterSuggestions() {
    if (this.suppressNextFilter) {
      this.suppressNextFilter = false;
      return;
    }

    if (!this.input) return;

    const hasFocus = document.activeElement === this.input;
    if (!hasFocus) {
      this.hideSuggestions();
      return;
    }

    const query = (this.input.value || '').trim().toLowerCase();

    let candidates = this.options;
    if (query) {
      candidates = this.options.filter((item) =>
        item.value.toLowerCase().includes(query)
      );
    }

    const limited = candidates.slice(0, 15);
    if (limited.length === 0) {
      this.hideSuggestions();
      return;
    }

    this.renderSuggestions(limited);
  },

  renderSuggestions(items) {
    if (!this.suggestionBox) return;

    this.matches = items;
    this.activeIndex = -1;

    const fragment = document.createDocumentFragment();

    items.forEach((item, index) => {
      const option = document.createElement('button');
      option.type = 'button';
      option.className = 'w-full px-3 py-2 text-left text-sm leading-tight text-slate-700 hover:bg-teal-50 focus:outline-none dark:text-slate-200 dark:hover:bg-slate-700';
      option.setAttribute('role', 'option');
      option.dataset.index = index;
      option.dataset.value = item.value;
      // Labels are generated server-side by ExploreCore.format_nested_path with
      // escaped path components and color span markup. Use HTML here so the
      // annotated/colorized path suggestions render instead of showing raw tags.
      option.innerHTML = item.label;

      option.addEventListener('mousedown', (event) => {
        event.preventDefault();
        this.selectOption(index);
      });

      fragment.appendChild(option);
    });

    this.suggestionBox.innerHTML = '';
    this.suggestionBox.appendChild(fragment);
    this.suggestionBox.classList.remove('hidden');
    this.visible = true;
  },

  openSuggestions() {
    if (this._blurTimer) clearTimeout(this._blurTimer);
    this.filterSuggestions();
  },

  hideSuggestions() {
    if (!this.suggestionBox) return;
    this.suggestionBox.classList.add('hidden');
    this.suggestionBox.innerHTML = '';
    this.visible = false;
    this.matches = [];
    this.activeIndex = -1;
  },

  onKeydown(event) {
    if (!this.visible && (event.key === 'ArrowDown' || event.key === 'ArrowUp')) {
      this.filterSuggestions();
    }

    if (!this.visible) return;

    switch (event.key) {
      case 'ArrowDown':
        event.preventDefault();
        this.moveActive(1);
        break;
      case 'ArrowUp':
        event.preventDefault();
        this.moveActive(-1);
        break;
      case 'Enter':
        if (this.activeIndex >= 0) {
          event.preventDefault();
          this.selectOption(this.activeIndex);
        }
        break;
      case 'Escape':
        this.hideSuggestions();
        break;
      default:
        break;
    }
  },

  moveActive(delta) {
    if (this.matches.length === 0 || !this.suggestionBox) return;

    const nextIndex = (this.activeIndex + delta + this.matches.length) % this.matches.length;
    this.setActive(nextIndex);
  },

  setActive(index) {
    if (!this.suggestionBox) return;

    const buttons = Array.from(this.suggestionBox.querySelectorAll('button[data-index]'));
    buttons.forEach((btn) => {
      btn.classList.remove('bg-teal-100', 'dark:bg-slate-600');
    });

    const active = buttons[index];
    if (active) {
      active.classList.add('bg-teal-100', 'dark:bg-slate-600');
      active.scrollIntoView({ block: 'nearest' });
      this.activeIndex = index;
    }
  },

  selectOption(index) {
    const item = this.matches[index];
    if (!item || !this.input) return;

    this.input.value = item.value;
    this.syncPathPreview();
    this.suppressNextFilter = true;
    this.hideSuggestions();

    const nativeInputValueSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value')?.set;
    if (nativeInputValueSetter) {
      nativeInputValueSetter.call(this.input, item.value);
    }

    this.input.dispatchEvent(new Event('input', { bubbles: true }));
    this.input.dispatchEvent(new Event('change', { bubbles: true }));
  },

  syncPathPreview() {
    if (!this.input) return;

    const value = this.input.value || '';

    if (!this.pathPreview) {
      this.input.style.removeProperty('color');
      this.input.style.removeProperty('caret-color');
      return;
    }

    this.input.style.setProperty('color', 'transparent');
    this.input.style.setProperty(
      'caret-color',
      document.documentElement.classList.contains('dark') ? '#ffffff' : '#111827'
    );

    if (!value) {
      this.pathPreview.innerHTML = '';
      this.pathPreview.classList.add('hidden');
      return;
    }

    this.pathPreview.innerHTML = formatAnnotatedPathPreview(value, this.optionValues || []);
    this.pathPreview.classList.remove('hidden');
  }
}

};

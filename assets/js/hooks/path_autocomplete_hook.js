import {pathSegments, pathTextSegments} from '../utils/stats_path.mjs';

export const registerPathAutocompleteHook = (Hooks, deps = {}) => {
const PATH_PREVIEW_FONT_PROPERTIES = [
  'fontFamily',
  'fontFeatureSettings',
  'fontKerning',
  'fontOpticalSizing',
  'fontSize',
  'fontStretch',
  'fontStyle',
  'fontVariant',
  'fontVariantNumeric',
  'fontWeight',
  'letterSpacing',
  'lineHeight',
  'tabSize',
  'textRendering',
  'textTransform',
  'wordSpacing'
];

const PATH_PREVIEW_LAYOUT_PROPERTIES = [
  'boxSizing',
  'paddingTop',
  'paddingRight',
  'paddingBottom',
  'paddingLeft',
  'borderTopStyle',
  'borderRightStyle',
  'borderBottomStyle',
  'borderLeftStyle',
  'borderTopWidth',
  'borderRightWidth',
  'borderBottomWidth',
  'borderLeftWidth',
  'textAlign',
  'textIndent'
];

const escapePathPreviewHtml = (value) =>
  String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');

const suggestionLabelHtml = (item) => {
  // The browser has already decoded the data-paths attribute. Keep the HTML
  // escaping within the label so path segments are rendered as text.
  return item.label === item.value ? escapePathPreviewHtml(item.value) : item.label;
};

const formatAnnotatedPathPreview = (value, pathColors, defaultColor) => {
  const labels = pathTextSegments(value);
  const prefix = [];

  return pathSegments(value)
    .map((segment, index) => {
      prefix.push(segment);
      const color = pathColors.get(JSON.stringify(prefix)) ?? defaultColor;

      return `<span style="color: ${escapePathPreviewHtml(color)} !important">${escapePathPreviewHtml(labels[index])}</span>`;
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
    this.suggestionsRequested = false;
    this.suppressInput = false;

    this.handleInput = () => {
      this.syncPathPreview();
      if (!this.suppressInput) this.openSuggestions();
    };
    this.handleFocus = () => {
      this.syncPathPreview();
      this.openSuggestions();
    };
    this.handleBlur = () => {
      this._blurTimer = setTimeout(() => this.closeSuggestions(), 100);
    };
    this.handleKeydown = (event) => this.onKeydown(event);
    this.repositionSuggestions = (event) => {
      if (event.target !== this.suggestionBox) this.positionSuggestions();
    };

    this.loadOptions();
    this.refreshElements();
    this.syncPathPreview();

    if (document.activeElement === this.input) {
      this.openSuggestions();
    }
  },

  updated() {
    const optionsChanged = this.loadOptions();
    const elementsChanged = this.refreshElements();
    this.syncPathPreview();

    if (document.activeElement !== this.input) {
      this.closeSuggestions();
    } else if (this.suggestionsRequested) {
      if (optionsChanged || elementsChanged || this.input.value !== this.lastValue) {
        this.filterSuggestions();
      } else if (this.visible) {
        this.positionSuggestions();
      }
    }
  },

  destroyed() {
    this.closeSuggestions();
    this.detachInputListeners();
    this.clearPathPreviewMetrics();
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

    this.hideSuggestions();
    this.detachInputListeners();
    this.clearPathPreviewMetrics();
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
    if (raw === this.loadedPaths) return false;
    this.loadedPaths = raw;
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
            label: typeof item.label === 'string' ? item.label : item.value,
            segmentColors: item.segment_colors
          };
        }

        return null;
      })
      .filter(Boolean);

    this.pathColors = new Map();
    for (const {value, segmentColors} of this.options) {
      if (!Array.isArray(segmentColors)) continue;

      const prefix = [];
      pathSegments(value).forEach((segment, index) => {
        prefix.push(segment);
        const color = segmentColors[index];
        if (typeof color === 'string') this.pathColors.set(JSON.stringify(prefix), color);
      });
    }
    return true;
  },

  filterSuggestions() {
    if (!this.input || document.activeElement !== this.input) {
      this.closeSuggestions();
      return;
    }

    this.lastValue = this.input.value;
    const query = this.lastValue.trim().toLowerCase();

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
      option.tabIndex = -1;
      option.className = 'block w-full [overflow-wrap:anywhere] px-3 py-2 text-left text-sm leading-tight text-slate-700 hover:bg-teal-50 focus:outline-none dark:text-slate-200 dark:hover:bg-slate-700';
      option.setAttribute('role', 'option');
      option.dataset.index = index;
      option.dataset.value = item.value;
      // Labels are generated server-side by ExploreCore.format_nested_path with
      // escaped path components and color span markup. Use HTML here so the
      // annotated/colorized path suggestions render instead of showing raw tags.
      option.innerHTML = suggestionLabelHtml(item);

      option.addEventListener('mousedown', (event) => event.preventDefault());
      option.addEventListener('click', () => this.selectOption(index));

      fragment.appendChild(option);
    });

    this.suggestionBox.innerHTML = '';
    this.suggestionBox.appendChild(fragment);
    this.suggestionBox.classList.remove('hidden');
    if (!this.visible) this.showSuggestionsPopover();
    this.visible = true;
    this.positionSuggestions();
  },

  showSuggestionsPopover() {
    if (!this.suggestionBox.showPopover) return;

    this.suggestionBox.showPopover();
    window.addEventListener('scroll', this.repositionSuggestions, true);
    window.addEventListener('resize', this.repositionSuggestions);
    window.visualViewport?.addEventListener('scroll', this.repositionSuggestions);
    window.visualViewport?.addEventListener('resize', this.repositionSuggestions);

    // A top-layer popover can outlive the visible part of its scrolling container.
    this.anchorObserver = new IntersectionObserver(([entry]) => {
      if (!entry.isIntersecting) this.closeSuggestions();
    });
    this.anchorObserver.observe(this.input);
  },

  positionSuggestions() {
    const box = this.suggestionBox;
    if (!box?.showPopover || !box.matches(':popover-open')) return;

    const anchor = this.input.getBoundingClientRect();
    const viewport = window.visualViewport;
    const {clientWidth, clientHeight} = document.documentElement;
    const viewportLeft = viewport?.offsetLeft ?? 0;
    const viewportTop = viewport?.offsetTop ?? 0;
    const gutter = 8;
    const gap = 4;
    const right = viewportLeft + (viewport?.width ?? clientWidth) - gutter;
    const bottom = viewportTop + (viewport?.height ?? clientHeight) - gutter;
    const width = Math.min(anchor.width, right - viewportLeft - gutter);

    box.style.width = `${width}px`;
    box.style.left = `${Math.max(viewportLeft + gutter, Math.min(anchor.left, right - width))}px`;

    box.style.removeProperty('max-height');
    const desiredHeight = box.offsetHeight;
    const spaceBelow = bottom - anchor.bottom - gap;
    const spaceAbove = anchor.top - viewportTop - gutter - gap;
    const openAbove = desiredHeight > spaceBelow && spaceAbove > spaceBelow;
    const height = Math.max(0, Math.min(desiredHeight, openAbove ? spaceAbove : spaceBelow));

    box.style.maxHeight = `${height}px`;
    box.style.top = `${openAbove ? anchor.top - gap - height : anchor.bottom + gap}px`;
  },

  openSuggestions() {
    if (this._blurTimer) clearTimeout(this._blurTimer);
    this.suggestionsRequested = true;
    this.filterSuggestions();
  },

  closeSuggestions() {
    this.suggestionsRequested = false;
    this.hideSuggestions();
  },

  hideSuggestions() {
    if (!this.suggestionBox) return;
    if (this.anchorObserver) {
      this.anchorObserver.disconnect();
      this.anchorObserver = null;
      window.removeEventListener('scroll', this.repositionSuggestions, true);
      window.removeEventListener('resize', this.repositionSuggestions);
      window.visualViewport?.removeEventListener('scroll', this.repositionSuggestions);
      window.visualViewport?.removeEventListener('resize', this.repositionSuggestions);
      if (this.suggestionBox.matches(':popover-open')) this.suggestionBox.hidePopover();
    }
    this.suggestionBox.classList.add('hidden');
    this.suggestionBox.innerHTML = '';
    this.visible = false;
    this.matches = [];
    this.activeIndex = -1;
  },

  onKeydown(event) {
    if (!this.visible && (event.key === 'ArrowDown' || event.key === 'ArrowUp')) {
      this.openSuggestions();
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
        event.preventDefault();
        event.stopPropagation();
        this.closeSuggestions();
        break;
      default:
        break;
    }
  },

  moveActive(delta) {
    if (this.matches.length === 0 || !this.suggestionBox) return;

    const current = this.activeIndex < 0 && delta < 0 ? 0 : this.activeIndex;
    const nextIndex = (current + delta + this.matches.length) % this.matches.length;
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
      const box = this.suggestionBox;
      const optionBottom = active.offsetTop + active.offsetHeight;
      box.scrollTop = Math.min(active.offsetTop, Math.max(box.scrollTop, optionBottom - box.clientHeight));
      this.activeIndex = index;
    }
  },

  selectOption(index) {
    const item = this.matches[index];
    if (!item || !this.input) return;

    this.input.value = item.value;
    this.closeSuggestions();
    this.suppressInput = true;
    this.input.dispatchEvent(new Event('input', { bubbles: true }));
    this.suppressInput = false;
    this.input.dispatchEvent(new Event('change', { bubbles: true }));
  },

  syncPathPreview() {
    if (!this.input) return;

    const value = this.input.value || '';

    if (!this.pathPreview) {
      this.clearPathPreviewMetrics();
      this.input.style.removeProperty('color');
      this.input.style.removeProperty('caret-color');
      return;
    }

    this.syncPathPreviewMetrics();
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

    this.pathPreview.innerHTML = formatAnnotatedPathPreview(
      value,
      this.pathColors,
      this.el.dataset.pathDefaultColor || 'currentColor'
    );
    this.pathPreview.classList.remove('hidden');
  },

  syncPathPreviewMetrics() {
    if (!this.input || !this.pathPreview || typeof window === 'undefined' || typeof window.getComputedStyle !== 'function') {
      return;
    }

    const inputStyle = window.getComputedStyle(this.input);

    PATH_PREVIEW_FONT_PROPERTIES.forEach((property) => {
      const value = inputStyle[property];
      if (!value) return;
      this.pathPreview.style[property] = value;
    });

    PATH_PREVIEW_LAYOUT_PROPERTIES.forEach((property) => {
      const value = inputStyle[property];
      if (!value) return;
      this.pathPreview.style[property] = value;
    });

    this.pathPreview.style.borderColor = 'transparent';
    this.pathPreview.style.backgroundColor = 'transparent';
    this.pathPreview.style.overflow = 'hidden';
    this.pathPreview.style.whiteSpace = 'pre';
  },

  clearPathPreviewMetrics() {
    if (this.pathPreview) {
      PATH_PREVIEW_FONT_PROPERTIES.concat(PATH_PREVIEW_LAYOUT_PROPERTIES).forEach((property) => {
        this.pathPreview.style.removeProperty(property.replace(/[A-Z]/g, (match) => `-${match.toLowerCase()}`));
      });
      this.pathPreview.style.removeProperty('border-color');
      this.pathPreview.style.removeProperty('background-color');
      this.pathPreview.style.removeProperty('overflow');
      this.pathPreview.style.removeProperty('white-space');
    }
  }
}

};

const FILTER_BAR_SELECTOR = '[data-filter-bar-shortcuts="true"]';
const EDITABLE_SELECTOR = "input, textarea, select";
const BLOCKING_DIALOG_SELECTOR = '[role="dialog"][aria-modal="true"]';

const isVisible = (element) => {
  if (!(element instanceof HTMLElement)) return false;
  if (!element.isConnected || element.hidden) return false;

  const style = window.getComputedStyle(element);
  if (style.display === "none" || style.visibility === "hidden") return false;

  return element.getClientRects().length > 0;
};

const isEditableTarget = (target) => {
  if (!(target instanceof HTMLElement)) return false;
  if (target.isContentEditable) return true;
  if (target.closest('[contenteditable="true"]')) return true;

  return !!target.closest(EDITABLE_SELECTOR);
};

const hasVisibleBlockingDialog = () =>
  Array.from(document.querySelectorAll(BLOCKING_DIALOG_SELECTOR)).some(isVisible);

const visibleFilterBars = () =>
  Array.from(document.querySelectorAll(FILTER_BAR_SELECTOR)).filter(isVisible);

const activeFilterBar = (event) => {
  const bars = visibleFilterBars();
  if (bars.length === 0) return null;

  const candidates = [event.target, document.activeElement].filter(
    (element) => element instanceof Element
  );

  for (const candidate of candidates) {
    const containingBar = bars.find((bar) => bar.contains(candidate));
    if (containingBar) return containingBar;
  }

  return bars[0];
};

const parseGranularities = (value) => {
  try {
    const parsed = JSON.parse(value || "[]");
    if (!Array.isArray(parsed)) return [];

    return parsed.map((granularity) => String(granularity || "").trim()).filter(Boolean);
  } catch (_) {
    return [];
  }
};

export const registerFilterBarShortcutsHook = (Hooks) => {
  Hooks.FilterBarShortcuts = {
    mounted() {
      this._eventTarget = this.el.closest("[data-phx-component]") || null;
      this._handleKeydown = (event) => this.handleShortcut(event);
      window.addEventListener("keydown", this._handleKeydown);
    },

    updated() {
      this._eventTarget = this.el.closest("[data-phx-component]") || null;
    },

    destroyed() {
      if (this._handleKeydown) {
        window.removeEventListener("keydown", this._handleKeydown);
        this._handleKeydown = null;
      }
    },

    handleShortcut(event) {
      if (!this.shouldHandle(event)) return;
      if (activeFilterBar(event) !== this.el) return;

      const key = String(event.key || "").toLowerCase();

      if (["h", "l", "p", "r"].includes(key)) {
        if (this.el.dataset.filterBarControlsEnabled !== "true") return;

        const controlEvents = {
          h: "navigate_timeframe_backward",
          l: "navigate_timeframe_forward",
          p: "toggle_play_pause",
          r: "reload_data"
        };

        event.preventDefault();
        this.pushFilterEvent(controlEvents[key]);
        return;
      }

      if (key === "j") {
        if (this.selectAdjacentGranularity(-1)) event.preventDefault();
        return;
      }

      if (key === "k") {
        if (this.selectAdjacentGranularity(1)) event.preventDefault();
        return;
      }

      if (key === "t") {
        if (this.focusTimeframeInput()) event.preventDefault();
      }
    },

    shouldHandle(event) {
      if (!event || event.defaultPrevented || event.repeat || event.isComposing) return false;
      if (event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return false;
      if (isEditableTarget(event.target)) return false;
      if (hasVisibleBlockingDialog()) return false;

      return isVisible(this.el);
    },

    focusTimeframeInput() {
      const input = this.el.querySelector('input[name="smart_timeframe"]');
      if (!(input instanceof HTMLInputElement)) return false;
      if (input.disabled || input.readOnly) return false;

      try {
        input.focus({ preventScroll: true });
      } catch (_) {
        input.focus();
      }

      if (typeof input.select === "function") {
        input.select();
      }

      this.pushFilterEvent("show_timeframe_dropdown");
      return true;
    },

    selectAdjacentGranularity(offset) {
      const granularities = parseGranularities(this.el.dataset.filterBarGranularities);
      const current = String(this.el.dataset.filterBarCurrentGranularity || "").trim();
      const currentIndex = granularities.indexOf(current);
      if (currentIndex < 0) return false;

      const next = granularities[currentIndex + offset];
      if (!next) return false;

      this.pushFilterEvent("select_granularity", { granularity: next });
      return true;
    },

    pushFilterEvent(eventName, payload = {}) {
      if (this._eventTarget && typeof this.pushEventTo === "function") {
        this.pushEventTo(this._eventTarget, eventName, payload);
      } else {
        this.pushEvent(eventName, payload);
      }
    }
  };
};

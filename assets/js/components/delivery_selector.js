const normalise = (value) => (value || "").toLowerCase();

const unique = (arr) => [...new Set(arr)];

window.deliverySelector = function () {
  return {
    options: [],
    selected: [],
    filtered: [],
    highlighted: 0,
    hidden: null,
    input: null,
    query: "",
    open: false,
    closeTimer: null,

    init(root) {
      if (!root) return;

      this.options = this.parseOptions(root.dataset.options).map((option) => ({
        handle: option.handle,
        label: option.label,
        description: option.description || "",
        badge: option.badge || "Channel",
        search_terms: normalise(option.search_terms || `${option.label} ${option.handle}`),
      }));

      this.selected = unique(this.parseOptions(root.dataset.selected));
      this.hidden = root.querySelector('input[type="hidden"][name]');
      this.input = root.querySelector('input[type="text"]');

      if (this.hidden) {
        this.hidden.value = this.selected.join("\n");
      }

      this.filter();

      if (document.activeElement === this.input) {
        requestAnimationFrame(() => this.openDropdown());
      }
    },

    parseOptions(value) {
      if (!value) return [];

      try {
        return JSON.parse(value);
      } catch (_error) {
        return [];
      }
    },

    filter() {
      const queryNormalised = normalise(this.query);
      const selectedSet = new Set(this.selected);

      if (queryNormalised === "") {
        this.filtered = this.options.filter((option) => !selectedSet.has(option.handle)).slice(0, 10);
      } else {
        this.filtered = this.options
          .filter((option) => !selectedSet.has(option.handle) && option.search_terms.includes(queryNormalised))
          .slice(0, 10);
      }

      this.highlighted = 0;
      this.open = this.filtered.length > 0 && document.activeElement === this.input;
    },

    selectedDetails() {
      const index = new Map(this.options.map((option) => [option.handle, option]));

      return this.selected
        .map((handle) => {
          const option = index.get(handle);

          if (!option) {
            return { handle, label: handle, badge: "Custom" };
          }

          return option;
        })
        .filter(Boolean);
    },

    select(handle) {
      if (!handle) return;
      if (!this.selected.includes(handle)) {
        this.selected.push(handle);
        this.selected = unique(this.selected);
        this.syncHidden();
      }

      this.query = "";
      this.filter();
      if (this.input) this.input.focus();
      this.openDropdown();
    },

    selectHighlighted() {
      const option = this.filtered[this.highlighted];
      if (option) {
        this.select(option.handle);
      }
    },

    highlightNext() {
      if (this.filtered.length === 0) return;
      this.highlighted = (this.highlighted + 1) % this.filtered.length;
    },

    highlightPrev() {
      if (this.filtered.length === 0) return;
      this.highlighted = (this.highlighted - 1 + this.filtered.length) % this.filtered.length;
    },

    remove(handle) {
      this.selected = this.selected.filter((value) => value !== handle);
      this.syncHidden();
      this.filter();
      this.openDropdown();
    },

    syncHidden() {
      if (!this.hidden) return;
      const next = this.selected.join("\n");
      // Only update and dispatch event if the value actually changed
      if (this.hidden.value !== next) {
        this.hidden.value = next;
        this.hidden.dispatchEvent(new Event("input", { bubbles: true }));
      }
    },

    openDropdown() {
      this.cancelScheduledClose();
      this.filter();
    },

    closeDropdown() {
      this.cancelScheduledClose();
      this.open = false;
    },

    scheduleClose() {
      this.cancelScheduledClose();
      this.closeTimer = setTimeout(() => {
        if (document.activeElement !== this.input) {
          this.closeDropdown();
        }
      }, 120);
    },

    cancelScheduledClose() {
      if (this.closeTimer) {
        clearTimeout(this.closeTimer);
        this.closeTimer = null;
      }
    },
  };
};

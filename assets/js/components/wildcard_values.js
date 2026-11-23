window.wildcardValues = function (root) {
  return {
    values: JSON.parse(root.dataset.values),
    suggestions: [],
    query: "",
    open: false,
    activeIndex: -1,

    init() {
      const updateSuggestions = () => {
        this.suggestions = JSON.parse(root.dataset.suggestions);
        this.activeIndex = -1;
      };

      updateSuggestions();
      this.observer = new MutationObserver(updateSuggestions);
      this.observer.observe(root, { attributes: true, attributeFilter: ["data-suggestions"] });
    },

    destroy() {
      this.observer.disconnect();
    },

    get filtered() {
      const query = this.query.trim().toLowerCase();
      return this.suggestions
        .filter((value) => !this.values.includes(value) && value.toLowerCase().includes(query))
        .slice(0, 10);
    },

    get showSuggestions() {
      return this.open && this.filtered.length > 0;
    },

    get activeOptionId() {
      return this.showSuggestions && this.activeIndex >= 0 ? this.optionId(this.activeIndex) : null;
    },

    optionId(index) {
      return `${root.id}-option-${index}`;
    },

    onInput(event) {
      if (event.isComposing) return;

      this.query = event.target.value;
      this.activeIndex = -1;
      this.open = true;

      if (this.query.includes(",")) {
        event.stopPropagation();
        this.add();
      }
    },

    onEnter(event) {
      if (event.isComposing) return;

      event.preventDefault();
      this.add(this.showSuggestions ? this.filtered[this.activeIndex] : undefined);
    },

    onEscape(event) {
      if (!this.showSuggestions) return;

      event.stopPropagation();
      this.open = false;
      this.activeIndex = -1;
    },

    highlight(event, direction) {
      const size = this.filtered.length;
      if (!size) return;

      event.preventDefault();
      this.open = true;
      const index = this.activeIndex < 0 && direction === -1 ? size : this.activeIndex;
      this.activeIndex = (index + direction + size) % size;
      this.$nextTick(() => {
        document.getElementById(this.activeOptionId)?.scrollIntoView({ block: "nearest" });
      });
    },

    add(suggestion) {
      const entry = this.$refs.entry;
      if (suggestion === undefined && !entry.value) return;

      const values = suggestion === undefined
        ? entry.value.split(",").map((value) => value.trim()).filter(Boolean)
        : [suggestion];
      entry.value = "";
      this.query = "";
      this.activeIndex = -1;
      this.values = [...new Set([...this.values, ...values])];
      this.notifyChange();
    },

    remove(value) {
      this.values = this.values.filter((selected) => selected !== value);
      this.$refs.entry.focus();
      this.notifyChange();
    },

    notifyChange() {
      this.$nextTick(() => {
        this.$refs.changeInput.dispatchEvent(new Event("input", { bubbles: true }));
      });
    },
  };
};

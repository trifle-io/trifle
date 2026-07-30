export const registerSeriesDisplayEditorHook = (Hooks, deps = {}) => {
  const { Sortable } = deps;

  Hooks.SeriesDisplayEditor = {
    mounted() {
      this.changeTimer = null;
      this.form = this.el.closest('form');
      this.bindElements();
      this.advancedOpen = this.shouldForceAdvancedOpen() || this.el.open;
      this.setupSortable();

      this.handleClick = (event) => {
        const modeButton = event.target.closest('[data-series-display-mode-button]');
        if (modeButton) {
          event.preventDefault();
          this.switchMode(modeButton.dataset.seriesDisplayModeButton);
          return;
        }

        const actionButton = event.target.closest('[data-action]');
        if (!actionButton) return;

        const action = actionButton.dataset.action;
        if (!action) return;

        event.preventDefault();
        this.handleAction(action, actionButton);
      };

      this.handleInput = (event) => {
        const input = event.target;
        if (!input) return;

        if (this.isVisualInput(input)) {
          event.stopPropagation();
          this.markRowState(input.closest('[data-alias-row], [data-priority-row]'));
          this.ensureTrailingRows();
          this.syncVisualToRaw();
          if (this.shouldQueueVisualInput(input)) this.queueFormChange();
        }
      };

      this.handleChange = (event) => {
        const input = event.target;
        if (!input) return;

        if (this.isVisualInput(input)) {
          event.stopPropagation();
          this.syncVisualToRaw();
          if (this.shouldQueueVisualInput(input)) this.queueFormChange();
        }
      };

      this.handlePaste = (event) => {
        const input = event.target;
        if (!input) return;

        if (input.matches('[data-role="series-alias-key"], [data-role="series-alias-value"]')) {
          this.handleAliasPaste(event);
        } else if (input.matches('[data-role="series-priority-value"]')) {
          this.handlePriorityPaste(event);
        }
      };

      this.handleSubmit = () => {
        if (this.modeInput && this.modeInput.value !== 'raw') {
          this.syncVisualToRaw();
        }
      };

      this.handleToggle = () => {
        this.advancedOpen = this.el.open;
      };

      this.el.addEventListener('click', this.handleClick);
      this.el.addEventListener('input', this.handleInput);
      this.el.addEventListener('change', this.handleChange);
      this.el.addEventListener('paste', this.handlePaste);
      this.el.addEventListener('toggle', this.handleToggle);
      if (this.form) this.form.addEventListener('submit', this.handleSubmit, true);

      if (this.modeInput && this.modeInput.value !== 'raw') {
        this.syncVisualToRaw();
      }
    },

    updated() {
      this.bindElements();
      this.restoreAdvancedOpen();
      this.setupSortable();
    },

    destroyed() {
      if (this.changeTimer) {
        clearTimeout(this.changeTimer);
        this.changeTimer = null;
      }

      if (this.prioritySortable) {
        this.prioritySortable.destroy();
        this.prioritySortable = null;
      }

      if (this.handleClick) this.el.removeEventListener('click', this.handleClick);
      if (this.handleInput) this.el.removeEventListener('input', this.handleInput);
      if (this.handleChange) this.el.removeEventListener('change', this.handleChange);
      if (this.handlePaste) this.el.removeEventListener('paste', this.handlePaste);
      if (this.handleToggle) this.el.removeEventListener('toggle', this.handleToggle);
      if (this.form && this.handleSubmit) {
        this.form.removeEventListener('submit', this.handleSubmit, true);
      }
    },

    bindElements() {
      this.inputDebounce = (this.form && this.form.dataset.deferredInputDebounce) || '600';
      this.modeInput = this.el.querySelector('[data-role="series-display-mode"]');
      this.aliasRaw = this.el.querySelector('[data-role="series-aliases-raw"]');
      this.aliasRawError = this.el.querySelector('[data-role="series-aliases-raw-error"]');
      this.priorityRaw = this.el.querySelector('[data-role="series-priority-raw"]');
      this.priorityLastRaw = this.el.querySelector('[data-role="series-priority-last-raw"]');
      this.aliasList = this.el.querySelector('[data-role="series-aliases-list"]');
      this.priorityList = this.el.querySelector('[data-role="series-priority-list"]');
      this.aliasTemplate = this.el.querySelector('[data-role="series-alias-row-template"]');
      this.priorityTemplate = this.el.querySelector('[data-role="series-priority-row-template"]');
      this.applyDeferredInputs(this.el);
      this.dedupeRemoveIcons(this.el);
    },

    restoreAdvancedOpen() {
      if (this.shouldForceAdvancedOpen()) {
        this.advancedOpen = true;
      }

      this.el.open = Boolean(this.advancedOpen);
    },

    shouldForceAdvancedOpen() {
      if (!this.aliasRawError || this.aliasRawError.hidden) return false;
      return (this.aliasRawError.textContent || '').trim() !== '';
    },

    applyDeferredInputs(root) {
      if (!root) return;

      root.querySelectorAll('textarea, input[type="text"], input:not([type])').forEach((input) => {
        if (input.hasAttribute('phx-debounce') || input.hasAttribute('data-immediate-change')) {
          return;
        }

        input.setAttribute('phx-debounce', input.dataset.deferredInputDebounce || this.inputDebounce);
      });
    },

    dedupeRemoveIcons(root) {
      if (!root) return;

      root.querySelectorAll('button[data-action$="-remove"]').forEach((button) => {
        const icons = Array.from(button.querySelectorAll('[data-row-remove-icon], svg'));
        icons.slice(1).forEach((icon) => icon.remove());
      });
    },

    setupSortable() {
      if (this.prioritySortable) {
        this.prioritySortable.destroy();
        this.prioritySortable = null;
      }

      if (!Sortable || !this.priorityList) return;

      this.prioritySortable = Sortable.create(this.priorityList, {
        animation: 150,
        handle: '[data-priority-drag-handle]',
        draggable: '[data-priority-row]',
        filter: '[data-empty-row="true"]',
        ghostClass: 'sortable-ghost',
        chosenClass: 'sortable-chosen',
        dragClass: 'sortable-drag',
        onEnd: () => {
          this.ensureTrailingPriorityRows();
          this.reindexPriorityRows();
          this.syncVisualToRaw();
          this.queueFormChange();
        }
      });
    },

    switchMode(mode) {
      if (!['visual', 'raw'].includes(mode) || !this.modeInput) return;

      if (mode === 'visual') {
        if (!this.loadRawIntoVisual()) return;
        this.syncVisualToRaw();
      } else {
        this.syncVisualToRaw();
      }

      this.modeInput.value = mode;
      this.updateModeVisibility(mode);
      this.queueFormChange();
    },

    updateModeVisibility(mode) {
      this.el.querySelectorAll('[data-series-display-mode-panel]').forEach((panel) => {
        panel.hidden = panel.dataset.seriesDisplayModePanel !== mode;
      });

      this.el.querySelectorAll('[data-series-display-mode-button]').forEach((button) => {
        const selected = button.dataset.seriesDisplayModeButton === mode;
        button.setAttribute('aria-pressed', selected ? 'true' : 'false');
        this.applyModeButtonClasses(button, selected);
      });
    },

    applyModeButtonClasses(button, selected) {
      // Mirrors TrifleApp.DesignSystem.ButtonGroup size="sm" classes.
      const base = [
        'relative',
        'inline-flex',
        'items-center',
        'px-2.5',
        'h-8',
        'text-sm',
        'font-medium',
        'transition-colors',
        'focus-visible:outline-none',
        'focus-visible:bg-white',
        'active:bg-white',
        'dark:focus-visible:bg-slate-800',
        'dark:active:bg-slate-800'
      ];

      const edge = button.dataset.seriesDisplayModeButton === 'raw'
        ? ['rounded-r-md', 'border-l', 'border-gray-200', 'dark:border-slate-700']
        : ['rounded-l-md'];

      const state = selected
        ? [
            'bg-white',
            'dark:bg-slate-800',
            'text-teal-500',
            'dark:text-teal-300',
            'font-semibold',
            'border-b-2',
            'border-b-teal-500',
            'dark:border-b-teal-400'
          ]
        : [
            'bg-white',
            'dark:bg-slate-800/80',
            'text-gray-700',
            'dark:text-slate-300',
            'hover:bg-gray-100',
            'dark:hover:bg-slate-700'
          ];

      button.className = base.concat(edge, state).join(' ');
    },

    handleAction(action, button) {
      if (action === 'alias-remove') {
        const row = button.closest('[data-alias-row]');
        if (!row) return;
        row.remove();
        this.ensureTrailingAliasRow();
        this.reindexAliasRows();
        this.syncVisualToRaw();
        this.queueFormChange();
        return;
      }

      const row = button.closest('[data-priority-row]');
      if (!row) return;

      if (action === 'priority-remove') {
        row.remove();
      } else {
        return;
      }

      this.ensureTrailingPriorityRows();
      this.reindexPriorityRows();
      this.syncVisualToRaw();
      this.queueFormChange();
    },

    isVisualInput(input) {
      return input.matches(
        '[data-role="series-alias-key"], [data-role="series-alias-value"], [data-role="series-priority-value"]'
      );
    },

    shouldQueueVisualInput(input) {
      if (input.matches('[data-role="series-priority-value"]')) return true;

      const row = input.closest('[data-alias-row]');
      if (!row) return false;

      const keyInput = row.querySelector('[data-role="series-alias-key"]');
      const valueInput = row.querySelector('[data-role="series-alias-value"]');
      const key = keyInput ? (keyInput.value || '').trim() : '';
      const value = valueInput ? (valueInput.value || '').trim() : '';

      return (key && value) || (!key && !value);
    },

    markRowState(row) {
      if (!row) return;
      row.dataset.emptyRow = this.rowHasValue(row) ? 'false' : 'true';
    },

    rowHasValue(row) {
      return Array.from(row.querySelectorAll('input:not([type="hidden"])')).some((input) => {
        return (input.value || '').trim() !== '';
      });
    },

    ensureTrailingRows() {
      this.ensureTrailingAliasRow();
      this.ensureTrailingPriorityRows();
    },

    ensureTrailingAliasRow() {
      if (!this.aliasList || !this.aliasTemplate) return;
      const rows = this.aliasRows();
      const last = rows[rows.length - 1];
      if (!last || this.rowHasValue(last)) {
        this.aliasList.appendChild(this.buildRowFromTemplate(this.aliasTemplate, rows.length));
      }
    },

    ensureTrailingPriorityRows() {
      if (!this.priorityList || !this.priorityTemplate) return;
      this.ensureTrailingPriorityRowForGroup('first');
      this.ensureTrailingPriorityRowForGroup('last');
    },

    ensureTrailingPriorityRowForGroup(group) {
      const rows = this.priorityRowsByGroup()[group];
      const last = rows[rows.length - 1];
      if (!last || this.rowHasValue(last)) {
        const row = this.buildRowFromTemplate(this.priorityTemplate, this.priorityRows().length);
        this.setPriorityGroup(row, group);
        this.insertPriorityRow(row, group);
      }
    },

    buildRowFromTemplate(template, index) {
      const row = template.content.firstElementChild.cloneNode(true);
      this.setRowIndex(row, index);
      row.dataset.emptyRow = 'true';
      this.applyDeferredInputs(row);
      this.dedupeRemoveIcons(row);
      return row;
    },

    setRowIndex(row, index) {
      row.dataset.index = String(index);
      if (row.id) row.id = row.id.replace(/-(?:__INDEX__|\d+)$/, `-${index}`);
      row.querySelectorAll('[name]').forEach((input) => {
        input.name = input.name.replace(/\[(?:__INDEX__|\d+)\]/, `[${index}]`);
      });
    },

    reindexAliasRows() {
      this.aliasRows().forEach((row, index) => this.setRowIndex(row, index));
    },

    reindexPriorityRows() {
      this.syncPriorityGroups();
      this.priorityRows().forEach((row, index) => this.setRowIndex(row, index));
    },

    aliasRows() {
      return this.aliasList ? Array.from(this.aliasList.querySelectorAll('[data-alias-row]')) : [];
    },

    priorityRows() {
      return this.priorityList ? Array.from(this.priorityList.querySelectorAll('[data-priority-row]')) : [];
    },

    priorityDivider() {
      return this.priorityList ? this.priorityList.querySelector('[data-priority-divider]') : null;
    },

    priorityRowsByGroup() {
      const grouped = { first: [], last: [] };
      if (!this.priorityList) return grouped;

      let group = 'first';
      Array.from(this.priorityList.children).forEach((child) => {
        if (child.matches('[data-priority-divider]')) {
          group = 'last';
          return;
        }

        if (child.matches('[data-priority-row]')) {
          grouped[group].push(child);
        }
      });

      return grouped;
    },

    insertPriorityRow(row, group) {
      if (!this.priorityList) return;

      const divider = this.priorityDivider();
      if (group === 'first' && divider) {
        this.priorityList.insertBefore(row, divider);
      } else {
        this.priorityList.appendChild(row);
      }
    },

    syncPriorityGroups() {
      const grouped = this.priorityRowsByGroup();
      grouped.first.forEach((row) => this.setPriorityGroup(row, 'first'));
      grouped.last.forEach((row) => this.setPriorityGroup(row, 'last'));
    },

    setPriorityGroup(row, group) {
      row.dataset.priorityGroup = group;
      const groupInput = row.querySelector('[data-role="series-priority-group"]');
      if (groupInput) groupInput.value = group;
    },

    readAliases() {
      const aliases = {};

      this.aliasRows().forEach((row) => {
        const keyInput = row.querySelector('[data-role="series-alias-key"]');
        const valueInput = row.querySelector('[data-role="series-alias-value"]');
        const key = keyInput ? (keyInput.value || '').trim() : '';
        const value = valueInput ? (valueInput.value || '').trim() : '';
        if (key && value) aliases[key] = value;
      });

      return aliases;
    },

    readPriority() {
      this.syncPriorityGroups();
      const grouped = this.priorityRowsByGroup();
      const readRows = (rows) => rows
        .map((row) => {
          const input = row.querySelector('[data-role="series-priority-value"]');
          return input ? (input.value || '').trim() : '';
        })
        .filter(Boolean);

      return {
        first: readRows(grouped.first),
        last: readRows(grouped.last)
      };
    },

    syncVisualToRaw() {
      const aliases = this.readAliases();
      const aliasKeys = Object.keys(aliases);
      if (this.aliasRaw) {
        this.aliasRaw.value = aliasKeys.length > 0 ? JSON.stringify(aliases, null, 2) : '';
      }

      if (this.priorityRaw) {
        const priority = this.readPriority();
        this.priorityRaw.value = priority.first.join('\n');
        if (this.priorityLastRaw) this.priorityLastRaw.value = priority.last.join('\n');
      }
    },

    loadRawIntoVisual() {
      const parsedAliases = this.parseAliasesRaw();
      if (!parsedAliases.ok) {
        this.showAliasRawError(parsedAliases.error);
        return false;
      }

      this.showAliasRawError(null);
      this.replaceAliasRows(Object.entries(parsedAliases.aliases));
      this.replacePriorityRows(this.parsePriorityRaw(this.priorityRaw), this.parsePriorityRaw(this.priorityLastRaw));
      return true;
    },

    parseAliasesRaw() {
      const value = this.aliasRaw ? (this.aliasRaw.value || '').trim() : '';
      if (!value) return { ok: true, aliases: {} };

      try {
        const parsed = JSON.parse(value);
        if (!parsed || Array.isArray(parsed) || typeof parsed !== 'object') {
          return { ok: false, error: 'Aliases must be a JSON object.' };
        }

        const aliases = {};
        Object.entries(parsed).forEach(([key, alias]) => {
          const normalizedKey = String(key || '').trim();
          const normalizedAlias = String(alias || '').trim();
          if (normalizedKey && normalizedAlias) aliases[normalizedKey] = normalizedAlias;
        });

        return { ok: true, aliases };
      } catch (_) {
        return { ok: false, error: 'Aliases must be valid JSON.' };
      }
    },

    parsePriorityRaw(rawInput) {
      const value = rawInput ? rawInput.value || '' : '';
      return value
        .split(/[\n,]+/)
        .map((item) => item.trim())
        .filter(Boolean);
    },

    showAliasRawError(message) {
      if (!this.aliasRawError) return;
      this.aliasRawError.textContent = message || '';
      this.aliasRawError.hidden = !message;
    },

    replaceAliasRows(entries) {
      if (!this.aliasList) return;
      this.aliasRows().forEach((row) => row.remove());
      entries.forEach(([key, value], index) => {
        const row = this.buildRowFromTemplate(this.aliasTemplate, index);
        row.querySelector('[data-role="series-alias-key"]').value = key;
        row.querySelector('[data-role="series-alias-value"]').value = value;
        row.dataset.emptyRow = 'false';
        this.aliasList.appendChild(row);
      });
      this.ensureTrailingAliasRow();
      this.reindexAliasRows();
    },

    replacePriorityRows(firstValues, lastValues = []) {
      if (!this.priorityList) return;
      this.priorityRows().forEach((row) => row.remove());
      firstValues.forEach((value, index) => {
        const row = this.buildRowFromTemplate(this.priorityTemplate, index);
        row.querySelector('[data-role="series-priority-value"]').value = value;
        row.dataset.emptyRow = 'false';
        this.setPriorityGroup(row, 'first');
        this.insertPriorityRow(row, 'first');
      });
      lastValues.forEach((value, index) => {
        const row = this.buildRowFromTemplate(this.priorityTemplate, firstValues.length + index);
        row.querySelector('[data-role="series-priority-value"]').value = value;
        row.dataset.emptyRow = 'false';
        this.setPriorityGroup(row, 'last');
        this.insertPriorityRow(row, 'last');
      });
      this.ensureTrailingPriorityRows();
      this.reindexPriorityRows();
    },

    replacePriorityGroupRows(group, values) {
      if (!this.priorityList) return;

      this.priorityRowsByGroup()[group].forEach((row) => row.remove());
      values.forEach((value, index) => {
        const row = this.buildRowFromTemplate(this.priorityTemplate, index);
        row.querySelector('[data-role="series-priority-value"]').value = value;
        row.dataset.emptyRow = 'false';
        this.setPriorityGroup(row, group);
        this.insertPriorityRow(row, group);
      });
      this.ensureTrailingPriorityRows();
      this.reindexPriorityRows();
    },

    handleAliasPaste(event) {
      const text = event.clipboardData ? event.clipboardData.getData('text') : '';
      const entries = this.parseAliasPaste(text);
      if (entries.length === 0) return;

      event.preventDefault();
      this.replaceAliasRows(entries);
      this.syncVisualToRaw();
      this.queueFormChange();
    },

    handlePriorityPaste(event) {
      const text = event.clipboardData ? event.clipboardData.getData('text') : '';
      const values = this.parsePriorityPaste(text);
      if (values.length === 0) return;

      event.preventDefault();
      const row = event.target.closest('[data-priority-row]');
      const group = row && row.dataset.priorityGroup === 'last' ? 'last' : 'first';
      this.replacePriorityGroupRows(group, values);
      this.syncVisualToRaw();
      this.queueFormChange();
    },

    parseAliasPaste(text) {
      const trimmed = (text || '').trim();
      if (!trimmed) return [];

      try {
        const parsed = JSON.parse(trimmed);
        if (parsed && !Array.isArray(parsed) && typeof parsed === 'object') {
          return Object.entries(parsed)
            .map(([key, value]) => [String(key || '').trim(), String(value || '').trim()])
            .filter(([key, value]) => key && value);
        }
      } catch (_) {}

      return trimmed
        .split(/\r?\n/)
        .map((line) => this.parseAliasLine(line))
        .filter(Boolean);
    },

    parseAliasLine(line) {
      const trimmed = (line || '').trim();
      if (!trimmed) return null;

      const tabParts = trimmed.split('\t');
      if (tabParts.length >= 2) {
        return this.aliasEntry(tabParts[0], tabParts.slice(1).join('\t'));
      }

      const dashMatch = trimmed.match(/^(.*?)\s+-\s+(.*?)$/);
      if (dashMatch) return this.aliasEntry(dashMatch[1], dashMatch[2]);

      const colonMatch = trimmed.match(/^([^:]+?)\s*:\s*(.*?)$/);
      if (colonMatch) return this.aliasEntry(colonMatch[1], colonMatch[2]);

      return null;
    },

    aliasEntry(key, value) {
      const normalizedKey = (key || '').trim();
      const normalizedValue = (value || '').trim();
      return normalizedKey && normalizedValue ? [normalizedKey, normalizedValue] : null;
    },

    parsePriorityPaste(text) {
      const trimmed = (text || '').trim();
      if (!trimmed) return [];

      try {
        const parsed = JSON.parse(trimmed);
        if (Array.isArray(parsed)) {
          return parsed.map((value) => String(value || '').trim()).filter(Boolean);
        }
      } catch (_) {}

      return trimmed
        .split(/[\r\n,]+/)
        .map((value) => value.trim())
        .filter(Boolean);
    },

    queueFormChange() {
      if (this.changeTimer) clearTimeout(this.changeTimer);
      const delay = Number.parseInt(this.inputDebounce || '600', 10);

      this.changeTimer = setTimeout(() => {
        this.changeTimer = null;
        const target = this.modeInput || this.aliasRaw || this.priorityRaw;
        if (!target) return;
        target.dispatchEvent(new Event('change', { bubbles: true }));
      }, Number.isFinite(delay) ? delay : 600);
    }
  };
};

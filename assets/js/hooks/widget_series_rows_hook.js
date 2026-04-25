export const registerWidgetSeriesRowsHook = (Hooks, deps = {}) => {
Hooks.WidgetSeriesRows = {
  mounted() {
    this.widgetId = this.el.dataset.widgetId;
    this.eventName = this.el.dataset.eventName || 'widget_series_rows_update';
    this.inputDebounceMs = 250;
    this._rowsInputTimer = null;
    this._lastRowsPayload = null;
    this._eventTarget = this.el.closest('[data-phx-component]') || null;

    this.emitRows = (rows) => {
      const payload = {
        widget_id: this.widgetId,
        rows
      };

      if (this._eventTarget && typeof this.pushEventTo === 'function') {
        this.pushEventTo(this._eventTarget, this.eventName, payload);
      } else {
        this.pushEvent(this.eventName, payload);
      }
    };

    this.pushRows = (rows) => {
      const payload = JSON.stringify(rows || []);
      if (payload === this._lastRowsPayload) return;
      this._lastRowsPayload = payload;
      this.emitRows(rows);
    };

    this.queueRowsPush = () => {
      if (this._rowsInputTimer) clearTimeout(this._rowsInputTimer);

      // Keep the editor responsive and avoid rebuilding the preview on every keypress.
      this._rowsInputTimer = setTimeout(() => {
        this._rowsInputTimer = null;
        this.pushRows(this.readRows());
      }, this.inputDebounceMs);
    };

    this.flushRowsPush = () => {
      if (this._rowsInputTimer) {
        clearTimeout(this._rowsInputTimer);
        this._rowsInputTimer = null;
      }

      this.pushRows(this.readRows());
    };

    this.handleClick = (event) => {
      const button = event.target.closest('[data-action]');
      if (!button) return;

      const action = button.dataset.action;
      if (!action) return;

      event.preventDefault();

      const rows = this.readRows();
      const index = Number.parseInt(button.dataset.index || '-1', 10);

      if (action === 'add' || action === 'add_query') {
        rows.push(this.defaultRow('path'));
      } else if (action === 'add_formula') {
        rows.push(this.defaultRow('expression'));
      } else if (action === 'remove') {
        if (!Number.isNaN(index)) rows.splice(index, 1);
        if (rows.length === 0) rows.push(this.defaultRow('path'));
      } else {
        return;
      }

      if (this._rowsInputTimer) {
        clearTimeout(this._rowsInputTimer);
        this._rowsInputTimer = null;
      }

      this.pushRows(rows);
    };

    this.handleChange = (event) => {
      const input = event.target;
      if (!input) return;

      if (input.matches('input[data-role="series-kind"]')) {
        event.stopPropagation();
        this.pushRows(this.readRows());
        return;
      }

      if (input.matches('input[data-role="series-visible"]')) {
        event.stopPropagation();
        this.pushRows(this.readRows());
        return;
      }

      if (input.matches('input[type="radio"][name^="widget_series_color_selector["]')) {
        event.stopPropagation();
        this.pushRows(this.readRows());
        return;
      }

      if (input.matches('input[data-role="series-color"]')) {
        event.stopPropagation();
        this.pushRows(this.readRows());
        return;
      }

      if (input.matches('input[data-role="series-path"], input[data-role="series-expression"], input[data-role="series-label"]')) {
        event.stopPropagation();
        this.flushRowsPush();
      }
    };

    this.handleInput = (event) => {
      const input = event.target;
      if (!input) return;

      if (input.matches('input[data-role="series-path"], input[data-role="series-expression"], input[data-role="series-label"]')) {
        event.stopPropagation();
        this.queueRowsPush();
      }
    };

    this.el.addEventListener('click', this.handleClick);
    this.el.addEventListener('change', this.handleChange);
    this.el.addEventListener('input', this.handleInput);

    this._lastRowsPayload = JSON.stringify(this.readRows());
  },

  updated() {
    this.widgetId = this.el.dataset.widgetId;
    this.eventName = this.el.dataset.eventName || 'widget_series_rows_update';
    this._eventTarget = this.el.closest('[data-phx-component]') || null;
    this._lastRowsPayload = JSON.stringify(this.readRows());
  },

  destroyed() {
    if (this._rowsInputTimer) {
      clearTimeout(this._rowsInputTimer);
      this._rowsInputTimer = null;
    }

    if (this.handleClick) {
      this.el.removeEventListener('click', this.handleClick);
    }

    if (this.handleChange) {
      this.el.removeEventListener('change', this.handleChange);
    }

    if (this.handleInput) {
      this.el.removeEventListener('input', this.handleInput);
    }
  },

  defaultRow(kind = 'path') {
    return {
      kind,
      path: '',
      expression: '',
      label: '',
      visible: true,
      color_selector: 'default.*'
    };
  },

  readRows() {
    return Array.from(this.el.querySelectorAll('[data-series-row]')).map((rowEl) => {
      const valueFor = (selector) => {
        const input = rowEl.querySelector(selector);
        return input ? input.value || '' : '';
      };

      const checkedColor = rowEl.querySelector(
        'input[data-role="series-color"]:checked'
      );
      const kindInput = rowEl.querySelector('input[data-role="series-kind"]:checked');
      const visibleInput = rowEl.querySelector('input[data-role="series-visible"]');

      return {
        kind: kindInput ? kindInput.value || 'path' : 'path',
        path: valueFor('input[data-role="series-path"]'),
        expression: valueFor('input[data-role="series-expression"]'),
        label: valueFor('input[data-role="series-label"]'),
        visible: !!(visibleInput && visibleInput.checked),
        color_selector: checkedColor ? checkedColor.value || 'default.*' : 'default.*'
      };
    });
  }
}


};

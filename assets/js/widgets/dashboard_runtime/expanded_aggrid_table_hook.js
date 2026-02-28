export const registerExpandedAgGridTableHook = (Hooks, deps) => {
  const {
    AGGRID_PATH_COL_MIN_WIDTH,
    AGGRID_PATH_COL_MAX_WIDTH,
    ensureAgGridCommunity,
    getAggridHeaderComponentClass,
    parseJsonSafe
  } = deps;
Hooks.ExpandedAgGridTable = {
  mounted() {
    this.grid = null;
    this.gridOptions = null;
    this.lastPayload = null;
    this.handleThemeChange = () => this.applyTheme();
    window.addEventListener('trifle:theme-changed', this.handleThemeChange);
    this.render();
    setTimeout(() => this.render(), 150);
  },

  updated() {
    this.render();
  },

  destroyed() {
    window.removeEventListener('trifle:theme-changed', this.handleThemeChange);
    this.destroyGrid();
  },

  render() {
    const payloadString = this.el.dataset.table || '';
    const root = this.el.querySelector('[data-role="aggrid-table-root"]');
    const gridRootReplaced =
      !!this.grid &&
      (
        !this.grid.root ||
        this.grid.root !== root ||
        !this.grid.root.isConnected
      );
    const gridDomWiped =
      !!this.grid &&
      !!root &&
      !root.querySelector('.ag-root-wrapper, .ag-root');

    if (gridRootReplaced || gridDomWiped) {
      this.destroyGrid();
    }

    if (!payloadString) {
      this.showEmpty();
      return;
    }
    if (payloadString === this.lastPayload && this.grid) {
      this.applyTheme();
      return;
    }
    this.lastPayload = payloadString;
    const payload = parseJsonSafe(payloadString);
    if (!payload) {
      this.showEmpty();
      return;
    }
    const rows = Array.isArray(payload.rows) ? payload.rows : [];
    if (rows.length === 0) {
      this.destroyGrid();
      this.showEmpty(payload.empty_message);
      return;
    }
    ensureAgGridCommunity()
      .then(() => this.renderGrid(payload))
      .catch((err) => {
        console.error('[ExpandedAgGridTable] Failed to load ag-grid-community', err);
        this.showEmpty('Unable to load table data.');
      });
  },

  renderGrid(payload) {
    const root = this.el.querySelector('[data-role="aggrid-table-root"]');
    if (!root) return;
    this.applyTheme();
    const shell = this.el;
    const shellHeight = shell && shell.clientHeight > 0 ? shell.clientHeight : (shell && shell.parentElement ? shell.parentElement.clientHeight : 0);
    const fallbackHeight = shellHeight > 0 ? shellHeight : 520;
    root.style.width = '100%';
    root.style.height = `${fallbackHeight}px`;
    root.style.minHeight = '400px';
    root.style.flex = '1 1 auto';
    const tableId = this.normalizeId(payload && payload.id);
    this.tableId = tableId;
    if (!this.grid || this.grid.root !== root || !this.grid.api) {
      this.destroyGrid();
      this.createGrid(root);
    }

    const columnDefs = this.buildColumns(payload);
    const rowData = this.buildRows(payload);

    try {
      this.grid.api.setColumnDefs(columnDefs);
      this.grid.api.setRowData(rowData);
      requestAnimationFrame(() => {
        try {
          this.autoSizePathColumn();
        } catch (_) {}
        try {
          this.grid.api.sizeColumnsToFit();
        } catch (_) {}
      });
    } catch (err) {
      console.error('[ExpandedAgGridTable] Failed to render grid', err);
      this.showEmpty('Unable to render table.');
    }
  },

  createGrid(root) {
    const agGrid = window.agGrid;
    if (!agGrid || typeof agGrid.Grid !== 'function') return;
    root.innerHTML = '';
    const gridOptions = {
      columnDefs: [],
      rowData: [],
      suppressCellFocus: true,
      suppressMovableColumns: true,
      suppressRowClickSelection: true,
      rowSelection: 'single',
      animateRows: false,
      rowHeight: 28,
      headerHeight: 48,
      enableRangeSelection: true,
      enableCellTextSelection: true,
      defaultColDef: {
        sortable: false,
        filter: false,
        resizable: false,
        flex: 1,
        headerComponent: getAggridHeaderComponentClass()
      }
    };
    new agGrid.Grid(root, gridOptions);
    this.grid = {
      api: gridOptions.api,
      columnApi: gridOptions.columnApi,
      root
    };
  },

  destroyGrid() {
    if (this.grid && this.grid.api && typeof this.grid.api.destroy === 'function') {
      try {
        this.grid.api.destroy();
      } catch (_) {}
    }
    this.grid = null;
  },

  showEmpty(message) {
    const root = this.el.querySelector('[data-role="aggrid-table-root"]');
    if (!root) return;
    this.destroyGrid();
    root.classList.remove('ag-theme-alpine', 'ag-theme-alpine-dark');
    root.innerHTML = `
      <div class="h-full w-full flex items-center justify-center text-sm text-slate-500 dark:text-slate-300 px-6 text-center">
        ${this.escapeHtml(message || 'No data available yet.')}
      </div>
    `;
  },

  applyTheme() {
    const root = this.el.querySelector('[data-role="aggrid-table-root"]');
    if (!root) return;
    const isDark = document.documentElement.classList.contains('dark');
    this.el.dataset.theme = isDark ? 'dark' : 'light';
    root.classList.remove('ag-theme-alpine', 'ag-theme-alpine-dark');
    root.classList.add(isDark ? 'ag-theme-alpine-dark' : 'ag-theme-alpine');
    if (this.grid && this.grid.api) {
      try {
        this.grid.api.refreshCells({ force: true });
        this.grid.api.redrawRows();
      } catch (_) {}
      requestAnimationFrame(() => {
        try {
          this.grid.api.sizeColumnsToFit();
        } catch (_) {}
      });
    }
  },

  buildColumns(payload) {
    const columns = Array.isArray(payload.columns) ? payload.columns : [];
    const defs = [
      {
        field: 'path',
        headerName: 'Path',
        pinned: 'left',
        lockPinned: true,
        suppressMovable: true,
        minWidth: AGGRID_PATH_COL_MIN_WIDTH,
        maxWidth: AGGRID_PATH_COL_MAX_WIDTH,
        width: AGGRID_PATH_COL_MIN_WIDTH,
        suppressSizeToFit: true,
        resizable: true,
        cellRenderer: (params) => {
          const wrapper = document.createElement('div');
          wrapper.className = 'aggrid-path-cell';
          const html = params && params.data ? params.data.__pathHtml : '';
          if (html && typeof html === 'string') {
            wrapper.innerHTML = html;
          } else {
            wrapper.textContent =
              params && params.value != null ? String(params.value) : (params && params.data && params.data.path) || '';
          }
          return wrapper;
        },
        cellClass: 'aggrid-path-cell-wrapper aggrid-body-cell ag-left-aligned-cell',
        headerClass: 'aggrid-header-cell ag-left-aligned-header',
        headerComponentParams: { lines: ['Path'], align: 'left' }
      }
    ];

    columns.forEach((column, idx) => {
      const label = this.stripHtml(column && column.label ? column.label : `Column ${idx + 1}`);
      defs.push({
        field: `col_${idx}`,
        headerName: label,
        headerTooltip: label,
        type: 'numericColumn',
        minWidth: 120,
        flex: 1,
        valueFormatter: (params) => {
          if (!params || params.value === null || params.value === undefined || params.value === '') return '';
          const numeric = Number(params.value);
          if (!Number.isFinite(numeric)) return String(params.value);
          return numeric.toLocaleString(undefined, { maximumFractionDigits: 2 });
        },
        cellClass: 'aggrid-numeric-cell aggrid-body-cell ag-right-aligned-cell',
        headerClass: 'aggrid-header-cell ag-right-aligned-header',
        headerComponentParams: { lines: [label], align: 'right' }
      });
    });

    return defs;
  },

  buildRows(payload) {
    const columns = Array.isArray(payload.columns) ? payload.columns : [];
    const rows = Array.isArray(payload.rows) ? payload.rows : [];
    return rows.map((row) => {
      const data = {
        path: row && (row.display_path || row.path || ''),
        __pathHtml: row && row.path_html ? row.path_html : ''
      };
      const values = Array.isArray(row && row.values) ? row.values : [];
      columns.forEach((_, idx) => {
        data[`col_${idx}`] = values[idx] != null ? values[idx] : '';
      });
      return data;
    });
  },

  stripHtml(input) {
    if (!input || typeof input !== 'string') return '';
    return input.replace(/<[^>]*>/g, '').trim();
  },

  escapeHtml(text) {
    if (text == null) return '';
    return String(text)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  },

  normalizeId(id) {
    if (id == null) return null;
    if (typeof id === 'string') return id;
    if (typeof id === 'number') return String(id);
    if (typeof id === 'object' && 'toString' in id) return String(id);
    return null;
  },

  autoSizePathColumn() {
    if (!this.grid || !this.grid.columnApi) return;
    const column = this.grid.columnApi.getColumn('path');
    if (!column) return;
    try {
      this.grid.columnApi.autoSizeColumns(['path'], false);
    } catch (_) {}
    const colDef = column.getColDef ? column.getColDef() : null;
    const minWidth = (colDef && Number.isFinite(colDef.minWidth)) ? colDef.minWidth : AGGRID_PATH_COL_MIN_WIDTH;
    const maxWidth = (colDef && Number.isFinite(colDef.maxWidth)) ? colDef.maxWidth : AGGRID_PATH_COL_MAX_WIDTH;
    let width = null;
    try {
      width = column.getActualWidth ? column.getActualWidth() : null;
    } catch (_) {
      width = null;
    }
    if (!Number.isFinite(width)) return;
    const clamped = Math.max(minWidth || AGGRID_PATH_COL_MIN_WIDTH, Math.min(maxWidth || AGGRID_PATH_COL_MAX_WIDTH, width));
    if (clamped !== width) {
      try { this.grid.columnApi.setColumnWidth(column, clamped); } catch (_) {}
    }
  }
};
};

export const createDashboardGridTableRendererMethods = ({
  Hooks,
  TABLE_PATH_HTML_FIELD,
  AGGRID_PATH_COL_MIN_WIDTH,
  AGGRID_PATH_COL_MAX_WIDTH,
  ensureAgGridCommunity,
  getAggridHeaderComponentClass,
  sanitizeRichHtml
}) => ({
  _render_table(items) {
    if (!Array.isArray(items)) return;
    this._lastTable = this._deepClone(items);
    const seenAggridTables = new Set();

    items.forEach((it) => {
      const item = this.el.querySelector(`.grid-stack-item[gs-id="${it.id}"]`);
      const body = item && item.querySelector('.grid-widget-body');
      if (!body) return;

      body.className = 'grid-widget-body flex-1 flex flex-col min-h-0';
      const tableId = this._tableKey(it.id);

      if (!it.rows || !it.rows.length || !it.columns || !it.columns.length) {
        this._destroy_aggrid_table(tableId);
        body.innerHTML = `<div class="h-full w-full flex items-center justify-center text-sm text-slate-500 dark:text-slate-300 px-6 text-center">${this.escapeHtml(it.empty_message || 'No data available yet.')}</div>`;
        return;
      }

      body.innerHTML = this._build_aggrid_table_html(it);
      this._render_aggrid_table(body, it);
      if (tableId) seenAggridTables.add(tableId);
    });

    if (this._aggridTables) {
      Object.keys(this._aggridTables).forEach((id) => {
        if (!seenAggridTables.has(id)) {
          this._destroy_aggrid_table(id);
        }
      });
    }
  },

  _activate_tooltips_for_element(element) {
    if (!element || !Hooks || !Hooks.FastTooltip) return;
    const fastTooltip = Hooks.FastTooltip;
    if (typeof fastTooltip.initTooltips !== 'function') return;
    const context = {
      el: element,
      showTooltip: fastTooltip.showTooltip.bind(fastTooltip),
      hideTooltip: fastTooltip.hideTooltip.bind(fastTooltip)
    };
    requestAnimationFrame(() => {
      try {
        fastTooltip.initTooltips.call(context);
      } catch (_) {}
    });
  },


  _build_aggrid_table_html(payload) {
    const idAttr = payload && payload.id != null ? ` data-aggrid-id="${this.escapeHtml(String(payload.id))}"` : '';
    const rootId = payload && payload.id != null ? ` id="aggrid-table-${this.escapeHtml(String(payload.id))}"` : '';
    const theme = this._aggridThemeIsDark ? 'dark' : 'light';
    const themeClass = this._aggridThemeIsDark ? 'ag-theme-alpine-dark' : 'ag-theme-alpine';
    return `
      <div class="aggrid-table-shell flex-1 flex flex-col min-h-0" data-role="aggrid-table"${idAttr} data-theme="${theme}">
        <div class="flex-1 min-h-0 ${themeClass}" data-role="aggrid-table-root"${rootId}>
          <div class="h-full w-full flex items-center justify-center text-sm text-slate-500 dark:text-slate-300 px-6 text-center">
            Loading AG Grid table...
          </div>
        </div>
      </div>
    `;
  },







  _render_aggrid_table(container, payload) {
    if (!payload) return;
    const root = container.querySelector('[data-role="aggrid-table-root"]');
    const tableId = this._tableKey(payload.id);
    if (!root || !tableId) return;

    if (!window.agGrid || typeof window.agGrid.Grid !== 'function') {
      ensureAgGridCommunity()
        .then(() => this._render_aggrid_table(container, payload))
        .catch((err) => console.error('[AGGrid] unable to load ag-grid-community', err));
      return;
    }

    if (root.clientWidth === 0 || root.clientHeight === 0) {
      if (!this._aggridResizeTimers) this._aggridResizeTimers = {};
      if (this._aggridResizeTimers[tableId]) clearTimeout(this._aggridResizeTimers[tableId]);
      this._aggridResizeTimers[tableId] = setTimeout(() => this._render_aggrid_table(container, payload), 60);
      return;
    }

    let entry = this._aggridTables && this._aggridTables[tableId];
    if (!entry || entry.root !== root || !entry.api) {
      this._destroy_aggrid_table(tableId);
      entry = this._create_aggrid_table(root);
      this._aggridTables[tableId] = entry;
    }

    const dataset = this._prepare_table_dataset(payload);
    entry.dataset = dataset;
    entry.payload = payload;
    entry.pathKey = dataset.pathKey;

    const schema = Array.isArray(dataset.schema) ? dataset.schema : [];
    const originalColumns = Array.isArray(payload.columns) ? payload.columns : [];
    const columnDefs = schema.map((col, idx) => {
      const isPathColumn = idx === 0;
      const sourceLabel = (
        isPathColumn
          ? (col.title || col.name || 'Path')
          : ((originalColumns[idx - 1] && originalColumns[idx - 1].label) || col.title || col.name || '')
      ).toString();
      const headerLines = sourceLabel
        .split(/<br\s*\/?>/i)
        .map((segment) => this._strip_html(segment))
        .map((line) => line.replace(/\s+/g, ' ').trim())
        .filter((line) => line !== '');
      const resolvedHeader = headerLines.length ? headerLines.join('\n') : this._strip_html(sourceLabel);
      const headerAlignment = idx === 0 ? 'left' : 'right';
      const baseDef = {
        field: col.name,
        headerName: resolvedHeader,
        headerTooltip: headerLines.join(' · ') || resolvedHeader,
        sortable: false,
        filter: false,
        resizable: false,
        suppressMenu: true,
        suppressMovable: true,
        minWidth: isPathColumn ? AGGRID_PATH_COL_MIN_WIDTH : 120,
        maxWidth: isPathColumn ? AGGRID_PATH_COL_MAX_WIDTH : undefined,
        cellClass: [
          col.align === 'right' ? 'ag-right-aligned-cell' : 'ag-left-aligned-cell',
          'aggrid-body-cell'
        ].join(' '),
        headerClass: [
          headerAlignment === 'right' ? 'ag-right-aligned-header' : 'ag-left-aligned-header',
          'aggrid-header-cell'
        ].join(' ')
      };
      baseDef.headerComponentParams = { lines: headerLines, align: headerAlignment };
      if (!isPathColumn) {
        baseDef.flex = 1;
      }
      if (isPathColumn) {
        baseDef.width = AGGRID_PATH_COL_MIN_WIDTH;
        baseDef.suppressSizeToFit = true;
        baseDef.resizable = true;
      }
      if (col.name === dataset.pathKey) {
        baseDef.cellRenderer = (params) => {
          if (params && params.data && params.data.__placeholder) {
            const empty = document.createElement('div');
            empty.className = 'aggrid-path-cell';
            empty.innerHTML = '&nbsp;';
            return empty;
          }
          const value = (params && params.value != null) ? params.value : '';
          const pathHtml = params && params.data ? params.data[TABLE_PATH_HTML_FIELD] : '';
          const wrapper = document.createElement('div');
          wrapper.className = 'aggrid-path-cell';
          if (pathHtml && typeof pathHtml === 'string') {
            const safeHtml =
              typeof sanitizeRichHtml === 'function' ? sanitizeRichHtml(pathHtml) : '';
            if (safeHtml && safeHtml.trim() !== '') {
              wrapper.innerHTML = safeHtml;
            } else {
              wrapper.textContent = value == null ? '' : String(value);
            }
          } else {
            wrapper.textContent = value == null ? '' : String(value);
          }
          return wrapper;
        };
        baseDef.cellClass += ' aggrid-path-cell-wrapper';
      }
      if (col.type === 'number') {
        baseDef.valueFormatter = (params) => {
          if (params && params.data && params.data.__placeholder) return '';
          const value = params && params.value;
          if (value === undefined || value === null || value === '') return '';
          const numeric = Number(value);
          if (!Number.isFinite(numeric)) return String(value);
          return numeric.toLocaleString(undefined, { maximumFractionDigits: 2 });
        };
        baseDef.type = 'numericColumn';
        baseDef.cellClass += ' aggrid-numeric-cell';
      }
      if (idx === 0) {
        baseDef.pinned = 'left';
        baseDef.lockPinned = true;
        baseDef.suppressMovable = true;
        baseDef.cellClass += ' aggrid-path-pinned';
      }
      return baseDef;
    });

    const filledRows = Array.isArray(dataset.rows) ? dataset.rows.map((row) => Object.assign({}, row)) : [];
    const rowHeight = entry.gridOptions && entry.gridOptions.rowHeight ? entry.gridOptions.rowHeight : 28;
    const headerHeight = entry.gridOptions && entry.gridOptions.headerHeight ? entry.gridOptions.headerHeight : 48;
    const containerHeight = container && container.clientHeight ? container.clientHeight : root.clientHeight;
    const bodyEl = container.closest('.grid-widget-body');
    const widgetEl = container.closest('.grid-stack-item');
    const bodyHeight = bodyEl ? bodyEl.clientHeight : containerHeight;
    const gridUnits = widgetEl ? parseInt(widgetEl.getAttribute('gs-h') || '0', 10) : 0;
    const estimatedWidgetHeight = gridUnits > 0 && this && this._cellHeight ? gridUnits * this._cellHeight : bodyHeight;
    const measuredHeight = Math.max(containerHeight || 0, bodyHeight || 0);
    const desiredHeight = measuredHeight > 0 ? measuredHeight : (estimatedWidgetHeight || 0);
    const availableHeight = Math.max(desiredHeight - headerHeight, 0);
    const estimatedRowsFromHeight = rowHeight > 0 ? Math.ceil(availableHeight / rowHeight) : 0;
    const minRows = Math.max(estimatedRowsFromHeight, 10);
    let fillerCount = 0;
    if (minRows > filledRows.length) {
      fillerCount = minRows - filledRows.length;
      for (let i = 0; i < fillerCount; i += 1) {
        const filler = { __placeholder: true };
        filler[dataset.pathKey] = '';
        filler[TABLE_PATH_HTML_FIELD] = '';
        schema.forEach((col) => {
          if (col && col.name) filler[col.name] = '';
        });
        filledRows.push(filler);
      }
    }

    const tableShell = container && container.querySelector('.aggrid-table-shell');
    if (tableShell) {
      if (fillerCount > 0) {
        tableShell.setAttribute('data-fillers', '1');
      } else {
        tableShell.removeAttribute('data-fillers');
      }
    }

    try {
      entry.gridOptions.api.setColumnDefs(columnDefs);
      entry.gridOptions.api.setRowData(filledRows);
      entry.gridOptions.api.refreshCells({ force: true });
      setTimeout(() => {
        this._auto_size_aggrid_path_column(entry, dataset.pathKey);
        try { entry.gridOptions.api.sizeColumnsToFit(); } catch (_) {}
        this._activate_tooltips_for_element(root);
      }, 0);
    } catch (err) {
      console.error('[AGGrid] failed to render grid', err);
    }
    this._apply_aggrid_theme_to_entry(entry);
  },

  _auto_size_aggrid_path_column(entry, pathKey) {
    if (!entry || !entry.columnApi || !pathKey) return;
    const column = entry.columnApi.getColumn(pathKey);
    if (!column) return;
    try {
      entry.columnApi.autoSizeColumns([pathKey], false);
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
      try { entry.columnApi.setColumnWidth(column, clamped); } catch (_) {}
    }
  },

  _create_aggrid_table(root) {
    root.innerHTML = '';
    root.style.width = '100%';
    root.style.height = '100%';
    root.style.width = '100%';
    root.style.height = '100%';
    const agGrid = window.agGrid;
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
      getRowClass: (params) => (params && params.data && params.data.__placeholder ? 'aggrid-placeholder-row' : ''),
      defaultColDef: {
        sortable: false,
        filter: false,
        resizable: false,
        flex: 1,
        headerComponent: getAggridHeaderComponentClass()
      }
    };
    new agGrid.Grid(root, gridOptions);
    const entry = {
      gridOptions,
      api: gridOptions.api,
      columnApi: gridOptions.columnApi,
      root,
      shell: root.closest('[data-role="aggrid-table"]') || null
    };
    if (typeof ResizeObserver !== 'undefined') {
      entry.resizeObserver = new ResizeObserver(() => {
        const dataset = entry.dataset;
        const payload = entry.payload;
        const container = entry.shell;
        if (dataset && payload && container) {
          if (entry._resizeRendering) return;
          entry._resizeRendering = true;
          try {
            this._render_aggrid_table(container, payload);
          } catch (err) {
            console.error('[AGGrid] resize render error', err);
          } finally {
            entry._resizeRendering = false;
          }
        } else if (entry.api && typeof entry.api.sizeColumnsToFit === 'function') {
          try { entry.api.sizeColumnsToFit(); } catch (_) {}
        }
      });
      try { entry.resizeObserver.observe(root); } catch (_) {}
    }
    this._apply_aggrid_theme_to_entry(entry);
    return entry;
  },

  _destroy_aggrid_table(id) {
    if (!this._aggridTables || !id || !this._aggridTables[id]) return;
    const entry = this._aggridTables[id];
    if (entry && entry.resizeObserver) {
      try { entry.resizeObserver.disconnect(); } catch (_) {}
      entry.resizeObserver = null;
    }
    if (entry && entry.api && typeof entry.api.destroy === 'function') {
      try { entry.api.destroy(); } catch (_) {}
    }
    delete this._aggridTables[id];
    if (this._aggridResizeTimers && this._aggridResizeTimers[id]) {
      clearTimeout(this._aggridResizeTimers[id]);
      delete this._aggridResizeTimers[id];
    }
  },

  _prepare_table_dataset(payload) {
    const columns = Array.isArray(payload.columns) ? payload.columns : [];
    const headerLabels = ['Path'].concat(
      columns.map((col) => this._strip_html(col && col.label ? col.label : ''))
    );
    const normalizedHeaders = this._ensure_unique_labels(headerLabels);

    const rows = Array.isArray(payload.rows)
      ? payload.rows.map((row) => {
          const obj = {};
          normalizedHeaders.forEach((header, idx) => {
            if (idx === 0) {
              obj[header] = row.display_path || row.path || '';
              obj[TABLE_PATH_HTML_FIELD] = row.path_html || (row.display_path || row.path || '');
            } else {
              const values = Array.isArray(row.values) ? row.values : [];
              const value = values[idx - 1];
              obj[header] = value == null || value === '' ? 0 : value;
            }
          });
          return obj;
        })
      : [];
    const schema = normalizedHeaders.map((label, idx) => ({
      name: label,
      title: label,
      width: idx === 0 ? 240 : 120,
      align: idx === 0 ? 'left' : 'right',
      type: idx === 0 ? 'string' : 'number'
    }));

    const meta = Array.isArray(payload.rows)
      ? payload.rows.map((row) => ({
          row,
          segments: this._build_path_segments(row, payload)
        }))
      : [];

    return {
      rows,
      schema,
      meta,
      pathKey: normalizedHeaders[0] || 'Path'
    };
  },

  _build_path_segments(row, payload) {
    const rawPath = (row && (row.display_path || row.path)) ? String(row.display_path || row.path) : '';
    if (!rawPath) return null;
    const parts = rawPath.split('.');
    const allPaths = (Array.isArray(payload.color_paths) && payload.color_paths.length
      ? payload.color_paths
      : (payload.rows || []).map((r) => r.display_path || r.path || '')
    ).map((p) => String(p || ''));
    const palette = Array.isArray(payload.color_palette) && payload.color_palette.length
      ? payload.color_palette
      : (this.colors || ['#14b8a6']);
    const segments = [];
    const prefix = [];
    parts.forEach((component) => {
      const idx = this._path_color_index(component, prefix, allPaths);
      const color = this._color_from_palette(idx, palette);
      segments.push({ text: component, color });
      prefix.push(component);
    });
    return segments;
  },

  _path_color_index(component, prefixParts, allPaths) {
    const prefix = prefixParts.length ? `${prefixParts.join('.')}.` : '';
    const siblingSet = new Set();
    allPaths.forEach((path) => {
      if (!path || typeof path !== 'string') return;
      if (!prefix && path.indexOf('.') === -1 && prefixParts.length === 0) {
        siblingSet.add(path);
        return;
      }
      if (!path.startsWith(prefix)) return;
      const remainder = path.slice(prefix.length);
      if (!remainder) return;
      const next = remainder.split('.')[0];
      if (next) siblingSet.add(next);
    });
    const siblings = Array.from(siblingSet).sort();
    const idx = siblings.indexOf(component);
    return idx >= 0 ? idx : 0;
  },

  _color_from_palette(index, palette) {
    if (!Array.isArray(palette) || palette.length === 0) return '#14b8a6';
    const safeIndex = index % palette.length;
    return palette[safeIndex] || palette[0];
  },

  _strip_html(value) {
    if (!value || typeof value !== 'string') return '';
    const div = document.createElement('div');
    div.innerHTML = value;
    return div.textContent || div.innerText || '';
  },

  _ensure_unique_labels(labels) {
    const seen = {};
    return labels.map((label, idx) => {
      const base = label && label.trim() !== '' ? label : `Column ${idx + 1}`;
      const count = seen[base] || 0;
      seen[base] = count + 1;
      return count === 0 ? base : `${base} (${count + 1})`;
    });
  },

  _tableKey(id) {
    if (id === undefined || id === null) return null;
    return String(id);
  },

  _resizeAgGridTables() {
    if (!this._aggridTables) return;
    Object.values(this._aggridTables).forEach((entry) => {
      if (entry && entry.api && typeof entry.api.sizeColumnsToFit === 'function') {
        try { entry.api.sizeColumnsToFit(); } catch (_) {}
      }
    });
  },

  _apply_aggrid_theme(isDark) {
    this._aggridThemeIsDark = !!isDark;
    if (!this._aggridTables) return;
    Object.values(this._aggridTables).forEach((entry) => this._apply_aggrid_theme_to_entry(entry));
  },

  _apply_aggrid_theme_to_entry(entry) {
    if (!entry || !entry.root) return;
    const theme = this._aggridThemeIsDark ? 'dark' : 'light';
    if (entry.shell) {
      entry.shell.dataset.theme = theme;
    }
    if (entry.root.classList) {
      entry.root.classList.remove('ag-theme-alpine', 'ag-theme-alpine-dark');
      entry.root.classList.add(this._aggridThemeIsDark ? 'ag-theme-alpine-dark' : 'ag-theme-alpine');
    }
    setTimeout(() => {
      if (entry.api && typeof entry.api.redrawRows === 'function') {
        try { entry.api.redrawRows(); } catch (_) {}
      }
    }, 0);
  },

});

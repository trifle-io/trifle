export const TABLE_PATH_HTML_FIELD = '__table_path_html__';
export const AGGRID_PATH_COL_MIN_WIDTH = 160;
export const AGGRID_PATH_COL_MAX_WIDTH = 640;
const AGGRID_SCRIPT_SRC = 'https://cdn.jsdelivr.net/npm/ag-grid-community@31.0.3/dist/ag-grid-community.min.js';
const AGGRID_BASE_STYLE_SRC = 'https://cdn.jsdelivr.net/npm/ag-grid-community@31.0.3/styles/ag-grid.css';
const AGGRID_THEME_LIGHT_STYLE_SRC = 'https://cdn.jsdelivr.net/npm/ag-grid-community@31.0.3/styles/ag-theme-alpine.css';
const AGGRID_THEME_DARK_STYLE_SRC = 'https://cdn.jsdelivr.net/npm/ag-grid-community@31.0.3/styles/ag-theme-alpine-dark.css';
let aggridLoaderPromise = null;
let aggridHeaderComponentClass = null;

const ensureStylesheet = (id, href) => {
  if (typeof document === 'undefined') return;
  if (document.getElementById(id)) return;
  const existing = Array.from(document.querySelectorAll(`link[data-trifle-css="${id}"]`));
  if (existing.length) return;
  const link = document.createElement('link');
  link.rel = 'stylesheet';
  link.href = href;
  link.id = id;
  link.dataset.trifleCss = id;
  document.head.appendChild(link);
};

export const ensureAgGridCommunity = () => {
  if (typeof window !== 'undefined' && window.agGrid && typeof window.agGrid.Grid === 'function') {
    return Promise.resolve(window.agGrid);
  }
  if (typeof document === 'undefined') {
    return Promise.reject(new Error('Document not available'));
  }
  if (!aggridLoaderPromise) {
    aggridLoaderPromise = new Promise((resolve, reject) => {
      let script = null;
      let settled = false;
      let timeout = null;
      const cleanup = () => {
        if (timeout) clearTimeout(timeout);
        if (!script) return;
        script.onload = null;
        script.onerror = null;
        try { script.remove(); } catch (_) {}
      };
      const fail = (err) => {
        if (settled) return;
        settled = true;
        cleanup();
        aggridLoaderPromise = null;
        reject(err);
      };
      const succeed = () => {
        if (settled) return;
        if (!window.agGrid || typeof window.agGrid.Grid !== 'function') {
          fail(new Error('AG Grid script loaded without expected API'));
          return;
        }
        settled = true;
        cleanup();
        resolve(window.agGrid);
      };
      try {
        ensureStylesheet('ag-grid-base-css', AGGRID_BASE_STYLE_SRC);
        ensureStylesheet('ag-grid-alpine-css', AGGRID_THEME_LIGHT_STYLE_SRC);
        ensureStylesheet('ag-grid-alpine-dark-css', AGGRID_THEME_DARK_STYLE_SRC);
        script = document.createElement('script');
        timeout = setTimeout(() => {
          fail(new Error('Timed out loading ag-grid-community script'));
        }, 15000);
        script.src = AGGRID_SCRIPT_SRC;
        script.async = true;
        script.onload = succeed;
        script.onerror = (err) => {
          console.error('[AGGrid] failed to load ag-grid-community script', err);
          fail(err instanceof Error ? err : new Error('Failed to load ag-grid-community script'));
        };
        document.head.appendChild(script);
      } catch (err) {
        fail(err instanceof Error ? err : new Error('Failed to initialize ag-grid-community loader'));
      }
    });
  }
  return aggridLoaderPromise;
};

export const getAggridHeaderComponentClass = () => {
  if (aggridHeaderComponentClass) return aggridHeaderComponentClass;
  class TrifleAgGridHeader {
    init(params) {
      this.eGui = document.createElement('div');
      this.eGui.className = 'aggrid-header-cell-wrapper';
      if (params && params.align === 'left') {
        this.eGui.classList.add('aggrid-header-align-left');
      } else {
        this.eGui.classList.add('aggrid-header-align-right');
      }
      const colDef = params?.column?.getColDef ? params.column.getColDef() : null;
      const lines = colDef?.headerComponentParams?.lines || [];
      const displayName = params && typeof params.displayName === 'string' ? params.displayName : '';
      const segments = Array.isArray(lines) && lines.length ? lines : [displayName];
      segments.forEach((segment, idx) => {
        const span = document.createElement('span');
        span.className = 'aggrid-header-line';
        span.textContent = segment;
        this.eGui.appendChild(span);
      });
    }

    getGui() {
      return this.eGui;
    }

    destroy() {}
  }
  aggridHeaderComponentClass = TrifleAgGridHeader;
  return aggridHeaderComponentClass;
};

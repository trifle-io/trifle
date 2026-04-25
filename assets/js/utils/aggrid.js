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
  if (typeof window !== 'undefined' && window.agGrid && window.agGrid.Grid) {
    return Promise.resolve(window.agGrid);
  }
  if (!aggridLoaderPromise) {
    aggridLoaderPromise = new Promise((resolve, reject) => {
      if (typeof document === 'undefined') {
        reject(new Error('Document not available'));
        return;
      }
      ensureStylesheet('ag-grid-base-css', AGGRID_BASE_STYLE_SRC);
      ensureStylesheet('ag-grid-alpine-css', AGGRID_THEME_LIGHT_STYLE_SRC);
      ensureStylesheet('ag-grid-alpine-dark-css', AGGRID_THEME_DARK_STYLE_SRC);
      const script = document.createElement('script');
      script.src = AGGRID_SCRIPT_SRC;
      script.async = true;
      script.onload = () => resolve(window.agGrid);
      script.onerror = (err) => {
        console.error('[AGGrid] failed to load ag-grid-community script', err);
        aggridLoaderPromise = null;
        reject(err);
      };
      document.head.appendChild(script);
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
      const lines =
        (params &&
          params.column &&
          params.column.getColDef &&
          params.column.getColDef() &&
          params.column.getColDef().headerComponentParams &&
          params.column.getColDef().headerComponentParams.lines) ||
        [];
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

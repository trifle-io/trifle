const COOKIE = 'trifle_trace_overview_rows';
const DEFAULT_ROWS = 3;
const MAX_ROWS = 100;

const rowCount = value => {
  const number = Number(value);
  return Number.isInteger(number) && number >= 1 && number <= MAX_ROWS ? number : DEFAULT_ROWS;
};

export const readTraceOverviewRows = cookie => {
  try {
    const entry = (cookie ?? globalThis.document?.cookie ?? '').split(';')
      .map(part => part.trim()).find(part => part.startsWith(`${COOKIE}=`));
    return rowCount(entry?.slice(COOKIE.length + 1));
  } catch (_) {
    return DEFAULT_ROWS;
  }
};

export const writeTraceOverviewRows = (rows, target = globalThis.document) => {
  try {
    target.cookie = `${COOKIE}=${rowCount(rows)}; Max-Age=31536000; Path=/; SameSite=Lax`;
  } catch (_) {}
};

export const createTraceOverviewPreferencesHook = ({
  document: target = globalThis.document,
  ResizeObserver: Observer = globalThis.ResizeObserver,
  getComputedStyle: style = globalThis.getComputedStyle
} = {}) => ({
  mounted() {
    this.lastColumns = Number(this.el.dataset.overviewColumns);
    this.handleEvent('trace_overview_rows', ({rows}) => writeTraceOverviewRows(rows, target));
    if (Observer) {
      this.resizeObserver = new Observer(() => this.syncColumns());
      this.resizeObserver.observe(this.el);
    }
    this.syncColumns();
  },

  updated() {
    this.syncColumns();
  },

  destroyed() {
    this.resizeObserver?.disconnect();
  },

  syncColumns() {
    const grid = this.el.querySelector('#traces-overview-grid');
    if (!grid || !grid.clientWidth) return;
    const columns = style(grid).gridTemplateColumns.trim().split(/\s+/).length;
    if (![1, 2, 3, 4, 6].includes(columns) || columns === this.lastColumns) return;
    this.lastColumns = columns;
    this.pushEvent('overview_columns', {columns});
  }
});

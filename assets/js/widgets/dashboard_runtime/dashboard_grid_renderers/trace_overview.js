import { registerCompactChartHook } from '../shared/compact_charts.mjs';

export const createTraceOverviewRendererMethods = ({echarts, withChartOpts}) => {
  const hooks = {};
  registerCompactChartHook(hooks, {echarts, withChartOpts});

  return {
    _disposeTraceOverview(id) {
      const entries = this._traceOverviewCharts?.[id] || [];
      entries.forEach(entry => entry.destroyed());
      if (this._traceOverviewCharts) delete this._traceOverviewCharts[id];
    },

    _render_trace_overview(items) {
      this._traceOverviewCharts ||= {};
      for (const payload of items) {
        const item = this.el.querySelector(`.grid-stack-item[gs-id="${payload.id}"]`);
        const content = item?.querySelector('.grid-stack-item-content');
        if (!content || !payload.html) continue;
        content.className = 'grid-stack-item-content job-overview-row group/widget-panel';
        const template = document.createElement('template');
        template.innerHTML = payload.html;
        const next = template.content.querySelector('[data-trace-overview-widget]');
        if (!next) continue;
        const current = content.querySelector('[data-trace-overview-widget]');
        const nextCharts = Array.from(next.querySelectorAll('[data-compact-chart]'));
        const currentCharts = Array.from(current?.querySelectorAll('[data-compact-chart]') || []);
        const sameCharts = current && currentCharts.map(el => el.id).join('|') === nextCharts.map(el => el.id).join('|');
        const entries = this._traceOverviewCharts[payload.id];
        const stale = entries?.some(entry => !content.contains(entry.el));

        if (!sameCharts || stale) {
          this._disposeTraceOverview(payload.id);
          content.innerHTML = payload.html;
        } else {
          const title = current.querySelector('[data-trace-path]');
          const nextTitle = next.querySelector('[data-trace-path]');
          if (title && nextTitle) {
            title.innerHTML = nextTitle.innerHTML;
            title.setAttribute('href', nextTitle.getAttribute('href'));
          }
          const counter = current.querySelector('.job-overview-counter');
          const nextCounter = next.querySelector('.job-overview-counter');
          if (counter && nextCounter) {
            counter.innerHTML = nextCounter.innerHTML;
            counter.title = nextCounter.title;
          }
          currentCharts.forEach((chart, index) => {
            const nextChart = nextCharts[index];
            chart.dataset.chart = nextChart.dataset.chart;
            chart.setAttribute('aria-label', nextChart.getAttribute('aria-label'));
            if (nextChart.dataset.tooltip) chart.dataset.tooltip = nextChart.dataset.tooltip;
          });
        }

        if (!this._traceOverviewCharts[payload.id]) {
          this._traceOverviewCharts[payload.id] = Array.from(content.querySelectorAll('[data-compact-chart]')).map(el => {
            const controller = {...hooks.CompactChart, el};
            controller.mounted();
            return controller;
          });
        } else {
          this._traceOverviewCharts[payload.id].forEach(controller => controller.updated());
        }
        this._scheduleCompactLayout();
      }
    },

    _scheduleCompactLayout() {
      if (this.el.dataset.compact !== 'true' || !this.grid) return;
      if (!this._compactGridObserver && typeof ResizeObserver === 'function') {
        this._compactGridObserver = new ResizeObserver(() => this._scheduleCompactLayout());
        this._compactGridObserver.observe(this.el);
      }
      if (this._compactLayoutRaf) return;
      this._compactLayoutRaf = requestAnimationFrame(() => {
        this._compactLayoutRaf = null;
        if (!this.grid || !this.el.isConnected) return;
        const columns = this.el.clientWidth >= 1152 ? 3 : this.el.clientWidth >= 736 ? 2 : 1;
        const width = 12 / columns;
        const items = this._gridItems(this.grid);
        this.grid.batchUpdate();
        items.forEach((item, index) => this.grid.update(item, {w: width, x: (index % columns) * width}));
        const heights = items.map(item => {
          const content = item.querySelector('.grid-stack-item-content');
          const body = content?.querySelector('[data-trace-overview-widget]');
          if (!body) return 10;
          const style = getComputedStyle(content);
          const height = body.getBoundingClientRect().height + parseFloat(style.paddingTop) + parseFloat(style.paddingBottom) + 10;
          return Math.max(1, Math.ceil(height / this._cellHeight));
        });
        let y = 0;
        for (let index = 0; index < items.length; index += columns) {
          const height = Math.max(...heights.slice(index, index + columns));
          items.slice(index, index + columns).forEach((item, offset) => {
            this.grid.update(item, {x: offset * width, y, w: width, h: height});
          });
          y += height;
        }
        this.grid.batchUpdate(false);
      });
    }
  };
};

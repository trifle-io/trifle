export const createDashboardGridCategoryRendererMethods = ({ formatCompactNumber }) => ({
  _render_category(items) {
    if (!Array.isArray(items)) return;
    const isDarkMode = document.documentElement.classList.contains('dark');
    const colors = this.colors || [];
    items.forEach((it) => {
      const item = this.el.querySelector(`.grid-stack-item[gs-id="${it.id}"]`);
      const body = item && item.querySelector('.grid-widget-body');
      if (!body) return;
      let container = body.querySelector('.cat-chart');
      if (!container) {
        body.innerHTML = '';
        body.classList.remove('items-center','justify-center','text-sm','text-gray-500','dark:text-slate-400');
        container = document.createElement('div');
        container.className = 'cat-chart';
        container.style.width = '100%';
        container.style.height = '100%';
        body.appendChild(container);
      }
      let chart = this._catCharts[it.id];
      const initTheme = isDarkMode ? 'dark' : undefined;
      const ensureInit = () => {
        if (!chart) {
          if (container.clientWidth === 0 || container.clientHeight === 0) { setTimeout(ensureInit, 80); return; }
          chart = echarts.init(container, initTheme, withChartOpts());
          this._catCharts[it.id] = chart;
        }
        const data = it.data || [];
        const type = (it.chart_type || 'bar');
        let option;
        if (type === 'pie' || type === 'donut') {
          const labelColor = isDarkMode ? '#E5E7EB' : '#374151';
          const labelLineColor = isDarkMode ? '#475569' : '#9CA3AF';
          option = {
            backgroundColor: 'transparent',
            tooltip: {
              trigger: 'item',
              textStyle: { color: isDarkMode ? '#F3F4F6' : '#1F2937' },
              backgroundColor: isDarkMode ? '#1F2937' : '#FFFFFF',
              borderColor: isDarkMode ? '#4B5563' : '#E5E7EB',
              appendToBody: true
            },
            color: (colors && colors.length ? colors : undefined),
            series: [{
              type: 'pie',
              radius: (type === 'donut') ? ['50%', '70%'] : '70%',
              avoidLabelOverlap: true,
              data,
              label: { color: labelColor },
              labelLine: { lineStyle: { color: labelLineColor } },
              itemStyle: {
                color: (params) => {
                  const explicit = data?.[params.dataIndex]?.color;
                  if (typeof explicit === 'string' && explicit.trim() !== '') return explicit.trim();
                  return (colors && colors.length)
                    ? colors[params.dataIndex % colors.length]
                    : params.color;
                }
              }
            }]
          };
        } else {
          option = {
            backgroundColor: 'transparent',
            grid: { top: 12, bottom: 28, left: 48, right: 16 },
            xAxis: { type: 'category', data: data.map((d) => d.name) },
            yAxis: {
              type: 'value',
              min: 0,
              axisLabel: {
                formatter: (v) => formatCompactNumber(v)
              }
            },
            tooltip: { trigger: 'axis', appendToBody: true },
            series: [{
              type: 'bar',
              data: data.map((d, idx) => {
                const explicit = typeof d?.color === 'string' && d.color.trim() !== '' ? d.color.trim() : null;
                const paletteColor = colors[idx % (colors.length || 1)] || '#14b8a6';
                const numeric = Number(d?.value);
                return {
                  value: Number.isFinite(numeric) ? numeric : 0,
                  itemStyle: { color: explicit || paletteColor }
                };
              })
            }]
          };
        }
        chart.setOption(option, true);
        try {
          chart.off('finished');
          chart.on('finished', () => {
            try { container.dataset.echartsReady = '1'; this._scheduleReadyMark(); } catch (_) {}
          });
        } catch (_) {}
        chart.resize();
      };
      setTimeout(ensureInit, 0);
    });
    this._seen.category = true;
    this._scheduleReadyMark();
    this._lastCategory = this._deepClone(items);
  },

});

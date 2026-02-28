export const createDashboardGridDistributionRendererMethods = ({
  echarts,
  withChartOpts,
  buildBucketIndexMap,
  buildDistributionHeatmapAggregation,
  buildDistributionScatterSeries,
  resolveHeatmapVisualMap,
  buildHeatmapOptions,
  formatCompactNumber
}) => ({
  _render_distribution(items) {
    if (!Array.isArray(items)) return;
    const isDarkMode = document.documentElement.classList.contains('dark');
    const colors = this.colors || [];
    const chartFontFamily =
      'Inter var, Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif';
    this._distCharts = this._distCharts || {};

    items.forEach((it) => {
      const widgetId = String(it && it.id != null ? it.id : '');
      const item = this.el.querySelector(`.grid-stack-item[gs-id="${it.id}"]`);
      const body = item && item.querySelector('.grid-widget-body');
      if (!body) return;

      const errors = Array.isArray(it.errors) ? it.errors.filter(Boolean) : [];
      if (errors.length) {
        this._disposeChartEntry(this._distCharts, widgetId);
        body.innerHTML = `
          <div class="flex items-center justify-center text-sm text-red-600 dark:text-red-300 text-center px-3">
            ${this.escapeHtml(errors.join(', '))}
          </div>`;
        return;
      }

      const labels = Array.isArray(it.bucket_labels) ? it.bucket_labels : [];
      const verticalLabels = Array.isArray(it.vertical_bucket_labels) ? it.vertical_bucket_labels : [];
      const widgetType = (it.widget_type || '').toLowerCase();
      const isHeatmap = widgetType === 'heatmap' || (it.chart_type || '').toLowerCase() === 'heatmap';
      const is3d = isHeatmap || (it.mode || '').toLowerCase() === '3d';
      if (is3d) {
        if (!labels.length || !verticalLabels.length) {
          this._disposeChartEntry(this._distCharts, widgetId);
          const emptyMessage = isHeatmap
            ? 'No heatmap buckets available. Add both horizontal and vertical bucket definitions in the editor.'
            : 'No 3D buckets available. Add both horizontal and vertical bucket definitions in the editor.';

          body.innerHTML = `
            <div class="flex items-center justify-center text-sm text-gray-500 dark:text-slate-400 text-center px-3">
              ${emptyMessage}
            </div>`;
          return;
        }
      } else {
        if (!labels.length) {
          this._disposeChartEntry(this._distCharts, widgetId);
          body.innerHTML = `
            <div class="flex items-center justify-center text-sm text-gray-500 dark:text-slate-400 text-center px-3">
              No distribution buckets available. Add bucket definitions in the editor.
            </div>`;
          return;
        }
      }

      let container = body.querySelector('.distribution-chart');
      if (!container) {
        body.innerHTML = '';
        body.classList.remove('items-center', 'justify-center', 'text-sm', 'text-gray-500', 'dark:text-slate-400');
        container = document.createElement('div');
        container.className = 'distribution-chart';
        container.style.width = '100%';
        container.style.height = '100%';
        container.dataset.echartsReady = '0';
        body.appendChild(container);
      }

      let chart = this._distCharts[it.id];
      const initTheme = isDarkMode ? 'dark' : undefined;
      const ensureInit = () => {
        if (!chart || chart.isDisposed?.()) {
          const existing = echarts.getInstanceByDom(container);
          if (existing) {
            chart = existing;
          } else {
            if (container.clientWidth === 0 || container.clientHeight === 0) { setTimeout(ensureInit, 80); return; }
            chart = echarts.init(container, initTheme, withChartOpts());
          }
          this._distCharts[it.id] = chart;
        }

        const legendNames = [];
        const hasLegendData = Array.isArray(it.series) && it.series.length > 1;
        const showLegend = it.legend === undefined ? hasLegendData : !!it.legend;
        const bottomPadding = showLegend ? 56 : 20;

        let seriesData;
        if (is3d) {
          if (isHeatmap) {
            const seriesList = Array.isArray(it.series) ? it.series : [];
            const labelIndexMap = buildBucketIndexMap(labels);
            const verticalLabelIndexMap = buildBucketIndexMap(verticalLabels);
            const { heatmapData, breakdownByCell } = buildDistributionHeatmapAggregation({
              seriesList,
              labelIndexMap,
              verticalLabelIndexMap
            });

            const showScale = it.legend === undefined ? true : !!it.legend;
            const gridBottom = showScale ? 72 : 20;
            const visualMapBottom = 8;
            const fallbackHeatColor = colors[0] || '#14b8a6';
            const visualSettings = resolveHeatmapVisualMap({
              payload: it,
              heatmapData,
              series: seriesList,
              fallbackHeatColor,
              isDarkMode
            });

            const option = buildHeatmapOptions({
              labels,
              verticalLabels,
              breakdownByCell,
              isDarkMode,
              gridBottom,
              visualMapBottom,
              visualSettings,
              showScale,
              heatmapData,
              chartFontFamily,
              escapeHtml: this.escapeHtml.bind(this)
            });

            chart.setOption(option, true);
            try {
              chart.off('finished');
              chart.on('finished', () => {
                try { container.dataset.echartsReady = '1'; this._scheduleReadyMark(); } catch (_) {}
              });
            } catch (_) {}
            chart.resize();
            return;
          }

          const seriesList = Array.isArray(it.series) ? it.series : [];
          const labelIndexMap = buildBucketIndexMap(labels);
          const verticalLabelIndexMap = buildBucketIndexMap(verticalLabels);
          const scatterData = buildDistributionScatterSeries({
            seriesList,
            labelIndexMap,
            verticalLabelIndexMap,
            resolveColor: (series, idx) => {
              const explicitColor =
                typeof series?.color === 'string' && series.color.trim() !== ''
                  ? series.color.trim()
                  : null;
              return explicitColor || colors[idx % (colors.length || 1)] || colors[0] || '#14b8a6';
            }
          });
          legendNames.push(...scatterData.legendNames);
          seriesData = scatterData.seriesData;

          if (!seriesData.length) {
            const fallbackColor = colors[0] || '#14b8a6';
            seriesData = [{
              name: legendNames[0] || 'Series 1',
              type: 'scatter',
              data: [],
              symbolSize: () => 10,
              itemStyle: { color: fallbackColor, opacity: 1 },
              hoverAnimation: false,
              emphasis: {
                disabled: true,
                focus: 'none',
                scale: false,
                blurScope: 'none',
                itemStyle: { opacity: 1 }
              },
              select: { disabled: true }
            }];
          }

          const option = {
            backgroundColor: 'transparent',
            legend: showLegend
              ? {
                  data: legendNames,
                  textStyle: { color: isDarkMode ? '#E2E8F0' : '#0F172A', fontFamily: chartFontFamily },
                  bottom: 0,
                  type: legendNames.length > 4 ? 'scroll' : 'plain'
                }
              : { show: false },
            tooltip: {
              trigger: 'item',
              appendToBody: true,
              formatter: (params) => {
                const valueArr = Array.isArray(params.value) && params.value.length >= 3
                  ? params.value
                  : (Array.isArray(params.data) && params.data.length >= 3 ? params.data : null);

                if (!valueArr) return '';

                const xIdx = Number.isFinite(valueArr[0]) ? valueArr[0] : null;
                const yIdx = Number.isFinite(valueArr[1]) ? valueArr[1] : null;
                const val = Number.isFinite(valueArr[2]) ? valueArr[2] : 0;
                const xLabel = (xIdx != null && labels[xIdx]) ? labels[xIdx] : (labels[0] || '');
                const yLabel = (yIdx != null && verticalLabels[yIdx]) ? verticalLabels[yIdx] : (verticalLabels[0] || '');

                if (!xLabel && !yLabel) return '';

                const seriesName = params.seriesName || '';
                const marker = params.marker || '';
                const escapedXLabel = this.escapeHtml(xLabel);
                const escapedYLabel = this.escapeHtml(yLabel);
                const escapedSeriesName = this.escapeHtml(seriesName);
                const lines = [`${escapedXLabel} × ${escapedYLabel}`];

                if (escapedSeriesName || marker) {
                  lines.push(
                    `${marker}${escapedSeriesName}  <strong>${formatCompactNumber(val)}</strong>`
                  );
                }

                return lines.join('<br/>');
              }
            },
            axisPointer: {
              show: true,
              type: 'line',
              lineStyle: { type: 'dashed', color: isDarkMode ? '#94a3b8' : '#0f172a' },
              link: [{ xAxisIndex: 'all' }, { yAxisIndex: 'all' }]
            },
            grid: { top: 16, left: 64, right: 16, bottom: bottomPadding },
            xAxis: {
              type: 'category',
              data: labels,
              splitLine: { show: true, lineStyle: { type: 'dashed', color: isDarkMode ? '#1f2937' : '#e2e8f0', opacity: isDarkMode ? 0.4 : 0.9 } },
              axisLabel: { color: isDarkMode ? '#CBD5F5' : '#475569', interval: 0, rotate: labels.length > 8 ? 30 : 0 }
            },
            yAxis: {
              type: 'category',
              data: verticalLabels,
              splitLine: { show: true, lineStyle: { type: 'dashed', color: isDarkMode ? '#1f2937' : '#e2e8f0', opacity: isDarkMode ? 0.4 : 0.9 } },
              axisLabel: { color: isDarkMode ? '#CBD5F5' : '#475569' }
            },
            series: seriesData
          };

          chart.setOption(option, true);
          try {
            chart.off('finished');
            chart.on('finished', () => {
              try { container.dataset.echartsReady = '1'; this._scheduleReadyMark(); } catch (_) {}
            });
          } catch (_) {}
          chart.resize();
          return;
        }

        seriesData = (Array.isArray(it.series) ? it.series : []).map((series, idx) => {
          const name = series && series.name ? series.name : `Series ${idx + 1}`;
          legendNames.push(name);
          const values = Array.isArray(series && series.values) ? series.values : [];
          const explicitColor =
            typeof series?.color === 'string' && series.color.trim() !== '' ? series.color.trim() : null;
          const color = explicitColor || colors[idx % (colors.length || 1)] || colors[0] || '#14b8a6';
          const data = labels.map((label) => {
            const match = values.find((v) => v && v.bucket === label);
            return match && Number.isFinite(match.value) ? Number(match.value) : 0;
          });
          return {
            name,
            type: 'bar',
            emphasis: { focus: 'series' },
            itemStyle: { color },
            data
          };
        });

          const option = {
            backgroundColor: 'transparent',
            legend: showLegend
              ? {
                  data: legendNames,
                  textStyle: { color: isDarkMode ? '#E2E8F0' : '#0F172A', fontFamily: chartFontFamily },
                  bottom: 0,
                  type: legendNames.length > 4 ? 'scroll' : 'plain'
                }
              : { show: false },
            grid: { top: 16, left: 52, right: 16, bottom: bottomPadding },
            tooltip: {
              trigger: 'axis',
              axisPointer: {
                type: 'line',
                lineStyle: { color: isDarkMode ? '#CBD5F5' : '#94a3b8', width: 1.5, type: 'dashed' }
              },
              appendToBody: true,
              valueFormatter: (value) => formatCompactNumber(value)
            },
          xAxis: {
            type: 'category',
            data: labels,
            axisLabel: { color: isDarkMode ? '#CBD5F5' : '#475569', interval: 0, rotate: labels.length > 6 ? 30 : 0 }
          },
          yAxis: {
            type: 'value',
            min: 0,
            axisLabel: { formatter: (v) => formatCompactNumber(v), color: isDarkMode ? '#CBD5F5' : '#475569' },
            splitLine: { lineStyle: { color: isDarkMode ? '#1f2937' : '#e2e8f0', opacity: isDarkMode ? 0.35 : 1 } }
          },
          series: seriesData.length ? seriesData : [{
            name: 'Values',
            type: 'bar',
            itemStyle: { color: colors[0] || '#14b8a6' },
            data: labels.map(() => 0)
          }]
        };

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

    this._seen.distribution = true;
    this._scheduleReadyMark();
    this._lastDistribution = this._deepClone(items);
  },

});

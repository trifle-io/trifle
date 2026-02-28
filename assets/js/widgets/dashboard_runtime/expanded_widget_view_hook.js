export const registerExpandedWidgetViewHook = (Hooks, deps) => {
  const {
    echarts,
    withChartOpts,
    formatCompactNumber,
    sanitizeRichHtml,
    resolveHeatmapVisualMap,
    buildHeatmapOptions,
    detectOngoingSegment,
    buildBucketIndexMap,
    buildDistributionHeatmapAggregation,
    buildDistributionScatterSeries,
    parseJsonSafe
  } = deps;
Hooks.ExpandedWidgetView = {
  mounted() {
    this.chartTarget = this.el.querySelector('[data-role="chart"]');
    this.tableRoot = this.el.querySelector('[data-role="table-root"]');
    this.chart = null;
    this.chartElement = null;
    this.chartTheme = null;
    this.lastPayloadKey = null;
    this.retryTimer = null;
    this._sparklineTimer = null;
    this.colors = [];
    this.handleResize = () => {
      if (this.chart && typeof this.chart.resize === 'function') {
        try { this.chart.resize(); } catch (_) {}
      }
    };
    this.handleThemeChange = () => this.render(true);
    window.addEventListener('resize', this.handleResize);
    window.addEventListener('trifle:theme-changed', this.handleThemeChange);
    this.render();
  },

  updated() {
    // LiveView patches may replace inner nodes; refresh targets before rendering.
    this.chartTarget = this.el.querySelector('[data-role="chart"]');
    this.tableRoot = this.el.querySelector('[data-role="table-root"]');
    this.render();
  },

  destroyed() {
    this.disposeChart();
    if (this.retryTimer) {
      clearTimeout(this.retryTimer);
      this.retryTimer = null;
    }
    window.removeEventListener('resize', this.handleResize);
    window.removeEventListener('trifle:theme-changed', this.handleThemeChange);
  },

  getTheme() {
    return document.documentElement.classList.contains('dark') ? 'dark' : 'light';
  },

  disposeChart() {
    if (this.chart && typeof this.chart.dispose === 'function') {
      try { this.chart.dispose(); } catch (_) {}
    }
    this.chart = null;
    this.chartElement = null;
    this.chartTheme = null;
    if (this.retryTimer) {
      clearTimeout(this.retryTimer);
      this.retryTimer = null;
    }
    if (this._sparklineTimer) {
      clearTimeout(this._sparklineTimer);
      this._sparklineTimer = null;
    }
  },

  ensureChart(opts = {}) {
    const container = this.chartTarget;
    if (!container) return null;
    if (container.clientWidth === 0 || container.clientHeight === 0) {
      if (this.retryTimer) clearTimeout(this.retryTimer);
      this.retryTimer = setTimeout(() => this.render(true), 140);
      return null;
    }
    const theme = this.getTheme();
    if (this.chart && (this.chartElement !== container || this.chartTheme !== theme)) {
      this.disposeChart();
    }
    if (!this.chart) {
      container.innerHTML = '';
      this.chart = echarts.init(container, theme === 'dark' ? 'dark' : undefined, withChartOpts(opts));
      this.chartTheme = theme;
      this.chartElement = container;
    }
    return this.chart;
  },

  render(force = false) {
    this.chartTarget = this.el.querySelector('[data-role="chart"]');
    this.tableRoot = this.el.querySelector('[data-role="table-root"]');

    const type = (this.el.dataset.type || '').toLowerCase();
    const tab = this.el.dataset.tab || '';
    const chartRaw = this.el.dataset.chart || '';
    const paletteRaw = this.el.dataset.colors || '';
    const visualRaw = this.el.dataset.visual || '';
    const textRaw = this.el.dataset.text || '';
    const key = [type, tab, chartRaw, paletteRaw, visualRaw, textRaw].join('||');
    const chartWidgetTypes = ['timeseries', 'category', 'distribution', 'heatmap', 'kpi'];
    const chartContentMissing =
      chartWidgetTypes.includes(type) &&
      !!this.chartTarget &&
      this.chartTarget.childElementCount === 0;
    const textContentMissing =
      type === 'text' &&
      !!this.chartTarget &&
      this.chartTarget.childElementCount === 0;
    const tableContentMissing = !!this.tableRoot && this.tableRoot.childElementCount === 0;
    const tableRootChanged = !!this._lastTableRoot && this._lastTableRoot !== this.tableRoot;
    this._lastTableRoot = this.tableRoot;

    const chartContainerChanged =
      !!this.chart &&
      (
        this.chartElement !== this.chartTarget ||
        !this.chartElement ||
        !this.chartElement.isConnected
      );

    const chartDomWiped =
      !!this.chart &&
      !!this.chartTarget &&
      !this.chartTarget.querySelector('canvas, svg');

    if (chartContainerChanged || chartDomWiped || tableRootChanged) {
      this.disposeChart();
      force = true;
    }

    if (
      !force &&
      key === this.lastPayloadKey &&
      !chartContentMissing &&
      !textContentMissing &&
      !tableContentMissing
    ) {
      if (this.chart && typeof this.chart.resize === 'function') {
        try { this.chart.resize(); } catch (_) {}
        // Reflow can complete after LiveView patch; do a deferred resize pass as well.
        requestAnimationFrame(() => {
          if (this.chart && typeof this.chart.resize === 'function') {
            try { this.chart.resize(); } catch (_) {}
          }
        });
        setTimeout(() => {
          if (this.chart && typeof this.chart.resize === 'function') {
            try { this.chart.resize(); } catch (_) {}
          }
        }, 90);
      }
      return;
    }
    this.lastPayloadKey = key;
    this.disposeChart();
    this.colors = parseJsonSafe(paletteRaw) || [];
    const chartData = parseJsonSafe(chartRaw);
    const visualData = parseJsonSafe(visualRaw);
    const textData = parseJsonSafe(textRaw);

    if (type === 'timeseries') {
      this.renderTimeseries(chartData);
      return;
    }

    if (type === 'category') {
      this.renderCategory(chartData);
      return;
    }

    if (type === 'distribution' || type === 'heatmap') {
      this.renderDistribution(chartData);
      return;
    }

    if (type === 'kpi') {
      this.renderKpi(chartData, visualData);
      return;
    }

    if (type === 'text') {
      this.renderText(textData);
      this.showTablePlaceholder('Series summary is not available for text widgets.');
      return;
    }

    this.showChartPlaceholder('Expanded view is currently available for chart widgets.');
    this.showTablePlaceholder('No additional data available.');
  },

  seriesColor(index) {
    if (Array.isArray(this.colors) && this.colors.length) {
      return this.colors[index % this.colors.length];
    }
    const fallback = ['#14b8a6', '#6366f1', '#f59e0b', '#ec4899', '#3b82f6', '#10b981', '#f97316', '#8b5cf6'];
    return fallback[index % fallback.length];
  },

  normalizedExplicitColor(color) {
    return typeof color === 'string' && color.trim() !== '' ? color.trim() : null;
  },

  resolveSeriesColor(color, index = 0) {
    return this.normalizedExplicitColor(color) || this.seriesColor(index);
  },

  getWidgetConfig(data) {
    if (!data || typeof data !== 'object') return {};

    if (data.widgetConfig && typeof data.widgetConfig === 'object') {
      return data.widgetConfig;
    }

    if (data.widget_config && typeof data.widget_config === 'object') {
      return data.widget_config;
    }

    return {};
  },

  resolveCategoryLegendVisible(data, chartType, seriesCount) {
    const widgetConfig = this.getWidgetConfig(data);
    const explicitLegendVisible =
      widgetConfig.legendVisible !== undefined
        ? widgetConfig.legendVisible
        : widgetConfig.legend_visible !== undefined
          ? widgetConfig.legend_visible
          : data && data.legend !== undefined
            ? data.legend
            : undefined;

    if (explicitLegendVisible !== undefined) {
      return !!explicitLegendVisible;
    }

    if (chartType === 'pie' || chartType === 'donut') {
      return seriesCount > 1;
    }

    return true;
  },

  renderEmptyChart(message, opts = {}) {
    const chart = this.ensureChart(opts);
    if (!chart) return;

    const isDarkMode = this.getTheme() === 'dark';
    const emptyText =
      typeof message === 'string' && message.trim() !== ''
        ? message
        : 'No data available yet.';

    chart.setOption({
      backgroundColor: 'transparent',
      animation: false,
      grid: { top: 20, bottom: 36, left: 52, right: 24, containLabel: true },
      xAxis: {
        type: 'category',
        data: [],
        axisLine: { lineStyle: { color: isDarkMode ? '#334155' : '#e2e8f0' } },
        axisTick: { show: false },
        axisLabel: { show: false },
        splitLine: { show: false }
      },
      yAxis: {
        type: 'value',
        min: 0,
        max: 1,
        axisLine: { show: false },
        axisTick: { show: false },
        axisLabel: { show: false },
        splitLine: {
          lineStyle: {
            color: isDarkMode ? '#1f2937' : '#e2e8f0',
            opacity: isDarkMode ? 0.35 : 1
          }
        }
      },
      tooltip: { show: false },
      series: [{ type: 'line', data: [], silent: true }],
      graphic: [{
        type: 'text',
        left: 'center',
        top: 'middle',
        silent: true,
        style: {
          text: emptyText,
          fill: isDarkMode ? '#94a3b8' : '#64748b',
          textAlign: 'center',
          font:
            '500 13px Inter var, Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif'
        }
      }]
    }, true);

    try { chart.resize(); } catch (_) {}
  },

  renderTimeseries(data) {
    if (!data || !Array.isArray(data.series) || data.series.length === 0) {
      this.renderEmptyChart('No chart data available yet.');
      this.showTablePlaceholder('No series data available yet.');
      return;
    }

    const chart = this.ensureChart();
    if (!chart) return;

    const theme = this.getTheme();
    const isDarkMode = theme === 'dark';
    const chartType = String(data.chart_type || 'line').toLowerCase();
    const isBar = chartType === 'bar';
    const isArea = chartType === 'area';
    const isDots = chartType === 'dots';
    const seriesType = isBar ? 'bar' : isDots ? 'scatter' : 'line';
    const stacked = !!data.stacked;
    const normalized = !!data.normalized;
    const showLegend = !!data.legend;
    const bottomPadding = showLegend ? 56 : 28;
    const palette = Array.isArray(this.colors) ? this.colors : [];
    const chartFontFamily =
      'Inter var, Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif';
    const overlayLabelBackground = isDarkMode ? 'rgba(15, 23, 42, 0.85)' : 'rgba(255, 255, 255, 0.92)';
    const overlayLabelText = isDarkMode ? '#F8FAFC' : '#0F172A';

    const series = (data.series || []).map((s, idx) => {
      const base = {
        name: s.name || `Series ${idx + 1}`,
        type: seriesType,
        data: Array.isArray(s.data) ? s.data : [],
        showSymbol: isDots
      };
      if (isDots) {
        base.symbol = 'circle';
        base.symbolSize = 5;
      }
      if (stacked && !isDots) base.stack = 'total';
      if (isArea) base.areaStyle = { opacity: 0.1 };
      const explicitColor =
        typeof s.color === 'string' && s.color.trim() !== '' ? s.color.trim() : null;
      const paletteColor = palette.length ? palette[idx % palette.length] : null;
      const color = explicitColor || paletteColor;
      if (color) {
        base.itemStyle = { color };
        base.lineStyle = { color };
        if (isArea) base.areaStyle = { opacity: 0.1, color };
      }
      return base;
    });

    const overlay = data.alert_overlay || null;
    const alertStrategy = String(data.alert_strategy || '').toLowerCase();
    const shouldApplyAlertAxis = !!overlay && (alertStrategy === 'threshold' || alertStrategy === 'range');

    if (overlay && series.length) {
      const primarySeries = series[0];
      const overlayMarks = this.buildOverlayMarkAreas({
        overlay,
        overlayLabelText,
        overlayLabelBackground,
        chartFontFamily
      });

      if (overlayMarks.markArea) primarySeries.markArea = overlayMarks.markArea;
      if (overlayMarks.markLine) primarySeries.markLine = overlayMarks.markLine;
      if (overlayMarks.markPoint) primarySeries.markPoint = overlayMarks.markPoint;
    }

    const baselineSeries = this.buildBaselineSeries(data, overlay, overlayLabelText);

    const ongoingInfo = detectOngoingSegment(data.series || []);
    if (ongoingInfo && series.length) {
      const start = new Date(ongoingInfo.lastTs - ongoingInfo.bucketMs * 0.5);
      const end = new Date(ongoingInfo.lastTs + ongoingInfo.bucketMs * 0.5);
      if (!Number.isNaN(start.getTime()) && !Number.isNaN(end.getTime())) {
        const areaColor = isDarkMode ? 'rgba(148,163,184,0.26)' : 'rgba(148,163,184,0.16)';
        const primarySeries = series[0];
        const existing = primarySeries.markArea && Array.isArray(primarySeries.markArea.data) ? primarySeries.markArea.data : [];
        primarySeries.markArea = {
          data: existing.concat([[
            { xAxis: start.toISOString(), itemStyle: { color: areaColor }, label: { show: false }, emphasis: { disabled: true } },
            { xAxis: end.toISOString() }
          ]]),
          silent: true,
          emphasis: { disabled: true }
        };
      }
    }

    const finalSeries = series.concat(baselineSeries);
    const legendData = Array.from(new Set(finalSeries.map((s) => s.name).filter((name) => name != null && name !== '')));
    const textColor = isDarkMode ? '#9CA3AF' : '#6B7280';
    const axisLineColor = isDarkMode ? '#374151' : '#E5E7EB';
    const legendText = isDarkMode ? '#D1D5DB' : '#374151';

    const extractPointValue = (point) => {
      if (Array.isArray(point)) return Number(point[1]);
      if (point && typeof point === 'object') {
        if (Array.isArray(point.value)) return Number(point.value[1]);
        if ('value' in point) return Number(point.value);
      }
      if (Number.isFinite(point)) return Number(point);
      return null;
    };

    const updateBounds = (bounds, value) => {
      if (!Number.isFinite(value)) return;
      if (value < bounds.min) bounds.min = value;
      if (value > bounds.max) bounds.max = value;
    };

    const seriesBounds = { min: Infinity, max: -Infinity };
    finalSeries.forEach((s) => {
      (s.data || []).forEach((point) => {
        updateBounds(seriesBounds, extractPointValue(point));
      });
    });

    const yAxis = this.buildYAxisConfig({
      normalized,
      data,
      seriesBounds,
      overlay,
      isDarkMode,
      shouldApplyAlertAxis,
      chartFontFamily
    });

    chart.setOption({
      backgroundColor: 'transparent',
      textStyle: { fontFamily: chartFontFamily },
      color: palette.length ? palette : undefined,
      grid: { top: 12, bottom: bottomPadding, left: 56, right: 24, containLabel: true },
      xAxis: {
        type: 'time',
        axisLine: { lineStyle: { color: axisLineColor } },
        axisLabel: {
          color: textColor,
          margin: 10,
          hideOverlap: true,
          fontFamily: chartFontFamily
        },
        splitLine: { show: false }
      },
      yAxis,
      legend: showLegend
        ? { type: 'scroll', bottom: 6, textStyle: { color: legendText, fontFamily: chartFontFamily }, data: legendData }
        : { show: false },
      tooltip: {
        trigger: 'axis',
        appendToBody: true,
        textStyle: { fontFamily: chartFontFamily },
        formatter: (params) => {
          const list = Array.isArray(params) ? params : [];
          if (!list.length) return '';
          const header = list[0].axisValueLabel || '';
          const formatValue = (val) => {
            if (val == null) return '-';
            if (normalized) {
              const pct = Number(val);
              return Number.isFinite(pct) ? `${pct.toFixed(2)}%` : '-';
            }
            return formatCompactNumber(val);
          };
          const lines = list.map((p) => {
            const raw = Array.isArray(p.value) ? p.value[1] : (p.data && Array.isArray(p.data) ? p.data[1] : p.value);
            return `${p.marker || ''}${p.seriesName || ''}: <strong>${formatValue(raw)}</strong>`;
          });
          const note = ongoingInfo
            ? '<div style="margin-top:6px;color:#64748b;font-size:11px;">Latest segment is still in progress</div>'
            : '';
          return `<div>${header}</div><div>${lines.join('<br/>')}</div>${note}`;
        }
      },
      series: finalSeries
    }, true);

    try { chart.resize(); } catch (_) {}
    this.renderTimeseriesTable(data);
  },

  buildOverlayMarkAreas({ overlay, overlayLabelText, overlayLabelBackground, chartFontFamily }) {
    if (!overlay || typeof overlay !== 'object') {
      return { markArea: null, markLine: null, markPoint: null };
    }

    const markAreas = [];
    const defaultSegmentColor = 'rgba(248,113,113,0.22)';
    const defaultBandColor = 'rgba(16,185,129,0.08)';
    const defaultLineColor = '#f87171';
    const defaultPointColor = '#f97316';

    const isoValue = (iso, ts) => {
      if (iso) return iso;
      if (typeof ts === 'number') {
        const dt = new Date(ts);
        if (!Number.isNaN(dt.getTime())) return dt.toISOString();
      }
      return null;
    };

    if (Array.isArray(overlay.segments)) {
      overlay.segments.forEach((segment, index) => {
        const startIso = isoValue(segment.from_iso, segment.from_ts);
        let endIso = isoValue(segment.to_iso, segment.to_ts);
        if (startIso && endIso && startIso === endIso) {
          const adjusted = new Date(startIso);
          if (!Number.isNaN(adjusted.getTime())) {
            adjusted.setMinutes(adjusted.getMinutes() + 1);
            endIso = adjusted.toISOString();
          }
        }
        if (startIso && endIso) {
          const itemStyle = segment.color ? { color: segment.color } : { color: defaultSegmentColor };
          const label = segment.label || `Alert window #${index + 1}`;
          markAreas.push([
            {
              name: label,
              xAxis: startIso,
              itemStyle,
              label: {
                color: overlayLabelText,
                fontFamily: chartFontFamily,
                position: 'insideTop',
                distance: 6,
                overflow: 'break',
                align: 'left',
                backgroundColor: overlayLabelBackground,
                padding: [2, 6],
                borderRadius: 4
              },
              emphasis: { disabled: true }
            },
            { xAxis: endIso }
          ]);
        }
      });
    }

    if (Array.isArray(overlay.bands)) {
      overlay.bands.forEach((band) => {
        if (typeof band.min === 'number' && typeof band.max === 'number') {
          const itemStyle = band.color ? { color: band.color } : { color: defaultBandColor };
          const label = band.label || 'Target band';
          markAreas.push([
            {
              name: label,
              yAxis: band.min,
              xAxis: 'min',
              itemStyle,
              label: {
                color: overlayLabelText,
                fontFamily: chartFontFamily,
                position: 'insideTop',
                distance: 6,
                overflow: 'break',
                align: 'left',
                backgroundColor: overlayLabelBackground,
                padding: [2, 6],
                borderRadius: 4
              },
              emphasis: { disabled: true }
            },
            { yAxis: band.max, xAxis: 'max' }
          ]);
        }
      });
    }

    const markLine =
      Array.isArray(overlay.reference_lines) && overlay.reference_lines.length
        ? {
            symbol: 'none',
            silent: true,
            animation: false,
            emphasis: { disabled: true },
            data: overlay.reference_lines
              .filter((line) => typeof line.value === 'number')
              .map((line) => ({
                yAxis: line.value,
                name: line.label || formatCompactNumber(line.value),
                lineStyle: {
                  color: line.color || defaultLineColor,
                  type: 'dashed',
                  width: 1.2
                },
                label: {
                  formatter: line.label || formatCompactNumber(line.value),
                  color: overlayLabelText,
                  fontFamily: chartFontFamily,
                  position: 'insideEndTop',
                  distance: 8,
                  overflow: 'break',
                  backgroundColor: overlayLabelBackground,
                  padding: [2, 6],
                  borderRadius: 4
                },
                emphasis: { disabled: true }
              }))
          }
        : null;

    const markPointData = Array.isArray(overlay.points)
      ? overlay.points
          .filter((point) => typeof point.value === 'number')
          .map((point, idx) => {
            const coordX = isoValue(point.at_iso, point.ts);
            if (!coordX) return null;
            const color = point.color || defaultPointColor;
            return {
              coord: [coordX, point.value],
              value: point.value,
              name: point.label || `Alert point #${idx + 1}`,
              itemStyle: { color },
              label: {
                color: overlayLabelText,
                formatter: point.label || formatCompactNumber(point.value),
                fontFamily: chartFontFamily,
                position: 'top',
                distance: 10,
                backgroundColor: overlayLabelBackground,
                padding: [2, 6],
                borderRadius: 4,
                overflow: 'truncate'
              }
            };
          })
          .filter(Boolean)
      : [];

    const markPoint = markPointData.length
      ? {
          symbol: 'circle',
          symbolSize: 16,
          animation: false,
          silent: true,
          emphasis: { disabled: true },
          data: markPointData
        }
      : null;

    return {
      markArea: markAreas.length ? { data: markAreas, silent: true, emphasis: { disabled: true } } : null,
      markLine,
      markPoint
    };
  },

  buildBaselineSeries(data, overlay, overlayLabelText) {
    const baselineSeries = [];
    const baselineCandidates = []
      .concat(Array.isArray(data?.alert_baseline_series) ? data.alert_baseline_series : [])
      .concat(overlay && Array.isArray(overlay.baseline_series) ? overlay.baseline_series : []);
    const seenBaselineKeys = new Set();

    baselineCandidates
      .filter((baseline) => {
        if (!baseline || !Array.isArray(baseline.data) || baseline.data.length === 0) return false;
        const key = baseline.name || `${baseline.color || 'baseline'}-${baseline.line_type || 'line'}`;
        if (seenBaselineKeys.has(key)) return false;
        seenBaselineKeys.add(key);
        return true;
      })
      .forEach((baseline) => {
        const baselineData = Array.isArray(baseline.data) ? baseline.data : [];
        if (!baselineData.length) return;
        const baselineColor = baseline.color || overlayLabelText;
        const lineType = baseline.line_type || 'dashed';
        const lineWidth = typeof baseline.width === 'number' ? baseline.width : 1.3;
        const lineOpacity = typeof baseline.opacity === 'number' ? baseline.opacity : 0.85;
        baselineSeries.push({
          name: baseline.name || 'Detection baseline',
          type: 'line',
          data: baselineData,
          showSymbol: false,
          smooth: false,
          connectNulls: true,
          animation: false,
          lineStyle: {
            width: lineWidth,
            type: lineType,
            color: baselineColor,
            opacity: lineOpacity
          },
          itemStyle: { color: baselineColor, opacity: lineOpacity },
          emphasis: { focus: 'series' },
          tooltip: {
            valueFormatter: (v) => (v == null ? '-' : formatCompactNumber(v))
          },
          zlevel: 1,
          z: 25
        });
      });

    return baselineSeries;
  },

  buildYAxisConfig({
    normalized,
    data,
    seriesBounds,
    overlay,
    isDarkMode,
    shouldApplyAlertAxis,
    chartFontFamily
  }) {
    const textColor = isDarkMode ? '#9CA3AF' : '#6B7280';
    const axisLineColor = isDarkMode ? '#374151' : '#E5E7EB';
    const gridLineColor = isDarkMode ? '#1F2937' : '#E5E7EB';

    const updateBounds = (bounds, value) => {
      if (!Number.isFinite(value)) return;
      if (value < bounds.min) bounds.min = value;
      if (value > bounds.max) bounds.max = value;
    };

    let alertAxis = null;
    if (shouldApplyAlertAxis) {
      const overlayBounds = { min: Infinity, max: -Infinity };
      if (overlay) {
        if (Array.isArray(overlay.reference_lines)) {
          overlay.reference_lines.forEach((line) => {
            updateBounds(overlayBounds, Number(line.value));
          });
        }
        if (Array.isArray(overlay.bands)) {
          overlay.bands.forEach((band) => {
            updateBounds(overlayBounds, Number(band.min));
            updateBounds(overlayBounds, Number(band.max));
          });
        }
        if (Array.isArray(overlay.points)) {
          overlay.points.forEach((point) => {
            updateBounds(overlayBounds, Number(point.value));
          });
        }
      }

      const minCandidates = [seriesBounds.min, overlayBounds.min].filter(Number.isFinite);
      const maxCandidates = [seriesBounds.max, overlayBounds.max].filter(Number.isFinite);
      const positiveOnly = minCandidates.length === 0 || minCandidates.every((value) => value >= 0);
      let axisMinCandidate = minCandidates.length ? Math.min(...minCandidates) : (positiveOnly ? 0 : -1);
      let axisMaxCandidate =
        maxCandidates.length ? Math.max(...maxCandidates) : (axisMinCandidate > 0 ? axisMinCandidate : 1);
      if (Number.isFinite(axisMaxCandidate)) {
        if (!Number.isFinite(axisMinCandidate)) {
          axisMinCandidate = positiveOnly ? 0 : axisMaxCandidate;
        }
        alertAxis = { positiveOnly, axisMinCandidate, axisMaxCandidate };
      }
    }

    const yAxis = {
      type: 'value',
      min: 0,
      name: normalized ? (data.y_label || 'Percentage') : (data.y_label || ''),
      nameLocation: 'middle',
      nameGap: 44,
      nameTextStyle: { color: textColor, fontFamily: chartFontFamily },
      axisLine: { lineStyle: { color: axisLineColor } },
      axisLabel: {
        color: textColor,
        margin: 10,
        hideOverlap: true,
        fontFamily: chartFontFamily
      },
      splitLine: { lineStyle: { color: gridLineColor, opacity: isDarkMode ? 0.4 : 1 } }
    };

    if (normalized) {
      yAxis.axisLabel = Object.assign({}, yAxis.axisLabel, { formatter: (v) => `${v}%` });
      if (alertAxis) {
        const normalizedMax = Math.max(alertAxis.axisMaxCandidate, 100);
        const topPad = normalizedMax * 0.05 || 5;
        yAxis.min = 0;
        yAxis.max = normalizedMax + topPad;
      } else {
        yAxis.max = 100;
      }
      return yAxis;
    }

    yAxis.axisLabel = Object.assign({}, yAxis.axisLabel, {
      formatter: (value) => formatCompactNumber(value)
    });

    if (alertAxis) {
      let axisMin = alertAxis.positiveOnly ? 0 : alertAxis.axisMinCandidate;
      let axisMax = Math.max(alertAxis.axisMaxCandidate, axisMin + 1);
      if (!Number.isFinite(axisMin)) axisMin = 0;
      if (!Number.isFinite(axisMax)) axisMax = axisMin + 1;
      if (axisMax <= axisMin) axisMax = axisMin + Math.max(Math.abs(axisMin), 1);
      const span = axisMax - axisMin;
      const topPad = span * 0.12 || Math.max(Math.abs(axisMax), 1) * 0.12;
      const bottomPad = alertAxis.positiveOnly ? 0 : (span * 0.05 || topPad * 0.5);
      axisMax += topPad;
      axisMin -= bottomPad;
      if (alertAxis.positiveOnly && axisMin < 0) axisMin = 0;
      yAxis.min = axisMin;
      yAxis.max = axisMax;
    } else if (Number.isFinite(seriesBounds.min) && seriesBounds.min < 0) {
      const axisMin = seriesBounds.min;
      const rawMax = Number.isFinite(seriesBounds.max) ? seriesBounds.max : 0;
      let axisMax = rawMax;
      if (!Number.isFinite(axisMax) || axisMax <= axisMin) {
        axisMax = axisMin + Math.max(Math.abs(axisMin), 1);
      }
      const span = axisMax - axisMin;
      const pad = span * 0.1 || Math.max(Math.abs(axisMax), 1) * 0.1;
      yAxis.min = axisMin - pad * 0.4;
      yAxis.max = axisMax + pad;
    }

    return yAxis;
  },

  renderKpi(data, visual) {
    if (!this.chartTarget) return;
    this.disposeChart();
    this.chartTarget.innerHTML = '';

    if (!data) {
      this.renderEmptyChart('No KPI data available yet.');
      this.showTablePlaceholder('Series summary is only available when a sparkline is enabled.');
      return;
    }

    const wrapper = document.createElement('div');
    wrapper.className = 'h-full w-full flex flex-col gap-6 p-6';

    const widgetTitle = this.el.dataset.title;
    if (widgetTitle) {
      const titleEl = document.createElement('div');
      titleEl.className = 'text-sm font-medium uppercase tracking-wide text-slate-500 dark:text-slate-300';
      titleEl.textContent = widgetTitle;
      wrapper.appendChild(titleEl);
    }

    const headline = document.createElement('div');
    headline.className = 'text-5xl font-semibold text-slate-900 dark:text-white';
    headline.textContent = this.formatKpiMainValue(data);
    wrapper.appendChild(headline);

    const metaHtml = this.formatKpiMeta(data);
    if (metaHtml) {
      const meta = document.createElement('div');
      meta.className = 'text-base text-slate-600 dark:text-slate-300';
      meta.innerHTML = metaHtml;
      wrapper.appendChild(meta);
    }

    this.chartTarget.appendChild(wrapper);

    let seriesEntries = [];
    const baseSeriesName = (data.path && String(data.path)) || this.el.dataset.title || 'Series';

    if (visual && visual.type === 'sparkline' && Array.isArray(visual.data) && visual.data.length) {
      const chartWrapper = document.createElement('div');
      chartWrapper.className =
        'flex-1 min-h-[240px] rounded-lg border border-gray-200 dark:border-slate-700/80 bg-white dark:bg-slate-900/40 p-4';
      const chartDiv = document.createElement('div');
      chartDiv.className = 'h-full w-full';
      chartWrapper.appendChild(chartDiv);
      wrapper.appendChild(chartWrapper);

      const theme = this.getTheme();
      const lineColor = this.resolveSeriesColor(visual && visual.color, 0);
      const initSparkline = () => {
        if (chartDiv.clientWidth === 0 || chartDiv.clientHeight === 0) {
          if (this._sparklineTimer) clearTimeout(this._sparklineTimer);
          this._sparklineTimer = setTimeout(initSparkline, 80);
          return;
        }

        const chart = echarts.init(chartDiv, theme === 'dark' ? 'dark' : undefined, withChartOpts({ height: 240 }));
        this.chart = chart;
        this.chartElement = chartDiv;
        this.chartTheme = theme;

        chart.setOption({
          backgroundColor: 'transparent',
          grid: { top: 16, bottom: 16, left: 32, right: 32 },
          xAxis: { type: 'time', show: false },
          yAxis: { type: 'value', show: false },
          tooltip: {
            trigger: 'axis',
            appendToBody: true,
            valueFormatter: (v) => (v == null ? '-' : formatCompactNumber(v))
          },
          series: [{
            type: 'line',
            data: visual.data,
            smooth: true,
            showSymbol: false,
            lineStyle: { width: 2, color: lineColor },
            areaStyle: { color: lineColor, opacity: 0.18 }
          }]
        }, true);

        try { chart.resize(); } catch (_) {}
        if (this._sparklineTimer) {
          clearTimeout(this._sparklineTimer);
          this._sparklineTimer = null;
        }
      };

      initSparkline();

      seriesEntries = [{
        name: baseSeriesName,
        data: visual.data,
        color: lineColor
      }];
    } else if (visual && visual.type === 'progress') {
      const container = document.createElement('div');
      container.className =
        'flex-1 min-h-[180px] rounded-lg border border-gray-200 dark:border-slate-700/80 bg-white dark:bg-slate-900/40 p-6 flex flex-col justify-center gap-3';
      const label = document.createElement('div');
      label.className = 'text-sm text-slate-600 dark:text-slate-300';
      label.textContent = 'Progress';
      container.appendChild(label);

      const barOuter = document.createElement('div');
      barOuter.className = 'w-full h-4 rounded-full bg-gray-200 dark:bg-slate-700';
      const barInner = document.createElement('div');
      const progressCurrent = Number(visual.current);
      const target = Number(visual.target);
      const axisMax = Math.max(target || 0, progressCurrent || 0, 1);
      const ratio =
        Number.isFinite(progressCurrent) && axisMax !== 0 ? Math.max(0, Math.min(1, progressCurrent / axisMax)) : 0;
      barInner.className = 'h-4 rounded-full';
      barInner.style.width = `${ratio * 100}%`;
      const lineColor = this.resolveSeriesColor(visual && visual.color, 0);
      barInner.style.background = this.getProgressColor(visual, lineColor);
      barOuter.appendChild(barInner);
      container.appendChild(barOuter);

      wrapper.appendChild(container);

      if (Number.isFinite(progressCurrent)) {
        seriesEntries = [{
          name: baseSeriesName,
          data: [[Date.now(), progressCurrent]],
          color: lineColor
        }];
      }
    }

    if (!seriesEntries.length) {
      const fallbackValue =
        Number.isFinite(Number(data.value)) ? Number(data.value) :
        Number.isFinite(Number(data.current)) ? Number(data.current) :
        Number.isFinite(Number(data.previous)) ? Number(data.previous) :
        null;

      if (fallbackValue != null && Number.isFinite(fallbackValue)) {
        const lineColor = this.resolveSeriesColor(visual && visual.color, 0);
        seriesEntries = [{
          name: baseSeriesName,
          data: [[Date.now(), fallbackValue]],
          color: lineColor
        }];
      }
    }

    if (seriesEntries.length) {
      this.renderSeriesSummary(seriesEntries, 'No series data available yet.');
    } else {
      this.showTablePlaceholder('No series data available yet.');
    }
  },

  renderText(data) {
    if (!this.chartTarget) return;
    this.disposeChart();
    this.chartTarget.innerHTML = '';

    if (!data) {
      this.showChartPlaceholder('No content available yet.');
      return;
    }

    if ((data.subtype || '').toLowerCase() === 'html' && data.payload) {
      const html = document.createElement('div');
      html.className = 'w-full h-full overflow-auto text-left text-slate-900 dark:text-slate-100 p-6';
      const sanitizedHtml = sanitizeRichHtml(data.payload);
      html.innerHTML =
        sanitizedHtml && sanitizedHtml.trim().length
          ? sanitizedHtml
          : '<div class="text-sm text-slate-500 dark:text-slate-300 italic">No HTML content</div>';
      this.chartTarget.appendChild(html);
      return;
    }

    const wrapper = document.createElement('div');
    wrapper.className = 'w-full h-full flex flex-col gap-4 justify-center items-center text-center p-8';

    if (data.title) {
      const title = document.createElement('div');
      title.className = 'text-4xl font-semibold text-slate-900 dark:text-slate-50';
      title.textContent = data.title;
      wrapper.appendChild(title);
    }

    if (data.subtitle) {
      const subtitle = document.createElement('div');
      subtitle.className = 'text-lg text-slate-600 dark:text-slate-300 max-w-3xl whitespace-pre-line';
      subtitle.textContent = data.subtitle;
      wrapper.appendChild(subtitle);
    }

    this.chartTarget.appendChild(wrapper);
  },

  renderTimeseriesTable(data) {
    if (!this.tableRoot) return;
    const entries = Array.isArray(data?.series)
      ? data.series.map((series, idx) => ({
          name: series.name || `Series ${idx + 1}`,
          data: series.data || [],
          color: this.resolveSeriesColor(series && series.color, idx)
        }))
      : [];

    this.renderSeriesSummary(entries, 'No series data available yet.');
  },

  renderSeriesSummary(seriesEntries, emptyMessage) {
    if (!this.tableRoot) return;
    if (!Array.isArray(seriesEntries) || seriesEntries.length === 0) {
      this.showTablePlaceholder(emptyMessage);
      return;
    }

    const escapeHtml = (str) => String(str || '').replace(/[&<>"']/g, (s) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' }[s]));
    const rows = seriesEntries.map((entry, idx) => {
      const color = entry.color || this.seriesColor(idx);
      const values = this.extractNumericValues(entry.data);
      const stats = this.computeSeriesStats(values);
      const name = escapeHtml(entry.name || `Series ${idx + 1}`);
      const formatRaw = (value) => {
        if (!Number.isFinite(value)) return '';
        try { return new Intl.NumberFormat(undefined, { maximumFractionDigits: 6 }).format(value); }
        catch (_) { return String(value); }
      };
      const formatStat = (value) => Number.isFinite(value) ? formatCompactNumber(value) : '—';

      return {
        name,
        color,
        min: { display: formatStat(stats.min), raw: escapeHtml(formatRaw(stats.min)) },
        max: { display: formatStat(stats.max), raw: escapeHtml(formatRaw(stats.max)) },
        mean: { display: formatStat(stats.mean), raw: escapeHtml(formatRaw(stats.mean)) },
        sum: { display: formatStat(stats.sum), raw: escapeHtml(formatRaw(stats.sum)) }
      };
    });

    const bodyHtml = rows.map((row) => `
      <tr>
        <td class="py-2 pr-4 pl-5 text-sm whitespace-nowrap text-gray-600 dark:text-slate-300">
          <div class="flex items-center gap-3">
            <span class="inline-flex h-2.5 w-2.5 rounded-full" style="background-color: ${row.color};"></span>
            <span class="font-medium" style="color: ${row.color};">${row.name}</span>
          </div>
        </td>
        <td class="px-5 py-2 text-sm whitespace-nowrap text-gray-500 dark:text-slate-200" data-tooltip="${row.min.raw}">${row.min.display}</td>
        <td class="px-5 py-2 text-sm whitespace-nowrap text-gray-500 dark:text-slate-200" data-tooltip="${row.max.raw}">${row.max.display}</td>
        <td class="px-5 py-2 text-sm whitespace-nowrap text-gray-500 dark:text-slate-200" data-tooltip="${row.mean.raw}">${row.mean.display}</td>
        <td class="py-2 pr-5 pl-5 text-sm whitespace-nowrap text-gray-500 dark:text-slate-200" data-tooltip="${row.sum.raw}">${row.sum.display}</td>
      </tr>
    `).join('');

    this.tableRoot.innerHTML = `
      <div class="h-full overflow-x-auto">
        <table class="min-w-full divide-y divide-gray-300 dark:divide-slate-700">
          <thead class="bg-white dark:bg-slate-900/60">
            <tr>
              <th scope="col" class="py-3.5 pr-4 pl-5 text-left text-sm font-semibold whitespace-nowrap text-gray-900 dark:text-white">Path</th>
              <th scope="col" class="px-5 py-3.5 text-left text-sm font-semibold whitespace-nowrap text-gray-900 dark:text-white">Min</th>
              <th scope="col" class="px-5 py-3.5 text-left text-sm font-semibold whitespace-nowrap text-gray-900 dark:text-white">Max</th>
              <th scope="col" class="px-5 py-3.5 text-left text-sm font-semibold whitespace-nowrap text-gray-900 dark:text-white">Mean</th>
              <th scope="col" class="py-3.5 pr-5 pl-5 text-left text-sm font-semibold whitespace-nowrap text-gray-900 dark:text-white">Sum</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-200 bg-white dark:divide-slate-700 dark:bg-slate-900/60">
            ${bodyHtml}
          </tbody>
        </table>
      </div>
    `;

    this.activateFastTooltips();
  },

  extractNumericValues(seriesData) {
    if (!Array.isArray(seriesData)) return [];
    return seriesData
      .map((point) => {
        if (Array.isArray(point)) return Number(point[1]);
        if (point && typeof point === 'object') {
          if (Array.isArray(point.value)) return Number(point.value[1]);
          if ('value' in point) return Number(point.value);
        }
        return Number(point);
      })
      .filter((value) => Number.isFinite(value));
  },

  computeSeriesStats(values) {
    if (!Array.isArray(values) || values.length === 0) {
      return { min: null, max: null, mean: null, sum: null };
    }
    const sum = values.reduce((acc, value) => acc + value, 0);
    const min = Math.min(...values);
    const max = Math.max(...values);
    const mean = sum / values.length;
    return { min, max, mean, sum };
  },

  formatKpiMainValue(data) {
    const subtype = String(data.subtype || 'number').toLowerCase();
    const formatMaybe = (value) => (Number.isFinite(value) ? formatCompactNumber(value) : '—');

    switch (subtype) {
      case 'split':
        return formatMaybe(Number(data.current));
      case 'goal':
        return formatMaybe(Number(data.value));
      default:
        return formatMaybe(Number(data.value));
    }
  },

  formatKpiMeta(data) {
    const subtype = String(data.subtype || 'number').toLowerCase();
    const formatMaybe = (value) => (Number.isFinite(value) ? formatCompactNumber(value) : '—');

    if (subtype === 'split') {
      const current = Number(data.current);
      const previous = Number(data.previous);
      const diff = Number.isFinite(current) && Number.isFinite(previous) ? current - previous : null;
      const diffPct =
        Number.isFinite(current) && Number.isFinite(previous) && previous !== 0
          ? ((current - previous) / Math.abs(previous)) * 100
          : null;

      let diffFragment = '';
      if (data.show_diff && diffPct != null) {
        const formatted = `${diffPct >= 0 ? '+' : ''}${diffPct.toFixed(1)}%`;
        diffFragment = ` · <span class="${diff >= 0 ? 'text-emerald-500' : 'text-rose-500'}">${formatted}</span>`;
      }

      return `Current: <strong>${formatMaybe(current)}</strong> · Previous: <span class="opacity-80">${formatMaybe(previous)}</span>${diffFragment}`;
    }

    if (subtype === 'goal') {
      const value = Number(data.value);
      const target = Number(data.target);
      const ratio =
        Number.isFinite(value) && Number.isFinite(target) && target !== 0 ? (value / target) * 100 : null;
      const ratioText = ratio != null ? `${ratio.toFixed(1)}%` : '—';

      return `Target: <span class="opacity-80">${formatMaybe(target)}</span> · Progress: <strong>${ratioText}</strong>`;
    }

    return '';
  },

  getProgressColor(visual, preferredColor) {
    const explicit = this.normalizedExplicitColor(preferredColor);
    if (explicit) return explicit;
    if (!visual) return '#14b8a6';
    const ratio = Number.isFinite(Number(visual.ratio)) ? Number(visual.ratio) : null;
    if (ratio == null) return '#14b8a6';
    if (visual.invert) {
      return ratio <= 1 ? '#14b8a6' : '#ef4444';
    }
    return ratio >= 1 ? '#22c55e' : '#14b8a6';
  },

  renderCategory(data) {
    if (!data || !Array.isArray(data.data) || data.data.length === 0) {
      this.renderEmptyChart('No category data available yet.');
      this.showTablePlaceholder('No categories available yet.');
      return;
    }
    const chart = this.ensureChart();
    if (!chart) return;

    const isDarkMode = this.getTheme() === 'dark';
    const chartType = String(data.chart_type || 'bar').toLowerCase();
    const series = Array.isArray(data?.data) ? data.data : [];
    const legendVisible = this.resolveCategoryLegendVisible(data, chartType, series.length);

    let option;
    if (chartType === 'pie' || chartType === 'donut') {
      const labelColor = isDarkMode ? '#E2E8F0' : '#1F2937';
      const labelLineColor = isDarkMode ? '#475569' : '#94A3B8';
      option = {
        backgroundColor: 'transparent',
        legend: { show: legendVisible },
        tooltip: {
          trigger: 'item',
          appendToBody: true,
          textStyle: { color: isDarkMode ? '#F8FAFC' : '#1F2937' },
          backgroundColor: isDarkMode ? '#111827' : '#FFFFFF',
          borderColor: isDarkMode ? '#334155' : '#E5E7EB'
        },
        color: this.colors.length ? this.colors : undefined,
        series: [{
          type: 'pie',
          radius: chartType === 'donut' ? ['50%', '72%'] : '70%',
          data: series,
          label: { color: labelColor },
          labelLine: { lineStyle: { color: labelLineColor } },
          itemStyle: {
            color: (params) => {
              const explicit = data.data?.[params.dataIndex]?.color;
              if (typeof explicit === 'string' && explicit.trim() !== '') return explicit.trim();
              return this.seriesColor(params.dataIndex);
            }
          }
        }]
      };
    } else {
      option = {
        backgroundColor: 'transparent',
        grid: { top: 20, bottom: 40, left: 80, right: 36 },
        xAxis: { type: 'category', data: data.data.map((d) => d.name) },
        yAxis: {
          type: 'value',
          min: 0,
          axisLabel: { formatter: (v) => formatCompactNumber(v) }
        },
        tooltip: { trigger: 'axis', appendToBody: true },
        series: [{
          type: 'bar',
          data: data.data.map((d, idx) => {
            const explicit = typeof d?.color === 'string' && d.color.trim() !== '' ? d.color.trim() : null;
            const numeric = Number(d?.value);
            return {
              value: Number.isFinite(numeric) ? numeric : 0,
              itemStyle: { color: explicit || this.seriesColor(idx) }
            };
          })
        }]
      };
    }

    chart.setOption(option, true);
    try { chart.resize(); } catch (_) {}

    this.renderCategoryTable(data);
  },
  renderDistribution(data) {
    const widgetType = (this.el.dataset.type || '').toLowerCase();
    const isHeatmap =
      widgetType === 'heatmap' ||
      String(data?.chart_type || '').toLowerCase() === 'heatmap' ||
      String(data?.widget_type || '').toLowerCase() === 'heatmap';
    const is3d = isHeatmap || String(data?.mode || '2d').toLowerCase() === '3d';
    const labels = Array.isArray(data?.bucket_labels) ? data.bucket_labels : [];
    const verticalLabelsRaw = Array.isArray(data?.vertical_bucket_labels) ? data.vertical_bucket_labels : [];
    const series = Array.isArray(data?.series) ? data.series : [];
    const legendFlag = data?.legend;
    const showLegendDefault = series.length > 1;
    const showLegend = legendFlag === undefined ? showLegendDefault : !!legendFlag;
    const bottomPadding = showLegend ? 56 : 24;
    const chartFontFamily =
      'Inter var, Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif';

    let verticalLabels = verticalLabelsRaw;
    if (is3d && (!verticalLabels || verticalLabels.length === 0)) {
      const derived = new Set();
      series.forEach((s) => {
        (Array.isArray(s?.points) ? s.points : []).forEach((p) => {
          if (p && p.bucket_y != null && p.bucket_y !== '') derived.add(String(p.bucket_y));
        });
      });
      verticalLabels = Array.from(derived);
    }

    if (
      !Array.isArray(labels) ||
      labels.length === 0 ||
      !Array.isArray(series) ||
      series.length === 0 ||
      (is3d && (!verticalLabels || verticalLabels.length === 0))
    ) {
      this.renderEmptyChart('No distribution data available yet.');
      this.renderDistributionTable(data);
      return;
    }

    const chart = this.ensureChart();
    if (!chart) {
      this.renderDistributionTable(data);
      return;
    }

    const options = {
      isDarkMode: this.getTheme() === 'dark',
      colors: Array.isArray(this.colors) && this.colors.length ? this.colors : null,
      legendFlag,
      showLegend,
      bottomPadding,
      chartFontFamily
    };

    if (is3d && isHeatmap) {
      this.renderHeatmapDistribution(data, chart, labels, verticalLabels, series, options);
      return;
    }

    if (is3d) {
      this.render3DScatterDistribution(data, chart, labels, verticalLabels, series, options);
      return;
    }

    this.render2DBarDistribution(data, chart, labels, series, options);
  },

  renderHeatmapDistribution(data, chart, labels, verticalLabels, series, options) {
    const { isDarkMode, legendFlag, chartFontFamily, colors } = options;
    const labelIndexMap = buildBucketIndexMap(labels);
    const verticalLabelIndexMap = buildBucketIndexMap(verticalLabels);
    const seriesList = Array.isArray(series) ? series : [];
    const { heatmapData, breakdownByCell } = buildDistributionHeatmapAggregation({
      seriesList,
      labelIndexMap,
      verticalLabelIndexMap
    });

    if (!heatmapData.length) {
      this.renderEmptyChart('No distribution data available yet.');
      this.renderDistributionTable(data);
      return;
    }

    const showScale = legendFlag === undefined ? true : !!legendFlag;
    const gridBottom = showScale ? 72 : 20;
    const visualMapBottom = 8;
    const fallbackHeatColor = colors ? colors[0] : this.seriesColor(0);
    const visualSettings = resolveHeatmapVisualMap({
      payload: data,
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
    try { chart.resize(); } catch (_) {}
    this.renderDistributionTable(data);
  },

  render3DScatterDistribution(data, chart, labels, verticalLabels, series, options) {
    const { isDarkMode, colors, showLegend, bottomPadding, chartFontFamily } = options;
    const labelIndexMap = buildBucketIndexMap(labels);
    const verticalLabelIndexMap = buildBucketIndexMap(verticalLabels);
    const scatterData = buildDistributionScatterSeries({
      seriesList: series,
      labelIndexMap,
      verticalLabelIndexMap,
      resolveColor: (seriesItem, idx) => {
        const explicitColor =
          typeof seriesItem?.color === 'string' && seriesItem.color.trim() !== ''
            ? seriesItem.color.trim()
            : null;
        return explicitColor || (colors ? colors[idx % colors.length] : this.seriesColor(idx));
      }
    });
    const legendNames = scatterData.legendNames;
    const seriesData = scatterData.seriesData;

    if (!seriesData.length) {
      this.renderEmptyChart('No distribution data available yet.');
      this.renderDistributionTable(data);
      return;
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
      grid: { top: 16, left: 64, right: 16, bottom: bottomPadding },
      tooltip: {
        trigger: 'item',
        appendToBody: true,
        formatter: (params) => {
          const valueArr =
            Array.isArray(params.value) && params.value.length >= 3
              ? params.value
              : Array.isArray(params.data) && params.data.length >= 3
                ? params.data
                : null;

          if (!valueArr) return '';

          const xIdx = Number.isFinite(valueArr[0]) ? valueArr[0] : null;
          const yIdx = Number.isFinite(valueArr[1]) ? valueArr[1] : null;
          const val = Number.isFinite(valueArr[2]) ? valueArr[2] : 0;
          const xLabel = xIdx != null && labels[xIdx] ? labels[xIdx] : labels[0] || '';
          const yLabel = yIdx != null && verticalLabels[yIdx] ? verticalLabels[yIdx] : verticalLabels[0] || '';

          if (!xLabel && !yLabel) return '';

          const seriesName = params.seriesName || '';
          const marker = params.marker || '';
          const escapedXLabel = this.escapeHtml(xLabel);
          const escapedYLabel = this.escapeHtml(yLabel);
          const escapedSeriesName = this.escapeHtml(seriesName);
          const lines = [`${escapedXLabel} × ${escapedYLabel}`];

          if (escapedSeriesName || marker) {
            lines.push(`${marker}${escapedSeriesName}  <strong>${formatCompactNumber(val)}</strong>`);
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
      xAxis: {
        type: 'category',
        data: labels,
        splitLine: {
          show: true,
          lineStyle: { type: 'dashed', color: isDarkMode ? '#1f2937' : '#e2e8f0', opacity: isDarkMode ? 0.4 : 0.9 }
        },
        axisLabel: { color: isDarkMode ? '#CBD5F5' : '#475569', interval: 0, rotate: labels.length > 8 ? 30 : 0 }
      },
      yAxis: {
        type: 'category',
        data: verticalLabels,
        splitLine: {
          show: true,
          lineStyle: { type: 'dashed', color: isDarkMode ? '#1f2937' : '#e2e8f0', opacity: isDarkMode ? 0.4 : 0.9 }
        },
        axisLabel: { color: isDarkMode ? '#CBD5F5' : '#475569' }
      },
      series: seriesData
    };

    chart.setOption(option, true);
    try { chart.resize(); } catch (_) {}
    this.renderDistributionTable(data);
  },

  render2DBarDistribution(data, chart, labels, series, options) {
    const { isDarkMode, colors, showLegend, bottomPadding, chartFontFamily } = options;
    const legendNames = [];
    const seriesData = series.map((seriesItem, idx) => {
      const name = seriesItem?.name || `Series ${idx + 1}`;
      legendNames.push(name);
      const values = Array.isArray(seriesItem?.values) ? seriesItem.values : [];
      const explicitColor =
        typeof seriesItem?.color === 'string' && seriesItem.color.trim() !== ''
          ? seriesItem.color.trim()
          : null;
      const color = explicitColor || (colors ? colors[idx % colors.length] : this.seriesColor(idx));
      const dataPoints = labels.map((label) => {
        const match = values.find((v) => v && (v.bucket === label || v.bucket_x === label));
        const val = match && Number.isFinite(Number(match.value)) ? Number(match.value) : 0;
        return val;
      });
      return {
        name,
        type: 'bar',
        emphasis: { focus: 'series' },
        itemStyle: { color },
        data: dataPoints
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
      grid: { top: 16, left: 52, right: 16, bottom: bottomPadding, containLabel: true },
      tooltip: {
        trigger: 'axis',
        axisPointer: {
          type: 'line',
          lineStyle: { color: isDarkMode ? '#CBD5F5' : '#94a3b8', width: 1.5, type: 'dashed' }
        },
        appendToBody: true,
        valueFormatter: (v) => (v == null ? '-' : formatCompactNumber(v))
      },
      xAxis: {
        type: 'category',
        data: labels,
        axisLabel: { color: isDarkMode ? '#CBD5F5' : '#475569', interval: 0, rotate: labels.length > 6 ? 30 : 0 }
      },
      yAxis: {
        type: 'value',
        min: 0,
        axisLabel: { formatter: (value) => formatCompactNumber(value), color: isDarkMode ? '#CBD5F5' : '#475569' },
        splitLine: { lineStyle: { color: isDarkMode ? '#1f2937' : '#e2e8f0', opacity: isDarkMode ? 0.35 : 1 } }
      },
      series: seriesData
    };

    chart.setOption(option, true);
    try { chart.resize(); } catch (_) {}
    this.renderDistributionTable(data);
  },

  renderDistributionTable(data) {
    if (!this.tableRoot) return;
    const is3d =
      String(data?.mode || '2d').toLowerCase() === '3d' ||
      String(data?.chart_type || '').toLowerCase() === 'heatmap' ||
      String(data?.widget_type || '').toLowerCase() === 'heatmap';
    const series = Array.isArray(data?.series) ? data.series : [];
    const rows = [];

    series.forEach((seriesItem, idx) => {
      const name = seriesItem?.name || `Series ${idx + 1}`;
      const color = this.resolveSeriesColor(seriesItem && seriesItem.color, idx);

      if (is3d) {
        const points = Array.isArray(seriesItem?.points) ? seriesItem.points : [];
        points.forEach((p) => {
          if (!p) return;
          const value = Number(p.value);
          if (!Number.isFinite(value)) return;
          rows.push({
            series: name,
            color,
            bucket_x: p.bucket_x || '',
            bucket_y: p.bucket_y || '',
            value
          });
        });
      } else {
        const values = Array.isArray(seriesItem?.values) ? seriesItem.values : [];
        values.forEach((v) => {
          if (!v) return;
          const value = Number(v.value);
          if (!Number.isFinite(value)) return;
          rows.push({
            series: name,
            color,
            bucket_x: v.bucket || v.bucket_x || '',
            bucket_y: '',
            value
          });
        });
      }
    });

    if (!rows.length) {
      this.showTablePlaceholder('No distribution data available yet.');
      return;
    }

    rows.sort((a, b) => Number(b.value || 0) - Number(a.value || 0));

    const hasSeries = series.length > 1;
    const hasVertical = is3d && rows.some((row) => row.bucket_y);

    const escapeHtml = (str) =>
      String(str || '').replace(/[&<>"']/g, (s) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' }[s]));
    const formatRaw = (value) => {
      if (!Number.isFinite(value)) return '';
      try {
        return new Intl.NumberFormat(undefined, { maximumFractionDigits: 6 }).format(value);
      } catch (_) {
        return String(value);
      }
    };

    const headerCells = [];
    if (hasSeries) {
      headerCells.push(
        '<th scope="col" class="py-3.5 pr-4 pl-5 text-left text-sm font-semibold whitespace-nowrap text-gray-900 dark:text-white">Series</th>'
      );
    }
    headerCells.push(
      '<th scope="col" class="px-5 py-3.5 text-left text-sm font-semibold whitespace-nowrap text-gray-900 dark:text-white">Horizontal Bucket</th>'
    );
    if (hasVertical) {
      headerCells.push(
        '<th scope="col" class="px-5 py-3.5 text-left text-sm font-semibold whitespace-nowrap text-gray-900 dark:text-white">Vertical Bucket</th>'
      );
    }
    headerCells.push(
      '<th scope="col" class="py-3.5 pr-5 pl-5 text-left text-sm font-semibold whitespace-nowrap text-gray-900 dark:text-white">Value</th>'
    );

    const bodyRows = rows
      .map((row) => {
        const bucketX = escapeHtml(row.bucket_x || '');
        const bucketY = escapeHtml(row.bucket_y || '');
        const formattedValue = Number.isFinite(row.value) ? formatCompactNumber(row.value) : '—';
        const raw = escapeHtml(formatRaw(row.value));

        const seriesCell = hasSeries
          ? `
            <td class="py-2 pr-4 pl-5 text-sm whitespace-nowrap text-gray-600 dark:text-slate-300">
              <div class="flex items-center gap-3">
                <span class="inline-flex h-2.5 w-2.5 rounded-full" style="background-color: ${row.color};"></span>
                <span class="font-medium" style="color: ${row.color};">${escapeHtml(row.series)}</span>
              </div>
            </td>
          `
          : '';

        const verticalCell = hasVertical
          ? `<td class="px-5 py-2 text-sm whitespace-nowrap text-gray-600 dark:text-slate-200 font-mono">${bucketY || 'total'}</td>`
          : '';

        return `
          <tr>
            ${seriesCell}
            <td class="px-5 py-2 text-sm whitespace-nowrap text-gray-600 dark:text-slate-200 font-mono">${bucketX || 'total'}</td>
            ${verticalCell}
            <td class="py-2 pr-5 pl-5 text-sm whitespace-nowrap text-gray-500 dark:text-slate-200" data-tooltip="${raw}">${formattedValue}</td>
          </tr>
        `;
      })
      .join('');

    this.tableRoot.innerHTML = `
      <div class="h-full overflow-x-auto">
        <table class="min-w-full divide-y divide-gray-300 dark:divide-slate-700">
          <thead class="bg-white dark:bg-slate-900/60">
            <tr>
              ${headerCells.join('')}
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-200 bg-white dark:divide-slate-700 dark:bg-slate-900/60">
            ${bodyRows}
          </tbody>
        </table>
      </div>
    `;

    this.activateFastTooltips();
  },

  showChartPlaceholder(message) {
    if (!this.chartTarget) return;
    this.disposeChart();
    this.chartTarget.innerHTML = '';
    const placeholder = document.createElement('div');
    placeholder.className = 'w-full h-full flex items-center justify-center text-sm text-slate-500 dark:text-slate-300 text-center px-6';
    placeholder.textContent = message;
    this.chartTarget.appendChild(placeholder);
  },

  showTablePlaceholder(message) {
    if (!this.tableRoot) return;
    this.tableRoot.innerHTML = '';
    const wrapper = document.createElement('div');
    wrapper.className =
      'h-full w-full flex items-center justify-center text-sm text-slate-500 dark:text-slate-300 px-6 text-center';
    wrapper.textContent = message == null ? '' : String(message);
    this.tableRoot.appendChild(wrapper);
  },

  escapeHtml(str) {
    if (str == null) return '';
    return String(str).replace(/[&<>"']/g, (s) => ({
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;',
      '"': '&quot;',
      "'": '&#039;'
    }[s]));
  },

  renderCategoryTable(data) {
    if (!this.tableRoot) return;
    const items = Array.isArray(data?.data) ? data.data : [];
    if (!items.length) {
      this.showTablePlaceholder('No categories available yet.');
      return;
    }

    const escapeHtml = (str) => String(str || '').replace(/[&<>"']/g, (s) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' }[s]));
    const formatRaw = (value) => {
      if (!Number.isFinite(value)) return '';
      try {
        return new Intl.NumberFormat(undefined, { maximumFractionDigits: 6 }).format(value);
      } catch (_) {
        return String(value);
      }
    };

    const rows = items.map((item, idx) => {
      const name = escapeHtml(String(item.name ?? `Item ${idx + 1}`));
      const value = Number(item.value);
      const color = this.resolveSeriesColor(item && item.color, idx);
      const formatted = Number.isFinite(value) ? formatCompactNumber(value) : '—';
      const raw = escapeHtml(formatRaw(value));

      return `
        <tr>
          <td class="py-2 pr-4 pl-5 text-sm whitespace-nowrap text-gray-600 dark:text-slate-300">
            <div class="flex items-center gap-3">
              <span class="inline-flex h-2.5 w-2.5 rounded-full" style="background-color: ${color};"></span>
              <span class="font-medium" style="color: ${color};">${name}</span>
            </div>
          </td>
          <td class="px-5 py-2 text-sm whitespace-nowrap text-gray-500 dark:text-slate-200" data-tooltip="${raw}">${formatted}</td>
        </tr>
      `;
    }).join('');

    this.tableRoot.innerHTML = `
      <div class="h-full overflow-x-auto">
        <table class="min-w-full divide-y divide-gray-300 dark:divide-slate-700">
          <thead class="bg-white dark:bg-slate-900/60">
            <tr>
              <th scope="col" class="py-3.5 pr-4 pl-5 text-left text-sm font-semibold whitespace-nowrap text-gray-900 dark:text-white">Category</th>
              <th scope="col" class="px-5 py-3.5 text-left text-sm font-semibold whitespace-nowrap text-gray-900 dark:text-white">Value</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-200 bg-white dark:divide-slate-700 dark:bg-slate-900/60">
            ${rows}
          </tbody>
        </table>
      </div>
    `;

    this.activateFastTooltips();
  },

  activateFastTooltips() {
    if (!this.tableRoot) return;
    const fastTooltip = Hooks.FastTooltip;
    if (!fastTooltip || typeof fastTooltip.initTooltips !== 'function') return;
    const context = {
      el: this.tableRoot,
      showTooltip: fastTooltip.showTooltip.bind(fastTooltip),
      hideTooltip: fastTooltip.hideTooltip.bind(fastTooltip)
    };
    requestAnimationFrame(() => {
      try {
        fastTooltip.initTooltips.call(context);
      } catch (_) {}
    });
  }
};
};

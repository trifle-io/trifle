export const createDashboardGridTimeseriesRendererMethods = ({
  echarts,
  withChartOpts,
  formatCompactNumber,
  detectOngoingSegment,
  extractTimestamp
}) => ({
  _render_timeseries(items) {
    if (!Array.isArray(items)) return;
    const isDarkMode = document.documentElement.classList.contains('dark');
    const colors = this.colors || [];
    items.forEach((it) => {
      const item = this.el.querySelector(`.grid-stack-item[gs-id="${it.id}"]`);
      const body = item && item.querySelector('.grid-widget-body');
      if (!body) return;
      let container = body.querySelector('.ts-chart');
      if (!container) {
        body.innerHTML = '';
        body.classList.remove('items-center','justify-center','text-sm','text-gray-500','dark:text-slate-400');
        container = document.createElement('div');
        container.className = 'ts-chart';
        container.style.width = '100%';
        container.style.height = '100%';
        body.appendChild(container);
      }
      let chart = this._tsCharts[it.id];
      const initTheme = isDarkMode ? 'dark' : undefined;
      const ensureInit = () => {
        if (!chart) {
          if (container.clientWidth === 0 || container.clientHeight === 0) { setTimeout(ensureInit, 80); return; }
          chart = echarts.init(container, initTheme, withChartOpts());
          chart.group = this._tsSyncGroup;
          if (this._tsSyncGroup && !this._tsSyncConnected) {
            try { echarts.connect(this._tsSyncGroup); this._tsSyncConnected = true; } catch (_) {}
          }
          this._tsCharts[it.id] = chart;
        } else if (chart && chart.group !== this._tsSyncGroup) {
          chart.group = this._tsSyncGroup;
        }
        const type = (it.chart_type || 'line');
        const isBar = type === 'bar';
        const isArea = type === 'area';
        const isDots = type === 'dots';
        const seriesType = isBar ? 'bar' : isDots ? 'scatter' : 'line';
        const stacked = !!it.stacked;
        const normalized = !!it.normalized;
        const textColor = isDarkMode ? '#9CA3AF' : '#6B7280';
        const axisLineColor = isDarkMode ? '#374151' : '#E5E7EB';
        const gridLineColor = isDarkMode ? '#1F2937' : '#E5E7EB';
        const legendText = isDarkMode ? '#D1D5DB' : '#374151';
        const showLegend = !!it.legend;
        const bottomPadding = showLegend ? 56 : 28;
        const chartFontFamily = 'Inter var, Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif';
        const overlayLabelBackground = isDarkMode ? 'rgba(15, 23, 42, 0.85)' : 'rgba(255, 255, 255, 0.92)';
        const overlayLabelText = isDarkMode ? '#F8FAFC' : '#0F172A';
        const series = (it.series || []).map((s, idx) => {
          const base = {
            name: s.name || `Series ${idx + 1}`,
            type: seriesType,
            data: s.data || [],
            showSymbol: isDots
          };
          if (isDots) {
            base.symbol = 'circle';
            base.symbolSize = 5;
          }
          if (stacked && !isDots) base.stack = 'total';
          if (isArea) base.areaStyle = { opacity: 0.1 };
          const customColor = typeof s.color === 'string' && s.color.trim() !== '' ? s.color.trim() : null;
          const paletteColor = colors.length ? colors[idx % colors.length] : null;
          const appliedColor = customColor || paletteColor;
          if (appliedColor) {
            base.color = appliedColor;
            base.itemStyle = Object.assign({}, base.itemStyle, { color: appliedColor });
            base.lineStyle = Object.assign({}, base.lineStyle, { color: appliedColor });
            if (isArea) {
              base.areaStyle = Object.assign({ opacity: 0.1 }, { color: appliedColor });
            }
          }
          return base;
        });
        const overlay = it.alert_overlay || null;
        const alertStrategy = String(it.alert_strategy || '').toLowerCase();
        const shouldApplyAlertAxis = !!overlay && (alertStrategy === 'threshold' || alertStrategy === 'range');
        const baselineSeries = [];
        if (overlay && series.length) {
          const primarySeries = series[0];
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
            overlay.segments.forEach((seg, index) => {
              const startIso = isoValue(seg.from_iso, seg.from_ts);
              let endIso = isoValue(seg.to_iso, seg.to_ts);
              if (startIso && endIso && startIso === endIso) {
                const adjusted = new Date(startIso);
                if (!Number.isNaN(adjusted.getTime())) {
                  adjusted.setMinutes(adjusted.getMinutes() + 1);
                  endIso = adjusted.toISOString();
                }
              }
              if (startIso && endIso) {
                const itemStyle = seg.color ? { color: seg.color } : { color: defaultSegmentColor };
                const label = seg.label || `Alert window #${index + 1}`;
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
                  {
                    xAxis: endIso
                  }
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
                  {
                    yAxis: band.max,
                    xAxis: 'max'
                  }
                ]);
              }
            });
          }
          if (markAreas.length) {
            primarySeries.markArea = { data: markAreas, silent: true, emphasis: { disabled: true } };
          }
          if (Array.isArray(overlay.reference_lines) && overlay.reference_lines.length) {
            primarySeries.markLine = {
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
            };
          }
          if (Array.isArray(overlay.points)) {
            const markPoints = overlay.points
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
              .filter(Boolean);
            if (markPoints.length) {
              primarySeries.markPoint = {
                symbol: 'circle',
                symbolSize: 16,
                animation: false,
                silent: true,
                emphasis: { disabled: true },
                data: markPoints
              };
            }
          }
          const baselineCandidates = []
            .concat(Array.isArray(it.alert_baseline_series) ? it.alert_baseline_series : [])
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
        }
        const ongoingInfo = detectOngoingSegment(it.series || []);
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
        this._tsSeriesData[it.id] = series.map((s) => Array.isArray(s.data) ? s.data : []);
        const legendData = Array.from(new Set(finalSeries.map((s) => s.name).filter((name) => name != null && name !== '')));
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
          (s.data || []).forEach((point) => updateBounds(seriesBounds, extractPointValue(point)));
        });
        let alertAxis = null;
        if (shouldApplyAlertAxis) {
          const overlayBounds = { min: Infinity, max: -Infinity };
          if (overlay) {
            if (Array.isArray(overlay.reference_lines)) {
              overlay.reference_lines.forEach((line) => updateBounds(overlayBounds, Number(line.value)));
            }
            if (Array.isArray(overlay.bands)) {
              overlay.bands.forEach((band) => {
                updateBounds(overlayBounds, Number(band.min));
                updateBounds(overlayBounds, Number(band.max));
              });
            }
            if (Array.isArray(overlay.points)) {
              overlay.points.forEach((point) => updateBounds(overlayBounds, Number(point.value)));
            }
          }
          const minCandidates = [seriesBounds.min, overlayBounds.min].filter(Number.isFinite);
          const maxCandidates = [seriesBounds.max, overlayBounds.max].filter(Number.isFinite);
          const positiveOnly = minCandidates.length === 0 || minCandidates.every((value) => value >= 0);
          let axisMinCandidate = minCandidates.length ? Math.min(...minCandidates) : (positiveOnly ? 0 : -1);
          let axisMaxCandidate = maxCandidates.length ? Math.max(...maxCandidates) : (axisMinCandidate > 0 ? axisMinCandidate : 1);
          if (Number.isFinite(axisMaxCandidate)) {
            if (!Number.isFinite(axisMinCandidate)) {
              axisMinCandidate = positiveOnly ? 0 : axisMaxCandidate;
            }
            alertAxis = { positiveOnly, axisMinCandidate, axisMaxCandidate };
          }
        }
        const yName = normalized ? (it.y_label || 'Percentage') : (it.y_label || '');
        const yAxis = {
          type: 'value',
          min: 0,
          name: yName,
          nameLocation: 'middle',
          nameGap: 40,
          nameTextStyle: { color: textColor, fontFamily: chartFontFamily },
          axisLine: { lineStyle: { color: axisLineColor } },
          axisLabel: { color: textColor, margin: 8, hideOverlap: true, fontFamily: chartFontFamily },
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
        } else {
          yAxis.axisLabel = Object.assign({}, yAxis.axisLabel, {
            formatter: (v) => formatCompactNumber(v)
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
            const axisMaxCandidate = Number.isFinite(seriesBounds.max) ? seriesBounds.max : 0;
            let axisMax = axisMaxCandidate;
            if (!Number.isFinite(axisMax) || axisMax <= axisMin) {
              axisMax = axisMin + Math.max(Math.abs(axisMin), 1);
            }
            const span = axisMax - axisMin;
            const pad = span * 0.1 || Math.max(Math.abs(axisMax), 1) * 0.1;
            yAxis.min = axisMin - pad * 0.4;
            yAxis.max = axisMax + pad;
          }
        }
        const escapeHtml = (value) =>
          String(value == null ? '' : value).replace(/[&<>"']/g, (s) => ({
            '&': '&amp;',
            '<': '&lt;',
            '>': '&gt;',
            '"': '&quot;',
            "'": '&#039;'
          }[s]));

        chart.setOption({
          backgroundColor: 'transparent',
          textStyle: { fontFamily: chartFontFamily },
          grid: { top: 12, bottom: bottomPadding, left: 56, right: 20, containLabel: true },
          xAxis: {
            type: 'time',
            axisLine: { lineStyle: { color: axisLineColor } },
            axisLabel: { color: textColor, margin: 8, hideOverlap: true, fontFamily: chartFontFamily },
            splitLine: { show: false }
          },
          yAxis,
          legend: showLegend
            ? { type: 'scroll', bottom: 4, textStyle: { color: legendText, fontFamily: chartFontFamily }, data: legendData }
            : { show: false },
      tooltip: {
        trigger: 'axis',
        appendToBody: true,
        textStyle: { fontFamily: chartFontFamily },
            formatter: (params) => {
              const list = Array.isArray(params) ? params : [];
              if (!list.length) return '';
              const header = escapeHtml(list[0].axisValueLabel || '');
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
                const seriesName = escapeHtml(p.seriesName || '');
                return `${p.marker || ''}${seriesName}: <strong>${formatValue(raw)}</strong>`;
              });
              const note = ongoingInfo ? '<div style="margin-top:6px;color:#64748b;font-size:11px;">Latest segment is still in progress</div>' : '';
              return `<div>${header}</div><div>${lines.join('<br/>')}</div>${note}`;
            }
          },
          series: finalSeries
        }, true);
        try {
          chart.off('finished');
          chart.on('finished', () => {
            try { container.dataset.echartsReady = '1'; this._scheduleReadyMark(); } catch (_) {}
          });
        } catch (_) {}
        chart.resize();
        this._bind_ts_sync(chart, it.id);
      };
      setTimeout(ensureInit, 0);
    });
    this._seen.timeseries = true;
    this._scheduleReadyMark();
    this._lastTimeseries = this._deepClone(items);
  },

  _bind_ts_sync(chart, widgetId) {
    if (!chart || typeof chart.on !== 'function') return;
    const id = String(widgetId || '');
    if (chart.__tsSyncHandlers) {
      const { pointer, leave, dom, out } = chart.__tsSyncHandlers;
      try { chart.off('updateAxisPointer', pointer); } catch (_) {}
      if (dom && dom.removeEventListener && leave) {
        try { dom.removeEventListener('mouseleave', leave); } catch (_) {}
      }
      if (out) {
        try { chart.off('mouseout', out); } catch (_) {}
      }
    }
    const pointer = (event) => {
      if (this._tsSyncApplying) return;
      if (!this._tsCharts || Object.keys(this._tsCharts).length <= 1) return;
      const axisInfo = event && Array.isArray(event.axesInfo) ? event.axesInfo[0] : null;
      const value = axisInfo ? axisInfo.value : null;
      if (!Number.isFinite(value) && typeof value !== 'string') return;
      this._cancel_ts_hide();
      this._tsHoveringId = id;
      this._tsLastValue = value;
      this._queue_ts_sync({ type: 'show', value, sourceId: id });
      this._kick_ts_sync_loop();
      this._ensure_ts_pointer_listener();
    };
    const leave = () => this._schedule_ts_hide(id);
    const out = () => this._schedule_ts_hide(id);
    chart.on('updateAxisPointer', pointer);
    const dom = chart.getDom ? chart.getDom() : null;
    if (dom && dom.addEventListener) {
      dom.addEventListener('mouseleave', leave);
    }
    chart.on('mouseout', out);
    chart.__tsSyncHandlers = { pointer, leave, out, dom };
  },

  _queue_ts_sync(payload) {
    this._tsSyncPending = payload;
    if (this._tsSyncRaf) return;
    this._tsSyncRaf = requestAnimationFrame(() => {
      this._tsSyncRaf = null;
      const task = this._tsSyncPending;
      this._tsSyncPending = null;
      if (!task) return;
      this._apply_ts_sync(task);
    });
  },

  _apply_ts_sync(payload) {
    if (!payload || !this._tsCharts) return;
    const entries = Object.entries(this._tsCharts)
      .filter(([, chart]) => chart && !(chart.isDisposed && chart.isDisposed()));
    if (entries.length === 0) return;
    if (entries.length === 1 && payload.type === 'show') return;
    const { type, value } = payload;
    if (type === 'show' && !Number.isFinite(value) && typeof value !== 'string') return;
    this._tsSyncApplying = true;
    try {
      entries.forEach(([, chart]) => {
        if (type === 'show') {
          try {
            chart.dispatchAction({ type: 'updateAxisPointer', xAxisIndex: 0, value });
            const idx = this._nearest_ts_index(chart, value);
            if (idx != null) {
              chart.dispatchAction({ type: 'showTip', seriesIndex: 0, dataIndex: idx });
              chart.dispatchAction({ type: 'highlight', seriesIndex: 0, dataIndex: idx });
            } else {
              chart.dispatchAction({ type: 'showTip', xAxisIndex: 0, value });
            }
          } catch (_) {}
        } else if (type === 'hide') {
          try { chart.dispatchAction({ type: 'hideTip' }); } catch (_) {}
          try { chart.dispatchAction({ type: 'downplay', seriesIndex: 0 }); } catch (_) {}
        }
      });
    } finally {
      this._tsSyncApplying = false;
    }
  },

  _kick_ts_sync_loop() {
    if (this._tsSyncLoop) return;
    const tick = () => {
      this._tsSyncLoop = null;
      if (!this._tsHoveringId || this._tsLastValue == null) {
        return;
      }
      this._apply_ts_sync({ type: 'show', value: this._tsLastValue, sourceId: this._tsHoveringId });
      this._tsSyncLoop = requestAnimationFrame(tick);
    };
    this._tsSyncLoop = requestAnimationFrame(tick);
  },

  _schedule_ts_hide(sourceId) {
    if (this._tsHideTimer) return;
    if (this._tsSyncLoop) {
      cancelAnimationFrame(this._tsSyncLoop);
      this._tsSyncLoop = null;
    }
    this._tsHideTimer = setTimeout(() => {
      this._tsHideTimer = null;
      this._tsHoveringId = null;
      this._tsLastValue = null;
      this._queue_ts_sync({ type: 'hide', sourceId });
    }, 120);
  },

  _cancel_ts_hide() {
    if (this._tsHideTimer) {
      clearTimeout(this._tsHideTimer);
      this._tsHideTimer = null;
    }
  },

  _ensure_ts_pointer_listener() {
    if (this._tsPointerMove) return;
    this._tsPointerMove = (e) => {
      if (!this._tsHoveringId) return;
      const inside = this._point_inside_ts(e.clientX, e.clientY);
      if (inside) {
        this._cancel_ts_hide();
      } else {
        this._schedule_ts_hide(this._tsHoveringId);
      }
    };
    window.addEventListener('pointermove', this._tsPointerMove, true);
  },

  _point_inside_ts(x, y) {
    if (!this._tsCharts) return false;
    const charts = Object.values(this._tsCharts);
    for (let i = 0; i < charts.length; i += 1) {
      const chart = charts[i];
      if (!chart || (chart.isDisposed && chart.isDisposed())) continue;
      const dom = chart.getDom ? chart.getDom() : null;
      if (!dom || dom.offsetParent === null) continue;
      const rect = dom.getBoundingClientRect();
      if (x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom) return true;
    }
    return false;
  },

  _nearest_ts_index(chart, value) {
    const id = Object.entries(this._tsCharts || {}).find(([, c]) => c === chart)?.[0];
    if (!id) return null;
    const seriesData = (this._tsSeriesData && this._tsSeriesData[id]) || [];
    if (!Array.isArray(seriesData) || !seriesData.length) return null;
    const target = typeof value === 'string' ? new Date(value).getTime() : Number(value);
    if (!Number.isFinite(target)) return null;
    let best = null;
    let bestDiff = Infinity;
    const extractTs = (point) => extractTimestamp(point);
    const data = Array.isArray(seriesData[0]) ? seriesData[0] : [];
    for (let i = 0; i < data.length; i += 1) {
      const ts = extractTs(data[i]);
      if (!Number.isFinite(ts)) continue;
      const diff = Math.abs(ts - target);
      if (diff < bestDiff) {
        bestDiff = diff;
        best = i;
        if (diff === 0) break;
      }
    }
    return best;
  },
});

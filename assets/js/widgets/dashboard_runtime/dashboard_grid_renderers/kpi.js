export const createDashboardGridKpiRendererMethods = ({ echarts, withChartOpts }) => ({
  _render_kpi_values(items) {
    if (!Array.isArray(items)) return;

    const escapeHtml = (value) =>
      String(value == null ? '' : value).replace(/[&<>"']/g, (s) => ({
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#039;'
      }[s]));

    const formatNumber = (value) => {
      if (value === null || value === undefined || value === '') return '—';
      const n = Number(value);
      if (!Number.isFinite(n)) return escapeHtml(value);
      if (Math.abs(n) >= 1000) {
        const units = ['', 'K', 'M', 'B', 'T'];
        let idx = 0;
        let num = Math.abs(n);
        while (num >= 1000 && idx < units.length - 1) {
          num /= 1000;
          idx += 1;
        }
        const sign = n < 0 ? '-' : '';
        return `${sign}${num.toFixed(num < 10 ? 2 : 1)}${units[idx]}`;
      }
      return n.toFixed(2).replace(/\.00$/, '');
    };

    const toNumber = (value) => {
      if (value === null || value === undefined || value === '') return null;
      const n = Number(value);
      return Number.isFinite(n) ? n : null;
    };

    const formatPercent = (ratio) => {
      if (ratio === null || ratio === undefined) return '—';
      const pct = Number(ratio) * 100;
      if (!Number.isFinite(pct)) return '—';
      const abs = Math.abs(pct);
      const decimals = abs < 10 ? 1 : 0;
      return `${pct.toFixed(decimals).replace(/\.0$/, '')}%`;
    };

    items.forEach((it) => {
      const item = this.el.querySelector(`.grid-stack-item[gs-id="${it.id}"]`);
      const body = item && item.querySelector('.grid-widget-body');
      if (!body) return;

      body.classList.remove('items-center', 'justify-center', 'text-sm', 'text-gray-500', 'dark:text-slate-400');
      body.classList.add('flex-col', 'items-stretch');

      const sizeClass = (() => {
        const sz = (it.size || 'm');
        if (sz === 's') return 'text-2xl';
        if (sz === 'l') return 'text-4xl';
        return 'text-3xl';
      })();

      let wrap = body.querySelector('.kpi-wrap');
      if (!wrap) {
        body.innerHTML = `<div class="kpi-wrap w-full flex flex-col flex-1 grow" style="min-height: 0; gap: 12px;"><div class="kpi-top px-3"></div><div class="kpi-meta px-3" style="display: none;"></div><div class="kpi-visual" style="margin-top: auto; height: 40px; width: 100%; margin-left: 0; margin-right: 0; margin-bottom: 0;"></div></div>`;
        wrap = body.querySelector('.kpi-wrap');
      }
      if (!wrap) return;

      wrap.classList.add('flex', 'flex-col', 'flex-1', 'grow');
      wrap.classList.remove('justify-center');
      wrap.style.minHeight = '0';

      const top = wrap.querySelector('.kpi-top');
      const meta = wrap.querySelector('.kpi-meta');
      const visual = wrap.querySelector('.kpi-visual');

      const subtype = String(it.subtype || 'number').toLowerCase();
      const hasVisual = !!it.has_visual;
      const visualType = hasVisual && it.visual_type ? String(it.visual_type).toLowerCase() : null;
      wrap.style.gap = (subtype === 'goal' && hasVisual && visualType === 'progress') ? '6px' : '12px';

      if (meta) {
        meta.innerHTML = '';
        meta.style.display = 'none';
        meta.style.marginTop = '0';
        meta.style.marginBottom = '0';
      }

      if (visual) {
        if (!hasVisual) {
          visual.style.display = 'none';
          delete visual.dataset.visualType;
          visual.dataset.echartsReady = '1';
          const chart = this._sparklines && this._sparklines[it.id];
          if (chart && !chart.isDisposed()) chart.dispose();
          if (this._sparklines) delete this._sparklines[it.id];
          if (this._sparkTimers && this._sparkTimers[it.id]) {
            clearTimeout(this._sparkTimers[it.id]);
            delete this._sparkTimers[it.id];
          }
          if (this._sparkTypes) delete this._sparkTypes[it.id];
        } else {
          visual.style.display = '';
          visual.dataset.echartsReady = '0';
          visual.dataset.visualType = visualType || 'sparkline';
          if (visualType !== 'progress') {
            visual.style.marginTop = 'auto';
            visual.style.height = '40px';
            visual.style.width = '100%';
            visual.style.marginLeft = '0';
            visual.style.marginRight = '0';
            visual.style.marginBottom = '0';
          }
        }
      }

      if (!top) return;

      if (subtype === 'split') {
        const previous = toNumber(it.previous);
        const current = toNumber(it.current);
        const prevLabel = formatNumber(it.previous);
        const currLabel = formatNumber(it.current);
        const showDiff = !!it.show_diff && previous !== null && current !== null && previous !== 0;
        let diffHtml = '';
        if (showDiff) {
          const delta = current - previous;
          const pct = (delta / Math.abs(previous)) * 100;
          const up = delta >= 0;
          const pctText = `${Math.abs(pct).toFixed(Math.abs(pct) < 10 ? 2 : 1)}%`;
          const clrWrap = up ? 'bg-green-100 text-green-800 dark:bg-green-900 dark:text-green-200' : 'bg-red-100 text-red-800 dark:bg-red-900 dark:text-red-200';
          const arrow = up
            ? '<span class="inline-block align-middle" style="width:0;height:0;border-left:4px solid transparent;border-right:4px solid transparent;border-bottom:6px solid currentColor;line-height:0"></span>'
            : '<span class="inline-block align-middle" style="width:0;height:0;border-left:4px solid transparent;border-right:4px solid transparent;border-top:6px solid currentColor;line-height:0"></span>';
          diffHtml = `<span class="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium leading-none whitespace-nowrap ${clrWrap}">${arrow}<span class="sr-only"> ${up ? 'Increased' : 'Decreased'} by </span><span>${pctText}</span></span>`;
        }

        top.innerHTML = `
          <div class="w-full">
            <div class="flex items-baseline justify-between w-full">
              <div class="flex flex-wrap items-baseline gap-x-2 ${sizeClass} font-bold text-gray-900 dark:text-white">
                <span>${currLabel}</span>
                <span class="text-sm font-medium text-gray-500 dark:text-slate-400">from ${prevLabel}</span>
              </div>
              ${diffHtml}
            </div>
          </div>`;
        if (meta) meta.style.display = 'none';
      } else if (subtype === 'goal') {
        const valueLabel = formatNumber(it.value);
        const targetLabel = formatNumber(it.target);
        const ratio = toNumber(it.progress_ratio != null ? it.progress_ratio : it.ratio);
        const invertGoal = !!it.invert;
        const showProgress = hasVisual && visualType === 'progress';
        const goalValue = targetLabel && targetLabel !== '—' ? targetLabel : '';
        const badge = goalValue
          ? `<div class="flex flex-col items-end gap-1 text-right">
              <span class="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium leading-none whitespace-nowrap bg-slate-100 text-slate-700 dark:bg-slate-800/70 dark:text-slate-200">Goal</span>
              ${showProgress ? '' : `<span class="text-sm font-medium text-gray-500 dark:text-slate-400">${goalValue}</span>`}
            </div>`
          : '';

        top.innerHTML = `
          <div class="w-full">
            <div class="flex items-baseline justify-between w-full">
              <div class="flex flex-wrap items-baseline gap-x-2 ${sizeClass} font-bold text-gray-900 dark:text-white">
                <span>${valueLabel}</span>
              </div>
              ${badge}
            </div>
          </div>`;

        if (meta && showProgress) {
          const pctText = formatPercent(ratio);
          const goalText = goalValue || '';
          meta.style.display = 'flex';
          meta.style.alignItems = 'baseline';
          meta.style.justifyContent = 'space-between';
          meta.style.gap = '8px';
          meta.style.marginTop = 'auto';
          meta.style.marginBottom = '-8px';
          const goalMarkup = goalText
            ? `<span class="text-sm font-medium text-gray-500 dark:text-slate-400">${goalText}</span>`
            : '';
          let statusClass;
          if (ratio == null) {
            statusClass = 'text-gray-700 dark:text-slate-200';
          } else if (invertGoal) {
            statusClass = ratio <= 1 ? 'text-teal-600 dark:text-teal-300' : 'text-red-600 dark:text-red-300';
          } else {
            statusClass = ratio >= 1 ? 'text-green-600 dark:text-green-300' : 'text-teal-600 dark:text-teal-300';
          }
          meta.innerHTML = `
            <span class="text-sm font-semibold ${statusClass}">${pctText}</span>
            ${goalMarkup}`;
          if (visual && visual.dataset.visualType === 'progress') {
            visual.style.marginTop = '-10px';
          }
        }
      } else {
        const val = formatNumber(it.value);
        top.innerHTML = `<div class="${sizeClass} font-bold text-gray-900 dark:text-white">${val}</div>`;
        if (meta) meta.style.display = 'none';
      }
    });
    this._lastKpiValues = this._deepClone(items);
  },

  _render_kpi_visuals(items) {
    if (!Array.isArray(items)) return;
    const isDarkMode = document.documentElement.classList.contains('dark');
    const defaultLineColor = (this.colors && this.colors[0]) || '#14b8a6';
    items.forEach((it) => {
      const lineColor =
        typeof it.color === 'string' && it.color.trim() !== '' ? it.color.trim() : defaultLineColor;
      const item = this.el.querySelector(`.grid-stack-item[gs-id="${it.id}"]`);
      const body = item && item.querySelector('.grid-widget-body');
      if (!body) return;
      const wrap = body.querySelector('.kpi-wrap');
      if (!wrap) return;

      let visual = wrap.querySelector('.kpi-visual');
      if (!visual) {
        visual = document.createElement('div');
        visual.className = 'kpi-visual';
        wrap.appendChild(visual);
      }

      const type = (it.type || 'sparkline').toLowerCase();
      this._sparkTypes[it.id] = type;

      const ensureClass = (mode) => {
        visual.className = `kpi-visual ${mode === 'progress' ? 'kpi-progress' : 'kpi-spark'}`;
        if (mode === 'progress') {
          visual.style.marginTop = '4px';
          visual.style.height = '20px';
          visual.style.width = '100%';
          visual.style.marginLeft = '0';
          visual.style.marginRight = '0';
          visual.style.marginBottom = '0';
        } else {
          visual.style.marginTop = 'auto';
          visual.style.height = '40px';
          visual.style.width = '100%';
          visual.style.marginLeft = '0';
          visual.style.marginRight = '0';
          visual.style.marginBottom = '0';
        }
        visual.dataset.visualType = mode;
        visual.dataset.echartsReady = '0';
      };

      ensureClass(type);

      const render = () => {
        let chart = this._sparklines[it.id];
        const initTheme = isDarkMode ? 'dark' : undefined;
       if (!chart) {
         if (visual.clientWidth === 0 || visual.clientHeight === 0) {
           if (this._sparkTimers && this._sparkTimers[it.id]) clearTimeout(this._sparkTimers[it.id]);
           if (this._sparkTimers) {
             this._sparkTimers[it.id] = setTimeout(render, 80);
           }
           return;
         }
         chart = echarts.init(visual, initTheme, withChartOpts({ height: type === 'progress' ? 20 : 40 }));
         this._sparklines[it.id] = chart;
       }
       if (this._sparkTimers && this._sparkTimers[it.id]) delete this._sparkTimers[it.id];

        if (type === 'progress') {
          const currentNum = Number.isFinite(Number(it.current)) ? Math.max(Number(it.current), 0) : 0;
          const rawTarget = Number(isFinite(Number(it.target)) ? Number(it.target) : null);
          const targetNum = Number.isFinite(rawTarget) ? Math.max(rawTarget, 0) : null;
          const axisMax = Math.max(targetNum ?? 0, currentNum, 1);
          const baseValue = targetNum == null || targetNum === 0 ? axisMax : targetNum;
          const ratio = Number.isFinite(Number(it.ratio)) ? Number(it.ratio) : (targetNum && targetNum !== 0 ? currentNum / targetNum : null);
          const invertGoal = !!it.invert;
          let progressColor;
          if (ratio == null) {
            progressColor = lineColor;
          } else if (invertGoal) {
            progressColor = ratio <= 1 ? lineColor : '#ef4444';
          } else {
            progressColor = ratio >= 1 ? '#22c55e' : lineColor;
          }
          const background = isDarkMode ? '#1f2937' : '#E5E7EB';
          chart.setOption({
            backgroundColor: 'transparent',
            grid: { top: 0, bottom: 0, left: 0, right: 0, containLabel: false },
            xAxis: { type: 'value', show: false, min: 0, max: axisMax },
            yAxis: { type: 'category', show: false, data: [''] },
            series: [
              { type: 'bar', data: [baseValue], barWidth: 10, silent: true, itemStyle: { color: background, borderRadius: 5 }, animation: false, barGap: '-100%', barCategoryGap: '60%' },
              { type: 'bar', data: [currentNum], barWidth: 10, itemStyle: { color: progressColor, borderRadius: 5 }, animation: false, z: 3 }
            ]
          }, true);
        } else {
          chart.setOption({
            backgroundColor: 'transparent',
            grid: { top: 0, bottom: 0, left: 0, right: 0 },
            xAxis: { type: 'time', show: false },
            yAxis: { type: 'value', show: false },
            tooltip: { show: false },
            series: [{
              type: 'line',
              data: Array.isArray(it.data) ? it.data : [],
              smooth: true,
              showSymbol: false,
              lineStyle: { width: 1, color: lineColor },
              areaStyle: { color: lineColor, opacity: 0.08 },
            }],
            animation: false
          }, true);
        }
       try {
         chart.off('finished');
         chart.on('finished', () => {
           try { visual.dataset.echartsReady = '1'; this._scheduleReadyMark(); } catch (_) {}
         });
       } catch (_) {}
       chart.resize();

        if (!this._sparkResize) {
          this._sparkResize = () => {
            Object.values(this._sparklines || {}).forEach((c) => {
              if (c && !c.isDisposed()) {
                c.resize();
              }
            });
          };
          window.addEventListener('resize', this._sparkResize);
        }
      };

      if (this._sparkTimers && this._sparkTimers[it.id]) clearTimeout(this._sparkTimers[it.id]);
      if (!this._sparkTimers) this._sparkTimers = {};
      this._sparkTimers[it.id] = setTimeout(render, 0);
    });
    this._seen.kpi_visual = true; this._scheduleReadyMark();
    this._lastKpiVisuals = this._deepClone(items);
  },
});

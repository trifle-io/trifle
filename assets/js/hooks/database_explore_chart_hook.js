export const registerDatabaseExploreChartHook = (Hooks, deps = {}) => {
  const { echarts, withChartOpts, formatCompactNumber, chartFontFamily } = deps;
Hooks.DatabaseExploreChart = {
  _resolveTheme() {
    return document.documentElement.classList.contains('dark') ? 'dark' : 'default';
  },

  _normalizeColors(colors) {
    if (Array.isArray(colors)) return colors;
    if (typeof colors === 'string') {
      try { return JSON.parse(colors); } catch (_) { return []; }
    }
    return [];
  },

  _parseJson(value, fallback) {
    try {
      return value ? JSON.parse(value) : fallback;
    } catch (_) {
      return fallback;
    }
  },

  _bindThemeListener() {
    if (this._themeListenerBound) return;
    this._themeListenerBound = true;
    this._onThemeChanged = () => this._handleThemeChanged();
    window.addEventListener('trifle:theme-changed', this._onThemeChanged);
  },

  _handleThemeChanged() {
    if (!this.chart || this.chart.isDisposed()) return;
    const themeName = this._resolveTheme();
    if (themeName !== this._currentThemeName && typeof this.chart.setTheme === 'function') {
      try {
        this.chart.setTheme(themeName);
        this._currentThemeName = themeName;
      } catch (_) {}
    }

    this._refreshChartFromDataset();
  },

  _buildOption(data, key, chartType, colors, selectedKeyColor, timezone) {
    const themeName = this._resolveTheme();
    const isDarkMode = themeName === 'dark';
    const colorArray = this._normalizeColors(colors);

    const isStacked = chartType === 'stacked';
    let series;
    if (isStacked) {
      series = (data && data.length > 0) ? data.map((seriesData, index) => ({
        name: seriesData.name,
        type: 'bar',
        stack: 'total',
        data: seriesData.data,
        itemStyle: {
          color: colorArray.length ? colorArray[index % colorArray.length] : undefined
        }
      })) : [];
    } else {
      const seriesColor = selectedKeyColor || colorArray[0];
      series = [{
        name: key || 'Data',
        type: 'bar',
        data: data || [],
        itemStyle: {
          color: seriesColor
        }
      }];
    }

    const textColor = isDarkMode ? '#9CA3AF' : '#6B7280';
    const axisLineColor = isDarkMode ? '#374151' : '#E5E7EB';
    const fontFamily = chartFontFamily || undefined;
    const formatDateTime = (value, options = {}) => {
      try {
        return new Intl.DateTimeFormat('en-CA', {
          timeZone: timezone || undefined,
          year: options.dateOnly ? undefined : 'numeric',
          month: '2-digit',
          day: '2-digit',
          hour: options.dateOnly ? undefined : '2-digit',
          minute: options.dateOnly ? undefined : '2-digit',
          second: options.withSeconds ? '2-digit' : undefined,
          hour12: false
        }).format(new Date(value));
      } catch (_) {
        return echarts.format.formatTime(options.dateOnly ? 'MM-dd' : options.withSeconds ? 'yyyy-MM-dd hh:mm:ss' : 'hh:mm', value, false);
      }
    };
    const timeParts = (value) => {
      try {
        const parts = new Intl.DateTimeFormat('en-US', {
          timeZone: timezone || undefined,
          hour: '2-digit',
          minute: '2-digit',
          hour12: false
        }).formatToParts(new Date(value));
        return {
          hours: Number(parts.find((part) => part.type === 'hour')?.value),
          minutes: Number(parts.find((part) => part.type === 'minute')?.value)
        };
      } catch (_) {
        const date = new Date(value);
        return { hours: date.getHours(), minutes: date.getMinutes() };
      }
    };

    return {
      backgroundColor: 'transparent',
      grid: {
        top: 8,
        bottom: 12,
        left: 32,
        right: 8,
        containLabel: true
      },
      textStyle: {
        color: textColor,
        fontFamily
      },
      tooltip: {
        trigger: 'item',
        axisPointer: {
          type: 'shadow'
        },
        backgroundColor: isDarkMode ? '#1F2937' : '#FFFFFF',
        borderColor: isDarkMode ? '#374151' : '#E5E7EB',
        textStyle: {
          color: isDarkMode ? '#F3F4F6' : '#1F2937',
          fontFamily
        },
        appendToBody: true,
        extraCssText: 'z-index: 9999;',
        formatter: function(params) {
          const dateStr = formatDateTime(params.value[0], { withSeconds: true });
          const value = formatCompactNumber(params.value[1]);
          return `${dateStr}<br/>${params.marker} ${params.seriesName}: ${value}`;
        }
      },
      xAxis: {
        type: 'time',
        axisLine: {
          lineStyle: {
            color: axisLineColor
          }
        },
        axisLabel: {
          color: textColor,
          margin: 6,
          formatter: function(value) {
            const { hours, minutes } = timeParts(value);

            if (hours === 0 && minutes === 0) {
              return formatDateTime(value, { dateOnly: true });
            }
            return formatDateTime(value);
          }
        },
        splitLine: {
          show: false
        }
      },
      yAxis: {
        type: 'value',
        min: 0,
        axisLine: {
          lineStyle: {
            color: axisLineColor
          }
        },
        axisLabel: {
          color: textColor,
          margin: 6,
          formatter: (value) => formatCompactNumber(value)
        },
        splitLine: {
          lineStyle: {
            color: axisLineColor
          }
        }
      },
      series,
      animation: true,
      animationDuration: 300
    };
  },

  _applyOption(option) {
    if (!this.chart || this.chart.isDisposed() || !option) return;
    try {
      this.chart.setOption(option, true);
      this.chart.resize();
    } catch (_) {}
  },

  _refreshChartFromDataset() {
    if (!this.chart || this.chart.isDisposed()) return;
    const data = this._parseJson(this.el.dataset.events, []);
    const key = this.el.dataset.key;
    const chartType = this.el.dataset.chartType;
    const colors = this._parseJson(this.el.dataset.colors, []);
    const selectedKeyColor = this.el.dataset.selectedKeyColor;
    const timezone = this.el.dataset.timezone;

    const option = this._buildOption(data, key, chartType, colors, selectedKeyColor, timezone);
    this._applyOption(option);
  },

  createChart(data, key, timezone, chartType, colors, selectedKeyColor) {
    // Initialize ECharts instance
    const themeName = this._resolveTheme();
    const initTheme = themeName === 'dark' ? 'dark' : undefined;
    const container =
      (this.el && this.el.id === 'timeline-chart' ? this.el : null) ||
      (this.el && this.el.querySelector ? this.el.querySelector('#timeline-chart') : null);
    if (!container) return null;
    container.style.height = '140px';
    container.style.width = '100%';

    // Set theme based on dark mode
    this.chart = echarts.init(container, initTheme, withChartOpts({ height: 140 }));
    this._currentThemeName = themeName;
    this._bindThemeListener();

    // Build and apply the base option
    const option = this._buildOption(data, key, chartType, colors, selectedKeyColor, timezone);
    this._applyOption(option);

    // Handle window resize
    this.resizeHandler = () => {
      if (this.chart && !this.chart.isDisposed()) {
        this.chart.resize();
      }
    };
    window.addEventListener('resize', this.resizeHandler);
    
    // Handle theme changes
    return this.chart;
  },

  mounted() {
    let data = this._parseJson(this.el.dataset.events, []);
    let key = this.el.dataset.key;
    let timezone = this.el.dataset.timezone;
    let chartType = this.el.dataset.chartType;
    let colors = this._parseJson(this.el.dataset.colors, []);
    let selectedKeyColor = this.el.dataset.selectedKeyColor;

    this.currentChartType = chartType;
    this.chart = this.createChart(data, key, timezone, chartType, colors, selectedKeyColor);
  },

  updated() {
    let data = this._parseJson(this.el.dataset.events, []);
    let key = this.el.dataset.key;
    let timezone = this.el.dataset.timezone;
    let chartType = this.el.dataset.chartType;
    let colors = this._parseJson(this.el.dataset.colors, []);
    let selectedKeyColor = this.el.dataset.selectedKeyColor;

    // Check if chart type changed - if so, recreate the entire chart
    if (this.currentChartType !== chartType) {
      if (this.chart && !this.chart.isDisposed()) {
        this.chart.dispose();
      }
      this.chart = this.createChart(data, key, timezone, chartType, colors, selectedKeyColor);
      this.currentChartType = chartType;
      return;
    }

    // Update existing chart with new data
    if (this.chart && !this.chart.isDisposed()) {
      const option = this._buildOption(data, key, chartType, colors, selectedKeyColor, timezone);
      this._applyOption(option);
    }
  },

  destroyed() {
    // Remove resize handler
    if (this.resizeHandler) {
      window.removeEventListener('resize', this.resizeHandler);
    }
    if (this._onThemeChanged) {
      window.removeEventListener('trifle:theme-changed', this._onThemeChanged);
      this._onThemeChanged = null;
      this._themeListenerBound = false;
    }

    // Dispose chart
    if (this.chart && !this.chart.isDisposed()) {
      this.chart.dispose();
    }
  }
}

};

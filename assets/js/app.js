// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"
import Sortable from "sortablejs"

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

let Hooks = {}

Hooks.SmartTimeframeInput = {
  mounted() {
    this.handleEvent("update_smart_timeframe_input", ({value}) => {
      this.el.value = value;
    });
  }
}

Hooks.SmartTimeframeBlur = {
  mounted() {
    this.el.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') {
        // Blur the input after Enter to trigger value update
        setTimeout(() => this.el.blur(), 100);
      }
    });
    
    this.handleEvent("update_timeframe_input", ({value}) => {
      this.el.value = value;
    });
  }
}


Hooks.ProjectTimeline = {
  createChart(data, key, timezone, chartType, colors, selectedKeyColor) {
    // Debug logging for color issues
    console.log('ProjectTimeline colors debug:', {
      chartType,
      passedColors: typeof colors === 'string' ? JSON.parse(colors) : colors,
      selectedKeyColor,
      key
    });
    
    // Calculate dynamic bar width based on container and data points
    const container = document.getElementById('timeline-chart');
    const containerWidth = container.clientWidth || 800; // fallback width
    const dataPointsLength = chartType === 'stacked' ? (data[0]?.data?.length || 0) : data.length;
    const availableWidth = containerWidth * 0.8; // leave some margin
    const maxBarWidth = Math.max(8, Math.min(40, availableWidth / dataPointsLength * 0.7)); // min 8px, max 40px
    
    // Configure series and options based on chart type
    const isStacked = chartType === 'stacked';
    
    // Handle empty data case - ensure we have at least an empty series structure
    let series;
    if (isStacked) {
      series = (data && data.length > 0) ? data : [];
    } else {
      series = [{name: key || 'Data', data: data || []}];
    }
    
    
    // Parse colors from the passed parameter (ensure it's an array)
    const colorArray = typeof colors === 'string' ? JSON.parse(colors) : colors;
    
    // Ensure styled mode is disabled globally for this chart to allow JS colors
    const originalStyledMode = Highcharts.getOptions().chart.styledMode;
    Highcharts.setOptions({
      chart: {
        styledMode: false
      }
    });
    
    const chart = Highcharts.chart('timeline-chart', {
      chart: {
        type: 'column',
        height: '120',
        marginTop: 10,
        spacingTop: 5,
        styledMode: false, // Disable styled mode to use programmatic colors
        style: {
          fontFamily: 'inherit'
        }
      },
      time: {
        useUTC: true,
        timezone: timezone
      },
      title: {
        text: undefined
      },
      xAxis: {
        type: 'datetime',
        dateTimeLabelFormats: {
          millisecond: '%H:%M:%S.%L',
          second: '%H:%M',
          minute: '%H:%M',
          hour: '%H:%M',
          day: '%m-%d %H:%M',
          week: '%m-%d',
          month: '%e. %b',
          year: '%b'
        },
        title: {
          enabled: false
        }
      },
      yAxis: {
        title: {
          enabled: false
        },
        min: 0,
        endOnTick: false,
        maxPadding: 0.05
      },

      tooltip: {
        xDateFormat: '%Y-%m-%d %H:%M:%S'
      },

      legend: {
        enabled: false
      },

      plotOptions: {
        column: {
          pointPadding: 0.2,
          groupPadding: 0.1,
          maxPointWidth: maxBarWidth,
          borderWidth: 0,
          stacking: isStacked ? 'normal' : null
        },
        series: {
          marker: {
            enabled: true,
            radius: 2.5
          }
        }
      },

      colors: (() => {
        // For single series with a selected key color, use that specific color
        if (chartType === 'single' && selectedKeyColor) {
          console.log('Using selected key color:', selectedKeyColor);
          return [selectedKeyColor];
        }
        
        // Use the unified color palette passed from Elixir
        console.log('Using unified color palette:', colorArray);
        return colorArray;
      })(),

      series: series
    });
    
    // Restore original styled mode setting
    if (originalStyledMode !== undefined) {
      Highcharts.setOptions({
        chart: {
          styledMode: originalStyledMode
        }
      });
    }
    
    // Force colors directly on chart elements after creation
    setTimeout(() => {
      // Check if chart and series exist
      if (!chart || !chart.series) {
        return;
      }
      
      if (chartType === 'single' && selectedKeyColor) {
        // For single series, force the selected key color
        chart.series.forEach((series, seriesIndex) => {
          series.update({
            color: selectedKeyColor
          }, false);
        });
        chart.redraw();
      } else if (chartType === 'stacked') {
        // For stacked series, force individual colors
        // Get colors from the chart configuration or use the parsed colorArray
        const chartColors = chart.options.colors || colorArray;
        chart.series.forEach((series, seriesIndex) => {
          const seriesColor = chartColors[seriesIndex % chartColors.length];
          series.update({
            color: seriesColor
          }, false);
        });
        chart.redraw();
      }
    }, 10);

    return chart;
  },


  mounted() {
    let data = JSON.parse(this.el.dataset.events);
    let key = this.el.dataset.key;
    let timezone = this.el.dataset.timezone;
    let chartType = this.el.dataset.chartType;
    let colors = JSON.parse(this.el.dataset.colors);
    let selectedKeyColor = this.el.dataset.selectedKeyColor;

    this.currentChartType = chartType;
    this.chart = this.createChart(data, key, timezone, chartType, colors, selectedKeyColor);
  },

  updated() {
    let data = JSON.parse(this.el.dataset.events);
    let key = this.el.dataset.key;
    let timezone = this.el.dataset.timezone;
    let chartType = this.el.dataset.chartType;
    let colors = JSON.parse(this.el.dataset.colors);
    let selectedKeyColor = this.el.dataset.selectedKeyColor;

    // Check if chart type changed - if so, recreate the entire chart
    if (this.currentChartType !== chartType) {
      this.chart.destroy();
      this.chart = this.createChart(data, key, timezone, chartType, colors, selectedKeyColor);
      this.currentChartType = chartType;
      return;
    }

    // Check if data structure changed significantly (granularity change)
    const currentDataLength = this.chart.series[0]?.data?.length || 0;
    const newDataLength = chartType === 'stacked' ? (data[0]?.data?.length || 0) : data.length;
    const dataLengthChange = Math.abs(newDataLength - currentDataLength) / Math.max(currentDataLength, 1);
    
    // If data points change by more than 30%, recreate the chart for better rendering
    if (dataLengthChange > 0.3) {
      this.chart.destroy();
      this.chart = this.createChart(data, key, timezone, chartType, colors, selectedKeyColor);
      this.currentChartType = chartType;
      return;
    }

    // Same chart type and similar data size - just update data
    const container = document.getElementById('timeline-chart');
    // Force layout reflow before measuring to ensure accurate dimensions
    container.style.display = 'none';
    container.offsetHeight; // Force reflow
    container.style.display = '';
    const containerWidth = container.clientWidth || 800;
    const dataPointsLength = chartType === 'stacked' ? (data[0]?.data?.length || 0) : data.length;
    const availableWidth = containerWidth * 0.8;
    const maxBarWidth = Math.max(8, Math.min(40, availableWidth / dataPointsLength * 0.7));
    
    // Update chart options with new bar width and colors
    const updateColors = chartType === 'single' && selectedKeyColor ? [selectedKeyColor] : colors;
    console.log('Update colors assigned to chart:', updateColors);
    this.chart.update({
      colors: updateColors,
      plotOptions: {
        column: {
          pointPadding: 0.2,
          groupPadding: 0.1,
          maxPointWidth: maxBarWidth,
          borderWidth: 0,
          stacking: chartType === 'stacked' ? 'normal' : null
        }
      }
    });
    
    if (chartType === 'stacked') {
      // Update multiple series for stacked chart
      while (this.chart.series.length > 0) {
        this.chart.series[0].remove(false);
      }
      // Only add series if data exists and is not empty
      if (data && data.length > 0) {
        data.forEach(series => {
          this.chart.addSeries(series, false);
        });
      }
      this.chart.redraw();
    } else {
      // Update single series - only if data exists
      if (this.chart.series[0] && data) {
        this.chart.series[0].setData(data);
      }
    }
  }
}

Hooks.TableHover = {
  mounted() {
    this.initHover();
  },
  
  updated() {
    this.initHover();
  },
  
  initHover() {
    const table = this.el;
    
    // Add hover listeners to data cells (not headers or row headers)
    const dataCells = table.querySelectorAll('td[data-row][data-col]');
    
    dataCells.forEach(cell => {
      cell.addEventListener('mouseenter', (e) => {
        const row = e.target.dataset.row;
        const col = e.target.dataset.col;
        
        // Detect if we're in dark mode
        const isDarkMode = document.documentElement.classList.contains('dark');
        const highlightColor = isDarkMode ? '#334155' : '#f9fafb';
        
        // Highlight current cell's row header with important style
        const rowHeader = table.querySelector(`td[data-row="${row}"]:not([data-col])`);
        if (rowHeader) {
          rowHeader.style.backgroundColor = highlightColor;
          rowHeader.classList.add('table-highlight');
        }
        
        // Highlight current cell's column header
        const colHeader = table.querySelector(`th[data-col="${col}"]`);
        if (colHeader) {
          colHeader.style.backgroundColor = highlightColor;
          colHeader.classList.add('table-highlight');
        }
        
        // Highlight all cells in the same column
        const colCells = table.querySelectorAll(`td[data-col="${col}"]`);
        colCells.forEach(colCell => {
          colCell.style.backgroundColor = highlightColor;
          colCell.classList.add('table-highlight');
        });
        
        // Highlight all cells in the same row
        const rowCells = table.querySelectorAll(`td[data-row="${row}"]`);
        rowCells.forEach(rowCell => {
          rowCell.style.backgroundColor = highlightColor;
          rowCell.classList.add('table-highlight');
        });
      });
      
      cell.addEventListener('mouseleave', (e) => {
        // Remove all highlights
        table.querySelectorAll('.table-highlight').forEach(el => {
          el.style.backgroundColor = '';
          el.classList.remove('table-highlight');
        });
      });
    });
  }
}

Hooks.Sortable = {
  mounted() {
    const group = this.el.dataset.group;
    const handle = this.el.dataset.handle;
    
    this.sortable = Sortable.create(this.el, {
      group: group,
      handle: handle,
      animation: 150,
      ghostClass: 'sortable-ghost',
      chosenClass: 'sortable-chosen',
      dragClass: 'sortable-drag',
      onEnd: (evt) => {
        // Get all item IDs in the new order
        const ids = Array.from(this.el.children).map(child => child.dataset.id);
        
        // Send the new order to LiveView
        this.pushEvent("reorder_transponders", { ids: ids });
      }
    });
  },
  
  destroyed() {
    if (this.sortable) {
      this.sortable.destroy();
    }
  }
}


Hooks.PhantomRows = {
  mounted() {
    this.addPhantomRows();
  },
  
  updated() {
    this.addPhantomRows();
  },
  
  addPhantomRows() {
    // Remove existing phantom rows
    this.clearPhantomRows();
    
    const container = this.el;
    const scrollContainer = container.querySelector('#table-hover-container');
    const table = container.querySelector('table');
    if (!table || !scrollContainer) return;
    
    // Fix border width to match table width
    const borderDiv = scrollContainer.querySelector('.border-t');
    if (borderDiv) {
      const tableWidth = table.scrollWidth;
      borderDiv.style.width = `${tableWidth}px`;
      borderDiv.style.minWidth = '100%';
    }
    
    // Get dimensions
    const scrollRect = scrollContainer.getBoundingClientRect();
    const table2Bottom = scrollContainer.scrollTop + table.offsetHeight;
    const scrollHeight = scrollContainer.scrollHeight;
    const clientHeight = scrollContainer.clientHeight;
    
    // Calculate if we need phantom rows (table + borders is shorter than visible area)
    const borderHeight = borderDiv ? borderDiv.offsetHeight : 0;
    const totalContentHeight = table.offsetHeight + borderHeight;
    
    if (totalContentHeight < clientHeight) {
      const remainingSpace = clientHeight - totalContentHeight;
      this.createPhantomRowsElement(remainingSpace, scrollContainer);
    }
  },
  
  createPhantomRowsElement(height, scrollContainer) {
    const table = scrollContainer.querySelector('table');
    const tableWidth = table ? table.scrollWidth : scrollContainer.scrollWidth;
    
    const phantomContainer = document.createElement('div');
    phantomContainer.className = 'phantom-rows-js';
    
    // Create horizontal stripes background
    const isDark = document.documentElement.classList.contains('dark');
    const stripeColor = isDark ? 'rgb(71 85 105)' : 'rgb(229 231 235)';
    const bgColor = isDark ? 'transparent' : 'transparent';
    
    phantomContainer.style.cssText = `
      height: ${height}px;
      width: ${tableWidth}px;
      min-width: 100%;
      background-image: repeating-linear-gradient(
        to bottom,
        ${bgColor} 0px,
        ${bgColor} 23px,
        ${stripeColor} 23px,
        ${stripeColor} 24px
      );
      pointer-events: none;
    `;
    
    // Append to scroll container, right after the border
    const borderDiv = scrollContainer.querySelector('.border-t');
    if (borderDiv && borderDiv.nextSibling) {
      scrollContainer.insertBefore(phantomContainer, borderDiv.nextSibling);
    } else {
      scrollContainer.appendChild(phantomContainer);
    }
  },
  
  clearPhantomRows() {
    const existing = document.querySelectorAll('.phantom-rows-js');
    existing.forEach(el => el.remove());
  }
}

Hooks.FastTooltip = {
  mounted() {
    this.initTooltips();
  },
  
  updated() {
    this.initTooltips();
  },
  
  initTooltips() {
    // Remove existing tooltips
    document.querySelectorAll('.fast-tooltip').forEach(el => el.remove());
    
    const tooltipElements = this.el.querySelectorAll('[data-tooltip]');
    
    tooltipElements.forEach(el => {
      el.addEventListener('mouseenter', (e) => {
        this.showTooltip(e.target, e.target.dataset.tooltip);
      });
      
      el.addEventListener('mouseleave', (e) => {
        this.hideTooltip();
      });
    });
  },
  
  showTooltip(element, text) {
    // Detect dark mode
    const isDarkMode = document.documentElement.classList.contains('dark');
    const backgroundColor = isDarkMode ? '#0f172a' : '#374151';
    const textColor = isDarkMode ? '#ffffff' : '#ffffff';
    
    // Create tooltip element
    const tooltip = document.createElement('div');
    tooltip.className = 'fast-tooltip';
    tooltip.textContent = text;
    tooltip.style.cssText = `
      position: absolute;
      background: ${backgroundColor};
      color: ${textColor};
      padding: 4px 8px;
      border-radius: 4px;
      font-size: 12px;
      z-index: 1000;
      pointer-events: none;
      white-space: nowrap;
      box-shadow: 0 1px 4px rgba(0,0,0,0.1);
    `;
    
    document.body.appendChild(tooltip);
    
    // Position tooltip
    const rect = element.getBoundingClientRect();
    const tooltipRect = tooltip.getBoundingClientRect();
    
    let left = rect.left + (rect.width / 2) - (tooltipRect.width / 2) + window.scrollX;
    let top = rect.top - tooltipRect.height - 8 + window.scrollY;
    
    // Keep tooltip within viewport
    if (left < 8) left = 8;
    if (left + tooltipRect.width > window.innerWidth - 8) {
      left = window.innerWidth - tooltipRect.width - 8;
    }
    if (top < 8 + window.scrollY) {
      top = rect.bottom + 8 + window.scrollY;
    }
    
    tooltip.style.left = left + 'px';
    tooltip.style.top = top + 'px';
  },
  
  hideTooltip() {
    document.querySelectorAll('.fast-tooltip').forEach(el => el.remove());
  }
}

Hooks.HighchartsDashboard = {
  mounted() {
    console.log('🚀 HighchartsDashboard hook mounted');
    console.log('🚀 Element:', this.el);
    console.log('🚀 Dataset:', this.el.dataset);
    this.initOrWaitForDashboards();
  },
  
  updated() {
    console.log('🔄 HighchartsDashboard hook updated');
    console.log('🔄 Dataset:', this.el.dataset);
    this.initOrWaitForDashboards();
  },
  
  initOrWaitForDashboards() {
    // Check if Dashboards is already loaded
    if (window.dashboardsReady && typeof window.Dashboards !== 'undefined') {
      this.initDashboard();
      return;
    }
    
    // Check if there was an error loading Dashboards
    if (window.dashboardsError) {
      this.showError(window.dashboardsError);
      return;
    }
    
    // Show loading message
    this.showLoading('Loading Dashboards library...');
    
    // Listen for the dashboards-loaded event
    const handleDashboardsLoaded = () => {
      window.removeEventListener('dashboards-loaded', handleDashboardsLoaded);
      if (typeof window.Dashboards !== 'undefined') {
        this.initDashboard();
      } else {
        this.showError('Dashboards library loaded but not available');
      }
    };
    
    window.addEventListener('dashboards-loaded', handleDashboardsLoaded);
    
    // Fallback timeout in case the event doesn't fire
    setTimeout(() => {
      window.removeEventListener('dashboards-loaded', handleDashboardsLoaded);
      if (!window.dashboardsReady) {
        this.showError('Timeout waiting for Dashboards library to load');
      }
    }, 10000); // 10 second timeout
  },
  
  initDashboard() {
    // Check if required libraries are loaded
    if (typeof window.Highcharts === 'undefined') {
      console.error('Highcharts library not loaded');
      this.showError('Highcharts library not loaded');
      return;
    }
    
    if (typeof window.Dashboards === 'undefined') {
      console.error('Dashboards library not loaded');
      this.showError('Dashboards library not available');
      return;
    }
    
    console.log('Both libraries available, initializing dashboard...');
    
    // Get the dashboard payload from data attribute
    const payloadData = this.el.dataset.payload;
    
    if (!payloadData) {
      console.warn('No payload data found for Highcharts Dashboard');
      this.showError('No dashboard configuration found');
      return;
    }
    
    try {
      const dashboardConfig = JSON.parse(payloadData);
      console.log('🔧 Dashboard configuration:', dashboardConfig);
      
      // Check if this is public access - only restriction for edit mode
      const isPublicAccess = this.el.dataset.publicAccess === 'true';
      console.log('🔧 Public access:', isPublicAccess);
      console.log('🔧 All dataset attributes:', this.el.dataset);
      
      // Always enable edit mode unless it's public access
      if (!isPublicAccess) {
        console.log('🔧 Enabling edit mode (not public access)');
        dashboardConfig.editMode = {
          enabled: true,
          contextMenu: {
            enabled: true
          }
        };
        console.log('🔧 Dashboard config with edit mode:', dashboardConfig);
      } else {
        console.log('🔧 Public access - edit mode disabled');
        // Remove any existing editMode from payload for public access
        delete dashboardConfig.editMode;
      }
      
      // Add event handlers to editMode configuration if it exists (regardless of data-edit-mode)
      const hasEditModeInConfig = dashboardConfig.editMode && dashboardConfig.editMode.enabled;
      console.log('🔧 Has edit mode in config:', hasEditModeInConfig);
      if (hasEditModeInConfig) {
        console.log('🔧 Adding event handlers to editMode configuration');
        
        // Store reference to this context for use in callbacks
        const hookContext = this;
        
        if (!dashboardConfig.editMode.events) {
          dashboardConfig.editMode.events = {};
        }
        
        dashboardConfig.editMode.events.componentChanged = function(e) {
          console.log('🎯 Component changed via config events:', e);
          hookContext.handleDashboardChange('componentChanged', e);
        };
        
        dashboardConfig.editMode.events.layoutChanged = function(e) {
          console.log('🎯 Layout changed via config events:', e);
          hookContext.handleDashboardChange('layoutChanged', e);
        };
        
        // Also try different callback patterns
        dashboardConfig.editMode.componentChanged = function(e) {
          console.log('🎯 Component changed via config callback:', e);
          hookContext.handleDashboardChange('componentChanged', e);
        };
        
        dashboardConfig.editMode.layoutChanged = function(e) {
          console.log('🎯 Layout changed via config callback:', e);
          hookContext.handleDashboardChange('layoutChanged', e);
        };
        
        console.log('🔧 Event handlers added to editMode config:', dashboardConfig.editMode);
      }
      
      // Check if the config uses renderTo with specific cell IDs
      if (dashboardConfig.components) {
        console.log('Components renderTo values:', dashboardConfig.components.map(c => c.renderTo));
      }
      
      // Clear any existing dashboard (but don't clear DOM)
      if (this.dashboard) {
        try {
          if (typeof this.dashboard.destroy === 'function') {
            this.dashboard.destroy();
          }
        } catch (e) {
          console.warn('Error destroying existing dashboard:', e);
        }
        this.dashboard = null;
      }
      
      // Create required HTML cell elements based on component renderTo values
      this.createRequiredCells(dashboardConfig);
      
      window.Highcharts.setOptions({ chart: { styledMode: true } });
      // Initialize Highcharts Dashboard with the payload
      // Use the third parameter (true) for responsive behavior as mentioned by user
      window.Dashboards.board(this.el, dashboardConfig, true).then(board => {
        console.log('🔧 Dashboard initialized successfully:', board);
        this.dashboard = board;
        
        // Setup edit mode callbacks if edit mode is enabled
        const hasEditModeInConfig = dashboardConfig.editMode && dashboardConfig.editMode.enabled;
        console.log('🔧 Edit mode in config:', hasEditModeInConfig);
        
        if (hasEditModeInConfig && board.editMode) {
          console.log('🔧 Setting up edit mode callbacks with Dashboards.addEvent...');
          
          const editMode = board.editMode;
          const addEvent = window.Dashboards.addEvent;
          
          console.log('🔧 EditMode object:', editMode);
          console.log('🔧 Dashboards.addEvent available:', !!addEvent);
          
          if (addEvent) {
            // Component changed callback
            addEvent(editMode, 'componentChanged', e => {
              console.log('🎯 Component Changed:', e);
              this.handleDashboardChange('componentChanged', e);
            });
            
            // Component changes discarded callback  
            addEvent(editMode, 'componentChangesDiscarded', e => {
              console.log('🎯 Component Changes Discarded:', e);
              this.handleDashboardChange('componentChangesDiscarded', e);
            });
            
            // Layout changed callback
            addEvent(editMode, 'layoutChanged', e => {
              console.log('🎯 Layout Changed:', e);
              this.handleDashboardChange('layoutChanged', e);
            });
            
            // Add more event types to see if any of them fire
            const additionalEvents = [
              'activate', 'deactivate', 'toggle', 'editModeToggle', 
              'change', 'beforeEdit', 'afterEdit', 'edit', 'save',
              'componentUpdate', 'layoutUpdate', 'boardChanged'
            ];
            
            additionalEvents.forEach(eventType => {
              try {
                addEvent(editMode, eventType, e => {
                  console.log(`🎯 EditMode event "${eventType}":`, e);
                  this.handleDashboardChange(eventType, e);
                });
              } catch (error) {
                // Silently ignore errors for non-existent events
              }
            });
            
            // Also try attaching to the board itself
            try {
              addEvent(board, 'componentChanged', e => {
                console.log('🎯 Board Component Changed:', e);
                this.handleDashboardChange('board-componentChanged', e);
              });
              
              addEvent(board, 'layoutChanged', e => {
                console.log('🎯 Board Layout Changed:', e);
                this.handleDashboardChange('board-layoutChanged', e);
              });
            } catch (error) {
              console.log('🔧 Board events not available:', error.message);
            }
            
            // Monitor editMode.active status changes and detect config changes during active editing
            let lastActiveState = editMode.active;
            let lastConfigSnapshot = null;
            let configMonitorInterval = null;
            
            const activeStateMonitor = setInterval(() => {
              if (editMode.active !== lastActiveState) {
                lastActiveState = editMode.active;
                
                if (editMode.active) {
                  // Start monitoring config changes while edit mode is active
                  lastConfigSnapshot = JSON.stringify(board.options);
                  
                  configMonitorInterval = setInterval(() => {
                    try {
                      const currentConfigSnapshot = JSON.stringify(board.options);
                      if (currentConfigSnapshot !== lastConfigSnapshot) {
                        this.handleDashboardChange('configChanged-while-active', {
                          type: 'configChanged-while-active',
                          previousConfig: lastConfigSnapshot,
                          currentConfig: currentConfigSnapshot
                        });
                        
                        lastConfigSnapshot = currentConfigSnapshot;
                      }
                    } catch (error) {
                      console.error('Error monitoring config during active edit:', error);
                    }
                  }, 250); // Check every 250ms while editing
                  
                } else {
                  // Stop monitoring config changes and save dashboard
                  if (configMonitorInterval) {
                    clearInterval(configMonitorInterval);
                    configMonitorInterval = null;
                  }
                  
                  // Always trigger save when edit mode exits
                  this.handleDashboardChange('editModeExit', {
                    type: 'editModeExit',
                    reason: 'edit_mode_deactivated'
                  });
                }
              }
            }, 500);
            
            // Clean up monitor after 30 seconds
            setTimeout(() => clearInterval(activeStateMonitor), 30000);
            
          } else {
            console.error('Dashboards.addEvent not available');
          }
        }
      }).catch(error => {
        console.error('Error initializing dashboard:', error);
        this.showError('Failed to initialize dashboard: ' + error.message);
      });
      
    } catch (error) {
      console.error('Error initializing Highcharts Dashboard:', error);
      this.showError('Failed to load dashboard: ' + error.message);
    }
  },
  
  createRequiredCells(dashboardConfig) {
    // Clear the container first
    this.el.innerHTML = '';
    
    // Extract unique cell IDs from components
    const cellIds = [];
    if (dashboardConfig.components) {
      dashboardConfig.components.forEach(component => {
        if (component.renderTo && !cellIds.includes(component.renderTo)) {
          cellIds.push(component.renderTo);
        }
      });
    }
    
    console.log('Creating cells:', cellIds);
    
    // Create div elements for each required cell
    cellIds.forEach(cellId => {
      const cellDiv = document.createElement('div');
      cellDiv.id = cellId;
      // Remove temporary styling - let dashboard handle its own styling
      this.el.appendChild(cellDiv);
    });
  },
  
  clearDashboard() {
    if (this.dashboard) {
      try {
        // Check if destroy method exists before calling it
        if (typeof this.dashboard.destroy === 'function') {
          this.dashboard.destroy();
        } else {
          console.warn('Dashboard destroy method not available');
        }
      } catch (e) {
        console.warn('Error destroying existing dashboard:', e);
      }
      this.dashboard = null;
    }
    // Don't clear the container - let Highcharts Dashboard manage the DOM structure
    // this.el.innerHTML = '';
  },
  
  showLoading(message) {
    this.el.innerHTML = `
      <div class="p-4 bg-blue-50 dark:bg-blue-900/20 border border-blue-200 dark:border-blue-800 rounded-lg">
        <div class="text-blue-700 dark:text-blue-400 font-medium">Loading Dashboard</div>
        <div class="text-blue-600 dark:text-blue-300 text-sm mt-1">${message}</div>
        <div class="mt-2">
          <div class="animate-spin rounded-full h-4 w-4 border-b-2 border-blue-600"></div>
        </div>
      </div>
    `;
  },
  
  showError(message) {
    this.el.innerHTML = `
      <div class="p-4 bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 rounded-lg">
        <div class="text-red-700 dark:text-red-400 font-medium">Dashboard Error</div>
        <div class="text-red-600 dark:text-red-300 text-sm mt-1">${message}</div>
        <div class="text-red-500 dark:text-red-400 text-xs mt-2">
          Check browser console for more details.
        </div>
      </div>
    `;
  },
  
  
  handleDashboardChange(changeType, event) {
    try {
      const completePayload = this.getCompleteDashboardPayload();
      
      if (completePayload) {
        this.pushEvent('dashboard_changed', {
          change_type: changeType,
          payload: completePayload,
          event_details: {
            type: event.type,
            target: event.target?.id || null
          }
        });
        
        if (changeType === 'editModeExit') {
          console.log('Dashboard changes saved');
        }
      }
    } catch (error) {
      console.error('Error handling dashboard change:', error);
    }
  },
  
  getCompleteDashboardPayload() {
    try {
      if (!this.dashboard) {
        return null;
      }
      
      // Try to get the complete configuration from the dashboard
      let config = null;
      
      if (typeof this.dashboard.toJSON === 'function') {
        config = this.dashboard.toJSON();
      } else if (typeof this.dashboard.getOptions === 'function') {
        config = this.dashboard.getOptions();
      } else if (this.dashboard.options) {
        config = JSON.parse(JSON.stringify(this.dashboard.options));
      } else {
        return null;
      }
      
      // Validate config before returning
      if (!config || typeof config !== 'object' || Object.keys(config).length === 0) {
        return null;
      }
      
      return config;
      
    } catch (error) {
      console.error('Error extracting dashboard payload:', error);
      return null;
    }
  },
  
  destroyed() {
    // Clean up polling interval
    if (this.changeDetectionInterval) {
      clearInterval(this.changeDetectionInterval);
      console.log('🔧 Polling change detection stopped');
    }
    
    this.clearDashboard();
  }
}

let liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: Hooks,
  dom: {
    onBeforeElUpdated(from, to) {
      if (from._x_dataStack) {
        window.Alpine.clone(from, to)
      }
    },
  }
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

window.addEventListener("phx:copy", (event) => {
  let text = event.target.textContent;
  navigator.clipboard.writeText(text).then(() => {
    // Copy completed
  })
})

// Theme Management
class ThemeManager {
  constructor() {
    this.init();
  }

  init() {
    // Apply theme on page load
    this.applyTheme();
    
    // Listen for theme changes from LiveView
    window.addEventListener("phx:theme-changed", (event) => {
      this.applyTheme(event.detail.theme);
    });

    // Listen for system theme changes
    if (window.matchMedia) {
      const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)');
      mediaQuery.addEventListener('change', () => {
        // Only apply system theme change if user has system preference
        const currentTheme = document.body.getAttribute('data-theme') || 'system';
        if (currentTheme === 'system') {
          this.applyTheme();
        }
      });
    }
  }

  shouldUseDarkTheme(themePreference = null) {
    const body = document.body;
    const currentTheme = themePreference || body.getAttribute('data-theme') || 'system';
    
    let shouldUseDark;
    switch (currentTheme) {
      case 'dark':
        shouldUseDark = true;
        break;
      case 'light':
        shouldUseDark = false;
        break;
      case 'system':
      default:
        // Check system preference
        shouldUseDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
        break;
    }
    
    return shouldUseDark;
  }

  applyTheme(themePreference = null) {
    const body = document.body;
    const currentTheme = themePreference || body.getAttribute('data-theme') || 'system';
    const shouldUseDark = this.shouldUseDarkTheme(themePreference);
    
    // Update data-theme attribute if preference was provided
    if (themePreference) {
      body.setAttribute('data-theme', themePreference);
    }
    
    // Remove existing theme classes (both our dark class and Highcharts classes)
    body.classList.remove('dark', 'highcharts-light', 'highcharts-dark');
    document.documentElement.classList.remove('dark');
    
    // Apply theme classes based on user preference
    switch (currentTheme) {
      case 'dark':
        body.classList.add('dark', 'highcharts-dark');
        document.documentElement.classList.add('dark');
        break;
      case 'light':
        body.classList.add('highcharts-light');
        break;
      case 'system':
      default:
        // No Highcharts override classes - let adaptive theme use system preference
        if (shouldUseDark) {
          body.classList.add('dark');
          document.documentElement.classList.add('dark');
        }
        break;
    }

    // No need to manually update Highcharts - adaptive theme handles it with CSS classes
  }

}

// Initialize theme manager when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
  window.themeManager = new ThemeManager();
});


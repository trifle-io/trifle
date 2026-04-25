export const registerSortableDashboardHooks = (Hooks, deps = {}) => {
  const { Sortable, echarts, withChartOpts } = deps;
Hooks.Sortable = {
  mounted() {
    const group = this.el.dataset.group;
    const handle = this.el.dataset.handle;
    const eventName = this.el.dataset.event || "reorder_transponders";
    
    const groupName = group || 'default';
    // Restrict cross-type moves: only allow within same named group
    const groupOpt = { name: groupName, pull: [groupName], put: [groupName] };

    this.lastTo = null;
    this.lastHeader = null;

    this.sortable = Sortable.create(this.el, {
      group: groupOpt,
      handle: handle,
      draggable: '[data-id]',
      animation: 150,
      ghostClass: 'sortable-ghost',
      chosenClass: 'sortable-chosen',
      dragClass: 'sortable-drag',
      emptyInsertThreshold: 5,
      onMove: (evt, originalEvent) => {
        try {
          // Highlight drop container
          if (this.lastTo && this.lastTo !== evt.to) {
            this.lastTo.style.backgroundColor = '';
          }
          evt.to.style.backgroundColor = 'rgba(20,184,166,0.08)';
          this.lastTo = evt.to;

          // Highlight corresponding group header if present
          const pid = evt.to.dataset.parentId;
          if (pid) {
            const header = document.querySelector(`[data-group-header="${pid}"]`);
            if (this.lastHeader && this.lastHeader !== header) {
              this.lastHeader.style.backgroundColor = '';
            }
            if (header) {
              header.style.backgroundColor = 'rgba(20,184,166,0.10)';
              this.lastHeader = header;
            }
          }
        } catch (_) {}
      },
      onEnd: (evt) => {
        const parentId = evt.to.dataset.parentId || null;
        const fromParentId = evt.from.dataset.parentId || null;
        const movedId = evt.item && evt.item.dataset ? evt.item.dataset.id : null;
        const movedType = evt.item && evt.item.dataset ? evt.item.dataset.type : null;

        if (eventName === 'reorder_transponders') {
          const ids = Array.from(evt.to.children).map(child => child.dataset.id).filter(Boolean);
          this.pushEvent(eventName, { ids });
        } else {
          // Mixed nodes payload with type info
          const items = Array.from(evt.to.children)
            .map(child => (child.dataset && child.dataset.id) ? { id: child.dataset.id, type: child.dataset.type } : null)
            .filter(Boolean);
          const fromItems = Array.from(evt.from.children)
            .map(child => (child.dataset && child.dataset.id) ? { id: child.dataset.id, type: child.dataset.type } : null)
            .filter(Boolean);
          this.pushEvent(eventName, { items, parent_id: parentId, from_items: fromItems, from_parent_id: fromParentId, moved_id: movedId, moved_type: movedType });
        }

        // Clear highlights
        try {
          if (this.lastTo) this.lastTo.style.backgroundColor = '';
          if (this.lastHeader) this.lastHeader.style.backgroundColor = '';
          this.lastTo = null;
          this.lastHeader = null;
        } catch (_) {}
      }
    });
  },
  
  destroyed() {
    if (this.sortable) {
      this.sortable.destroy();
    }
  }
}

// Collapsible Dashboard Groups: sync collapsed state to localStorage
Hooks.DashboardGroupsCollapse = {
  mounted() {
    const dbId = this.el.dataset.dbId || 'default';
    const key = `dashboard_group_collapsed_${dbId}`;
    let map = {};
    try { map = JSON.parse(localStorage.getItem(key) || '{}'); } catch (_) { map = {}; }
    const ids = Object.keys(map).filter(id => map[id]);
    try { this.pushEvent('set_collapsed_groups', { ids }); } catch (_) {}
    this.handleEvent('save_collapsed_groups', ({ ids }) => {
      const store = {};
      (ids || []).forEach(id => { store[id] = true; });
      try { localStorage.setItem(key, JSON.stringify(store)); } catch (_) {}
    });
  }
}

Hooks.HomeSparkline = {
  mounted() {
    this.renderSparkline();
  },
  updated() {
    this.renderSparkline(true);
  },
  destroyed() {
    this.dispose();
  },
  disconnected() {
    this.dispose();
  },
  renderSparkline(force) {
    let series;
    try {
      series = JSON.parse(this.el.dataset.series || '[]');
    } catch (_) {
      series = [];
    }
    if (!Array.isArray(series)) series = [];

    if (!this.chart || force) {
      this.dispose();
      const height = this.el.clientHeight || 64;
      const theme = document.documentElement.classList.contains('dark') ? 'dark' : undefined;
      this.chart = echarts.init(this.el, theme, withChartOpts({ height }));
    }

    const lineColor = 'oklch(70.4% 0.14 182.503)';

    this.chart.setOption(
      {
        backgroundColor: 'transparent',
        grid: { top: 2, bottom: 2, left: 0, right: 0, containLabel: false },
        xAxis: { type: 'time', show: false },
        yAxis: {
          type: 'value',
          show: false,
          min: 0,
          max: (value) => (value.max === 0 ? 1 : value.max)
        },
        tooltip: { show: false },
        series: [
          {
            type: 'line',
            data: series,
            smooth: true,
            showSymbol: false,
            lineStyle: { width: 2, color: lineColor },
            areaStyle: { color: lineColor, opacity: 0.0 },
            animation: false
          }
        ],
        animation: false
      },
      true
    );

    try {
      this.chart.resize();
    } catch (_) {}
  },
  dispose() {
    if (this.chart) {
      try {
        this.chart.dispose();
      } catch (_) {}
      this.chart = null;
    }
  }
}

// Generic file download handler via pushEvent

};

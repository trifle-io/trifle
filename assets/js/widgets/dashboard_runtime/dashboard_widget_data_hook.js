export const registerDashboardWidgetDataHook = (Hooks, deps) => {
  const { parseJsonSafe, findDashboardGridHook } = deps;
Hooks.DashboardWidgetData = {
  mounted() {
    this.widgetId = this.el.dataset.widgetId || '';
    this.widgetType = (this.el.dataset.widgetType || '').toLowerCase() || 'kpi';
    this.widgetPayload = parseJsonSafe(this.el.dataset.widgetPayload || '');
    this._retryTimer = null;
    this._lastKey = null;
    this._registeredType = null;
    this.register();
  },

  updated() {
    this.register();
  },

  reconnected() {
    // Force re-register so widgets with unchanged payloads (text/list) render after reconnects
    this._lastKey = null;
    this.register();
  },

  destroyed() {
    if (this._retryTimer) {
      clearTimeout(this._retryTimer);
      this._retryTimer = null;
    }
    const gridHook = findDashboardGridHook(this.el);
    if (gridHook && this.widgetId) {
      const cleanupType = this._registeredType || this.widgetType || null;
      gridHook.unregisterWidget(cleanupType, this.widgetId);
    }
  },

  register() {
    const payloadEnvelope = parseJsonSafe(this.el.dataset.widgetPayload || '');
    const rawType = (this.el.dataset.widgetType || '').toLowerCase();
    const envelopeType =
      payloadEnvelope && typeof payloadEnvelope.type === 'string'
        ? payloadEnvelope.type.toLowerCase()
        : '';
    const nextType = envelopeType || rawType || this.widgetType || 'kpi';
    if (nextType !== this.widgetType) {
      this.widgetType = nextType;
    }

    const titleData =
      payloadEnvelope && typeof payloadEnvelope.title === 'string'
        ? payloadEnvelope.title
        : this.el.dataset.title || '';
    const key = [this.widgetType, this.widgetId, this.el.dataset.widgetPayload || '', titleData].join('||');
    if (key === this._lastKey) return;
    this._lastKey = key;

    if (this._retryTimer) {
      clearTimeout(this._retryTimer);
      this._retryTimer = null;
    }

    const attempt = () => {
      const gridHook = findDashboardGridHook(this.el);
      if (!gridHook) {
        this._retryTimer = setTimeout(attempt, 20);
        return;
      }

      const envelope =
        parseJsonSafe(this.el.dataset.widgetPayload || '') ||
        payloadEnvelope ||
        null;

      const type =
        (envelope && typeof envelope.type === 'string' ? envelope.type.toLowerCase() : '') ||
        this.widgetType;

      const id =
        (envelope && envelope.id != null ? String(envelope.id) : '') ||
        this.widgetId;

      let payload =
        envelope && Object.prototype.hasOwnProperty.call(envelope, 'payload')
          ? envelope.payload
          : null;

      this.widgetId = id;
      this.widgetType = type;

      if (this._registeredType && this._registeredType !== type && id) {
        gridHook.unregisterWidget(this._registeredType, id);
        this._registeredType = null;
      }

      // Backward compatibility path while old markup exists during rollout.
      if (!envelope) {
        if (type === 'kpi') {
          const value = parseJsonSafe(this.el.dataset.kpiValues || '');
          if (value && value.id == null) value.id = id;
          const visual = parseJsonSafe(this.el.dataset.kpiVisual || '');
          if (visual && visual.id == null) visual.id = id;
          payload = { value, visual };
        } else if (type === 'timeseries') {
          const data = parseJsonSafe(this.el.dataset.timeseries || '');
          if (data && data.id == null) data.id = id;
          payload = data;
        } else if (type === 'category') {
          const data = parseJsonSafe(this.el.dataset.category || '');
          if (data && data.id == null) data.id = id;
          payload = data;
        } else if (type === 'table') {
          const data = parseJsonSafe(this.el.dataset.table || '');
          if (data && data.id == null) data.id = id;
          payload = data;
        } else if (type === 'text') {
          const data = parseJsonSafe(this.el.dataset.text || '');
          if (data && data.id == null) data.id = id;
          payload = data;
        } else if (type === 'list') {
          const data = parseJsonSafe(this.el.dataset.list || '');
          if (data && data.id == null) data.id = id;
          payload = data;
        } else if (type === 'distribution' || type === 'heatmap') {
          const data = parseJsonSafe(this.el.dataset.distribution || '');
          if (data && data.id == null) data.id = id;
          if (data && !data.widget_type) data.widget_type = type;
          payload = data;
        }
      }

      gridHook.registerWidget(type || null, id, payload);
      this._registeredType = type || null;
      this.updateWidgetTitle(titleData, type);
    };

    attempt();
  },

  updateWidgetTitle(title, type) {
    if (!this.widgetId) return;
    if (!title || type === 'text') return;
    const trimmed = title.trim();
    if (trimmed === '') return;
    const gridHook = findDashboardGridHook(this.el);
    const root = gridHook && gridHook.el ? gridHook.el : document;
    const item =
      root && root.querySelector
        ? root.querySelector(`.grid-stack-item[gs-id="${this.widgetId}"]`)
        : null;
    if (!item) return;
    const titleEl = item.querySelector('.grid-widget-title');
    if (!titleEl) return;
    titleEl.textContent = trimmed;
    titleEl.dataset.originalTitle = trimmed;
    const content = item.querySelector('.grid-stack-item-content');
    if (content) {
      content.dataset.widgetTitle = trimmed;
    }
  }
};
};

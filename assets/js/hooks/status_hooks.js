export const registerStatusHooks = (Hooks, deps = {}) => {
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
    
    const tooltipElements = this.el.querySelectorAll('[data-tooltip], [data-fast-tooltip]');
    
    tooltipElements.forEach(el => {
      if (el.dataset.fastTooltipBound === 'true') return;
      el.dataset.fastTooltipBound = 'true';

      el.addEventListener('mouseenter', (e) => {
        const text = e.currentTarget.dataset.tooltip;
        if (!text) return;
        this.showTooltip(e.currentTarget, text);
      });

      el.addEventListener('focus', (e) => {
        const text = e.currentTarget.dataset.tooltip;
        if (!text) return;
        this.showTooltip(e.currentTarget, text);
      });
      
      el.addEventListener('mouseleave', () => {
        this.hideTooltip();
      });

      el.addEventListener('blur', () => {
        this.hideTooltip();
      });
    });
  },
  
  showTooltip(element, text) {
    // Detect dark mode
    const isDarkMode = document.documentElement.classList.contains('dark');
    const backgroundColor = isDarkMode ? '#0f172a' : '#374151';
    const textColor = isDarkMode ? '#ffffff' : '#ffffff';
    const placement = String(element.dataset.tooltipPlacement || 'top').toLowerCase();
    const gap = 8;
    const viewportLeft = window.scrollX + 8;
    const viewportRight = window.scrollX + window.innerWidth - 8;
    const viewportTop = window.scrollY + 8;
    const viewportBottom = window.scrollY + window.innerHeight - 8;
    
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

    let left;
    let top;

    if (placement === 'right') {
      left = rect.right + gap + window.scrollX;
      top = rect.top + (rect.height / 2) - (tooltipRect.height / 2) + window.scrollY;

      if (left + tooltipRect.width > viewportRight) {
        left = rect.left - tooltipRect.width - gap + window.scrollX;
      }

      if (left < viewportLeft) {
        left = viewportLeft;
      }

      if (top < viewportTop) {
        top = viewportTop;
      }

      if (top + tooltipRect.height > viewportBottom) {
        top = viewportBottom - tooltipRect.height;
      }
    } else {
      left = rect.left + (rect.width / 2) - (tooltipRect.width / 2) + window.scrollX;
      top = rect.top - tooltipRect.height - gap + window.scrollY;

      // Keep tooltip within viewport
      if (left < viewportLeft) left = viewportLeft;
      if (left + tooltipRect.width > viewportRight) {
        left = viewportRight - tooltipRect.width;
      }
      if (top < viewportTop) {
        top = rect.bottom + gap + window.scrollY;
      }

      if (top + tooltipRect.height > viewportBottom) {
        top = viewportBottom - tooltipRect.height;
      }
    }
    
    tooltip.style.left = left + 'px';
    tooltip.style.top = top + 'px';
  },
  
  hideTooltip() {
    document.querySelectorAll('.fast-tooltip').forEach(el => el.remove());
  }
}

Hooks.ChatContextRefresh = {
  mounted() {
    this.setupRefresh();
  },

  destroyed() {
    this.teardownRefresh();
  },

  setupRefresh() {
    if (this.el.dataset.chatContextRefresh !== "true" || this._chatContextRefreshBound) return;

    this._chatContextRefreshBound = true;
    this._chatContextRefreshTimeout = null;
    this._handleChatContextRefreshNavigate = () => {
      if (this._chatContextRefreshTimeout) {
        clearTimeout(this._chatContextRefreshTimeout);
      }

      this._chatContextRefreshTimeout = setTimeout(() => {
        this.pushEvent("refresh_page_context", {
          path: window.location?.pathname || null
        });
      }, 50);
    };

    window.addEventListener("phx:page-loading-stop", this._handleChatContextRefreshNavigate);
    window.addEventListener("phx:navigate", this._handleChatContextRefreshNavigate);
  },

  teardownRefresh() {
    if (this._chatContextRefreshTimeout) {
      clearTimeout(this._chatContextRefreshTimeout);
      this._chatContextRefreshTimeout = null;
    }

    if (!this._chatContextRefreshBound || !this._handleChatContextRefreshNavigate) return;

    window.removeEventListener("phx:page-loading-stop", this._handleChatContextRefreshNavigate);
    window.removeEventListener("phx:navigate", this._handleChatContextRefreshNavigate);
    this._handleChatContextRefreshNavigate = null;
    this._chatContextRefreshBound = false;
  }
}

Hooks.FlashAutoDismiss = {
  mounted() {
    this.flashKey = this.el.dataset.flashKey;
    this.clearQueued = false;

    this.handleClearFlash = () => {
      this.queueClear();
    };

    this.el.addEventListener("trifle:clear-flash", this.handleClearFlash);

    this.timeoutId = window.setTimeout(() => {
      this.el.dispatchEvent(new CustomEvent("trifle:flash-hide"));
      this.queueClear();
    }, 5000);
  },

  queueClear() {
    if (this.clearQueued || !this.flashKey) return;

    this.clearQueued = true;
    window.clearTimeout(this.timeoutId);

    this.clearTimeoutId = window.setTimeout(() => {
      this.pushEvent("lv:clear-flash", { key: this.flashKey });
    }, 300);
  },

  destroyed() {
    if (this.timeoutId) {
      window.clearTimeout(this.timeoutId);
    }

    if (this.clearTimeoutId) {
      window.clearTimeout(this.clearTimeoutId);
    }

    if (this.handleClearFlash) {
      this.el.removeEventListener("trifle:clear-flash", this.handleClearFlash);
    }
  }
}

Hooks.SocketStatusDot = {
  mounted() {
    this.connectedClasses = this.parseClasses(this.el.dataset.connectedClasses);
    this.offlineClasses = this.parseClasses(this.el.dataset.offlineClasses);
    this.reconnectingClasses = this.parseClasses(this.el.dataset.reconnectingClasses);
    this.allStatusClasses = [
      ...this.connectedClasses,
      ...this.offlineClasses,
      ...this.reconnectingClasses
    ];

    this.handleOnline = () => this.syncStatus();
    this.handleOffline = () => this.applyStatus("offline");

    window.addEventListener("online", this.handleOnline);
    window.addEventListener("offline", this.handleOffline);

    this.socket = window.liveSocket && typeof window.liveSocket.getSocket === "function"
      ? window.liveSocket.getSocket()
      : null;
    this.socketRefs = [];

    if (this.socket) {
      if (typeof this.socket.onOpen === "function") {
        this.socketRefs.push(this.socket.onOpen(() => this.applyStatus("connected")));
      }

      if (typeof this.socket.onClose === "function") {
        this.socketRefs.push(this.socket.onClose(() => this.syncStatus()));
      }

      if (typeof this.socket.onError === "function") {
        this.socketRefs.push(this.socket.onError(() => this.syncStatus()));
      }
    }

    this.syncStatus();
  },

  updated() {
    this.syncStatus();
  },

  destroyed() {
    if (this.handleOnline) {
      window.removeEventListener("online", this.handleOnline);
    }

    if (this.handleOffline) {
      window.removeEventListener("offline", this.handleOffline);
    }

    if (this.socket && this.socketRefs.length && typeof this.socket.off === "function") {
      this.socket.off(this.socketRefs);
    }
  },

  parseClasses(value) {
    return String(value || "")
      .split(/\s+/)
      .map((name) => name.trim())
      .filter(Boolean);
  },

  syncStatus() {
    if (!navigator.onLine) {
      this.applyStatus("offline");
      return;
    }

    if (window.liveSocket && typeof window.liveSocket.isConnected === "function" && window.liveSocket.isConnected()) {
      this.applyStatus("connected");
      return;
    }

    this.applyStatus("reconnecting");
  },

  applyStatus(status) {
    this.el.classList.remove(...this.allStatusClasses);

    const nextClasses =
      status === "connected"
        ? this.connectedClasses
        : status === "offline"
          ? this.offlineClasses
          : this.reconnectingClasses;

    this.el.classList.add(...nextClasses);
    this.el.dataset.socketStatus = status;
  }
}

};

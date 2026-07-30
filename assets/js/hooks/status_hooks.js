export const registerStatusHooks = (Hooks, deps = {}) => {
  // Fast tooltips are globally delegated: any element carrying [data-tooltip]
  // gets a JS tooltip on hover/focus, wherever it lives (modals, forms,
  // JS-generated content) — no wrapper hook or per-element binding required.
  // Optional [data-tooltip-media] (e.g. "(max-width: 767px)") restricts the
  // tooltip to viewports matching the media query.
  let activeTooltipTarget = null;
  let activeTooltipDescription = null;
  let tooltipSequence = 0;

  const matchesTooltipMedia = (element) => {
    const media = element.dataset.tooltipMedia;
    if (!media || !window.matchMedia) return true;
    return window.matchMedia(media).matches;
  };

  const hideFastTooltip = () => {
    document.querySelectorAll('.fast-tooltip').forEach(el => el.remove());
    if (!activeTooltipDescription) return;

    const { element, tooltipId } = activeTooltipDescription;
    if (element.isConnected) {
      const remainingDescriptions = String(element.getAttribute('aria-describedby') || '')
        .split(/\s+/)
        .filter((id) => id && id !== tooltipId);

      if (remainingDescriptions.length > 0) {
        element.setAttribute('aria-describedby', remainingDescriptions.join(' '));
      } else {
        element.removeAttribute('aria-describedby');
      }
    }

    activeTooltipDescription = null;
  };

  const activateTooltipTarget = (target) => {
    const el = target instanceof Element ? target.closest('[data-tooltip]') : null;
    if (el === activeTooltipTarget && document.querySelector('.fast-tooltip')) return;

    activeTooltipTarget = el;
    hideFastTooltip();

    if (!el) return;
    const text = el.dataset.tooltip;
    if (!text || !matchesTooltipMedia(el)) return;
    showFastTooltip(el, text);
  };

  const clearTooltipTarget = () => {
    activeTooltipTarget = null;
    hideFastTooltip();
  };

  const installFastTooltipDelegation = () => {
    if (window.__fastTooltipDelegated) return;
    window.__fastTooltipDelegated = true;

    document.addEventListener('mouseover', (e) => activateTooltipTarget(e.target));
    document.addEventListener('focusin', (e) => activateTooltipTarget(e.target));
    document.addEventListener('focusout', clearTooltipTarget);
    document.addEventListener('mouseleave', clearTooltipTarget);
    document.addEventListener('pointerdown', clearTooltipTarget);
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') clearTooltipTarget();
    });
    document.addEventListener('phx:page-loading-start', clearTooltipTarget);
    window.addEventListener('scroll', clearTooltipTarget, true);
    window.addEventListener('resize', clearTooltipTarget);
    window.addEventListener('blur', clearTooltipTarget);
  };

  function showFastTooltip(element, text) {
    hideFastTooltip();
    if (!element?.isConnected || !text) return;

    activeTooltipTarget = element;

    // Detect dark mode
    const isDarkMode = document.documentElement.classList.contains('dark');
    const backgroundColor = isDarkMode ? '#0f172a' : '#374151';
    const textColor = isDarkMode ? '#ffffff' : '#ffffff';
    const placement = String(element.dataset.tooltipPlacement || 'top').toLowerCase();
    const gap = 8;
    const viewportLeft = 8;
    const viewportRight = window.innerWidth - 8;
    const viewportTop = 8;
    const viewportBottom = window.innerHeight - 8;

    // Create tooltip element
    const tooltip = document.createElement('div');
    const tooltipId = `fast-tooltip-${++tooltipSequence}`;
    tooltip.id = tooltipId;
    tooltip.setAttribute('role', 'tooltip');
    tooltip.className = 'fast-tooltip';
    tooltip.textContent = text;
    tooltip.style.cssText = `
      position: fixed;
      background: ${backgroundColor};
      color: ${textColor};
      padding: 4px 8px;
      border-radius: 4px;
      font-size: 12px;
      line-height: 1.25;
      max-width: min(20rem, calc(100vw - 16px));
      z-index: 13000;
      pointer-events: none;
      text-align: center;
      white-space: normal;
      box-shadow: 0 1px 4px rgba(0,0,0,0.1);
    `;

    document.body.appendChild(tooltip);

    const previousDescription = element.getAttribute('aria-describedby');
    element.setAttribute(
      'aria-describedby',
      [previousDescription, tooltipId].filter(Boolean).join(' ')
    );
    activeTooltipDescription = { element, tooltipId };

    // Position tooltip
    const rect = element.getBoundingClientRect();
    const tooltipRect = tooltip.getBoundingClientRect();

    let left;
    let top;

    if (placement === 'right') {
      left = rect.right + gap;
      top = rect.top + (rect.height / 2) - (tooltipRect.height / 2);

      if (left + tooltipRect.width > viewportRight) {
        left = rect.left - tooltipRect.width - gap;
      }
    } else {
      left = rect.left + (rect.width / 2) - (tooltipRect.width / 2);
      top = rect.top - tooltipRect.height - gap;

      if (top < viewportTop) {
        top = rect.bottom + gap;
      }
    }

    const maximumLeft = Math.max(viewportLeft, viewportRight - tooltipRect.width);
    const maximumTop = Math.max(viewportTop, viewportBottom - tooltipRect.height);
    left = Math.min(Math.max(left, viewportLeft), maximumLeft);
    top = Math.min(Math.max(top, viewportTop), maximumTop);

    tooltip.style.left = left + 'px';
    tooltip.style.top = top + 'px';
  }

  installFastTooltipDelegation();

  // Legacy shim: FastTooltip previously bound per-element listeners from this
  // hook, and some renderers (expanded widget view, AG Grid tables) call its
  // methods directly. Delegation now covers every [data-tooltip] element, so
  // the hook reduces to the shared show/hide helpers.
  Hooks.FastTooltip = {
    mounted() {},
    updated() {
      if (activeTooltipTarget && !activeTooltipTarget.isConnected) clearTooltipTarget();
    },
    destroyed() {
      if (activeTooltipTarget && this.el.contains(activeTooltipTarget)) clearTooltipTarget();
    },
    initTooltips() {},

    showTooltip(element, text) {
      if (matchesTooltipMedia(element)) showFastTooltip(element, text);
    },

    hideTooltip() {
      clearTooltipTarget();
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

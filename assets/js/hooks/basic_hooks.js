export const registerBasicHooks = (Hooks, deps = {}) => {
  const { setHidden } = deps;
Hooks.DocumentTitle = {
  mounted() {
    // Create bound event handler so we can properly remove it
    this.handleNavigate = () => {
      // Force LiveView to update the title after navigation
      // This ensures the title updates even when using push_navigate
      requestAnimationFrame(() => {
        const liveTitle = document.querySelector('[data-phx-main] title')
        if (liveTitle && liveTitle.textContent) {
          document.title = liveTitle.textContent
        } else {
          // Fallback to our element's data
          this.updateTitle()
        }
      })
    }
    
    this.updateTitle()
    
    // Listen for both navigation events
    window.addEventListener("phx:page-loading-stop", this.handleNavigate)
    window.addEventListener("phx:navigate", this.handleNavigate)
  },
  updated() {
    this.updateTitle()
  },
  destroyed() {
    if (this.handleNavigate) {
      window.removeEventListener("phx:page-loading-stop", this.handleNavigate)
      window.removeEventListener("phx:navigate", this.handleNavigate)
    }
  },
  updateTitle() {
    const title = this.el.dataset.title || 'Trifle'
    const suffix = this.el.dataset.suffix || ''
    document.title = `${title}${suffix}`
  }
}

Hooks.CopyFeedback = {
  mounted() {
    this._copyFeedbackTimeout = null;
    const applyHidden = typeof setHidden === 'function' ? setHidden : () => {};
    this._handleCopyFeedbackClick = () => {
      const timeout = parseInt(this.el.dataset.copyTimeout || '2000', 10);
      const delay = Number.isFinite(timeout) ? timeout : 2000;
      const copyIcon = this.el.dataset.copyIcon
        ? document.getElementById(this.el.dataset.copyIcon)
        : null;
      const copiedIcon = this.el.dataset.copiedIcon
        ? document.getElementById(this.el.dataset.copiedIcon)
        : null;
      const copyLabel = this.el.dataset.copyLabel
        ? document.getElementById(this.el.dataset.copyLabel)
        : null;
      const copiedLabel = this.el.dataset.copiedLabel
        ? document.getElementById(this.el.dataset.copiedLabel)
        : null;

      applyHidden(copyIcon, true);
      applyHidden(copiedIcon, false);
      applyHidden(copyLabel, true);
      applyHidden(copiedLabel, false);

      if (this._copyFeedbackTimeout) {
        clearTimeout(this._copyFeedbackTimeout);
      }

      this._copyFeedbackTimeout = setTimeout(() => {
        applyHidden(copyIcon, false);
        applyHidden(copiedIcon, true);
        applyHidden(copyLabel, false);
        applyHidden(copiedLabel, true);
        this._copyFeedbackTimeout = null;
      }, delay);
    };

    this.el.addEventListener('click', this._handleCopyFeedbackClick);
  },
  destroyed() {
    if (this._handleCopyFeedbackClick) {
      this.el.removeEventListener('click', this._handleCopyFeedbackClick);
    }
    if (this._copyFeedbackTimeout) {
      clearTimeout(this._copyFeedbackTimeout);
      this._copyFeedbackTimeout = null;
    }
  }
}

Hooks.SmartTimeframeInput = {
  mounted() {
    this.handleEvent("update_smart_timeframe_input", ({value}) => {
      this.el.value = value;
    });
  }
}

Hooks.SmartTimeframeBlur = {
  mounted() {
    this._onKeydown = (e) => {
      if (e.key === 'Enter') {
        // Blur the input after Enter to trigger value update
        setTimeout(() => this.el.blur(), 100);
      }
    };
    this.el.addEventListener('keydown', this._onKeydown);

    // Auto-select text when input is focused
    this._onFocus = () => {
      // Use setTimeout to ensure selection happens after other focus events
      setTimeout(() => {
        this.el.select();
      }, 10);
    };
    this.el.addEventListener('focus', this._onFocus);

    // Also handle click events in case focus doesn't work
    this._onClick = () => {
      // Only select if the input wasn't already focused
      if (document.activeElement !== this.el) {
        setTimeout(() => {
          this.el.select();
        }, 10);
      }
    };
    this.el.addEventListener('click', this._onClick);

    this._updateHandler = this.handleEvent("update_timeframe_input", ({value}) => {
      this.el.value = value;
    });
  },
  destroyed() {
    if (this._onKeydown) this.el.removeEventListener('keydown', this._onKeydown);
    if (this._onFocus) this.el.removeEventListener('focus', this._onFocus);
    if (this._onClick) this.el.removeEventListener('click', this._onClick);
    if (this._updateHandler && typeof this.removeHandleEvent === 'function') {
      this.removeHandleEvent(this._updateHandler);
    }
  }
}

Hooks.ChatScroll = {
  mounted() {
    this._pendingScroll = null
    this.scrollToBottom()
    this.handleEvent("chat_scroll_bottom", () => this.scrollToBottom())
  },
  updated() {
    this.scrollToBottom()
  },
  scrollToBottom() {
    if (this._pendingScroll) {
      clearTimeout(this._pendingScroll)
    }

    const performScroll = (behavior = "auto") => {
      const el = this.el
      if (!el) return
      el.scrollTo({ top: el.scrollHeight, behavior })
    }

    requestAnimationFrame(() => {
      performScroll("auto")
      requestAnimationFrame(() => performScroll("smooth"))
    })

    this._pendingScroll = setTimeout(() => performScroll("auto"), 300)
  },
  destroyed() {
    if (this._pendingScroll) {
      clearTimeout(this._pendingScroll)
    }
  }
}

Hooks.ChatInput = {
  mounted() {
    this.handleKeydown = (event) => {
      if (event.defaultPrevented || this.el.disabled || this.el.readOnly) {
        return
      }

      if (event.key === "Enter" && !event.shiftKey) {
        event.preventDefault()

        const form = this.el.form || this.el.closest("form")
        if (!form) return

        if (typeof form.requestSubmit === "function") {
          form.requestSubmit()
        } else {
          const submit = form.querySelector('[type="submit"]:not([disabled])')
          if (submit) submit.click()
        }
      }
    }

    this.el.addEventListener("keydown", this.handleKeydown)
  },
  destroyed() {
    if (this.handleKeydown) {
      this.el.removeEventListener("keydown", this.handleKeydown)
    }
  }
}

Hooks.ExportTheme = {
  // ExportTheme deliberately overlaps with ThemeManager: applyTheme forces document.documentElement
  // and document.body classes, then emits the same 'trifle:theme-changed' CustomEvent for export pages.
  mounted() {
    this.applyTheme();
  },
  updated() {
    this.applyTheme();
  },
  destroyed() {
    if (this._themeTimer) {
      clearTimeout(this._themeTimer);
      this._themeTimer = null;
    }
  },
  applyTheme() {
    const dataset = this.el.dataset || {};
    const value = (dataset.exportTheme || dataset.theme || '').toLowerCase();
    const theme = value === 'dark' ? 'dark' : 'light';
    const root = document.documentElement;
    const body = document.body;
    try {
      if (theme === 'dark') {
        root.classList.add('dark');
        if (body && body.classList) body.classList.add('dark');
      } else {
        root.classList.remove('dark');
        if (body && body.classList) body.classList.remove('dark');
      }
      root.dataset.exportTheme = theme;
      if (body) body.dataset.theme = theme;
      root.style.background = 'transparent';
      if (body) body.style.background = 'transparent';
    } catch (_) {}

    if (this._themeTimer) {
      clearTimeout(this._themeTimer);
      this._themeTimer = null;
    }

    this._themeTimer = setTimeout(() => {
      try {
        window.dispatchEvent(new CustomEvent('trifle:theme-changed', { detail: { theme } }));
      } catch (_) {}
    }, 0);
  }
}

};

export const registerDownloadHooks = (Hooks, deps = {}) => {
Hooks.FileDownload = {
  mounted() {
    this.handleEvent('file_download', ({ content, content_base64, base64, filename, type }) => {
      try {
        let blob;
        if (base64 || content_base64) {
          const b64 = content_base64 || content || '';
          const bytes = this._b64ToUint8Array(b64);
          blob = new Blob([bytes], { type: type || 'application/octet-stream' });
        } else {
          blob = new Blob([content || ''], { type: type || 'application/octet-stream' });
        }
        const url = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = url;
        a.download = filename || 'download';
        document.body.appendChild(a);
        a.click();
        setTimeout(() => {
          URL.revokeObjectURL(url);
          document.body.removeChild(a);
        }, 0);
        // Notify any listeners that a download was initiated
        window.dispatchEvent(new CustomEvent('download:complete'));
      } catch (e) {
        console.error('File download failed', e);
      }
    });

    this.handleEvent('file_download_url', ({ url, filename, target }) => {
      try {
        if (!url) throw new Error('Missing url');
        // Prefer hidden iframe to avoid interfering with LiveView navigation
        const iframe = document.createElement('iframe');
        iframe.style.display = 'none';
        iframe.src = url;
        iframe.addEventListener('load', () => {
          window.dispatchEvent(new CustomEvent('download:complete'));
        });
        document.body.appendChild(iframe);
        // Safety cleanup
        setTimeout(() => { try { document.body.removeChild(iframe); } catch (_) {} }, 60000);
        // Note: Avoid forcing navigation to keep LiveView intact
      } catch (e) {
        console.error('File download url failed', e);
      }
    });

    this.handleEvent('export_dashboard_pdf', ({ title, timeframe, granularity }) => {
      try {
        const root = document.documentElement;
        const wasDark = root.classList.contains('dark');
        if (wasDark) root.classList.remove('dark');

        const header = document.createElement('div');
        header.id = 'dashboard-print-header';
        header.style.background = '#ffffff';
        header.style.color = '#0f172a';
        header.style.padding = '16px 24px';
        header.style.borderBottom = '1px solid #e5e7eb';
        header.style.fontFamily = 'ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Ubuntu, Cantarell, Noto Sans, Helvetica Neue, Arial';
        header.innerHTML = `
          <div style="max-width: 1024px; margin: 0 auto;">
            <div style="font-size: 18px; font-weight: 600;">${this.escapeHtml(title || 'Dashboard')}</div>
            <div style="margin-top: 6px; font-size: 12px; color: #475569;">
              ${timeframe ? this.escapeHtml(timeframe) + ' • ' : ''}Granularity: ${this.escapeHtml(granularity || '')}
            </div>
          </div>
        `;
        document.body.prepend(header);

        const cleanup = () => {
          try { header.remove(); } catch (_) {}
          if (wasDark) root.classList.add('dark');
          window.removeEventListener('afterprint', cleanup);
        };
        window.addEventListener('afterprint', cleanup);
        setTimeout(() => window.print(), 50);
      } catch (e) {
        console.error('PDF export failed', e);
      }
    });
  },

  escapeHtml(str) { return String(str || '').replace(/[&<>"']/g, (s) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' }[s])); },

  _b64ToUint8Array(b64) {
    const binary = atob(b64);
    const len = binary.length;
    const bytes = new Uint8Array(len);
    for (let i = 0; i < len; i++) bytes[i] = binary.charCodeAt(i);
    return bytes;
  }
};

// Download menu: close on click, show loading state until iframe loads
Hooks.DownloadMenu = {
  mounted() {
    this.loading = false;
    this.setElements();
    const datasetLabel = (this.el.dataset && this.el.dataset.defaultLabel) || '';
    this.originalLabel = datasetLabel || (this.label ? this.label.textContent : '');
    this.loadingLabel = (this.el.dataset && this.el.dataset.loadingLabel) || 'Exporting…';
    this.iframe = document.querySelector('iframe[name="download_iframe"]');
    this.hrefSignature = this.computeHrefSignature();

    this.bindAnchors();
    this.bindIframe();

    this.handleEvent('monitor_widget_export_params', ({ params }) => {
      this.updateExportLinks(params || {});
    });

    // Global completion signal (for blob-based downloads or alternate flows)
    this._onDownloadComplete = () => this.stopLoading();
    window.addEventListener('download:complete', this._onDownloadComplete);
  },

  updated() {
    // Rebind anchors when dropdown content re-renders and reselect elements that may have been replaced
    this.setElements();
    const datasetLabel = (this.el.dataset && this.el.dataset.defaultLabel) || '';
    if (datasetLabel) {
      this.originalLabel = datasetLabel;
    } else if (!this.originalLabel && this.label) {
      this.originalLabel = this.label.textContent;
    }

    const newSignature = this.computeHrefSignature();
    if (newSignature !== this.hrefSignature) {
      this.hrefSignature = newSignature;
      if (!this.loading) {
        this.stopLoading(true);
      }
    }

    this.bindAnchors();
    // Rebind iframe in case it was re-rendered
    const newIframe = document.querySelector('iframe[name="download_iframe"]');
    if (newIframe !== this.iframe) {
      this.unbindIframe();
      this.iframe = newIframe;
      this.bindIframe();
    }
    // If still loading, re-apply loading UI state after LV patch
    if (this.loading) this.applyLoadingState();
  },

  updateExportLinks(params) {
    if (!params || typeof params !== 'object') return;
    const managedKeys = ['timeframe', 'granularity', 'from', 'to', 'segments', 'key'];
    this.el.querySelectorAll('a[data-export-link]').forEach((a) => {
      const href = a.getAttribute('href');
      if (!href) return;
      try {
        const url = new URL(href, window.location.origin);
        managedKeys.forEach((key) => {
          const value = params[key];
          if (value == null || value === '') {
            url.searchParams.delete(key);
          }
        });
        Object.entries(params).forEach(([key, value]) => {
          if (value == null || value === '') {
            url.searchParams.delete(key);
          } else {
            url.searchParams.set(key, value);
          }
        });
        const token = url.searchParams.get('download_token');
        if (token) {
          this._downloadToken = token;
          try { window.__downloadToken = token; } catch (_) {}
          this.startCookiePolling();
        }
        url.searchParams.delete('download_token');
        a.setAttribute('href', url.toString());
      } catch (_) {
        // Ignore malformed hrefs
      }
    });
    this.hrefSignature = this.computeHrefSignature();
  },

  computeHrefSignature() {
    return Array.from(this.el.querySelectorAll('a[data-export-link]'))
      .map((a) => a.getAttribute('href') || '')
      .join('|');
  },

  bindAnchors() {
    if (this._bound) {
      return;
    }
    this._bound = true;
    this._onClickCapture = (e) => {
      const a = e.target.closest('a[data-export-link]');
      const btn = e.target.closest('button[data-export-trigger]');
      if (!this.el.contains(e.target)) return; // Only handle clicks within this menu
      if (a) {
        try {
          const url = new URL(a.getAttribute('href') || '', window.location.origin);
          const token = url.searchParams.get('download_token');
          if (token) {
            this._downloadToken = token;
            try { window.__downloadToken = token; } catch (_) {}
            this.startCookiePolling();
          }
        } catch (_) {}
        this.startLoading();
        setTimeout(() => this.pushEvent('hide_export_dropdown', {}), 0);
        return;
      }
      if (!btn) return;
      // Separate loading instance for button-triggered exports
      this.loading = true;
      this.applyLoadingState();
      // Generate token so iframe poller knows when to reset for button-trigger downloads
      const token = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
      this._downloadToken = token;
      try { window.__downloadToken = token; } catch (_) {}
      this.pushEvent('hide_export_dropdown', {});
      // Start polling for the cookie to flip back UI when done
      this.startCookiePolling();
    };
    // Use capture phase to run before LiveView's phx-click-away handler
    document.addEventListener('click', this._onClickCapture, true);
  },

  bindIframe() {
    if (!this.iframe || this._iframeBound) return;
    this._onIframeLoad = () => {
      // Any load in the download iframe marks completion
      this.stopLoading();
    };
    this.iframe.addEventListener('load', this._onIframeLoad);
    this._iframeBound = true;
  },

  unbindIframe() {
    if (this.iframe && this._onIframeLoad) {
      this.iframe.removeEventListener('load', this._onIframeLoad);
    }
    this._onIframeLoad = null;
    this._iframeBound = false;
  },

  startLoading() {
    if (this.loading) return;
    this.loading = true;
    this.applyLoadingState();
  },

  stopLoading(force = false) {
    if (!this.loading && !force) return;
    this.loading = false;
    this.stopCookiePolling();
    if (this.button) {
      this.button.removeAttribute('data-loading');
      this.button.removeAttribute('aria-busy');
      this.button.classList.remove('opacity-70', 'cursor-wait');
      this.button.disabled = false;
    }
    const datasetLabel = (this.el.dataset && this.el.dataset.defaultLabel) || '';
    if (this.icon) this.icon.classList.remove('hidden');
    if (this.spinner) this.spinner.classList.add('hidden');
    if (this.label) this.label.textContent = this.originalLabel || datasetLabel || 'Download';
  },

  applyLoadingState() {
    if (this.button) {
      this.button.setAttribute('aria-busy', 'true');
      this.button.setAttribute('data-loading', 'true');
      this.button.classList.add('opacity-70', 'cursor-wait');
      this.button.disabled = true;
    }
    if (this.icon) this.icon.classList.add('hidden');
    if (this.spinner) this.spinner.classList.remove('hidden');
    if (this.label) this.label.textContent = this.loadingLabel;
  },

  startCookiePolling() {
    this.stopCookiePolling();
    const token = this._downloadToken;
    if (!token) return;
    const deadline = Date.now() + 60000; // 60s timeout
    this._cookieTimer = setInterval(() => {
      try {
        const cookieEntry = document.cookie.split('; ').find((c) => c.startsWith('download_token='));
        if (cookieEntry) {
          const val = decodeURIComponent(cookieEntry.split('=')[1] || '');
          const expected = token || (window.__downloadToken || '');
          if (!expected || val === expected) {
            // Clear cookie and stop loading
            document.cookie = 'download_token=; Max-Age=0; path=/';
            this.stopLoading();
          }
        }
        if (Date.now() > deadline) {
          // Fallback timeout
          this.stopLoading();
        }
      } catch (_) {
        // ignore
      }
    }, 500);
  },

  stopCookiePolling() {
    if (this._cookieTimer) {
      clearInterval(this._cookieTimer);
      this._cookieTimer = null;
    }
  },

  setElements() {
    this.button = this.el.querySelector('[data-role="download-button"]');
    this.label = this.el.querySelector('[data-role="download-text"]');
    this.icon = this.el.querySelector('[data-role="download-icon"]');
    this.spinner = this.el.querySelector('[data-role="download-spinner"]');
  },

  destroyed() {
    if (this._onClickCapture) {
      document.removeEventListener('pointerdown', this._onClickCapture, true);
      document.removeEventListener('click', this._onClickCapture, true);
    }
    if (this._onDownloadComplete) {
      window.removeEventListener('download:complete', this._onDownloadComplete);
    }
    this.unbindIframe();
    this.stopCookiePolling();
  }
}

// Widget export dropdown helpers (non-LiveView toggled)
window.TrifleDownloads = window.TrifleDownloads || {};
(function (scope) {
  const HIDDEN_CLASS = 'hidden';

  const queryDropdown = (menu) => (menu ? menu.querySelector('[data-widget-dropdown]') : null);
  const queryButton = (menu) => (menu ? menu.querySelector('[data-role="download-button"]') : null);

  scope.closeWidgetMenu = function closeWidgetMenu(menu) {
    if (!menu) return;
    const dropdown = queryDropdown(menu);
    if (dropdown) {
      dropdown.classList.add(HIDDEN_CLASS);
      dropdown.setAttribute('aria-hidden', 'true');
    }
    const button = queryButton(menu);
    if (button) button.setAttribute('aria-expanded', 'false');
    menu.dataset.open = 'false';
  };

  scope.closeAllWidgetMenus = function closeAllWidgetMenus(exceptMenu) {
    document
      .querySelectorAll('[data-widget-download-menu][data-open="true"]')
      .forEach((menu) => {
        if (exceptMenu && menu === exceptMenu) return;
        scope.closeWidgetMenu(menu);
      });
  };

  scope.toggleWidgetMenu = function toggleWidgetMenu(button) {
    if (!button) return;
    const menu = button.closest('[data-widget-download-menu]');
    if (!menu) return;
    const dropdown = queryDropdown(menu);
    if (!dropdown) return;
    const isOpen = menu.dataset.open === 'true';
    if (isOpen) {
      scope.closeWidgetMenu(menu);
      return;
    }
    scope.closeAllWidgetMenus(menu);
    dropdown.classList.remove(HIDDEN_CLASS);
    dropdown.setAttribute('aria-hidden', 'false');
    menu.dataset.open = 'true';
    button.setAttribute('aria-expanded', 'true');
  };

  scope.handleWidgetExportClick = function handleWidgetExportClick(link) {
    if (!link) return;
    const menu = link.closest('[data-widget-download-menu]');
    if (menu) {
      const dropdown = queryDropdown(menu);
      if (dropdown) {
        dropdown.classList.add(HIDDEN_CLASS);
        dropdown.setAttribute('aria-hidden', 'true');
      }
      menu.dataset.open = 'false';
      const button = queryButton(menu);
      if (button) {
        button.setAttribute('aria-expanded', 'false');
      }
    }
    try {
      const url = new URL(link.getAttribute('href') || '', window.location.origin);
      if (!url.searchParams.get('download_token')) {
        const token = `${Date.now()}-${Math.random().toString(36).slice(2)}`;
        window.__downloadToken = token;
        url.searchParams.set('download_token', token);
        link.href = url.toString();
      }
    } catch (_) {
      // ignore malformed URLs
    }
  };

  document.addEventListener('click', (event) => {
    if (event.defaultPrevented) return;
    const menu = event.target.closest('[data-widget-download-menu]');
    if (!menu) {
      scope.closeAllWidgetMenus();
    }
  });

  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') {
      scope.closeAllWidgetMenus();
    }
  });
})(window.TrifleDownloads);

};

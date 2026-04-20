const ANNOTATIONS_COOKIE = 'trifle_dashboard_annotations';

const readAnnotationsCookie = () => {
  try {
    const match = document.cookie
      .split(';')
      .map((part) => part.trim())
      .find((part) => part.startsWith(`${ANNOTATIONS_COOKIE}=`));
    if (!match) return true;
    return match.split('=').slice(1).join('=') !== '0';
  } catch (_) {
    return true;
  }
};

const writeAnnotationsCookie = (enabled) => {
  try {
    const value = enabled ? '1' : '0';
    document.cookie = `${ANNOTATIONS_COOKIE}=${value}; Max-Age=31536000; Path=/; SameSite=Lax`;
  } catch (_) {}
};

const broadcastAnnotationsVisibility = (enabled) => {
  try {
    window.dispatchEvent(new CustomEvent('trifle:annotations-visibility-changed', {
      detail: { enabled: !!enabled }
    }));
  } catch (_) {}
};

export const registerDashboardAnnotationsDataHook = (Hooks, deps) => {
  const { parseJsonSafe, findDashboardGridHook } = deps;

  Hooks.DashboardAnnotationsData = {
    mounted() {
      this._lastPayload = null;
      this._retryTimer = null;
      this.register();
    },

    updated() {
      this.register();
    },

    destroyed() {
      if (this._retryTimer) {
        clearTimeout(this._retryTimer);
        this._retryTimer = null;
      }
    },

    register() {
      const raw = this.el.dataset.annotationsPayload || '';
      if (raw === this._lastPayload) return;
      this._lastPayload = raw;
      const payload = parseJsonSafe(raw) || { groups: [] };
      const gridHook = findDashboardGridHook(this.el);
      if (gridHook && typeof gridHook.setAnnotations === 'function') {
        gridHook.setAnnotations(payload);
      } else {
        this._retryTimer = setTimeout(() => {
          this._lastPayload = null;
          this.register();
        }, 20);
      }
    }
  };

  Hooks.DashboardAnnotationToggle = {
    mounted() {
      this.input = this.el.querySelector('[data-role="annotation-toggle"]');
      this.knob = this.input && this.input.querySelector
        ? this.input.querySelector('[data-role="annotation-toggle-knob"]')
        : null;
      this._onChange = () => {
        const enabled = this.isCheckbox()
          ? !!(this.input && this.input.checked)
          : !(this.input && this.input.getAttribute('aria-pressed') === 'true');
        writeAnnotationsCookie(enabled);
        this.applyState(enabled);
        broadcastAnnotationsVisibility(enabled);
      };

      const enabled = readAnnotationsCookie();
      if (this.input) {
        this.applyState(enabled);
        this.input.addEventListener(this.isCheckbox() ? 'change' : 'click', this._onChange);
      }
      broadcastAnnotationsVisibility(enabled);
    },

    updated() {
      if (this.input) {
        this.applyState(readAnnotationsCookie());
      }
    },

    destroyed() {
      if (this.input && this._onChange) {
        this.input.removeEventListener(this.isCheckbox() ? 'change' : 'click', this._onChange);
      }
      this.input = null;
      this.knob = null;
      this._onChange = null;
    },

    isCheckbox() {
      return this.input && this.input.tagName === 'INPUT';
    },

    applyState(enabled) {
      if (!this.input) return;
      if (this.isCheckbox()) {
        this.input.checked = !!enabled;
        return;
      }

      this.input.setAttribute('aria-pressed', enabled ? 'true' : 'false');
      this.input.classList.toggle('bg-teal-600', !!enabled);
      this.input.classList.toggle('bg-gray-200', !enabled);
      this.input.classList.toggle('dark:bg-gray-700', !enabled);

      if (this.knob) {
        this.knob.classList.toggle('translate-x-5', !!enabled);
        this.knob.classList.toggle('translate-x-0', !enabled);
      }
    }
  };
};

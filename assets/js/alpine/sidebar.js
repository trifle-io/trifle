const SIDEBAR_SCROLL_LOCK_CLASS = "trifle-sidebar-open";
const CHAT_SHELL_STORAGE_KEY = "trifle:chat-shell-open";
const CHAT_SHELL_MODE_STORAGE_KEY = "trifle:chat-shell-mode";
const CHAT_SHELL_DEFAULT_MODE = "panel";
const CHAT_SHELL_MODES = new Set(["pinned", "panel", "fullscreen"]);
const CHAT_SHELL_SET_MODE_EVENT = "trifle:chat-shell:set-mode";
const CHAT_SHELL_MODE_CHANGED_EVENT = "trifle:chat-shell:mode-changed";
const SIDEBAR_ROOT_DATASET_KEYS = Object.freeze({
  "trifle:sidebar": "trifleClientSidebar",
  "trifle:client-sidebar": "trifleClientSidebar",
  "trifle:admin-sidebar": "trifleAdminSidebar"
});
const SIDEBAR_SHELL_IDS = Object.freeze({
  "trifle:sidebar": "client-sidebar-shell",
  "trifle:client-sidebar": "client-sidebar-shell",
  "trifle:admin-sidebar": "admin-sidebar-shell"
});
const MOBILE_SIDEBAR_FOCUSABLE_SELECTOR = [
  "a[href]",
  "button:not([disabled])",
  "input:not([disabled]):not([type='hidden'])",
  "select:not([disabled])",
  "textarea:not([disabled])",
  "[tabindex]:not([tabindex='-1'])"
].join(", ");
const COMMAND_PALETTE_ITEM_SELECTOR = "[data-command-palette-item]";
const COMMAND_PALETTE_SECTION_SELECTOR = "[data-command-palette-section]";
const COMMAND_PALETTE_EMPTY_SELECTOR = "[data-command-palette-empty]";

const syncSidebarRootState = (storageKey, desktopCollapsed) => {
  const datasetKey = SIDEBAR_ROOT_DATASET_KEYS[storageKey];
  if (!datasetKey || !document.documentElement) return;
  document.documentElement.dataset[datasetKey] = desktopCollapsed ? "collapsed" : "expanded";
};

const dispatchSyntheticResize = () => {
  try {
    window.dispatchEvent(new Event("resize"));
  } catch (_) {}
};

const scheduleSyntheticResize = () => {
  dispatchSyntheticResize();

  try {
    window.requestAnimationFrame(() => dispatchSyntheticResize());
  } catch (_) {}

  [160, 340, 520].forEach((delay) => {
    window.setTimeout(() => dispatchSyntheticResize(), delay);
  });
};

const readChatShellMode = () => {
  try {
    const stored =
      window.sessionStorage ? window.sessionStorage.getItem(CHAT_SHELL_MODE_STORAGE_KEY) : null;
    return CHAT_SHELL_MODES.has(stored) ? stored : CHAT_SHELL_DEFAULT_MODE;
  } catch (_) {
    return CHAT_SHELL_DEFAULT_MODE;
  }
};

const emitChatShellModeChanged = (mode) => {
  window.dispatchEvent(
    new CustomEvent(CHAT_SHELL_MODE_CHANGED_EVENT, {
      detail: { mode }
    })
  );
};

const isEditableShortcutTarget = (target) => {
  if (!(target instanceof HTMLElement)) return false;
  if (target.isContentEditable) return true;

  const tagName = String(target.tagName || "").toLowerCase();
  return ["input", "textarea", "select"].includes(tagName);
};

const isApplePlatform = () => {
  try {
    const platform = navigator.userAgentData?.platform || navigator.platform || "";
    const userAgent = navigator.userAgent || "";
    return /Mac|iPhone|iPad|iPod/i.test(`${platform} ${userAgent}`);
  } catch (_) {
    return false;
  }
};

const generateTabId = () =>
  window.crypto && typeof window.crypto.randomUUID === "function"
    ? window.crypto.randomUUID()
    : `tab-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;

const normalizeSidebarStorageKey = (storageKey) =>
  storageKey === "trifle:sidebar" ? "trifle:client-sidebar" : storageKey;

export const getOrCreateTabId = (() => {
  const storageKey = "trifle:tab-id";
  const claimKeyPrefix = "trifle:tab-id-owner:";
  const currentTabOwner = generateTabId();
  let currentTabId = null;

  const claimCurrentTabId = () => {
    if (!currentTabId || !window.localStorage) return;
    window.localStorage.setItem(`${claimKeyPrefix}${currentTabId}`, currentTabOwner);
  };

  const hasDuplicateClaim = () => {
    if (!currentTabId || !window.localStorage) return false;
    const owner = window.localStorage.getItem(`${claimKeyPrefix}${currentTabId}`);
    return !!owner && owner !== currentTabOwner;
  };

  const persistCurrentTabId = () => {
    if (!currentTabId || !window.sessionStorage) return;
    window.sessionStorage.setItem(storageKey, currentTabId);
    claimCurrentTabId();
  };

  const refreshCurrentTabId = () => {
    currentTabId = generateTabId();
    persistCurrentTabId();
    return currentTabId;
  };

  const syncTabIdOnShow = () => {
    if (document.visibilityState && document.visibilityState !== "visible") return;

    try {
      const storedTabId = window.sessionStorage && window.sessionStorage.getItem(storageKey);
      if (storedTabId && storedTabId !== currentTabId) {
        currentTabId = storedTabId;
      }
      if (storedTabId && storedTabId === currentTabId && hasDuplicateClaim()) {
        refreshCurrentTabId();
        return;
      }
      persistCurrentTabId();
    } catch (_) {
      try {
        refreshCurrentTabId();
      } catch (_) {
        // Ignore storage failures and keep using the in-memory tab id.
      }
    }
  };

  try {
    const storedTabId = window.sessionStorage && window.sessionStorage.getItem(storageKey);

    if (storedTabId) {
      currentTabId = storedTabId;
      if (hasDuplicateClaim()) {
        refreshCurrentTabId();
      } else {
        persistCurrentTabId();
      }
    } else {
      refreshCurrentTabId();
    }
  } catch (_) {
    currentTabId = generateTabId();
  }

  window.addEventListener("pageshow", syncTabIdOnShow);
  document.addEventListener("visibilitychange", syncTabIdOnShow);

  return () => currentTabId || refreshCurrentTabId();
})();

export const registerSidebarAlpineComponents = () => {
window.trifleSidebar = ({ storageKey = "trifle:sidebar", defaultCollapsed = false } = {}) => ({
  storageKey,
  defaultCollapsed,
  mobileOpen: false,
  desktopCollapsed: defaultCollapsed,
  chatOpen: false,
  chatMode: CHAT_SHELL_DEFAULT_MODE,
  commandPaletteOpen: false,
  commandPaletteQuery: "",
  commandPaletteActiveIndex: 0,
  commandPaletteActiveItemId: null,
  desktopViewport: false,
  _mediaQuery: null,
  _handleViewportChange: null,
  _mobileFocusOrigin: null,
  _commandPaletteFocusOrigin: null,
  _handleMobileKeydown: null,
  _handleChatToggle: null,
  _handleChatSetOpen: null,
  _handleChatSetMode: null,
  _handleChatShortcut: null,
  _handleCommandPaletteShortcut: null,
  _handleStorageSync: null,

  init() {
    this.loadState();
    this.loadChatState();
    this.loadChatMode();
    this.syncViewport();

    this._mediaQuery = window.matchMedia("(min-width: 1024px)");
    this._handleViewportChange = () => this.syncViewport(this._mediaQuery);

    if (typeof this._mediaQuery.addEventListener === "function") {
      this._mediaQuery.addEventListener("change", this._handleViewportChange);
    } else if (typeof this._mediaQuery.addListener === "function") {
      this._mediaQuery.addListener(this._handleViewportChange);
    }

    this.$watch("mobileOpen", (isOpen) => {
      this.syncBodyScrollLock();
      this.syncMobileFocus(isOpen);
    });

    this._handleChatToggle = () => this.toggleChat();
    this._handleChatSetOpen = (event) => {
      const detail = event && event.detail ? event.detail : {};
      this.setChatOpen(detail.open !== false);
    };
    this._handleChatSetMode = (event) => {
      const detail = event && event.detail ? event.detail : {};
      this.setChatMode(detail.mode);
    };
    this._handleChatShortcut = (event) => this.handleChatShortcut(event);
    this._handleCommandPaletteShortcut = (event) => this.handleCommandPaletteShortcut(event);
    this._handleStorageSync = (event) => this.syncStorageEvent(event);

    window.addEventListener("trifle:chat-shell:toggle", this._handleChatToggle);
    window.addEventListener("trifle:chat-shell:set-open", this._handleChatSetOpen);
    window.addEventListener(CHAT_SHELL_SET_MODE_EVENT, this._handleChatSetMode);
    window.addEventListener("keydown", this._handleChatShortcut);
    window.addEventListener("keydown", this._handleCommandPaletteShortcut);
    window.addEventListener("storage", this._handleStorageSync);
    emitChatShellModeChanged(this.chatMode);

    this.$watch("commandPaletteOpen", () => this.syncBodyScrollLock());
  },

  get compact() {
    return this.desktopViewport && this.desktopCollapsed;
  },

  chatShortcutLabel() {
    return isApplePlatform() ? "⌘+/" : "Ctrl+/";
  },

  commandShortcutLabel() {
    return isApplePlatform() ? "⌘+K" : "Ctrl+K";
  },

  loadState() {
    const preload = window.__TRIFLE_SIDEBAR_PRELOAD__ || {};
    const sidebarStorageKey = normalizeSidebarStorageKey(this.storageKey);
    const preloadedState =
      sidebarStorageKey === "trifle:client-sidebar"
        ? preload.client
        : sidebarStorageKey === "trifle:admin-sidebar"
          ? preload.admin
          : null;

    try {
      const stored = window.localStorage ? window.localStorage.getItem(sidebarStorageKey) : null;

      if (stored === "collapsed") {
        this.desktopCollapsed = true;
      } else if (stored === "expanded") {
        this.desktopCollapsed = false;
      } else if (preloadedState === "collapsed") {
        this.desktopCollapsed = true;
      } else if (preloadedState === "expanded") {
        this.desktopCollapsed = false;
      } else {
        this.desktopCollapsed = !!this.defaultCollapsed;
      }
    } catch (_) {
      if (preloadedState === "collapsed") {
        this.desktopCollapsed = true;
      } else if (preloadedState === "expanded") {
        this.desktopCollapsed = false;
      } else {
        this.desktopCollapsed = !!this.defaultCollapsed;
      }
    }

    syncSidebarRootState(sidebarStorageKey, this.desktopCollapsed);
  },

  loadChatState() {
    try {
      const stored = window.localStorage ? window.localStorage.getItem(CHAT_SHELL_STORAGE_KEY) : null;
      this.chatOpen = stored === "open";
    } catch (_) {
      this.chatOpen = false;
    }
  },

  loadChatMode() {
    this.chatMode = readChatShellMode();
  },

  syncViewport(mediaQuery = null) {
    const query = mediaQuery || window.matchMedia("(min-width: 1024px)");
    this.desktopViewport = !!query.matches;

    if (this.desktopViewport) {
      this.mobileOpen = false;
    }

    this.syncBodyScrollLock();
  },

  effectiveChatMode() {
    return this.desktopViewport ? this.chatMode : "fullscreen";
  },

  mainContentClasses() {
    const base = this.compact ? "lg:pl-[6.25rem]" : "lg:pl-[18rem]";
    const pinnedOpen =
      this.chatOpen && this.desktopViewport && this.effectiveChatMode() === "pinned";

    return pinnedOpen ? `${base} lg:pr-[51rem]` : base;
  },

  mainContentHidden() {
    return (
      (!this.desktopViewport && this.mobileOpen) ||
      (this.chatOpen && this.effectiveChatMode() === "fullscreen")
    );
  },

  chatShellViewportClasses() {
    const widthClass =
      this.desktopViewport && this.effectiveChatMode() !== "fullscreen" ? " lg:w-[51rem]" : "";

    return `${widthClass}${this.chatOpen ? " translate-x-0" : " translate-x-full"}`;
  },

  syncBodyScrollLock() {
    if (!document.body) return;
    document.body.classList.toggle(
      SIDEBAR_SCROLL_LOCK_CLASS,
      (this.mobileOpen && !this.desktopViewport) || this.commandPaletteOpen
    );
  },

  getSidebarShell() {
    const shellId = SIDEBAR_SHELL_IDS[this.storageKey];
    return shellId ? document.getElementById(shellId) : null;
  },

  getMobileFocusableElements() {
    const shell = this.getSidebarShell();
    if (!shell) return [];

    return Array.from(shell.querySelectorAll(MOBILE_SIDEBAR_FOCUSABLE_SELECTOR)).filter((element) => {
      if (!(element instanceof HTMLElement)) return false;
      if (element.getAttribute("aria-hidden") === "true") return false;
      const style = window.getComputedStyle(element);
      return style.display !== "none" && style.visibility !== "hidden";
    });
  },

  captureMobileFocusOrigin(focusOrigin = null) {
    const shell = this.getSidebarShell();
    const candidate =
      focusOrigin instanceof HTMLElement
        ? focusOrigin
        : document.activeElement instanceof HTMLElement
          ? document.activeElement
          : null;

    if (!candidate || candidate === document.body) return;
    if (shell && shell.contains(candidate)) return;

    this._mobileFocusOrigin = candidate;
  },

  syncMobileFocus(isOpen) {
    if (isOpen && !this.desktopViewport) {
      this.captureMobileFocusOrigin();
      this.activateMobileFocusTrap();
    } else {
      this.deactivateMobileFocusTrap();
    }
  },

  activateMobileFocusTrap() {
    const shell = this.getSidebarShell();
    if (!shell) return;

    this.deactivateMobileFocusTrap({ restoreFocus: false });

    this._handleMobileKeydown = (event) => {
      if (!this.mobileOpen || this.desktopViewport) return;

      if (event.key === "Escape") {
        event.preventDefault();
        this.closeMobile();
        return;
      }

      if (event.key !== "Tab") return;

      const focusable = this.getMobileFocusableElements();
      if (focusable.length === 0) {
        event.preventDefault();
        if (!shell.hasAttribute("tabindex")) {
          shell.setAttribute("tabindex", "-1");
        }
        shell.focus();
        return;
      }

      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      const active = document.activeElement;

      if (!(active instanceof HTMLElement) || !shell.contains(active)) {
        event.preventDefault();
        first.focus();
        return;
      }

      if (event.shiftKey && active === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && active === last) {
        event.preventDefault();
        first.focus();
      }
    };

    document.addEventListener("keydown", this._handleMobileKeydown);

    window.requestAnimationFrame(() => {
      if (!this.mobileOpen || this.desktopViewport) return;

      const preferredTarget = shell.querySelector("[data-mobile-sidebar-close]");
      const focusTarget =
        preferredTarget instanceof HTMLElement
          ? preferredTarget
          : this.getMobileFocusableElements()[0] || shell;

      if (focusTarget === shell && !shell.hasAttribute("tabindex")) {
        shell.setAttribute("tabindex", "-1");
      }

      focusTarget.focus();
    });
  },

  deactivateMobileFocusTrap({ restoreFocus = true } = {}) {
    if (this._handleMobileKeydown) {
      document.removeEventListener("keydown", this._handleMobileKeydown);
      this._handleMobileKeydown = null;
    }

    if (!restoreFocus) return;

    const focusOrigin = this._mobileFocusOrigin;
    this._mobileFocusOrigin = null;

    if (!(focusOrigin instanceof HTMLElement)) return;

    window.requestAnimationFrame(() => {
      if (focusOrigin.isConnected) {
        focusOrigin.focus();
      }
    });
  },

  persistState() {
    const sidebarStorageKey = normalizeSidebarStorageKey(this.storageKey);
    try {
      if (window.localStorage) {
        window.localStorage.setItem(
          sidebarStorageKey,
          this.desktopCollapsed ? "collapsed" : "expanded"
        );
      }
    } catch (_) {}

    syncSidebarRootState(sidebarStorageKey, this.desktopCollapsed);
  },

  persistChatState() {
    try {
      if (window.localStorage) {
        window.localStorage.setItem(CHAT_SHELL_STORAGE_KEY, this.chatOpen ? "open" : "closed");
      }
    } catch (_) {}
  },

  persistChatMode() {
    try {
      if (window.sessionStorage) {
        window.sessionStorage.setItem(CHAT_SHELL_MODE_STORAGE_KEY, this.chatMode);
      }
    } catch (_) {}
  },

  toggleDesktop() {
    this.desktopCollapsed = !this.desktopCollapsed;
    this.persistState();
    scheduleSyntheticResize();
  },

  setChatOpen(open) {
    this.chatOpen = !!open;
    this.persistChatState();
    scheduleSyntheticResize();
  },

  setChatMode(mode) {
    if (!CHAT_SHELL_MODES.has(mode)) return;
    this.chatMode = mode;
    this.persistChatMode();
    emitChatShellModeChanged(this.chatMode);
    scheduleSyntheticResize();
  },

  toggleChat() {
    this.chatOpen = !this.chatOpen;
    this.persistChatState();
    scheduleSyntheticResize();
  },

  handleChatShortcut(event) {
    const sidebarStorageKey = normalizeSidebarStorageKey(this.storageKey);
    if (sidebarStorageKey !== "trifle:client-sidebar" || !event || event.defaultPrevented) return;
    if (event.isComposing || event.repeat) return;
    if (event.altKey || !(event.metaKey || event.ctrlKey)) return;
    if (event.code !== "Slash") return;
    if (isEditableShortcutTarget(event.target)) return;

    event.preventDefault();
    this.toggleChat();
  },

  syncStorageEvent(event) {
    if (!event || event.key !== CHAT_SHELL_STORAGE_KEY) return;
    this.chatOpen = event.newValue === "open";
    scheduleSyntheticResize();
  },

  toggleMobile(focusOrigin = null) {
    if (!this.mobileOpen) {
      this.captureMobileFocusOrigin(focusOrigin);
    }

    this.mobileOpen = !this.mobileOpen;
  },

  closeMobile() {
    this.mobileOpen = false;
    this.syncBodyScrollLock();
  },

  getCommandPaletteDialog() {
    return document.getElementById("command-palette-dialog");
  },

  getCommandPaletteInput() {
    return document.getElementById("command-palette-input");
  },

  focusCommandPaletteInput() {
    if (!this.commandPaletteOpen) return;

    const input = this.getCommandPaletteInput();
    if (!(input instanceof HTMLElement)) return;

    try {
      input.focus({ preventScroll: true });
    } catch (_) {
      input.focus();
    }
  },

  getCommandPaletteItems() {
    const dialog = this.getCommandPaletteDialog();
    if (!dialog) return [];

    return Array.from(dialog.querySelectorAll(COMMAND_PALETTE_ITEM_SELECTOR)).filter(
      (element) => element instanceof HTMLElement
    );
  },

  getCommandPaletteVisibleItems() {
    return this.getCommandPaletteItems().filter((element) => !element.hidden);
  },

  setCommandPaletteElementVisible(element, visible) {
    if (!(element instanceof HTMLElement)) return;

    element.hidden = !visible;
    element.style.display = visible ? "" : "none";
  },

  normalizeCommandPaletteText(value) {
    return String(value || "")
      .trim()
      .toLowerCase()
      .replace(/\s+/g, " ");
  },

  commandPaletteMatchesQuery(searchText, query) {
    const normalizedSearch = this.normalizeCommandPaletteText(searchText);
    const terms = this.normalizeCommandPaletteText(query).split(" ").filter(Boolean);

    if (terms.length === 0) return true;
    return terms.every((term) => normalizedSearch.includes(term));
  },

  queueCommandPaletteRefresh() {
    this.$nextTick(() => this.refreshCommandPaletteResults());
  },

  refreshCommandPaletteResults() {
    const dialog = this.getCommandPaletteDialog();
    if (!dialog) return;

    const query = this.normalizeCommandPaletteText(this.commandPaletteQuery);
    const sections = Array.from(dialog.querySelectorAll(COMMAND_PALETTE_SECTION_SELECTOR)).filter(
      (element) => element instanceof HTMLElement
    );
    let visibleCount = 0;

    sections.forEach((section) => {
      let sectionVisibleCount = 0;
      const items = Array.from(section.querySelectorAll(COMMAND_PALETTE_ITEM_SELECTOR)).filter(
        (element) => element instanceof HTMLElement
      );

      items.forEach((item) => {
        const defaultVisible = item.dataset.commandPaletteDefaultVisible === "true";
        const searchable = item.dataset.commandPaletteSearchable === "true";
        const visible = query
          ? searchable && this.commandPaletteMatchesQuery(item.dataset.commandPaletteSearchText, query)
          : defaultVisible;

        this.setCommandPaletteElementVisible(item, visible);
        if (visible) {
          sectionVisibleCount += 1;
          visibleCount += 1;
        }
      });

      this.setCommandPaletteElementVisible(section, sectionVisibleCount > 0);
    });

    const empty = dialog.querySelector(COMMAND_PALETTE_EMPTY_SELECTOR);
    if (empty instanceof HTMLElement) {
      this.setCommandPaletteElementVisible(empty, visibleCount === 0);
    }

    const visibleItems = this.getCommandPaletteVisibleItems();

    if (visibleItems.length === 0) {
      this.commandPaletteActiveIndex = -1;
    } else if (this.commandPaletteActiveIndex < 0) {
      this.commandPaletteActiveIndex = 0;
    } else if (this.commandPaletteActiveIndex >= visibleItems.length) {
      this.commandPaletteActiveIndex = visibleItems.length - 1;
    }

    this.syncCommandPaletteActiveItem({ scroll: false });
  },

  captureCommandPaletteFocusOrigin(focusOrigin = null) {
    const candidate =
      focusOrigin instanceof HTMLElement
        ? focusOrigin
        : document.activeElement instanceof HTMLElement
          ? document.activeElement
          : null;

    if (!candidate || candidate === document.body) return;
    this._commandPaletteFocusOrigin = candidate;
  },

  openCommandPalette(focusOrigin = null) {
    const sidebarStorageKey = normalizeSidebarStorageKey(this.storageKey);
    if (sidebarStorageKey !== "trifle:client-sidebar") return;

    this.captureCommandPaletteFocusOrigin(focusOrigin);
    this.commandPaletteQuery = "";
    this.commandPaletteActiveIndex = 0;
    this.commandPaletteOpen = true;

    this.$nextTick(() => {
      this.refreshCommandPaletteResults();
      this.focusCommandPaletteInput();

      try {
        window.requestAnimationFrame(() => this.focusCommandPaletteInput());
      } catch (_) {}

      [80, 180].forEach((delay) => {
        window.setTimeout(() => this.focusCommandPaletteInput(), delay);
      });
    });
  },

  closeCommandPalette({ restoreFocus = true } = {}) {
    if (!this.commandPaletteOpen) return;

    this.commandPaletteOpen = false;
    this.commandPaletteQuery = "";
    this.commandPaletteActiveIndex = 0;
    this.commandPaletteActiveItemId = null;
    this.syncBodyScrollLock();

    if (!restoreFocus) {
      this._commandPaletteFocusOrigin = null;
      return;
    }

    const focusOrigin = this._commandPaletteFocusOrigin;
    this._commandPaletteFocusOrigin = null;

    if (!(focusOrigin instanceof HTMLElement)) return;

    window.requestAnimationFrame(() => {
      if (focusOrigin.isConnected) {
        focusOrigin.focus();
      }
    });
  },

  moveCommandPaletteActive(delta) {
    const visibleItems = this.getCommandPaletteVisibleItems();
    if (visibleItems.length === 0) return;

    const currentIndex = this.commandPaletteActiveIndex < 0 ? 0 : this.commandPaletteActiveIndex;
    this.commandPaletteActiveIndex =
      (currentIndex + delta + visibleItems.length) % visibleItems.length;
    this.syncCommandPaletteActiveItem({ scroll: true });
  },

  activateCommandPaletteElement(element) {
    if (!(element instanceof HTMLElement) || element.hidden) return;

    const visibleItems = this.getCommandPaletteVisibleItems();
    const index = visibleItems.indexOf(element);
    if (index < 0) return;

    this.commandPaletteActiveIndex = index;
    this.syncCommandPaletteActiveItem({ scroll: false });
  },

  commandPaletteItemActive(element) {
    return (
      element instanceof HTMLElement &&
      this.commandPaletteActiveItemId &&
      element.id === this.commandPaletteActiveItemId
    );
  },

  syncCommandPaletteActiveItem({ scroll = false } = {}) {
    const items = this.getCommandPaletteItems();
    const visibleItems = items.filter((element) => !element.hidden);
    const active = visibleItems[this.commandPaletteActiveIndex] || null;

    this.commandPaletteActiveItemId = active ? active.id : null;

    items.forEach((item) => {
      item.setAttribute("aria-selected", item === active ? "true" : "false");
    });

    if (scroll && active) {
      active.scrollIntoView({ block: "nearest" });
    }
  },

  selectActiveCommandPaletteItem() {
    const visibleItems = this.getCommandPaletteVisibleItems();
    const active = visibleItems[this.commandPaletteActiveIndex] || visibleItems[0];
    this.selectCommandPaletteElement(active);
  },

  selectCommandPaletteElement(element) {
    if (!(element instanceof HTMLElement) || element.hidden) return;

    const action = element.dataset.commandPaletteAction;
    if (action === "chat") {
      this.closeCommandPalette({ restoreFocus: false });
      this.closeMobile();
      this.setChatOpen(true);
      return;
    }

    const to = element.dataset.commandPaletteTo;
    if (!to) return;

    this.navigateCommandPalette(to);
  },

  navigateCommandPalette(to) {
    this.closeCommandPalette({ restoreFocus: false });
    this.closeMobile();

    if (window.liveSocket && typeof window.liveSocket.historyRedirect === "function") {
      window.liveSocket.historyRedirect(
        { isTrusted: false, type: "command-palette" },
        to,
        "push",
        null
      );
    } else {
      window.location.assign(to);
    }
  },

  handleCommandPaletteShortcut(event) {
    const sidebarStorageKey = normalizeSidebarStorageKey(this.storageKey);
    if (sidebarStorageKey !== "trifle:client-sidebar" || !event || event.defaultPrevented) return;
    if (event.isComposing || event.repeat) return;
    if (event.altKey || event.shiftKey || !(event.metaKey || event.ctrlKey)) return;
    if (event.code !== "KeyK") return;
    if (isEditableShortcutTarget(event.target)) return;

    event.preventDefault();
    this.openCommandPalette();
  },

  getCommandPaletteFocusableElements() {
    const dialog = this.getCommandPaletteDialog();
    if (!dialog) return [];

    return Array.from(dialog.querySelectorAll(MOBILE_SIDEBAR_FOCUSABLE_SELECTOR)).filter(
      (element) => {
        if (!(element instanceof HTMLElement)) return false;
        if (element.hidden || element.getAttribute("aria-hidden") === "true") return false;
        const style = window.getComputedStyle(element);
        return style.display !== "none" && style.visibility !== "hidden";
      }
    );
  },

  handleCommandPalettePanelKeydown(event) {
    if (!this.commandPaletteOpen || !event) return;

    if (event.key === "Escape") {
      event.preventDefault();
      this.closeCommandPalette();
      return;
    }

    if (event.key !== "Tab") return;

    const focusable = this.getCommandPaletteFocusableElements();
    if (focusable.length === 0) {
      event.preventDefault();
      return;
    }

    const first = focusable[0];
    const last = focusable[focusable.length - 1];
    const active = document.activeElement;

    if (!(active instanceof HTMLElement) || !this.getCommandPaletteDialog().contains(active)) {
      event.preventDefault();
      first.focus();
      return;
    }

    if (event.shiftKey && active === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && active === last) {
      event.preventDefault();
      first.focus();
    }
  },

  destroy() {
    this.deactivateMobileFocusTrap({ restoreFocus: false });
    if (document.body && document.body.classList) {
      document.body.classList.remove(SIDEBAR_SCROLL_LOCK_CLASS);
    }

    if (this._handleChatToggle) {
      window.removeEventListener("trifle:chat-shell:toggle", this._handleChatToggle);
      this._handleChatToggle = null;
    }

    if (this._handleChatSetOpen) {
      window.removeEventListener("trifle:chat-shell:set-open", this._handleChatSetOpen);
      this._handleChatSetOpen = null;
    }

    if (this._handleChatSetMode) {
      window.removeEventListener(CHAT_SHELL_SET_MODE_EVENT, this._handleChatSetMode);
      this._handleChatSetMode = null;
    }

    if (this._handleChatShortcut) {
      window.removeEventListener("keydown", this._handleChatShortcut);
      this._handleChatShortcut = null;
    }

    if (this._handleCommandPaletteShortcut) {
      window.removeEventListener("keydown", this._handleCommandPaletteShortcut);
      this._handleCommandPaletteShortcut = null;
    }

    if (this._handleStorageSync) {
      window.removeEventListener("storage", this._handleStorageSync);
      this._handleStorageSync = null;
    }

    if (!this._mediaQuery || !this._handleViewportChange) return;

    if (typeof this._mediaQuery.removeEventListener === "function") {
      this._mediaQuery.removeEventListener("change", this._handleViewportChange);
    } else if (typeof this._mediaQuery.removeListener === "function") {
      this._mediaQuery.removeListener(this._handleViewportChange);
    }
  }
});

window.trifleChatShellHeader = () => ({
  moreOpen: false,
  chatMode: readChatShellMode(),
  _handleChatModeChanged: null,

  init() {
    this._handleChatModeChanged = (event) => {
      const detail = event && event.detail ? event.detail : {};
      this.chatMode = CHAT_SHELL_MODES.has(detail.mode) ? detail.mode : readChatShellMode();
    };

    window.addEventListener(CHAT_SHELL_MODE_CHANGED_EVENT, this._handleChatModeChanged);
    this.chatMode = readChatShellMode();
  },

  setMode(mode) {
    if (!CHAT_SHELL_MODES.has(mode)) return;
    this.chatMode = mode;
    window.dispatchEvent(
      new CustomEvent(CHAT_SHELL_SET_MODE_EVENT, {
        detail: { mode }
      })
    );
  },

  destroy() {
    if (this._handleChatModeChanged) {
      window.removeEventListener(CHAT_SHELL_MODE_CHANGED_EVENT, this._handleChatModeChanged);
      this._handleChatModeChanged = null;
    }
  }
});

};

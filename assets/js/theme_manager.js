export class ThemeManager {
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
    const preload = window.__TRIFLE_THEME_PRELOAD__ || {};
    const currentTheme = themePreference || preload.pref || body.getAttribute('data-theme') || 'system';
    
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
    if (window.__trifleThemeLocked) return;
    const body = document.body;
    const preload = window.__TRIFLE_THEME_PRELOAD__ || {};
    const currentTheme = themePreference || preload.pref || body.getAttribute('data-theme') || 'system';
    const shouldUseDark = this.shouldUseDarkTheme(currentTheme);
    const resolvedTheme = shouldUseDark ? 'dark' : 'light';
    const previousTheme = this._resolvedTheme;

    // Update data-theme attribute if preference was provided
    if (themePreference) {
      body.setAttribute('data-theme', themePreference);
    } else if (body.getAttribute('data-theme') !== currentTheme) {
      body.setAttribute('data-theme', currentTheme);
    }
    
    // Remove existing theme classes
    body.classList.remove('dark');
    document.documentElement.classList.remove('dark');

    // Apply theme classes based on user preference
    if (shouldUseDark) {
      body.classList.add('dark');
      document.documentElement.classList.add('dark');
    }

    this._resolvedTheme = resolvedTheme;
    try {
      if (window.localStorage) {
        window.localStorage.setItem('trifle:theme-pref', currentTheme);
        window.localStorage.setItem('trifle:resolved-theme', resolvedTheme);
      }
    } catch (_) {}

    window.__TRIFLE_THEME_PRELOAD__ = { pref: currentTheme, resolved: resolvedTheme };
    if (previousTheme !== resolvedTheme) {
      try {
        window.dispatchEvent(new CustomEvent('trifle:theme-changed', { detail: { theme: resolvedTheme } }));
      } catch (_) {}
    }
  }

}

export const initializeThemeManager = () => {
  const createThemeManager = () => {
    window.themeManager = new ThemeManager();
  };

  if (document.readyState !== 'loading') {
    createThemeManager();
  } else {
    document.addEventListener('DOMContentLoaded', createThemeManager);
  }
};

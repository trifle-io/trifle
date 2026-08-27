defmodule TrifleWeb.LayoutPreloads do
  use Phoenix.Component

  def preload_scripts(assigns) do
    ~H"""
    <script>
      (function () {
        try {
          var storage = window.localStorage;
          var storedPref = storage ? storage.getItem('trifle:theme-pref') : null;
          var storedResolved = storage ? storage.getItem('trifle:resolved-theme') : null;
          var pref = storedPref || 'system';
          var isDark;

          if (pref === 'dark') {
            isDark = true;
          } else if (pref === 'light') {
            isDark = false;
          } else {
            isDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
          }

          if (isDark) {
            document.documentElement.classList.add('dark');
          } else {
            document.documentElement.classList.remove('dark');
          }

          window.__TRIFLE_THEME_PRELOAD__ = {
            pref: pref,
            resolved: isDark ? 'dark' : 'light'
          };
        } catch (error) {
          var fallbackDark = false;
          try {
            fallbackDark = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
          } catch (_) {
            fallbackDark = false;
          }
          if (fallbackDark) {
            document.documentElement.classList.add('dark');
          } else {
            document.documentElement.classList.remove('dark');
          }
          window.__TRIFLE_THEME_PRELOAD__ = { pref: 'system', resolved: fallbackDark ? 'dark' : 'light' };
        }
      })();
    </script>
    <script>
      (function () {
        var clientState = null;
        var adminState = null;

        try {
          var storage = window.localStorage;
          var storedClient = storage ? storage.getItem('trifle:client-sidebar') : null;
          var storedAdmin = storage ? storage.getItem('trifle:admin-sidebar') : null;

          if (storedClient === 'collapsed' || storedClient === 'expanded') {
            clientState = storedClient;
          }

          if (storedAdmin === 'collapsed' || storedAdmin === 'expanded') {
            adminState = storedAdmin;
          }
        } catch (_) {}

        var preload = {};

        if (clientState === 'collapsed' || clientState === 'expanded') {
          document.documentElement.dataset.trifleClientSidebar = clientState;
          preload.client = clientState;
        }

        if (adminState === 'collapsed' || adminState === 'expanded') {
          document.documentElement.dataset.trifleAdminSidebar = adminState;
          preload.admin = adminState;
        }

        window.__TRIFLE_SIDEBAR_PRELOAD__ = preload;
      })();
    </script>
    <script>
      (function () {
        var storageKey = 'dashboard_group_collapsed_default';
        var styleId = 'trifle-dashboard-groups-preload';
        var ids = [];

        try {
          var storage = window.localStorage;
          var stored = storage ? storage.getItem(storageKey) : null;
          var collapsed = stored ? JSON.parse(stored) : {};

          ids = Object.keys(collapsed || {}).filter(function (id) {
            return collapsed[id] && /^[A-Za-z0-9_-]+$/.test(id);
          });
        } catch (_) {
          ids = [];
        }

        window.__TRIFLE_DASHBOARD_GROUPS_PRELOAD__ = {
          storageKey: storageKey,
          ids: ids
        };

        if (ids.length === 0) return;

        var style = document.createElement('style');
        style.id = styleId;
        style.textContent = ids.map(function (id) {
          return '[data-dashboard-group-content="' + id + '"]{display:none!important;}' +
            '[data-dashboard-group-expanded-icon="' + id + '"]{display:none!important;}' +
            '[data-dashboard-group-collapsed-icon="' + id + '"]{display:block!important;}';
        }).join('');
        document.head.appendChild(style);
      })();
    </script>
    """
  end
end

// Read-only grids can keep their existing chart visible during same-page URL
// changes. Their widget data hooks still handle actual payload/loading updates.
export const createGridPageLoadingHandlers = (hook, requestFrame) => {
  const shouldHide = (kind) => !kind || kind === 'redirect' ||
    (kind === 'patch' && hook.el?.dataset.hideOnPatch !== 'false');

  return {
    start(event) {
      const kind = event?.detail?.kind;
      if (!shouldHide(kind)) return;
      hook._suppressSave = true;
      hook._gridHiddenForLoading = true;
      if (hook.el) {
        hook.el.classList.remove('opacity-100');
        hook.el.classList.add('opacity-0', 'pointer-events-none');
      }
    },

    stop(event) {
      const kind = event?.detail?.kind;
      if (!shouldHide(kind) && !hook._gridHiddenForLoading) return;
      hook._suppressSave = false;
      if (hook.el) {
        hook.el.classList.remove('opacity-0', 'pointer-events-none');
        hook.el.classList.add('opacity-100');
      }
      hook._gridHiddenForLoading = false;
      requestFrame(() => {
        try {
          hook.syncServerRenderedItems();
          if (typeof hook._applyResponsiveGrid === 'function') {
            hook._applyResponsiveGrid();
          }
          hook._scheduleDeferredResize();
        } catch (_) {}
      });
    }
  };
};

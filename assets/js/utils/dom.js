export const parseJsonSafe = (value) => {
  if (value == null || value === '') return null;
  try {
    return JSON.parse(value);
  } catch (_) {
    return null;
  }
};

export const setHidden = (el, hidden) => {
  if (!el) return;
  if (hidden) {
    el.classList.add('hidden');
  } else {
    el.classList.remove('hidden');
  }
};

export const findDashboardGridHook = (el) => {
  if (!el) return null;
  const gridId = el.dataset && el.dataset.gridId;
  const direct = gridId ? document.getElementById(gridId) : null;
  if (direct && direct.__dashboardGrid) return direct.__dashboardGrid;
  const gridEl = el.closest('#dashboard-grid') || el.closest('.grid-stack');
  if (gridEl && gridEl.__dashboardGrid) return gridEl.__dashboardGrid;
  return null;
};

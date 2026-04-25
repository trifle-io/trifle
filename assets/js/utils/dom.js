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
  if (gridId) {
    const direct = document.getElementById(gridId);
    if (direct && direct.__dashboardGrid) return direct.__dashboardGrid;
  }
  const gridEl = el.closest('#dashboard-grid') || el.closest('.grid-stack');
  if (gridEl && gridEl.__dashboardGrid) return gridEl.__dashboardGrid;
  if (gridId) {
    const fallback = document.querySelector(`#${gridId}`);
    if (fallback && fallback.__dashboardGrid) return fallback.__dashboardGrid;
  }
  return null;
};

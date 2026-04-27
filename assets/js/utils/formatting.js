export const formatCompactNumber = (value) => {
  if (value === null || value === undefined || value === '') return '0';
  const n = Number(value);
  if (!Number.isFinite(n)) return String(value);
  const abs = Math.abs(n);
  if (abs >= 1_000) {
    const units = ['', 'K', 'M', 'B', 'T'];
    let unitIndex = 0;
    let scaled = abs;
    while (scaled >= 1000 && unitIndex < units.length - 1) {
      scaled /= 1000;
      unitIndex += 1;
    }
    const decimals = scaled < 10 ? 2 : scaled < 100 ? 1 : 0;
    const formatted = scaled
      .toFixed(decimals)
      .replace(/\.0+$/, '')
      .replace(/(\.\d*?[1-9])0+$/, '$1');
    return `${n < 0 ? '-' : ''}${formatted}${units[unitIndex]}`;
  }

  const decimals = abs < 1 ? 2 : Number.isInteger(n) ? 0 : abs < 10 ? 2 : 1;
  return n
    .toFixed(decimals)
    .replace(/\.0+$/, '')
    .replace(/(\.\d*?[1-9])0+$/, '$1');
};

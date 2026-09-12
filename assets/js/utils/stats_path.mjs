// Public Stats path syntax. Storage percent encoding belongs to the driver.
export function parsePath(path, syntax = 'escaped') {
  if (syntax !== 'escaped' && syntax !== 'legacy') throw new Error('Unknown path syntax');
  if (path === '') return [];
  if (syntax === 'legacy') {
    return path.split('.').map(value => ({
      value, wildcard: value === '*', unescaped_star: value.includes('*'),
    }));
  }

  const segments = [];
  let value = '';
  let star = false;
  const finish = () => {
    segments.push({value, wildcard: value === '*' && star, unescaped_star: star});
    value = '';
    star = false;
  };

  for (let index = 0; index < path.length; index += 1) {
    const char = path[index];
    if (char === '\\' && index + 1 < path.length && ['.', '*', '\\'].includes(path[index + 1])) {
      index += 1;
      value += path[index];
    } else if (char === '.') {
      finish();
    } else {
      value += char;
      star ||= char === '*';
    }
  }
  finish();
  return segments;
}

export function escapeSegment(value) {
  return String(value).replace(/[\\.*]/g, char => `\\${char}`);
}

// Names collected from actual data are always literal, including '*'.
export function joinPath(segments) {
  return segments.map(escapeSegment).join('.');
}

export function renderPath(segments) {
  return segments.map(segment => segment.wildcard ? '*' : escapeSegment(segment.value)).join('.');
}

export function pathHasWildcard(path, syntax = 'escaped') {
  return parsePath(path, syntax).some(segment => segment.unescaped_star);
}

export function pathSegments(path) {
  return parsePath(path).map(segment => segment.value);
}

// Preserve the exact text for editable-input overlays (and caret alignment).
export function pathTextSegments(path) {
  if (path === '') return [];
  const result = [];
  let start = 0;
  for (let index = 0; index < path.length; index += 1) {
    if (path[index] === '\\' && ['.', '*', '\\'].includes(path[index + 1])) {
      index += 1;
    } else if (path[index] === '.') {
      result.push(path.slice(start, index));
      start = index + 1;
    }
  }
  result.push(path.slice(start));
  return result;
}

export function siblingSegments(paths, prefix) {
  return [...new Set(paths.filter(path => typeof path === 'string')
    .map(pathSegments)
    .filter(parts => parts.length > prefix.length && prefix.every((part, index) => part === parts[index]))
    .map(parts => parts[prefix.length]))];
}

const SAFE_HTML_ALLOWED_TAGS = new Set([
  'a', 'b', 'blockquote', 'br', 'code', 'div', 'em', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
  'hr', 'i', 'li', 'ol', 'p', 'pre', 's', 'span', 'strong', 'table', 'tbody', 'td', 'th',
  'thead', 'tr', 'u', 'ul'
]);
const SAFE_HTML_DROP_TAGS = new Set([
  'script', 'style', 'iframe', 'object', 'embed', 'link', 'meta', 'base', 'form', 'input',
  'button', 'textarea', 'select', 'option', 'svg', 'math'
]);
const SAFE_HTML_GLOBAL_ATTRS = new Set(['class', 'title', 'role']);
const SAFE_HTML_TAG_ATTRS = {
  a: new Set(['href', 'target', 'rel']),
  th: new Set(['colspan', 'rowspan', 'scope']),
  td: new Set(['colspan', 'rowspan'])
};

const isSafeHtmlHref = (value) => {
  const href = String(value || '').trim();
  if (href === '') return false;
  if (href.startsWith('#')) return true;
  if (href.startsWith('/')) return !href.startsWith('//');

  try {
    const baseOrigin =
      window.location && window.location.origin ? window.location.origin : 'http://localhost';
    const parsed = new URL(href, baseOrigin);
    const protocol = String(parsed.protocol || '').toLowerCase();
    return protocol === 'http:' || protocol === 'https:' || protocol === 'mailto:' || protocol === 'tel:';
  } catch (_) {
    return false;
  }
};

export const sanitizeRichHtml = (rawHtml) => {
  if (typeof rawHtml !== 'string' || rawHtml.trim() === '') return '';
  const template = document.createElement('template');
  template.innerHTML = rawHtml;

  const sanitizeAttrs = (element, tag) => {
    const tagAllowedAttrs = SAFE_HTML_TAG_ATTRS[tag] || new Set();

    Array.from(element.attributes).forEach((attr) => {
      const name = String(attr.name || '').toLowerCase();
      const value = String(attr.value || '');
      const isAria = name.startsWith('aria-');
      const allowed = isAria || SAFE_HTML_GLOBAL_ATTRS.has(name) || tagAllowedAttrs.has(name);

      if (
        !allowed ||
        name.startsWith('on') ||
        name === 'style' ||
        name === 'srcdoc' ||
        name.includes(':')
      ) {
        element.removeAttribute(attr.name);
        return;
      }

      if (tag === 'a' && name === 'href') {
        const href = value.trim();
        if (!isSafeHtmlHref(href)) {
          element.removeAttribute(attr.name);
        } else {
          element.setAttribute('href', href);
        }
      }

      if (tag === 'a' && name === 'target') {
        const target = value.trim().toLowerCase();
        if (!['_blank', '_self', '_parent', '_top'].includes(target)) {
          element.removeAttribute(attr.name);
        } else {
          element.setAttribute('target', target);
        }
      }

      if ((name === 'colspan' || name === 'rowspan') && !/^\d+$/.test(value.trim())) {
        element.removeAttribute(attr.name);
      }
    });

    if (tag === 'a' && String(element.getAttribute('target') || '').toLowerCase() === '_blank') {
      const relTokens = new Set(
        String(element.getAttribute('rel') || '')
          .toLowerCase()
          .split(/\s+/)
          .filter(Boolean)
      );

      ['noopener', 'noreferrer', 'nofollow'].forEach((token) => {
        relTokens.add(token);
      });
      element.setAttribute('rel', Array.from(relTokens).sort().join(' '));
    }
  };

  const sanitizeNode = (node) => {
    if (!node) return;

    if (node.nodeType === 8) {
      node.remove();
      return;
    }

    if (node.nodeType !== 1) return;

    const tag = String(node.tagName || '').toLowerCase();
    if (SAFE_HTML_DROP_TAGS.has(tag)) {
      node.remove();
      return;
    }

    Array.from(node.childNodes).forEach((child) => {
      sanitizeNode(child);
    });

    if (!SAFE_HTML_ALLOWED_TAGS.has(tag)) {
      node.replaceWith(...Array.from(node.childNodes));
      return;
    }

    sanitizeAttrs(node, tag);
  };

  Array.from(template.content.childNodes).forEach((node) => {
    sanitizeNode(node);
  });
  return template.innerHTML;
};

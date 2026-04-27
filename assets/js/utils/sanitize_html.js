import DOMPurify from 'dompurify';

export const sanitizeRichHtml = (rawHtml) => {
  if (typeof rawHtml !== 'string' || rawHtml.trim() === '') return '';

  const safeHtml = DOMPurify.sanitize(rawHtml, {
    ALLOWED_TAGS: [
      'a', 'b', 'blockquote', 'br', 'code', 'div', 'em', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
      'hr', 'i', 'li', 'ol', 'p', 'pre', 's', 'span', 'strong', 'table', 'tbody', 'td', 'th',
      'thead', 'tr', 'u', 'ul'
    ],
    ALLOWED_ATTR: ['aria-*', 'class', 'colspan', 'href', 'rel', 'role', 'rowspan', 'scope', 'target', 'title']
  });

  const template = document.createElement('template');
  template.innerHTML = safeHtml;

  template.content.querySelectorAll('a').forEach((link) => {
    link.setAttribute('target', '_blank');
    link.setAttribute('rel', 'noopener noreferrer nofollow');
  });

  return template.innerHTML;
};

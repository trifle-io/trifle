export const createDashboardGridTextRendererMethods = ({ sanitizeRichHtml }) => ({
  _render_text(items) {
    if (!Array.isArray(items)) return;
    const cloned = this._deepClone(items);
    this._lastText = cloned;

    const activeIds = new Set(cloned.map((it) => String(it.id)));

    this.el.querySelectorAll('.grid-stack-item-content[data-text-widget="1"]').forEach((content) => {
      const parent = content.closest('.grid-stack-item');
      const id = parent && parent.getAttribute('gs-id');
      if (!activeIds.has(id)) {
        this._resetTextWidget(content);
      }
    });

    cloned.forEach((it) => {
      const id = String(it.id);
      const item = this.el.querySelector(`.grid-stack-item[gs-id="${id}"]`);
      if (!item) return;

      const content = item.querySelector('.grid-stack-item-content');
      const body = item.querySelector('.grid-widget-body');
      if (!content || !body) return;

      content.dataset.textWidget = '1';
      content.dataset.widgetTitle = it.title || '';
      content.style.paddingTop = '';

      const bg = typeof it.background_color === 'string' ? it.background_color : '';
      const fg = typeof it.text_color === 'string' ? it.text_color : '';

      const colorId = (it.color_id || 'default').toLowerCase();
      const hasCustomColor = colorId !== 'default' && bg && this._isHexColor(bg);

      if (hasCustomColor) {
        content.style.backgroundColor = bg;
        content.style.color = fg || '';
        const isDark = this._isColorDark(bg);
        content.style.borderColor = isDark ? 'rgba(255,255,255,0.12)' : 'rgba(15,23,42,0.08)';
        content.dataset.customBg = '1';
      } else {
        content.style.backgroundColor = '';
        content.style.color = '';
        content.style.borderColor = '';
        delete content.dataset.customBg;
      }

      const header = content.querySelector('.grid-widget-header');
      if (header) {
        header.classList.add('text-widget-header');
        header.style.borderColor = 'transparent';
        header.style.marginBottom = '0';
        header.style.paddingBottom = '0';
        header.style.minHeight = '1.75rem';
      }

      const titleBar = content.querySelector('.grid-widget-title');
      if (titleBar) {
        const originalTitle = it.title || '';
        titleBar.dataset.originalTitle = originalTitle;
        titleBar.textContent = '\u00A0';
        titleBar.setAttribute('aria-hidden', 'true');
        titleBar.style.opacity = '0';
        titleBar.style.pointerEvents = 'none';
        titleBar.style.minHeight = '1.25rem';
        titleBar.style.display = 'block';
      }

      body.className = 'grid-widget-body flex-1 flex text-widget-body flex-col gap-2 px-4 pt-0 pb-4';
      body.dataset.textSubtype = it.subtype || 'header';
      body.style.justifyContent = 'center';
      body.style.alignItems = 'center';
      body.style.textAlign = 'center';
      body.style.overflowY = 'visible';
      body.style.paddingTop = '';
      body.style.paddingBottom = '';

      if ((it.subtype || 'header') === 'html') {
        body.style.justifyContent = 'flex-start';
        body.style.alignItems = 'stretch';
        body.style.textAlign = 'left';
        body.style.overflowY = 'auto';

        const raw = typeof it.payload === 'string' ? it.payload : '';
        const sanitizedHtml = sanitizeRichHtml(raw);
        const finalHtml =
          sanitizedHtml && sanitizedHtml.trim().length
            ? sanitizedHtml
            : '<div class="text-xs opacity-60 italic">No HTML content</div>';
        body.innerHTML = `<div class="text-widget-html w-full leading-relaxed">${finalHtml}</div>`;
      } else {
        const align = (it.alignment || 'center').toLowerCase();
        const alignItems = align === 'left' ? 'flex-start' : (align === 'right' ? 'flex-end' : 'center');
        const textAlign = align === 'left' ? 'left' : (align === 'right' ? 'right' : 'center');
        body.style.alignItems = alignItems;
        body.style.textAlign = textAlign;

        const sizeClass = (() => {
          switch (it.title_size) {
            case 'small': return 'text-2xl';
            case 'medium': return 'text-3xl';
            default: return 'text-4xl';
          }
        })();

        const title = this.escapeHtml(it.title || '');
        const subtitleRaw = typeof it.subtitle === 'string' ? it.subtitle.trim() : '';
        const subtitle = subtitleRaw ? `<div class="text-widget-subtitle text-base leading-relaxed opacity-80">${this.escapeHtml(subtitleRaw).replace(/\r?\n/g, '<br />')}</div>` : '';

        body.innerHTML = `<div class="text-widget-header-content w-full flex flex-col gap-2"><div class="text-widget-title font-semibold ${sizeClass} leading-tight">${title || '&nbsp;'}</div>${subtitle}</div>`;
      }
    });

    if (this._seen) this._seen.text = true;
    if (typeof this._scheduleReadyMark === 'function') this._scheduleReadyMark();
  },

});

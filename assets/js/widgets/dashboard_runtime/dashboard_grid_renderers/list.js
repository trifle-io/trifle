export const createDashboardGridListRendererMethods = () => ({
  _render_list(items) {
    if (!Array.isArray(items)) return;
    const cloned = this._deepClone(items);
    this._lastList = cloned;

    const activeIds = new Set(cloned.map((it) => String(it.id)));

    this.el
      .querySelectorAll('.grid-stack-item-content[data-list-widget="1"]')
      .forEach((content) => {
        const parent = content.closest('.grid-stack-item');
        const id = parent && parent.getAttribute('gs-id');
        if (!activeIds.has(id)) {
          this._resetListWidget(content);
        }
      });

    cloned.forEach((dataset) => {
      if (!dataset) return;
      const id = String(dataset.id);
      const item = this.el.querySelector(`.grid-stack-item[gs-id="${id}"]`);
      if (!item) return;

      const content = item.querySelector('.grid-stack-item-content');
      const body = item.querySelector('.grid-widget-body');
      if (!content || !body) return;

      content.dataset.listWidget = '1';
      this._render_list_body(body, dataset);
    });

    if (this._seen) this._seen.list = true;
    if (typeof this._scheduleReadyMark === 'function') this._scheduleReadyMark();
  },

  _resetTextWidget(content) {
    if (!content) return;
    delete content.dataset.textWidget;
    delete content.dataset.widgetTitle;
    content.style.paddingTop = '';
    content.style.backgroundColor = '';
    content.style.color = '';
    content.style.borderColor = '';
    delete content.dataset.customBg;

    const header = content.querySelector('.grid-widget-header');
    if (header) {
      header.classList.remove('text-widget-header');
      header.style.borderColor = '';
      header.style.marginBottom = '';
      header.style.paddingBottom = '';
      header.style.minHeight = '';
    }

    const titleBar = content.querySelector('.grid-widget-title');
    if (titleBar) {
      const originalTitle = titleBar.dataset.originalTitle;
      if (originalTitle !== undefined) {
        titleBar.textContent = originalTitle;
      }
      delete titleBar.dataset.originalTitle;
      titleBar.removeAttribute('aria-hidden');
      titleBar.style.opacity = '';
      titleBar.style.pointerEvents = '';
      titleBar.style.minHeight = '';
      titleBar.style.display = '';
    }

    const body = content.querySelector('.grid-widget-body');
    if (body) {
      delete body.dataset.textSubtype;
      body.className = 'grid-widget-body flex-1 flex items-center justify-center text-sm text-gray-500 dark:text-slate-400';
      body.style.textAlign = '';
      body.style.alignItems = '';
      body.style.justifyContent = '';
      body.style.overflowY = '';
      body.style.paddingTop = '';
      body.style.paddingBottom = '';
      body.innerHTML = 'Chart is coming soon';
    }
  },

  _resetListWidget(content) {
    if (!content) return;
    delete content.dataset.listWidget;
    const body = content.querySelector('.grid-widget-body');
    if (!body) return;
    body.className = 'grid-widget-body flex-1 flex flex-col min-h-0 gap-0';
    const empty = document.createElement('div');
    empty.className = 'flex-1 flex items-center justify-center text-sm text-gray-500 dark:text-slate-400 px-4 text-center';
    empty.textContent = 'No data available yet.';
    body.innerHTML = '';
    body.appendChild(empty);
  },

  _render_list_body(body, dataset) {
    if (!body) return;
    body.className = 'grid-widget-body flex-1 flex flex-col min-h-0 gap-0';
    const items = Array.isArray(dataset.items) ? dataset.items : [];
    if (!items.length) {
      const emptyMessage =
        typeof dataset.empty_message === 'string' && dataset.empty_message.trim() !== ''
          ? dataset.empty_message
          : 'No data available yet.';
      const empty = document.createElement('div');
      empty.className = 'flex-1 flex items-center justify-center text-sm text-gray-500 dark:text-slate-400 px-4 text-center';
      empty.textContent = emptyMessage;
      body.innerHTML = '';
      body.appendChild(empty);
      return;
    }

    const selectedPath = typeof dataset.selected_path === 'string' && dataset.selected_path.trim() !== '' ? dataset.selected_path.trim() : null;
    const rawSelectedKey = typeof dataset.selected_key === 'string' ? dataset.selected_key : '';
    const selectedKey = rawSelectedKey.trim() !== '' ? rawSelectedKey : null;
    const selectEvent = typeof dataset.select_event === 'string' && dataset.select_event.trim() !== '' ? dataset.select_event.trim() : null;
    const deselectEvent = typeof dataset.deselect_event === 'string' && dataset.deselect_event.trim() !== '' ? dataset.deselect_event.trim() : null;
    const interactive = Boolean(selectEvent);

    if (interactive) {
      this._currentListSelectionPath = selectedPath;
      this._currentListSelectionKey = selectedKey;
    } else {
      this._currentListSelectionPath = null;
      this._currentListSelectionKey = null;
    }

    const list = document.createElement('ul');
    list.className = 'flex-1 divide-y divide-gray-100/80 dark:divide-slate-500/60 overflow-auto list-none m-0 p-0';

    items.forEach((entry, index) => {
      if (!entry) return;
      const li = document.createElement('li');
      li.className = 'first:pt-0 last:pb-0';

      const wrapperTag = interactive ? 'button' : 'div';
      const wrapper = document.createElement(wrapperTag);
      if (interactive) {
        wrapper.type = 'button';
        wrapper.setAttribute('data-role', 'list-selectable');
      }

      const entryPath = typeof entry.path === 'string' ? entry.path : '';
      const rawLabel = typeof entry.label === 'string' ? entry.label : '';
      const trimmedLabel = rawLabel.trim();
      const labelText = trimmedLabel !== '' ? rawLabel : (entryPath || `Item ${index + 1}`);
      const payloadKey = trimmedLabel !== '' ? rawLabel : entryPath || labelText;
      const isSelected =
        (selectedPath && entryPath === selectedPath) ||
        (selectedKey && rawLabel === selectedKey);

      const baseClasses = [
        'flex',
        'items-center',
        'justify-between',
        'gap-2.5',
        'border',
        'border-transparent',
        'px-2.5',
        'py-1.5',
        'transition-colors',
        'w-full',
        'list-widget-row'
      ];

      if (isSelected && interactive) {
        baseClasses.push('bg-teal-50', 'dark:bg-teal-900/30', 'border-teal-100', 'dark:border-teal-800');
      }

      if (interactive) {
        baseClasses.push('cursor-pointer', 'focus-visible:outline-none', 'focus-visible:ring-2', 'focus-visible:ring-teal-500/60');
      }

      wrapper.className = baseClasses.join(' ');
      if (interactive) {
        wrapper.setAttribute('aria-pressed', isSelected ? 'true' : 'false');
      }

      const row = document.createElement('div');
      row.className = 'w-full flex items-center justify-between gap-2.5';

      const left = document.createElement('div');
      left.className = `flex items-center ${interactive ? 'gap-2.5' : 'gap-2'} min-w-0`;

      const color =
        typeof entry.color === 'string' && entry.color.trim() !== '' ? entry.color : '#14b8a6';

      if (interactive) {
        const indicator = this._buildListSelectionIcon(isSelected);
        left.appendChild(indicator);
      } else {
        left.appendChild(this._buildListColorChip(color));
      }

      const label = document.createElement('span');
      label.className = 'text-sm font-mono truncate';
      label.style.color = color;
      label.textContent = labelText;
      label.title = labelText;

      left.appendChild(label);

      const badge = document.createElement('span');
      badge.className = 'inline-flex items-center rounded-md border px-2 py-0.5 text-xs font-semibold';
      badge.style.color = color;
      const bgColor = this._colorWithAlpha(color, '15');
      const borderColor = this._colorWithAlpha(color, '40');
      if (bgColor) badge.style.backgroundColor = bgColor;
      if (borderColor) badge.style.borderColor = borderColor;
      const valueText =
        entry.formatted_value ||
        (typeof entry.value === 'number' ? String(entry.value) : '0');
      badge.textContent = valueText;

      row.appendChild(left);
      row.appendChild(badge);
      wrapper.appendChild(row);
      li.appendChild(wrapper);
      list.appendChild(li);

      if (interactive) {
        wrapper.addEventListener('click', (event) => {
          event.preventDefault();
          event.stopPropagation();
          const keyToSend = payloadKey;
          if (!keyToSend || !selectEvent) return;
          const currentlySelected =
            (this._currentListSelectionPath && entryPath === this._currentListSelectionPath) ||
            (this._currentListSelectionKey && keyToSend === this._currentListSelectionKey) ||
            isSelected;

          if (currentlySelected && deselectEvent) {
            this.pushEvent(deselectEvent, {});
            this._currentListSelectionKey = null;
            this._currentListSelectionPath = null;
          } else {
            this.pushEvent(selectEvent, { key: keyToSend });
            this._currentListSelectionKey = keyToSend;
            this._currentListSelectionPath = entryPath || null;
          }
        });
      }
    });

    body.innerHTML = '';
    body.appendChild(list);
  },

  _isColorDark(color) {
    if (!color || typeof color !== 'string') return false;
    const hexMatch = color.trim().match(/^#?([0-9a-f]{6})$/i);
    if (!hexMatch) return false;
    const hex = hexMatch[1];
    const r = parseInt(hex.slice(0, 2), 16);
    const g = parseInt(hex.slice(2, 4), 16);
    const b = parseInt(hex.slice(4, 6), 16);
    const luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
    return Number.isFinite(luminance) ? luminance < 0.5 : false;
  },

  _isHexColor(color) {
    if (!color || typeof color !== 'string') return false;
    return /^#?[0-9a-f]{3}([0-9a-f]{3})?$/i.test(color.trim());
  },

  _colorWithAlpha(color, alphaHex) {
    if (!color || typeof color !== 'string') return '';
    const trimmed = color.trim();
    const match = trimmed.match(/^#([0-9a-f]{6})$/i);
    if (match) {
      return `${trimmed}${alphaHex}`;
    }
    return trimmed;
  },

  _buildListColorChip(color) {
    const span = document.createElement('span');
    span.className = 'inline-flex h-2.5 w-2.5 rounded-full flex-shrink-0';
    if (color && typeof color === 'string') {
      span.style.backgroundColor = color;
    }
    span.setAttribute('aria-hidden', 'true');
    return span;
  },

  _buildListSelectionIcon(selected) {
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('viewBox', '0 0 24 24');
    svg.setAttribute('fill', 'none');
    svg.setAttribute('stroke-width', '1.5');
    svg.setAttribute('stroke', 'currentColor');
    svg.classList.add('h-5', 'w-5', 'flex-shrink-0');
    svg.setAttribute('aria-hidden', 'true');

    if (selected) {
      svg.classList.add('text-teal-600');
    } else {
      svg.classList.add('text-gray-400', 'dark:text-slate-400');
    }

    const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
    path.setAttribute('stroke-linecap', 'round');
    path.setAttribute('stroke-linejoin', 'round');
    path.setAttribute('d', 'M21 12a9 9 0 11-18 0 9 9 0 0118 0z');
    svg.appendChild(path);

    if (selected) {
      const circle = document.createElementNS('http://www.w3.org/2000/svg', 'circle');
      circle.setAttribute('cx', '12');
      circle.setAttribute('cy', '12');
      circle.setAttribute('r', '4');
      circle.setAttribute('fill', 'currentColor');
      svg.appendChild(circle);
    }

    return svg;
  },

});

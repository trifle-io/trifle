export const registerPhantomRowsHook = (Hooks, deps = {}) => {
Hooks.PhantomRows = {
  mounted() {
    this._phantomRowsTimer = null;
    this.debounceAddPhantomRows = () => {
      if (this._phantomRowsTimer) clearTimeout(this._phantomRowsTimer);
      this._phantomRowsTimer = setTimeout(() => {
        this._phantomRowsTimer = null;
        this.addPhantomRows();
      }, 80);
    };

    window.addEventListener('resize', this.debounceAddPhantomRows);
    window.addEventListener('trifle:theme-changed', this.debounceAddPhantomRows);
    window.addEventListener('trifle:sidebar-resize', this.debounceAddPhantomRows);

    if (typeof MutationObserver !== 'undefined') {
      this._themeObserver = new MutationObserver((mutations) => {
        const hasThemeClassChange = mutations.some((mutation) => mutation.attributeName === 'class');
        if (hasThemeClassChange) this.debounceAddPhantomRows();
      });
      this._themeObserver.observe(document.documentElement, { attributes: true, attributeFilter: ['class'] });
    }

    this.addPhantomRows();
  },
  
  updated() {
    this.addPhantomRows();
  },

  destroyed() {
    if (this.debounceAddPhantomRows) {
      window.removeEventListener('resize', this.debounceAddPhantomRows);
      window.removeEventListener('trifle:theme-changed', this.debounceAddPhantomRows);
      window.removeEventListener('trifle:sidebar-resize', this.debounceAddPhantomRows);
    }
    if (this._themeObserver) {
      this._themeObserver.disconnect();
      this._themeObserver = null;
    }
    if (this._phantomRowsTimer) {
      clearTimeout(this._phantomRowsTimer);
      this._phantomRowsTimer = null;
    }
  },
  
  addPhantomRows() {
    // Remove existing phantom rows
    this.clearPhantomRows();
    
    const container = this.el;
    const scrollContainer = container.querySelector('[data-role="table-scroll"]');
    const table = scrollContainer ? scrollContainer.querySelector('[data-role="data-table"]') : null;
    if (!table || !scrollContainer) return;
    
    // Fix border width to match table width
    const borderDiv = scrollContainer.querySelector('[data-role="table-border"]');
    if (borderDiv) {
      const tableWidth = table.scrollWidth;
      borderDiv.style.width = `${tableWidth}px`;
      borderDiv.style.minWidth = '100%';
    }
    
    // Get dimensions
    const clientHeight = scrollContainer.clientHeight;
    
    // Calculate if we need phantom rows (table + borders is shorter than visible area)
    const borderHeight = borderDiv ? borderDiv.offsetHeight : 0;
    const totalContentHeight = table.offsetHeight + borderHeight;
    
    if (totalContentHeight < clientHeight) {
      const remainingSpace = clientHeight - totalContentHeight;
      this.createPhantomRowsElement(remainingSpace, scrollContainer);
    }
  },
  
  createPhantomRowsElement(height, scrollContainer) {
    const table = scrollContainer.querySelector('[data-role="data-table"]');
    const tableWidth = table ? table.scrollWidth : scrollContainer.scrollWidth;
    
    const phantomContainer = document.createElement('div');
    phantomContainer.className = 'phantom-rows-js';
    
    // Create horizontal stripes background
    const isDark = document.documentElement.classList.contains('dark');
    const stripeColor = isDark ? 'rgb(71 85 105)' : 'rgb(229 231 235)';
    const bgColor = isDark ? 'transparent' : 'transparent';
    
    phantomContainer.style.cssText = `
      height: ${height}px;
      width: ${tableWidth}px;
      min-width: 100%;
      background-image: repeating-linear-gradient(
        to bottom,
        ${bgColor} 0px,
        ${bgColor} 23px,
        ${stripeColor} 23px,
        ${stripeColor} 24px
      );
      pointer-events: none;
    `;
    
    // Append to scroll container, right after the border
    const borderDiv = scrollContainer.querySelector('[data-role="table-border"]');
    if (borderDiv && borderDiv.nextSibling) {
      scrollContainer.insertBefore(phantomContainer, borderDiv.nextSibling);
    } else {
      scrollContainer.appendChild(phantomContainer);
    }
  },
  
  clearPhantomRows() {
    const existing = this.el.querySelectorAll('.phantom-rows-js');
    existing.forEach(el => el.remove());
  }
}


};

export const registerTableHoverHook = (Hooks) => {
Hooks.TableHover = {
  mounted() {
    this._refreshHighlightColor = () => {
      const value = getComputedStyle(document.documentElement)
        .getPropertyValue('--table-highlight-bg')
        .trim();
      this.highlightColor = value || '#f9fafb';
    };
    this._onThemeChanged = () => {
      this._refreshHighlightColor();
      document.querySelectorAll('.table-highlight').forEach((element) => {
        element.style.backgroundColor = this.highlightColor;
      });
    };
    this._refreshHighlightColor();
    window.addEventListener('trifle:theme-changed', this._onThemeChanged);
    this.initHover();
  },
  
  updated() {
    this.initHover();
  },

  destroyed() {
    this.teardownHover();
    if (this._onThemeChanged) {
      window.removeEventListener('trifle:theme-changed', this._onThemeChanged);
      this._onThemeChanged = null;
    }
  },

  teardownHover() {
    const table = this.el;
    const dataCells = table.querySelectorAll('td[data-row][data-col]');
    dataCells.forEach((cell) => {
      if (!cell._hoverHandlers) return;
      try { cell._hoverHandlers.leave({ target: cell }); } catch (_) {}
      cell.removeEventListener('mouseenter', cell._hoverHandlers.enter);
      cell.removeEventListener('mouseleave', cell._hoverHandlers.leave);
      delete cell._hoverHandlers;
    });
  },
  
  initHover() {
    const table = this.el;
    this.teardownHover();
    
    // Add hover listeners to data cells (not headers or row headers)
    const dataCells = table.querySelectorAll('td[data-row][data-col]');
    
    dataCells.forEach(cell => {
      const onCellMouseEnter = (e) => {
        const row = e.target.dataset.row;
        const col = e.target.dataset.col;
        
        const highlightColor = this.highlightColor || '#f9fafb';
        
        // Highlight current cell's row header with important style
        const rowHeader = table.querySelector(`td[data-row="${row}"]:not([data-col])`);
        if (rowHeader) {
          rowHeader.style.backgroundColor = highlightColor;
          rowHeader.classList.add('table-highlight');
        }
        
        // Highlight current cell's column header
        const colHeader = table.querySelector(`th[data-col="${col}"]`);
        if (colHeader) {
          colHeader.style.backgroundColor = highlightColor;
          colHeader.classList.add('table-highlight');
        }
        
        // Highlight all cells in the same column
        const colCells = table.querySelectorAll(`td[data-col="${col}"]`);
        colCells.forEach(colCell => {
          colCell.style.backgroundColor = highlightColor;
          colCell.classList.add('table-highlight');
        });
        
        // Highlight all cells in the same row
        const rowCells = table.querySelectorAll(`td[data-row="${row}"]`);
        rowCells.forEach(rowCell => {
          rowCell.style.backgroundColor = highlightColor;
          rowCell.classList.add('table-highlight');
        });
      };

      const onCellMouseLeave = () => {
        // Remove all highlights
        table.querySelectorAll('.table-highlight').forEach(el => {
          el.style.backgroundColor = '';
          el.classList.remove('table-highlight');
        });
      };

      cell._hoverHandlers = { enter: onCellMouseEnter, leave: onCellMouseLeave };
      cell.addEventListener('mouseenter', onCellMouseEnter);
      cell.addEventListener('mouseleave', onCellMouseLeave);
    });
  }
}


};

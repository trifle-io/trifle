export const createTraceCopyHook = ({
  getClipboard = () => navigator.clipboard,
  setTimer = setTimeout,
  clearTimer = clearTimeout
} = {}) => ({
  mounted() {
    this.copyButton = this.el.querySelector('[data-copy-button]');
    this.copyState = 'idle';
    this.copyDestroyed = false;
    this.copyClick = () => this.copyLoadedTrace();
    this.copyButton.addEventListener('click', this.copyClick);
    this.renderCopyState();
  },

  updated() {
    this.renderCopyState();
  },

  destroyed() {
    this.copyDestroyed = true;
    this.copyButton.removeEventListener('click', this.copyClick);
    if (this.copyTimer) clearTimer(this.copyTimer);
  },

  async copyLoadedTrace() {
    if (this.copyDestroyed || this.copyState === 'copying' || this.el.dataset.copyReady !== 'true') return;
    const content = this.el.querySelector('[data-copy-text]');
    if (!content) return;
    if (this.copyTimer) clearTimer(this.copyTimer);
    this.copyState = 'copying';
    this.renderCopyState();

    try {
      // Start within the click gesture. No requests, extra parts or attachment reads.
      await getClipboard().writeText(content.textContent);
      if (this.copyDestroyed) return;
      this.copyState = 'copied';
      this.renderCopyState();
      this.copyTimer = setTimer(() => {
        this.copyState = 'idle';
        this.renderCopyState();
      }, 2000);
    } catch (_) {
      if (this.copyDestroyed) return;
      this.copyState = 'error';
      this.renderCopyState();
    }
  },

  renderCopyState() {
    const copied = this.copyState === 'copied';
    const copying = this.copyState === 'copying';
    const failed = this.copyState === 'error';
    const reference = this.el.dataset.copyKind === 'reference';
    const copiedLabel = reference ? 'Trace reference copied' : 'Trace copied';
    const copyingLabel = reference ? 'Copying trace reference…' : 'Copying trace…';
    const idleLabel = reference ? 'Copy trace reference' : 'Copy loaded trace text';
    const label = copied ? copiedLabel : copying ? copyingLabel : idleLabel;
    this.copyButton.disabled = copying || this.el.dataset.copyReady !== 'true';
    this.copyButton.setAttribute('aria-busy', String(copying));
    this.copyButton.setAttribute('aria-label', label);
    this.copyButton.setAttribute('title', label);
    this.copyButton.querySelector('svg').classList.toggle('opacity-0', copied);
    const success = this.el.querySelector('[data-copy-success]');
    success.classList.toggle('hidden', !copied);
    success.classList.toggle('flex', copied);
    const status = this.el.querySelector('[data-copy-status]');
    status.textContent = failed ? 'Could not copy. Check clipboard access and try again.' : copied ? `${copiedLabel}.` : '';
    status.className = failed ? status.dataset.copyErrorClass : 'sr-only';
  }
});

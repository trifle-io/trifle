export const createTraceMediaHook = () => ({
  mounted() {
    this.media = this.el.querySelector('[data-media-element]');
    this.toggle = this.el.querySelector('[data-media-toggle]');
    this.preview = this.el.querySelector('[data-media-preview]');
    this.status = this.el.querySelector('[data-media-status]');
    this.isVideo = this.el.dataset.mediaKind === 'video';
    this.state = 'loading';
    this.onClick = () => this.state === 'closed' || this.state === 'error' ? this.openMedia() : this.closeMedia();
    this.onReady = () => {
      if (this.state !== 'loading') return;
      this.state = 'ready';
      this.renderState();
    };
    this.onError = () => {
      if (!['loading', 'ready'].includes(this.state)) return;
      this.releaseMedia();
      this.state = 'error';
      this.renderState();
    };
    this.readyEvent = this.isVideo ? 'loadedmetadata' : 'load';
    this.media.addEventListener(this.readyEvent, this.onReady);
    this.media.addEventListener('error', this.onError);
    this.toggle.addEventListener('click', this.onClick);
    this.renderState();
    // Media can finish before LiveView mounts the hook. Don't reload it on mount
    // or on unrelated patches (this hook's subtree uses phx-update="ignore").
    if (this.isVideo) {
      if (this.media.error) this.onError();
      else if (this.media.readyState >= 1) this.onReady();
    } else if (this.media.complete) {
      if (this.media.naturalWidth > 0) this.onReady();
      else this.onError();
    }
  },

  openMedia() {
    this.state = 'loading';
    this.renderState();
    // No data URI or LiveView payload: the browser uses the authenticated endpoint.
    if (this.isVideo) this.media.preload = 'metadata';
    this.media.setAttribute('src', this.el.dataset.mediaUrl);
    if (this.isVideo) this.media.load();
  },

  closeMedia() {
    this.state = 'closed';
    this.releaseMedia();
    this.renderState();
  },

  releaseMedia() {
    if (this.isVideo) this.media.pause();
    this.media.removeAttribute('src');
    if (this.isVideo) {
      this.media.preload = 'none';
      this.media.load();
    }
  },

  renderState() {
    const open = ['loading', 'ready'].includes(this.state);
    const kind = this.isVideo ? 'video' : 'image';
    this.toggle.textContent = `${open ? 'Hide' : this.state === 'error' ? 'Retry' : 'Show'} ${kind}`;
    this.toggle.setAttribute('aria-expanded', String(open));
    this.preview.classList.toggle('hidden', !open);
    this.preview.setAttribute('aria-busy', String(this.state === 'loading'));
    this.status.textContent = this.state === 'loading' ? `Loading ${kind}…` :
      this.state === 'error' ? 'Preview unavailable. Retry or download the attachment.' : '';
  },

  destroyed() {
    this.state = 'destroyed';
    this.media.removeEventListener(this.readyEvent, this.onReady);
    this.media.removeEventListener('error', this.onError);
    this.toggle.removeEventListener('click', this.onClick);
    this.releaseMedia();
  }
});

// LiveView emits phx:push for clicks, forms, and hook events. Its completion
// promise resolves after the reply is applied, including large DOM patches.
export const registerLiveLoading = ({topbar, liveSocket, window = globalThis.window}) => {
  const pending = new Map();
  let pageLoading = false;
  let active = false;

  const update = () => {
    // Navigation can remove the source element before its reply arrives.
    for (const [completion, element] of pending) {
      if (!element.isConnected) pending.delete(completion);
    }
    const busy = pageLoading || pending.size > 0;
    if (busy === active) return;
    active = busy;
    if (busy) topbar.show(300);
    else topbar.hide();
  };

  window.addEventListener('phx:push', ({target, detail}) => {
    const completion = detail?.loadingComplete;
    if (!completion) return;
    pending.set(completion, target);
    update();
    const done = () => {
      pending.delete(completion);
      update();
    };
    completion.then(done, done);
  });
  window.addEventListener('phx:page-loading-start', () => {
    pageLoading = true;
    update();
  });
  window.addEventListener('phx:page-loading-stop', () => {
    pageLoading = false;
    update();
  });

  const reset = () => {
    pending.clear();
    pageLoading = false;
    update();
  };
  window.addEventListener('pagehide', reset);
  liveSocket.getSocket().onClose(reset);
  liveSocket.getSocket().onError(reset);
};

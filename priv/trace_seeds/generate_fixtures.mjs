// Optional fixture maintenance, not used by mix seed_traces.
// Node 20: node --experimental-websocket generate_fixtures.mjs http://chrome:9222
// Chrome must see this directory at /fixtures. No external pages are loaded.
import { writeFile } from 'node:fs/promises';
import { lookup } from 'node:dns/promises';

const endpointUrl = new URL(process.argv[2] || 'http://localhost:9222');
endpointUrl.hostname = (await lookup(endpointUrl.hostname, { family: 4 })).address;
const endpoint = endpointUrl.origin;
const tab = await (await fetch(`${endpoint}/json/new?about:blank`, { method: 'PUT' })).json();
const wsUrl = new URL(tab.webSocketDebuggerUrl);
wsUrl.host = new URL(endpoint).host;
const socket = new WebSocket(wsUrl);
await new Promise((resolve, reject) => {
  socket.onopen = resolve;
  socket.onerror = reject;
});
let id = 0;
const pending = new Map();
socket.onmessage = ({ data }) => {
  const message = JSON.parse(data);
  if (!pending.has(message.id)) return;
  const { resolve, reject, timeout } = pending.get(message.id);
  clearTimeout(timeout);
  pending.delete(message.id);
  if (message.error) reject(new Error(JSON.stringify(message.error)));
  else resolve(message.result);
};
function call(method, params = {}) {
  return new Promise((resolve, reject) => {
    const requestId = ++id;
    const timeout = setTimeout(() => reject(new Error(`Timed out: ${method}`)), 15000);
    pending.set(requestId, { resolve, reject, timeout });
    socket.send(JSON.stringify({ id: requestId, method, params }));
  });
}
try {
  await call('Page.enable');
  await call('Emulation.setDeviceMetricsOverride', { width: 960, height: 760, deviceScaleFactor: 1, mobile: false });
  await call('Page.navigate', { url: 'file:///fixtures/fixtures.html#video' });
  let encoded;
  for (let n = 0; n < 100; n++) {
    const value = await call('Runtime.evaluate', {
      expression: 'document.querySelector("#video-fixture")?.textContent', returnByValue: true
    });
    encoded = value.result?.value;
    if (encoded) break;
    await new Promise(resolve => setTimeout(resolve, 100));
  }
  if (!encoded) throw new Error('Browser did not record the WebM fixture');
  await writeFile(new URL('./fulfillment.webm', import.meta.url), Buffer.from(encoded, 'base64'));
  const screenshot = await call('Page.captureScreenshot', { format: 'png' });
  await writeFile(new URL('./checkout.png', import.meta.url), Buffer.from(screenshot.data, 'base64'));
  // Decode the result in the browser, not just check its file extension.
  const check = await call('Runtime.evaluate', {
    expression: `new Promise((resolve, reject) => {
      const video = document.createElement('video');
      video.onloadeddata = () => resolve({width: video.videoWidth, height: video.videoHeight});
      video.onerror = () => reject(new Error('Recorded video is not decodable'));
      video.src = 'data:video/webm;base64,${encoded}';
      video.load();
    })`, awaitPromise: true, returnByValue: true
  });
  if (check.exceptionDetails || !check.result?.value?.width) throw new Error('WebM verification failed');
  console.log(`Generated checkout.png and fulfillment.webm (${Buffer.from(encoded, 'base64').length} bytes; ${JSON.stringify(check.result.value)}).`);
} finally {
  socket.close();
  await fetch(`${endpoint}/json/close/${tab.id}`);
}

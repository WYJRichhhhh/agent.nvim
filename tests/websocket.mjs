import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import crypto from 'node:crypto';
import { once } from 'node:events';
import { connect } from '../scripts/websocket.mjs';

function frame(opcode, text, fin = true) {
  const body = Buffer.from(text), extra = body.length < 126 ? 0 : body.length < 65536 ? 2 : 8;
  const h = Buffer.alloc(2 + extra); h[0] = (fin ? 128 : 0) | opcode;
  h[1] = extra === 0 ? body.length : extra === 2 ? 126 : 127;
  if (extra === 2) h.writeUInt16BE(body.length, 2);
  if (extra === 8) h.writeBigUInt64BE(BigInt(body.length), 2);
  return Buffer.concat([h, body]);
}
test('authenticated WebSocket: rejected token, fragmented messages, extended lengths, ping and masked client data', async () => {
  const sockets = new Set();
  const server = http.createServer();
  let received = Buffer.alloc(0), upgraded;
  server.on('upgrade', (req, socket) => {
    socket.on('error', () => {}); sockets.add(socket); socket.on('close', () => sockets.delete(socket));
    if (req.headers.authorization !== 'Bearer test-token') { socket.end('HTTP/1.1 401 Unauthorized\r\n\r\n'); return; }
    const accept = crypto.createHash('sha1').update(req.headers['sec-websocket-key'] + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
    socket.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: '+accept+'\r\n\r\n');
    socket.on('data', chunk => { received = Buffer.concat([received, chunk]); });
    upgraded = socket;
  });
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  let client;
  try {
    const endpoint = 'ws://127.0.0.1:' + server.address().port;
    await assert.rejects(connect(endpoint, 'wrong'), /401/);
    client = await connect(endpoint, 'test-token'); client.on('error', error => assert.fail(error));
    let message = once(client, 'message');
    upgraded.write(frame(1, 'first ', false)); upgraded.write(frame(9, 'ping'));
    upgraded.write(frame(0, 'second')); assert.equal((await message)[0], 'first second');
    for (const size of [300, 70000]) {
      const text = '字'.repeat(size), bytes = frame(1, text);
      message = once(client, 'message');
      upgraded.write(bytes.subarray(0, 3)); upgraded.write(bytes.subarray(3));
      assert.equal((await message)[0], text);
    }
    received = Buffer.alloc(0); client.send('request');
    await new Promise(resolve => setTimeout(resolve, 30));
    // Skip a possible masked pong emitted in response to the earlier ping.
    let offset = 0;
    while ((received[offset] & 15) !== 1) offset += 2 + 4 + (received[offset+1] & 127);
    assert.equal(received[offset+1] & 128, 128);
    const mask = received.subarray(offset+2, offset+6), decoded = Buffer.from(received.subarray(offset+6));
    for (let i=0;i<decoded.length;i++) decoded[i] ^= mask[i%4];
    assert.equal(decoded.toString(), 'request');
  } finally {
    client?.removeAllListeners('error'); client?.on('error', () => {});
    client?.close(); for (const socket of sockets) socket.destroy();
    await new Promise(resolve => server.close(resolve));
  }
});

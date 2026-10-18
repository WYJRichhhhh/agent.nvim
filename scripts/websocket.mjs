// Small RFC 6455 client using Node's built-in HTTP/crypto modules. No npm packages.
import http from 'node:http';
import crypto from 'node:crypto';
import { EventEmitter } from 'node:events';

export function connect(url, token) {
  return new Promise((resolve, reject) => {
    const key = crypto.randomBytes(16).toString('base64');
    const req = http.request(url.replace('ws:', 'http:'), {
      headers: { Connection: 'Upgrade', Upgrade: 'websocket', 'Sec-WebSocket-Version': '13',
        'Sec-WebSocket-Key': key, Authorization: `Bearer ${token}` },
    });
    req.setTimeout(3000, () => req.destroy(new Error('WebSocket handshake timed out')));
    req.on('error', reject);
    req.on('response', res => { res.resume(); reject(new Error(`WebSocket HTTP ${res.statusCode}`)); });
    req.on('upgrade', (res, socket, head) => {
      const expected = crypto.createHash('sha1').update(key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
      if (res.headers['sec-websocket-accept'] !== expected) { socket.destroy(); reject(new Error('Invalid WebSocket handshake')); return; }
      req.setTimeout(0);
      const client = new EventEmitter();
      let pending = Buffer.alloc(0), fragments = [], fragmentBytes = 0, fragmentOpcode;
      const MAX = 32 * 1024 * 1024;
      function send(opcode, payload) {
        payload = Buffer.from(payload);
        const extra = payload.length < 126 ? 0 : payload.length < 65536 ? 2 : 8;
        const header = Buffer.alloc(2 + extra + 4);
        header[0] = 0x80 | opcode;
        header[1] = 0x80 | (extra === 0 ? payload.length : extra === 2 ? 126 : 127);
        if (extra === 2) header.writeUInt16BE(payload.length, 2);
        if (extra === 8) header.writeBigUInt64BE(BigInt(payload.length), 2);
        const mask = crypto.randomBytes(4); mask.copy(header, 2 + extra);
        const encoded = Buffer.from(payload);
        for (let i = 0; i < encoded.length; i++) encoded[i] ^= mask[i % 4];
        socket.write(Buffer.concat([header, encoded]));
      }
      client.send = value => send(1, Buffer.from(value));
      client.close = () => { if (!socket.destroyed) { send(8, Buffer.alloc(0)); socket.end(); } };
      function fail(message) { client.emit('error', new Error(message)); socket.destroy(); }
      function receive(chunk) {
        pending = Buffer.concat([pending, chunk]);
        while (pending.length >= 2) {
          const opcode = pending[0] & 15, fin = !!(pending[0] & 128);
          let length = pending[1] & 127, offset = 2;
          if (pending[0] & 0x70 || pending[1] & 128) return fail('Invalid server WebSocket frame');
          if (length === 126) { if (pending.length < 4) return; length = pending.readUInt16BE(2); offset = 4; }
          else if (length === 127) { if (pending.length < 10) return; const n = pending.readBigUInt64BE(2); if (n > BigInt(MAX)) return fail('WebSocket message exceeds limit'); length = Number(n); offset = 10; }
          if (length > MAX || fragmentBytes + length > MAX) return fail('WebSocket message exceeds limit');
          if (opcode >= 8 && (!fin || length > 125)) return fail('Invalid control frame');
          if (pending.length < offset + length) return;
          const data = pending.subarray(offset, offset + length); pending = pending.subarray(offset + length);
          if (opcode === 8) { client.close(); return; }
          if (opcode === 9) { send(10, data); continue; }
          if (opcode === 10) continue;
          if (opcode === 1 && fragmentOpcode === undefined) fragmentOpcode = 1;
          else if (opcode !== 0 || fragmentOpcode === undefined) return fail('Unexpected WebSocket opcode');
          fragments.push(data); fragmentBytes += data.length;
          if (fin) {
            const value = Buffer.concat(fragments).toString('utf8');
            fragments = []; fragmentBytes = 0; fragmentOpcode = undefined;
            client.emit('message', value);
          }
        }
      }
      socket.on('data', receive);
      socket.on('error', error => client.emit('error', error));
      socket.on('close', () => client.emit('close'));
      resolve(client);
      if (head.length) queueMicrotask(() => receive(head));
    });
    req.end();
  });
}

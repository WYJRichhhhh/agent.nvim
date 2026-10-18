// Local-only test server: token authentication, delayed subscription, native approval.
import http from 'node:http';
import crypto from 'node:crypto';
import fs from 'node:fs';
const arg=name=>process.argv[process.argv.indexOf(name)+1];
const url=new URL(arg('--listen')), hash=arg('--ws-token-sha256');
const sockets=new Set();let attempts=0,wrongAnswers=0;
const thread={id:'fixture-thread',source:'cli'};
const diff='diff --git a/sample.txt b/sample.txt\n--- a/sample.txt\n+++ b/sample.txt\n@@ -1 +1 @@\n-before\n+after\n';
const auth=req=>crypto.createHash('sha256').update((req.headers.authorization??'').replace(/^Bearer /,'')).digest('hex')===hash;
function send(socket,value){
 const data=Buffer.from(JSON.stringify(value));const extra=data.length<126?0:data.length<65536?2:8;
 const h=Buffer.alloc(2+extra);h[0]=0x81;h[1]=extra===0?data.length:extra===2?126:127;
 if(extra===2)h.writeUInt16BE(data.length,2);if(extra===8)h.writeBigUInt64BE(BigInt(data.length),2);
 socket.write(Buffer.concat([h,data]));
}
function broadcast(method,params){for(const s of sockets)send(s,{method,params});}
const server=http.createServer((req,res)=>{
 if(!auth(req)){res.writeHead(401).end();return;}
 if(req.url==='/edit'){broadcast('thread/started',{thread});res.end('EDIT_STARTED');}
 else if(req.url==='/approve'){
  fs.writeFileSync('sample.txt','after\n');
  broadcast('serverRequest/resolved',{threadId:thread.id,requestId:900});
  const item={id:'edit1',type:'fileChange',status:'completed',changes:[{path:process.cwd()+'/sample.txt',kind:{type:'update',move_path:null},diff:'@@ -1 +1 @@\n-before\n+after\n'}]};
  broadcast('item/completed',{threadId:thread.id,turnId:'turn1',item});
  broadcast('turn/diff/updated',{threadId:thread.id,turnId:'turn1',diff});
  broadcast('turn/completed',{threadId:thread.id,turn:{id:'turn1',status:'completed'}});
  res.end('APPROVED_IN_NATIVE_TUI');
 }else if(req.url==='/stats')res.end(JSON.stringify({attempts,wrongAnswers}));else res.writeHead(404).end();
});
server.on('upgrade',(req,socket)=>{
 if(!auth(req)){socket.end('HTTP/1.1 401 Unauthorized\r\n\r\n');return;}
 const accept=crypto.createHash('sha1').update(req.headers['sec-websocket-key']+'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
 socket.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: '+accept+'\r\n\r\n');sockets.add(socket);
 let pending=Buffer.alloc(0);
 socket.on('data',chunk=>{
  pending=Buffer.concat([pending,chunk]);
  while(pending.length>=2){
   const opcode=pending[0]&15;let n=pending[1]&127,offset=2;
   if(n===126){if(pending.length<4)return;n=pending.readUInt16BE(2);offset=4;}
   if(n===127){if(pending.length<10)return;n=Number(pending.readBigUInt64BE(2));offset=10;}
   if(pending.length<offset+4+n)return;
   const mask=pending.subarray(offset,offset+4),data=Buffer.from(pending.subarray(offset+4,offset+4+n));pending=pending.subarray(offset+4+n);
   for(let i=0;i<data.length;i++)data[i]^=mask[i%4];
   if(opcode===8){socket.end();return;}if(opcode!==1)continue;
   const message=JSON.parse(data.toString());if(message.id===900){wrongAnswers++;continue;}
   if(!message.method||message.id===undefined)continue;
   let result={};
   if(message.method==='initialize')result={userAgent:'fixture'};
   else if(message.method==='thread/resume'){
    attempts++;
    if(attempts===1){send(socket,{id:message.id,error:{code:-32600,message:'no rollout found'}});continue;}
    result={thread};
   }else if(message.method==='thread/turns/list')result={data:[]};
   send(socket,{id:message.id,result});
   if(message.method==='thread/resume'){
    broadcast('thread/started',{thread});
    broadcast('thread/started',{thread:{id:'title-thread',ephemeral:true,threadSource:'thread_title',source:'vscode'}});
    broadcast('thread/started',{thread:{id:'child-thread',parentThreadId:thread.id,source:{subAgent:{}}}});
    broadcast('turn/started',{threadId:thread.id,turn:{id:'turn1'},turnId:'turn1'});
    send(socket,{id:900,method:'item/fileChange/requestApproval',params:{threadId:thread.id,turnId:'turn1',itemId:'edit1'}});
   }
  }
 });socket.on('close',()=>sockets.delete(socket));socket.on('error',()=>{});
});
server.listen(Number(url.port),url.hostname,()=>{if(process.env.AGENT_TEST_PID_FILE)fs.writeFileSync(process.env.AGENT_TEST_PID_FILE,String(process.pid));});
process.on('SIGTERM',()=>{for(const s of sockets)s.destroy();server.close(()=>process.exit(0));});

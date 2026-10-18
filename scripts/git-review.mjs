// Git fallback for shell/script writes that do not produce Codex fileChange items.
// Snapshots stay local, bounded, and are taken before a turn; never write source files.
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
const exec = promisify(execFile);
const fingerprint = value => value === null ? 'absent' : crypto.createHash('sha256').update(value).digest('hex');
const quoted = value => JSON.stringify(value);

export class GitReview {
  constructor(cwd, options, emit) {
    this.cwd = cwd; this.options = options; this.emit = emit;
    this.roots = []; this.baseline = new Map(); this.seen = new Map(); this.bytes = 0;
    this.turnId = null; this.queue = Promise.resolve(); this.notice = new Set(); this.closed = false; this.candidates = new Map(); this.heads = new Map(); this.excluded = new Set();
  }
  async git(root, args, extra = {}) {
    return (await exec('git', ['-c','core.fsmonitor=false','-C', root, ...args], { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024, ...extra })).stdout;
  }
  warn(key, message) {
    if (!this.notice.has(key)) { this.notice.add(key); this.emit({type:'warning',message}); }
  }
  async discover() {
    try {
      const top = await this.git(this.cwd, ['rev-parse','--show-toplevel']);
      const primary = await fs.realpath(top.trim());
      let roots = [primary];
      if (this.options.worktrees) {
        const list = await this.git(primary, ['worktree','list','--porcelain','-z']);
        roots = [];
        for (const field of list.split('\0')) {
          if (!field.startsWith('worktree ')) continue;
          try { roots.push(await fs.realpath(field.slice(9))); } catch {}
        }
      }
      this.emit({type:'roots',roots:roots.filter(root => root !== primary || primary === this.cwd)});
      this.roots = roots;
      return roots;
    } catch { this.roots = []; return []; } // Non-Git projects keep native events only.
  }
  async paths(root) {
    const list = await this.git(root, ['ls-files','--cached','--others','--exclude-standard','-z']);
    return [...new Set(list.split('\0').filter(Boolean))];
  }
  async dirty(root) {
    const fields=(await this.git(root,['status','--porcelain=v1','-z','--untracked-files=all'])).split('\0');
    const files=[];
    for(let i=0;i<fields.length;i++) {
      const field=fields[i]; if(!field)continue;
      files.push(field.slice(3));
      if(field.slice(0,2).match(/[RC]/)) { if(fields[i+1])files.push(fields[++i]); }
    }
    return files;
  }
  async read(root, relative) {
    if (path.isAbsolute(relative) || relative.split('/').includes('..')) return undefined;
    const file = path.join(root,relative);
    try {
      const stat = await fs.lstat(file);
      if (!stat.isFile() || stat.size > this.options.max_diff_bytes) return undefined;
      const real = await fs.realpath(file);
      if (!real.startsWith(root + path.sep)) return undefined;
      const value = await fs.readFile(file);
      if (value.includes(0)) return undefined;
      return value;
    } catch (error) { if (error.code === 'ENOENT') return null; return undefined; }
  }
  async committed(root, relative) {
    try {
      const value = await this.git(root,['show',`HEAD:${relative}`],{encoding:'buffer',maxBuffer:this.options.max_diff_bytes});
      return value.includes(0) ? undefined : value;
    } catch { return undefined; }
  }
  remember(key, value) {
    if (value && this.bytes + value.length > this.options.max_snapshot_bytes) {
      this.excluded.add(key);
      this.warn('budget','Git review snapshot limit reached; some files are omitted. Increase review.max_snapshot_bytes if needed.');
      return false;
    }
    this.baseline.set(key,value); this.bytes += value?.length ?? 0;
    return true;
  }
  async snapshot() {
    this.baseline.clear(); this.seen.clear(); this.bytes = 0; this.notice.clear(); this.candidates.clear(); this.heads.clear(); this.excluded.clear();
    for (const root of await this.discover()) {
      try { this.heads.set(root,(await this.git(root,['rev-parse','HEAD'])).trim()); } catch {}
      this.candidates.set(root,new Set(await this.dirty(root)));
      for (const relative of await this.paths(root)) {
        if (this.closed) return;
        const value = await this.read(root,relative);
        const key=root+'\0'+relative;
        if(value===undefined) this.excluded.add(key);
        else if(this.remember(key,value)) this.seen.set(key,fingerprint(value));
      }
    }
  }
  async begin(turnId) {
    if (!turnId || this.turnId === turnId) return;
    this.turnId = turnId;
    await this.snapshot();
  }
  async patch(root, relative, before, after) {
    const directory = await fs.mkdtemp(path.join(os.tmpdir(),'agent-nvim-diff-'));
    await fs.chmod(directory,0o700);
    try {
      const old = path.join(directory,'before'), next = path.join(directory,'after');
      await fs.writeFile(old,before ?? Buffer.alloc(0),{mode:0o600});
      await fs.writeFile(next,after ?? Buffer.alloc(0),{mode:0o600});
      let output;
      try {
        output = (await exec('git',['--no-pager','diff','--no-index','--no-color','--no-ext-diff','--no-textconv','--text','--',old,next],{encoding:'utf8',maxBuffer:this.options.max_diff_bytes})).stdout;
      } catch (error) {
        if (error.code !== 1 || error.killed || error.stdout?.length >= this.options.max_diff_bytes) return null;
        output = error.stdout;
      }
      const offset = output.indexOf('@@');
      if (offset < 0) return null;
      const display=path.relative(this.cwd,path.join(root,relative)).split(path.sep).join('/');
      const a = before === null ? '/dev/null' : quoted('a/'+display);
      const b = after === null ? '/dev/null' : quoted('b/'+display);
      return `diff --git ${quoted('a/'+display)} ${quoted('b/'+display)}\n--- ${a}\n+++ ${b}\n${output.slice(offset)}`;
    } finally { await fs.rm(directory,{recursive:true,force:true}); }
  }
  async scan(turnId) {
    if (!turnId || this.closed) return;
    // Initial snapshot exists before native TUI launch. If turn/started was missed,
    // preserve that baseline rather than snapshotting after the write.
    if (!this.turnId) this.turnId = turnId;
    if (this.turnId !== turnId) return;
    const oldRoots = new Set(this.roots);
    const roots = await this.discover();
    const changes = [];
    for (const root of roots) {
      const files=this.candidates.get(root) ?? new Set();
      for(const relative of await this.dirty(root)) files.add(relative);
      let head; try { head=(await this.git(root,['rev-parse','HEAD'])).trim(); } catch {}
      if(oldRoots.has(root) && head!==this.heads.get(root)) {
        for(const relative of await this.paths(root)) files.add(relative);
        for(const key of this.baseline.keys()) if(key.startsWith(root+'\0')) files.add(key.slice(root.length+1));
      }
      this.candidates.set(root,files);
      const committedPaths=oldRoots.has(root) ? null : new Set((await this.git(root,['ls-tree','-rz','--name-only','HEAD'])).split('\0'));
      for (const relative of files) {
        if (this.closed) return;
        const key=root+'\0'+relative;
        if(this.excluded.has(key)) continue;
        const after=await this.read(root,relative);
        if (after===undefined) continue;
        if (!this.baseline.has(key)) {
          // New worktrees may be created and edited in one shell command. Their
          // committed content is the baseline; new untracked files start absent.
          const before=committedPaths?.has(relative) ? await this.committed(root,relative) : null;
          if (before===undefined) {this.excluded.add(key);continue;}
          if (!this.remember(key,before)) continue;
        }
        const hash=fingerprint(after);
        if (this.seen.get(key)===hash) continue;
        this.seen.set(key,hash);
        const before=this.baseline.get(key);
        if (fingerprint(before)===hash) {
          changes.push({path:path.join(root,relative),kind:{type:'update'},diff:'',reverted:true});
          continue;
        }
        const diff=await this.patch(root,relative,before,after);
        if (!diff) continue;
        changes.push({path:path.join(root,relative),kind:{type:before===null?'add':after===null?'delete':'update'},diff});
      }
    }
    if (changes.length) this.emit({type:'event',method:'item/completed',params:{turnId,item:{id:'git-'+crypto.randomUUID(),type:'fileChange',status:'completed',source:'git',changes}}});
  }
  run(task) {
    this.queue=this.queue.then(async()=>{if (!this.closed) await task();}).catch(()=>{
      this.warn('scan','Git review scan failed; native Codex events remain available.');
    });
    return this.queue;
  }
  close() {this.closed=true;this.baseline.clear();this.seen.clear();}
}

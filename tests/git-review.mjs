import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { GitReview } from '../scripts/git-review.mjs';
const exec=promisify(execFile);
const options={worktrees:true,max_diff_bytes:1024*1024,max_snapshot_bytes:8*1024*1024};
async function fixture(run) {
 const parent=await fs.realpath(await fs.mkdtemp(path.join(os.tmpdir(),'agent-git-review-test-')));
 const root=path.join(parent,'project');await fs.mkdir(root);const events=[];
 const git=async(...args)=>exec('git',['-c','commit.gpgsign=false','-c','core.hooksPath=/dev/null','-C',root,...args]);
 let review;
 try {
  await git('init','-q');await fs.writeFile(path.join(root,'doc.md'),'original\n');
  await fs.writeFile(path.join(root,'.gitignore'),'.worktrees/\n');await git('add','.');
  await git('-c','user.name=Test','-c','user.email=test@example.invalid','commit','-qm','base');
  review=new GitReview(root,options,event=>events.push(event));
  await run({root,parent,git,review,events});
 }finally{review?.close();await fs.rm(parent,{recursive:true,force:true});}
}
function changes(events){return events.filter(e=>e.type==='event').flatMap(e=>e.params.item.changes);}
test('shell writes use pre-turn dirty contents, include new/deleted files, and report reverts',async()=>fixture(async({root,review,events})=>{
 await fs.writeFile(path.join(root,'doc.md'),'user edit before turn\n');
 await review.snapshot();await review.begin('turn1');
 await fs.writeFile(path.join(root,'doc.md'),'agent changed it\n');
 await fs.writeFile(path.join(root,'new.md'),'new document\n');
 await review.scan('turn1');
 let files=changes(events);assert.equal(files.length,2);
 const doc=files.find(e=>e.path.endsWith('doc.md'));assert.match(doc.diff,/-user edit before turn\n\+agent changed it/);
 assert.ok(!doc.diff.includes('-original'));
 const count=events.length;await review.scan('turn1');assert.equal(changes(events).length,2,'unchanged files must not emit again');
 await fs.writeFile(path.join(root,'doc.md'),'user edit before turn\n');await fs.rm(path.join(root,'new.md'));
 await review.scan('turn1');assert.equal(changes(events).filter(c=>c.reverted).length,2);
 assert.ok(events.every(e=>e.type!=='warning'));assert.ok(count>0);
}));
test('worktree created and modified within one script is discovered and diffed against its commit',async()=>fixture(async({root,git,review,events})=>{
 await review.snapshot();await review.begin('turn2');
 const tree=path.join(root,'.worktrees','docs');await git('worktree','add','--detach',tree,'HEAD');
 await fs.writeFile(path.join(tree,'doc.md'),'worktree update\n');
 await review.scan('turn2');
 const doc=changes(events).find(e=>e.path===path.join(tree,'doc.md'));
 assert.ok(doc);assert.match(doc.diff,/-original\n\+worktree update/);
 assert.ok(events.filter(e=>e.type==='roots').at(-1).roots.includes(await fs.realpath(tree)));
}));
test('external registered worktrees are allowed, symlink targets and snapshot-budget overflow are excluded',async()=>fixture(async({parent,git,review,events})=>{
 const tree=path.join(parent,'external tree');await git('worktree','add','--detach',tree,'HEAD');
 const external=path.join(parent,'outside-secret');await fs.writeFile(external,'outside\n');
 await fs.symlink(external,path.join(tree,'link.md'));
 await review.snapshot();await review.begin('turn3');
 await fs.writeFile(path.join(tree,'doc.md'),'external tree update\n');await fs.writeFile(external,'changed outside\n');
 await review.scan('turn3');assert.ok(changes(events).some(e=>e.path===path.join(tree,'doc.md')));
 assert.ok(!changes(events).some(e=>e.path.endsWith('link.md')));
 const boundedEvents=[];const bounded=new GitReview(tree,{...options,max_snapshot_bytes:1},event=>boundedEvents.push(event));
 await bounded.snapshot();await fs.writeFile(path.join(tree,'doc.md'),'changed after budget overflow\n');await bounded.scan('bounded-turn');
 assert.ok(boundedEvents.some(e=>e.type==='warning'&&e.message.includes('limit')));assert.equal(changes(boundedEvents).length,0);bounded.close();
}));

test('a shell write followed by a commit is detected even when Git status is clean',async()=>fixture(async({root,git,review,events})=>{
 await review.snapshot();await review.begin('commit-turn');
 await fs.writeFile(path.join(root,'doc.md'),'committed by shell\n');await git('add','.');
 await git('-c','user.name=Test','-c','user.email=test@example.invalid','commit','-qm','script update');
 await review.scan('commit-turn');assert.ok(changes(events).some(change=>change.diff.includes('+committed by shell')));
}));

test('a registered nested worktree not ignored by its parent is not thousands of new files',async()=>fixture(async({root,git,review,events})=>{
 await fs.writeFile(path.join(root,'.gitignore'),'');await git('add','.gitignore');
 await git('-c','user.name=Test','-c','user.email=test@example.invalid','commit','-qm','do not ignore worktrees');
 await review.snapshot();await review.begin('nested-turn');
 const tree=path.join(root,'.worktrees','nested');await git('worktree','add','--detach',tree,'HEAD');
 await fs.writeFile(path.join(tree,'doc.md'),'only this document changed\n');
 await review.scan('nested-turn');
 const edits=changes(events).filter(change=>!change.reverted);
 assert.equal(edits.length,1,JSON.stringify(edits.map(change=>({path:change.path,kind:change.kind})),null,2));
 assert.equal(edits[0].kind.type,'update');assert.match(edits[0].diff,/-original/);
}));

test('repeated scans of a new worktree do not turn untouched tracked files into additions',async()=>fixture(async({root,git,review,events})=>{
 await review.snapshot();await review.begin('repeat-worktree-turn');
 const tree=path.join(root,'.worktrees','repeated');await git('worktree','add','--detach',tree,'HEAD');
 await fs.writeFile(path.join(tree,'doc.md'),'one real edit\n');await review.scan('repeat-worktree-turn');
 assert.equal(changes(events).filter(c=>!c.reverted).length,1);
 await review.scan('repeat-worktree-turn');
 const edits=changes(events).filter(c=>!c.reverted);
 assert.equal(edits.length,1,JSON.stringify(edits.map(c=>({path:c.path,kind:c.kind}))));
 await fs.writeFile(path.join(tree,'.gitignore'),'new ignore rule\n');await review.scan('repeat-worktree-turn');
 const last=changes(events).at(-1);assert.equal(last.kind.type,'update','later edits to existing files must not be additions');
}));

test('clean tracked files use committed baselines without exhausting the working snapshot budget',async()=>fixture(async({root,git,review,events})=>{
 for(let i=0;i<20;i++)await fs.writeFile(path.join(root,'asset-'+i+'.txt'),'clean tracked content\n'.repeat(100));
 await git('add','.');await git('-c','user.name=Test','-c','user.email=test@example.invalid','commit','-qm','clean assets');
 const boundedEvents=[];const bounded=new GitReview(root,{...options,max_snapshot_bytes:64},e=>boundedEvents.push(e));
 await bounded.snapshot();assert.ok(!boundedEvents.some(e=>e.type==='warning'),'clean files consumed snapshot budget');
 await fs.writeFile(path.join(root,'doc.md'),'real edit after clean snapshot\n');await bounded.scan('lazy-turn');
 assert.match(changes(boundedEvents)[0].diff,/-original\n\+real edit/);bounded.close();
}));

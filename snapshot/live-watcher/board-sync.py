#!/usr/bin/env python3
"""Sync factory issues/PRs onto adamsuk project #2. Idempotent. --dry-run to preview."""
import json, os, re, subprocess, sys
DRY = '--dry-run' in sys.argv
OWNER, NUM, PID = 'adamsuk', '2', 'PVT_kwHOAYEAOs4Bo3vn'
REPOS = ['adamsuk/software-factory','adamsuk/gh-factory','adamsuk/activity-feed','adamsuk/line','adamsuk/adamsuk']
ENV = {k:v for k,v in os.environ.items() if k not in ('GH_TOKEN','GITHUB_TOKEN')}
import time
def gh(*a, parse=True):
    for n in range(3):
        try:
            r = subprocess.run(['gh',*a], env=ENV, capture_output=True, text=True, timeout=120)
            if not r.returncode: break
            err = r.stderr[:300]
        except subprocess.TimeoutExpired: err = 'timeout'
        if n < 2: time.sleep(5 * 3**n)
    else: raise SystemExit(f"gh {a[:3]} failed after 3 tries: {err}")
    return json.loads(r.stdout) if parse and r.stdout.strip() else r.stdout
def fields():
    return {f['name']:f for f in gh('project','field-list',NUM,'--owner',OWNER,'--format','json','--limit','50')['fields']}
F = fields()
if 'Waiting on' not in F:
    print('create field: Waiting on')
    if not DRY:
        gh('project','field-create',NUM,'--owner',OWNER,'--name','Waiting on','--data-type','SINGLE_SELECT','--single-select-options','Scott,Factory,Nobody')
        F = fields()
def opt(field, name):
    f = F.get(field)
    if not f: return None
    return next(o['id'] for o in f['options'] if o['name']==name)
items = gh('project','item-list',NUM,'--owner',OWNER,'--format','json','--limit','1000')['items']
onboard = {i['content'].get('url'):i for i in items if i.get('content',{}).get('url')}
SCOTT = re.compile(r'needs[- ]scott|\bscott\b|@adamsuk|waiting (on|for) (you|the owner)|owner (decision|approval)', re.I)
def blocked_on_scott(repo, n, body):
    if SCOTT.search(body or ''): return True
    c = gh('issue','view',str(n),'-R',repo,'--json','comments')['comments'][-3:]
    return any(SCOTT.search(x['body']) for x in c)
def ci(rollup):
    st = set()
    for c in rollup or []:
        st.add((c.get('conclusion') or c.get('state') or c.get('status') or '').upper())
    if st & {'FAILURE','ERROR','TIMED_OUT','CANCELLED','ACTION_REQUIRED','STARTUP_FAILURE'}: return 'red'
    if st & {'PENDING','IN_PROGRESS','QUEUED','EXPECTED','WAITING',''}: return 'pending'
    return 'green' if st else 'none'
OVERRIDE = {
            'https://github.com/adamsuk/software-factory/issues/22': ('Blocked','Nobody')}  # parked after v0.2 (Scott 3 Nov)
want = {}  # url -> (fs, wait, status, label)
unmapped = []
for repo in REPOS:
    for it in gh('issue','list','-R',repo,'--state','open','--limit','500','--json','number,title,url,labels,body'):
        L = {l['name'] for l in it['labels']}
        if not any(l.startswith('factory') or l=='needs-scott' for l in L): continue
        if 'needs-scott' in L: m=('Blocked','Scott')
        elif 'factory:blocked' in L: m=('Blocked','Scott' if blocked_on_scott(repo,it['number'],it['body']) else 'Nobody')
        elif 'factory:building' in L: m=('Building','Factory')
        elif L & {'factory:gate','factory:review'}: m=('Review','Factory')
        elif 'factory:ready' in L: m=('Ready','Factory')
        elif 'factory:triage' in L: m=('Triage','Factory')
        else: unmapped.append(f"{repo}#{it['number']} labels={sorted(L)}"); continue
        m = OVERRIDE.get(it['url'], m)
        want[it['url']] = (*m, 'Todo' if m[0] in ('Triage','Ready','Blocked') else 'In Progress', f"{repo}#{it['number']}", it['title'])
    for pr in gh('pr','list','-R',repo,'--state','open','--limit','200','--json','number,title,url,isDraft,author,reviewDecision,mergeStateStatus,statusCheckRollup'):
        c = ci(pr['statusCheckRollup']); dep = 'dependabot' in pr['author']['login']
        if c=='red': m=('Blocked','Scott') if dep else ('Gate','Factory')
        elif c in ('green','none') and not pr['isDraft'] and (pr['reviewDecision'] in ('REVIEW_REQUIRED','') or pr['mergeStateStatus'] in ('BLOCKED','CLEAN')): m=('Merge','Scott')
        else: m=('Review','Factory')
        want[pr['url']] = (*m, 'In Progress', f"{repo}#{pr['number']}", pr['title'])
added=updated=0
def setf(item, field, name, cur):
    global updated
    if cur == name: return False
    o = opt(field, name)
    if not DRY: gh('project','item-edit','--project-id',PID,'--id',item,'--field-id',F[field]['id'],'--single-select-option-id',o, parse=False)
    return True
for url,(fs,w,st,ref,title) in want.items():
    it = onboard.get(url)
    if not it:
        print('add', ref); added+=1
        if DRY: continue
        it = gh('project','item-add',NUM,'--owner',OWNER,'--url',url,'--format','json'); it.setdefault('id',it.get('id'))
    assert st != 'Done' and fs != 'Done'  # open items are never Done
    ch = [setf(it['id'],'Status',st,it.get('status')), setf(it['id'],'Factory status',fs,it.get('factory status')), setf(it['id'],'Waiting on',w,it.get('waiting on')) if 'Waiting on' in F else False]
    if any(ch): updated+=1; print(f'set {ref}: {fs}/{w}/{st}')
# closed/merged items still not Done
for url,it in onboard.items():
    if url in want or not any(r in url for r in REPOS): continue
    stt = gh('api', re.sub(r'https://github.com/([^/]+/[^/]+)/(issues|pull)/(\d+)', r'repos/\1/issues/\3', url)).get('state')
    if stt!='closed': print('skip open item not in want (no Done):', url); continue
    if stt=='closed' and (it.get('factory status') != 'Done' or it.get('status')!='Done' or it.get('waiting on') not in (None,'Nobody')):
        ch=[setf(it['id'],'Status','Done',it.get('status')), setf(it['id'],'Factory status','Done',it.get('factory status'))]
        if it.get('waiting on'): ch.append(setf(it['id'],'Waiting on','Nobody',it.get('waiting on')))
        if any(ch): updated+=1; print('done', url)
print(f"\nadded={added} updated={updated} dry_run={DRY}")
for k,lab in [(('Merge','Scott'),'MERGE+SCOTT'),(('Blocked','Scott'),'BLOCKED+SCOTT'),(('Ready','Factory'),'READY')]:
    print(f"\n## {lab}")
    for url,v in want.items():
        if v[:2]==k: print(f"- [{v[3]}]({url}) {v[4]}")
if unmapped: print('\n## UNMAPPED'); [print('-',u) for u in unmapped]

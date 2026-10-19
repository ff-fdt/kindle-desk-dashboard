'use strict';
const $ = id => document.getElementById(id);
const capture = new URLSearchParams(location.search).has('capture');
if(capture) document.body.classList.add('capture');
let state = null, ui = {language:'zh'};
const words={
 zh:{system:'系统状态',memory:'内存',disk:'磁盘',battery:'Kindle 电量',running:'进行中',completed:'已完成',previous:'上一页',next:'下一页',read:'阅读全文',back:'返回总览',question:'问题',reply:'Codex 回复',waiting:'正在处理，等待回复。',original:'原文',cached:'缓存',rain:'降雨',noWeather:'暂无天气',waitingWeather:'等待天气更新',lastReading:'上次读数',charging:'正在充电',onBattery:'使用电池',waitingKindle:'等待读取 Kindle',updated:'更新于',sampling:'正在采样',empty:'等待下一次对话',unavailable:'暂时无法读取对话',emptyCopy:'你提出的问题和 Codex 的回复，会出现在这里。',unavailableCopy:'稍后将自动重试。',asked:'提问',answered:'回复'},
 en:{system:'System',memory:'Memory',disk:'Storage',battery:'Kindle battery',running:'In progress',completed:'Completed',previous:'Previous',next:'Next',read:'Read more',back:'Overview',question:'Question',reply:'Codex reply',waiting:'In progress. Waiting for a reply.',original:'Text',cached:'cached',rain:'Rain',noWeather:'Unavailable',waitingWeather:'Waiting for weather',lastReading:'Last read',charging:'Charging',onBattery:'On battery',waitingKindle:'Waiting for Kindle',updated:'Updated',sampling:'Sampling',empty:'Ready for your next conversation',unavailable:'Conversations unavailable',emptyCopy:'Your questions and Codex replies will appear here.',unavailableCopy:'Trying again shortly.',asked:'asked',answered:'replied'}
};
const t=key=>words[ui.language==='en'?'en':'zh'][key];
const zone=()=>state?.timezone||'Europe/London';
const locale=()=>ui.language==='en'?'en-GB':'zh-CN';
const weatherEnglish={0:'Clear',1:'Mostly clear',2:'Partly cloudy',3:'Overcast',45:'Fog',48:'Rime fog',51:'Light drizzle',53:'Drizzle',55:'Heavy drizzle',56:'Freezing drizzle',57:'Freezing drizzle',61:'Light rain',63:'Rain',65:'Heavy rain',66:'Freezing rain',67:'Freezing rain',71:'Light snow',73:'Snow',75:'Heavy snow',77:'Snow grains',80:'Showers',81:'Showers',82:'Heavy showers',85:'Snow showers',86:'Snow showers',95:'Thunderstorm',96:'Thunderstorm',99:'Thunderstorm'};
function paintLanguage(){
 $('refresh').textContent=ui.language==='en'?'Refresh':'刷新';
 document.documentElement.lang=ui.language==='en'?'en':'zh-CN';
 for(const [id,key] of [['system-heading','system'],['memory-heading','memory'],['disk-heading','disk'],['battery-heading','battery']])$(id).textContent=t(key);
 $('panel').setAttribute('aria-label',ui.language==='en'?'Kindle Desk dashboard':'Kindle Desk 看板');
 document.querySelector('.feed').setAttribute('aria-label','Codex');
 for(const [id,zh,en] of [['memory-bar','内存使用率','Memory usage'],['disk-bar','磁盘使用率','Storage usage'],['cpu-chart','CPU 使用率最近趋势','Recent CPU usage']])$(id).setAttribute('aria-label',ui.language==='en'?en:zh);
}
const esc = s => String(s ?? '').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const icon = (name, cls='') => `<img class="${cls}" src="assets/${name}.svg" alt="">`;
const time = at => new Intl.DateTimeFormat(locale(),{hour:'2-digit',minute:'2-digit',hour12:false,timeZone:zone()}).format(new Date(at*1000));
const status = t => t.status==='running' ? `<span class="status running">${icon('loader')}${words[ui.language==='en'?'en':'zh'].running}</span>` : `<span class="status">${icon('check')}${words[ui.language==='en'?'en':'zh'].completed}</span>`;
const num = (n,d=0) => Number.isFinite(n) ? Number(n).toLocaleString('en-GB',{maximumFractionDigits:d,minimumFractionDigits:d}) : '—';
function resize(){if(!capture){const scale=Math.min(1,(innerWidth-24)/1236);document.documentElement.style.setProperty('--preview-scale',scale);document.body.style.height=(1648*scale+24)+'px';}}
addEventListener('resize',resize);resize();
function weatherIcon(code){if(code===0)return 'sun';if(code<4)return 'cloud';if(code<50)return 'mist';if(code>=95)return 'cloud-storm';if(code>=71&&code<=77||code===85||code===86)return 'cloud-snow';return 'cloud-rain';}
function paintHeader(){
 const now=new Date(state.generated_at*1000),dateParts=new Intl.DateTimeFormat('zh-CN',{month:'numeric',day:'numeric',weekday:'long',timeZone:zone()}).formatToParts(now), part=type=>dateParts.find(p=>p.type===type)?.value||'', parts=part('month')+'月'+part('day')+'日  '+part('weekday');
 $('clock').textContent=time(state.generated_at);$('date').textContent=ui.language==='en'?new Intl.DateTimeFormat('en-GB',{day:'numeric',month:'long',weekday:'long',timeZone:zone()}).format(now):parts.replace(/\s+/g,'  ');
 const w=state.weather||{};$('city').textContent=w.city==='London'||!w.city?(ui.language==='en'?'London':'伦敦'):w.city;$('weather-icon').src='assets/'+weatherIcon(w.code??3)+'.svg';
 $('temperature').textContent=w.available?num(w.temperature)+'°':'—';$('weather-description').textContent=w.available?(ui.language==='en'?(weatherEnglish[w.code]||'Unknown'):w.description):t('noWeather');
 $('forecast').textContent=w.available?`${num(w.low)}° – ${num(w.high)}°　${t('rain')} ${num(w.rain_percent)}%${w.stale?' · '+t('cached'):''}`:t('waitingWeather');
 const m=state.mac||{};$('computer-name').textContent=m.name||'Mac';$('computer-detail').textContent=m.chip||'macOS';
 $('cpu-value').textContent=num(Math.max(0,m.cpu_percent))+'%';$('memory-value').textContent=num(m.memory_percent)+'%';$('disk-value').textContent=num(m.disk_percent)+'%';
 $('memory-detail').textContent=`${num(m.memory_used_gb,1)} / ${num(m.memory_total_gb)} GB`;
 $('disk-detail').textContent=`${num(m.disk_used_gb)} / ${num(m.disk_total_gb)} GB`;
 $('memory-bar').value=m.memory_percent||0;$('disk-bar').value=m.disk_percent||0;
 const canvas=$('cpu-chart'),ctx=canvas.getContext('2d'),h=m.cpu_history||[];ctx.clearRect(0,0,254,105);ctx.fillStyle='#252525';
 const gap=8,bar=3,start=254-h.length*gap;h.slice(-32).forEach((v,i)=>ctx.fillRect(start+i*gap,105-Math.max(2,v*1.0),bar,Math.max(2,v*1.0)));
 $('cpu-caption').textContent=h.length>1?(ui.language==='en'?'Last ':'最近 ')+Math.max(1,h.length)+(ui.language==='en'?' min':' 分钟'):t('sampling');
 const k=state.kindle||{},valid=Number.isFinite(k.battery_percent),stale= !k.observed_at || Date.now()/1000-k.observed_at>180;
 $('battery-value').textContent=valid?`${k.battery_percent}%`:'—';
 $('battery-icon').src='assets/'+(k.charging?'battery-charging':valid?'battery-'+Math.max(1,Math.ceil(k.battery_percent/25)):'battery')+'.svg';
 $('battery-detail').textContent=valid?(stale?`${t('lastReading')} ${time(k.observed_at)}`:k.charging?t('charging'):t('onBattery')):t('waitingKindle');
 $('updated').textContent=t('updated')+' '+time(state.generated_at);
}
function mathContent(item, field){
 const runs=item[field+'_runs'];
 if(!runs) return esc(item[field]||'');
 return runs.map(run=>{
  if(run.kind!=='math') return esc(run.text);
  try{return `<span class="${run.display?'display-math':'inline-math'}">${katex.renderToString(run.text,{displayMode:!!run.display,throwOnError:true,trust:false,maxExpand:500,maxSize:20,output:'html'})}</span>`;}
  catch{return esc(run.source||run.text);}
 }).join('');
}
function scaleMath(node){
 for(const formula of node.querySelectorAll('.inline-math,.display-math')){
  const widths=[...formula.querySelectorAll('.base')].map(n=>n.getBoundingClientRect().width);
  const width=Math.max(0,...widths), available=node.getBoundingClientRect().width;
  if(width>available && available>0) formula.style.fontSize=(available/width*100)+'%';
 }
}
function fitMath(node){
 const bottom=node.getBoundingClientRect().bottom;
 let cut=false;
 for(const child of [...node.childNodes]){
  if(cut){child.remove();continue;}
  if(child.nodeType===Node.ELEMENT_NODE){
   if(child.getBoundingClientRect().bottom>bottom+.5){child.remove();cut=true;}
  }else if(child.nodeType===Node.TEXT_NODE){
   const range=document.createRange();range.selectNodeContents(child);
   if([...range.getClientRects()].some(r=>r.bottom>bottom+.5)){
    const chars=Array.from(child.textContent);let lo=0,hi=chars.length;
    while(lo<hi){const mid=Math.ceil((lo+hi)/2);range.setEnd(child,chars.slice(0,mid).join('').length);
     if([...range.getClientRects()].every(r=>r.bottom<=bottom+.5))lo=mid;else hi=mid-1;}
    child.textContent=chars.slice(0,Math.max(0,lo-2)).join('').trimEnd()+'…';cut=true;
   }
  }
 }
}
function paintFeed(){
 const items=[...(state.codex?.items||[])].sort((a,b)=>(b.updated_at||b.at)-(a.updated_at||a.at)).slice(0,3);
 const running=items.filter(item=>item.status==='running').length;
 $('counts').textContent=items.length?`${running} ${t('running')} · ${items.length-running} ${t('completed')}`:'';
 $('conversations').innerHTML=items.map(item=>`<article class="turn"><div class="turn-meta"><time>${time(item.at)}</time>${status(item)}</div><div class="question"><div class="question-text">${mathContent(item,"question")}</div></div><div class="reply-label">Codex${item.status==='completed'?' · '+time(item.updated_at||item.at):''}</div><div class="reply">${item.reply?mathContent(item,"reply"):esc(t("waiting"))}</div></article>`).join('') || `<div class="empty"><h2>${state.codex?.available?t('empty'):t('unavailable')}</h2><p>${state.codex?.available?t('emptyCopy'):t('unavailableCopy')}</p></div>`;
 document.querySelectorAll('.question-text,.reply').forEach(scaleMath);
 document.querySelectorAll('.question-text').forEach(node=>{if(node.querySelector('.inline-math,.display-math')){node.classList.add('has-math');fitMath(node);}});
 document.querySelectorAll('.reply').forEach(node=>{
  const height=node.clientHeight, line=parseFloat(getComputedStyle(node).lineHeight);
  if(node.querySelector('.inline-math,.display-math')){
   node.classList.add('has-math');node.style.flex='0 0 auto';node.style.height=height+'px';fitMath(node);return;
  }
  const lines=Math.max(1,Math.floor(height/line));
  node.style.webkitLineClamp=String(lines);
  node.style.flex='0 0 auto';
  node.style.height=(lines*line)+'px';
 });
 window.panelUI={...ui};
}
window.renderDashboard=(value,restore)=>{state=value;ui={language:restore?.language==='en'?'en':'zh'};paintLanguage();paintHeader();paintFeed();window.panelReady=true;return {...ui};};
if(!capture){async function poll(){try{const r=await fetch('/api/state');const s=await r.json();window.renderDashboard(s,s.panel_ui);}catch{}}poll();setInterval(poll,2000);}
if(!capture) $('refresh').addEventListener('click',()=>fetch('/api/refresh',{method:'POST',headers:{'X-Kindle-Desk':'refresh'}}));

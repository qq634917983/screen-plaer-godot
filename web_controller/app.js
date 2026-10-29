(() => {
  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
  const grid = $('#media-grid');
  const toastNode = document.createElement('div'); toastNode.className = 'toast'; document.body.appendChild(toastNode);
  let state = null, currentFilter = 'all', selectedId = '', mode = localStorage.getItem('screenplayer-preview-mode') || 'fast';
  let previewTimer = 0, pollTimer = 0, mediaSignature = '', thumbCache = new Map();
  const thumbnailObserver = 'IntersectionObserver' in window ? new IntersectionObserver(entries => entries.forEach(entry => { if (entry.isIntersecting) { thumbnailObserver.unobserve(entry.target); loadThumb(entry.target); } }), {rootMargin:'120px'}) : null;
  const labels = {video:'视频',audio:'音频',image:'图片',html:'网页',ppt:'PPT',other:'其他'};
  const glyphs = {video:'▶',audio:'♫',image:'▧',html:'◎',ppt:'P',other:'·'};
  const toast = (message) => { toastNode.textContent = message; toastNode.classList.add('visible'); clearTimeout(toastTimer); toastTimer = setTimeout(() => toastNode.classList.remove('visible'), 2400); };
  let toastTimer;
  const token = () => localStorage.getItem('screenplayer-web-token') || '';
  async function api(path, options = {}) {
    const headers = new Headers(options.headers || {});
    if (token()) headers.set('Authorization', 'Bearer ' + token());
    if (options.body && typeof options.body === 'string') headers.set('Content-Type', 'application/json');
    const response = await fetch(path, {...options, headers, cache:'no-store'});
    if (response.status === 401 && path !== '/api/pair') { localStorage.removeItem('screenplayer-web-token'); showPairDialog(); throw new Error('需要配对'); }
    if (!response.ok) { let detail=''; try { const payload=await response.clone().json(); detail=payload.error||''; } catch { detail=await response.text().catch(() => ''); } throw new Error(detail || ('HTTP ' + response.status)); }
    const type = response.headers.get('content-type') || '';
    return type.includes('application/json') ? response.json() : response;
  }
  function showPairDialog() {
    let dialog = $('#pair-dialog'); if (dialog) { if (!dialog.open) dialog.showModal(); return; }
    dialog = document.createElement('dialog'); dialog.id = 'pair-dialog'; dialog.className = 'server-dialog';
    dialog.innerHTML = '<form id="pair-form"><div class="dialog-heading"><div><div class="eyebrow">PAIR DEVICE</div><h2>连接 ScreenPlayer</h2></div></div><p style="font-size:11px;color:#8997a8;line-height:1.6">在播放器电脑的「Web 控制器」菜单中查看本次会话配对码。</p><label style="display:flex;flex-direction:column;gap:7px;font-size:10px;color:#9eacbc">配对码<input id="pair-code" autocomplete="one-time-code" inputmode="numeric" maxlength="6" style="height:38px;background:#0b121b;border:1px solid #33465b;border-radius:6px;color:#fff;padding:0 11px;font-size:16px;letter-spacing:4px"></label><div class="dialog-footer"><span id="pair-error"></span><button class="button primary" type="submit">配对并连接</button></div></form>';
    document.body.appendChild(dialog); dialog.showModal();
    $('#pair-form', dialog).addEventListener('submit', async event => { event.preventDefault(); const button = $('button[type=submit]', dialog); button.disabled = true; $('#pair-error', dialog).textContent = '正在验证…'; try { const result = await api('/api/pair', {method:'POST', body:JSON.stringify({code:$('#pair-code',dialog).value.trim()})}); localStorage.setItem('screenplayer-web-token', result.token); dialog.close(); toast('已连接播放器'); refresh(); } catch (error) { $('#pair-error',dialog).textContent = error.message; } finally { button.disabled = false; } });
  }
  function updateConnection(connected, text) { $('#connection-label').textContent = text; $('#output-connection').textContent = connected ? '输出在线' : '未连接'; const dot = $('.status-dot'); dot.style.background = connected ? '#4cd49b' : '#e39b58'; dot.style.boxShadow = connected ? '0 0 12px #45d99a70' : '0 0 12px #e39b5860'; }
  function mediaType(item) { const t = String(item.type || 'other').toLowerCase(); return labels[t] || item.type_label || '媒体'; }
  function formatTime(value) { if (!Number.isFinite(Number(value)) || Number(value) < 0) return '--:--'; const n = Math.floor(Number(value)); return String(Math.floor(n/60)).padStart(2,'0')+':'+String(n%60).padStart(2,'0'); }
  function renderMedia(items = []) {
    grid.replaceChildren();
    const filtered = items.filter(item => currentFilter === 'all' || item.type === currentFilter || (currentFilter === 'web' && ['html','ppt'].includes(item.type))).filter(item => !$('#search-input').value.trim() || item.name.toLowerCase().includes($('#search-input').value.trim().toLowerCase()));
    $('#result-count').textContent = filtered.length + ' 个媒体'; $('#empty-state').hidden = filtered.length > 0; grid.hidden = filtered.length === 0;
    const counts = {all:items.length,video:0,image:0,audio:0,web:0}; for (const item of items) { if (counts[item.type] !== undefined) counts[item.type]++; else if (['html','ppt'].includes(item.type)) counts.web++; }
    for (const [key,value] of Object.entries(counts)) { const el = $('#count-'+key); if(el) el.textContent = value; }
    for (const item of filtered) {
      const card = document.createElement('article'); card.className = 'media-card'+(selectedId === item.id ? ' selected':''); card.dataset.id=item.id;
      const cover = document.createElement('div'); cover.className='media-cover';
      const fallback=document.createElement('span'); fallback.className='cover-fallback'; fallback.textContent=glyphs[item.type]||'·'; cover.appendChild(fallback);
      const badge=document.createElement('span'); badge.className='media-type'; badge.textContent=mediaType(item); cover.appendChild(badge);
      if (item.thumbnail) { const img=document.createElement('img'); img.alt=''; img.loading='lazy'; img.dataset.thumb=item.thumbnail; cover.appendChild(img); }
      if (item.duration) { const duration=document.createElement('span'); duration.className='duration-pill'; duration.textContent=formatTime(item.duration); cover.appendChild(duration); }
      const copy=document.createElement('div'); copy.className='card-copy'; const title=document.createElement('div'); title.className='card-title'; title.title=item.name; title.textContent=item.name; copy.appendChild(title); const meta=document.createElement('div'); meta.className='card-meta'; meta.textContent=item.missing?'文件暂不可用':(item.type_label||mediaType(item))+' · '+(item.size_label||'已入库'); copy.appendChild(meta);
      const actions=document.createElement('div'); actions.className='card-actions'; const preview=document.createElement('button'); preview.className='button preview-action'; preview.title='预览'; preview.textContent='◉'; preview.onclick=()=>command('/api/playback/preview',{id:item.id},'已发送到预览'); const output=document.createElement('button'); output.className='button'; output.textContent='⇧ 输出'; output.onclick=()=>command('/api/playback/output',{id:item.id},'已发送到输出'); actions.append(preview,output); card.append(cover,copy,actions); card.onclick=e=>{if(!e.target.closest('button')){selectedId=item.id;$$('.media-card').forEach(x=>x.classList.toggle('selected',x.dataset.id===item.id));$('#now-title').textContent=item.name;$('#now-subtitle').textContent=mediaType(item)+' · 点击预览或输出';}}; grid.appendChild(card);
    }
    for (const img of $('img[data-thumb]',grid)) { if (thumbnailObserver) thumbnailObserver.observe(img); else loadThumb(img); }
  }
  async function loadThumb(img) { const path=img.dataset.thumb; if(thumbCache.has(path)){img.src=thumbCache.get(path);img.onload=()=>img.parentElement?.querySelector('.cover-fallback')?.remove();return;} try { const response=await api(path); const url=URL.createObjectURL(await response.blob()); thumbCache.set(path,url); img.src=url; img.onload=()=>img.parentElement?.querySelector('.cover-fallback')?.remove(); } catch {} }
  function updateState(next) {
    state=next; $('#project-name').textContent=next.project?.name||'默认项目';
    const out=next.output||{}; $('#now-title').textContent=out.name||'暂无播放内容'; $('#now-subtitle').textContent=out.playing?'正在输出 · '+(out.type_label||'媒体'):(out.name?'已暂停或静止':'选中媒体以开始'); $('#cast-status').textContent=next.cast_visible?'正在显示':'已隐藏';
    $('#play-button').textContent=out.playing?'Ⅱ':'▶'; $('#elapsed').textContent=formatTime(out.elapsed); $('#duration').textContent=formatTime(out.duration); const pct=out.duration>0?Math.max(0,Math.min(100,out.elapsed/out.duration*100)):0; $('#timeline-progress').style.width=pct+'%';
    $('#preview-status').textContent=(next.preview_mode==='economy'?'省性能模式':'流畅模式')+' · 预览为定时截图，不传输声音';
    $('#status-message').textContent=next.status_text||'就绪';
    if (next.media) { const signature=JSON.stringify(next.media.map(item=>[item.id,item.name,item.type,item.missing,item.thumbnail])); if(signature!==mediaSignature){mediaSignature=signature;renderMedia(next.media);} }
    updateConnection(true,'播放器已连接');
    const desired=next.preview_mode||mode; if (desired!==mode && ['fast','economy'].includes(desired)) { mode=desired==='economy'?'economy':'fast'; localStorage.setItem('screenplayer-preview-mode',mode); updateModeButtons(); }
  }
  async function refresh() { try { const next=await api('/api/state'); updateState(next); } catch(error) { if(error.message!=='需要配对') updateConnection(false,'连接中断'); } finally { clearTimeout(pollTimer); pollTimer=setTimeout(refresh,1200); } }
  async function pollPreview() { if (!token()) return; const started=performance.now(); try { const response=await api('/api/preview.jpg?slot=output&ts='+Date.now()); const blob=await response.blob(); if(blob.size){const url=URL.createObjectURL(blob); const image=$('#preview-image'); const old=image.dataset.objectUrl; image.dataset.objectUrl=url; image.onload=()=>{if(old)URL.revokeObjectURL(old);}; image.src=url; $('#preview-screen').classList.add('has-image'); $('#preview-time').textContent='刚刚更新';} const latency=performance.now()-started; if(mode==='fast'&&latency>850){mode='economy';localStorage.setItem('screenplayer-preview-mode',mode);updateModeButtons();api('/api/preview-mode',{method:'POST',body:JSON.stringify({mode})}).catch(()=>{});toast('网络较慢，已切换省性能预览');} } catch {} finally { clearTimeout(previewTimer); previewTimer=setTimeout(pollPreview,mode==='economy'?1500:350); } }
  function updateModeButtons(){ $$('.mode-option').forEach(button=>button.classList.toggle('selected',button.dataset.mode===mode)); }
  async function command(path,payload,message){try{await api(path,{method:'POST',body:JSON.stringify(payload||{})});if(message)toast(message);setTimeout(refresh,250);}catch(error){toast(error.message);}}
  async function browseServer(path='') { try { const result=await api('/api/server-files?path='+encodeURIComponent(path)); const dialog=$('#server-dialog'); $('#server-path').textContent=result.path||'/'; const list=$('#server-list'); list.replaceChildren(); $('#server-selection').textContent=result.roots?.length?'选择媒体文件加入当前项目':'没有授权目录，请先在播放器菜单添加一个共享目录'; let chosen=''; if(result.parent){const up=document.createElement('button');up.type='button';up.className='server-row';up.innerHTML='<span class="file-icon">↰</span>上一级';up.onclick=()=>browseServer(result.parent);list.appendChild(up);} for(const dir of result.directories||[]){const row=document.createElement('button');row.type='button';row.className='server-row';row.innerHTML='<span class="file-icon">▰</span>';const label=document.createElement('span');label.textContent=dir.name;row.append(label);row.onclick=()=>browseServer(dir.path);list.appendChild(row);}for(const file of result.files||[]){const row=document.createElement('button');row.type='button';row.className='server-row';row.innerHTML='<span class="file-icon">▧</span>';const label=document.createElement('span');label.textContent=file.name;const kind=document.createElement('span');kind.className='server-kind';kind.textContent=file.type_label||'媒体';row.append(label,kind);row.onclick=()=>{$$('.server-row',list).forEach(x=>x.classList.remove('selected'));row.classList.add('selected');chosen=file.path;$('#server-selection').textContent=file.name;$('#import-server-file').disabled=false;};list.appendChild(row);} $('#import-server-file').disabled=!chosen; $('#import-server-file').onclick=async event=>{event.preventDefault();if(!chosen)return;try{await api('/api/server-files/import',{method:'POST',body:JSON.stringify({path:chosen})});toast('已加入媒体库');dialog.close();setTimeout(refresh,250);}catch(error){toast(error.message);}}; dialog.showModal(); }catch(error){toast(error.message);} }
  $('#browse-server').onclick=()=>browseServer(); $('#upload-button').onclick=()=>$('#upload-input').click(); $('#empty-upload').onclick=()=>$('#upload-input').click();
  $('#upload-input').addEventListener('change',async event=>{const files=[...event.target.files];if(!files.length)return;for(const file of files){try{$('#status-message').textContent='正在上传 '+file.name+'…';await api('/api/media/upload',{method:'POST',headers:{'X-Filename':encodeURIComponent(file.name),'Content-Type':file.type||'application/octet-stream'},body:file});toast('已上传：'+file.name);}catch(error){toast(file.name+'：'+error.message);}}event.target.value='';refresh();});
  $('#search-input').addEventListener('input',()=>state&&renderMedia(state.media||[])); $$('.filter').forEach(button=>button.onclick=()=>{currentFilter=button.dataset.filter;$$('.filter').forEach(x=>x.classList.toggle('active',x===button));state&&renderMedia(state.media||[]);});
  $$('.mode-option').forEach(button=>button.onclick=async()=>{mode=button.dataset.mode;localStorage.setItem('screenplayer-preview-mode',mode);updateModeButtons();try{await api('/api/preview-mode',{method:'POST',body:JSON.stringify({mode})});}catch(error){toast(error.message);}});
  $('#play-button').onclick=()=>command('/api/playback/toggle',{},null); $('#stop-button').onclick=()=>command('/api/playback/stop',{},'已停止输出'); $('#output-button').onclick=()=>selectedId&&command('/api/playback/output',{id:selectedId},'正在输出'); $('#previous-button').onclick=()=>command('/api/playback/prev',{},null); $('#next-button').onclick=()=>command('/api/playback/next',{},null);
  $('#server-dialog').addEventListener('close',()=>{$('#import-server-file').disabled=true;});
  updateModeButtons(); if(!token()) showPairDialog(); refresh(); pollPreview();
})();

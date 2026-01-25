import Foundation

enum HTMLTemplates {
    static func mainPage(appURL: String? = nil, quickButtons: [QuickButton] = []) -> String {
        let customButtonsHtml = quickButtons.map { button in
            let escapedCommand = button.command
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return """
            <button class="btn bq bc" data-v="\(escapedCommand)">\(button.label)</button>
            """
        }.joined()

        return """
        <!DOCTYPE html>
        <html><head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no,viewport-fit=cover">
        <title>Tapback</title>
        <style>
        *{box-sizing:border-box;margin:0;padding:0}
        html,body{height:100%;height:100dvh;overflow:hidden}
        body{font-family:-apple-system,BlinkMacSystemFont,monospace;background:#0d1117;color:#c9d1d9}
        /* Left sidebar */
        #sidebar{position:fixed;top:0;left:0;bottom:0;width:44px;background:#161b22;border-right:1px solid #30363d;display:flex;flex-direction:column;padding-top:env(safe-area-inset-top);overflow:hidden;z-index:10;transition:width 0.2s}
        #sidebar.expanded{width:200px;box-shadow:4px 0 20px rgba(0,0,0,0.5)}
        #legend-btn{width:100%;height:36px;display:flex;align-items:center;justify-content:center;font-size:14px;cursor:pointer;color:#8b949e;border-bottom:1px solid #30363d}
        #legend{display:none;position:fixed;top:50%;left:50%;transform:translate(-50%,-50%);background:#161b22;border:1px solid #30363d;border-radius:10px;padding:16px;z-index:200;min-width:200px}
        #legend.show{display:block}
        #legend-overlay{display:none;position:fixed;top:0;left:0;right:0;bottom:0;background:rgba(0,0,0,0.5);z-index:199}
        #legend-overlay.show{display:block}
        #legend h3{margin:0 0 12px;font-size:14px;color:#c9d1d9}
        .legend-item{display:flex;align-items:center;gap:10px;margin:8px 0;font-size:13px}
        .legend-color{width:20px;height:20px;border-radius:4px;display:flex;align-items:center;justify-content:center}
        .legend-color.starting{background:#3d2f1a}
        .legend-color.processing{background:#1a3d1a}
        .legend-color.idle{background:#1a2a3f}
        .legend-color.waiting{background:#3d3520}
        .legend-color.ended{background:#2d2d2d}
        .sess{width:100%;height:44px;display:flex;align-items:center;padding:0 10px;font-size:16px;cursor:pointer;border:2px solid transparent;transition:background 0.2s;gap:8px;background:#21262d}
        .sess .name{display:none;font-size:14px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;color:#c9d1d9}
        #sidebar.expanded .sess .name{display:block}
        .sess.active{border-color:#fff}
        .sess.status-starting{background:#3d2f1a}
        .sess.status-processing{background:#1a3d1a}
        .sess.status-idle{background:#1a2a3f}
        .sess.status-waiting{background:#3d3520}
        .sess.status-ended{background:#2d2d2d}
        @keyframes pulse{0%,100%{opacity:1}50%{opacity:0.5}}
        .sess.status-processing .icon{animation:pulse 1s infinite}
        /* Main content */
        #main{display:flex;flex-direction:column;height:100%;margin-left:44px;overflow:hidden}
        #h{padding:10px 14px;padding-top:max(10px,env(safe-area-inset-top));background:#161b22;border-bottom:1px solid #30363d;display:flex;justify-content:space-between;align-items:center;flex-shrink:0}
        #h .t{font-weight:bold;font-size:16px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
        #h .t.status-starting{color:#f0883e}
        #h .t.status-processing{color:#3fb950}
        #h .t.status-idle{color:#58a6ff}
        #h .t.status-waiting{color:#d29922}
        #h .t.status-ended{color:#8b949e}
        #h .s{font-size:13px;flex-shrink:0}
        #sound-toggle{font-size:18px;cursor:pointer;margin-left:8px}
        .on{color:#3fb950}.off{color:#f85149}
        \(appURL != nil ? ".app-link{display:block;padding:8px 14px;background:#1f3a5f;color:#58a6ff;text-align:center;text-decoration:none;font-size:13px;border-bottom:1px solid #30363d}" : "")
        #term-contents{flex:1;overflow-y:auto;-webkit-overflow-scrolling:touch;padding:14px;font-size:13px;line-height:1.5;white-space:pre-wrap;word-break:break-all;font-family:monospace}
        #in{padding:12px;padding-bottom:max(12px,env(safe-area-inset-bottom));background:#161b22;border-top:1px solid #30363d;flex-shrink:0}
        .row{display:flex;gap:8px;align-items:center}
        .quick{margin-bottom:8px}
        .btn{padding:12px 18px;font-size:15px;font-weight:600;border:none;border-radius:10px;cursor:pointer;-webkit-tap-highlight-color:transparent}
        .btn:active{opacity:0.7}
        .bq{flex:1;background:#21262d;color:#c9d1d9}
        .cust{overflow-x:auto;flex-wrap:nowrap;-webkit-overflow-scrolling:touch}
        .bc{flex:none;background:#1f3a5f;color:#58a6ff;font-size:13px;padding:10px 14px}
        #txt{flex:1;padding:12px 14px;font-size:16px;background:#0d1117;color:#c9d1d9;border:1px solid #30363d;border-radius:10px;min-width:0}
        #txt:focus{outline:none;border-color:#8b5cf6}
        .bsend{background:#8b5cf6;color:#fff}
        .empty{color:#8b949e;text-align:center;padding:20px}
        </style></head>
        <body>
        <div id="legend-overlay"></div>
        <div id="legend">
            <h3>ステータス</h3>
            <div class="legend-item"><span class="legend-color starting">🔄</span><span>starting - 開始中</span></div>
            <div class="legend-item"><span class="legend-color processing">⚡</span><span>processing - 処理中</span></div>
            <div class="legend-item"><span class="legend-color idle">💤</span><span>idle - 待機中</span></div>
            <div class="legend-item"><span class="legend-color waiting">⏳</span><span>waiting - 入力待ち</span></div>
            <div class="legend-item"><span class="legend-color ended">⏹</span><span>ended - 終了</span></div>
        </div>
        <div id="sidebar">
            <div id="legend-btn">❓</div>
            <div id="sessions"></div>
        </div>
        <div id="main">
            <div id="h"><span class="t" id="title">Tapback</span><span id="sound-toggle">🔇</span><span class="s" id="st">...</span></div>
            \(appURL != nil ? "<a class=\"app-link\" href=\"\(appURL!)\">Open App</a>" : "")
            <div id="term-contents"></div>
            <div id="in">
                <div class="row quick">
                    <button class="btn bq" data-v="1">1</button>
                    <button class="btn bq" data-v="2">2</button>
                    <button class="btn bq" data-v="3">3</button>
                    <button class="btn bq" data-v="4">4</button>
                    <button class="btn bq" data-v="5">5</button>
                </div>
                \(customButtonsHtml.isEmpty ? "" : "<div class=\"row quick cust\">\(customButtonsHtml)</div>")
                <div class="row">
                    <input type="text" id="txt" placeholder="Input..." autocomplete="off" enterkeyhint="send">
                    <button class="btn bsend" id="send">Send</button>
                </div>
            </div>
        </div>
        <script>
        const st=document.getElementById('st'),txt=document.getElementById('txt');
        const contents=document.getElementById('term-contents');
        const title=document.getElementById('title');
        const sidebar=document.getElementById('sidebar');
        const sessionsEl=document.getElementById('sessions');
        const legend=document.getElementById('legend');
        const legendOverlay=document.getElementById('legend-overlay');
        const legendBtn=document.getElementById('legend-btn');
        const soundToggle=document.getElementById('sound-toggle');
        let ws,activeId='',sessions=[],outputs={},sessionPaths={},claudeStatuses={};
        let soundEnabled=localStorage.getItem('tapback_sound')==='1';
        let prevStatuses={};

        // Sound functions
        function updateSoundIcon(){soundToggle.textContent=soundEnabled?'🔔':'🔇';}
        updateSoundIcon();
        soundToggle.onclick=()=>{soundEnabled=!soundEnabled;localStorage.setItem('tapback_sound',soundEnabled?'1':'0');updateSoundIcon();};

        function playTone(freq,duration,type='sine'){
            if(!soundEnabled)return;
            try{
                const ctx=new(window.AudioContext||window.webkitAudioContext)();
                const osc=ctx.createOscillator();
                const gain=ctx.createGain();
                osc.connect(gain);gain.connect(ctx.destination);
                osc.frequency.value=freq;
                osc.type=type;
                gain.gain.setValueAtTime(1.0,ctx.currentTime);
                gain.gain.exponentialRampToValueAtTime(0.01,ctx.currentTime+duration);
                osc.start();osc.stop(ctx.currentTime+duration);
            }catch(e){}
        }
        // idle: 優しい音1回（ポン）
        function playIdleSound(){playTone(600,0.3,'sine');}
        // waiting: 少し高い音2回（ポンポン）
        function playWaitingSound(){
            playTone(700,0.2,'sine');
            setTimeout(()=>playTone(800,0.2,'sine'),250);
        }

        legendBtn.onclick=()=>{legend.classList.add('show');legendOverlay.classList.add('show');};
        legendOverlay.onclick=()=>{legend.classList.remove('show');legendOverlay.classList.remove('show');};

        const statusIcons={starting:'🔄',processing:'⚡',idle:'💤',waiting:'⏳',ended:'⏹'};

        function getProjectName(sessionName){
            const path=sessionPaths[sessionName];
            if(!path)return sessionName;
            const parts=path.split('/').filter(p=>p);
            return parts[parts.length-1]||sessionName;
        }

        function getStatusForSession(sessionName){
            const sessionPath=sessionPaths[sessionName];
            if(!sessionPath)return null;
            if(claudeStatuses[sessionPath])return claudeStatuses[sessionPath].status;
            for(const[dir,s]of Object.entries(claudeStatuses)){
                if(sessionPath.startsWith(dir+'/'))return s.status;
            }
            return null;
        }

        function renderSidebar(){
            const prevActive=activeId;
            sessionsEl.innerHTML='';
            if(sessions.length===0){
                contents.innerHTML='<div class="empty">No tmux sessions found</div>';
                activeId='';
                title.textContent='Tapback';
                return;
            }
            if(!prevActive||!sessions.find(s=>s.name===prevActive)){
                activeId=sessions[0].name;
            }
            sessions.forEach(s=>{
                const btn=document.createElement('div');
                const status=getStatusForSession(s.name);
                btn.className='sess'+(s.name===activeId?' active':'')+(status?' status-'+status:'');
                btn.dataset.id=s.name;
                const icon=document.createElement('span');
                icon.className='icon';
                icon.textContent=status?statusIcons[status]:'📁';
                btn.appendChild(icon);
                const name=document.createElement('span');
                name.className='name';
                name.textContent=getProjectName(s.name);
                btn.appendChild(name);
                btn.onclick=()=>selectSession(s.name);
                sessionsEl.appendChild(btn);
            });
            updateContent();
        }

        function selectSession(id){
            activeId=id;
            document.querySelectorAll('.sess').forEach(el=>{
                const status=getStatusForSession(el.dataset.id);
                el.className='sess'+(el.dataset.id===activeId?' active':'')+(status?' status-'+status:'');
            });
            updateContent();
        }

        function updateSidebar(){
            document.querySelectorAll('.sess').forEach(el=>{
                const id=el.dataset.id;
                const status=getStatusForSession(id);
                const icon=el.querySelector('.icon');
                const name=el.querySelector('.name');
                el.className='sess'+(id===activeId?' active':'')+(status?' status-'+status:'');
                if(icon)icon.textContent=status?statusIcons[status]:'📁';
                if(name)name.textContent=getProjectName(id);
            });
            updateTitle();
        }

        function updateTitle(){
            if(activeId){
                const status=getStatusForSession(activeId);
                const icon=status?statusIcons[status]+' ':'';
                title.textContent=icon+getProjectName(activeId);
                title.className='t'+(status?' status-'+status:'');
            }else{
                title.textContent='Tapback';
                title.className='t';
            }
        }

        function updateContent(){
            if(!activeId){contents.innerHTML='';return;}
            const text=outputs[activeId]||'(waiting for output...)';
            const wasAtBottom=contents.scrollHeight-contents.scrollTop-contents.clientHeight<50;
            contents.innerHTML=escapeHtml(filterOutput(text));
            if(wasAtBottom)contents.scrollTop=contents.scrollHeight;
            updateTitle();
        }

        function escapeHtml(t){
            return t.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
        }

        function filterOutput(t){
            // Remove Claude Code input box lines (─ lines with ❯)
            return t.split('\\n').filter(line=>{
                const trimmed=line.trim();
                if(/^[─]+$/.test(trimmed))return false;
                if(/^❯\\s*$/.test(trimmed))return false;
                return true;
            }).join('\\n');
        }

        function connect(){
            const p=location.protocol==='https:'?'wss:':'ws:';
            ws=new WebSocket(p+'//'+location.host+'/ws');
            ws.onopen=()=>{st.textContent='Connected';st.className='s on'};
            ws.onmessage=(e)=>{
                const d=JSON.parse(e.data);
                if(d.t==='o'){
                    outputs[d.id]=d.c;
                    if(d.path)sessionPaths[d.id]=d.path;
                    if(d.id===activeId)updateContent();
                    if(!sessions.find(s=>s.name===d.id)){
                        sessions.push({name:d.id});
                        renderSidebar();
                    }
                    updateSidebar();
                }else if(d.t==='status'){
                    const s=d.d;
                    const prev=prevStatuses[s.project_dir];
                    if(prev!==s.status){
                        if(s.status==='idle')playIdleSound();
                        else if(s.status==='waiting')playWaitingSound();
                    }
                    prevStatuses[s.project_dir]=s.status;
                    claudeStatuses[s.project_dir]=s;
                    updateSidebar();
                }
            };
            ws.onclose=()=>{st.textContent='Reconnecting...';st.className='s off';setTimeout(connect,2000)};
            ws.onerror=()=>ws.close();
        }

        function send(v){if(ws&&ws.readyState===1&&activeId)ws.send(JSON.stringify({t:'i',id:activeId,c:v}))}

        document.querySelectorAll('.bq').forEach(b=>b.onclick=()=>send(b.dataset.v));
        document.getElementById('send').onclick=()=>{send(txt.value);txt.value='';};
        txt.onkeypress=(e)=>{if(e.key==='Enter'){send(txt.value);txt.value='';}};

        // Swipe to expand/collapse sidebar
        let touchStartX=0;
        sidebar.addEventListener('touchstart',e=>{touchStartX=e.touches[0].clientX;},{passive:true});
        sidebar.addEventListener('touchend',e=>{
            const dx=e.changedTouches[0].clientX-touchStartX;
            if(dx>40)sidebar.classList.add('expanded');
            else if(dx<-40)sidebar.classList.remove('expanded');
        },{passive:true});
        // Tap terminal to close sidebar
        contents.onclick=()=>sidebar.classList.remove('expanded');

        async function loadSessions(){
            try{
                const r=await fetch('/api/sessions');
                const newSessions=await r.json();
                const newNames=newSessions.map(s=>s.name).sort().join(',');
                const oldNames=sessions.map(s=>s.name).sort().join(',');
                if(newNames!==oldNames){
                    sessions=newSessions;
                    renderSidebar();
                }
            }catch(e){console.error(e)}
        }

        async function loadStatuses(){
            try{
                const r=await fetch('/api/claude-status');
                const statuses=await r.json();
                statuses.forEach(s=>{claudeStatuses[s.project_dir]=s});
                updateSidebar();
            }catch(e){console.error(e)}
        }

        loadSessions();
        loadStatuses();
        connect();
        setInterval(loadSessions,5000);
        </script>
        </body></html>
        """
    }

    static func pinPage(error: String?) -> String {
        let errorHtml = error.map { "<div class=\"e\">\($0)</div>" } ?? ""
        return """
        <!DOCTYPE html>
        <html><head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <title>Tapback</title>
        <style>
        *{box-sizing:border-box;margin:0;padding:0}
        body{font-family:sans-serif;background:#0d1117;color:#c9d1d9;min-height:100vh;display:flex;align-items:center;justify-content:center}
        .c{max-width:320px;width:100%;padding:20px;text-align:center}
        .l{font-size:2rem;margin-bottom:1.5rem;color:#8b5cf6}
        .p{width:100%;padding:1.2rem;font-size:2rem;text-align:center;letter-spacing:0.8rem;border:1px solid #30363d;border-radius:8px;background:#161b22;color:#c9d1d9;margin-bottom:1rem}
        .b{width:100%;padding:1rem;font-size:1.1rem;border:none;border-radius:8px;background:#8b5cf6;color:#fff;cursor:pointer}
        .e{color:#f85149;margin-top:1rem}
        </style></head>
        <body><div class="c">
        <div class="l">Tapback</div>
        <form method="POST" action="/auth">
        <input type="text" name="pin" class="p" maxlength="4" inputmode="numeric" placeholder="----" required autofocus>
        <button type="submit" class="b">Auth</button>
        </form>\(errorHtml)
        </div></body></html>
        """
    }
}

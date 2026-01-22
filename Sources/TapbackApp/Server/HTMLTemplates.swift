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
        body{font-family:-apple-system,BlinkMacSystemFont,monospace;background:#0d1117;color:#c9d1d9;display:flex;flex-direction:column}
        #h{padding:10px 14px;padding-top:max(10px,env(safe-area-inset-top));background:#161b22;border-bottom:1px solid #30363d;display:flex;justify-content:space-between;align-items:center;flex-shrink:0}
        #h .t{color:#8b5cf6;font-weight:bold;font-size:18px}
        #h .s{font-size:13px}
        .on{color:#3fb950}.off{color:#f85149}
        .mtabs{display:flex;gap:0;flex-shrink:0}
        .mtab{flex:1;padding:12px;background:#161b22;border:none;border-bottom:2px solid transparent;color:#8b949e;font-size:15px;font-weight:600;cursor:pointer;text-decoration:none;text-align:center;display:flex;align-items:center;justify-content:center}
        .mtab.active{color:#8b5cf6;border-bottom-color:#8b5cf6}
        a.mtab{color:#8b949e}
        a.mtab:hover{color:#c9d1d9}
        .mode-content{display:none;flex:1;flex-direction:column;overflow:hidden}
        .mode-content.active{display:flex}
        #terminal-view{flex:1;display:flex;flex-direction:column;overflow:hidden}
        .stabs{display:flex;gap:4px;padding:8px;background:#161b22;border-bottom:1px solid #30363d;overflow-x:auto;flex-shrink:0;-webkit-overflow-scrolling:touch}
        .stab{padding:8px 16px;background:#21262d;border:none;border-radius:8px;color:#8b949e;font-size:14px;cursor:pointer;white-space:nowrap}
        .stab.active{background:#8b5cf6;color:#fff}
        #term-contents{flex:1;overflow:hidden;display:flex;flex-direction:column}
        .stab-content{display:none;flex:1;overflow-y:auto;-webkit-overflow-scrolling:touch;padding:14px;font-size:13px;line-height:1.5;white-space:pre-wrap;word-break:break-all;font-family:monospace}
        .stab-content.active{display:flex;flex-direction:column}
        .term{flex:1}
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
        <div id="h"><span class="t">Tapback</span><span class="s" id="st">...</span></div>
        <div class="mtabs">
            <button class="mtab active" data-mode="terminal">Terminal</button>
            \(appURL != nil ? "<a class=\"mtab\" href=\"\(appURL!)\">App</a>" : "")
        </div>
        <div id="terminal-view" class="mode-content active">
            <div class="stabs" id="stabs"></div>
            <div id="term-contents"></div>
            <div id="in">
                <div class="row quick">
                    <button class="btn bq" data-v="0">0</button>
                    <button class="btn bq" data-v="1">1</button>
                    <button class="btn bq" data-v="2">2</button>
                    <button class="btn bq" data-v="3">3</button>
                    <button class="btn bq" data-v="4">4</button>
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
        const stabs=document.getElementById('stabs'),contents=document.getElementById('term-contents');
        let ws,activeId='',sessions=[];

        async function loadSessions(){
            try{
                const r=await fetch('/api/sessions');
                sessions=await r.json();
                renderSessions();
            }catch(e){console.error(e)}
        }

        function renderSessions(){
            stabs.innerHTML='';
            contents.innerHTML='';
            if(sessions.length===0){
                contents.innerHTML='<div class="empty">No tmux sessions found</div>';
                return;
            }
            sessions.forEach((s,i)=>{
                const btn=document.createElement('button');
                btn.className='stab'+(i===0?' active':'');
                btn.dataset.id=s.name;
                btn.textContent=s.name;
                btn.onclick=()=>selectSession(s.name);
                stabs.appendChild(btn);

                const div=document.createElement('div');
                div.className='stab-content'+(i===0?' active':'');
                div.dataset.id=s.name;
                div.innerHTML='<div class="term" id="term-'+s.name+'"></div>';
                contents.appendChild(div);
            });
            if(!activeId&&sessions.length>0)activeId=sessions[0].name;
        }

        function selectSession(id){
            activeId=id;
            document.querySelectorAll('.stab,.stab-content').forEach(el=>el.classList.remove('active'));
            document.querySelector('.stab[data-id="'+id+'"]')?.classList.add('active');
            document.querySelector('.stab-content[data-id="'+id+'"]')?.classList.add('active');
        }

        function connect(){
            const p=location.protocol==='https:'?'wss:':'ws:';
            ws=new WebSocket(p+'//'+location.host+'/ws');
            ws.onopen=()=>{st.textContent='Connected';st.className='s on'};
            ws.onmessage=(e)=>{
                const d=JSON.parse(e.data);
                if(d.t==='o'){
                    let term=document.getElementById('term-'+d.id);
                    if(!term){
                        // New session appeared, reload sessions
                        if(!sessions.find(s=>s.name===d.id)){
                            sessions.push({name:d.id});
                            renderSessions();
                            term=document.getElementById('term-'+d.id);
                        }
                    }
                    if(term)term.textContent=d.c;
                }
            };
            ws.onclose=()=>{st.textContent='Reconnecting...';st.className='s off';setTimeout(connect,2000)};
            ws.onerror=()=>ws.close();
        }

        function send(v){if(ws&&ws.readyState===1&&activeId)ws.send(JSON.stringify({t:'i',id:activeId,c:v}))}

        document.querySelectorAll('.bq').forEach(b=>b.onclick=()=>send(b.dataset.v));
        document.getElementById('send').onclick=()=>{send(txt.value);txt.value=''};
        txt.onkeypress=(e)=>{if(e.key==='Enter'){send(txt.value);txt.value=''}};

        loadSessions();
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

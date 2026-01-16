import Foundation

enum HTMLTemplates {
    static func mainPage(sessions: [Session]) -> String {
        let tabButtons = sessions.enumerated().map { index, session in
            """
            <button class="tab\(index == 0 ? " active" : "")" data-id="\(session.id.uuidString)">\(session.name)</button>
            """
        }.joined()

        let tabContents = sessions.enumerated().map { index, session in
            """
            <div class="tab-content\(index == 0 ? " active" : "")" data-id="\(session.id.uuidString)">
                <div class="term" id="term-\(session.id.uuidString)"></div>
            </div>
            """
        }.joined()

        return """
        <!DOCTYPE html>
        <html><head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
        <title>Tapback</title>
        <style>
        *{box-sizing:border-box;margin:0;padding:0}
        html,body{height:100%;overflow:hidden}
        body{font-family:-apple-system,BlinkMacSystemFont,monospace;background:#0d1117;color:#c9d1d9;display:flex;flex-direction:column}
        #h{padding:10px 14px;background:#161b22;border-bottom:1px solid #30363d;display:flex;justify-content:space-between;align-items:center;flex-shrink:0}
        #h .t{color:#8b5cf6;font-weight:bold;font-size:18px}
        #h .s{font-size:13px}
        .on{color:#3fb950}.off{color:#f85149}
        .tabs{display:flex;gap:4px;padding:8px;background:#161b22;border-bottom:1px solid #30363d;overflow-x:auto;flex-shrink:0}
        .tab{padding:8px 16px;background:#21262d;border:none;border-radius:8px;color:#8b949e;font-size:14px;cursor:pointer}
        .tab.active{background:#8b5cf6;color:#fff}
        .tab-content{display:none;flex:1;overflow-y:auto;padding:14px;font-size:13px;line-height:1.5;white-space:pre-wrap;word-break:break-all;font-family:monospace}
        .tab-content.active{display:block}
        .term{min-height:100%}
        #in{padding:12px;background:#161b22;border-top:1px solid #30363d;flex-shrink:0}
        .row{display:flex;gap:8px;align-items:center}
        .quick{margin-bottom:8px}
        .btn{padding:12px 18px;font-size:15px;font-weight:600;border:none;border-radius:10px;cursor:pointer}
        .bq{flex:1;background:#21262d;color:#c9d1d9}
        #txt{flex:1;padding:12px 14px;font-size:16px;background:#0d1117;color:#c9d1d9;border:1px solid #30363d;border-radius:10px;min-width:0}
        #txt:focus{outline:none;border-color:#8b5cf6}
        .bsend{background:#8b5cf6;color:#fff}
        </style></head>
        <body>
        <div id="h"><span class="t">Tapback</span><span class="s" id="st">...</span></div>
        <div class="tabs">\(tabButtons)</div>
        <div id="contents">\(tabContents)</div>
        <div id="in">
        <div class="row quick">
        <button class="btn bq" data-v="0">0</button>
        <button class="btn bq" data-v="1">1</button>
        <button class="btn bq" data-v="2">2</button>
        <button class="btn bq" data-v="3">3</button>
        <button class="btn bq" data-v="4">4</button>
        </div>
        <div class="row">
        <input type="text" id="txt" placeholder="Input..." autocomplete="off">
        <button class="btn bsend" id="send">Send</button>
        </div>
        </div>
        <script>
        const st=document.getElementById('st'),txt=document.getElementById('txt');
        let ws,activeId='\(sessions.first?.id.uuidString ?? "")';
        function connect(){
        const p=location.protocol==='https:'?'wss:':'ws:';
        ws=new WebSocket(p+'//'+location.host+'/ws');
        ws.onopen=()=>{st.textContent='Connected';st.className='s on'};
        ws.onmessage=(e)=>{
            const d=JSON.parse(e.data);
            if(d.t==='o'){
                const term=document.getElementById('term-'+d.id);
                if(term)term.textContent=d.c;
            }
        };
        ws.onclose=()=>{st.textContent='Reconnecting...';st.className='s off';setTimeout(connect,2000)};
        ws.onerror=()=>ws.close();
        }
        function send(v){if(ws&&ws.readyState===1)ws.send(JSON.stringify({t:'i',id:activeId,c:v}))}
        document.querySelectorAll('.tab').forEach(t=>t.onclick=()=>{
            document.querySelectorAll('.tab,.tab-content').forEach(el=>el.classList.remove('active'));
            t.classList.add('active');
            activeId=t.dataset.id;
            document.querySelector('.tab-content[data-id="'+activeId+'"]').classList.add('active');
        });
        document.querySelectorAll('.bq').forEach(b=>b.onclick=()=>send(b.dataset.v));
        document.getElementById('send').onclick=()=>{send(txt.value);txt.value=''};
        txt.onkeypress=(e)=>{if(e.key==='Enter'){send(txt.value);txt.value=''}};
        connect();
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

import Foundation

enum WebSocketDebugPage {
    static let html = #"""
    <!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
    <title>书源调试</title><style>body{max-width:48rem;margin:2rem auto;padding:0 1rem;font:18px system-ui}label{display:block;margin:1rem 0}input{width:100%;box-sizing:border-box;padding:.5rem}button{padding:.6rem}pre{white-space:pre-wrap;overflow-wrap:anywhere}</style>
    <a href="/">返回书架</a><h1>书源调试</h1>
    <form id="debug"><label for="source">书源 URL</label><input id="source" required>
    <label for="key">关键字或调试链接</label><input id="key" required>
    <label for="token">Web 访问令牌</label><input id="token" type="password" autocomplete="off">
    <button type="submit">开始调试</button><button id="stop" type="button">停止</button></form>
    <p id="status" role="status"></p><pre id="logs" aria-live="polite"></pre>
    <script>
    const form=document.getElementById('debug'),logs=document.getElementById('logs'),status=document.getElementById('status');
    let socket=null,generation=0;
    function stop(){generation++;if(socket){socket.close(1000,'用户停止');socket=null}}
    document.getElementById('stop').onclick=()=>{stop();status.textContent='已停止'};
    window.addEventListener('pagehide',stop);
    form.onsubmit=async event=>{
      event.preventDefault();stop();const current=generation;logs.textContent='';status.textContent='连接中…';
      const tag=document.getElementById('source').value.trim(),key=document.getElementById('key').value.trim();
      try{
        const response=await fetch('/getJsSourceApiTokenRequired');const result=await response.json();
        if(!response.ok||!result.isSuccess)throw Error('无法读取令牌设置');
        if(current!==generation)return;
        const protocols=['legado'];
        if(result.data){const token=document.getElementById('token').value.trim();if(!token)throw Error('请输入 Web 访问令牌');
          const bytes=new TextEncoder().encode(token);let raw='';for(const byte of bytes)raw+=String.fromCharCode(byte);
          protocols.push('legado.token.'+btoa(raw).replace(/\+/g,'-').replace(/\//g,'_').replace(/=+$/,''));}
        const ws=new WebSocket((location.protocol==='https:'?'wss://':'ws://')+location.host+'/bookSourceDebug',protocols);socket=ws;
        ws.onopen=()=>{if(current!==generation){ws.close();return}status.textContent='正在调试';ws.send(JSON.stringify({tag,key}))};
        ws.onmessage=event=>{if(current===generation)logs.textContent=(logs.textContent+event.data+'\n').slice(-200000)};
        ws.onerror=()=>{if(current===generation)status.textContent='连接失败，请检查服务状态和令牌'};
        ws.onclose=event=>{if(current===generation){socket=null;status.textContent=event.reason||'连接已关闭（'+event.code+'）'}};
      }catch(error){if(current===generation)status.textContent=error.message}
    };
    </script></html>
    """#
}

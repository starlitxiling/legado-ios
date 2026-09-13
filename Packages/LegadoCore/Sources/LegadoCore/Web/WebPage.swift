import Foundation

enum WebPage {
    static let html = #"""
    <!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
    <title>Legado 局域网阅读</title><style>body{max-width:48rem;margin:2rem auto;padding:0 1rem;font:18px system-ui}button{padding:.6rem;margin:.2rem}pre{white-space:pre-wrap;line-height:1.8}li{margin:.5rem 0}</style>
    <h1>Legado</h1><nav><button id="books">书架</button><button id="sources">书源</button></nav><p id="status" role="status"></p><main id="main"></main>
    <script>
    const main=document.getElementById('main'),status=document.getElementById('status');
    async function api(path){status.textContent='加载中…';const r=await fetch(path);const v=await r.json();if(!v.isSuccess)throw Error(v.errorMsg);status.textContent='';return v.data}
    function renderContent(text,bookUrl){const container=document.createElement('pre');for(const part of text.split(/(<img\b[^>]*>)/gi)){if(/^<img\b/i.test(part)){const parsed=new DOMParser().parseFromString(part,'text/html').querySelector('img');const src=parsed?.getAttribute('src');if(src){const image=document.createElement('img');image.loading='lazy';image.style.maxWidth='100%';image.src='/image?url='+encodeURIComponent(bookUrl)+'&path='+encodeURIComponent(src)+'&width=640';container.append(image)}}else{container.append(document.createTextNode(part))}}main.replaceChildren(container)}
    function run(f){Promise.resolve().then(f).catch(e=>status.textContent=e.message)}
    function list(items,label,action){main.replaceChildren();const ul=document.createElement('ul');for(const item of items){const li=document.createElement('li'),node=document.createElement(action?'button':'span');node.textContent=label(item);if(action)node.onclick=()=>run(()=>action(item));li.append(node);ul.append(li)}main.append(ul)}
    document.getElementById('books').onclick=()=>run(async()=>list(await api('/getBookshelf'),b=>b.name+' · '+b.author,async b=>list(await api('/getChapterList?url='+encodeURIComponent(b.bookUrl)),c=>c.title,async c=>{const text=await api('/getBookContent?url='+encodeURIComponent(b.bookUrl)+'&index='+c.index);renderContent(text,b.bookUrl)})));
    document.getElementById('sources').onclick=()=>run(async()=>list(await api('/getBookSources'),s=>s.bookSourceName));
    document.getElementById('books').click();
    </script></html>
    """#
}

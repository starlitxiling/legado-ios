import Foundation
import JavaScriptCore

/// 会话客户端提供持久化 source 方法；普通客户端保留同一 API 实例内的状态。
public final class JsSourceApi {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    private var initializingLoginInfo = false

    public init() {}

    func install(in context: JSContext, engine: JsEngine? = nil) {
        if context.objectForKeyedSubscript("__sourceRead")?.isUndefined == false { return }
        let get: @convention(block) (String) -> String? = { key in
            self.lock.lock(); defer { self.lock.unlock() }
            return self.values[key]
        }
        let put: @convention(block) (String, JSValue) -> Bool = { key, value in
            self.lock.lock(); defer { self.lock.unlock() }
            self.values[key] = value.isNull || value.isUndefined ? nil : value.toString()
            return true
        }
        context.setObject(get, forKeyedSubscript: "__sourceRead" as NSString)
        context.setObject(put, forKeyedSubscript: "__sourceWrite" as NSString)
        installMethods(in: context, engine: engine)
    }

    func installMethods(in context: JSContext, engine: JsEngine?, refreshExplore: (() throws -> Void)? = nil) {
        let begin: @convention(block) () -> Bool = {
            self.lock.lock(); defer { self.lock.unlock() }
            guard !self.initializingLoginInfo else { return false }
            self.initializingLoginInfo = true
            return true
        }
        let end: @convention(block) () -> Void = {
            self.lock.lock(); defer { self.lock.unlock() }
            self.initializingLoginInfo = false
        }
        let evaluate: @convention(block) (String, String, String) -> Any? = { [weak engine] script, sourceJSON, extraJSON in
            do {
                guard let engine else { throw JsEngineError.unavailable }
                let source = try JSONSerialization.jsonObject(with: Data(sourceJSON.utf8))
                var bindings = try JSONSerialization.jsonObject(with: Data(extraJSON.utf8)) as? [String: Any] ?? [:]
                bindings["source"] = source
                return try engine.evaluateScript(script, bindings: bindings)
            } catch { Self.raise(error); return nil }
        }
        let refresh: @convention(block) () -> Void = {
            do { try refreshExplore?() } catch { Self.raise(error) }
        }
        let concurrent: @convention(block) (String, String) -> Void = { [weak engine] key, rate in
            do {
                guard let limiter = engine?.rateLimiter else { throw JsEngineError.unavailable }
                try HostAsyncBridge.wait { await limiter.updateConcurrentRate(key: key, rate: rate) }
            } catch { Self.raise(error) }
        }
        context.setObject(begin, forKeyedSubscript: "__sourceBeginInfo" as NSString)
        context.setObject(end, forKeyedSubscript: "__sourceEndInfo" as NSString)
        context.setObject(evaluate, forKeyedSubscript: "__sourceEval" as NSString)
        context.setObject(refresh, forKeyedSubscript: "__sourceRefreshExplore" as NSString)
        context.setObject(concurrent, forKeyedSubscript: "__sourceConcurrent" as NSString)
        context.setObject(UrlRequestBuilder.defaultUserAgent, forKeyedSubscript: "__sourceUserAgent" as NSString)
        context.evaluateScript(Self.script)
    }

    private static func raise(_ error: Error) {
        if let context = JSContext.current() { context.exception = JSValue(newErrorFromMessage: String(describing: error), in: context) }
    }

    private static let script = #"""
    var __sourceMethods=(function(s){
      function inline(rule) {
        var text=String(rule == null ? '' : rule).trim(), match=text.match(/^(?:<js>([\s\S]*)<\/js>|@js:([\s\S]*))$/i);
        return match ? String(match[1] == null ? match[2] : match[1]).trim() : null;
      }
      function object(text) {
        try { var value=JSON.parse(text); return value && typeof value === 'object' && !Array.isArray(value) ? value : null; }
        catch(e) { return null; }
      }
      function map(value) {
        if(value == null) return null;
        Object.defineProperty(value,'get',{value:function(k){return Object.prototype.hasOwnProperty.call(this,k) ? this[k] : null;},enumerable:false});
        Object.defineProperty(value,'put',{value:function(k,v){var old=this.get(k);this[k]=v;return old;},enumerable:false});
        return value;
      }
      function run(code, bindings) { return __sourceEval(String(code),JSON.stringify(s),JSON.stringify(bindings || {})); }
      function normalize(value) { return value == null ? null : typeof value === 'string' ? value : JSON.stringify(value); }
      var methods={
        getKey:function(){return s.bookSourceUrl || '';},
        getTag:function(){return s.bookSourceName || '';},
        getSource:function(){return s;},
        getLoginJs:function(){
          if(s.mainJs != null && String(s.mainJs).trim()) return s.mainJs;
          var rule=String(s.loginUrl == null ? '' : s.loginUrl).trim();
          return rule ? (inline(rule) == null ? rule : inline(rule)) : null;
        },
        getLoginUiJs:function(){return inline(s.loginUi);},
        isLoginUiV2:function(){var ui=object(s.loginUi);return !!ui && Number(ui.version) === 2;},
        hasLoginForm:function(){var form=String(s.loginUi == null ? '' : s.loginUi).trim();return !!form && form.replace(/\s/g,'') !== '[]';},
        hasLogin:function(){return !!String(s.loginUrl == null ? '' : s.loginUrl).trim() || methods.hasLoginForm();},
        login:function(){var code=methods.getLoginJs();if(code) run(code+"\nif(typeof login !== 'function') throw 'Function login not implements!!!';login.apply(this);");},
        evalJS:function(code){return run(code);},
        evalLoginUiV2:function(state,book,chapter){
          var code=methods.getLoginJs();if(!code) throw new Error('登录UI v2 缺少 loginUi/loginAction 脚本');
          return normalize(run(code+'\nloginUi(JSON.parse(String(__loginState)))',{__loginState:state,book:book || null,chapter:chapter || null}));
        },
        evalLoginActionV2:function(action,state,form,book,chapter){
          var code=methods.getLoginJs();if(!code) throw new Error('登录UI v2 缺少 loginUi/loginAction 脚本');
          return normalize(run(code+'\nloginAction(String(__loginAction),JSON.parse(String(__loginState)),JSON.parse(String(__loginForm)))',
            {__loginAction:action,__loginState:state,__loginForm:form,book:book || null,chapter:chapter || null}));
        },
        getHeaderMap:function(hasLoginHeader){
          var headers={};
          try { var code=inline(s.header);headers=object(code == null ? s.header : normalize(run(code))) || {}; } catch(e) {}
          if(!Object.keys(headers).some(function(k){return k.toLowerCase() === 'user-agent';})) headers['User-Agent']=__sourceUserAgent;
          if(hasLoginHeader) Object.assign(headers,methods.getLoginHeaderMap() || {});
          return map(headers);
        },
        getLoginHeader:function(){return __sourceRead('loginHeader');},
        getLoginHeaderMap:function(){return map(object(methods.getLoginHeader()));},
        putLoginHeader:function(value){
          value=String(value);var headers=object(value), c=headers && (headers.Cookie == null ? headers.cookie : headers.Cookie);
          if(c != null) cookie.replaceCookie(methods.getKey(),String(c));
          __sourceWrite('loginHeader',value);
        },
        removeLoginHeader:function(){__sourceWrite('loginHeader',null);cookie.removeCookie(methods.getKey());},
        getLoginInfo:function(){return __sourceRead('loginInfo');},
        getLoginInfoMap:function(){
          var saved=methods.getLoginInfo();if(saved != null) return map(object(saved) || {});
          if(methods.isLoginUiV2() || !methods.hasLoginForm() || !__sourceBeginInfo()) return map({});
          try {
            var code=methods.getLoginUiJs(), text=code == null ? s.loginUi : normalize(run((methods.getLoginJs() || '')+'\n'+code,{result:{},book:null,chapter:null}));
            var rows;try { rows=JSON.parse(text); } catch(e) { return map({}); }
            var values={};
            if(Array.isArray(rows)) rows.forEach(function(row){if(row && row.type !== 'button') values[row.name]=row.default == null ? '' : String(row.default);});
            if(Object.keys(values).length) methods.putLoginInfo(JSON.stringify(values));
            return map(values);
          } finally { __sourceEndInfo(); }
        },
        putLoginInfo:function(value){return __sourceWrite('loginInfo',String(value));},
        removeLoginInfo:function(){__sourceWrite('loginInfo',null);},
        getVariable:function(){return __sourceRead('variable') || '';},
        setVariable:function(value){__sourceWrite('variable',value == null ? null : String(value));},
        putVariable:function(value){methods.setVariable(value);},
        put:function(key,value){__sourceWrite('v_'+key,String(value));return String(value);},
        get:function(key){return __sourceRead('v_'+key) || '';},
        refreshExplore:function(){__sourceRefreshExplore();},
        // 每次调用都重新执行 jsLib，当前没有需要失效的编译或共享作用域缓存。
        refreshJSLib:function(){},
        putConcurrent:function(value){__sourceConcurrent(methods.getKey(),String(value));}
      };
      Object.assign(s,methods);
      return methods;
    })(source || (source={}));
    var sourceApi=source;
    """#
}

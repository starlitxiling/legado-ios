import Foundation

public enum JsSourceConfig {
    public static func extract(_ text: String) throws -> BookSource {
        let result = try JsEngine().evaluateScript(text + "\n" + validation)
        guard let json = result as? String else { throw JsEngineError.exception("配置对象无法解析") }
        var source = try GsonJSONDecoder().decode(BookSource.self, from: Data(json.utf8))
        source.mainJs = text
        return source
    }

    private static let validation = """
    ;(function() {
      var c = typeof config === 'undefined' ? null : config;
      var s = typeof source === 'undefined' ? null : source;
      function normalized(v) { return JSON.parse(typeof v === 'string' ? v : JSON.stringify(v)); }
      function complete(v) {
        try {
          var o=normalized(v);
          return o && typeof o === 'object' && !Array.isArray(o) &&
            String(o.bookSourceUrl == null ? '' : o.bookSourceUrl).trim() !== '' &&
            String(o.bookSourceName == null ? '' : o.bookSourceName).trim() !== '';
        } catch(e) { return false; }
      }
      if (s != null && (c == null || !complete(c))) c = s;
      if (c == null) throw new Error('JS源缺少顶层 config 配置对象（兼容旧版 source）');
      c = normalized(c);
      if (!c || Array.isArray(c) || typeof c !== 'object') throw new Error('配置对象不是合法对象');
      if (!String(c.bookSourceUrl || '').trim()) throw new Error('JS源 config.bookSourceUrl 不能为空');
      if (!String(c.bookSourceName || '').trim()) throw new Error('JS源 config.bookSourceName 不能为空');
      function has(n) { return eval('typeof '+n) === 'function'; }
      function required(n) { if (!has(n)) throw new Error('JS源缺少必备函数 '+n); }
      function exists(n) { return typeof eval('typeof '+n) === 'string' && eval('typeof '+n) !== 'undefined'; }
      (Number(c.bookSourceType) === 3 ? ['search','getBookInfo'] : ['search','getChapters','getContent']).forEach(required);
      ['mainJs','ruleSearch','ruleExplore','ruleBookInfo','ruleToc','ruleContent','ruleReview'].forEach(function(k){delete c[k];});
      [['exploreUrl','title'],['loginUi','name']].forEach(function(pair){
        var a=c[pair[0]];
        if (Array.isArray(a)) {
          if (!a.length) {delete c[pair[0]]; return;}
          a.forEach(function(v,i){if(!v || !String(v[pair[1]] || '').trim()) throw new Error(pair[0]+' 第 '+(i+1)+' 项缺少 '+pair[1]);});
          c[pair[0]]=JSON.stringify(a);
        }
      });
      if (typeof c.loginUi === 'string' && c.loginUi.replace(/\\s/g,'') === '[]') delete c.loginUi;
      if (c.exploreUrl && !has('explore')) throw new Error('JS源声明了 exploreUrl,缺少配对的 explore 函数');
      if (has('loginUi')) {
        if(c.loginUi) throw new Error('loginUi 函数与 config.loginUi 数据只能二选一');
        required('loginAction'); c.loginUi='{"version":2}';
      } else if(c.loginUi) required('login');
      ['getReviewSummary','getReviewDetail','getReviewReplies'].forEach(function(n){if(exists(n) && !has(n)) throw new Error(n+' 必须是函数');});
      if(has('getReviewSummary') !== has('getReviewDetail')) throw new Error('getReviewSummary/getReviewDetail 必须配对');
      if(has('getReviewReplies') && !has('getReviewSummary')) throw new Error('getReviewReplies 缺少 getReviewSummary/getReviewDetail');
      if(Object.prototype.hasOwnProperty.call(c,'maxBatchSize')) {
        if(typeof c.maxBatchSize !== 'number' || !Number.isInteger(c.maxBatchSize) || c.maxBatchSize <= 1) throw new Error('config.maxBatchSize 必须是大于1的整数');
        required('getContentBatch'); c.ruleContent={maxBatchSize:Math.min(c.maxBatchSize,50)};
      } else if(has('getContentBatch')) throw new Error('getContentBatch 缺少配对的 config.maxBatchSize');
      return JSON.stringify(c);
    })();
    """
}

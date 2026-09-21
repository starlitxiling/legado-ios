enum JavaPackageCompatibility {
    static let script = #"""
    (function() {
        const NativeString = String;
        function JavaString(value, charset) {
            const text = Array.isArray(value) || ArrayBuffer.isView(value) ? java.bytesToStr(value, charset || 'UTF-8') : NativeString(value);
            const result = new NativeString(text);
            result.getBytes = charset => java.strToBytes(text, charset || 'UTF-8');
            return result;
        }
        function SecretKeySpec(bytes, algorithm) { return {bytes:bytes,algorithm:NativeString(algorithm)}; }
        function IvParameterSpec(bytes) { return {bytes:bytes}; }
        const Cipher = {ENCRYPT_MODE:1, DECRYPT_MODE:2, getInstance:function(transformation) {
            let crypto, mode;
            return {init:function(operation,key,iv) {
                if(operation!==1 && operation!==2) throw new Error('Unsupported cipher operation');
                mode=operation; crypto=java.createSymmetricCrypto(transformation,key.bytes,iv ? iv.bytes : null);
            },doFinal:function(bytes) {
                if(!crypto) throw new Error('Cipher must be initialized');
                return mode===1 ? crypto.encrypt(bytes) : crypto.decrypt(bytes);
            }};
        }};
        const Base64 = {DEFAULT:0, NO_PADDING:1, NO_WRAP:2, CRLF:4, URL_SAFE:8,
            decode:function(value,flags) { return java.base64DecodeToByteArray(typeof value==='string' ? value : java.bytesToStr(value,'UTF-8'),flags || 0); },
            encodeToString:function(value,flags) {
                const bytes=Array.from(value), alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
                let result='';
                for(let i=0;i<bytes.length;i+=3) {
                    const a=bytes[i]&255,b=(bytes[i+1]||0)&255,c=(bytes[i+2]||0)&255;
                    result+=alphabet[a>>2]+alphabet[((a&3)<<4)|(b>>4)]+(i+1<bytes.length?alphabet[((b&15)<<2)|(c>>6)]:'=')+(i+2<bytes.length?alphabet[c&63]:'=');
                }
                if(flags&8) result=result.replace(/\+/g,'-').replace(/\//g,'_');
                if(flags&1) result=result.replace(/=+$/,'');
                if(!(flags&2) && result) result=result.match(/.{1,76}/g).join(flags&4?'\r\n':'\n')+(flags&4?'\r\n':'\n');
                return result;
            }};
        function HashMap() {
            const map={};
            Object.defineProperty(map,'put',{value:(key,value)=>{const previous=map[key];map[key]=value;return previous===undefined?null:previous;}});
            Object.defineProperty(map,'get',{value:key=>Object.prototype.hasOwnProperty.call(map,key)?map[key]:null});
            return map;
        }
        org.jsoup.Connection={Method:{GET:'GET',POST:'POST',HEAD:'HEAD',PUT:'PUT',DELETE:'DELETE'}};
        org.jsoup.Jsoup.connect=function(url) {
            const options={method:'GET',followRedirects:true,headers:{}};
            const connection={};
            ['followRedirects','headers','method','timeout'].forEach(name=>connection[name]=value=>{options[name]=value;return connection;});
            connection.ignoreContentType=()=>connection;
            connection.requestBody=value=>{options.body=NativeString(value);return connection;};
            connection.execute=()=>java.connect(NativeString(url)+','+JSON.stringify(options));
            return connection;
        };
        Packages.java={lang:{String:JavaString},net:{URLEncoder:{encode:(value,charset)=>java.encodeURI(NativeString(value),charset || 'UTF-8')},URLDecoder:{decode:(value,charset)=>java.decodeURI(NativeString(value),charset || 'UTF-8')}},util:{HashMap:HashMap}};
        Packages.javax={crypto:{Cipher:Cipher,spec:{SecretKeySpec:SecretKeySpec,IvParameterSpec:IvParameterSpec}}};
        Packages.android={util:{Base64:Base64}};
        globalThis.JavaImporter=function() {
            const imported={};
            Object.defineProperty(imported,'importPackage',{value:function() {
                for(const value of arguments) {
                    if(!value) throw new Error('Unsupported Java package');
                    Object.assign(imported,value);
                }
            }});
            imported.importPackage(...arguments);
            return imported;
        };
    })();
    """#
}

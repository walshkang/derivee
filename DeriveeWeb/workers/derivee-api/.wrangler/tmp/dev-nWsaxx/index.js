var __create = Object.create;
var __defProp = Object.defineProperty;
var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
var __getOwnPropNames = Object.getOwnPropertyNames;
var __getProtoOf = Object.getPrototypeOf;
var __hasOwnProp = Object.prototype.hasOwnProperty;
var __name = (target, value) => __defProp(target, "name", { value, configurable: true });
var __esm = (fn, res, err) => function __init() {
  if (err) throw err[0];
  try {
    return fn && (res = (0, fn[__getOwnPropNames(fn)[0]])(fn = 0)), res;
  } catch (e) {
    throw err = [e], e;
  }
};
var __commonJS = (cb, mod) => function __require() {
  try {
    return mod || (0, cb[__getOwnPropNames(cb)[0]])((mod = { exports: {} }).exports, mod), mod.exports;
  } catch (e) {
    throw mod = 0, e;
  }
};
var __copyProps = (to, from, except, desc) => {
  if (from && typeof from === "object" || typeof from === "function") {
    for (let key of __getOwnPropNames(from))
      if (!__hasOwnProp.call(to, key) && key !== except)
        __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
  }
  return to;
};
var __toESM = (mod, isNodeMode, target) => (target = mod != null ? __create(__getProtoOf(mod)) : {}, __copyProps(
  // If the importer is in node compatibility mode or this is not an ESM
  // file that has been converted to a CommonJS file using a Babel-
  // compatible transform (i.e. "__esModule" has not been set), then set
  // "default" to the CommonJS "module.exports" for node compatibility.
  isNodeMode || !mod || !mod.__esModule ? __defProp(target, "default", { value: mod, enumerable: true }) : target,
  mod
));

// wrangler-modules-watch:wrangler:modules-watch
var init_wrangler_modules_watch = __esm({
  "wrangler-modules-watch:wrangler:modules-watch"() {
    init_modules_watch_stub();
  }
});

// ../../../../../.npm/_npx/32026684e21afda6/node_modules/wrangler/templates/modules-watch-stub.js
var init_modules_watch_stub = __esm({
  "../../../../../.npm/_npx/32026684e21afda6/node_modules/wrangler/templates/modules-watch-stub.js"() {
    init_wrangler_modules_watch();
  }
});

// node_modules/protobufjs/src/util/aspromise.js
var require_aspromise = __commonJS({
  "node_modules/protobufjs/src/util/aspromise.js"(exports, module) {
    "use strict";
    init_modules_watch_stub();
    module.exports = asPromise;
    function asPromise(fn, ctx) {
      var params = new Array(arguments.length - 1), offset = 0, index = 2, pending = true;
      while (index < arguments.length)
        params[offset++] = arguments[index++];
      return new Promise(/* @__PURE__ */ __name(function executor(resolve, reject) {
        params[offset] = /* @__PURE__ */ __name(function callback(err) {
          if (pending) {
            pending = false;
            if (err)
              reject(err);
            else {
              var params2 = new Array(arguments.length - 1), offset2 = 0;
              while (offset2 < params2.length)
                params2[offset2++] = arguments[offset2];
              resolve.apply(null, params2);
            }
          }
        }, "callback");
        try {
          fn.apply(ctx || null, params);
        } catch (err) {
          if (pending) {
            pending = false;
            reject(err);
          }
        }
      }, "executor"));
    }
    __name(asPromise, "asPromise");
  }
});

// node_modules/protobufjs/src/util/base64.js
var require_base64 = __commonJS({
  "node_modules/protobufjs/src/util/base64.js"(exports) {
    "use strict";
    init_modules_watch_stub();
    var base64 = exports;
    base64.length = /* @__PURE__ */ __name(function length(string) {
      var p = string.length;
      if (!p)
        return 0;
      while (p > 0 && string.charAt(p - 1) === "=")
        --p;
      return Math.floor(p * 3 / 4);
    }, "length");
    var b64 = new Array(64);
    var s64 = new Array(123);
    for (i = 0; i < 64; )
      s64[b64[i] = i < 26 ? i + 65 : i < 52 ? i + 71 : i < 62 ? i - 4 : i - 59 | 43] = i++;
    var i;
    s64[45] = 62;
    s64[95] = 63;
    base64.encode = /* @__PURE__ */ __name(function encode(buffer, start, end) {
      var parts = null, chunk = [];
      var i2 = 0, j = 0, t;
      while (start < end) {
        var b = buffer[start++];
        switch (j) {
          case 0:
            chunk[i2++] = b64[b >> 2];
            t = (b & 3) << 4;
            j = 1;
            break;
          case 1:
            chunk[i2++] = b64[t | b >> 4];
            t = (b & 15) << 2;
            j = 2;
            break;
          case 2:
            chunk[i2++] = b64[t | b >> 6];
            chunk[i2++] = b64[b & 63];
            j = 0;
            break;
        }
        if (i2 > 8191) {
          (parts || (parts = [])).push(String.fromCharCode.apply(String, chunk));
          i2 = 0;
        }
      }
      if (j) {
        chunk[i2++] = b64[t];
        chunk[i2++] = 61;
        if (j === 1)
          chunk[i2++] = 61;
      }
      if (parts) {
        if (i2)
          parts.push(String.fromCharCode.apply(String, chunk.slice(0, i2)));
        return parts.join("");
      }
      return String.fromCharCode.apply(String, chunk.slice(0, i2));
    }, "encode");
    var invalidEncoding = "invalid encoding";
    base64.decode = /* @__PURE__ */ __name(function decode(string, buffer, offset) {
      var start = offset;
      var j = 0, t;
      for (var i2 = 0; i2 < string.length; ) {
        var c = string.charCodeAt(i2++);
        if (c === 61 && j > 1)
          break;
        if ((c = s64[c]) === void 0)
          throw Error(invalidEncoding);
        switch (j) {
          case 0:
            t = c;
            j = 1;
            break;
          case 1:
            buffer[offset++] = t << 2 | (c & 48) >> 4;
            t = c;
            j = 2;
            break;
          case 2:
            buffer[offset++] = (t & 15) << 4 | (c & 60) >> 2;
            t = c;
            j = 3;
            break;
          case 3:
            buffer[offset++] = (t & 3) << 6 | c;
            j = 0;
            break;
        }
      }
      if (j === 1)
        throw Error(invalidEncoding);
      return offset - start;
    }, "decode");
    var base64Re = /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/;
    var base64UrlRe = /[-_]/;
    var base64UrlNoPaddingRe = /^(?:[A-Za-z0-9_-]{4})*(?:[A-Za-z0-9_-]{2}(?:==)?|[A-Za-z0-9_-]{3}=?)?$/;
    base64.test = /* @__PURE__ */ __name(function test(string) {
      return base64Re.test(string) || base64UrlRe.test(string) && base64UrlNoPaddingRe.test(string);
    }, "test");
  }
});

// node_modules/protobufjs/src/util/eventemitter.js
var require_eventemitter = __commonJS({
  "node_modules/protobufjs/src/util/eventemitter.js"(exports, module) {
    "use strict";
    init_modules_watch_stub();
    module.exports = EventEmitter;
    function EventEmitter() {
      this._listeners = /* @__PURE__ */ Object.create(null);
    }
    __name(EventEmitter, "EventEmitter");
    EventEmitter.prototype.on = /* @__PURE__ */ __name(function on(evt, fn, ctx) {
      (this._listeners[evt] || (this._listeners[evt] = [])).push({
        fn,
        ctx: ctx || this
      });
      return this;
    }, "on");
    EventEmitter.prototype.off = /* @__PURE__ */ __name(function off(evt, fn) {
      if (evt === void 0)
        this._listeners = /* @__PURE__ */ Object.create(null);
      else {
        if (fn === void 0)
          this._listeners[evt] = [];
        else {
          var listeners = this._listeners[evt];
          if (!listeners)
            return this;
          for (var i = 0; i < listeners.length; )
            if (listeners[i].fn === fn)
              listeners.splice(i, 1);
            else
              ++i;
        }
      }
      return this;
    }, "off");
    EventEmitter.prototype.emit = /* @__PURE__ */ __name(function emit(evt) {
      var listeners = this._listeners[evt];
      if (listeners) {
        var args = [], i = 1;
        for (; i < arguments.length; )
          args.push(arguments[i++]);
        for (i = 0; i < listeners.length; )
          listeners[i].fn.apply(listeners[i++].ctx, args);
      }
      return this;
    }, "emit");
  }
});

// node_modules/protobufjs/src/util/float.js
var require_float = __commonJS({
  "node_modules/protobufjs/src/util/float.js"(exports, module) {
    "use strict";
    init_modules_watch_stub();
    module.exports = factory(factory);
    function factory(exports2) {
      if (typeof Float32Array !== "undefined") (function() {
        var f32 = new Float32Array([-0]), f8b = new Uint8Array(f32.buffer), le = f8b[3] === 128;
        function writeFloat_f32_cpy(val, buf, pos) {
          f32[0] = val;
          buf[pos] = f8b[0];
          buf[pos + 1] = f8b[1];
          buf[pos + 2] = f8b[2];
          buf[pos + 3] = f8b[3];
        }
        __name(writeFloat_f32_cpy, "writeFloat_f32_cpy");
        function writeFloat_f32_rev(val, buf, pos) {
          f32[0] = val;
          buf[pos] = f8b[3];
          buf[pos + 1] = f8b[2];
          buf[pos + 2] = f8b[1];
          buf[pos + 3] = f8b[0];
        }
        __name(writeFloat_f32_rev, "writeFloat_f32_rev");
        exports2.writeFloatLE = le ? writeFloat_f32_cpy : writeFloat_f32_rev;
        exports2.writeFloatBE = le ? writeFloat_f32_rev : writeFloat_f32_cpy;
        function readFloat_f32_cpy(buf, pos) {
          f8b[0] = buf[pos];
          f8b[1] = buf[pos + 1];
          f8b[2] = buf[pos + 2];
          f8b[3] = buf[pos + 3];
          return f32[0];
        }
        __name(readFloat_f32_cpy, "readFloat_f32_cpy");
        function readFloat_f32_rev(buf, pos) {
          f8b[3] = buf[pos];
          f8b[2] = buf[pos + 1];
          f8b[1] = buf[pos + 2];
          f8b[0] = buf[pos + 3];
          return f32[0];
        }
        __name(readFloat_f32_rev, "readFloat_f32_rev");
        exports2.readFloatLE = le ? readFloat_f32_cpy : readFloat_f32_rev;
        exports2.readFloatBE = le ? readFloat_f32_rev : readFloat_f32_cpy;
      })();
      else (function() {
        function writeFloat_ieee754(writeUint, val, buf, pos) {
          var sign = val < 0 ? 1 : 0;
          if (sign)
            val = -val;
          if (val === 0)
            writeUint(1 / val > 0 ? (
              /* positive */
              0
            ) : (
              /* negative 0 */
              2147483648
            ), buf, pos);
          else if (isNaN(val))
            writeUint(2143289344, buf, pos);
          else if (val > 34028234663852886e22)
            writeUint((sign << 31 | 2139095040) >>> 0, buf, pos);
          else if (val < 11754943508222875e-54)
            writeUint((sign << 31 | Math.round(val / 1401298464324817e-60)) >>> 0, buf, pos);
          else {
            var exponent = Math.floor(Math.log(val) / Math.LN2), mantissa = Math.round(val * Math.pow(2, -exponent) * 8388608) & 8388607;
            writeUint((sign << 31 | exponent + 127 << 23 | mantissa) >>> 0, buf, pos);
          }
        }
        __name(writeFloat_ieee754, "writeFloat_ieee754");
        exports2.writeFloatLE = writeFloat_ieee754.bind(null, writeUintLE);
        exports2.writeFloatBE = writeFloat_ieee754.bind(null, writeUintBE);
        function readFloat_ieee754(readUint, buf, pos) {
          var uint = readUint(buf, pos), sign = (uint >> 31) * 2 + 1, exponent = uint >>> 23 & 255, mantissa = uint & 8388607;
          return exponent === 255 ? mantissa ? NaN : sign * Infinity : exponent === 0 ? sign * 1401298464324817e-60 * mantissa : sign * Math.pow(2, exponent - 150) * (mantissa + 8388608);
        }
        __name(readFloat_ieee754, "readFloat_ieee754");
        exports2.readFloatLE = readFloat_ieee754.bind(null, readUintLE);
        exports2.readFloatBE = readFloat_ieee754.bind(null, readUintBE);
      })();
      if (typeof Float64Array !== "undefined") (function() {
        var f64 = new Float64Array([-0]), f8b = new Uint8Array(f64.buffer), le = f8b[7] === 128;
        function writeDouble_f64_cpy(val, buf, pos) {
          f64[0] = val;
          buf[pos] = f8b[0];
          buf[pos + 1] = f8b[1];
          buf[pos + 2] = f8b[2];
          buf[pos + 3] = f8b[3];
          buf[pos + 4] = f8b[4];
          buf[pos + 5] = f8b[5];
          buf[pos + 6] = f8b[6];
          buf[pos + 7] = f8b[7];
        }
        __name(writeDouble_f64_cpy, "writeDouble_f64_cpy");
        function writeDouble_f64_rev(val, buf, pos) {
          f64[0] = val;
          buf[pos] = f8b[7];
          buf[pos + 1] = f8b[6];
          buf[pos + 2] = f8b[5];
          buf[pos + 3] = f8b[4];
          buf[pos + 4] = f8b[3];
          buf[pos + 5] = f8b[2];
          buf[pos + 6] = f8b[1];
          buf[pos + 7] = f8b[0];
        }
        __name(writeDouble_f64_rev, "writeDouble_f64_rev");
        exports2.writeDoubleLE = le ? writeDouble_f64_cpy : writeDouble_f64_rev;
        exports2.writeDoubleBE = le ? writeDouble_f64_rev : writeDouble_f64_cpy;
        function readDouble_f64_cpy(buf, pos) {
          f8b[0] = buf[pos];
          f8b[1] = buf[pos + 1];
          f8b[2] = buf[pos + 2];
          f8b[3] = buf[pos + 3];
          f8b[4] = buf[pos + 4];
          f8b[5] = buf[pos + 5];
          f8b[6] = buf[pos + 6];
          f8b[7] = buf[pos + 7];
          return f64[0];
        }
        __name(readDouble_f64_cpy, "readDouble_f64_cpy");
        function readDouble_f64_rev(buf, pos) {
          f8b[7] = buf[pos];
          f8b[6] = buf[pos + 1];
          f8b[5] = buf[pos + 2];
          f8b[4] = buf[pos + 3];
          f8b[3] = buf[pos + 4];
          f8b[2] = buf[pos + 5];
          f8b[1] = buf[pos + 6];
          f8b[0] = buf[pos + 7];
          return f64[0];
        }
        __name(readDouble_f64_rev, "readDouble_f64_rev");
        exports2.readDoubleLE = le ? readDouble_f64_cpy : readDouble_f64_rev;
        exports2.readDoubleBE = le ? readDouble_f64_rev : readDouble_f64_cpy;
      })();
      else (function() {
        function writeDouble_ieee754(writeUint, off0, off1, val, buf, pos) {
          var sign = val < 0 ? 1 : 0;
          if (sign)
            val = -val;
          if (val === 0) {
            writeUint(0, buf, pos + off0);
            writeUint(1 / val > 0 ? (
              /* positive */
              0
            ) : (
              /* negative 0 */
              2147483648
            ), buf, pos + off1);
          } else if (isNaN(val)) {
            writeUint(0, buf, pos + off0);
            writeUint(2146959360, buf, pos + off1);
          } else if (val > 17976931348623157e292) {
            writeUint(0, buf, pos + off0);
            writeUint((sign << 31 | 2146435072) >>> 0, buf, pos + off1);
          } else {
            var mantissa;
            if (val < 22250738585072014e-324) {
              mantissa = val / 5e-324;
              writeUint(mantissa >>> 0, buf, pos + off0);
              writeUint((sign << 31 | mantissa / 4294967296) >>> 0, buf, pos + off1);
            } else {
              var exponent = Math.floor(Math.log(val) / Math.LN2);
              if (exponent === 1024)
                exponent = 1023;
              mantissa = val * Math.pow(2, -exponent);
              writeUint(mantissa * 4503599627370496 >>> 0, buf, pos + off0);
              writeUint((sign << 31 | exponent + 1023 << 20 | mantissa * 1048576 & 1048575) >>> 0, buf, pos + off1);
            }
          }
        }
        __name(writeDouble_ieee754, "writeDouble_ieee754");
        exports2.writeDoubleLE = writeDouble_ieee754.bind(null, writeUintLE, 0, 4);
        exports2.writeDoubleBE = writeDouble_ieee754.bind(null, writeUintBE, 4, 0);
        function readDouble_ieee754(readUint, off0, off1, buf, pos) {
          var lo = readUint(buf, pos + off0), hi = readUint(buf, pos + off1);
          var sign = (hi >> 31) * 2 + 1, exponent = hi >>> 20 & 2047, mantissa = 4294967296 * (hi & 1048575) + lo;
          return exponent === 2047 ? mantissa ? NaN : sign * Infinity : exponent === 0 ? sign * 5e-324 * mantissa : sign * Math.pow(2, exponent - 1075) * (mantissa + 4503599627370496);
        }
        __name(readDouble_ieee754, "readDouble_ieee754");
        exports2.readDoubleLE = readDouble_ieee754.bind(null, readUintLE, 0, 4);
        exports2.readDoubleBE = readDouble_ieee754.bind(null, readUintBE, 4, 0);
      })();
      return exports2;
    }
    __name(factory, "factory");
    function writeUintLE(val, buf, pos) {
      buf[pos] = val & 255;
      buf[pos + 1] = val >>> 8 & 255;
      buf[pos + 2] = val >>> 16 & 255;
      buf[pos + 3] = val >>> 24;
    }
    __name(writeUintLE, "writeUintLE");
    function writeUintBE(val, buf, pos) {
      buf[pos] = val >>> 24;
      buf[pos + 1] = val >>> 16 & 255;
      buf[pos + 2] = val >>> 8 & 255;
      buf[pos + 3] = val & 255;
    }
    __name(writeUintBE, "writeUintBE");
    function readUintLE(buf, pos) {
      return (buf[pos] | buf[pos + 1] << 8 | buf[pos + 2] << 16 | buf[pos + 3] << 24) >>> 0;
    }
    __name(readUintLE, "readUintLE");
    function readUintBE(buf, pos) {
      return (buf[pos] << 24 | buf[pos + 1] << 16 | buf[pos + 2] << 8 | buf[pos + 3]) >>> 0;
    }
    __name(readUintBE, "readUintBE");
  }
});

// node_modules/protobufjs/src/util/utf8.js
var require_utf8 = __commonJS({
  "node_modules/protobufjs/src/util/utf8.js"(exports) {
    "use strict";
    init_modules_watch_stub();
    var utf8 = exports;
    var looseDecoder = new TextDecoder("utf-8", { ignoreBOM: true });
    var strictDecoder;
    var TEXT_DECODER_MIN_LENGTH = 64;
    try {
      strictDecoder = new TextDecoder("utf-8", { fatal: true, ignoreBOM: true });
    } catch (err) {
      strictDecoder = looseDecoder;
    }
    utf8.length = /* @__PURE__ */ __name(function utf8_length(string) {
      var len = 0, c = 0;
      for (var i = 0; i < string.length; ++i) {
        c = string.charCodeAt(i);
        if (c < 128)
          len += 1;
        else if (c < 2048)
          len += 2;
        else if ((c & 64512) === 55296 && (string.charCodeAt(i + 1) & 64512) === 56320) {
          ++i;
          len += 4;
        } else
          len += 3;
      }
      return len;
    }, "utf8_length");
    function utf8_read_decoder(decoder, buffer, start, end) {
      var source = start === 0 && end === buffer.length ? buffer : buffer.subarray(start, end);
      return decoder.decode(source);
    }
    __name(utf8_read_decoder, "utf8_read_decoder");
    utf8.read = /* @__PURE__ */ __name(function utf8_read_loose(buffer, start, end) {
      if (end - start < 1)
        return "";
      if (end - start >= TEXT_DECODER_MIN_LENGTH)
        return utf8_read_decoder(looseDecoder, buffer, start, end);
      var str = "", i = start, c1, c2, c3, c4, c5, c6, c7, c8;
      for (; i + 7 < end; i += 8) {
        c1 = buffer[i];
        c2 = buffer[i + 1];
        c3 = buffer[i + 2];
        c4 = buffer[i + 3];
        c5 = buffer[i + 4];
        c6 = buffer[i + 5];
        c7 = buffer[i + 6];
        c8 = buffer[i + 7];
        if ((c1 | c2 | c3 | c4 | c5 | c6 | c7 | c8) & 128)
          return str + utf8_read_decoder(looseDecoder, buffer, i, end);
        str += String.fromCharCode(c1, c2, c3, c4, c5, c6, c7, c8);
      }
      for (; i < end; ++i) {
        c1 = buffer[i];
        if (c1 & 128)
          return str + utf8_read_decoder(looseDecoder, buffer, i, end);
        str += String.fromCharCode(c1);
      }
      return str;
    }, "utf8_read_loose");
    utf8.readStrict = /* @__PURE__ */ __name(function utf8_read_strict(buffer, start, end) {
      if (end - start < 1)
        return "";
      if (end - start >= TEXT_DECODER_MIN_LENGTH)
        return utf8_read_decoder(strictDecoder, buffer, start, end);
      var str = "", i = start, c1, c2, c3, c4, c5, c6, c7, c8;
      for (; i + 7 < end; i += 8) {
        c1 = buffer[i];
        c2 = buffer[i + 1];
        c3 = buffer[i + 2];
        c4 = buffer[i + 3];
        c5 = buffer[i + 4];
        c6 = buffer[i + 5];
        c7 = buffer[i + 6];
        c8 = buffer[i + 7];
        if ((c1 | c2 | c3 | c4 | c5 | c6 | c7 | c8) & 128)
          return str + utf8_read_decoder(strictDecoder, buffer, i, end);
        str += String.fromCharCode(c1, c2, c3, c4, c5, c6, c7, c8);
      }
      for (; i < end; ++i) {
        c1 = buffer[i];
        if (c1 & 128)
          return str + utf8_read_decoder(strictDecoder, buffer, i, end);
        str += String.fromCharCode(c1);
      }
      return str;
    }, "utf8_read_strict");
    utf8.write = /* @__PURE__ */ __name(function utf8_write(string, buffer, offset) {
      var start = offset, c1, c2;
      for (var i = 0; i < string.length; ++i) {
        c1 = string.charCodeAt(i);
        if (c1 < 128) {
          buffer[offset++] = c1;
        } else if (c1 < 2048) {
          buffer[offset++] = c1 >> 6 | 192;
          buffer[offset++] = c1 & 63 | 128;
        } else if ((c1 & 64512) === 55296 && ((c2 = string.charCodeAt(i + 1)) & 64512) === 56320) {
          c1 = 65536 + ((c1 & 1023) << 10) + (c2 & 1023);
          ++i;
          buffer[offset++] = c1 >> 18 | 240;
          buffer[offset++] = c1 >> 12 & 63 | 128;
          buffer[offset++] = c1 >> 6 & 63 | 128;
          buffer[offset++] = c1 & 63 | 128;
        } else {
          buffer[offset++] = c1 >> 12 | 224;
          buffer[offset++] = c1 >> 6 & 63 | 128;
          buffer[offset++] = c1 & 63 | 128;
        }
      }
      return offset - start;
    }, "utf8_write");
  }
});

// node_modules/protobufjs/src/util/pool.js
var require_pool = __commonJS({
  "node_modules/protobufjs/src/util/pool.js"(exports, module) {
    "use strict";
    init_modules_watch_stub();
    module.exports = pool;
    function pool(alloc, slice, size) {
      var SIZE = size || 8192;
      var MAX = SIZE >>> 1;
      var slab = null;
      var offset = SIZE;
      return /* @__PURE__ */ __name(function pool_alloc(size2) {
        if (size2 < 1 || size2 > MAX)
          return alloc(size2);
        if (offset + size2 > SIZE) {
          slab = alloc(SIZE);
          offset = 0;
        }
        var buf = slice.call(slab, offset, offset += size2);
        if (offset & 7)
          offset = (offset | 7) + 1;
        return buf;
      }, "pool_alloc");
    }
    __name(pool, "pool");
  }
});

// node_modules/protobufjs/src/util/longbits.js
var require_longbits = __commonJS({
  "node_modules/protobufjs/src/util/longbits.js"(exports, module) {
    "use strict";
    init_modules_watch_stub();
    module.exports = LongBits;
    var Long;
    function LongBits(lo, hi) {
      this.lo = lo >>> 0;
      this.hi = hi >>> 0;
    }
    __name(LongBits, "LongBits");
    var zero = LongBits.zero = new LongBits(0, 0);
    zero.toNumber = function() {
      return 0;
    };
    zero.zzEncode = zero.zzDecode = function() {
      return this;
    };
    zero.length = function() {
      return 1;
    };
    var zeroHash = LongBits.zeroHash = "\0\0\0\0\0\0\0\0";
    LongBits.fromNumber = /* @__PURE__ */ __name(function fromNumber(value) {
      if (value === 0)
        return zero;
      var sign = value < 0;
      if (sign)
        value = -value;
      var lo = value >>> 0, hi = (value - lo) / 4294967296 >>> 0;
      if (sign) {
        hi = ~hi >>> 0;
        lo = ~lo >>> 0;
        if (++lo > 4294967295) {
          lo = 0;
          if (++hi > 4294967295)
            hi = 0;
        }
      }
      return new LongBits(lo, hi);
    }, "fromNumber");
    LongBits.from = /* @__PURE__ */ __name(function from(value) {
      if (typeof value === "number")
        return LongBits.fromNumber(value);
      if (typeof value === "string" || value instanceof String) {
        if (Long)
          value = Long.fromString(value);
        else
          return LongBits.fromNumber(parseInt(value, 10));
      }
      return value.low || value.high ? new LongBits(value.low >>> 0, value.high >>> 0) : zero;
    }, "from");
    LongBits.prototype.toNumber = /* @__PURE__ */ __name(function toNumber(unsigned) {
      if (!unsigned && this.hi >>> 31) {
        var lo = ~this.lo + 1 >>> 0, hi = ~this.hi >>> 0;
        if (!lo)
          hi = hi + 1 >>> 0;
        return -(lo + hi * 4294967296);
      }
      return this.lo + this.hi * 4294967296;
    }, "toNumber");
    LongBits.prototype.toLong = /* @__PURE__ */ __name(function toLong(unsigned) {
      return Long ? new Long(this.lo | 0, this.hi | 0, Boolean(unsigned)) : { low: this.lo | 0, high: this.hi | 0, unsigned: Boolean(unsigned) };
    }, "toLong");
    var charCodeAt = String.prototype.charCodeAt;
    LongBits.fromHash = /* @__PURE__ */ __name(function fromHash(hash) {
      if (hash === zeroHash)
        return zero;
      return new LongBits(
        (charCodeAt.call(hash, 0) | charCodeAt.call(hash, 1) << 8 | charCodeAt.call(hash, 2) << 16 | charCodeAt.call(hash, 3) << 24) >>> 0,
        (charCodeAt.call(hash, 4) | charCodeAt.call(hash, 5) << 8 | charCodeAt.call(hash, 6) << 16 | charCodeAt.call(hash, 7) << 24) >>> 0
      );
    }, "fromHash");
    LongBits.prototype.toHash = /* @__PURE__ */ __name(function toHash() {
      return String.fromCharCode(
        this.lo & 255,
        this.lo >>> 8 & 255,
        this.lo >>> 16 & 255,
        this.lo >>> 24,
        this.hi & 255,
        this.hi >>> 8 & 255,
        this.hi >>> 16 & 255,
        this.hi >>> 24
      );
    }, "toHash");
    LongBits.prototype.zzEncode = /* @__PURE__ */ __name(function zzEncode() {
      var mask = this.hi >> 31;
      this.hi = ((this.hi << 1 | this.lo >>> 31) ^ mask) >>> 0;
      this.lo = (this.lo << 1 ^ mask) >>> 0;
      return this;
    }, "zzEncode");
    LongBits.prototype.zzDecode = /* @__PURE__ */ __name(function zzDecode() {
      var mask = -(this.lo & 1);
      this.lo = ((this.lo >>> 1 | this.hi << 31) ^ mask) >>> 0;
      this.hi = (this.hi >>> 1 ^ mask) >>> 0;
      return this;
    }, "zzDecode");
    LongBits.prototype.length = /* @__PURE__ */ __name(function length() {
      var part0 = this.lo, part1 = (this.lo >>> 28 | this.hi << 4) >>> 0, part2 = this.hi >>> 24;
      return part2 === 0 ? part1 === 0 ? part0 < 16384 ? part0 < 128 ? 1 : 2 : part0 < 2097152 ? 3 : 4 : part1 < 16384 ? part1 < 128 ? 5 : 6 : part1 < 2097152 ? 7 : 8 : part2 < 128 ? 9 : 10;
    }, "length");
    LongBits._configure = function(Long_) {
      Long = Long_;
    };
  }
});

// node_modules/long/umd/index.js
var require_umd = __commonJS({
  "node_modules/long/umd/index.js"(exports, module) {
    init_modules_watch_stub();
    (function(global2, factory) {
      function preferDefault(exports2) {
        return exports2.default || exports2;
      }
      __name(preferDefault, "preferDefault");
      if (typeof define === "function" && define.amd) {
        define([], function() {
          var exports2 = {};
          factory(exports2);
          return preferDefault(exports2);
        });
      } else if (typeof exports === "object") {
        factory(exports);
        if (typeof module === "object") module.exports = preferDefault(exports);
      } else {
        (function() {
          var exports2 = {};
          factory(exports2);
          global2.Long = preferDefault(exports2);
        })();
      }
    })(
      typeof globalThis !== "undefined" ? globalThis : typeof self !== "undefined" ? self : exports,
      function(_exports) {
        "use strict";
        Object.defineProperty(_exports, "__esModule", {
          value: true
        });
        _exports.default = void 0;
        var wasm = null;
        try {
          wasm = new WebAssembly.Instance(
            new WebAssembly.Module(
              new Uint8Array([
                // \0asm
                0,
                97,
                115,
                109,
                // version 1
                1,
                0,
                0,
                0,
                // section "type"
                1,
                13,
                2,
                // 0, () => i32
                96,
                0,
                1,
                127,
                // 1, (i32, i32, i32, i32) => i32
                96,
                4,
                127,
                127,
                127,
                127,
                1,
                127,
                // section "function"
                3,
                7,
                6,
                // 0, type 0
                0,
                // 1, type 1
                1,
                // 2, type 1
                1,
                // 3, type 1
                1,
                // 4, type 1
                1,
                // 5, type 1
                1,
                // section "global"
                6,
                6,
                1,
                // 0, "high", mutable i32
                127,
                1,
                65,
                0,
                11,
                // section "export"
                7,
                50,
                6,
                // 0, "mul"
                3,
                109,
                117,
                108,
                0,
                1,
                // 1, "div_s"
                5,
                100,
                105,
                118,
                95,
                115,
                0,
                2,
                // 2, "div_u"
                5,
                100,
                105,
                118,
                95,
                117,
                0,
                3,
                // 3, "rem_s"
                5,
                114,
                101,
                109,
                95,
                115,
                0,
                4,
                // 4, "rem_u"
                5,
                114,
                101,
                109,
                95,
                117,
                0,
                5,
                // 5, "get_high"
                8,
                103,
                101,
                116,
                95,
                104,
                105,
                103,
                104,
                0,
                0,
                // section "code"
                10,
                191,
                1,
                6,
                // 0, "get_high"
                4,
                0,
                35,
                0,
                11,
                // 1, "mul"
                36,
                1,
                1,
                126,
                32,
                0,
                173,
                32,
                1,
                173,
                66,
                32,
                134,
                132,
                32,
                2,
                173,
                32,
                3,
                173,
                66,
                32,
                134,
                132,
                126,
                34,
                4,
                66,
                32,
                135,
                167,
                36,
                0,
                32,
                4,
                167,
                11,
                // 2, "div_s"
                36,
                1,
                1,
                126,
                32,
                0,
                173,
                32,
                1,
                173,
                66,
                32,
                134,
                132,
                32,
                2,
                173,
                32,
                3,
                173,
                66,
                32,
                134,
                132,
                127,
                34,
                4,
                66,
                32,
                135,
                167,
                36,
                0,
                32,
                4,
                167,
                11,
                // 3, "div_u"
                36,
                1,
                1,
                126,
                32,
                0,
                173,
                32,
                1,
                173,
                66,
                32,
                134,
                132,
                32,
                2,
                173,
                32,
                3,
                173,
                66,
                32,
                134,
                132,
                128,
                34,
                4,
                66,
                32,
                135,
                167,
                36,
                0,
                32,
                4,
                167,
                11,
                // 4, "rem_s"
                36,
                1,
                1,
                126,
                32,
                0,
                173,
                32,
                1,
                173,
                66,
                32,
                134,
                132,
                32,
                2,
                173,
                32,
                3,
                173,
                66,
                32,
                134,
                132,
                129,
                34,
                4,
                66,
                32,
                135,
                167,
                36,
                0,
                32,
                4,
                167,
                11,
                // 5, "rem_u"
                36,
                1,
                1,
                126,
                32,
                0,
                173,
                32,
                1,
                173,
                66,
                32,
                134,
                132,
                32,
                2,
                173,
                32,
                3,
                173,
                66,
                32,
                134,
                132,
                130,
                34,
                4,
                66,
                32,
                135,
                167,
                36,
                0,
                32,
                4,
                167,
                11
              ])
            ),
            {}
          ).exports;
        } catch {
        }
        function Long(low, high, unsigned) {
          this.low = low | 0;
          this.high = high | 0;
          this.unsigned = !!unsigned;
        }
        __name(Long, "Long");
        Long.prototype.__isLong__;
        Object.defineProperty(Long.prototype, "__isLong__", {
          value: true
        });
        function isLong(obj) {
          return (obj && obj["__isLong__"]) === true;
        }
        __name(isLong, "isLong");
        function ctz32(value) {
          var c = Math.clz32(value & -value);
          return value ? 31 - c : c;
        }
        __name(ctz32, "ctz32");
        Long.isLong = isLong;
        var INT_CACHE = {};
        var UINT_CACHE = {};
        function fromInt(value, unsigned) {
          var obj, cachedObj, cache;
          if (unsigned) {
            value >>>= 0;
            if (cache = 0 <= value && value < 256) {
              cachedObj = UINT_CACHE[value];
              if (cachedObj) return cachedObj;
            }
            obj = fromBits(value, 0, true);
            if (cache) UINT_CACHE[value] = obj;
            return obj;
          } else {
            value |= 0;
            if (cache = -128 <= value && value < 128) {
              cachedObj = INT_CACHE[value];
              if (cachedObj) return cachedObj;
            }
            obj = fromBits(value, value < 0 ? -1 : 0, false);
            if (cache) INT_CACHE[value] = obj;
            return obj;
          }
        }
        __name(fromInt, "fromInt");
        Long.fromInt = fromInt;
        function fromNumber(value, unsigned) {
          if (isNaN(value)) return unsigned ? UZERO : ZERO;
          if (unsigned) {
            if (value < 0) return UZERO;
            if (value >= TWO_PWR_64_DBL) return MAX_UNSIGNED_VALUE;
          } else {
            if (value <= -TWO_PWR_63_DBL) return MIN_VALUE;
            if (value + 1 >= TWO_PWR_63_DBL) return MAX_VALUE;
          }
          if (value < 0) return fromNumber(-value, unsigned).neg();
          return fromBits(
            value % TWO_PWR_32_DBL | 0,
            value / TWO_PWR_32_DBL | 0,
            unsigned
          );
        }
        __name(fromNumber, "fromNumber");
        Long.fromNumber = fromNumber;
        function fromBits(lowBits, highBits, unsigned) {
          return new Long(lowBits, highBits, unsigned);
        }
        __name(fromBits, "fromBits");
        Long.fromBits = fromBits;
        var pow_dbl = Math.pow;
        function fromString(str, unsigned, radix) {
          if (str.length === 0) throw Error("empty string");
          if (typeof unsigned === "number") {
            radix = unsigned;
            unsigned = false;
          } else {
            unsigned = !!unsigned;
          }
          if (str === "NaN" || str === "Infinity" || str === "+Infinity" || str === "-Infinity")
            return unsigned ? UZERO : ZERO;
          radix = radix || 10;
          if (radix < 2 || 36 < radix) throw RangeError("radix");
          var p;
          if ((p = str.indexOf("-")) > 0) throw Error("interior hyphen");
          else if (p === 0) {
            return fromString(str.substring(1), unsigned, radix).neg();
          }
          var radixToPower = fromNumber(pow_dbl(radix, 8));
          var result = ZERO;
          for (var i = 0; i < str.length; i += 8) {
            var size = Math.min(8, str.length - i), value = parseInt(str.substring(i, i + size), radix);
            if (size < 8) {
              var power = fromNumber(pow_dbl(radix, size));
              result = result.mul(power).add(fromNumber(value));
            } else {
              result = result.mul(radixToPower);
              result = result.add(fromNumber(value));
            }
          }
          result.unsigned = unsigned;
          return result;
        }
        __name(fromString, "fromString");
        Long.fromString = fromString;
        function fromValue(val, unsigned) {
          if (typeof val === "number") return fromNumber(val, unsigned);
          if (typeof val === "string") return fromString(val, unsigned);
          return fromBits(
            val.low,
            val.high,
            typeof unsigned === "boolean" ? unsigned : val.unsigned
          );
        }
        __name(fromValue, "fromValue");
        Long.fromValue = fromValue;
        var TWO_PWR_16_DBL = 1 << 16;
        var TWO_PWR_24_DBL = 1 << 24;
        var TWO_PWR_32_DBL = TWO_PWR_16_DBL * TWO_PWR_16_DBL;
        var TWO_PWR_64_DBL = TWO_PWR_32_DBL * TWO_PWR_32_DBL;
        var TWO_PWR_63_DBL = TWO_PWR_64_DBL / 2;
        var TWO_PWR_24 = fromInt(TWO_PWR_24_DBL);
        var ZERO = fromInt(0);
        Long.ZERO = ZERO;
        var UZERO = fromInt(0, true);
        Long.UZERO = UZERO;
        var ONE = fromInt(1);
        Long.ONE = ONE;
        var UONE = fromInt(1, true);
        Long.UONE = UONE;
        var NEG_ONE = fromInt(-1);
        Long.NEG_ONE = NEG_ONE;
        var MAX_VALUE = fromBits(4294967295 | 0, 2147483647 | 0, false);
        Long.MAX_VALUE = MAX_VALUE;
        var MAX_UNSIGNED_VALUE = fromBits(4294967295 | 0, 4294967295 | 0, true);
        Long.MAX_UNSIGNED_VALUE = MAX_UNSIGNED_VALUE;
        var MIN_VALUE = fromBits(0, 2147483648 | 0, false);
        Long.MIN_VALUE = MIN_VALUE;
        var LongPrototype = Long.prototype;
        LongPrototype.toInt = /* @__PURE__ */ __name(function toInt() {
          return this.unsigned ? this.low >>> 0 : this.low;
        }, "toInt");
        LongPrototype.toNumber = /* @__PURE__ */ __name(function toNumber() {
          if (this.unsigned)
            return (this.high >>> 0) * TWO_PWR_32_DBL + (this.low >>> 0);
          return this.high * TWO_PWR_32_DBL + (this.low >>> 0);
        }, "toNumber");
        LongPrototype.toString = /* @__PURE__ */ __name(function toString(radix) {
          radix = radix || 10;
          if (radix < 2 || 36 < radix) throw RangeError("radix");
          if (this.isZero()) return "0";
          if (this.isNegative()) {
            if (this.eq(MIN_VALUE)) {
              var radixLong = fromNumber(radix), div = this.div(radixLong), rem1 = div.mul(radixLong).sub(this);
              return div.toString(radix) + rem1.toInt().toString(radix);
            } else return "-" + this.neg().toString(radix);
          }
          var radixToPower = fromNumber(pow_dbl(radix, 6), this.unsigned), rem = this;
          var result = "";
          while (true) {
            var remDiv = rem.div(radixToPower), intval = rem.sub(remDiv.mul(radixToPower)).toInt() >>> 0, digits = intval.toString(radix);
            rem = remDiv;
            if (rem.isZero()) return digits + result;
            else {
              while (digits.length < 6) digits = "0" + digits;
              result = "" + digits + result;
            }
          }
        }, "toString");
        LongPrototype.getHighBits = /* @__PURE__ */ __name(function getHighBits() {
          return this.high;
        }, "getHighBits");
        LongPrototype.getHighBitsUnsigned = /* @__PURE__ */ __name(function getHighBitsUnsigned() {
          return this.high >>> 0;
        }, "getHighBitsUnsigned");
        LongPrototype.getLowBits = /* @__PURE__ */ __name(function getLowBits() {
          return this.low;
        }, "getLowBits");
        LongPrototype.getLowBitsUnsigned = /* @__PURE__ */ __name(function getLowBitsUnsigned() {
          return this.low >>> 0;
        }, "getLowBitsUnsigned");
        LongPrototype.getNumBitsAbs = /* @__PURE__ */ __name(function getNumBitsAbs() {
          if (this.isNegative())
            return this.eq(MIN_VALUE) ? 64 : this.neg().getNumBitsAbs();
          var val = this.high != 0 ? this.high : this.low;
          for (var bit = 31; bit > 0; bit--) if ((val & 1 << bit) != 0) break;
          return this.high != 0 ? bit + 33 : bit + 1;
        }, "getNumBitsAbs");
        LongPrototype.isSafeInteger = /* @__PURE__ */ __name(function isSafeInteger() {
          var top11Bits = this.high >> 21;
          if (!top11Bits) return true;
          if (this.unsigned) return false;
          return top11Bits === -1 && !(this.low === 0 && this.high === -2097152);
        }, "isSafeInteger");
        LongPrototype.isZero = /* @__PURE__ */ __name(function isZero() {
          return this.high === 0 && this.low === 0;
        }, "isZero");
        LongPrototype.eqz = LongPrototype.isZero;
        LongPrototype.isNegative = /* @__PURE__ */ __name(function isNegative() {
          return !this.unsigned && this.high < 0;
        }, "isNegative");
        LongPrototype.isPositive = /* @__PURE__ */ __name(function isPositive() {
          return this.unsigned || this.high >= 0;
        }, "isPositive");
        LongPrototype.isOdd = /* @__PURE__ */ __name(function isOdd() {
          return (this.low & 1) === 1;
        }, "isOdd");
        LongPrototype.isEven = /* @__PURE__ */ __name(function isEven() {
          return (this.low & 1) === 0;
        }, "isEven");
        LongPrototype.equals = /* @__PURE__ */ __name(function equals(other) {
          if (!isLong(other)) other = fromValue(other);
          if (this.unsigned !== other.unsigned && this.high >>> 31 === 1 && other.high >>> 31 === 1)
            return false;
          return this.high === other.high && this.low === other.low;
        }, "equals");
        LongPrototype.eq = LongPrototype.equals;
        LongPrototype.notEquals = /* @__PURE__ */ __name(function notEquals(other) {
          return !this.eq(
            /* validates */
            other
          );
        }, "notEquals");
        LongPrototype.neq = LongPrototype.notEquals;
        LongPrototype.ne = LongPrototype.notEquals;
        LongPrototype.lessThan = /* @__PURE__ */ __name(function lessThan(other) {
          return this.comp(
            /* validates */
            other
          ) < 0;
        }, "lessThan");
        LongPrototype.lt = LongPrototype.lessThan;
        LongPrototype.lessThanOrEqual = /* @__PURE__ */ __name(function lessThanOrEqual(other) {
          return this.comp(
            /* validates */
            other
          ) <= 0;
        }, "lessThanOrEqual");
        LongPrototype.lte = LongPrototype.lessThanOrEqual;
        LongPrototype.le = LongPrototype.lessThanOrEqual;
        LongPrototype.greaterThan = /* @__PURE__ */ __name(function greaterThan(other) {
          return this.comp(
            /* validates */
            other
          ) > 0;
        }, "greaterThan");
        LongPrototype.gt = LongPrototype.greaterThan;
        LongPrototype.greaterThanOrEqual = /* @__PURE__ */ __name(function greaterThanOrEqual(other) {
          return this.comp(
            /* validates */
            other
          ) >= 0;
        }, "greaterThanOrEqual");
        LongPrototype.gte = LongPrototype.greaterThanOrEqual;
        LongPrototype.ge = LongPrototype.greaterThanOrEqual;
        LongPrototype.compare = /* @__PURE__ */ __name(function compare(other) {
          if (!isLong(other)) other = fromValue(other);
          if (this.eq(other)) return 0;
          var thisNeg = this.isNegative(), otherNeg = other.isNegative();
          if (thisNeg && !otherNeg) return -1;
          if (!thisNeg && otherNeg) return 1;
          if (!this.unsigned) return this.sub(other).isNegative() ? -1 : 1;
          return other.high >>> 0 > this.high >>> 0 || other.high === this.high && other.low >>> 0 > this.low >>> 0 ? -1 : 1;
        }, "compare");
        LongPrototype.comp = LongPrototype.compare;
        LongPrototype.negate = /* @__PURE__ */ __name(function negate() {
          if (!this.unsigned && this.eq(MIN_VALUE)) return MIN_VALUE;
          return this.not().add(ONE);
        }, "negate");
        LongPrototype.neg = LongPrototype.negate;
        LongPrototype.add = /* @__PURE__ */ __name(function add(addend) {
          if (!isLong(addend)) addend = fromValue(addend);
          var a48 = this.high >>> 16;
          var a32 = this.high & 65535;
          var a16 = this.low >>> 16;
          var a00 = this.low & 65535;
          var b48 = addend.high >>> 16;
          var b32 = addend.high & 65535;
          var b16 = addend.low >>> 16;
          var b00 = addend.low & 65535;
          var c48 = 0, c32 = 0, c16 = 0, c00 = 0;
          c00 += a00 + b00;
          c16 += c00 >>> 16;
          c00 &= 65535;
          c16 += a16 + b16;
          c32 += c16 >>> 16;
          c16 &= 65535;
          c32 += a32 + b32;
          c48 += c32 >>> 16;
          c32 &= 65535;
          c48 += a48 + b48;
          c48 &= 65535;
          return fromBits(c16 << 16 | c00, c48 << 16 | c32, this.unsigned);
        }, "add");
        LongPrototype.subtract = /* @__PURE__ */ __name(function subtract(subtrahend) {
          if (!isLong(subtrahend)) subtrahend = fromValue(subtrahend);
          return this.add(subtrahend.neg());
        }, "subtract");
        LongPrototype.sub = LongPrototype.subtract;
        LongPrototype.multiply = /* @__PURE__ */ __name(function multiply(multiplier) {
          if (this.isZero()) return this;
          if (!isLong(multiplier)) multiplier = fromValue(multiplier);
          if (wasm) {
            var low = wasm["mul"](
              this.low,
              this.high,
              multiplier.low,
              multiplier.high
            );
            return fromBits(low, wasm["get_high"](), this.unsigned);
          }
          if (multiplier.isZero()) return this.unsigned ? UZERO : ZERO;
          if (this.eq(MIN_VALUE)) return multiplier.isOdd() ? MIN_VALUE : ZERO;
          if (multiplier.eq(MIN_VALUE)) return this.isOdd() ? MIN_VALUE : ZERO;
          if (this.isNegative()) {
            if (multiplier.isNegative()) return this.neg().mul(multiplier.neg());
            else return this.neg().mul(multiplier).neg();
          } else if (multiplier.isNegative())
            return this.mul(multiplier.neg()).neg();
          if (this.lt(TWO_PWR_24) && multiplier.lt(TWO_PWR_24))
            return fromNumber(
              this.toNumber() * multiplier.toNumber(),
              this.unsigned
            );
          var a48 = this.high >>> 16;
          var a32 = this.high & 65535;
          var a16 = this.low >>> 16;
          var a00 = this.low & 65535;
          var b48 = multiplier.high >>> 16;
          var b32 = multiplier.high & 65535;
          var b16 = multiplier.low >>> 16;
          var b00 = multiplier.low & 65535;
          var c48 = 0, c32 = 0, c16 = 0, c00 = 0;
          c00 += a00 * b00;
          c16 += c00 >>> 16;
          c00 &= 65535;
          c16 += a16 * b00;
          c32 += c16 >>> 16;
          c16 &= 65535;
          c16 += a00 * b16;
          c32 += c16 >>> 16;
          c16 &= 65535;
          c32 += a32 * b00;
          c48 += c32 >>> 16;
          c32 &= 65535;
          c32 += a16 * b16;
          c48 += c32 >>> 16;
          c32 &= 65535;
          c32 += a00 * b32;
          c48 += c32 >>> 16;
          c32 &= 65535;
          c48 += a48 * b00 + a32 * b16 + a16 * b32 + a00 * b48;
          c48 &= 65535;
          return fromBits(c16 << 16 | c00, c48 << 16 | c32, this.unsigned);
        }, "multiply");
        LongPrototype.mul = LongPrototype.multiply;
        LongPrototype.divide = /* @__PURE__ */ __name(function divide(divisor) {
          if (!isLong(divisor)) divisor = fromValue(divisor);
          if (divisor.isZero()) throw Error("division by zero");
          if (wasm) {
            if (!this.unsigned && this.high === -2147483648 && divisor.low === -1 && divisor.high === -1) {
              return this;
            }
            var low = (this.unsigned ? wasm["div_u"] : wasm["div_s"])(
              this.low,
              this.high,
              divisor.low,
              divisor.high
            );
            return fromBits(low, wasm["get_high"](), this.unsigned);
          }
          if (this.isZero()) return this.unsigned ? UZERO : ZERO;
          var approx, rem, res;
          if (!this.unsigned) {
            if (this.eq(MIN_VALUE)) {
              if (divisor.eq(ONE) || divisor.eq(NEG_ONE))
                return MIN_VALUE;
              else if (divisor.eq(MIN_VALUE)) return ONE;
              else {
                var halfThis = this.shr(1);
                approx = halfThis.div(divisor).shl(1);
                if (approx.eq(ZERO)) {
                  return divisor.isNegative() ? ONE : NEG_ONE;
                } else {
                  rem = this.sub(divisor.mul(approx));
                  res = approx.add(rem.div(divisor));
                  return res;
                }
              }
            } else if (divisor.eq(MIN_VALUE)) return this.unsigned ? UZERO : ZERO;
            if (this.isNegative()) {
              if (divisor.isNegative()) return this.neg().div(divisor.neg());
              return this.neg().div(divisor).neg();
            } else if (divisor.isNegative()) return this.div(divisor.neg()).neg();
            res = ZERO;
          } else {
            if (!divisor.unsigned) divisor = divisor.toUnsigned();
            if (divisor.gt(this)) return UZERO;
            if (divisor.gt(this.shru(1)))
              return UONE;
            res = UZERO;
          }
          rem = this;
          while (rem.gte(divisor)) {
            approx = Math.max(1, Math.floor(rem.toNumber() / divisor.toNumber()));
            var log2 = Math.ceil(Math.log(approx) / Math.LN2), delta = log2 <= 48 ? 1 : pow_dbl(2, log2 - 48), approxRes = fromNumber(approx), approxRem = approxRes.mul(divisor);
            while (approxRem.isNegative() || approxRem.gt(rem)) {
              approx -= delta;
              approxRes = fromNumber(approx, this.unsigned);
              approxRem = approxRes.mul(divisor);
            }
            if (approxRes.isZero()) approxRes = ONE;
            res = res.add(approxRes);
            rem = rem.sub(approxRem);
          }
          return res;
        }, "divide");
        LongPrototype.div = LongPrototype.divide;
        LongPrototype.modulo = /* @__PURE__ */ __name(function modulo(divisor) {
          if (!isLong(divisor)) divisor = fromValue(divisor);
          if (wasm) {
            var low = (this.unsigned ? wasm["rem_u"] : wasm["rem_s"])(
              this.low,
              this.high,
              divisor.low,
              divisor.high
            );
            return fromBits(low, wasm["get_high"](), this.unsigned);
          }
          return this.sub(this.div(divisor).mul(divisor));
        }, "modulo");
        LongPrototype.mod = LongPrototype.modulo;
        LongPrototype.rem = LongPrototype.modulo;
        LongPrototype.not = /* @__PURE__ */ __name(function not() {
          return fromBits(~this.low, ~this.high, this.unsigned);
        }, "not");
        LongPrototype.countLeadingZeros = /* @__PURE__ */ __name(function countLeadingZeros() {
          return this.high ? Math.clz32(this.high) : Math.clz32(this.low) + 32;
        }, "countLeadingZeros");
        LongPrototype.clz = LongPrototype.countLeadingZeros;
        LongPrototype.countTrailingZeros = /* @__PURE__ */ __name(function countTrailingZeros() {
          return this.low ? ctz32(this.low) : ctz32(this.high) + 32;
        }, "countTrailingZeros");
        LongPrototype.ctz = LongPrototype.countTrailingZeros;
        LongPrototype.and = /* @__PURE__ */ __name(function and(other) {
          if (!isLong(other)) other = fromValue(other);
          return fromBits(
            this.low & other.low,
            this.high & other.high,
            this.unsigned
          );
        }, "and");
        LongPrototype.or = /* @__PURE__ */ __name(function or(other) {
          if (!isLong(other)) other = fromValue(other);
          return fromBits(
            this.low | other.low,
            this.high | other.high,
            this.unsigned
          );
        }, "or");
        LongPrototype.xor = /* @__PURE__ */ __name(function xor(other) {
          if (!isLong(other)) other = fromValue(other);
          return fromBits(
            this.low ^ other.low,
            this.high ^ other.high,
            this.unsigned
          );
        }, "xor");
        LongPrototype.shiftLeft = /* @__PURE__ */ __name(function shiftLeft(numBits) {
          if (isLong(numBits)) numBits = numBits.toInt();
          if ((numBits &= 63) === 0) return this;
          else if (numBits < 32)
            return fromBits(
              this.low << numBits,
              this.high << numBits | this.low >>> 32 - numBits,
              this.unsigned
            );
          else return fromBits(0, this.low << numBits - 32, this.unsigned);
        }, "shiftLeft");
        LongPrototype.shl = LongPrototype.shiftLeft;
        LongPrototype.shiftRight = /* @__PURE__ */ __name(function shiftRight(numBits) {
          if (isLong(numBits)) numBits = numBits.toInt();
          if ((numBits &= 63) === 0) return this;
          else if (numBits < 32)
            return fromBits(
              this.low >>> numBits | this.high << 32 - numBits,
              this.high >> numBits,
              this.unsigned
            );
          else
            return fromBits(
              this.high >> numBits - 32,
              this.high >= 0 ? 0 : -1,
              this.unsigned
            );
        }, "shiftRight");
        LongPrototype.shr = LongPrototype.shiftRight;
        LongPrototype.shiftRightUnsigned = /* @__PURE__ */ __name(function shiftRightUnsigned(numBits) {
          if (isLong(numBits)) numBits = numBits.toInt();
          if ((numBits &= 63) === 0) return this;
          if (numBits < 32)
            return fromBits(
              this.low >>> numBits | this.high << 32 - numBits,
              this.high >>> numBits,
              this.unsigned
            );
          if (numBits === 32) return fromBits(this.high, 0, this.unsigned);
          return fromBits(this.high >>> numBits - 32, 0, this.unsigned);
        }, "shiftRightUnsigned");
        LongPrototype.shru = LongPrototype.shiftRightUnsigned;
        LongPrototype.shr_u = LongPrototype.shiftRightUnsigned;
        LongPrototype.rotateLeft = /* @__PURE__ */ __name(function rotateLeft(numBits) {
          var b;
          if (isLong(numBits)) numBits = numBits.toInt();
          if ((numBits &= 63) === 0) return this;
          if (numBits === 32) return fromBits(this.high, this.low, this.unsigned);
          if (numBits < 32) {
            b = 32 - numBits;
            return fromBits(
              this.low << numBits | this.high >>> b,
              this.high << numBits | this.low >>> b,
              this.unsigned
            );
          }
          numBits -= 32;
          b = 32 - numBits;
          return fromBits(
            this.high << numBits | this.low >>> b,
            this.low << numBits | this.high >>> b,
            this.unsigned
          );
        }, "rotateLeft");
        LongPrototype.rotl = LongPrototype.rotateLeft;
        LongPrototype.rotateRight = /* @__PURE__ */ __name(function rotateRight(numBits) {
          var b;
          if (isLong(numBits)) numBits = numBits.toInt();
          if ((numBits &= 63) === 0) return this;
          if (numBits === 32) return fromBits(this.high, this.low, this.unsigned);
          if (numBits < 32) {
            b = 32 - numBits;
            return fromBits(
              this.high << b | this.low >>> numBits,
              this.low << b | this.high >>> numBits,
              this.unsigned
            );
          }
          numBits -= 32;
          b = 32 - numBits;
          return fromBits(
            this.low << b | this.high >>> numBits,
            this.high << b | this.low >>> numBits,
            this.unsigned
          );
        }, "rotateRight");
        LongPrototype.rotr = LongPrototype.rotateRight;
        LongPrototype.toSigned = /* @__PURE__ */ __name(function toSigned() {
          if (!this.unsigned) return this;
          return fromBits(this.low, this.high, false);
        }, "toSigned");
        LongPrototype.toUnsigned = /* @__PURE__ */ __name(function toUnsigned() {
          if (this.unsigned) return this;
          return fromBits(this.low, this.high, true);
        }, "toUnsigned");
        LongPrototype.toBytes = /* @__PURE__ */ __name(function toBytes(le) {
          return le ? this.toBytesLE() : this.toBytesBE();
        }, "toBytes");
        LongPrototype.toBytesLE = /* @__PURE__ */ __name(function toBytesLE() {
          var hi = this.high, lo = this.low;
          return [
            lo & 255,
            lo >>> 8 & 255,
            lo >>> 16 & 255,
            lo >>> 24,
            hi & 255,
            hi >>> 8 & 255,
            hi >>> 16 & 255,
            hi >>> 24
          ];
        }, "toBytesLE");
        LongPrototype.toBytesBE = /* @__PURE__ */ __name(function toBytesBE() {
          var hi = this.high, lo = this.low;
          return [
            hi >>> 24,
            hi >>> 16 & 255,
            hi >>> 8 & 255,
            hi & 255,
            lo >>> 24,
            lo >>> 16 & 255,
            lo >>> 8 & 255,
            lo & 255
          ];
        }, "toBytesBE");
        Long.fromBytes = /* @__PURE__ */ __name(function fromBytes(bytes, unsigned, le) {
          return le ? Long.fromBytesLE(bytes, unsigned) : Long.fromBytesBE(bytes, unsigned);
        }, "fromBytes");
        Long.fromBytesLE = /* @__PURE__ */ __name(function fromBytesLE(bytes, unsigned) {
          return new Long(
            bytes[0] | bytes[1] << 8 | bytes[2] << 16 | bytes[3] << 24,
            bytes[4] | bytes[5] << 8 | bytes[6] << 16 | bytes[7] << 24,
            unsigned
          );
        }, "fromBytesLE");
        Long.fromBytesBE = /* @__PURE__ */ __name(function fromBytesBE(bytes, unsigned) {
          return new Long(
            bytes[4] << 24 | bytes[5] << 16 | bytes[6] << 8 | bytes[7],
            bytes[0] << 24 | bytes[1] << 16 | bytes[2] << 8 | bytes[3],
            unsigned
          );
        }, "fromBytesBE");
        if (typeof BigInt === "function") {
          Long.fromBigInt = /* @__PURE__ */ __name(function fromBigInt(value, unsigned) {
            var lowBits = Number(BigInt.asIntN(32, value));
            var highBits = Number(BigInt.asIntN(32, value >> BigInt(32)));
            return fromBits(lowBits, highBits, unsigned);
          }, "fromBigInt");
          Long.fromValue = /* @__PURE__ */ __name(function fromValueWithBigInt(value, unsigned) {
            if (typeof value === "bigint") return Long.fromBigInt(value, unsigned);
            return fromValue(value, unsigned);
          }, "fromValueWithBigInt");
          LongPrototype.toBigInt = /* @__PURE__ */ __name(function toBigInt() {
            var lowBigInt = BigInt(this.low >>> 0);
            var highBigInt = BigInt(this.unsigned ? this.high >>> 0 : this.high);
            return highBigInt << BigInt(32) | lowBigInt;
          }, "toBigInt");
        }
        var _default = _exports.default = Long;
      }
    );
  }
});

// node_modules/protobufjs/src/util/minimal.js
var require_minimal = __commonJS({
  "node_modules/protobufjs/src/util/minimal.js"(exports) {
    "use strict";
    init_modules_watch_stub();
    var util = exports;
    util.asPromise = require_aspromise();
    util.base64 = require_base64();
    util.EventEmitter = require_eventemitter();
    util.float = require_float();
    util.utf8 = require_utf8();
    util.pool = require_pool();
    util.LongBits = require_longbits();
    function isUnsafeProperty(key) {
      return key === "__proto__" || key === "prototype" || key === "constructor";
    }
    __name(isUnsafeProperty, "isUnsafeProperty");
    util.isUnsafeProperty = isUnsafeProperty;
    util.isNode = Boolean(typeof global !== "undefined" && global && global.process && global.process.versions && global.process.versions.node);
    util.global = util.isNode && global || typeof window !== "undefined" && window || typeof self !== "undefined" && self || typeof globalThis !== "undefined" && globalThis || exports;
    util.emptyArray = Object.freeze ? Object.freeze([]) : (
      /* istanbul ignore next */
      []
    );
    util.emptyObject = Object.freeze ? Object.freeze({}) : (
      /* istanbul ignore next */
      {}
    );
    util.isInteger = Number.isInteger || /* istanbul ignore next */
    /* @__PURE__ */ __name(function isInteger(value) {
      return typeof value === "number" && isFinite(value) && Math.floor(value) === value;
    }, "isInteger");
    util.isString = /* @__PURE__ */ __name(function isString(value) {
      return typeof value === "string" || value instanceof String;
    }, "isString");
    util.isObject = /* @__PURE__ */ __name(function isObject(value) {
      return value && typeof value === "object";
    }, "isObject");
    util.isset = /**
     * Checks if a property on a message is considered to be present.
     * @param {Object} obj Plain object or message instance
     * @param {string} prop Property name
     * @returns {boolean} `true` if considered to be present, otherwise `false`
     */
    util.isSet = /* @__PURE__ */ __name(function isSet(obj, prop) {
      var value = obj[prop];
      if (value != null && Object.hasOwnProperty.call(obj, prop))
        return typeof value !== "object" || (Array.isArray(value) ? value.length : Object.keys(value).length) > 0;
      return false;
    }, "isSet");
    util.Buffer = (function() {
      try {
        var Buffer2 = util.global.Buffer;
        return Buffer2.prototype.utf8Write || util.isNode ? Buffer2 : (
          /* istanbul ignore next */
          null
        );
      } catch (e) {
        return null;
      }
    })();
    util.newBuffer = /* @__PURE__ */ __name(function newBuffer(sizeOrArray) {
      var Buffer2 = util.Buffer;
      return typeof sizeOrArray === "number" ? Buffer2 ? Buffer2.allocUnsafe(sizeOrArray) : new Uint8Array(sizeOrArray) : Buffer2 ? Buffer2.from(sizeOrArray) : new Uint8Array(sizeOrArray);
    }, "newBuffer");
    util.rawField = /* @__PURE__ */ __name(function rawField(id, wireType, data) {
      var out = [], tag = id << 3 | wireType;
      tag >>>= 0;
      while (tag > 127) {
        out.push(tag & 127 | 128);
        tag >>>= 7;
      }
      out.push(tag);
      for (var i = 0; i < data.length; ++i)
        out.push(data[i]);
      return util.newBuffer(out);
    }, "rawField");
    util.Array = Uint8Array;
    util.Long = /* istanbul ignore next */
    util.global.dcodeIO && /* istanbul ignore next */
    util.global.dcodeIO.Long || /* istanbul ignore next */
    util.global.Long || (function() {
      try {
        var Long = require_umd();
        return Long && Long.isLong ? Long : null;
      } catch (e) {
        return null;
      }
    })();
    util.key2Re = /^(?:true|false|0|1)$/;
    util.key32Re = /^-?(?:0|[1-9][0-9]*)$/;
    util.key64Re = /^(?:[\x00-\xff]{8}|-?(?:0|[1-9][0-9]*))$/;
    util.longToHash = /* @__PURE__ */ __name(function longToHash(value) {
      return value ? util.LongBits.from(value).toHash() : util.LongBits.zeroHash;
    }, "longToHash");
    util.longFromHash = /* @__PURE__ */ __name(function longFromHash(hash, unsigned) {
      var bits = util.LongBits.fromHash(hash);
      if (util.Long)
        return util.Long.fromBits(bits.lo, bits.hi, unsigned);
      return bits.toNumber(Boolean(unsigned));
    }, "longFromHash");
    util.longFromKey = /* @__PURE__ */ __name(function longFromKey(key, unsigned) {
      return util.key64Re.test(key) && !util.key32Re.test(key) ? util.longFromHash(key, unsigned) : key;
    }, "longFromKey");
    util.boolFromKey = /* @__PURE__ */ __name(function boolFromKey(key) {
      return key === "true" || key === "1";
    }, "boolFromKey");
    function merge(dst) {
      var ifNotSet = typeof arguments[arguments.length - 1] === "boolean", limit = ifNotSet ? arguments.length - 1 : arguments.length;
      ifNotSet = ifNotSet && arguments[arguments.length - 1];
      for (var a = 1; a < limit; ++a) {
        var src = arguments[a];
        if (!src)
          continue;
        for (var keys = Object.keys(src), i = 0; i < keys.length; ++i)
          if (!isUnsafeProperty(keys[i]) && (!ifNotSet || !Object.prototype.hasOwnProperty.call(dst, keys[i]) || dst[keys[i]] === void 0))
            dst[keys[i]] = src[keys[i]];
      }
      return dst;
    }
    __name(merge, "merge");
    util.merge = merge;
    util.nestingLimit = 32;
    util.recursionLimit = 100;
    util.makeProp = /* @__PURE__ */ __name(function makeProp(obj, key, enumerable) {
      if (Object.prototype.hasOwnProperty.call(obj, key))
        return;
      Object.defineProperty(obj, key, {
        enumerable: enumerable === void 0 ? true : enumerable,
        configurable: true,
        writable: true
      });
    }, "makeProp");
    util.lcFirst = /* @__PURE__ */ __name(function lcFirst(str) {
      return str.charAt(0).toLowerCase() + str.substring(1);
    }, "lcFirst");
    function newError(name) {
      function CustomError(message, properties) {
        if (!(this instanceof CustomError))
          return new CustomError(message, properties);
        Object.defineProperty(this, "message", { get: /* @__PURE__ */ __name(function() {
          return message;
        }, "get") });
        if (Error.captureStackTrace)
          Error.captureStackTrace(this, CustomError);
        else
          Object.defineProperty(this, "stack", { value: new Error().stack || "" });
        if (properties)
          merge(this, properties);
      }
      __name(CustomError, "CustomError");
      CustomError.prototype = Object.create(Error.prototype, {
        constructor: {
          value: CustomError,
          writable: true,
          enumerable: false,
          configurable: true
        },
        name: {
          get: /* @__PURE__ */ __name(function get() {
            return name;
          }, "get"),
          set: void 0,
          enumerable: false,
          // configurable: false would accurately preserve the behavior of
          // the original, but I'm guessing that was not intentional.
          // For an actual error subclass, this property would
          // be configurable.
          configurable: true
        },
        toString: {
          value: /* @__PURE__ */ __name(function value() {
            return this.name + ": " + this.message;
          }, "value"),
          writable: true,
          enumerable: false,
          configurable: true
        }
      });
      return CustomError;
    }
    __name(newError, "newError");
    util.newError = newError;
    util.ProtocolError = newError("ProtocolError");
    util.oneOfGetter = /* @__PURE__ */ __name(function getOneOf(fieldNames) {
      var fieldMap = {};
      for (var i = 0; i < fieldNames.length; ++i)
        fieldMap[fieldNames[i]] = 1;
      return function() {
        for (var keys = Object.keys(this), i2 = keys.length - 1; i2 > -1; --i2)
          if (fieldMap[keys[i2]] === 1 && this[keys[i2]] !== void 0 && this[keys[i2]] !== null)
            return keys[i2];
      };
    }, "getOneOf");
    util.oneOfSetter = /* @__PURE__ */ __name(function setOneOf(fieldNames) {
      return function(name) {
        for (var i = 0; i < fieldNames.length; ++i)
          if (fieldNames[i] !== name)
            delete this[fieldNames[i]];
      };
    }, "setOneOf");
    util.toJSONOptions = {
      longs: String,
      enums: String,
      bytes: String,
      json: true
    };
  }
});

// node_modules/protobufjs/src/writer.js
var require_writer = __commonJS({
  "node_modules/protobufjs/src/writer.js"(exports, module) {
    "use strict";
    init_modules_watch_stub();
    module.exports = Writer;
    var util = require_minimal();
    var BufferWriter;
    var LongBits = util.LongBits;
    var base64 = util.base64;
    var utf8 = util.utf8;
    function Writer() {
      this.pos = 0;
      this.buf = this.constructor.alloc(Writer.initialBufferSize);
      this.view = null;
      this.states = null;
    }
    __name(Writer, "Writer");
    Writer.initialBufferSize = 128;
    Object.defineProperty(Writer.prototype, "len", {
      configurable: true,
      enumerable: true,
      get: /* @__PURE__ */ __name(function get_len() {
        return this.pos;
      }, "get_len")
    });
    var create = /* @__PURE__ */ __name(function create2() {
      return util.Buffer ? /* @__PURE__ */ __name(function create_buffer_setup() {
        return (Writer.create = /* @__PURE__ */ __name(function create_buffer() {
          return new BufferWriter();
        }, "create_buffer"))();
      }, "create_buffer_setup") : /* @__PURE__ */ __name(function create_array() {
        return new Writer();
      }, "create_array");
    }, "create");
    Writer.create = create();
    Writer.alloc = /* @__PURE__ */ __name(function alloc(size) {
      return new Uint8Array(size);
    }, "alloc");
    Writer.alloc = util.pool(Writer.alloc, Uint8Array.prototype.subarray);
    function sizeVarint32(value) {
      return value < 128 ? 1 : value < 16384 ? 2 : value < 2097152 ? 3 : value < 268435456 ? 4 : 5;
    }
    __name(sizeVarint32, "sizeVarint32");
    Writer.prototype._reserve = /* @__PURE__ */ __name(function _reserve(n) {
      var need = this.pos + n;
      if (need > this.buf.length) {
        var size = this.buf.length << 1;
        if (size < need)
          size = need;
        var buf = this.constructor.alloc(size);
        buf.set(this.buf.subarray(0, this.pos), 0);
        this.buf = buf;
        this.view = null;
      }
    }, "_reserve");
    function writeStringAscii(val, buf, pos) {
      for (var i = 0; i < val.length; )
        buf[pos++] = val.charCodeAt(i++);
    }
    __name(writeStringAscii, "writeStringAscii");
    function writeVarint32(val, buf, pos) {
      while (val > 127) {
        buf[pos++] = val & 127 | 128;
        val >>>= 7;
      }
      buf[pos] = val;
      return pos + 1;
    }
    __name(writeVarint32, "writeVarint32");
    Writer.prototype.uint32 = /* @__PURE__ */ __name(function write_uint32(value) {
      value = value >>> 0;
      this._reserve(5);
      var pos = this.pos;
      this.pos = writeVarint32(value, this.buf, pos);
      return this;
    }, "write_uint32");
    Writer.prototype.int32 = /* @__PURE__ */ __name(function write_int32(value) {
      if ((value |= 0) < 0) {
        this._reserve(10);
        writeVarint64(LongBits.fromNumber(value), this.buf, this.pos);
        this.pos += 10;
        return this;
      }
      return this.uint32(value);
    }, "write_int32");
    Writer.prototype.sint32 = /* @__PURE__ */ __name(function write_sint32(value) {
      return this.uint32((value << 1 ^ value >> 31) >>> 0);
    }, "write_sint32");
    function writeVarint64(val, buf, pos) {
      var lo = val.lo, hi = val.hi;
      while (hi) {
        buf[pos++] = lo & 127 | 128;
        lo = (lo >>> 7 | hi << 25) >>> 0;
        hi >>>= 7;
      }
      while (lo > 127) {
        buf[pos++] = lo & 127 | 128;
        lo = lo >>> 7;
      }
      buf[pos] = lo;
      return pos + 1;
    }
    __name(writeVarint64, "writeVarint64");
    Writer.prototype.uint64 = /* @__PURE__ */ __name(function write_uint64(value) {
      var bits = LongBits.from(value);
      this._reserve(10);
      var pos = this.pos;
      this.pos = writeVarint64(bits, this.buf, pos);
      return this;
    }, "write_uint64");
    Writer.prototype.int64 = Writer.prototype.uint64;
    Writer.prototype.sint64 = /* @__PURE__ */ __name(function write_sint64(value) {
      var bits = LongBits.from(value).zzEncode();
      this._reserve(10);
      var pos = this.pos;
      this.pos = writeVarint64(bits, this.buf, pos);
      return this;
    }, "write_sint64");
    Writer.prototype.bool = /* @__PURE__ */ __name(function write_bool(value) {
      this._reserve(1);
      this.buf[this.pos++] = value ? 1 : 0;
      return this;
    }, "write_bool");
    function writeFixed32(val, buf, pos) {
      buf[pos] = val & 255;
      buf[pos + 1] = val >>> 8 & 255;
      buf[pos + 2] = val >>> 16 & 255;
      buf[pos + 3] = val >>> 24;
    }
    __name(writeFixed32, "writeFixed32");
    Writer.prototype.fixed32 = /* @__PURE__ */ __name(function write_fixed32(value) {
      this._reserve(4);
      writeFixed32(value >>> 0, this.buf, this.pos);
      this.pos += 4;
      return this;
    }, "write_fixed32");
    Writer.prototype.sfixed32 = Writer.prototype.fixed32;
    Writer.prototype.fixed64 = /* @__PURE__ */ __name(function write_fixed64(value) {
      var bits = LongBits.from(value);
      this._reserve(8);
      writeFixed32(bits.lo, this.buf, this.pos);
      writeFixed32(bits.hi, this.buf, this.pos + 4);
      this.pos += 8;
      return this;
    }, "write_fixed64");
    Writer.prototype.sfixed64 = Writer.prototype.fixed64;
    Writer.prototype.float = /* @__PURE__ */ __name(function write_float(value) {
      this._reserve(4);
      util.float.writeFloatLE(value, this.buf, this.pos);
      this.pos += 4;
      return this;
    }, "write_float");
    Writer.prototype.double = /* @__PURE__ */ __name(function write_double(value) {
      this._reserve(8);
      util.float.writeDoubleLE(value, this.buf, this.pos);
      this.pos += 8;
      return this;
    }, "write_double");
    Writer.prototype.bytes = /* @__PURE__ */ __name(function write_bytes(value) {
      var len = value.length >>> 0;
      if (!len) {
        this._reserve(1);
        this.buf[this.pos++] = 0;
        return this;
      }
      if (util.isString(value)) {
        var buf = Writer.alloc(len = base64.length(value));
        base64.decode(value, buf, 0);
        value = buf;
      }
      this.uint32(len);
      this._reserve(len);
      this.buf.set(value, this.pos);
      this.pos += len;
      return this;
    }, "write_bytes");
    Writer.prototype.raw = /* @__PURE__ */ __name(function write_raw(value) {
      var len = value.length >>> 0;
      if (!len)
        return this;
      this._reserve(len);
      this.buf.set(value, this.pos);
      this.pos += len;
      return this;
    }, "write_raw");
    Writer.prototype._delim = /* @__PURE__ */ __name(function _delim(pos, len) {
      var n = sizeVarint32(len);
      if (n > 1)
        this.buf.copyWithin(pos + n, pos + 1, pos + 1 + len);
      writeVarint32(len, this.buf, pos);
      this.pos = pos + n + len;
      return this;
    }, "_delim");
    Writer.prototype.string = /* @__PURE__ */ __name(function write_string(value) {
      var n = value.length;
      if (!n) {
        this._reserve(1);
        this.buf[this.pos++] = 0;
        return this;
      }
      if (n < 128) {
        this._reserve(n * 3 + 5);
        var lenPos = this.pos;
        return this._delim(lenPos, utf8.write(value, this.buf, lenPos + 1));
      }
      var len = utf8.length(value);
      this.uint32(len);
      this._reserve(len);
      if (len === value.length)
        writeStringAscii(value, this.buf, this.pos);
      else
        utf8.write(value, this.buf, this.pos);
      this.pos += len;
      return this;
    }, "write_string");
    Writer.prototype.uint32s = /* @__PURE__ */ __name(function write_uint32s(value) {
      var n = value.length;
      this._reserve(n * 5 + 5);
      var buf = this.buf, lenPos = this.pos, p = lenPos + 1;
      for (var i = 0; i < n; ++i)
        p = writeVarint32(value[i] >>> 0, buf, p);
      return this._delim(lenPos, p - lenPos - 1);
    }, "write_uint32s");
    Writer.prototype.int32s = /* @__PURE__ */ __name(function write_int32s(value) {
      var n = value.length;
      this._reserve(n * 10 + 5);
      var buf = this.buf, lenPos = this.pos, pos = lenPos + 1, val;
      for (var i = 0; i < n; ++i) {
        if ((val = value[i] | 0) < 0) {
          pos = writeVarint64(LongBits.fromNumber(val), buf, pos);
        } else {
          pos = writeVarint32(val, buf, pos);
        }
      }
      return this._delim(lenPos, pos - lenPos - 1);
    }, "write_int32s");
    Writer.prototype.sint32s = /* @__PURE__ */ __name(function write_sint32s(value) {
      var n = value.length;
      this._reserve(n * 5 + 5);
      var buf = this.buf, lenPos = this.pos, pos = lenPos + 1;
      for (var i = 0; i < n; ++i)
        pos = writeVarint32((value[i] << 1 ^ value[i] >> 31) >>> 0, buf, pos);
      return this._delim(lenPos, pos - lenPos - 1);
    }, "write_sint32s");
    Writer.prototype.uint64s = /* @__PURE__ */ __name(function write_uint64s(value) {
      var n = value.length;
      this._reserve(n * 10 + 5);
      var buf = this.buf, lenPos = this.pos, pos = lenPos + 1;
      for (var i = 0; i < n; ++i) {
        pos = writeVarint64(LongBits.from(value[i]), buf, pos);
      }
      return this._delim(lenPos, pos - lenPos - 1);
    }, "write_uint64s");
    Writer.prototype.int64s = Writer.prototype.uint64s;
    Writer.prototype.sint64s = /* @__PURE__ */ __name(function write_sint64s(value) {
      var n = value.length;
      this._reserve(n * 10 + 5);
      var buf = this.buf, lenPos = this.pos, pos = lenPos + 1;
      for (var i = 0; i < n; ++i) {
        pos = writeVarint64(LongBits.from(value[i]).zzEncode(), buf, pos);
      }
      return this._delim(lenPos, pos - lenPos - 1);
    }, "write_sint64s");
    Writer.prototype.bools = /* @__PURE__ */ __name(function write_bools(value) {
      var n = value.length;
      this.uint32(n);
      this._reserve(n);
      var buf = this.buf, p = this.pos;
      for (var i = 0; i < n; ++i)
        buf[p++] = value[i] ? 1 : 0;
      this.pos += n;
      return this;
    }, "write_bools");
    var VIEW_THRESHOLD_FLOAT = 16;
    var VIEW_THRESHOLD_INT = 128;
    function getLazyView(writer, count, threshold) {
      var view = writer.view;
      if (view || count < threshold)
        return view;
      var buf = writer.buf;
      return writer.view = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
    }
    __name(getLazyView, "getLazyView");
    Writer.prototype.fixed32s = /* @__PURE__ */ __name(function write_fixed32s(value) {
      var n = value.length, bytes = n * 4;
      this.uint32(bytes);
      this._reserve(bytes);
      var p = this.pos, i, dv = getLazyView(this, n, VIEW_THRESHOLD_INT);
      if (dv)
        for (i = 0; i < n; ++i) {
          dv.setUint32(p, value[i] >>> 0, true);
          p += 4;
        }
      else {
        var buf = this.buf;
        for (i = 0; i < n; ++i) {
          writeFixed32(value[i] >>> 0, buf, p);
          p += 4;
        }
      }
      this.pos += bytes;
      return this;
    }, "write_fixed32s");
    Writer.prototype.sfixed32s = Writer.prototype.fixed32s;
    Writer.prototype.fixed64s = /* @__PURE__ */ __name(function write_fixed64s(value) {
      var n = value.length, bytes = n * 8;
      this.uint32(bytes);
      this._reserve(bytes);
      var p = this.pos, i, bits, dv = getLazyView(this, n, VIEW_THRESHOLD_INT);
      if (dv)
        for (i = 0; i < n; ++i) {
          bits = LongBits.from(value[i]);
          dv.setUint32(p, bits.lo, true);
          dv.setUint32(p + 4, bits.hi, true);
          p += 8;
        }
      else {
        var buf = this.buf;
        for (i = 0; i < n; ++i) {
          bits = LongBits.from(value[i]);
          writeFixed32(bits.lo, buf, p);
          writeFixed32(bits.hi, buf, p + 4);
          p += 8;
        }
      }
      this.pos += bytes;
      return this;
    }, "write_fixed64s");
    Writer.prototype.sfixed64s = Writer.prototype.fixed64s;
    Writer.prototype.floats = /* @__PURE__ */ __name(function write_floats(value) {
      var n = value.length, bytes = n * 4;
      this.uint32(bytes);
      this._reserve(bytes);
      var p = this.pos, i, dv = getLazyView(this, n, VIEW_THRESHOLD_FLOAT);
      if (dv)
        for (i = 0; i < n; ++i) {
          dv.setFloat32(p, value[i], true);
          p += 4;
        }
      else {
        var buf = this.buf;
        for (i = 0; i < n; ++i) {
          util.float.writeFloatLE(value[i], buf, p);
          p += 4;
        }
      }
      this.pos += bytes;
      return this;
    }, "write_floats");
    Writer.prototype.doubles = /* @__PURE__ */ __name(function write_doubles(value) {
      var n = value.length, bytes = n * 8;
      this.uint32(bytes);
      this._reserve(bytes);
      var p = this.pos, i, dv = getLazyView(this, n, VIEW_THRESHOLD_FLOAT);
      if (dv)
        for (i = 0; i < n; ++i) {
          dv.setFloat64(p, value[i], true);
          p += 8;
        }
      else {
        var buf = this.buf;
        for (i = 0; i < n; ++i) {
          util.float.writeDoubleLE(value[i], buf, p);
          p += 8;
        }
      }
      this.pos += bytes;
      return this;
    }, "write_doubles");
    Writer.prototype.fork = /* @__PURE__ */ __name(function fork() {
      this._reserve(1);
      (this.states || (this.states = [])).push(this.pos);
      this.pos += 1;
      return this;
    }, "fork");
    Writer.prototype.reset = /* @__PURE__ */ __name(function reset() {
      var states = this.states;
      if (states && states.length) {
        this.pos = states.pop();
      } else {
        this.pos = 0;
      }
      return this;
    }, "reset");
    Writer.prototype.ldelim = /* @__PURE__ */ __name(function ldelim() {
      var states = this.states, len, vlen;
      if (states && states.length) {
        var lenPos = states.pop();
        len = this.pos - lenPos - 1;
        vlen = sizeVarint32(len);
        if (vlen > 1) {
          this._reserve(vlen - 1);
          this.buf.copyWithin(lenPos + vlen, lenPos + 1, lenPos + 1 + len);
          this.pos += vlen - 1;
          writeVarint32(len, this.buf, lenPos);
        } else {
          this.buf[lenPos] = len;
        }
      } else {
        len = this.pos;
        vlen = sizeVarint32(len);
        this._reserve(vlen);
        this.buf.copyWithin(vlen, 0, len);
        writeVarint32(len, this.buf, 0);
        this.pos += vlen;
      }
      return this;
    }, "ldelim");
    Writer.prototype.finish = /* @__PURE__ */ __name(function finish(shared) {
      if (shared)
        return this.buf.subarray(0, this.pos);
      var buf = this.constructor.alloc(this.pos);
      buf.set(this.buf.subarray(0, this.pos), 0);
      return buf;
    }, "finish");
    Writer.prototype.finishInto = /* @__PURE__ */ __name(function finishInto(buf, offset) {
      if (offset === void 0)
        offset = 0;
      buf.set(this.buf.subarray(0, this.pos), offset);
      return buf;
    }, "finishInto");
    Writer._configure = function(BufferWriter_) {
      BufferWriter = BufferWriter_;
      Writer.create = create();
      BufferWriter._configure();
    };
  }
});

// node_modules/protobufjs/src/writer_buffer.js
var require_writer_buffer = __commonJS({
  "node_modules/protobufjs/src/writer_buffer.js"(exports, module) {
    "use strict";
    init_modules_watch_stub();
    module.exports = BufferWriter;
    var Writer = require_writer();
    BufferWriter.prototype = Object.create(Writer.prototype, {
      constructor: {
        value: BufferWriter,
        writable: true,
        enumerable: false,
        configurable: true
      }
    });
    var util = require_minimal();
    function BufferWriter() {
      Writer.call(this);
    }
    __name(BufferWriter, "BufferWriter");
    var writeStringBuffer;
    BufferWriter._configure = function() {
      BufferWriter.alloc = util.Buffer && util.Buffer.allocUnsafe;
      writeStringBuffer = util.Buffer && util.Buffer.prototype.utf8Write ? /* @__PURE__ */ __name(function writeStringBuffer_utf8Write(val, buf, pos) {
        return buf.utf8Write(val, pos);
      }, "writeStringBuffer_utf8Write") : /* @__PURE__ */ __name(function writeStringBuffer_write(val, buf, pos) {
        return buf.write(val, pos);
      }, "writeStringBuffer_write");
    };
    BufferWriter.prototype.bytes = /* @__PURE__ */ __name(function write_bytes_buffer(value) {
      if (util.isString(value))
        value = util.Buffer.from(value, "base64");
      var len = value.length >>> 0;
      this.uint32(len);
      if (len) {
        this._reserve(len);
        this.buf.set(value, this.pos);
        this.pos += len;
      }
      return this;
    }, "write_bytes_buffer");
    BufferWriter.prototype.string = /* @__PURE__ */ __name(function write_string_buffer(value) {
      var n = value.length;
      if (!n) {
        this._reserve(1);
        this.buf[this.pos++] = 0;
        return this;
      }
      if (n < 128) {
        this._reserve(n * 3 + 5);
        var pos = this.pos, buf = this.buf;
        return this._delim(
          pos,
          n < 40 ? util.utf8.write(value, buf, pos + 1) : writeStringBuffer(value, buf, pos + 1)
        );
      }
      var len = util.Buffer.byteLength(value);
      this.uint32(len);
      this._reserve(len);
      writeStringBuffer(value, this.buf, this.pos);
      this.pos += len;
      return this;
    }, "write_string_buffer");
    BufferWriter._configure();
  }
});

// node_modules/protobufjs/src/reader.js
var require_reader = __commonJS({
  "node_modules/protobufjs/src/reader.js"(exports, module) {
    "use strict";
    init_modules_watch_stub();
    module.exports = Reader;
    var util = require_minimal();
    var BufferReader;
    var LongBits = util.LongBits;
    var utf8 = util.utf8;
    function indexOutOfRange(reader, writeLength) {
      return RangeError("index out of range: " + reader.pos + " + " + (writeLength || 1) + " > " + reader.len);
    }
    __name(indexOutOfRange, "indexOutOfRange");
    function Reader(buffer) {
      this.buf = buffer;
      this.pos = 0;
      this.len = buffer.length;
      this.view = null;
      this.discardUnknown = Reader.discardUnknown;
    }
    __name(Reader, "Reader");
    function create_array(buffer) {
      if (Array.isArray(buffer))
        buffer = new Uint8Array(buffer);
      if (buffer instanceof Uint8Array)
        return new Reader(buffer);
      throw Error("illegal buffer");
    }
    __name(create_array, "create_array");
    var create = /* @__PURE__ */ __name(function create2() {
      return util.Buffer ? /* @__PURE__ */ __name(function create_buffer_setup(buffer) {
        return (Reader.create = /* @__PURE__ */ __name(function create_buffer(buffer2) {
          return util.Buffer.isBuffer(buffer2) ? new BufferReader(buffer2) : create_array(buffer2);
        }, "create_buffer"))(buffer);
      }, "create_buffer_setup") : create_array;
    }, "create");
    Reader.create = create();
    Reader.prototype.raw = /* @__PURE__ */ __name(function read_raw(start, end) {
      return this.buf.subarray(start, end);
    }, "read_raw");
    function readVarint32NearEnd(reader) {
      var value = 0;
      for (var i = 0; i < 4; ++i) {
        if (reader.pos >= reader.len)
          throw indexOutOfRange(reader);
        var b = reader.buf[reader.pos++];
        value = (value | (b & 127) << i * 7) >>> 0;
        if (b < 128)
          return value;
      }
      throw indexOutOfRange(reader);
    }
    __name(readVarint32NearEnd, "readVarint32NearEnd");
    Reader.prototype.uint32 = /* @__PURE__ */ __name(function read_uint32() {
      if (this.len - this.pos < 5) {
        if (this.pos >= this.len)
          throw indexOutOfRange(this);
        if (this.buf[this.pos] >= 128)
          return readVarint32NearEnd(this);
      }
      var buf = this.buf, pos = this.pos, value = (buf[pos] & 127) >>> 0;
      if (buf[pos++] < 128) {
        this.pos = pos;
        return value;
      }
      value = (value | (buf[pos] & 127) << 7) >>> 0;
      if (buf[pos++] < 128) {
        this.pos = pos;
        return value;
      }
      value = (value | (buf[pos] & 127) << 14) >>> 0;
      if (buf[pos++] < 128) {
        this.pos = pos;
        return value;
      }
      value = (value | (buf[pos] & 127) << 21) >>> 0;
      if (buf[pos++] < 128) {
        this.pos = pos;
        return value;
      }
      value = (value | (buf[pos] & 15) << 28) >>> 0;
      if (buf[pos++] < 128) {
        this.pos = pos;
        return value;
      }
      for (var i = 0; i < 5; ++i) {
        if (pos >= this.len) {
          this.pos = pos;
          throw indexOutOfRange(this);
        }
        if (buf[pos++] < 128) {
          this.pos = pos;
          return value;
        }
      }
      this.pos = pos;
      throw Error("invalid varint encoding");
    }, "read_uint32");
    Reader.prototype.tag = /* @__PURE__ */ __name(function read_tag() {
      if (this.len - this.pos < 5) {
        if (this.pos >= this.len)
          throw indexOutOfRange(this);
        if (this.buf[this.pos] >= 128)
          return readVarint32NearEnd(this);
      }
      var buf = this.buf, pos = this.pos, value = (buf[pos] & 127) >>> 0;
      if (buf[pos++] < 128) {
        this.pos = pos;
        return value;
      }
      value = (value | (buf[pos] & 127) << 7) >>> 0;
      if (buf[pos++] < 128) {
        this.pos = pos;
        return value;
      }
      value = (value | (buf[pos] & 127) << 14) >>> 0;
      if (buf[pos++] < 128) {
        this.pos = pos;
        return value;
      }
      value = (value | (buf[pos] & 127) << 21) >>> 0;
      if (buf[pos++] < 128) {
        this.pos = pos;
        return value;
      }
      value = (value | (buf[pos] & 15) << 28) >>> 0;
      if (buf[pos] < 128 && (buf[pos] & 112) === 0) {
        this.pos = pos + 1;
        return value;
      }
      this.pos = pos + 1;
      throw Error("invalid tag encoding");
    }, "read_tag");
    Reader.prototype.int32 = /* @__PURE__ */ __name(function read_int32() {
      return this.uint32() | 0;
    }, "read_int32");
    Reader.prototype.sint32 = /* @__PURE__ */ __name(function read_sint32() {
      var value = this.uint32();
      return value >>> 1 ^ -(value & 1) | 0;
    }, "read_sint32");
    function readLongVarint() {
      var bits = new LongBits(0, 0);
      var i = 0;
      if (this.len - this.pos > 4) {
        for (; i < 4; ++i) {
          bits.lo = (bits.lo | (this.buf[this.pos] & 127) << i * 7) >>> 0;
          if (this.buf[this.pos++] < 128)
            return bits;
        }
        bits.lo = (bits.lo | (this.buf[this.pos] & 127) << 28) >>> 0;
        bits.hi = (bits.hi | (this.buf[this.pos] & 127) >> 4) >>> 0;
        if (this.buf[this.pos++] < 128)
          return bits;
        i = 0;
      } else {
        for (; i < 4; ++i) {
          if (this.pos >= this.len)
            throw indexOutOfRange(this);
          bits.lo = (bits.lo | (this.buf[this.pos] & 127) << i * 7) >>> 0;
          if (this.buf[this.pos++] < 128)
            return bits;
        }
        throw indexOutOfRange(this);
      }
      if (this.len - this.pos > 4) {
        for (; i < 5; ++i) {
          bits.hi = (bits.hi | (this.buf[this.pos] & 127) << i * 7 + 3) >>> 0;
          if (this.buf[this.pos++] < 128)
            return bits;
        }
      } else {
        for (; i < 5; ++i) {
          if (this.pos >= this.len)
            throw indexOutOfRange(this);
          bits.hi = (bits.hi | (this.buf[this.pos] & 127) << i * 7 + 3) >>> 0;
          if (this.buf[this.pos++] < 128)
            return bits;
        }
      }
      throw Error("invalid varint encoding");
    }
    __name(readLongVarint, "readLongVarint");
    Reader.prototype.bool = /* @__PURE__ */ __name(function read_bool() {
      var value = false, b;
      for (var i = 0; i < 10; ++i) {
        if (this.pos >= this.len)
          throw indexOutOfRange(this);
        b = this.buf[this.pos++];
        if (b & 127)
          value = true;
        if (b < 128)
          return value;
      }
      throw Error("invalid varint encoding");
    }, "read_bool");
    function readFixed32_end(buf, end) {
      return (buf[end - 4] | buf[end - 3] << 8 | buf[end - 2] << 16 | buf[end - 1] << 24) >>> 0;
    }
    __name(readFixed32_end, "readFixed32_end");
    Reader.prototype.fixed32 = /* @__PURE__ */ __name(function read_fixed32() {
      if (this.pos + 4 > this.len)
        throw indexOutOfRange(this, 4);
      return readFixed32_end(this.buf, this.pos += 4);
    }, "read_fixed32");
    Reader.prototype.sfixed32 = /* @__PURE__ */ __name(function read_sfixed32() {
      if (this.pos + 4 > this.len)
        throw indexOutOfRange(this, 4);
      return readFixed32_end(this.buf, this.pos += 4) | 0;
    }, "read_sfixed32");
    function readFixed64() {
      if (this.pos + 8 > this.len)
        throw indexOutOfRange(this, 8);
      return new LongBits(readFixed32_end(this.buf, this.pos += 4), readFixed32_end(this.buf, this.pos += 4));
    }
    __name(readFixed64, "readFixed64");
    Reader.prototype.float = /* @__PURE__ */ __name(function read_float() {
      if (this.pos + 4 > this.len)
        throw indexOutOfRange(this, 4);
      var value = util.float.readFloatLE(this.buf, this.pos);
      this.pos += 4;
      return value;
    }, "read_float");
    Reader.prototype.double = /* @__PURE__ */ __name(function read_double() {
      if (this.pos + 8 > this.len)
        throw indexOutOfRange(this, 4);
      var value = util.float.readDoubleLE(this.buf, this.pos);
      this.pos += 8;
      return value;
    }, "read_double");
    Reader.prototype.uint32s = /* @__PURE__ */ __name(function read_uint32s(array) {
      if (array === void 0) array = [];
      var end = this.uint32() + this.pos, len = this.len, buf = this.buf, pos = this.pos, value;
      if (end > len) throw indexOutOfRange(this, end - this.pos);
      this.len = end;
      while (pos < end) {
        value = buf[pos++];
        if (value < 128)
          array.push(value);
        else {
          this.pos = pos - 1;
          array.push(this.uint32());
          pos = this.pos;
        }
      }
      this.pos = pos;
      if (pos !== end) throw RangeError("index out of range");
      this.len = len;
      return array;
    }, "read_uint32s");
    Reader.prototype.int32s = /* @__PURE__ */ __name(function read_int32s(array) {
      if (array === void 0) array = [];
      var end = this.uint32() + this.pos, len = this.len, buf = this.buf, pos = this.pos, value;
      if (end > len) throw indexOutOfRange(this, end - this.pos);
      this.len = end;
      while (pos < end) {
        value = buf[pos++];
        if (value < 128)
          array.push(value);
        else {
          this.pos = pos - 1;
          array.push(this.int32());
          pos = this.pos;
        }
      }
      this.pos = pos;
      if (pos !== end) throw RangeError("index out of range");
      this.len = len;
      return array;
    }, "read_int32s");
    Reader.prototype.sint32s = /* @__PURE__ */ __name(function read_sint32s(array) {
      if (array === void 0) array = [];
      var end = this.uint32() + this.pos, len = this.len;
      if (end > len) throw indexOutOfRange(this, end - this.pos);
      this.len = end;
      while (this.pos < end)
        array.push(this.sint32());
      if (this.pos !== end) throw RangeError("index out of range");
      this.len = len;
      return array;
    }, "read_sint32s");
    Reader.prototype.bools = /* @__PURE__ */ __name(function read_bools(array) {
      if (array === void 0) array = [];
      var end = this.uint32() + this.pos, len = this.len, buf = this.buf, pos = this.pos, value;
      if (end > len) throw indexOutOfRange(this, end - this.pos);
      this.len = end;
      while (pos < end) {
        value = buf[pos++];
        if (value < 128)
          array.push(value !== 0);
        else {
          this.pos = pos - 1;
          array.push(this.bool());
          pos = this.pos;
        }
      }
      this.pos = pos;
      if (pos !== end) throw RangeError("index out of range");
      this.len = len;
      return array;
    }, "read_bools");
    var VIEW_THRESHOLD_FLOAT = 8;
    var VIEW_THRESHOLD_INT = 128;
    function getLazyView(reader, count, threshold) {
      var view = reader.view;
      if (view || count < threshold)
        return view;
      var buf = reader.buf;
      return reader.view = new DataView(buf.buffer, buf.byteOffset, buf.byteLength);
    }
    __name(getLazyView, "getLazyView");
    Reader.prototype.fixed32s = /* @__PURE__ */ __name(function read_fixed32s(array) {
      if (array === void 0) array = [];
      var len = this.uint32(), end = this.pos + len;
      if (end > this.len) throw indexOutOfRange(this, len);
      var count = len >>> 2, i = array.length, pos = this.pos;
      array.length = i + count;
      var dv = getLazyView(this, count, VIEW_THRESHOLD_INT);
      if (dv)
        for (var k = 0; k < count; ++k, pos += 4) array[i++] = dv.getUint32(pos, true);
      else {
        var buf = this.buf;
        for (var j = 0; j < count; ++j, pos += 4) array[i++] = readFixed32_end(buf, pos + 4);
      }
      this.pos = pos;
      if (pos !== end) throw indexOutOfRange(this, 4);
      return array;
    }, "read_fixed32s");
    Reader.prototype.sfixed32s = /* @__PURE__ */ __name(function read_sfixed32s(array) {
      if (array === void 0) array = [];
      var len = this.uint32(), end = this.pos + len;
      if (end > this.len) throw indexOutOfRange(this, len);
      var count = len >>> 2, i = array.length, pos = this.pos;
      array.length = i + count;
      var dv = getLazyView(this, count, VIEW_THRESHOLD_INT);
      if (dv)
        for (var k = 0; k < count; ++k, pos += 4) array[i++] = dv.getInt32(pos, true);
      else {
        var buf = this.buf;
        for (var j = 0; j < count; ++j, pos += 4) array[i++] = readFixed32_end(buf, pos + 4) | 0;
      }
      this.pos = pos;
      if (pos !== end) throw indexOutOfRange(this, 4);
      return array;
    }, "read_sfixed32s");
    Reader.prototype.floats = /* @__PURE__ */ __name(function read_floats(array) {
      if (array === void 0) array = [];
      var len = this.uint32(), end = this.pos + len;
      if (end > this.len) throw indexOutOfRange(this, len);
      var count = len >>> 2, i = array.length, pos = this.pos;
      array.length = i + count;
      var dv = getLazyView(this, count, VIEW_THRESHOLD_FLOAT);
      if (dv)
        for (var k = 0; k < count; ++k, pos += 4) array[i++] = dv.getFloat32(pos, true);
      else {
        var buf = this.buf;
        for (var j = 0; j < count; ++j, pos += 4) array[i++] = util.float.readFloatLE(buf, pos);
      }
      this.pos = pos;
      if (pos !== end) throw indexOutOfRange(this, 4);
      return array;
    }, "read_floats");
    Reader.prototype.doubles = /* @__PURE__ */ __name(function read_doubles(array) {
      if (array === void 0) array = [];
      var len = this.uint32(), end = this.pos + len;
      if (end > this.len) throw indexOutOfRange(this, len);
      var count = len >>> 3, i = array.length, pos = this.pos;
      array.length = i + count;
      var dv = getLazyView(this, count, VIEW_THRESHOLD_FLOAT);
      if (dv)
        for (var k = 0; k < count; ++k, pos += 8) array[i++] = dv.getFloat64(pos, true);
      else {
        var buf = this.buf;
        for (var j = 0; j < count; ++j, pos += 8) array[i++] = util.float.readDoubleLE(buf, pos);
      }
      this.pos = pos;
      if (pos !== end) throw indexOutOfRange(this, 8);
      return array;
    }, "read_doubles");
    Reader.prototype.uint64s = /* @__PURE__ */ __name(function read_uint64s(array) {
      if (array === void 0) array = [];
      var end = this.uint32() + this.pos, len = this.len;
      if (end > len) throw indexOutOfRange(this, end - this.pos);
      this.len = end;
      while (this.pos < end)
        array.push(this.uint64());
      if (this.pos !== end) throw RangeError("index out of range");
      this.len = len;
      return array;
    }, "read_uint64s");
    Reader.prototype.int64s = /* @__PURE__ */ __name(function read_int64s(array) {
      if (array === void 0) array = [];
      var end = this.uint32() + this.pos, len = this.len;
      if (end > len) throw indexOutOfRange(this, end - this.pos);
      this.len = end;
      while (this.pos < end)
        array.push(this.int64());
      if (this.pos !== end) throw RangeError("index out of range");
      this.len = len;
      return array;
    }, "read_int64s");
    Reader.prototype.sint64s = /* @__PURE__ */ __name(function read_sint64s(array) {
      if (array === void 0) array = [];
      var end = this.uint32() + this.pos, len = this.len;
      if (end > len) throw indexOutOfRange(this, end - this.pos);
      this.len = end;
      while (this.pos < end)
        array.push(this.sint64());
      if (this.pos !== end) throw RangeError("index out of range");
      this.len = len;
      return array;
    }, "read_sint64s");
    Reader.prototype.fixed64s = /* @__PURE__ */ __name(function read_fixed64s(array) {
      if (array === void 0) array = [];
      var len = this.uint32(), end = this.pos + len, i = array.length;
      if (end > this.len) throw indexOutOfRange(this, len);
      var count = len >>> 3;
      array.length = i + count;
      for (var j = 0; j < count; ++j)
        array[i++] = this.fixed64();
      if (this.pos !== end) throw indexOutOfRange(this, 8);
      return array;
    }, "read_fixed64s");
    Reader.prototype.sfixed64s = /* @__PURE__ */ __name(function read_sfixed64s(array) {
      if (array === void 0) array = [];
      var len = this.uint32(), end = this.pos + len, i = array.length;
      if (end > this.len) throw indexOutOfRange(this, len);
      var count = len >>> 3;
      array.length = i + count;
      for (var j = 0; j < count; ++j)
        array[i++] = this.sfixed64();
      if (this.pos !== end) throw indexOutOfRange(this, 8);
      return array;
    }, "read_sfixed64s");
    Reader.prototype.bytes = /* @__PURE__ */ __name(function read_bytes() {
      var length = this.uint32(), start = this.pos, end = this.pos + length;
      if (end > this.len)
        throw indexOutOfRange(this, length);
      this.pos = end;
      return this.raw(start, end);
    }, "read_bytes");
    Reader.prototype.string = /* @__PURE__ */ __name(function read_string() {
      var length = this.uint32(), start = this.pos, end = this.pos + length;
      if (end > this.len)
        throw indexOutOfRange(this, length);
      this.pos = end;
      return utf8.read(this.buf, start, end);
    }, "read_string");
    Reader.prototype.stringVerify = /* @__PURE__ */ __name(function read_string_verify() {
      var length = this.uint32(), start = this.pos, end = this.pos + length;
      if (end > this.len)
        throw indexOutOfRange(this, length);
      this.pos = end;
      return utf8.readStrict(this.buf, start, end);
    }, "read_string_verify");
    Reader.prototype.skip = /* @__PURE__ */ __name(function skip(length) {
      if (typeof length === "number") {
        if (this.pos + length > this.len)
          throw indexOutOfRange(this, length);
        this.pos += length;
      } else {
        do {
          if (this.pos >= this.len)
            throw indexOutOfRange(this);
        } while (this.buf[this.pos++] & 128);
      }
      return this;
    }, "skip");
    Reader.recursionLimit = util.recursionLimit;
    Reader.discardUnknown = true;
    Reader.prototype.skipType = function(wireType, depth, fieldNumber) {
      if (depth === void 0) depth = 0;
      if (depth > Reader.recursionLimit)
        throw Error("max depth exceeded");
      if (fieldNumber === 0)
        throw Error("illegal tag: field number 0");
      switch (wireType) {
        case 0:
          this.skip();
          break;
        case 1:
          this.skip(8);
          break;
        case 2:
          this.skip(this.uint32());
          break;
        case 3:
          while (true) {
            var tag = this.tag();
            var nestedField = tag >>> 3;
            wireType = tag & 7;
            if (!nestedField)
              throw Error("illegal tag: field number 0");
            if (wireType === 4) {
              if (fieldNumber !== void 0 && nestedField !== fieldNumber)
                throw Error("invalid end group tag");
              break;
            }
            this.skipType(wireType, depth + 1, nestedField);
          }
          break;
        case 5:
          this.skip(4);
          break;
        /* istanbul ignore next */
        default:
          throw Error("invalid wire type " + wireType + " at offset " + this.pos);
      }
      return this;
    };
    Reader._configure = function(BufferReader_) {
      BufferReader = BufferReader_;
      Reader.create = create();
      BufferReader._configure();
      var fn = util.Long ? "toLong" : (
        /* istanbul ignore next */
        "toNumber"
      );
      util.merge(Reader.prototype, {
        int64: /* @__PURE__ */ __name(function read_int64() {
          return readLongVarint.call(this)[fn](false);
        }, "read_int64"),
        uint64: /* @__PURE__ */ __name(function read_uint64() {
          return readLongVarint.call(this)[fn](true);
        }, "read_uint64"),
        sint64: /* @__PURE__ */ __name(function read_sint64() {
          return readLongVarint.call(this).zzDecode()[fn](false);
        }, "read_sint64"),
        fixed64: /* @__PURE__ */ __name(function read_fixed64() {
          return readFixed64.call(this)[fn](true);
        }, "read_fixed64"),
        sfixed64: /* @__PURE__ */ __name(function read_sfixed64() {
          return readFixed64.call(this)[fn](false);
        }, "read_sfixed64")
      });
    };
  }
});

// node_modules/protobufjs/src/reader_buffer.js
var require_reader_buffer = __commonJS({
  "node_modules/protobufjs/src/reader_buffer.js"(exports, module) {
    "use strict";
    init_modules_watch_stub();
    module.exports = BufferReader;
    var Reader = require_reader();
    BufferReader.prototype = Object.create(Reader.prototype, {
      constructor: {
        value: BufferReader,
        writable: true,
        enumerable: false,
        configurable: true
      }
    });
    var util = require_minimal();
    function BufferReader(buffer) {
      Reader.call(this, buffer);
    }
    __name(BufferReader, "BufferReader");
    BufferReader._configure = function() {
      if (util.Buffer)
        BufferReader.prototype._slice = util.Buffer.prototype.slice;
    };
    BufferReader.prototype.raw = /* @__PURE__ */ __name(function read_raw_buffer(start, end) {
      return this._slice.call(this.buf, start, end);
    }, "read_raw_buffer");
    BufferReader.prototype.string = /* @__PURE__ */ __name(function read_string_buffer() {
      var len = this.uint32(), start = this.pos, end = this.pos + len;
      if (end > this.len)
        throw RangeError("index out of range: " + this.pos + " + " + len + " > " + this.len);
      this.pos = end;
      return this.buf.utf8Slice ? this.buf.utf8Slice(start, end) : this.buf.toString("utf-8", start, end);
    }, "read_string_buffer");
    BufferReader._configure();
  }
});

// node_modules/protobufjs/src/rpc/service.js
var require_service = __commonJS({
  "node_modules/protobufjs/src/rpc/service.js"(exports, module) {
    "use strict";
    init_modules_watch_stub();
    module.exports = Service;
    var util = require_minimal();
    Service.prototype = Object.create(util.EventEmitter.prototype, {
      constructor: {
        value: Service,
        writable: true,
        enumerable: false,
        configurable: true
      }
    });
    function Service(rpcImpl, requestDelimited, responseDelimited) {
      if (typeof rpcImpl !== "function")
        throw TypeError("rpcImpl must be a function");
      util.EventEmitter.call(this);
      this.rpcImpl = rpcImpl;
      this.requestDelimited = Boolean(requestDelimited);
      this.responseDelimited = Boolean(responseDelimited);
    }
    __name(Service, "Service");
    Service.prototype.rpcCall = /* @__PURE__ */ __name(function rpcCall(method, requestCtor, responseCtor, request, callback) {
      if (!request)
        throw TypeError("request must be specified");
      var self2 = this;
      if (!callback)
        return util.asPromise(rpcCall, self2, method, requestCtor, responseCtor, request);
      if (!self2.rpcImpl) {
        setTimeout(function() {
          callback(Error("already ended"));
        }, 0);
        return void 0;
      }
      try {
        return self2.rpcImpl(
          method,
          requestCtor[self2.requestDelimited ? "encodeDelimited" : "encode"](request).finish(),
          /* @__PURE__ */ __name(function rpcCallback(err, response) {
            if (err) {
              self2.emit("error", err, method);
              return callback(err);
            }
            if (response === null) {
              self2.end(
                /* endedByRPC */
                true
              );
              return void 0;
            }
            if (!(response instanceof responseCtor)) {
              try {
                response = responseCtor[self2.responseDelimited ? "decodeDelimited" : "decode"](response);
              } catch (err2) {
                self2.emit("error", err2, method);
                return callback(err2);
              }
            }
            self2.emit("data", response, method);
            return callback(null, response);
          }, "rpcCallback")
        );
      } catch (err) {
        self2.emit("error", err, method);
        setTimeout(function() {
          callback(err);
        }, 0);
        return void 0;
      }
    }, "rpcCall");
    Service.prototype.end = /* @__PURE__ */ __name(function end(endedByRPC) {
      if (this.rpcImpl) {
        if (!endedByRPC)
          this.rpcImpl(null, null, null);
        this.rpcImpl = null;
        this.emit("end").off();
      }
      return this;
    }, "end");
  }
});

// node_modules/protobufjs/src/rpc.js
var require_rpc = __commonJS({
  "node_modules/protobufjs/src/rpc.js"(exports) {
    "use strict";
    init_modules_watch_stub();
    var rpc = exports;
    rpc.Service = require_service();
  }
});

// node_modules/protobufjs/src/roots.js
var require_roots = __commonJS({
  "node_modules/protobufjs/src/roots.js"(exports, module) {
    "use strict";
    init_modules_watch_stub();
    module.exports = /* @__PURE__ */ Object.create(null);
  }
});

// node_modules/protobufjs/src/index-minimal.js
var require_index_minimal = __commonJS({
  "node_modules/protobufjs/src/index-minimal.js"(exports) {
    "use strict";
    init_modules_watch_stub();
    exports.build = "minimal";
    exports.Writer = require_writer();
    exports.BufferWriter = require_writer_buffer();
    exports.Reader = require_reader();
    exports.BufferReader = require_reader_buffer();
    exports.util = require_minimal();
    exports.rpc = require_rpc();
    exports.roots = require_roots();
    exports.configure = configure;
    function configure() {
      exports.util.LongBits._configure(exports.util.Long);
      exports.Writer._configure(exports.BufferWriter);
      exports.Reader._configure(exports.BufferReader);
    }
    __name(configure, "configure");
    configure();
  }
});

// node_modules/protobufjs/minimal.js
var require_minimal2 = __commonJS({
  "node_modules/protobufjs/minimal.js"(exports, module) {
    "use strict";
    init_modules_watch_stub();
    module.exports = require_index_minimal();
  }
});

// .wrangler/tmp/bundle-PN86BB/middleware-loader.entry.ts
init_modules_watch_stub();

// .wrangler/tmp/bundle-PN86BB/middleware-insertion-facade.js
init_modules_watch_stub();

// src/index.ts
init_modules_watch_stub();

// src/gtfs.ts
init_modules_watch_stub();

// src/proto/gtfs-realtime.js
init_modules_watch_stub();
var import_minimal = __toESM(require_minimal2(), 1);
var $Reader = import_minimal.default.Reader;
var $Writer = import_minimal.default.Writer;
var $util = import_minimal.default.util;
var $Object = $util.global.Object;
var $undefined = $util.global.undefined;
var $Error = $util.global.Error;
var $RangeError = $util.global.RangeError;
var $Array = $util.global.Array;
var $TypeError = $util.global.TypeError;
var $String = $util.global.String;
var $parseInt = $util.global.parseInt;
var $Number = $util.global.Number;
var $BigInt = $util.global.BigInt;
var $Boolean = $util.global.Boolean;
var $isFinite = $util.global.isFinite;
var $root = import_minimal.default.roots["default"] || (import_minimal.default.roots["default"] = {});
var transit_realtime = $root.transit_realtime = (() => {
  const transit_realtime2 = {};
  transit_realtime2.FeedMessage = (function() {
    const FeedMessage = /* @__PURE__ */ __name(function(properties) {
      this.entity = [];
      if (properties) {
        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
          if (properties[keys[i]] != null && keys[i] !== "__proto__")
            this[keys[i]] = properties[keys[i]];
      }
    }, "FeedMessage");
    FeedMessage.prototype.header = null;
    FeedMessage.prototype.entity = $util.emptyArray;
    FeedMessage.create = function(properties) {
      return new FeedMessage(properties);
    };
    FeedMessage.encode = function(message, writer, _depth) {
      if (!writer)
        writer = $Writer.create();
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      $root.transit_realtime.FeedHeader.encode(message.header, writer.uint32(
        /* id 1, wireType 2 =*/
        10
      ).fork(), _depth + 1).ldelim();
      if (message.entity != null && message.entity.length)
        for (let i = 0; i < message.entity.length; ++i)
          $root.transit_realtime.FeedEntity.encode(message.entity[i], writer.uint32(
            /* id 2, wireType 2 =*/
            18
          ).fork(), _depth + 1).ldelim();
      if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
        for (let i = 0; i < message.$unknowns.length; ++i)
          writer.raw(message.$unknowns[i]);
      return writer;
    };
    FeedMessage.encodeDelimited = function(message, writer) {
      return this.encode(message, (writer || $Writer.create()).fork()).ldelim();
    };
    FeedMessage.decode = function(reader, length, _end, _depth, _target) {
      if (!(reader instanceof $Reader))
        reader = $Reader.create(reader);
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $Reader.recursionLimit)
        throw $Error("max depth exceeded");
      let end, message;
      if (length === $undefined)
        end = reader.len;
      else {
        end = reader.pos + length;
        if (end > reader.len)
          throw $RangeError("index out of range");
        length = reader.len;
        reader.len = end;
      }
      message = _target || new $root.transit_realtime.FeedMessage();
      while (reader.pos < end) {
        let start = reader.pos;
        let tag = reader.tag();
        if (tag === _end) {
          _end = $undefined;
          break;
        }
        let wireType = tag & 7;
        switch (tag >>>= 3) {
          case 1: {
            if (wireType !== 2)
              break;
            message.header = $root.transit_realtime.FeedHeader.decode(reader, reader.uint32(), $undefined, _depth + 1, message.header);
            continue;
          }
          case 2: {
            if (wireType !== 2)
              break;
            if (!(message.entity && message.entity.length))
              message.entity = [];
            message.entity.push($root.transit_realtime.FeedEntity.decode(reader, reader.uint32(), $undefined, _depth + 1));
            continue;
          }
        }
        reader.skipType(wireType, _depth, tag);
        if (!reader.discardUnknown) {
          $util.makeProp(message, "$unknowns", false);
          (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
        }
      }
      if (length !== $undefined) {
        if (reader.pos !== end)
          throw $RangeError("index out of range");
        reader.len = length;
      }
      if (_end !== $undefined)
        throw $Error("missing end group");
      if (!$Object.hasOwnProperty.call(message, "header"))
        throw $util.ProtocolError("missing required 'header'", { instance: message });
      return message;
    };
    FeedMessage.decodeDelimited = function(reader) {
      if (!(reader instanceof $Reader))
        reader = new $Reader(reader);
      return this.decode(reader, reader.uint32());
    };
    FeedMessage.verify = function(message, _depth) {
      if (typeof message !== "object" || message === null)
        return "object expected";
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        return "max depth exceeded";
      {
        let error = $root.transit_realtime.FeedHeader.verify(message.header, _depth + 1);
        if (error)
          return "header." + error;
      }
      if (message.entity != null && $Object.hasOwnProperty.call(message, "entity")) {
        if (!$Array.isArray(message.entity))
          return "entity: array expected";
        for (let i = 0; i < message.entity.length; ++i) {
          let error = $root.transit_realtime.FeedEntity.verify(message.entity[i], _depth + 1);
          if (error)
            return "entity." + error;
        }
      }
      return null;
    };
    FeedMessage.fromObject = function(object, _depth) {
      if (object instanceof $root.transit_realtime.FeedMessage)
        return object;
      if (!$util.isObject(object))
        throw $TypeError(".transit_realtime.FeedMessage: object expected");
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let message = new $root.transit_realtime.FeedMessage();
      if (object.header != null) {
        if (!$util.isObject(object.header))
          throw $TypeError(".transit_realtime.FeedMessage.header: object expected");
        message.header = $root.transit_realtime.FeedHeader.fromObject(object.header, _depth + 1);
      }
      if (object.entity) {
        if (!$Array.isArray(object.entity))
          throw $TypeError(".transit_realtime.FeedMessage.entity: array expected");
        message.entity = $Array(object.entity.length);
        for (let i = 0; i < object.entity.length; ++i) {
          if (!$util.isObject(object.entity[i]))
            throw $TypeError(".transit_realtime.FeedMessage.entity: object expected");
          message.entity[i] = $root.transit_realtime.FeedEntity.fromObject(object.entity[i], _depth + 1);
        }
      }
      return message;
    };
    FeedMessage.toObject = function(message, options, _depth) {
      if (!options)
        options = {};
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let object = {};
      if (options.arrays || options.defaults)
        object.entity = [];
      if (options.defaults)
        object.header = null;
      if (message.header != null && $Object.hasOwnProperty.call(message, "header"))
        object.header = $root.transit_realtime.FeedHeader.toObject(message.header, options, _depth + 1);
      if (message.entity && message.entity.length) {
        object.entity = $Array(message.entity.length);
        for (let j = 0; j < message.entity.length; ++j)
          object.entity[j] = $root.transit_realtime.FeedEntity.toObject(message.entity[j], options, _depth + 1);
      }
      return object;
    };
    FeedMessage.prototype.toJSON = function() {
      return FeedMessage.toObject(this, import_minimal.default.util.toJSONOptions);
    };
    FeedMessage.getTypeUrl = function(prefix) {
      if (prefix === $undefined)
        prefix = "type.googleapis.com";
      return prefix + "/transit_realtime.FeedMessage";
    };
    return FeedMessage;
  })();
  transit_realtime2.FeedHeader = (function() {
    const FeedHeader = /* @__PURE__ */ __name(function(properties) {
      if (properties) {
        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
          if (properties[keys[i]] != null && keys[i] !== "__proto__")
            this[keys[i]] = properties[keys[i]];
      }
    }, "FeedHeader");
    FeedHeader.prototype.gtfsRealtimeVersion = "";
    FeedHeader.prototype.incrementality = 0;
    FeedHeader.prototype.timestamp = $util.Long ? $util.Long.fromBits(0, 0, true) : 0;
    FeedHeader.prototype.feedVersion = "";
    FeedHeader.prototype[".transit_realtime.nyctFeedHeader"] = null;
    FeedHeader.prototype[".transit_realtime.mercuryFeedHeader"] = null;
    FeedHeader.create = function(properties) {
      return new FeedHeader(properties);
    };
    FeedHeader.encode = function(message, writer, _depth) {
      if (!writer)
        writer = $Writer.create();
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      writer.uint32(
        /* id 1, wireType 2 =*/
        10
      ).string(message.gtfsRealtimeVersion);
      if (message.incrementality != null && $Object.hasOwnProperty.call(message, "incrementality"))
        writer.uint32(
          /* id 2, wireType 0 =*/
          16
        ).int32(message.incrementality);
      if (message.timestamp != null && $Object.hasOwnProperty.call(message, "timestamp"))
        writer.uint32(
          /* id 3, wireType 0 =*/
          24
        ).uint64(message.timestamp);
      if (message.feedVersion != null && $Object.hasOwnProperty.call(message, "feedVersion"))
        writer.uint32(
          /* id 4, wireType 2 =*/
          34
        ).string(message.feedVersion);
      if (message[".transit_realtime.nyctFeedHeader"] != null && $Object.hasOwnProperty.call(message, ".transit_realtime.nyctFeedHeader"))
        $root.transit_realtime.NyctFeedHeader.encode(message[".transit_realtime.nyctFeedHeader"], writer.uint32(
          /* id 1001, wireType 2 =*/
          8010
        ).fork(), _depth + 1).ldelim();
      if (message[".transit_realtime.mercuryFeedHeader"] != null && $Object.hasOwnProperty.call(message, ".transit_realtime.mercuryFeedHeader"))
        $root.transit_realtime.MercuryFeedHeader.encode(message[".transit_realtime.mercuryFeedHeader"], writer.uint32(
          /* id 1002, wireType 2 =*/
          8018
        ).fork(), _depth + 1).ldelim();
      if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
        for (let i = 0; i < message.$unknowns.length; ++i)
          writer.raw(message.$unknowns[i]);
      return writer;
    };
    FeedHeader.encodeDelimited = function(message, writer) {
      return this.encode(message, (writer || $Writer.create()).fork()).ldelim();
    };
    FeedHeader.decode = function(reader, length, _end, _depth, _target) {
      if (!(reader instanceof $Reader))
        reader = $Reader.create(reader);
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $Reader.recursionLimit)
        throw $Error("max depth exceeded");
      let end, message, value;
      if (length === $undefined)
        end = reader.len;
      else {
        end = reader.pos + length;
        if (end > reader.len)
          throw $RangeError("index out of range");
        length = reader.len;
        reader.len = end;
      }
      message = _target || new $root.transit_realtime.FeedHeader();
      while (reader.pos < end) {
        let start = reader.pos;
        let tag = reader.tag();
        if (tag === _end) {
          _end = $undefined;
          break;
        }
        let wireType = tag & 7;
        switch (tag >>>= 3) {
          case 1: {
            if (wireType !== 2)
              break;
            message.gtfsRealtimeVersion = reader.string();
            continue;
          }
          case 2: {
            if (wireType !== 0)
              break;
            value = reader.int32();
            if ($root.transit_realtime.FeedHeader.Incrementality[value] !== $undefined)
              message.incrementality = value;
            else if (!reader.discardUnknown) {
              $util.makeProp(message, "$unknowns", false);
              (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
            }
            continue;
          }
          case 3: {
            if (wireType !== 0)
              break;
            message.timestamp = reader.uint64();
            continue;
          }
          case 4: {
            if (wireType !== 2)
              break;
            message.feedVersion = reader.string();
            continue;
          }
          case 1001: {
            if (wireType !== 2)
              break;
            message[".transit_realtime.nyctFeedHeader"] = $root.transit_realtime.NyctFeedHeader.decode(reader, reader.uint32(), $undefined, _depth + 1, message[".transit_realtime.nyctFeedHeader"]);
            continue;
          }
          case 1002: {
            if (wireType !== 2)
              break;
            message[".transit_realtime.mercuryFeedHeader"] = $root.transit_realtime.MercuryFeedHeader.decode(reader, reader.uint32(), $undefined, _depth + 1, message[".transit_realtime.mercuryFeedHeader"]);
            continue;
          }
        }
        reader.skipType(wireType, _depth, tag);
        if (!reader.discardUnknown) {
          $util.makeProp(message, "$unknowns", false);
          (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
        }
      }
      if (length !== $undefined) {
        if (reader.pos !== end)
          throw $RangeError("index out of range");
        reader.len = length;
      }
      if (_end !== $undefined)
        throw $Error("missing end group");
      if (!$Object.hasOwnProperty.call(message, "gtfsRealtimeVersion"))
        throw $util.ProtocolError("missing required 'gtfsRealtimeVersion'", { instance: message });
      return message;
    };
    FeedHeader.decodeDelimited = function(reader) {
      if (!(reader instanceof $Reader))
        reader = new $Reader(reader);
      return this.decode(reader, reader.uint32());
    };
    FeedHeader.verify = function(message, _depth) {
      if (typeof message !== "object" || message === null)
        return "object expected";
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        return "max depth exceeded";
      if (!$util.isString(message.gtfsRealtimeVersion))
        return "gtfsRealtimeVersion: string expected";
      if (message.incrementality != null && $Object.hasOwnProperty.call(message, "incrementality"))
        switch (message.incrementality) {
          default:
            return "incrementality: enum value expected";
          case 0:
          case 1:
            break;
        }
      if (message.timestamp != null && $Object.hasOwnProperty.call(message, "timestamp")) {
        if (!$util.isInteger(message.timestamp) && !(message.timestamp && $util.isInteger(message.timestamp.low) && $util.isInteger(message.timestamp.high)))
          return "timestamp: integer|Long expected";
      }
      if (message.feedVersion != null && $Object.hasOwnProperty.call(message, "feedVersion")) {
        if (!$util.isString(message.feedVersion))
          return "feedVersion: string expected";
      }
      if (message[".transit_realtime.nyctFeedHeader"] != null && $Object.hasOwnProperty.call(message, ".transit_realtime.nyctFeedHeader")) {
        let error = $root.transit_realtime.NyctFeedHeader.verify(message[".transit_realtime.nyctFeedHeader"], _depth + 1);
        if (error)
          return ".transit_realtime.nyctFeedHeader." + error;
      }
      if (message[".transit_realtime.mercuryFeedHeader"] != null && $Object.hasOwnProperty.call(message, ".transit_realtime.mercuryFeedHeader")) {
        let error = $root.transit_realtime.MercuryFeedHeader.verify(message[".transit_realtime.mercuryFeedHeader"], _depth + 1);
        if (error)
          return ".transit_realtime.mercuryFeedHeader." + error;
      }
      return null;
    };
    FeedHeader.fromObject = function(object, _depth) {
      if (object instanceof $root.transit_realtime.FeedHeader)
        return object;
      if (!$util.isObject(object))
        throw $TypeError(".transit_realtime.FeedHeader: object expected");
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let message = new $root.transit_realtime.FeedHeader();
      if (object.gtfsRealtimeVersion != null)
        message.gtfsRealtimeVersion = $String(object.gtfsRealtimeVersion);
      switch (object.incrementality) {
        case "FULL_DATASET":
        case 0:
          message.incrementality = 0;
          break;
        case "DIFFERENTIAL":
        case 1:
          message.incrementality = 1;
          break;
        default:
      }
      if (object.timestamp != null) {
        if ($util.Long)
          message.timestamp = $util.Long.fromValue(object.timestamp, true);
        else if (typeof object.timestamp === "string")
          message.timestamp = $parseInt(object.timestamp, 10);
        else if (typeof object.timestamp === "number")
          message.timestamp = object.timestamp;
        else if (typeof object.timestamp === "object")
          message.timestamp = new $util.LongBits(object.timestamp.low >>> 0, object.timestamp.high >>> 0).toNumber(true);
      }
      if (object.feedVersion != null)
        message.feedVersion = $String(object.feedVersion);
      if (object[".transit_realtime.nyctFeedHeader"] != null) {
        if (!$util.isObject(object[".transit_realtime.nyctFeedHeader"]))
          throw $TypeError(".transit_realtime.FeedHeader..transit_realtime.nyctFeedHeader: object expected");
        message[".transit_realtime.nyctFeedHeader"] = $root.transit_realtime.NyctFeedHeader.fromObject(object[".transit_realtime.nyctFeedHeader"], _depth + 1);
      }
      if (object[".transit_realtime.mercuryFeedHeader"] != null) {
        if (!$util.isObject(object[".transit_realtime.mercuryFeedHeader"]))
          throw $TypeError(".transit_realtime.FeedHeader..transit_realtime.mercuryFeedHeader: object expected");
        message[".transit_realtime.mercuryFeedHeader"] = $root.transit_realtime.MercuryFeedHeader.fromObject(object[".transit_realtime.mercuryFeedHeader"], _depth + 1);
      }
      return message;
    };
    FeedHeader.toObject = function(message, options, _depth) {
      if (!options)
        options = {};
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let object = {};
      if (options.defaults) {
        object.gtfsRealtimeVersion = "";
        object.incrementality = options.enums === $String ? "FULL_DATASET" : 0;
        if ($util.Long) {
          let long = new $util.Long(0, 0, true);
          object.timestamp = options.longs === $String ? long.toString() : options.longs === $Number ? long.toNumber() : typeof $BigInt !== "undefined" && options.longs === $BigInt ? long.toBigInt() : long;
        } else
          object.timestamp = options.longs === $String ? "0" : typeof $BigInt !== "undefined" && options.longs === $BigInt ? $BigInt("0") : 0;
        object.feedVersion = "";
        object[".transit_realtime.nyctFeedHeader"] = null;
        object[".transit_realtime.mercuryFeedHeader"] = null;
      }
      if (message.gtfsRealtimeVersion != null && $Object.hasOwnProperty.call(message, "gtfsRealtimeVersion"))
        object.gtfsRealtimeVersion = message.gtfsRealtimeVersion;
      if (message.incrementality != null && $Object.hasOwnProperty.call(message, "incrementality"))
        object.incrementality = options.enums === $String ? $root.transit_realtime.FeedHeader.Incrementality[message.incrementality] === $undefined ? message.incrementality : $root.transit_realtime.FeedHeader.Incrementality[message.incrementality] : message.incrementality;
      if (message.timestamp != null && $Object.hasOwnProperty.call(message, "timestamp"))
        if (typeof $BigInt !== "undefined" && options.longs === $BigInt)
          object.timestamp = typeof message.timestamp === "number" ? $BigInt(message.timestamp) : $util.Long.fromBits(message.timestamp.low >>> 0, message.timestamp.high >>> 0, true).toBigInt();
        else if (typeof message.timestamp === "number")
          object.timestamp = options.longs === $String ? $String(message.timestamp) : message.timestamp;
        else
          object.timestamp = options.longs === $String ? $util.Long.prototype.toString.call(message.timestamp) : options.longs === $Number ? new $util.LongBits(message.timestamp.low >>> 0, message.timestamp.high >>> 0).toNumber(true) : message.timestamp;
      if (message.feedVersion != null && $Object.hasOwnProperty.call(message, "feedVersion"))
        object.feedVersion = message.feedVersion;
      if (message[".transit_realtime.nyctFeedHeader"] != null && $Object.hasOwnProperty.call(message, ".transit_realtime.nyctFeedHeader"))
        object[".transit_realtime.nyctFeedHeader"] = $root.transit_realtime.NyctFeedHeader.toObject(message[".transit_realtime.nyctFeedHeader"], options, _depth + 1);
      if (message[".transit_realtime.mercuryFeedHeader"] != null && $Object.hasOwnProperty.call(message, ".transit_realtime.mercuryFeedHeader"))
        object[".transit_realtime.mercuryFeedHeader"] = $root.transit_realtime.MercuryFeedHeader.toObject(message[".transit_realtime.mercuryFeedHeader"], options, _depth + 1);
      return object;
    };
    FeedHeader.prototype.toJSON = function() {
      return FeedHeader.toObject(this, import_minimal.default.util.toJSONOptions);
    };
    FeedHeader.getTypeUrl = function(prefix) {
      if (prefix === $undefined)
        prefix = "type.googleapis.com";
      return prefix + "/transit_realtime.FeedHeader";
    };
    FeedHeader.Incrementality = (function() {
      const valuesById = $Object.create(null), values = $Object.create(valuesById);
      values[valuesById[0] = "FULL_DATASET"] = 0;
      values[valuesById[1] = "DIFFERENTIAL"] = 1;
      return values;
    })();
    return FeedHeader;
  })();
  transit_realtime2.FeedEntity = (function() {
    const FeedEntity = /* @__PURE__ */ __name(function(properties) {
      if (properties) {
        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
          if (properties[keys[i]] != null && keys[i] !== "__proto__")
            this[keys[i]] = properties[keys[i]];
      }
    }, "FeedEntity");
    FeedEntity.prototype.id = "";
    FeedEntity.prototype.isDeleted = false;
    FeedEntity.prototype.tripUpdate = null;
    FeedEntity.prototype.vehicle = null;
    FeedEntity.prototype.alert = null;
    FeedEntity.prototype.shape = null;
    FeedEntity.prototype.stop = null;
    FeedEntity.prototype.tripModifications = null;
    FeedEntity.create = function(properties) {
      return new FeedEntity(properties);
    };
    FeedEntity.encode = function(message, writer, _depth) {
      if (!writer)
        writer = $Writer.create();
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      writer.uint32(
        /* id 1, wireType 2 =*/
        10
      ).string(message.id);
      if (message.isDeleted != null && $Object.hasOwnProperty.call(message, "isDeleted"))
        writer.uint32(
          /* id 2, wireType 0 =*/
          16
        ).bool(message.isDeleted);
      if (message.tripUpdate != null && $Object.hasOwnProperty.call(message, "tripUpdate"))
        $root.transit_realtime.TripUpdate.encode(message.tripUpdate, writer.uint32(
          /* id 3, wireType 2 =*/
          26
        ).fork(), _depth + 1).ldelim();
      if (message.vehicle != null && $Object.hasOwnProperty.call(message, "vehicle"))
        $root.transit_realtime.VehiclePosition.encode(message.vehicle, writer.uint32(
          /* id 4, wireType 2 =*/
          34
        ).fork(), _depth + 1).ldelim();
      if (message.alert != null && $Object.hasOwnProperty.call(message, "alert"))
        $root.transit_realtime.Alert.encode(message.alert, writer.uint32(
          /* id 5, wireType 2 =*/
          42
        ).fork(), _depth + 1).ldelim();
      if (message.shape != null && $Object.hasOwnProperty.call(message, "shape"))
        $root.transit_realtime.Shape.encode(message.shape, writer.uint32(
          /* id 6, wireType 2 =*/
          50
        ).fork(), _depth + 1).ldelim();
      if (message.stop != null && $Object.hasOwnProperty.call(message, "stop"))
        $root.transit_realtime.Stop.encode(message.stop, writer.uint32(
          /* id 7, wireType 2 =*/
          58
        ).fork(), _depth + 1).ldelim();
      if (message.tripModifications != null && $Object.hasOwnProperty.call(message, "tripModifications"))
        $root.transit_realtime.TripModifications.encode(message.tripModifications, writer.uint32(
          /* id 8, wireType 2 =*/
          66
        ).fork(), _depth + 1).ldelim();
      if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
        for (let i = 0; i < message.$unknowns.length; ++i)
          writer.raw(message.$unknowns[i]);
      return writer;
    };
    FeedEntity.encodeDelimited = function(message, writer) {
      return this.encode(message, (writer || $Writer.create()).fork()).ldelim();
    };
    FeedEntity.decode = function(reader, length, _end, _depth, _target) {
      if (!(reader instanceof $Reader))
        reader = $Reader.create(reader);
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $Reader.recursionLimit)
        throw $Error("max depth exceeded");
      let end, message;
      if (length === $undefined)
        end = reader.len;
      else {
        end = reader.pos + length;
        if (end > reader.len)
          throw $RangeError("index out of range");
        length = reader.len;
        reader.len = end;
      }
      message = _target || new $root.transit_realtime.FeedEntity();
      while (reader.pos < end) {
        let start = reader.pos;
        let tag = reader.tag();
        if (tag === _end) {
          _end = $undefined;
          break;
        }
        let wireType = tag & 7;
        switch (tag >>>= 3) {
          case 1: {
            if (wireType !== 2)
              break;
            message.id = reader.string();
            continue;
          }
          case 2: {
            if (wireType !== 0)
              break;
            message.isDeleted = reader.bool();
            continue;
          }
          case 3: {
            if (wireType !== 2)
              break;
            message.tripUpdate = $root.transit_realtime.TripUpdate.decode(reader, reader.uint32(), $undefined, _depth + 1, message.tripUpdate);
            continue;
          }
          case 4: {
            if (wireType !== 2)
              break;
            message.vehicle = $root.transit_realtime.VehiclePosition.decode(reader, reader.uint32(), $undefined, _depth + 1, message.vehicle);
            continue;
          }
          case 5: {
            if (wireType !== 2)
              break;
            message.alert = $root.transit_realtime.Alert.decode(reader, reader.uint32(), $undefined, _depth + 1, message.alert);
            continue;
          }
          case 6: {
            if (wireType !== 2)
              break;
            message.shape = $root.transit_realtime.Shape.decode(reader, reader.uint32(), $undefined, _depth + 1, message.shape);
            continue;
          }
          case 7: {
            if (wireType !== 2)
              break;
            message.stop = $root.transit_realtime.Stop.decode(reader, reader.uint32(), $undefined, _depth + 1, message.stop);
            continue;
          }
          case 8: {
            if (wireType !== 2)
              break;
            message.tripModifications = $root.transit_realtime.TripModifications.decode(reader, reader.uint32(), $undefined, _depth + 1, message.tripModifications);
            continue;
          }
        }
        reader.skipType(wireType, _depth, tag);
        if (!reader.discardUnknown) {
          $util.makeProp(message, "$unknowns", false);
          (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
        }
      }
      if (length !== $undefined) {
        if (reader.pos !== end)
          throw $RangeError("index out of range");
        reader.len = length;
      }
      if (_end !== $undefined)
        throw $Error("missing end group");
      if (!$Object.hasOwnProperty.call(message, "id"))
        throw $util.ProtocolError("missing required 'id'", { instance: message });
      return message;
    };
    FeedEntity.decodeDelimited = function(reader) {
      if (!(reader instanceof $Reader))
        reader = new $Reader(reader);
      return this.decode(reader, reader.uint32());
    };
    FeedEntity.verify = function(message, _depth) {
      if (typeof message !== "object" || message === null)
        return "object expected";
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        return "max depth exceeded";
      if (!$util.isString(message.id))
        return "id: string expected";
      if (message.isDeleted != null && $Object.hasOwnProperty.call(message, "isDeleted")) {
        if (typeof message.isDeleted !== "boolean")
          return "isDeleted: boolean expected";
      }
      if (message.tripUpdate != null && $Object.hasOwnProperty.call(message, "tripUpdate")) {
        let error = $root.transit_realtime.TripUpdate.verify(message.tripUpdate, _depth + 1);
        if (error)
          return "tripUpdate." + error;
      }
      if (message.vehicle != null && $Object.hasOwnProperty.call(message, "vehicle")) {
        let error = $root.transit_realtime.VehiclePosition.verify(message.vehicle, _depth + 1);
        if (error)
          return "vehicle." + error;
      }
      if (message.alert != null && $Object.hasOwnProperty.call(message, "alert")) {
        let error = $root.transit_realtime.Alert.verify(message.alert, _depth + 1);
        if (error)
          return "alert." + error;
      }
      if (message.shape != null && $Object.hasOwnProperty.call(message, "shape")) {
        let error = $root.transit_realtime.Shape.verify(message.shape, _depth + 1);
        if (error)
          return "shape." + error;
      }
      if (message.stop != null && $Object.hasOwnProperty.call(message, "stop")) {
        let error = $root.transit_realtime.Stop.verify(message.stop, _depth + 1);
        if (error)
          return "stop." + error;
      }
      if (message.tripModifications != null && $Object.hasOwnProperty.call(message, "tripModifications")) {
        let error = $root.transit_realtime.TripModifications.verify(message.tripModifications, _depth + 1);
        if (error)
          return "tripModifications." + error;
      }
      return null;
    };
    FeedEntity.fromObject = function(object, _depth) {
      if (object instanceof $root.transit_realtime.FeedEntity)
        return object;
      if (!$util.isObject(object))
        throw $TypeError(".transit_realtime.FeedEntity: object expected");
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let message = new $root.transit_realtime.FeedEntity();
      if (object.id != null)
        message.id = $String(object.id);
      if (object.isDeleted != null)
        message.isDeleted = $Boolean(object.isDeleted);
      if (object.tripUpdate != null) {
        if (!$util.isObject(object.tripUpdate))
          throw $TypeError(".transit_realtime.FeedEntity.tripUpdate: object expected");
        message.tripUpdate = $root.transit_realtime.TripUpdate.fromObject(object.tripUpdate, _depth + 1);
      }
      if (object.vehicle != null) {
        if (!$util.isObject(object.vehicle))
          throw $TypeError(".transit_realtime.FeedEntity.vehicle: object expected");
        message.vehicle = $root.transit_realtime.VehiclePosition.fromObject(object.vehicle, _depth + 1);
      }
      if (object.alert != null) {
        if (!$util.isObject(object.alert))
          throw $TypeError(".transit_realtime.FeedEntity.alert: object expected");
        message.alert = $root.transit_realtime.Alert.fromObject(object.alert, _depth + 1);
      }
      if (object.shape != null) {
        if (!$util.isObject(object.shape))
          throw $TypeError(".transit_realtime.FeedEntity.shape: object expected");
        message.shape = $root.transit_realtime.Shape.fromObject(object.shape, _depth + 1);
      }
      if (object.stop != null) {
        if (!$util.isObject(object.stop))
          throw $TypeError(".transit_realtime.FeedEntity.stop: object expected");
        message.stop = $root.transit_realtime.Stop.fromObject(object.stop, _depth + 1);
      }
      if (object.tripModifications != null) {
        if (!$util.isObject(object.tripModifications))
          throw $TypeError(".transit_realtime.FeedEntity.tripModifications: object expected");
        message.tripModifications = $root.transit_realtime.TripModifications.fromObject(object.tripModifications, _depth + 1);
      }
      return message;
    };
    FeedEntity.toObject = function(message, options, _depth) {
      if (!options)
        options = {};
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let object = {};
      if (options.defaults) {
        object.id = "";
        object.isDeleted = false;
        object.tripUpdate = null;
        object.vehicle = null;
        object.alert = null;
        object.shape = null;
        object.stop = null;
        object.tripModifications = null;
      }
      if (message.id != null && $Object.hasOwnProperty.call(message, "id"))
        object.id = message.id;
      if (message.isDeleted != null && $Object.hasOwnProperty.call(message, "isDeleted"))
        object.isDeleted = message.isDeleted;
      if (message.tripUpdate != null && $Object.hasOwnProperty.call(message, "tripUpdate"))
        object.tripUpdate = $root.transit_realtime.TripUpdate.toObject(message.tripUpdate, options, _depth + 1);
      if (message.vehicle != null && $Object.hasOwnProperty.call(message, "vehicle"))
        object.vehicle = $root.transit_realtime.VehiclePosition.toObject(message.vehicle, options, _depth + 1);
      if (message.alert != null && $Object.hasOwnProperty.call(message, "alert"))
        object.alert = $root.transit_realtime.Alert.toObject(message.alert, options, _depth + 1);
      if (message.shape != null && $Object.hasOwnProperty.call(message, "shape"))
        object.shape = $root.transit_realtime.Shape.toObject(message.shape, options, _depth + 1);
      if (message.stop != null && $Object.hasOwnProperty.call(message, "stop"))
        object.stop = $root.transit_realtime.Stop.toObject(message.stop, options, _depth + 1);
      if (message.tripModifications != null && $Object.hasOwnProperty.call(message, "tripModifications"))
        object.tripModifications = $root.transit_realtime.TripModifications.toObject(message.tripModifications, options, _depth + 1);
      return object;
    };
    FeedEntity.prototype.toJSON = function() {
      return FeedEntity.toObject(this, import_minimal.default.util.toJSONOptions);
    };
    FeedEntity.getTypeUrl = function(prefix) {
      if (prefix === $undefined)
        prefix = "type.googleapis.com";
      return prefix + "/transit_realtime.FeedEntity";
    };
    return FeedEntity;
  })();
  transit_realtime2.TripUpdate = (function() {
    const TripUpdate = /* @__PURE__ */ __name(function(properties) {
      this.stopTimeUpdate = [];
      if (properties) {
        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
          if (properties[keys[i]] != null && keys[i] !== "__proto__")
            this[keys[i]] = properties[keys[i]];
      }
    }, "TripUpdate");
    TripUpdate.prototype.trip = null;
    TripUpdate.prototype.vehicle = null;
    TripUpdate.prototype.stopTimeUpdate = $util.emptyArray;
    TripUpdate.prototype.timestamp = $util.Long ? $util.Long.fromBits(0, 0, true) : 0;
    TripUpdate.prototype.delay = 0;
    TripUpdate.prototype.tripProperties = null;
    TripUpdate.create = function(properties) {
      return new TripUpdate(properties);
    };
    TripUpdate.encode = function(message, writer, _depth) {
      if (!writer)
        writer = $Writer.create();
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      $root.transit_realtime.TripDescriptor.encode(message.trip, writer.uint32(
        /* id 1, wireType 2 =*/
        10
      ).fork(), _depth + 1).ldelim();
      if (message.stopTimeUpdate != null && message.stopTimeUpdate.length)
        for (let i = 0; i < message.stopTimeUpdate.length; ++i)
          $root.transit_realtime.TripUpdate.StopTimeUpdate.encode(message.stopTimeUpdate[i], writer.uint32(
            /* id 2, wireType 2 =*/
            18
          ).fork(), _depth + 1).ldelim();
      if (message.vehicle != null && $Object.hasOwnProperty.call(message, "vehicle"))
        $root.transit_realtime.VehicleDescriptor.encode(message.vehicle, writer.uint32(
          /* id 3, wireType 2 =*/
          26
        ).fork(), _depth + 1).ldelim();
      if (message.timestamp != null && $Object.hasOwnProperty.call(message, "timestamp"))
        writer.uint32(
          /* id 4, wireType 0 =*/
          32
        ).uint64(message.timestamp);
      if (message.delay != null && $Object.hasOwnProperty.call(message, "delay"))
        writer.uint32(
          /* id 5, wireType 0 =*/
          40
        ).int32(message.delay);
      if (message.tripProperties != null && $Object.hasOwnProperty.call(message, "tripProperties"))
        $root.transit_realtime.TripUpdate.TripProperties.encode(message.tripProperties, writer.uint32(
          /* id 6, wireType 2 =*/
          50
        ).fork(), _depth + 1).ldelim();
      if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
        for (let i = 0; i < message.$unknowns.length; ++i)
          writer.raw(message.$unknowns[i]);
      return writer;
    };
    TripUpdate.encodeDelimited = function(message, writer) {
      return this.encode(message, (writer || $Writer.create()).fork()).ldelim();
    };
    TripUpdate.decode = function(reader, length, _end, _depth, _target) {
      if (!(reader instanceof $Reader))
        reader = $Reader.create(reader);
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $Reader.recursionLimit)
        throw $Error("max depth exceeded");
      let end, message;
      if (length === $undefined)
        end = reader.len;
      else {
        end = reader.pos + length;
        if (end > reader.len)
          throw $RangeError("index out of range");
        length = reader.len;
        reader.len = end;
      }
      message = _target || new $root.transit_realtime.TripUpdate();
      while (reader.pos < end) {
        let start = reader.pos;
        let tag = reader.tag();
        if (tag === _end) {
          _end = $undefined;
          break;
        }
        let wireType = tag & 7;
        switch (tag >>>= 3) {
          case 1: {
            if (wireType !== 2)
              break;
            message.trip = $root.transit_realtime.TripDescriptor.decode(reader, reader.uint32(), $undefined, _depth + 1, message.trip);
            continue;
          }
          case 3: {
            if (wireType !== 2)
              break;
            message.vehicle = $root.transit_realtime.VehicleDescriptor.decode(reader, reader.uint32(), $undefined, _depth + 1, message.vehicle);
            continue;
          }
          case 2: {
            if (wireType !== 2)
              break;
            if (!(message.stopTimeUpdate && message.stopTimeUpdate.length))
              message.stopTimeUpdate = [];
            message.stopTimeUpdate.push($root.transit_realtime.TripUpdate.StopTimeUpdate.decode(reader, reader.uint32(), $undefined, _depth + 1));
            continue;
          }
          case 4: {
            if (wireType !== 0)
              break;
            message.timestamp = reader.uint64();
            continue;
          }
          case 5: {
            if (wireType !== 0)
              break;
            message.delay = reader.int32();
            continue;
          }
          case 6: {
            if (wireType !== 2)
              break;
            message.tripProperties = $root.transit_realtime.TripUpdate.TripProperties.decode(reader, reader.uint32(), $undefined, _depth + 1, message.tripProperties);
            continue;
          }
        }
        reader.skipType(wireType, _depth, tag);
        if (!reader.discardUnknown) {
          $util.makeProp(message, "$unknowns", false);
          (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
        }
      }
      if (length !== $undefined) {
        if (reader.pos !== end)
          throw $RangeError("index out of range");
        reader.len = length;
      }
      if (_end !== $undefined)
        throw $Error("missing end group");
      if (!$Object.hasOwnProperty.call(message, "trip"))
        throw $util.ProtocolError("missing required 'trip'", { instance: message });
      return message;
    };
    TripUpdate.decodeDelimited = function(reader) {
      if (!(reader instanceof $Reader))
        reader = new $Reader(reader);
      return this.decode(reader, reader.uint32());
    };
    TripUpdate.verify = function(message, _depth) {
      if (typeof message !== "object" || message === null)
        return "object expected";
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        return "max depth exceeded";
      {
        let error = $root.transit_realtime.TripDescriptor.verify(message.trip, _depth + 1);
        if (error)
          return "trip." + error;
      }
      if (message.vehicle != null && $Object.hasOwnProperty.call(message, "vehicle")) {
        let error = $root.transit_realtime.VehicleDescriptor.verify(message.vehicle, _depth + 1);
        if (error)
          return "vehicle." + error;
      }
      if (message.stopTimeUpdate != null && $Object.hasOwnProperty.call(message, "stopTimeUpdate")) {
        if (!$Array.isArray(message.stopTimeUpdate))
          return "stopTimeUpdate: array expected";
        for (let i = 0; i < message.stopTimeUpdate.length; ++i) {
          let error = $root.transit_realtime.TripUpdate.StopTimeUpdate.verify(message.stopTimeUpdate[i], _depth + 1);
          if (error)
            return "stopTimeUpdate." + error;
        }
      }
      if (message.timestamp != null && $Object.hasOwnProperty.call(message, "timestamp")) {
        if (!$util.isInteger(message.timestamp) && !(message.timestamp && $util.isInteger(message.timestamp.low) && $util.isInteger(message.timestamp.high)))
          return "timestamp: integer|Long expected";
      }
      if (message.delay != null && $Object.hasOwnProperty.call(message, "delay")) {
        if (!$util.isInteger(message.delay))
          return "delay: integer expected";
      }
      if (message.tripProperties != null && $Object.hasOwnProperty.call(message, "tripProperties")) {
        let error = $root.transit_realtime.TripUpdate.TripProperties.verify(message.tripProperties, _depth + 1);
        if (error)
          return "tripProperties." + error;
      }
      return null;
    };
    TripUpdate.fromObject = function(object, _depth) {
      if (object instanceof $root.transit_realtime.TripUpdate)
        return object;
      if (!$util.isObject(object))
        throw $TypeError(".transit_realtime.TripUpdate: object expected");
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let message = new $root.transit_realtime.TripUpdate();
      if (object.trip != null) {
        if (!$util.isObject(object.trip))
          throw $TypeError(".transit_realtime.TripUpdate.trip: object expected");
        message.trip = $root.transit_realtime.TripDescriptor.fromObject(object.trip, _depth + 1);
      }
      if (object.vehicle != null) {
        if (!$util.isObject(object.vehicle))
          throw $TypeError(".transit_realtime.TripUpdate.vehicle: object expected");
        message.vehicle = $root.transit_realtime.VehicleDescriptor.fromObject(object.vehicle, _depth + 1);
      }
      if (object.stopTimeUpdate) {
        if (!$Array.isArray(object.stopTimeUpdate))
          throw $TypeError(".transit_realtime.TripUpdate.stopTimeUpdate: array expected");
        message.stopTimeUpdate = $Array(object.stopTimeUpdate.length);
        for (let i = 0; i < object.stopTimeUpdate.length; ++i) {
          if (!$util.isObject(object.stopTimeUpdate[i]))
            throw $TypeError(".transit_realtime.TripUpdate.stopTimeUpdate: object expected");
          message.stopTimeUpdate[i] = $root.transit_realtime.TripUpdate.StopTimeUpdate.fromObject(object.stopTimeUpdate[i], _depth + 1);
        }
      }
      if (object.timestamp != null) {
        if ($util.Long)
          message.timestamp = $util.Long.fromValue(object.timestamp, true);
        else if (typeof object.timestamp === "string")
          message.timestamp = $parseInt(object.timestamp, 10);
        else if (typeof object.timestamp === "number")
          message.timestamp = object.timestamp;
        else if (typeof object.timestamp === "object")
          message.timestamp = new $util.LongBits(object.timestamp.low >>> 0, object.timestamp.high >>> 0).toNumber(true);
      }
      if (object.delay != null)
        message.delay = object.delay | 0;
      if (object.tripProperties != null) {
        if (!$util.isObject(object.tripProperties))
          throw $TypeError(".transit_realtime.TripUpdate.tripProperties: object expected");
        message.tripProperties = $root.transit_realtime.TripUpdate.TripProperties.fromObject(object.tripProperties, _depth + 1);
      }
      return message;
    };
    TripUpdate.toObject = function(message, options, _depth) {
      if (!options)
        options = {};
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let object = {};
      if (options.arrays || options.defaults)
        object.stopTimeUpdate = [];
      if (options.defaults) {
        object.trip = null;
        object.vehicle = null;
        if ($util.Long) {
          let long = new $util.Long(0, 0, true);
          object.timestamp = options.longs === $String ? long.toString() : options.longs === $Number ? long.toNumber() : typeof $BigInt !== "undefined" && options.longs === $BigInt ? long.toBigInt() : long;
        } else
          object.timestamp = options.longs === $String ? "0" : typeof $BigInt !== "undefined" && options.longs === $BigInt ? $BigInt("0") : 0;
        object.delay = 0;
        object.tripProperties = null;
      }
      if (message.trip != null && $Object.hasOwnProperty.call(message, "trip"))
        object.trip = $root.transit_realtime.TripDescriptor.toObject(message.trip, options, _depth + 1);
      if (message.stopTimeUpdate && message.stopTimeUpdate.length) {
        object.stopTimeUpdate = $Array(message.stopTimeUpdate.length);
        for (let j = 0; j < message.stopTimeUpdate.length; ++j)
          object.stopTimeUpdate[j] = $root.transit_realtime.TripUpdate.StopTimeUpdate.toObject(message.stopTimeUpdate[j], options, _depth + 1);
      }
      if (message.vehicle != null && $Object.hasOwnProperty.call(message, "vehicle"))
        object.vehicle = $root.transit_realtime.VehicleDescriptor.toObject(message.vehicle, options, _depth + 1);
      if (message.timestamp != null && $Object.hasOwnProperty.call(message, "timestamp"))
        if (typeof $BigInt !== "undefined" && options.longs === $BigInt)
          object.timestamp = typeof message.timestamp === "number" ? $BigInt(message.timestamp) : $util.Long.fromBits(message.timestamp.low >>> 0, message.timestamp.high >>> 0, true).toBigInt();
        else if (typeof message.timestamp === "number")
          object.timestamp = options.longs === $String ? $String(message.timestamp) : message.timestamp;
        else
          object.timestamp = options.longs === $String ? $util.Long.prototype.toString.call(message.timestamp) : options.longs === $Number ? new $util.LongBits(message.timestamp.low >>> 0, message.timestamp.high >>> 0).toNumber(true) : message.timestamp;
      if (message.delay != null && $Object.hasOwnProperty.call(message, "delay"))
        object.delay = message.delay;
      if (message.tripProperties != null && $Object.hasOwnProperty.call(message, "tripProperties"))
        object.tripProperties = $root.transit_realtime.TripUpdate.TripProperties.toObject(message.tripProperties, options, _depth + 1);
      return object;
    };
    TripUpdate.prototype.toJSON = function() {
      return TripUpdate.toObject(this, import_minimal.default.util.toJSONOptions);
    };
    TripUpdate.getTypeUrl = function(prefix) {
      if (prefix === $undefined)
        prefix = "type.googleapis.com";
      return prefix + "/transit_realtime.TripUpdate";
    };
    TripUpdate.StopTimeEvent = (function() {
      const StopTimeEvent = /* @__PURE__ */ __name(function(properties) {
        if (properties) {
          for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
            if (properties[keys[i]] != null && keys[i] !== "__proto__")
              this[keys[i]] = properties[keys[i]];
        }
      }, "StopTimeEvent");
      StopTimeEvent.prototype.delay = 0;
      StopTimeEvent.prototype.time = $util.Long ? $util.Long.fromBits(0, 0, false) : 0;
      StopTimeEvent.prototype.uncertainty = 0;
      StopTimeEvent.prototype.scheduledTime = $util.Long ? $util.Long.fromBits(0, 0, false) : 0;
      StopTimeEvent.create = function(properties) {
        return new StopTimeEvent(properties);
      };
      StopTimeEvent.encode = function(message, writer, _depth) {
        if (!writer)
          writer = $Writer.create();
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $util.recursionLimit)
          throw $Error("max depth exceeded");
        if (message.delay != null && $Object.hasOwnProperty.call(message, "delay"))
          writer.uint32(
            /* id 1, wireType 0 =*/
            8
          ).int32(message.delay);
        if (message.time != null && $Object.hasOwnProperty.call(message, "time"))
          writer.uint32(
            /* id 2, wireType 0 =*/
            16
          ).int64(message.time);
        if (message.uncertainty != null && $Object.hasOwnProperty.call(message, "uncertainty"))
          writer.uint32(
            /* id 3, wireType 0 =*/
            24
          ).int32(message.uncertainty);
        if (message.scheduledTime != null && $Object.hasOwnProperty.call(message, "scheduledTime"))
          writer.uint32(
            /* id 4, wireType 0 =*/
            32
          ).int64(message.scheduledTime);
        if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
          for (let i = 0; i < message.$unknowns.length; ++i)
            writer.raw(message.$unknowns[i]);
        return writer;
      };
      StopTimeEvent.encodeDelimited = function(message, writer) {
        return this.encode(message, (writer || $Writer.create()).fork()).ldelim();
      };
      StopTimeEvent.decode = function(reader, length, _end, _depth, _target) {
        if (!(reader instanceof $Reader))
          reader = $Reader.create(reader);
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $Reader.recursionLimit)
          throw $Error("max depth exceeded");
        let end, message;
        if (length === $undefined)
          end = reader.len;
        else {
          end = reader.pos + length;
          if (end > reader.len)
            throw $RangeError("index out of range");
          length = reader.len;
          reader.len = end;
        }
        message = _target || new $root.transit_realtime.TripUpdate.StopTimeEvent();
        while (reader.pos < end) {
          let start = reader.pos;
          let tag = reader.tag();
          if (tag === _end) {
            _end = $undefined;
            break;
          }
          let wireType = tag & 7;
          switch (tag >>>= 3) {
            case 1: {
              if (wireType !== 0)
                break;
              message.delay = reader.int32();
              continue;
            }
            case 2: {
              if (wireType !== 0)
                break;
              message.time = reader.int64();
              continue;
            }
            case 3: {
              if (wireType !== 0)
                break;
              message.uncertainty = reader.int32();
              continue;
            }
            case 4: {
              if (wireType !== 0)
                break;
              message.scheduledTime = reader.int64();
              continue;
            }
          }
          reader.skipType(wireType, _depth, tag);
          if (!reader.discardUnknown) {
            $util.makeProp(message, "$unknowns", false);
            (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
          }
        }
        if (length !== $undefined) {
          if (reader.pos !== end)
            throw $RangeError("index out of range");
          reader.len = length;
        }
        if (_end !== $undefined)
          throw $Error("missing end group");
        return message;
      };
      StopTimeEvent.decodeDelimited = function(reader) {
        if (!(reader instanceof $Reader))
          reader = new $Reader(reader);
        return this.decode(reader, reader.uint32());
      };
      StopTimeEvent.verify = function(message, _depth) {
        if (typeof message !== "object" || message === null)
          return "object expected";
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $util.recursionLimit)
          return "max depth exceeded";
        if (message.delay != null && $Object.hasOwnProperty.call(message, "delay")) {
          if (!$util.isInteger(message.delay))
            return "delay: integer expected";
        }
        if (message.time != null && $Object.hasOwnProperty.call(message, "time")) {
          if (!$util.isInteger(message.time) && !(message.time && $util.isInteger(message.time.low) && $util.isInteger(message.time.high)))
            return "time: integer|Long expected";
        }
        if (message.uncertainty != null && $Object.hasOwnProperty.call(message, "uncertainty")) {
          if (!$util.isInteger(message.uncertainty))
            return "uncertainty: integer expected";
        }
        if (message.scheduledTime != null && $Object.hasOwnProperty.call(message, "scheduledTime")) {
          if (!$util.isInteger(message.scheduledTime) && !(message.scheduledTime && $util.isInteger(message.scheduledTime.low) && $util.isInteger(message.scheduledTime.high)))
            return "scheduledTime: integer|Long expected";
        }
        return null;
      };
      StopTimeEvent.fromObject = function(object, _depth) {
        if (object instanceof $root.transit_realtime.TripUpdate.StopTimeEvent)
          return object;
        if (!$util.isObject(object))
          throw $TypeError(".transit_realtime.TripUpdate.StopTimeEvent: object expected");
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $util.recursionLimit)
          throw $Error("max depth exceeded");
        let message = new $root.transit_realtime.TripUpdate.StopTimeEvent();
        if (object.delay != null)
          message.delay = object.delay | 0;
        if (object.time != null) {
          if ($util.Long)
            message.time = $util.Long.fromValue(object.time, false);
          else if (typeof object.time === "string")
            message.time = $parseInt(object.time, 10);
          else if (typeof object.time === "number")
            message.time = object.time;
          else if (typeof object.time === "object")
            message.time = new $util.LongBits(object.time.low >>> 0, object.time.high >>> 0).toNumber();
        }
        if (object.uncertainty != null)
          message.uncertainty = object.uncertainty | 0;
        if (object.scheduledTime != null) {
          if ($util.Long)
            message.scheduledTime = $util.Long.fromValue(object.scheduledTime, false);
          else if (typeof object.scheduledTime === "string")
            message.scheduledTime = $parseInt(object.scheduledTime, 10);
          else if (typeof object.scheduledTime === "number")
            message.scheduledTime = object.scheduledTime;
          else if (typeof object.scheduledTime === "object")
            message.scheduledTime = new $util.LongBits(object.scheduledTime.low >>> 0, object.scheduledTime.high >>> 0).toNumber();
        }
        return message;
      };
      StopTimeEvent.toObject = function(message, options, _depth) {
        if (!options)
          options = {};
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $util.recursionLimit)
          throw $Error("max depth exceeded");
        let object = {};
        if (options.defaults) {
          object.delay = 0;
          if ($util.Long) {
            let long = new $util.Long(0, 0, false);
            object.time = options.longs === $String ? long.toString() : options.longs === $Number ? long.toNumber() : typeof $BigInt !== "undefined" && options.longs === $BigInt ? long.toBigInt() : long;
          } else
            object.time = options.longs === $String ? "0" : typeof $BigInt !== "undefined" && options.longs === $BigInt ? $BigInt("0") : 0;
          object.uncertainty = 0;
          if ($util.Long) {
            let long = new $util.Long(0, 0, false);
            object.scheduledTime = options.longs === $String ? long.toString() : options.longs === $Number ? long.toNumber() : typeof $BigInt !== "undefined" && options.longs === $BigInt ? long.toBigInt() : long;
          } else
            object.scheduledTime = options.longs === $String ? "0" : typeof $BigInt !== "undefined" && options.longs === $BigInt ? $BigInt("0") : 0;
        }
        if (message.delay != null && $Object.hasOwnProperty.call(message, "delay"))
          object.delay = message.delay;
        if (message.time != null && $Object.hasOwnProperty.call(message, "time"))
          if (typeof $BigInt !== "undefined" && options.longs === $BigInt)
            object.time = typeof message.time === "number" ? $BigInt(message.time) : $util.Long.fromBits(message.time.low >>> 0, message.time.high >>> 0, false).toBigInt();
          else if (typeof message.time === "number")
            object.time = options.longs === $String ? $String(message.time) : message.time;
          else
            object.time = options.longs === $String ? $util.Long.prototype.toString.call(message.time) : options.longs === $Number ? new $util.LongBits(message.time.low >>> 0, message.time.high >>> 0).toNumber() : message.time;
        if (message.uncertainty != null && $Object.hasOwnProperty.call(message, "uncertainty"))
          object.uncertainty = message.uncertainty;
        if (message.scheduledTime != null && $Object.hasOwnProperty.call(message, "scheduledTime"))
          if (typeof $BigInt !== "undefined" && options.longs === $BigInt)
            object.scheduledTime = typeof message.scheduledTime === "number" ? $BigInt(message.scheduledTime) : $util.Long.fromBits(message.scheduledTime.low >>> 0, message.scheduledTime.high >>> 0, false).toBigInt();
          else if (typeof message.scheduledTime === "number")
            object.scheduledTime = options.longs === $String ? $String(message.scheduledTime) : message.scheduledTime;
          else
            object.scheduledTime = options.longs === $String ? $util.Long.prototype.toString.call(message.scheduledTime) : options.longs === $Number ? new $util.LongBits(message.scheduledTime.low >>> 0, message.scheduledTime.high >>> 0).toNumber() : message.scheduledTime;
        return object;
      };
      StopTimeEvent.prototype.toJSON = function() {
        return StopTimeEvent.toObject(this, import_minimal.default.util.toJSONOptions);
      };
      StopTimeEvent.getTypeUrl = function(prefix) {
        if (prefix === $undefined)
          prefix = "type.googleapis.com";
        return prefix + "/transit_realtime.TripUpdate.StopTimeEvent";
      };
      return StopTimeEvent;
    })();
    TripUpdate.StopTimeUpdate = (function() {
      const StopTimeUpdate = /* @__PURE__ */ __name(function(properties) {
        if (properties) {
          for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
            if (properties[keys[i]] != null && keys[i] !== "__proto__")
              this[keys[i]] = properties[keys[i]];
        }
      }, "StopTimeUpdate");
      StopTimeUpdate.prototype.stopSequence = 0;
      StopTimeUpdate.prototype.stopId = "";
      StopTimeUpdate.prototype.arrival = null;
      StopTimeUpdate.prototype.departure = null;
      StopTimeUpdate.prototype.departureOccupancyStatus = 0;
      StopTimeUpdate.prototype.scheduleRelationship = 0;
      StopTimeUpdate.prototype.stopTimeProperties = null;
      StopTimeUpdate.prototype[".transit_realtime.nyctStopTimeUpdate"] = null;
      StopTimeUpdate.create = function(properties) {
        return new StopTimeUpdate(properties);
      };
      StopTimeUpdate.encode = function(message, writer, _depth) {
        if (!writer)
          writer = $Writer.create();
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $util.recursionLimit)
          throw $Error("max depth exceeded");
        if (message.stopSequence != null && $Object.hasOwnProperty.call(message, "stopSequence"))
          writer.uint32(
            /* id 1, wireType 0 =*/
            8
          ).uint32(message.stopSequence);
        if (message.arrival != null && $Object.hasOwnProperty.call(message, "arrival"))
          $root.transit_realtime.TripUpdate.StopTimeEvent.encode(message.arrival, writer.uint32(
            /* id 2, wireType 2 =*/
            18
          ).fork(), _depth + 1).ldelim();
        if (message.departure != null && $Object.hasOwnProperty.call(message, "departure"))
          $root.transit_realtime.TripUpdate.StopTimeEvent.encode(message.departure, writer.uint32(
            /* id 3, wireType 2 =*/
            26
          ).fork(), _depth + 1).ldelim();
        if (message.stopId != null && $Object.hasOwnProperty.call(message, "stopId"))
          writer.uint32(
            /* id 4, wireType 2 =*/
            34
          ).string(message.stopId);
        if (message.scheduleRelationship != null && $Object.hasOwnProperty.call(message, "scheduleRelationship"))
          writer.uint32(
            /* id 5, wireType 0 =*/
            40
          ).int32(message.scheduleRelationship);
        if (message.stopTimeProperties != null && $Object.hasOwnProperty.call(message, "stopTimeProperties"))
          $root.transit_realtime.TripUpdate.StopTimeUpdate.StopTimeProperties.encode(message.stopTimeProperties, writer.uint32(
            /* id 6, wireType 2 =*/
            50
          ).fork(), _depth + 1).ldelim();
        if (message.departureOccupancyStatus != null && $Object.hasOwnProperty.call(message, "departureOccupancyStatus"))
          writer.uint32(
            /* id 7, wireType 0 =*/
            56
          ).int32(message.departureOccupancyStatus);
        if (message[".transit_realtime.nyctStopTimeUpdate"] != null && $Object.hasOwnProperty.call(message, ".transit_realtime.nyctStopTimeUpdate"))
          $root.transit_realtime.NyctStopTimeUpdate.encode(message[".transit_realtime.nyctStopTimeUpdate"], writer.uint32(
            /* id 1001, wireType 2 =*/
            8010
          ).fork(), _depth + 1).ldelim();
        if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
          for (let i = 0; i < message.$unknowns.length; ++i)
            writer.raw(message.$unknowns[i]);
        return writer;
      };
      StopTimeUpdate.encodeDelimited = function(message, writer) {
        return this.encode(message, (writer || $Writer.create()).fork()).ldelim();
      };
      StopTimeUpdate.decode = function(reader, length, _end, _depth, _target) {
        if (!(reader instanceof $Reader))
          reader = $Reader.create(reader);
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $Reader.recursionLimit)
          throw $Error("max depth exceeded");
        let end, message, value;
        if (length === $undefined)
          end = reader.len;
        else {
          end = reader.pos + length;
          if (end > reader.len)
            throw $RangeError("index out of range");
          length = reader.len;
          reader.len = end;
        }
        message = _target || new $root.transit_realtime.TripUpdate.StopTimeUpdate();
        while (reader.pos < end) {
          let start = reader.pos;
          let tag = reader.tag();
          if (tag === _end) {
            _end = $undefined;
            break;
          }
          let wireType = tag & 7;
          switch (tag >>>= 3) {
            case 1: {
              if (wireType !== 0)
                break;
              message.stopSequence = reader.uint32();
              continue;
            }
            case 4: {
              if (wireType !== 2)
                break;
              message.stopId = reader.string();
              continue;
            }
            case 2: {
              if (wireType !== 2)
                break;
              message.arrival = $root.transit_realtime.TripUpdate.StopTimeEvent.decode(reader, reader.uint32(), $undefined, _depth + 1, message.arrival);
              continue;
            }
            case 3: {
              if (wireType !== 2)
                break;
              message.departure = $root.transit_realtime.TripUpdate.StopTimeEvent.decode(reader, reader.uint32(), $undefined, _depth + 1, message.departure);
              continue;
            }
            case 7: {
              if (wireType !== 0)
                break;
              value = reader.int32();
              if ($root.transit_realtime.VehiclePosition.OccupancyStatus[value] !== $undefined)
                message.departureOccupancyStatus = value;
              else if (!reader.discardUnknown) {
                $util.makeProp(message, "$unknowns", false);
                (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
              }
              continue;
            }
            case 5: {
              if (wireType !== 0)
                break;
              value = reader.int32();
              if ($root.transit_realtime.TripUpdate.StopTimeUpdate.ScheduleRelationship[value] !== $undefined)
                message.scheduleRelationship = value;
              else if (!reader.discardUnknown) {
                $util.makeProp(message, "$unknowns", false);
                (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
              }
              continue;
            }
            case 6: {
              if (wireType !== 2)
                break;
              message.stopTimeProperties = $root.transit_realtime.TripUpdate.StopTimeUpdate.StopTimeProperties.decode(reader, reader.uint32(), $undefined, _depth + 1, message.stopTimeProperties);
              continue;
            }
            case 1001: {
              if (wireType !== 2)
                break;
              message[".transit_realtime.nyctStopTimeUpdate"] = $root.transit_realtime.NyctStopTimeUpdate.decode(reader, reader.uint32(), $undefined, _depth + 1, message[".transit_realtime.nyctStopTimeUpdate"]);
              continue;
            }
          }
          reader.skipType(wireType, _depth, tag);
          if (!reader.discardUnknown) {
            $util.makeProp(message, "$unknowns", false);
            (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
          }
        }
        if (length !== $undefined) {
          if (reader.pos !== end)
            throw $RangeError("index out of range");
          reader.len = length;
        }
        if (_end !== $undefined)
          throw $Error("missing end group");
        return message;
      };
      StopTimeUpdate.decodeDelimited = function(reader) {
        if (!(reader instanceof $Reader))
          reader = new $Reader(reader);
        return this.decode(reader, reader.uint32());
      };
      StopTimeUpdate.verify = function(message, _depth) {
        if (typeof message !== "object" || message === null)
          return "object expected";
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $util.recursionLimit)
          return "max depth exceeded";
        if (message.stopSequence != null && $Object.hasOwnProperty.call(message, "stopSequence")) {
          if (!$util.isInteger(message.stopSequence))
            return "stopSequence: integer expected";
        }
        if (message.stopId != null && $Object.hasOwnProperty.call(message, "stopId")) {
          if (!$util.isString(message.stopId))
            return "stopId: string expected";
        }
        if (message.arrival != null && $Object.hasOwnProperty.call(message, "arrival")) {
          let error = $root.transit_realtime.TripUpdate.StopTimeEvent.verify(message.arrival, _depth + 1);
          if (error)
            return "arrival." + error;
        }
        if (message.departure != null && $Object.hasOwnProperty.call(message, "departure")) {
          let error = $root.transit_realtime.TripUpdate.StopTimeEvent.verify(message.departure, _depth + 1);
          if (error)
            return "departure." + error;
        }
        if (message.departureOccupancyStatus != null && $Object.hasOwnProperty.call(message, "departureOccupancyStatus"))
          switch (message.departureOccupancyStatus) {
            default:
              return "departureOccupancyStatus: enum value expected";
            case 0:
            case 1:
            case 2:
            case 3:
            case 4:
            case 5:
            case 6:
            case 7:
            case 8:
              break;
          }
        if (message.scheduleRelationship != null && $Object.hasOwnProperty.call(message, "scheduleRelationship"))
          switch (message.scheduleRelationship) {
            default:
              return "scheduleRelationship: enum value expected";
            case 0:
            case 1:
            case 2:
            case 3:
              break;
          }
        if (message.stopTimeProperties != null && $Object.hasOwnProperty.call(message, "stopTimeProperties")) {
          let error = $root.transit_realtime.TripUpdate.StopTimeUpdate.StopTimeProperties.verify(message.stopTimeProperties, _depth + 1);
          if (error)
            return "stopTimeProperties." + error;
        }
        if (message[".transit_realtime.nyctStopTimeUpdate"] != null && $Object.hasOwnProperty.call(message, ".transit_realtime.nyctStopTimeUpdate")) {
          let error = $root.transit_realtime.NyctStopTimeUpdate.verify(message[".transit_realtime.nyctStopTimeUpdate"], _depth + 1);
          if (error)
            return ".transit_realtime.nyctStopTimeUpdate." + error;
        }
        return null;
      };
      StopTimeUpdate.fromObject = function(object, _depth) {
        if (object instanceof $root.transit_realtime.TripUpdate.StopTimeUpdate)
          return object;
        if (!$util.isObject(object))
          throw $TypeError(".transit_realtime.TripUpdate.StopTimeUpdate: object expected");
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $util.recursionLimit)
          throw $Error("max depth exceeded");
        let message = new $root.transit_realtime.TripUpdate.StopTimeUpdate();
        if (object.stopSequence != null)
          message.stopSequence = object.stopSequence >>> 0;
        if (object.stopId != null)
          message.stopId = $String(object.stopId);
        if (object.arrival != null) {
          if (!$util.isObject(object.arrival))
            throw $TypeError(".transit_realtime.TripUpdate.StopTimeUpdate.arrival: object expected");
          message.arrival = $root.transit_realtime.TripUpdate.StopTimeEvent.fromObject(object.arrival, _depth + 1);
        }
        if (object.departure != null) {
          if (!$util.isObject(object.departure))
            throw $TypeError(".transit_realtime.TripUpdate.StopTimeUpdate.departure: object expected");
          message.departure = $root.transit_realtime.TripUpdate.StopTimeEvent.fromObject(object.departure, _depth + 1);
        }
        switch (object.departureOccupancyStatus) {
          case "EMPTY":
          case 0:
            message.departureOccupancyStatus = 0;
            break;
          case "MANY_SEATS_AVAILABLE":
          case 1:
            message.departureOccupancyStatus = 1;
            break;
          case "FEW_SEATS_AVAILABLE":
          case 2:
            message.departureOccupancyStatus = 2;
            break;
          case "STANDING_ROOM_ONLY":
          case 3:
            message.departureOccupancyStatus = 3;
            break;
          case "CRUSHED_STANDING_ROOM_ONLY":
          case 4:
            message.departureOccupancyStatus = 4;
            break;
          case "FULL":
          case 5:
            message.departureOccupancyStatus = 5;
            break;
          case "NOT_ACCEPTING_PASSENGERS":
          case 6:
            message.departureOccupancyStatus = 6;
            break;
          case "NO_DATA_AVAILABLE":
          case 7:
            message.departureOccupancyStatus = 7;
            break;
          case "NOT_BOARDABLE":
          case 8:
            message.departureOccupancyStatus = 8;
            break;
          default:
        }
        switch (object.scheduleRelationship) {
          case "SCHEDULED":
          case 0:
            message.scheduleRelationship = 0;
            break;
          case "SKIPPED":
          case 1:
            message.scheduleRelationship = 1;
            break;
          case "NO_DATA":
          case 2:
            message.scheduleRelationship = 2;
            break;
          case "UNSCHEDULED":
          case 3:
            message.scheduleRelationship = 3;
            break;
          default:
        }
        if (object.stopTimeProperties != null) {
          if (!$util.isObject(object.stopTimeProperties))
            throw $TypeError(".transit_realtime.TripUpdate.StopTimeUpdate.stopTimeProperties: object expected");
          message.stopTimeProperties = $root.transit_realtime.TripUpdate.StopTimeUpdate.StopTimeProperties.fromObject(object.stopTimeProperties, _depth + 1);
        }
        if (object[".transit_realtime.nyctStopTimeUpdate"] != null) {
          if (!$util.isObject(object[".transit_realtime.nyctStopTimeUpdate"]))
            throw $TypeError(".transit_realtime.TripUpdate.StopTimeUpdate..transit_realtime.nyctStopTimeUpdate: object expected");
          message[".transit_realtime.nyctStopTimeUpdate"] = $root.transit_realtime.NyctStopTimeUpdate.fromObject(object[".transit_realtime.nyctStopTimeUpdate"], _depth + 1);
        }
        return message;
      };
      StopTimeUpdate.toObject = function(message, options, _depth) {
        if (!options)
          options = {};
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $util.recursionLimit)
          throw $Error("max depth exceeded");
        let object = {};
        if (options.defaults) {
          object.stopSequence = 0;
          object.arrival = null;
          object.departure = null;
          object.stopId = "";
          object.scheduleRelationship = options.enums === $String ? "SCHEDULED" : 0;
          object.stopTimeProperties = null;
          object.departureOccupancyStatus = options.enums === $String ? "EMPTY" : 0;
          object[".transit_realtime.nyctStopTimeUpdate"] = null;
        }
        if (message.stopSequence != null && $Object.hasOwnProperty.call(message, "stopSequence"))
          object.stopSequence = message.stopSequence;
        if (message.arrival != null && $Object.hasOwnProperty.call(message, "arrival"))
          object.arrival = $root.transit_realtime.TripUpdate.StopTimeEvent.toObject(message.arrival, options, _depth + 1);
        if (message.departure != null && $Object.hasOwnProperty.call(message, "departure"))
          object.departure = $root.transit_realtime.TripUpdate.StopTimeEvent.toObject(message.departure, options, _depth + 1);
        if (message.stopId != null && $Object.hasOwnProperty.call(message, "stopId"))
          object.stopId = message.stopId;
        if (message.scheduleRelationship != null && $Object.hasOwnProperty.call(message, "scheduleRelationship"))
          object.scheduleRelationship = options.enums === $String ? $root.transit_realtime.TripUpdate.StopTimeUpdate.ScheduleRelationship[message.scheduleRelationship] === $undefined ? message.scheduleRelationship : $root.transit_realtime.TripUpdate.StopTimeUpdate.ScheduleRelationship[message.scheduleRelationship] : message.scheduleRelationship;
        if (message.stopTimeProperties != null && $Object.hasOwnProperty.call(message, "stopTimeProperties"))
          object.stopTimeProperties = $root.transit_realtime.TripUpdate.StopTimeUpdate.StopTimeProperties.toObject(message.stopTimeProperties, options, _depth + 1);
        if (message.departureOccupancyStatus != null && $Object.hasOwnProperty.call(message, "departureOccupancyStatus"))
          object.departureOccupancyStatus = options.enums === $String ? $root.transit_realtime.VehiclePosition.OccupancyStatus[message.departureOccupancyStatus] === $undefined ? message.departureOccupancyStatus : $root.transit_realtime.VehiclePosition.OccupancyStatus[message.departureOccupancyStatus] : message.departureOccupancyStatus;
        if (message[".transit_realtime.nyctStopTimeUpdate"] != null && $Object.hasOwnProperty.call(message, ".transit_realtime.nyctStopTimeUpdate"))
          object[".transit_realtime.nyctStopTimeUpdate"] = $root.transit_realtime.NyctStopTimeUpdate.toObject(message[".transit_realtime.nyctStopTimeUpdate"], options, _depth + 1);
        return object;
      };
      StopTimeUpdate.prototype.toJSON = function() {
        return StopTimeUpdate.toObject(this, import_minimal.default.util.toJSONOptions);
      };
      StopTimeUpdate.getTypeUrl = function(prefix) {
        if (prefix === $undefined)
          prefix = "type.googleapis.com";
        return prefix + "/transit_realtime.TripUpdate.StopTimeUpdate";
      };
      StopTimeUpdate.ScheduleRelationship = (function() {
        const valuesById = $Object.create(null), values = $Object.create(valuesById);
        values[valuesById[0] = "SCHEDULED"] = 0;
        values[valuesById[1] = "SKIPPED"] = 1;
        values[valuesById[2] = "NO_DATA"] = 2;
        values[valuesById[3] = "UNSCHEDULED"] = 3;
        return values;
      })();
      StopTimeUpdate.StopTimeProperties = (function() {
        const StopTimeProperties = /* @__PURE__ */ __name(function(properties) {
          if (properties) {
            for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
              if (properties[keys[i]] != null && keys[i] !== "__proto__")
                this[keys[i]] = properties[keys[i]];
          }
        }, "StopTimeProperties");
        StopTimeProperties.prototype.assignedStopId = "";
        StopTimeProperties.prototype.stopHeadsign = "";
        StopTimeProperties.prototype.pickupType = 0;
        StopTimeProperties.prototype.dropOffType = 0;
        StopTimeProperties.create = function(properties) {
          return new StopTimeProperties(properties);
        };
        StopTimeProperties.encode = function(message, writer, _depth) {
          if (!writer)
            writer = $Writer.create();
          if (_depth === $undefined)
            _depth = 0;
          if (_depth > $util.recursionLimit)
            throw $Error("max depth exceeded");
          if (message.assignedStopId != null && $Object.hasOwnProperty.call(message, "assignedStopId"))
            writer.uint32(
              /* id 1, wireType 2 =*/
              10
            ).string(message.assignedStopId);
          if (message.stopHeadsign != null && $Object.hasOwnProperty.call(message, "stopHeadsign"))
            writer.uint32(
              /* id 2, wireType 2 =*/
              18
            ).string(message.stopHeadsign);
          if (message.pickupType != null && $Object.hasOwnProperty.call(message, "pickupType"))
            writer.uint32(
              /* id 3, wireType 0 =*/
              24
            ).int32(message.pickupType);
          if (message.dropOffType != null && $Object.hasOwnProperty.call(message, "dropOffType"))
            writer.uint32(
              /* id 4, wireType 0 =*/
              32
            ).int32(message.dropOffType);
          if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
            for (let i = 0; i < message.$unknowns.length; ++i)
              writer.raw(message.$unknowns[i]);
          return writer;
        };
        StopTimeProperties.encodeDelimited = function(message, writer) {
          return this.encode(message, (writer || $Writer.create()).fork()).ldelim();
        };
        StopTimeProperties.decode = function(reader, length, _end, _depth, _target) {
          if (!(reader instanceof $Reader))
            reader = $Reader.create(reader);
          if (_depth === $undefined)
            _depth = 0;
          if (_depth > $Reader.recursionLimit)
            throw $Error("max depth exceeded");
          let end, message, value;
          if (length === $undefined)
            end = reader.len;
          else {
            end = reader.pos + length;
            if (end > reader.len)
              throw $RangeError("index out of range");
            length = reader.len;
            reader.len = end;
          }
          message = _target || new $root.transit_realtime.TripUpdate.StopTimeUpdate.StopTimeProperties();
          while (reader.pos < end) {
            let start = reader.pos;
            let tag = reader.tag();
            if (tag === _end) {
              _end = $undefined;
              break;
            }
            let wireType = tag & 7;
            switch (tag >>>= 3) {
              case 1: {
                if (wireType !== 2)
                  break;
                message.assignedStopId = reader.string();
                continue;
              }
              case 2: {
                if (wireType !== 2)
                  break;
                message.stopHeadsign = reader.string();
                continue;
              }
              case 3: {
                if (wireType !== 0)
                  break;
                value = reader.int32();
                if ($root.transit_realtime.TripUpdate.StopTimeUpdate.StopTimeProperties.DropOffPickupType[value] !== $undefined)
                  message.pickupType = value;
                else if (!reader.discardUnknown) {
                  $util.makeProp(message, "$unknowns", false);
                  (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
                }
                continue;
              }
              case 4: {
                if (wireType !== 0)
                  break;
                value = reader.int32();
                if ($root.transit_realtime.TripUpdate.StopTimeUpdate.StopTimeProperties.DropOffPickupType[value] !== $undefined)
                  message.dropOffType = value;
                else if (!reader.discardUnknown) {
                  $util.makeProp(message, "$unknowns", false);
                  (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
                }
                continue;
              }
            }
            reader.skipType(wireType, _depth, tag);
            if (!reader.discardUnknown) {
              $util.makeProp(message, "$unknowns", false);
              (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
            }
          }
          if (length !== $undefined) {
            if (reader.pos !== end)
              throw $RangeError("index out of range");
            reader.len = length;
          }
          if (_end !== $undefined)
            throw $Error("missing end group");
          return message;
        };
        StopTimeProperties.decodeDelimited = function(reader) {
          if (!(reader instanceof $Reader))
            reader = new $Reader(reader);
          return this.decode(reader, reader.uint32());
        };
        StopTimeProperties.verify = function(message, _depth) {
          if (typeof message !== "object" || message === null)
            return "object expected";
          if (_depth === $undefined)
            _depth = 0;
          if (_depth > $util.recursionLimit)
            return "max depth exceeded";
          if (message.assignedStopId != null && $Object.hasOwnProperty.call(message, "assignedStopId")) {
            if (!$util.isString(message.assignedStopId))
              return "assignedStopId: string expected";
          }
          if (message.stopHeadsign != null && $Object.hasOwnProperty.call(message, "stopHeadsign")) {
            if (!$util.isString(message.stopHeadsign))
              return "stopHeadsign: string expected";
          }
          if (message.pickupType != null && $Object.hasOwnProperty.call(message, "pickupType"))
            switch (message.pickupType) {
              default:
                return "pickupType: enum value expected";
              case 0:
              case 1:
              case 2:
              case 3:
                break;
            }
          if (message.dropOffType != null && $Object.hasOwnProperty.call(message, "dropOffType"))
            switch (message.dropOffType) {
              default:
                return "dropOffType: enum value expected";
              case 0:
              case 1:
              case 2:
              case 3:
                break;
            }
          return null;
        };
        StopTimeProperties.fromObject = function(object, _depth) {
          if (object instanceof $root.transit_realtime.TripUpdate.StopTimeUpdate.StopTimeProperties)
            return object;
          if (!$util.isObject(object))
            throw $TypeError(".transit_realtime.TripUpdate.StopTimeUpdate.StopTimeProperties: object expected");
          if (_depth === $undefined)
            _depth = 0;
          if (_depth > $util.recursionLimit)
            throw $Error("max depth exceeded");
          let message = new $root.transit_realtime.TripUpdate.StopTimeUpdate.StopTimeProperties();
          if (object.assignedStopId != null)
            message.assignedStopId = $String(object.assignedStopId);
          if (object.stopHeadsign != null)
            message.stopHeadsign = $String(object.stopHeadsign);
          switch (object.pickupType) {
            case "REGULAR":
            case 0:
              message.pickupType = 0;
              break;
            case "NONE":
            case 1:
              message.pickupType = 1;
              break;
            case "PHONE_AGENCY":
            case 2:
              message.pickupType = 2;
              break;
            case "COORDINATE_WITH_DRIVER":
            case 3:
              message.pickupType = 3;
              break;
            default:
          }
          switch (object.dropOffType) {
            case "REGULAR":
            case 0:
              message.dropOffType = 0;
              break;
            case "NONE":
            case 1:
              message.dropOffType = 1;
              break;
            case "PHONE_AGENCY":
            case 2:
              message.dropOffType = 2;
              break;
            case "COORDINATE_WITH_DRIVER":
            case 3:
              message.dropOffType = 3;
              break;
            default:
          }
          return message;
        };
        StopTimeProperties.toObject = function(message, options, _depth) {
          if (!options)
            options = {};
          if (_depth === $undefined)
            _depth = 0;
          if (_depth > $util.recursionLimit)
            throw $Error("max depth exceeded");
          let object = {};
          if (options.defaults) {
            object.assignedStopId = "";
            object.stopHeadsign = "";
            object.pickupType = options.enums === $String ? "REGULAR" : 0;
            object.dropOffType = options.enums === $String ? "REGULAR" : 0;
          }
          if (message.assignedStopId != null && $Object.hasOwnProperty.call(message, "assignedStopId"))
            object.assignedStopId = message.assignedStopId;
          if (message.stopHeadsign != null && $Object.hasOwnProperty.call(message, "stopHeadsign"))
            object.stopHeadsign = message.stopHeadsign;
          if (message.pickupType != null && $Object.hasOwnProperty.call(message, "pickupType"))
            object.pickupType = options.enums === $String ? $root.transit_realtime.TripUpdate.StopTimeUpdate.StopTimeProperties.DropOffPickupType[message.pickupType] === $undefined ? message.pickupType : $root.transit_realtime.TripUpdate.StopTimeUpdate.StopTimeProperties.DropOffPickupType[message.pickupType] : message.pickupType;
          if (message.dropOffType != null && $Object.hasOwnProperty.call(message, "dropOffType"))
            object.dropOffType = options.enums === $String ? $root.transit_realtime.TripUpdate.StopTimeUpdate.StopTimeProperties.DropOffPickupType[message.dropOffType] === $undefined ? message.dropOffType : $root.transit_realtime.TripUpdate.StopTimeUpdate.StopTimeProperties.DropOffPickupType[message.dropOffType] : message.dropOffType;
          return object;
        };
        StopTimeProperties.prototype.toJSON = function() {
          return StopTimeProperties.toObject(this, import_minimal.default.util.toJSONOptions);
        };
        StopTimeProperties.getTypeUrl = function(prefix) {
          if (prefix === $undefined)
            prefix = "type.googleapis.com";
          return prefix + "/transit_realtime.TripUpdate.StopTimeUpdate.StopTimeProperties";
        };
        StopTimeProperties.DropOffPickupType = (function() {
          const valuesById = $Object.create(null), values = $Object.create(valuesById);
          values[valuesById[0] = "REGULAR"] = 0;
          values[valuesById[1] = "NONE"] = 1;
          values[valuesById[2] = "PHONE_AGENCY"] = 2;
          values[valuesById[3] = "COORDINATE_WITH_DRIVER"] = 3;
          return values;
        })();
        return StopTimeProperties;
      })();
      return StopTimeUpdate;
    })();
    TripUpdate.TripProperties = (function() {
      const TripProperties = /* @__PURE__ */ __name(function(properties) {
        if (properties) {
          for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
            if (properties[keys[i]] != null && keys[i] !== "__proto__")
              this[keys[i]] = properties[keys[i]];
        }
      }, "TripProperties");
      TripProperties.prototype.tripId = "";
      TripProperties.prototype.startDate = "";
      TripProperties.prototype.startTime = "";
      TripProperties.prototype.shapeId = "";
      TripProperties.prototype.tripHeadsign = "";
      TripProperties.prototype.tripShortName = "";
      TripProperties.create = function(properties) {
        return new TripProperties(properties);
      };
      TripProperties.encode = function(message, writer, _depth) {
        if (!writer)
          writer = $Writer.create();
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $util.recursionLimit)
          throw $Error("max depth exceeded");
        if (message.tripId != null && $Object.hasOwnProperty.call(message, "tripId"))
          writer.uint32(
            /* id 1, wireType 2 =*/
            10
          ).string(message.tripId);
        if (message.startDate != null && $Object.hasOwnProperty.call(message, "startDate"))
          writer.uint32(
            /* id 2, wireType 2 =*/
            18
          ).string(message.startDate);
        if (message.startTime != null && $Object.hasOwnProperty.call(message, "startTime"))
          writer.uint32(
            /* id 3, wireType 2 =*/
            26
          ).string(message.startTime);
        if (message.shapeId != null && $Object.hasOwnProperty.call(message, "shapeId"))
          writer.uint32(
            /* id 4, wireType 2 =*/
            34
          ).string(message.shapeId);
        if (message.tripHeadsign != null && $Object.hasOwnProperty.call(message, "tripHeadsign"))
          writer.uint32(
            /* id 5, wireType 2 =*/
            42
          ).string(message.tripHeadsign);
        if (message.tripShortName != null && $Object.hasOwnProperty.call(message, "tripShortName"))
          writer.uint32(
            /* id 6, wireType 2 =*/
            50
          ).string(message.tripShortName);
        if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
          for (let i = 0; i < message.$unknowns.length; ++i)
            writer.raw(message.$unknowns[i]);
        return writer;
      };
      TripProperties.encodeDelimited = function(message, writer) {
        return this.encode(message, (writer || $Writer.create()).fork()).ldelim();
      };
      TripProperties.decode = function(reader, length, _end, _depth, _target) {
        if (!(reader instanceof $Reader))
          reader = $Reader.create(reader);
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $Reader.recursionLimit)
          throw $Error("max depth exceeded");
        let end, message;
        if (length === $undefined)
          end = reader.len;
        else {
          end = reader.pos + length;
          if (end > reader.len)
            throw $RangeError("index out of range");
          length = reader.len;
          reader.len = end;
        }
        message = _target || new $root.transit_realtime.TripUpdate.TripProperties();
        while (reader.pos < end) {
          let start = reader.pos;
          let tag = reader.tag();
          if (tag === _end) {
            _end = $undefined;
            break;
          }
          let wireType = tag & 7;
          switch (tag >>>= 3) {
            case 1: {
              if (wireType !== 2)
                break;
              message.tripId = reader.string();
              continue;
            }
            case 2: {
              if (wireType !== 2)
                break;
              message.startDate = reader.string();
              continue;
            }
            case 3: {
              if (wireType !== 2)
                break;
              message.startTime = reader.string();
              continue;
            }
            case 4: {
              if (wireType !== 2)
                break;
              message.shapeId = reader.string();
              continue;
            }
            case 5: {
              if (wireType !== 2)
                break;
              message.tripHeadsign = reader.string();
              continue;
            }
            case 6: {
              if (wireType !== 2)
                break;
              message.tripShortName = reader.string();
              continue;
            }
          }
          reader.skipType(wireType, _depth, tag);
          if (!reader.discardUnknown) {
            $util.makeProp(message, "$unknowns", false);
            (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
          }
        }
        if (length !== $undefined) {
          if (reader.pos !== end)
            throw $RangeError("index out of range");
          reader.len = length;
        }
        if (_end !== $undefined)
          throw $Error("missing end group");
        return message;
      };
      TripProperties.decodeDelimited = function(reader) {
        if (!(reader instanceof $Reader))
          reader = new $Reader(reader);
        return this.decode(reader, reader.uint32());
      };
      TripProperties.verify = function(message, _depth) {
        if (typeof message !== "object" || message === null)
          return "object expected";
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $util.recursionLimit)
          return "max depth exceeded";
        if (message.tripId != null && $Object.hasOwnProperty.call(message, "tripId")) {
          if (!$util.isString(message.tripId))
            return "tripId: string expected";
        }
        if (message.startDate != null && $Object.hasOwnProperty.call(message, "startDate")) {
          if (!$util.isString(message.startDate))
            return "startDate: string expected";
        }
        if (message.startTime != null && $Object.hasOwnProperty.call(message, "startTime")) {
          if (!$util.isString(message.startTime))
            return "startTime: string expected";
        }
        if (message.shapeId != null && $Object.hasOwnProperty.call(message, "shapeId")) {
          if (!$util.isString(message.shapeId))
            return "shapeId: string expected";
        }
        if (message.tripHeadsign != null && $Object.hasOwnProperty.call(message, "tripHeadsign")) {
          if (!$util.isString(message.tripHeadsign))
            return "tripHeadsign: string expected";
        }
        if (message.tripShortName != null && $Object.hasOwnProperty.call(message, "tripShortName")) {
          if (!$util.isString(message.tripShortName))
            return "tripShortName: string expected";
        }
        return null;
      };
      TripProperties.fromObject = function(object, _depth) {
        if (object instanceof $root.transit_realtime.TripUpdate.TripProperties)
          return object;
        if (!$util.isObject(object))
          throw $TypeError(".transit_realtime.TripUpdate.TripProperties: object expected");
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $util.recursionLimit)
          throw $Error("max depth exceeded");
        let message = new $root.transit_realtime.TripUpdate.TripProperties();
        if (object.tripId != null)
          message.tripId = $String(object.tripId);
        if (object.startDate != null)
          message.startDate = $String(object.startDate);
        if (object.startTime != null)
          message.startTime = $String(object.startTime);
        if (object.shapeId != null)
          message.shapeId = $String(object.shapeId);
        if (object.tripHeadsign != null)
          message.tripHeadsign = $String(object.tripHeadsign);
        if (object.tripShortName != null)
          message.tripShortName = $String(object.tripShortName);
        return message;
      };
      TripProperties.toObject = function(message, options, _depth) {
        if (!options)
          options = {};
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $util.recursionLimit)
          throw $Error("max depth exceeded");
        let object = {};
        if (options.defaults) {
          object.tripId = "";
          object.startDate = "";
          object.startTime = "";
          object.shapeId = "";
          object.tripHeadsign = "";
          object.tripShortName = "";
        }
        if (message.tripId != null && $Object.hasOwnProperty.call(message, "tripId"))
          object.tripId = message.tripId;
        if (message.startDate != null && $Object.hasOwnProperty.call(message, "startDate"))
          object.startDate = message.startDate;
        if (message.startTime != null && $Object.hasOwnProperty.call(message, "startTime"))
          object.startTime = message.startTime;
        if (message.shapeId != null && $Object.hasOwnProperty.call(message, "shapeId"))
          object.shapeId = message.shapeId;
        if (message.tripHeadsign != null && $Object.hasOwnProperty.call(message, "tripHeadsign"))
          object.tripHeadsign = message.tripHeadsign;
        if (message.tripShortName != null && $Object.hasOwnProperty.call(message, "tripShortName"))
          object.tripShortName = message.tripShortName;
        return object;
      };
      TripProperties.prototype.toJSON = function() {
        return TripProperties.toObject(this, import_minimal.default.util.toJSONOptions);
      };
      TripProperties.getTypeUrl = function(prefix) {
        if (prefix === $undefined)
          prefix = "type.googleapis.com";
        return prefix + "/transit_realtime.TripUpdate.TripProperties";
      };
      return TripProperties;
    })();
    return TripUpdate;
  })();
  transit_realtime2.VehiclePosition = (function() {
    const VehiclePosition = /* @__PURE__ */ __name(function(properties) {
      this.multiCarriageDetails = [];
      if (properties) {
        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
          if (properties[keys[i]] != null && keys[i] !== "__proto__")
            this[keys[i]] = properties[keys[i]];
      }
    }, "VehiclePosition");
    VehiclePosition.prototype.trip = null;
    VehiclePosition.prototype.vehicle = null;
    VehiclePosition.prototype.position = null;
    VehiclePosition.prototype.currentStopSequence = 0;
    VehiclePosition.prototype.stopId = "";
    VehiclePosition.prototype.currentStatus = 2;
    VehiclePosition.prototype.timestamp = $util.Long ? $util.Long.fromBits(0, 0, true) : 0;
    VehiclePosition.prototype.congestionLevel = 0;
    VehiclePosition.prototype.occupancyStatus = 0;
    VehiclePosition.prototype.occupancyPercentage = 0;
    VehiclePosition.prototype.multiCarriageDetails = $util.emptyArray;
    VehiclePosition.create = function(properties) {
      return new VehiclePosition(properties);
    };
    VehiclePosition.encode = function(message, writer, _depth) {
      if (!writer)
        writer = $Writer.create();
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      if (message.trip != null && $Object.hasOwnProperty.call(message, "trip"))
        $root.transit_realtime.TripDescriptor.encode(message.trip, writer.uint32(
          /* id 1, wireType 2 =*/
          10
        ).fork(), _depth + 1).ldelim();
      if (message.position != null && $Object.hasOwnProperty.call(message, "position"))
        $root.transit_realtime.Position.encode(message.position, writer.uint32(
          /* id 2, wireType 2 =*/
          18
        ).fork(), _depth + 1).ldelim();
      if (message.currentStopSequence != null && $Object.hasOwnProperty.call(message, "currentStopSequence"))
        writer.uint32(
          /* id 3, wireType 0 =*/
          24
        ).uint32(message.currentStopSequence);
      if (message.currentStatus != null && $Object.hasOwnProperty.call(message, "currentStatus"))
        writer.uint32(
          /* id 4, wireType 0 =*/
          32
        ).int32(message.currentStatus);
      if (message.timestamp != null && $Object.hasOwnProperty.call(message, "timestamp"))
        writer.uint32(
          /* id 5, wireType 0 =*/
          40
        ).uint64(message.timestamp);
      if (message.congestionLevel != null && $Object.hasOwnProperty.call(message, "congestionLevel"))
        writer.uint32(
          /* id 6, wireType 0 =*/
          48
        ).int32(message.congestionLevel);
      if (message.stopId != null && $Object.hasOwnProperty.call(message, "stopId"))
        writer.uint32(
          /* id 7, wireType 2 =*/
          58
        ).string(message.stopId);
      if (message.vehicle != null && $Object.hasOwnProperty.call(message, "vehicle"))
        $root.transit_realtime.VehicleDescriptor.encode(message.vehicle, writer.uint32(
          /* id 8, wireType 2 =*/
          66
        ).fork(), _depth + 1).ldelim();
      if (message.occupancyStatus != null && $Object.hasOwnProperty.call(message, "occupancyStatus"))
        writer.uint32(
          /* id 9, wireType 0 =*/
          72
        ).int32(message.occupancyStatus);
      if (message.occupancyPercentage != null && $Object.hasOwnProperty.call(message, "occupancyPercentage"))
        writer.uint32(
          /* id 10, wireType 0 =*/
          80
        ).uint32(message.occupancyPercentage);
      if (message.multiCarriageDetails != null && message.multiCarriageDetails.length)
        for (let i = 0; i < message.multiCarriageDetails.length; ++i)
          $root.transit_realtime.VehiclePosition.CarriageDetails.encode(message.multiCarriageDetails[i], writer.uint32(
            /* id 11, wireType 2 =*/
            90
          ).fork(), _depth + 1).ldelim();
      if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
        for (let i = 0; i < message.$unknowns.length; ++i)
          writer.raw(message.$unknowns[i]);
      return writer;
    };
    VehiclePosition.encodeDelimited = function(message, writer) {
      return this.encode(message, (writer || $Writer.create()).fork()).ldelim();
    };
    VehiclePosition.decode = function(reader, length, _end, _depth, _target) {
      if (!(reader instanceof $Reader))
        reader = $Reader.create(reader);
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $Reader.recursionLimit)
        throw $Error("max depth exceeded");
      let end, message, value;
      if (length === $undefined)
        end = reader.len;
      else {
        end = reader.pos + length;
        if (end > reader.len)
          throw $RangeError("index out of range");
        length = reader.len;
        reader.len = end;
      }
      message = _target || new $root.transit_realtime.VehiclePosition();
      while (reader.pos < end) {
        let start = reader.pos;
        let tag = reader.tag();
        if (tag === _end) {
          _end = $undefined;
          break;
        }
        let wireType = tag & 7;
        switch (tag >>>= 3) {
          case 1: {
            if (wireType !== 2)
              break;
            message.trip = $root.transit_realtime.TripDescriptor.decode(reader, reader.uint32(), $undefined, _depth + 1, message.trip);
            continue;
          }
          case 8: {
            if (wireType !== 2)
              break;
            message.vehicle = $root.transit_realtime.VehicleDescriptor.decode(reader, reader.uint32(), $undefined, _depth + 1, message.vehicle);
            continue;
          }
          case 2: {
            if (wireType !== 2)
              break;
            message.position = $root.transit_realtime.Position.decode(reader, reader.uint32(), $undefined, _depth + 1, message.position);
            continue;
          }
          case 3: {
            if (wireType !== 0)
              break;
            message.currentStopSequence = reader.uint32();
            continue;
          }
          case 7: {
            if (wireType !== 2)
              break;
            message.stopId = reader.string();
            continue;
          }
          case 4: {
            if (wireType !== 0)
              break;
            value = reader.int32();
            if ($root.transit_realtime.VehiclePosition.VehicleStopStatus[value] !== $undefined)
              message.currentStatus = value;
            else if (!reader.discardUnknown) {
              $util.makeProp(message, "$unknowns", false);
              (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
            }
            continue;
          }
          case 5: {
            if (wireType !== 0)
              break;
            message.timestamp = reader.uint64();
            continue;
          }
          case 6: {
            if (wireType !== 0)
              break;
            value = reader.int32();
            if ($root.transit_realtime.VehiclePosition.CongestionLevel[value] !== $undefined)
              message.congestionLevel = value;
            else if (!reader.discardUnknown) {
              $util.makeProp(message, "$unknowns", false);
              (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
            }
            continue;
          }
          case 9: {
            if (wireType !== 0)
              break;
            value = reader.int32();
            if ($root.transit_realtime.VehiclePosition.OccupancyStatus[value] !== $undefined)
              message.occupancyStatus = value;
            else if (!reader.discardUnknown) {
              $util.makeProp(message, "$unknowns", false);
              (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
            }
            continue;
          }
          case 10: {
            if (wireType !== 0)
              break;
            message.occupancyPercentage = reader.uint32();
            continue;
          }
          case 11: {
            if (wireType !== 2)
              break;
            if (!(message.multiCarriageDetails && message.multiCarriageDetails.length))
              message.multiCarriageDetails = [];
            message.multiCarriageDetails.push($root.transit_realtime.VehiclePosition.CarriageDetails.decode(reader, reader.uint32(), $undefined, _depth + 1));
            continue;
          }
        }
        reader.skipType(wireType, _depth, tag);
        if (!reader.discardUnknown) {
          $util.makeProp(message, "$unknowns", false);
          (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
        }
      }
      if (length !== $undefined) {
        if (reader.pos !== end)
          throw $RangeError("index out of range");
        reader.len = length;
      }
      if (_end !== $undefined)
        throw $Error("missing end group");
      return message;
    };
    VehiclePosition.decodeDelimited = function(reader) {
      if (!(reader instanceof $Reader))
        reader = new $Reader(reader);
      return this.decode(reader, reader.uint32());
    };
    VehiclePosition.verify = function(message, _depth) {
      if (typeof message !== "object" || message === null)
        return "object expected";
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        return "max depth exceeded";
      if (message.trip != null && $Object.hasOwnProperty.call(message, "trip")) {
        let error = $root.transit_realtime.TripDescriptor.verify(message.trip, _depth + 1);
        if (error)
          return "trip." + error;
      }
      if (message.vehicle != null && $Object.hasOwnProperty.call(message, "vehicle")) {
        let error = $root.transit_realtime.VehicleDescriptor.verify(message.vehicle, _depth + 1);
        if (error)
          return "vehicle." + error;
      }
      if (message.position != null && $Object.hasOwnProperty.call(message, "position")) {
        let error = $root.transit_realtime.Position.verify(message.position, _depth + 1);
        if (error)
          return "position." + error;
      }
      if (message.currentStopSequence != null && $Object.hasOwnProperty.call(message, "currentStopSequence")) {
        if (!$util.isInteger(message.currentStopSequence))
          return "currentStopSequence: integer expected";
      }
      if (message.stopId != null && $Object.hasOwnProperty.call(message, "stopId")) {
        if (!$util.isString(message.stopId))
          return "stopId: string expected";
      }
      if (message.currentStatus != null && $Object.hasOwnProperty.call(message, "currentStatus"))
        switch (message.currentStatus) {
          default:
            return "currentStatus: enum value expected";
          case 0:
          case 1:
          case 2:
            break;
        }
      if (message.timestamp != null && $Object.hasOwnProperty.call(message, "timestamp")) {
        if (!$util.isInteger(message.timestamp) && !(message.timestamp && $util.isInteger(message.timestamp.low) && $util.isInteger(message.timestamp.high)))
          return "timestamp: integer|Long expected";
      }
      if (message.congestionLevel != null && $Object.hasOwnProperty.call(message, "congestionLevel"))
        switch (message.congestionLevel) {
          default:
            return "congestionLevel: enum value expected";
          case 0:
          case 1:
          case 2:
          case 3:
          case 4:
            break;
        }
      if (message.occupancyStatus != null && $Object.hasOwnProperty.call(message, "occupancyStatus"))
        switch (message.occupancyStatus) {
          default:
            return "occupancyStatus: enum value expected";
          case 0:
          case 1:
          case 2:
          case 3:
          case 4:
          case 5:
          case 6:
          case 7:
          case 8:
            break;
        }
      if (message.occupancyPercentage != null && $Object.hasOwnProperty.call(message, "occupancyPercentage")) {
        if (!$util.isInteger(message.occupancyPercentage))
          return "occupancyPercentage: integer expected";
      }
      if (message.multiCarriageDetails != null && $Object.hasOwnProperty.call(message, "multiCarriageDetails")) {
        if (!$Array.isArray(message.multiCarriageDetails))
          return "multiCarriageDetails: array expected";
        for (let i = 0; i < message.multiCarriageDetails.length; ++i) {
          let error = $root.transit_realtime.VehiclePosition.CarriageDetails.verify(message.multiCarriageDetails[i], _depth + 1);
          if (error)
            return "multiCarriageDetails." + error;
        }
      }
      return null;
    };
    VehiclePosition.fromObject = function(object, _depth) {
      if (object instanceof $root.transit_realtime.VehiclePosition)
        return object;
      if (!$util.isObject(object))
        throw $TypeError(".transit_realtime.VehiclePosition: object expected");
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let message = new $root.transit_realtime.VehiclePosition();
      if (object.trip != null) {
        if (!$util.isObject(object.trip))
          throw $TypeError(".transit_realtime.VehiclePosition.trip: object expected");
        message.trip = $root.transit_realtime.TripDescriptor.fromObject(object.trip, _depth + 1);
      }
      if (object.vehicle != null) {
        if (!$util.isObject(object.vehicle))
          throw $TypeError(".transit_realtime.VehiclePosition.vehicle: object expected");
        message.vehicle = $root.transit_realtime.VehicleDescriptor.fromObject(object.vehicle, _depth + 1);
      }
      if (object.position != null) {
        if (!$util.isObject(object.position))
          throw $TypeError(".transit_realtime.VehiclePosition.position: object expected");
        message.position = $root.transit_realtime.Position.fromObject(object.position, _depth + 1);
      }
      if (object.currentStopSequence != null)
        message.currentStopSequence = object.currentStopSequence >>> 0;
      if (object.stopId != null)
        message.stopId = $String(object.stopId);
      switch (object.currentStatus) {
        case "INCOMING_AT":
        case 0:
          message.currentStatus = 0;
          break;
        case "STOPPED_AT":
        case 1:
          message.currentStatus = 1;
          break;
        case "IN_TRANSIT_TO":
        case 2:
          message.currentStatus = 2;
          break;
        default:
      }
      if (object.timestamp != null) {
        if ($util.Long)
          message.timestamp = $util.Long.fromValue(object.timestamp, true);
        else if (typeof object.timestamp === "string")
          message.timestamp = $parseInt(object.timestamp, 10);
        else if (typeof object.timestamp === "number")
          message.timestamp = object.timestamp;
        else if (typeof object.timestamp === "object")
          message.timestamp = new $util.LongBits(object.timestamp.low >>> 0, object.timestamp.high >>> 0).toNumber(true);
      }
      switch (object.congestionLevel) {
        case "UNKNOWN_CONGESTION_LEVEL":
        case 0:
          message.congestionLevel = 0;
          break;
        case "RUNNING_SMOOTHLY":
        case 1:
          message.congestionLevel = 1;
          break;
        case "STOP_AND_GO":
        case 2:
          message.congestionLevel = 2;
          break;
        case "CONGESTION":
        case 3:
          message.congestionLevel = 3;
          break;
        case "SEVERE_CONGESTION":
        case 4:
          message.congestionLevel = 4;
          break;
        default:
      }
      switch (object.occupancyStatus) {
        case "EMPTY":
        case 0:
          message.occupancyStatus = 0;
          break;
        case "MANY_SEATS_AVAILABLE":
        case 1:
          message.occupancyStatus = 1;
          break;
        case "FEW_SEATS_AVAILABLE":
        case 2:
          message.occupancyStatus = 2;
          break;
        case "STANDING_ROOM_ONLY":
        case 3:
          message.occupancyStatus = 3;
          break;
        case "CRUSHED_STANDING_ROOM_ONLY":
        case 4:
          message.occupancyStatus = 4;
          break;
        case "FULL":
        case 5:
          message.occupancyStatus = 5;
          break;
        case "NOT_ACCEPTING_PASSENGERS":
        case 6:
          message.occupancyStatus = 6;
          break;
        case "NO_DATA_AVAILABLE":
        case 7:
          message.occupancyStatus = 7;
          break;
        case "NOT_BOARDABLE":
        case 8:
          message.occupancyStatus = 8;
          break;
        default:
      }
      if (object.occupancyPercentage != null)
        message.occupancyPercentage = object.occupancyPercentage >>> 0;
      if (object.multiCarriageDetails) {
        if (!$Array.isArray(object.multiCarriageDetails))
          throw $TypeError(".transit_realtime.VehiclePosition.multiCarriageDetails: array expected");
        message.multiCarriageDetails = $Array(object.multiCarriageDetails.length);
        for (let i = 0; i < object.multiCarriageDetails.length; ++i) {
          if (!$util.isObject(object.multiCarriageDetails[i]))
            throw $TypeError(".transit_realtime.VehiclePosition.multiCarriageDetails: object expected");
          message.multiCarriageDetails[i] = $root.transit_realtime.VehiclePosition.CarriageDetails.fromObject(object.multiCarriageDetails[i], _depth + 1);
        }
      }
      return message;
    };
    VehiclePosition.toObject = function(message, options, _depth) {
      if (!options)
        options = {};
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let object = {};
      if (options.arrays || options.defaults)
        object.multiCarriageDetails = [];
      if (options.defaults) {
        object.trip = null;
        object.position = null;
        object.currentStopSequence = 0;
        object.currentStatus = options.enums === $String ? "IN_TRANSIT_TO" : 2;
        if ($util.Long) {
          let long = new $util.Long(0, 0, true);
          object.timestamp = options.longs === $String ? long.toString() : options.longs === $Number ? long.toNumber() : typeof $BigInt !== "undefined" && options.longs === $BigInt ? long.toBigInt() : long;
        } else
          object.timestamp = options.longs === $String ? "0" : typeof $BigInt !== "undefined" && options.longs === $BigInt ? $BigInt("0") : 0;
        object.congestionLevel = options.enums === $String ? "UNKNOWN_CONGESTION_LEVEL" : 0;
        object.stopId = "";
        object.vehicle = null;
        object.occupancyStatus = options.enums === $String ? "EMPTY" : 0;
        object.occupancyPercentage = 0;
      }
      if (message.trip != null && $Object.hasOwnProperty.call(message, "trip"))
        object.trip = $root.transit_realtime.TripDescriptor.toObject(message.trip, options, _depth + 1);
      if (message.position != null && $Object.hasOwnProperty.call(message, "position"))
        object.position = $root.transit_realtime.Position.toObject(message.position, options, _depth + 1);
      if (message.currentStopSequence != null && $Object.hasOwnProperty.call(message, "currentStopSequence"))
        object.currentStopSequence = message.currentStopSequence;
      if (message.currentStatus != null && $Object.hasOwnProperty.call(message, "currentStatus"))
        object.currentStatus = options.enums === $String ? $root.transit_realtime.VehiclePosition.VehicleStopStatus[message.currentStatus] === $undefined ? message.currentStatus : $root.transit_realtime.VehiclePosition.VehicleStopStatus[message.currentStatus] : message.currentStatus;
      if (message.timestamp != null && $Object.hasOwnProperty.call(message, "timestamp"))
        if (typeof $BigInt !== "undefined" && options.longs === $BigInt)
          object.timestamp = typeof message.timestamp === "number" ? $BigInt(message.timestamp) : $util.Long.fromBits(message.timestamp.low >>> 0, message.timestamp.high >>> 0, true).toBigInt();
        else if (typeof message.timestamp === "number")
          object.timestamp = options.longs === $String ? $String(message.timestamp) : message.timestamp;
        else
          object.timestamp = options.longs === $String ? $util.Long.prototype.toString.call(message.timestamp) : options.longs === $Number ? new $util.LongBits(message.timestamp.low >>> 0, message.timestamp.high >>> 0).toNumber(true) : message.timestamp;
      if (message.congestionLevel != null && $Object.hasOwnProperty.call(message, "congestionLevel"))
        object.congestionLevel = options.enums === $String ? $root.transit_realtime.VehiclePosition.CongestionLevel[message.congestionLevel] === $undefined ? message.congestionLevel : $root.transit_realtime.VehiclePosition.CongestionLevel[message.congestionLevel] : message.congestionLevel;
      if (message.stopId != null && $Object.hasOwnProperty.call(message, "stopId"))
        object.stopId = message.stopId;
      if (message.vehicle != null && $Object.hasOwnProperty.call(message, "vehicle"))
        object.vehicle = $root.transit_realtime.VehicleDescriptor.toObject(message.vehicle, options, _depth + 1);
      if (message.occupancyStatus != null && $Object.hasOwnProperty.call(message, "occupancyStatus"))
        object.occupancyStatus = options.enums === $String ? $root.transit_realtime.VehiclePosition.OccupancyStatus[message.occupancyStatus] === $undefined ? message.occupancyStatus : $root.transit_realtime.VehiclePosition.OccupancyStatus[message.occupancyStatus] : message.occupancyStatus;
      if (message.occupancyPercentage != null && $Object.hasOwnProperty.call(message, "occupancyPercentage"))
        object.occupancyPercentage = message.occupancyPercentage;
      if (message.multiCarriageDetails && message.multiCarriageDetails.length) {
        object.multiCarriageDetails = $Array(message.multiCarriageDetails.length);
        for (let j = 0; j < message.multiCarriageDetails.length; ++j)
          object.multiCarriageDetails[j] = $root.transit_realtime.VehiclePosition.CarriageDetails.toObject(message.multiCarriageDetails[j], options, _depth + 1);
      }
      return object;
    };
    VehiclePosition.prototype.toJSON = function() {
      return VehiclePosition.toObject(this, import_minimal.default.util.toJSONOptions);
    };
    VehiclePosition.getTypeUrl = function(prefix) {
      if (prefix === $undefined)
        prefix = "type.googleapis.com";
      return prefix + "/transit_realtime.VehiclePosition";
    };
    VehiclePosition.VehicleStopStatus = (function() {
      const valuesById = $Object.create(null), values = $Object.create(valuesById);
      values[valuesById[0] = "INCOMING_AT"] = 0;
      values[valuesById[1] = "STOPPED_AT"] = 1;
      values[valuesById[2] = "IN_TRANSIT_TO"] = 2;
      return values;
    })();
    VehiclePosition.CongestionLevel = (function() {
      const valuesById = $Object.create(null), values = $Object.create(valuesById);
      values[valuesById[0] = "UNKNOWN_CONGESTION_LEVEL"] = 0;
      values[valuesById[1] = "RUNNING_SMOOTHLY"] = 1;
      values[valuesById[2] = "STOP_AND_GO"] = 2;
      values[valuesById[3] = "CONGESTION"] = 3;
      values[valuesById[4] = "SEVERE_CONGESTION"] = 4;
      return values;
    })();
    VehiclePosition.OccupancyStatus = (function() {
      const valuesById = $Object.create(null), values = $Object.create(valuesById);
      values[valuesById[0] = "EMPTY"] = 0;
      values[valuesById[1] = "MANY_SEATS_AVAILABLE"] = 1;
      values[valuesById[2] = "FEW_SEATS_AVAILABLE"] = 2;
      values[valuesById[3] = "STANDING_ROOM_ONLY"] = 3;
      values[valuesById[4] = "CRUSHED_STANDING_ROOM_ONLY"] = 4;
      values[valuesById[5] = "FULL"] = 5;
      values[valuesById[6] = "NOT_ACCEPTING_PASSENGERS"] = 6;
      values[valuesById[7] = "NO_DATA_AVAILABLE"] = 7;
      values[valuesById[8] = "NOT_BOARDABLE"] = 8;
      return values;
    })();
    VehiclePosition.CarriageDetails = (function() {
      const CarriageDetails = /* @__PURE__ */ __name(function(properties) {
        if (properties) {
          for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
            if (properties[keys[i]] != null && keys[i] !== "__proto__")
              this[keys[i]] = properties[keys[i]];
        }
      }, "CarriageDetails");
      CarriageDetails.prototype.id = "";
      CarriageDetails.prototype.label = "";
      CarriageDetails.prototype.occupancyStatus = 7;
      CarriageDetails.prototype.occupancyPercentage = -1;
      CarriageDetails.prototype.carriageSequence = 0;
      CarriageDetails.create = function(properties) {
        return new CarriageDetails(properties);
      };
      CarriageDetails.encode = function(message, writer, _depth) {
        if (!writer)
          writer = $Writer.create();
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $util.recursionLimit)
          throw $Error("max depth exceeded");
        if (message.id != null && $Object.hasOwnProperty.call(message, "id"))
          writer.uint32(
            /* id 1, wireType 2 =*/
            10
          ).string(message.id);
        if (message.label != null && $Object.hasOwnProperty.call(message, "label"))
          writer.uint32(
            /* id 2, wireType 2 =*/
            18
          ).string(message.label);
        if (message.occupancyStatus != null && $Object.hasOwnProperty.call(message, "occupancyStatus"))
          writer.uint32(
            /* id 3, wireType 0 =*/
            24
          ).int32(message.occupancyStatus);
        if (message.occupancyPercentage != null && $Object.hasOwnProperty.call(message, "occupancyPercentage"))
          writer.uint32(
            /* id 4, wireType 0 =*/
            32
          ).int32(message.occupancyPercentage);
        if (message.carriageSequence != null && $Object.hasOwnProperty.call(message, "carriageSequence"))
          writer.uint32(
            /* id 5, wireType 0 =*/
            40
          ).uint32(message.carriageSequence);
        if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
          for (let i = 0; i < message.$unknowns.length; ++i)
            writer.raw(message.$unknowns[i]);
        return writer;
      };
      CarriageDetails.encodeDelimited = function(message, writer) {
        return this.encode(message, (writer || $Writer.create()).fork()).ldelim();
      };
      CarriageDetails.decode = function(reader, length, _end, _depth, _target) {
        if (!(reader instanceof $Reader))
          reader = $Reader.create(reader);
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $Reader.recursionLimit)
          throw $Error("max depth exceeded");
        let end, message, value;
        if (length === $undefined)
          end = reader.len;
        else {
          end = reader.pos + length;
          if (end > reader.len)
            throw $RangeError("index out of range");
          length = reader.len;
          reader.len = end;
        }
        message = _target || new $root.transit_realtime.VehiclePosition.CarriageDetails();
        while (reader.pos < end) {
          let start = reader.pos;
          let tag = reader.tag();
          if (tag === _end) {
            _end = $undefined;
            break;
          }
          let wireType = tag & 7;
          switch (tag >>>= 3) {
            case 1: {
              if (wireType !== 2)
                break;
              message.id = reader.string();
              continue;
            }
            case 2: {
              if (wireType !== 2)
                break;
              message.label = reader.string();
              continue;
            }
            case 3: {
              if (wireType !== 0)
                break;
              value = reader.int32();
              if ($root.transit_realtime.VehiclePosition.OccupancyStatus[value] !== $undefined)
                message.occupancyStatus = value;
              else if (!reader.discardUnknown) {
                $util.makeProp(message, "$unknowns", false);
                (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
              }
              continue;
            }
            case 4: {
              if (wireType !== 0)
                break;
              message.occupancyPercentage = reader.int32();
              continue;
            }
            case 5: {
              if (wireType !== 0)
                break;
              message.carriageSequence = reader.uint32();
              continue;
            }
          }
          reader.skipType(wireType, _depth, tag);
          if (!reader.discardUnknown) {
            $util.makeProp(message, "$unknowns", false);
            (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
          }
        }
        if (length !== $undefined) {
          if (reader.pos !== end)
            throw $RangeError("index out of range");
          reader.len = length;
        }
        if (_end !== $undefined)
          throw $Error("missing end group");
        return message;
      };
      CarriageDetails.decodeDelimited = function(reader) {
        if (!(reader instanceof $Reader))
          reader = new $Reader(reader);
        return this.decode(reader, reader.uint32());
      };
      CarriageDetails.verify = function(message, _depth) {
        if (typeof message !== "object" || message === null)
          return "object expected";
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $util.recursionLimit)
          return "max depth exceeded";
        if (message.id != null && $Object.hasOwnProperty.call(message, "id")) {
          if (!$util.isString(message.id))
            return "id: string expected";
        }
        if (message.label != null && $Object.hasOwnProperty.call(message, "label")) {
          if (!$util.isString(message.label))
            return "label: string expected";
        }
        if (message.occupancyStatus != null && $Object.hasOwnProperty.call(message, "occupancyStatus"))
          switch (message.occupancyStatus) {
            default:
              return "occupancyStatus: enum value expected";
            case 0:
            case 1:
            case 2:
            case 3:
            case 4:
            case 5:
            case 6:
            case 7:
            case 8:
              break;
          }
        if (message.occupancyPercentage != null && $Object.hasOwnProperty.call(message, "occupancyPercentage")) {
          if (!$util.isInteger(message.occupancyPercentage))
            return "occupancyPercentage: integer expected";
        }
        if (message.carriageSequence != null && $Object.hasOwnProperty.call(message, "carriageSequence")) {
          if (!$util.isInteger(message.carriageSequence))
            return "carriageSequence: integer expected";
        }
        return null;
      };
      CarriageDetails.fromObject = function(object, _depth) {
        if (object instanceof $root.transit_realtime.VehiclePosition.CarriageDetails)
          return object;
        if (!$util.isObject(object))
          throw $TypeError(".transit_realtime.VehiclePosition.CarriageDetails: object expected");
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $util.recursionLimit)
          throw $Error("max depth exceeded");
        let message = new $root.transit_realtime.VehiclePosition.CarriageDetails();
        if (object.id != null)
          message.id = $String(object.id);
        if (object.label != null)
          message.label = $String(object.label);
        switch (object.occupancyStatus) {
          case "EMPTY":
          case 0:
            message.occupancyStatus = 0;
            break;
          case "MANY_SEATS_AVAILABLE":
          case 1:
            message.occupancyStatus = 1;
            break;
          case "FEW_SEATS_AVAILABLE":
          case 2:
            message.occupancyStatus = 2;
            break;
          case "STANDING_ROOM_ONLY":
          case 3:
            message.occupancyStatus = 3;
            break;
          case "CRUSHED_STANDING_ROOM_ONLY":
          case 4:
            message.occupancyStatus = 4;
            break;
          case "FULL":
          case 5:
            message.occupancyStatus = 5;
            break;
          case "NOT_ACCEPTING_PASSENGERS":
          case 6:
            message.occupancyStatus = 6;
            break;
          case "NO_DATA_AVAILABLE":
          case 7:
            message.occupancyStatus = 7;
            break;
          case "NOT_BOARDABLE":
          case 8:
            message.occupancyStatus = 8;
            break;
          default:
        }
        if (object.occupancyPercentage != null)
          message.occupancyPercentage = object.occupancyPercentage | 0;
        if (object.carriageSequence != null)
          message.carriageSequence = object.carriageSequence >>> 0;
        return message;
      };
      CarriageDetails.toObject = function(message, options, _depth) {
        if (!options)
          options = {};
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $util.recursionLimit)
          throw $Error("max depth exceeded");
        let object = {};
        if (options.defaults) {
          object.id = "";
          object.label = "";
          object.occupancyStatus = options.enums === $String ? "NO_DATA_AVAILABLE" : 7;
          object.occupancyPercentage = -1;
          object.carriageSequence = 0;
        }
        if (message.id != null && $Object.hasOwnProperty.call(message, "id"))
          object.id = message.id;
        if (message.label != null && $Object.hasOwnProperty.call(message, "label"))
          object.label = message.label;
        if (message.occupancyStatus != null && $Object.hasOwnProperty.call(message, "occupancyStatus"))
          object.occupancyStatus = options.enums === $String ? $root.transit_realtime.VehiclePosition.OccupancyStatus[message.occupancyStatus] === $undefined ? message.occupancyStatus : $root.transit_realtime.VehiclePosition.OccupancyStatus[message.occupancyStatus] : message.occupancyStatus;
        if (message.occupancyPercentage != null && $Object.hasOwnProperty.call(message, "occupancyPercentage"))
          object.occupancyPercentage = message.occupancyPercentage;
        if (message.carriageSequence != null && $Object.hasOwnProperty.call(message, "carriageSequence"))
          object.carriageSequence = message.carriageSequence;
        return object;
      };
      CarriageDetails.prototype.toJSON = function() {
        return CarriageDetails.toObject(this, import_minimal.default.util.toJSONOptions);
      };
      CarriageDetails.getTypeUrl = function(prefix) {
        if (prefix === $undefined)
          prefix = "type.googleapis.com";
        return prefix + "/transit_realtime.VehiclePosition.CarriageDetails";
      };
      return CarriageDetails;
    })();
    return VehiclePosition;
  })();
  transit_realtime2.Alert = (function() {
    const Alert = /* @__PURE__ */ __name(function(properties) {
      this.activePeriod = [];
      this.informedEntity = [];
      if (properties) {
        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
          if (properties[keys[i]] != null && keys[i] !== "__proto__")
            this[keys[i]] = properties[keys[i]];
      }
    }, "Alert");
    Alert.prototype.activePeriod = $util.emptyArray;
    Alert.prototype.informedEntity = $util.emptyArray;
    Alert.prototype.cause = 1;
    Alert.prototype.effect = 8;
    Alert.prototype.url = null;
    Alert.prototype.headerText = null;
    Alert.prototype.descriptionText = null;
    Alert.prototype.ttsHeaderText = null;
    Alert.prototype.ttsDescriptionText = null;
    Alert.prototype.severityLevel = 1;
    Alert.prototype.image = null;
    Alert.prototype.imageAlternativeText = null;
    Alert.prototype.causeDetail = null;
    Alert.prototype.effectDetail = null;
    Alert.prototype[".transit_realtime.mercuryAlert"] = null;
    Alert.create = function(properties) {
      return new Alert(properties);
    };
    Alert.encode = function(message, writer, _depth) {
      if (!writer)
        writer = $Writer.create();
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      if (message.activePeriod != null && message.activePeriod.length)
        for (let i = 0; i < message.activePeriod.length; ++i)
          $root.transit_realtime.TimeRange.encode(message.activePeriod[i], writer.uint32(
            /* id 1, wireType 2 =*/
            10
          ).fork(), _depth + 1).ldelim();
      if (message.informedEntity != null && message.informedEntity.length)
        for (let i = 0; i < message.informedEntity.length; ++i)
          $root.transit_realtime.EntitySelector.encode(message.informedEntity[i], writer.uint32(
            /* id 5, wireType 2 =*/
            42
          ).fork(), _depth + 1).ldelim();
      if (message.cause != null && $Object.hasOwnProperty.call(message, "cause"))
        writer.uint32(
          /* id 6, wireType 0 =*/
          48
        ).int32(message.cause);
      if (message.effect != null && $Object.hasOwnProperty.call(message, "effect"))
        writer.uint32(
          /* id 7, wireType 0 =*/
          56
        ).int32(message.effect);
      if (message.url != null && $Object.hasOwnProperty.call(message, "url"))
        $root.transit_realtime.TranslatedString.encode(message.url, writer.uint32(
          /* id 8, wireType 2 =*/
          66
        ).fork(), _depth + 1).ldelim();
      if (message.headerText != null && $Object.hasOwnProperty.call(message, "headerText"))
        $root.transit_realtime.TranslatedString.encode(message.headerText, writer.uint32(
          /* id 10, wireType 2 =*/
          82
        ).fork(), _depth + 1).ldelim();
      if (message.descriptionText != null && $Object.hasOwnProperty.call(message, "descriptionText"))
        $root.transit_realtime.TranslatedString.encode(message.descriptionText, writer.uint32(
          /* id 11, wireType 2 =*/
          90
        ).fork(), _depth + 1).ldelim();
      if (message.ttsHeaderText != null && $Object.hasOwnProperty.call(message, "ttsHeaderText"))
        $root.transit_realtime.TranslatedString.encode(message.ttsHeaderText, writer.uint32(
          /* id 12, wireType 2 =*/
          98
        ).fork(), _depth + 1).ldelim();
      if (message.ttsDescriptionText != null && $Object.hasOwnProperty.call(message, "ttsDescriptionText"))
        $root.transit_realtime.TranslatedString.encode(message.ttsDescriptionText, writer.uint32(
          /* id 13, wireType 2 =*/
          106
        ).fork(), _depth + 1).ldelim();
      if (message.severityLevel != null && $Object.hasOwnProperty.call(message, "severityLevel"))
        writer.uint32(
          /* id 14, wireType 0 =*/
          112
        ).int32(message.severityLevel);
      if (message.image != null && $Object.hasOwnProperty.call(message, "image"))
        $root.transit_realtime.TranslatedImage.encode(message.image, writer.uint32(
          /* id 15, wireType 2 =*/
          122
        ).fork(), _depth + 1).ldelim();
      if (message.imageAlternativeText != null && $Object.hasOwnProperty.call(message, "imageAlternativeText"))
        $root.transit_realtime.TranslatedString.encode(message.imageAlternativeText, writer.uint32(
          /* id 16, wireType 2 =*/
          130
        ).fork(), _depth + 1).ldelim();
      if (message.causeDetail != null && $Object.hasOwnProperty.call(message, "causeDetail"))
        $root.transit_realtime.TranslatedString.encode(message.causeDetail, writer.uint32(
          /* id 17, wireType 2 =*/
          138
        ).fork(), _depth + 1).ldelim();
      if (message.effectDetail != null && $Object.hasOwnProperty.call(message, "effectDetail"))
        $root.transit_realtime.TranslatedString.encode(message.effectDetail, writer.uint32(
          /* id 18, wireType 2 =*/
          146
        ).fork(), _depth + 1).ldelim();
      if (message[".transit_realtime.mercuryAlert"] != null && $Object.hasOwnProperty.call(message, ".transit_realtime.mercuryAlert"))
        $root.transit_realtime.MercuryAlert.encode(message[".transit_realtime.mercuryAlert"], writer.uint32(
          /* id 1001, wireType 2 =*/
          8010
        ).fork(), _depth + 1).ldelim();
      if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
        for (let i = 0; i < message.$unknowns.length; ++i)
          writer.raw(message.$unknowns[i]);
      return writer;
    };
    Alert.encodeDelimited = function(message, writer) {
      return this.encode(message, (writer || $Writer.create()).fork()).ldelim();
    };
    Alert.decode = function(reader, length, _end, _depth, _target) {
      if (!(reader instanceof $Reader))
        reader = $Reader.create(reader);
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $Reader.recursionLimit)
        throw $Error("max depth exceeded");
      let end, message, value;
      if (length === $undefined)
        end = reader.len;
      else {
        end = reader.pos + length;
        if (end > reader.len)
          throw $RangeError("index out of range");
        length = reader.len;
        reader.len = end;
      }
      message = _target || new $root.transit_realtime.Alert();
      while (reader.pos < end) {
        let start = reader.pos;
        let tag = reader.tag();
        if (tag === _end) {
          _end = $undefined;
          break;
        }
        let wireType = tag & 7;
        switch (tag >>>= 3) {
          case 1: {
            if (wireType !== 2)
              break;
            if (!(message.activePeriod && message.activePeriod.length))
              message.activePeriod = [];
            message.activePeriod.push($root.transit_realtime.TimeRange.decode(reader, reader.uint32(), $undefined, _depth + 1));
            continue;
          }
          case 5: {
            if (wireType !== 2)
              break;
            if (!(message.informedEntity && message.informedEntity.length))
              message.informedEntity = [];
            message.informedEntity.push($root.transit_realtime.EntitySelector.decode(reader, reader.uint32(), $undefined, _depth + 1));
            continue;
          }
          case 6: {
            if (wireType !== 0)
              break;
            value = reader.int32();
            if ($root.transit_realtime.Alert.Cause[value] !== $undefined)
              message.cause = value;
            else if (!reader.discardUnknown) {
              $util.makeProp(message, "$unknowns", false);
              (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
            }
            continue;
          }
          case 7: {
            if (wireType !== 0)
              break;
            value = reader.int32();
            if ($root.transit_realtime.Alert.Effect[value] !== $undefined)
              message.effect = value;
            else if (!reader.discardUnknown) {
              $util.makeProp(message, "$unknowns", false);
              (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
            }
            continue;
          }
          case 8: {
            if (wireType !== 2)
              break;
            message.url = $root.transit_realtime.TranslatedString.decode(reader, reader.uint32(), $undefined, _depth + 1, message.url);
            continue;
          }
          case 10: {
            if (wireType !== 2)
              break;
            message.headerText = $root.transit_realtime.TranslatedString.decode(reader, reader.uint32(), $undefined, _depth + 1, message.headerText);
            continue;
          }
          case 11: {
            if (wireType !== 2)
              break;
            message.descriptionText = $root.transit_realtime.TranslatedString.decode(reader, reader.uint32(), $undefined, _depth + 1, message.descriptionText);
            continue;
          }
          case 12: {
            if (wireType !== 2)
              break;
            message.ttsHeaderText = $root.transit_realtime.TranslatedString.decode(reader, reader.uint32(), $undefined, _depth + 1, message.ttsHeaderText);
            continue;
          }
          case 13: {
            if (wireType !== 2)
              break;
            message.ttsDescriptionText = $root.transit_realtime.TranslatedString.decode(reader, reader.uint32(), $undefined, _depth + 1, message.ttsDescriptionText);
            continue;
          }
          case 14: {
            if (wireType !== 0)
              break;
            value = reader.int32();
            if ($root.transit_realtime.Alert.SeverityLevel[value] !== $undefined)
              message.severityLevel = value;
            else if (!reader.discardUnknown) {
              $util.makeProp(message, "$unknowns", false);
              (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
            }
            continue;
          }
          case 15: {
            if (wireType !== 2)
              break;
            message.image = $root.transit_realtime.TranslatedImage.decode(reader, reader.uint32(), $undefined, _depth + 1, message.image);
            continue;
          }
          case 16: {
            if (wireType !== 2)
              break;
            message.imageAlternativeText = $root.transit_realtime.TranslatedString.decode(reader, reader.uint32(), $undefined, _depth + 1, message.imageAlternativeText);
            continue;
          }
          case 17: {
            if (wireType !== 2)
              break;
            message.causeDetail = $root.transit_realtime.TranslatedString.decode(reader, reader.uint32(), $undefined, _depth + 1, message.causeDetail);
            continue;
          }
          case 18: {
            if (wireType !== 2)
              break;
            message.effectDetail = $root.transit_realtime.TranslatedString.decode(reader, reader.uint32(), $undefined, _depth + 1, message.effectDetail);
            continue;
          }
          case 1001: {
            if (wireType !== 2)
              break;
            message[".transit_realtime.mercuryAlert"] = $root.transit_realtime.MercuryAlert.decode(reader, reader.uint32(), $undefined, _depth + 1, message[".transit_realtime.mercuryAlert"]);
            continue;
          }
        }
        reader.skipType(wireType, _depth, tag);
        if (!reader.discardUnknown) {
          $util.makeProp(message, "$unknowns", false);
          (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
        }
      }
      if (length !== $undefined) {
        if (reader.pos !== end)
          throw $RangeError("index out of range");
        reader.len = length;
      }
      if (_end !== $undefined)
        throw $Error("missing end group");
      return message;
    };
    Alert.decodeDelimited = function(reader) {
      if (!(reader instanceof $Reader))
        reader = new $Reader(reader);
      return this.decode(reader, reader.uint32());
    };
    Alert.verify = function(message, _depth) {
      if (typeof message !== "object" || message === null)
        return "object expected";
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        return "max depth exceeded";
      if (message.activePeriod != null && $Object.hasOwnProperty.call(message, "activePeriod")) {
        if (!$Array.isArray(message.activePeriod))
          return "activePeriod: array expected";
        for (let i = 0; i < message.activePeriod.length; ++i) {
          let error = $root.transit_realtime.TimeRange.verify(message.activePeriod[i], _depth + 1);
          if (error)
            return "activePeriod." + error;
        }
      }
      if (message.informedEntity != null && $Object.hasOwnProperty.call(message, "informedEntity")) {
        if (!$Array.isArray(message.informedEntity))
          return "informedEntity: array expected";
        for (let i = 0; i < message.informedEntity.length; ++i) {
          let error = $root.transit_realtime.EntitySelector.verify(message.informedEntity[i], _depth + 1);
          if (error)
            return "informedEntity." + error;
        }
      }
      if (message.cause != null && $Object.hasOwnProperty.call(message, "cause"))
        switch (message.cause) {
          default:
            return "cause: enum value expected";
          case 1:
          case 2:
          case 3:
          case 4:
          case 5:
          case 6:
          case 7:
          case 8:
          case 9:
          case 10:
          case 11:
          case 12:
          case 13:
            break;
        }
      if (message.effect != null && $Object.hasOwnProperty.call(message, "effect"))
        switch (message.effect) {
          default:
            return "effect: enum value expected";
          case 1:
          case 2:
          case 3:
          case 4:
          case 5:
          case 6:
          case 7:
          case 8:
          case 9:
          case 10:
          case 11:
            break;
        }
      if (message.url != null && $Object.hasOwnProperty.call(message, "url")) {
        let error = $root.transit_realtime.TranslatedString.verify(message.url, _depth + 1);
        if (error)
          return "url." + error;
      }
      if (message.headerText != null && $Object.hasOwnProperty.call(message, "headerText")) {
        let error = $root.transit_realtime.TranslatedString.verify(message.headerText, _depth + 1);
        if (error)
          return "headerText." + error;
      }
      if (message.descriptionText != null && $Object.hasOwnProperty.call(message, "descriptionText")) {
        let error = $root.transit_realtime.TranslatedString.verify(message.descriptionText, _depth + 1);
        if (error)
          return "descriptionText." + error;
      }
      if (message.ttsHeaderText != null && $Object.hasOwnProperty.call(message, "ttsHeaderText")) {
        let error = $root.transit_realtime.TranslatedString.verify(message.ttsHeaderText, _depth + 1);
        if (error)
          return "ttsHeaderText." + error;
      }
      if (message.ttsDescriptionText != null && $Object.hasOwnProperty.call(message, "ttsDescriptionText")) {
        let error = $root.transit_realtime.TranslatedString.verify(message.ttsDescriptionText, _depth + 1);
        if (error)
          return "ttsDescriptionText." + error;
      }
      if (message.severityLevel != null && $Object.hasOwnProperty.call(message, "severityLevel"))
        switch (message.severityLevel) {
          default:
            return "severityLevel: enum value expected";
          case 1:
          case 2:
          case 3:
          case 4:
            break;
        }
      if (message.image != null && $Object.hasOwnProperty.call(message, "image")) {
        let error = $root.transit_realtime.TranslatedImage.verify(message.image, _depth + 1);
        if (error)
          return "image." + error;
      }
      if (message.imageAlternativeText != null && $Object.hasOwnProperty.call(message, "imageAlternativeText")) {
        let error = $root.transit_realtime.TranslatedString.verify(message.imageAlternativeText, _depth + 1);
        if (error)
          return "imageAlternativeText." + error;
      }
      if (message.causeDetail != null && $Object.hasOwnProperty.call(message, "causeDetail")) {
        let error = $root.transit_realtime.TranslatedString.verify(message.causeDetail, _depth + 1);
        if (error)
          return "causeDetail." + error;
      }
      if (message.effectDetail != null && $Object.hasOwnProperty.call(message, "effectDetail")) {
        let error = $root.transit_realtime.TranslatedString.verify(message.effectDetail, _depth + 1);
        if (error)
          return "effectDetail." + error;
      }
      if (message[".transit_realtime.mercuryAlert"] != null && $Object.hasOwnProperty.call(message, ".transit_realtime.mercuryAlert")) {
        let error = $root.transit_realtime.MercuryAlert.verify(message[".transit_realtime.mercuryAlert"], _depth + 1);
        if (error)
          return ".transit_realtime.mercuryAlert." + error;
      }
      return null;
    };
    Alert.fromObject = function(object, _depth) {
      if (object instanceof $root.transit_realtime.Alert)
        return object;
      if (!$util.isObject(object))
        throw $TypeError(".transit_realtime.Alert: object expected");
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let message = new $root.transit_realtime.Alert();
      if (object.activePeriod) {
        if (!$Array.isArray(object.activePeriod))
          throw $TypeError(".transit_realtime.Alert.activePeriod: array expected");
        message.activePeriod = $Array(object.activePeriod.length);
        for (let i = 0; i < object.activePeriod.length; ++i) {
          if (!$util.isObject(object.activePeriod[i]))
            throw $TypeError(".transit_realtime.Alert.activePeriod: object expected");
          message.activePeriod[i] = $root.transit_realtime.TimeRange.fromObject(object.activePeriod[i], _depth + 1);
        }
      }
      if (object.informedEntity) {
        if (!$Array.isArray(object.informedEntity))
          throw $TypeError(".transit_realtime.Alert.informedEntity: array expected");
        message.informedEntity = $Array(object.informedEntity.length);
        for (let i = 0; i < object.informedEntity.length; ++i) {
          if (!$util.isObject(object.informedEntity[i]))
            throw $TypeError(".transit_realtime.Alert.informedEntity: object expected");
          message.informedEntity[i] = $root.transit_realtime.EntitySelector.fromObject(object.informedEntity[i], _depth + 1);
        }
      }
      switch (object.cause) {
        case "UNKNOWN_CAUSE":
        case 1:
          message.cause = 1;
          break;
        case "OTHER_CAUSE":
        case 2:
          message.cause = 2;
          break;
        case "TECHNICAL_PROBLEM":
        case 3:
          message.cause = 3;
          break;
        case "STRIKE":
        case 4:
          message.cause = 4;
          break;
        case "DEMONSTRATION":
        case 5:
          message.cause = 5;
          break;
        case "ACCIDENT":
        case 6:
          message.cause = 6;
          break;
        case "HOLIDAY":
        case 7:
          message.cause = 7;
          break;
        case "WEATHER":
        case 8:
          message.cause = 8;
          break;
        case "MAINTENANCE":
        case 9:
          message.cause = 9;
          break;
        case "CONSTRUCTION":
        case 10:
          message.cause = 10;
          break;
        case "POLICE_ACTIVITY":
        case 11:
          message.cause = 11;
          break;
        case "MEDICAL_EMERGENCY":
        case 12:
          message.cause = 12;
          break;
        case "SPECIAL_EVENT":
        case 13:
          message.cause = 13;
          break;
        default:
      }
      switch (object.effect) {
        case "NO_SERVICE":
        case 1:
          message.effect = 1;
          break;
        case "REDUCED_SERVICE":
        case 2:
          message.effect = 2;
          break;
        case "SIGNIFICANT_DELAYS":
        case 3:
          message.effect = 3;
          break;
        case "DETOUR":
        case 4:
          message.effect = 4;
          break;
        case "ADDITIONAL_SERVICE":
        case 5:
          message.effect = 5;
          break;
        case "MODIFIED_SERVICE":
        case 6:
          message.effect = 6;
          break;
        case "OTHER_EFFECT":
        case 7:
          message.effect = 7;
          break;
        case "UNKNOWN_EFFECT":
        case 8:
          message.effect = 8;
          break;
        case "STOP_MOVED":
        case 9:
          message.effect = 9;
          break;
        case "NO_EFFECT":
        case 10:
          message.effect = 10;
          break;
        case "ACCESSIBILITY_ISSUE":
        case 11:
          message.effect = 11;
          break;
        default:
      }
      if (object.url != null) {
        if (!$util.isObject(object.url))
          throw $TypeError(".transit_realtime.Alert.url: object expected");
        message.url = $root.transit_realtime.TranslatedString.fromObject(object.url, _depth + 1);
      }
      if (object.headerText != null) {
        if (!$util.isObject(object.headerText))
          throw $TypeError(".transit_realtime.Alert.headerText: object expected");
        message.headerText = $root.transit_realtime.TranslatedString.fromObject(object.headerText, _depth + 1);
      }
      if (object.descriptionText != null) {
        if (!$util.isObject(object.descriptionText))
          throw $TypeError(".transit_realtime.Alert.descriptionText: object expected");
        message.descriptionText = $root.transit_realtime.TranslatedString.fromObject(object.descriptionText, _depth + 1);
      }
      if (object.ttsHeaderText != null) {
        if (!$util.isObject(object.ttsHeaderText))
          throw $TypeError(".transit_realtime.Alert.ttsHeaderText: object expected");
        message.ttsHeaderText = $root.transit_realtime.TranslatedString.fromObject(object.ttsHeaderText, _depth + 1);
      }
      if (object.ttsDescriptionText != null) {
        if (!$util.isObject(object.ttsDescriptionText))
          throw $TypeError(".transit_realtime.Alert.ttsDescriptionText: object expected");
        message.ttsDescriptionText = $root.transit_realtime.TranslatedString.fromObject(object.ttsDescriptionText, _depth + 1);
      }
      switch (object.severityLevel) {
        case "UNKNOWN_SEVERITY":
        case 1:
          message.severityLevel = 1;
          break;
        case "INFO":
        case 2:
          message.severityLevel = 2;
          break;
        case "WARNING":
        case 3:
          message.severityLevel = 3;
          break;
        case "SEVERE":
        case 4:
          message.severityLevel = 4;
          break;
        default:
      }
      if (object.image != null) {
        if (!$util.isObject(object.image))
          throw $TypeError(".transit_realtime.Alert.image: object expected");
        message.image = $root.transit_realtime.TranslatedImage.fromObject(object.image, _depth + 1);
      }
      if (object.imageAlternativeText != null) {
        if (!$util.isObject(object.imageAlternativeText))
          throw $TypeError(".transit_realtime.Alert.imageAlternativeText: object expected");
        message.imageAlternativeText = $root.transit_realtime.TranslatedString.fromObject(object.imageAlternativeText, _depth + 1);
      }
      if (object.causeDetail != null) {
        if (!$util.isObject(object.causeDetail))
          throw $TypeError(".transit_realtime.Alert.causeDetail: object expected");
        message.causeDetail = $root.transit_realtime.TranslatedString.fromObject(object.causeDetail, _depth + 1);
      }
      if (object.effectDetail != null) {
        if (!$util.isObject(object.effectDetail))
          throw $TypeError(".transit_realtime.Alert.effectDetail: object expected");
        message.effectDetail = $root.transit_realtime.TranslatedString.fromObject(object.effectDetail, _depth + 1);
      }
      if (object[".transit_realtime.mercuryAlert"] != null) {
        if (!$util.isObject(object[".transit_realtime.mercuryAlert"]))
          throw $TypeError(".transit_realtime.Alert..transit_realtime.mercuryAlert: object expected");
        message[".transit_realtime.mercuryAlert"] = $root.transit_realtime.MercuryAlert.fromObject(object[".transit_realtime.mercuryAlert"], _depth + 1);
      }
      return message;
    };
    Alert.toObject = function(message, options, _depth) {
      if (!options)
        options = {};
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let object = {};
      if (options.arrays || options.defaults) {
        object.activePeriod = [];
        object.informedEntity = [];
      }
      if (options.defaults) {
        object.cause = options.enums === $String ? "UNKNOWN_CAUSE" : 1;
        object.effect = options.enums === $String ? "UNKNOWN_EFFECT" : 8;
        object.url = null;
        object.headerText = null;
        object.descriptionText = null;
        object.ttsHeaderText = null;
        object.ttsDescriptionText = null;
        object.severityLevel = options.enums === $String ? "UNKNOWN_SEVERITY" : 1;
        object.image = null;
        object.imageAlternativeText = null;
        object.causeDetail = null;
        object.effectDetail = null;
        object[".transit_realtime.mercuryAlert"] = null;
      }
      if (message.activePeriod && message.activePeriod.length) {
        object.activePeriod = $Array(message.activePeriod.length);
        for (let j = 0; j < message.activePeriod.length; ++j)
          object.activePeriod[j] = $root.transit_realtime.TimeRange.toObject(message.activePeriod[j], options, _depth + 1);
      }
      if (message.informedEntity && message.informedEntity.length) {
        object.informedEntity = $Array(message.informedEntity.length);
        for (let j = 0; j < message.informedEntity.length; ++j)
          object.informedEntity[j] = $root.transit_realtime.EntitySelector.toObject(message.informedEntity[j], options, _depth + 1);
      }
      if (message.cause != null && $Object.hasOwnProperty.call(message, "cause"))
        object.cause = options.enums === $String ? $root.transit_realtime.Alert.Cause[message.cause] === $undefined ? message.cause : $root.transit_realtime.Alert.Cause[message.cause] : message.cause;
      if (message.effect != null && $Object.hasOwnProperty.call(message, "effect"))
        object.effect = options.enums === $String ? $root.transit_realtime.Alert.Effect[message.effect] === $undefined ? message.effect : $root.transit_realtime.Alert.Effect[message.effect] : message.effect;
      if (message.url != null && $Object.hasOwnProperty.call(message, "url"))
        object.url = $root.transit_realtime.TranslatedString.toObject(message.url, options, _depth + 1);
      if (message.headerText != null && $Object.hasOwnProperty.call(message, "headerText"))
        object.headerText = $root.transit_realtime.TranslatedString.toObject(message.headerText, options, _depth + 1);
      if (message.descriptionText != null && $Object.hasOwnProperty.call(message, "descriptionText"))
        object.descriptionText = $root.transit_realtime.TranslatedString.toObject(message.descriptionText, options, _depth + 1);
      if (message.ttsHeaderText != null && $Object.hasOwnProperty.call(message, "ttsHeaderText"))
        object.ttsHeaderText = $root.transit_realtime.TranslatedString.toObject(message.ttsHeaderText, options, _depth + 1);
      if (message.ttsDescriptionText != null && $Object.hasOwnProperty.call(message, "ttsDescriptionText"))
        object.ttsDescriptionText = $root.transit_realtime.TranslatedString.toObject(message.ttsDescriptionText, options, _depth + 1);
      if (message.severityLevel != null && $Object.hasOwnProperty.call(message, "severityLevel"))
        object.severityLevel = options.enums === $String ? $root.transit_realtime.Alert.SeverityLevel[message.severityLevel] === $undefined ? message.severityLevel : $root.transit_realtime.Alert.SeverityLevel[message.severityLevel] : message.severityLevel;
      if (message.image != null && $Object.hasOwnProperty.call(message, "image"))
        object.image = $root.transit_realtime.TranslatedImage.toObject(message.image, options, _depth + 1);
      if (message.imageAlternativeText != null && $Object.hasOwnProperty.call(message, "imageAlternativeText"))
        object.imageAlternativeText = $root.transit_realtime.TranslatedString.toObject(message.imageAlternativeText, options, _depth + 1);
      if (message.causeDetail != null && $Object.hasOwnProperty.call(message, "causeDetail"))
        object.causeDetail = $root.transit_realtime.TranslatedString.toObject(message.causeDetail, options, _depth + 1);
      if (message.effectDetail != null && $Object.hasOwnProperty.call(message, "effectDetail"))
        object.effectDetail = $root.transit_realtime.TranslatedString.toObject(message.effectDetail, options, _depth + 1);
      if (message[".transit_realtime.mercuryAlert"] != null && $Object.hasOwnProperty.call(message, ".transit_realtime.mercuryAlert"))
        object[".transit_realtime.mercuryAlert"] = $root.transit_realtime.MercuryAlert.toObject(message[".transit_realtime.mercuryAlert"], options, _depth + 1);
      return object;
    };
    Alert.prototype.toJSON = function() {
      return Alert.toObject(this, import_minimal.default.util.toJSONOptions);
    };
    Alert.getTypeUrl = function(prefix) {
      if (prefix === $undefined)
        prefix = "type.googleapis.com";
      return prefix + "/transit_realtime.Alert";
    };
    Alert.Cause = (function() {
      const valuesById = $Object.create(null), values = $Object.create(valuesById);
      values[valuesById[1] = "UNKNOWN_CAUSE"] = 1;
      values[valuesById[2] = "OTHER_CAUSE"] = 2;
      values[valuesById[3] = "TECHNICAL_PROBLEM"] = 3;
      values[valuesById[4] = "STRIKE"] = 4;
      values[valuesById[5] = "DEMONSTRATION"] = 5;
      values[valuesById[6] = "ACCIDENT"] = 6;
      values[valuesById[7] = "HOLIDAY"] = 7;
      values[valuesById[8] = "WEATHER"] = 8;
      values[valuesById[9] = "MAINTENANCE"] = 9;
      values[valuesById[10] = "CONSTRUCTION"] = 10;
      values[valuesById[11] = "POLICE_ACTIVITY"] = 11;
      values[valuesById[12] = "MEDICAL_EMERGENCY"] = 12;
      values[valuesById[13] = "SPECIAL_EVENT"] = 13;
      return values;
    })();
    Alert.Effect = (function() {
      const valuesById = $Object.create(null), values = $Object.create(valuesById);
      values[valuesById[1] = "NO_SERVICE"] = 1;
      values[valuesById[2] = "REDUCED_SERVICE"] = 2;
      values[valuesById[3] = "SIGNIFICANT_DELAYS"] = 3;
      values[valuesById[4] = "DETOUR"] = 4;
      values[valuesById[5] = "ADDITIONAL_SERVICE"] = 5;
      values[valuesById[6] = "MODIFIED_SERVICE"] = 6;
      values[valuesById[7] = "OTHER_EFFECT"] = 7;
      values[valuesById[8] = "UNKNOWN_EFFECT"] = 8;
      values[valuesById[9] = "STOP_MOVED"] = 9;
      values[valuesById[10] = "NO_EFFECT"] = 10;
      values[valuesById[11] = "ACCESSIBILITY_ISSUE"] = 11;
      return values;
    })();
    Alert.SeverityLevel = (function() {
      const valuesById = $Object.create(null), values = $Object.create(valuesById);
      values[valuesById[1] = "UNKNOWN_SEVERITY"] = 1;
      values[valuesById[2] = "INFO"] = 2;
      values[valuesById[3] = "WARNING"] = 3;
      values[valuesById[4] = "SEVERE"] = 4;
      return values;
    })();
    return Alert;
  })();
  transit_realtime2.TimeRange = (function() {
    const TimeRange = /* @__PURE__ */ __name(function(properties) {
      if (properties) {
        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
          if (properties[keys[i]] != null && keys[i] !== "__proto__")
            this[keys[i]] = properties[keys[i]];
      }
    }, "TimeRange");
    TimeRange.prototype.start = $util.Long ? $util.Long.fromBits(0, 0, true) : 0;
    TimeRange.prototype.end = $util.Long ? $util.Long.fromBits(0, 0, true) : 0;
    TimeRange.create = function(properties) {
      return new TimeRange(properties);
    };
    TimeRange.encode = function(message, writer, _depth) {
      if (!writer)
        writer = $Writer.create();
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      if (message.start != null && $Object.hasOwnProperty.call(message, "start"))
        writer.uint32(
          /* id 1, wireType 0 =*/
          8
        ).uint64(message.start);
      if (message.end != null && $Object.hasOwnProperty.call(message, "end"))
        writer.uint32(
          /* id 2, wireType 0 =*/
          16
        ).uint64(message.end);
      if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
        for (let i = 0; i < message.$unknowns.length; ++i)
          writer.raw(message.$unknowns[i]);
      return writer;
    };
    TimeRange.encodeDelimited = function(message, writer) {
      return this.encode(message, (writer || $Writer.create()).fork()).ldelim();
    };
    TimeRange.decode = function(reader, length, _end, _depth, _target) {
      if (!(reader instanceof $Reader))
        reader = $Reader.create(reader);
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $Reader.recursionLimit)
        throw $Error("max depth exceeded");
      let end, message;
      if (length === $undefined)
        end = reader.len;
      else {
        end = reader.pos + length;
        if (end > reader.len)
          throw $RangeError("index out of range");
        length = reader.len;
        reader.len = end;
      }
      message = _target || new $root.transit_realtime.TimeRange();
      while (reader.pos < end) {
        let start = reader.pos;
        let tag = reader.tag();
        if (tag === _end) {
          _end = $undefined;
          break;
        }
        let wireType = tag & 7;
        switch (tag >>>= 3) {
          case 1: {
            if (wireType !== 0)
              break;
            message.start = reader.uint64();
            continue;
          }
          case 2: {
            if (wireType !== 0)
              break;
            message.end = reader.uint64();
            continue;
          }
        }
        reader.skipType(wireType, _depth, tag);
        if (!reader.discardUnknown) {
          $util.makeProp(message, "$unknowns", false);
          (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
        }
      }
      if (length !== $undefined) {
        if (reader.pos !== end)
          throw $RangeError("index out of range");
        reader.len = length;
      }
      if (_end !== $undefined)
        throw $Error("missing end group");
      return message;
    };
    TimeRange.decodeDelimited = function(reader) {
      if (!(reader instanceof $Reader))
        reader = new $Reader(reader);
      return this.decode(reader, reader.uint32());
    };
    TimeRange.verify = function(message, _depth) {
      if (typeof message !== "object" || message === null)
        return "object expected";
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        return "max depth exceeded";
      if (message.start != null && $Object.hasOwnProperty.call(message, "start")) {
        if (!$util.isInteger(message.start) && !(message.start && $util.isInteger(message.start.low) && $util.isInteger(message.start.high)))
          return "start: integer|Long expected";
      }
      if (message.end != null && $Object.hasOwnProperty.call(message, "end")) {
        if (!$util.isInteger(message.end) && !(message.end && $util.isInteger(message.end.low) && $util.isInteger(message.end.high)))
          return "end: integer|Long expected";
      }
      return null;
    };
    TimeRange.fromObject = function(object, _depth) {
      if (object instanceof $root.transit_realtime.TimeRange)
        return object;
      if (!$util.isObject(object))
        throw $TypeError(".transit_realtime.TimeRange: object expected");
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let message = new $root.transit_realtime.TimeRange();
      if (object.start != null) {
        if ($util.Long)
          message.start = $util.Long.fromValue(object.start, true);
        else if (typeof object.start === "string")
          message.start = $parseInt(object.start, 10);
        else if (typeof object.start === "number")
          message.start = object.start;
        else if (typeof object.start === "object")
          message.start = new $util.LongBits(object.start.low >>> 0, object.start.high >>> 0).toNumber(true);
      }
      if (object.end != null) {
        if ($util.Long)
          message.end = $util.Long.fromValue(object.end, true);
        else if (typeof object.end === "string")
          message.end = $parseInt(object.end, 10);
        else if (typeof object.end === "number")
          message.end = object.end;
        else if (typeof object.end === "object")
          message.end = new $util.LongBits(object.end.low >>> 0, object.end.high >>> 0).toNumber(true);
      }
      return message;
    };
    TimeRange.toObject = function(message, options, _depth) {
      if (!options)
        options = {};
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let object = {};
      if (options.defaults) {
        if ($util.Long) {
          let long = new $util.Long(0, 0, true);
          object.start = options.longs === $String ? long.toString() : options.longs === $Number ? long.toNumber() : typeof $BigInt !== "undefined" && options.longs === $BigInt ? long.toBigInt() : long;
        } else
          object.start = options.longs === $String ? "0" : typeof $BigInt !== "undefined" && options.longs === $BigInt ? $BigInt("0") : 0;
        if ($util.Long) {
          let long = new $util.Long(0, 0, true);
          object.end = options.longs === $String ? long.toString() : options.longs === $Number ? long.toNumber() : typeof $BigInt !== "undefined" && options.longs === $BigInt ? long.toBigInt() : long;
        } else
          object.end = options.longs === $String ? "0" : typeof $BigInt !== "undefined" && options.longs === $BigInt ? $BigInt("0") : 0;
      }
      if (message.start != null && $Object.hasOwnProperty.call(message, "start"))
        if (typeof $BigInt !== "undefined" && options.longs === $BigInt)
          object.start = typeof message.start === "number" ? $BigInt(message.start) : $util.Long.fromBits(message.start.low >>> 0, message.start.high >>> 0, true).toBigInt();
        else if (typeof message.start === "number")
          object.start = options.longs === $String ? $String(message.start) : message.start;
        else
          object.start = options.longs === $String ? $util.Long.prototype.toString.call(message.start) : options.longs === $Number ? new $util.LongBits(message.start.low >>> 0, message.start.high >>> 0).toNumber(true) : message.start;
      if (message.end != null && $Object.hasOwnProperty.call(message, "end"))
        if (typeof $BigInt !== "undefined" && options.longs === $BigInt)
          object.end = typeof message.end === "number" ? $BigInt(message.end) : $util.Long.fromBits(message.end.low >>> 0, message.end.high >>> 0, true).toBigInt();
        else if (typeof message.end === "number")
          object.end = options.longs === $String ? $String(message.end) : message.end;
        else
          object.end = options.longs === $String ? $util.Long.prototype.toString.call(message.end) : options.longs === $Number ? new $util.LongBits(message.end.low >>> 0, message.end.high >>> 0).toNumber(true) : message.end;
      return object;
    };
    TimeRange.prototype.toJSON = function() {
      return TimeRange.toObject(this, import_minimal.default.util.toJSONOptions);
    };
    TimeRange.getTypeUrl = function(prefix) {
      if (prefix === $undefined)
        prefix = "type.googleapis.com";
      return prefix + "/transit_realtime.TimeRange";
    };
    return TimeRange;
  })();
  transit_realtime2.Position = (function() {
    const Position = /* @__PURE__ */ __name(function(properties) {
      if (properties) {
        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
          if (properties[keys[i]] != null && keys[i] !== "__proto__")
            this[keys[i]] = properties[keys[i]];
      }
    }, "Position");
    Position.prototype.latitude = 0;
    Position.prototype.longitude = 0;
    Position.prototype.bearing = 0;
    Position.prototype.odometer = 0;
    Position.prototype.speed = 0;
    Position.create = function(properties) {
      return new Position(properties);
    };
    Position.encode = function(message, writer, _depth) {
      if (!writer)
        writer = $Writer.create();
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      writer.uint32(
        /* id 1, wireType 5 =*/
        13
      ).float(message.latitude);
      writer.uint32(
        /* id 2, wireType 5 =*/
        21
      ).float(message.longitude);
      if (message.bearing != null && $Object.hasOwnProperty.call(message, "bearing"))
        writer.uint32(
          /* id 3, wireType 5 =*/
          29
        ).float(message.bearing);
      if (message.odometer != null && $Object.hasOwnProperty.call(message, "odometer"))
        writer.uint32(
          /* id 4, wireType 1 =*/
          33
        ).double(message.odometer);
      if (message.speed != null && $Object.hasOwnProperty.call(message, "speed"))
        writer.uint32(
          /* id 5, wireType 5 =*/
          45
        ).float(message.speed);
      if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
        for (let i = 0; i < message.$unknowns.length; ++i)
          writer.raw(message.$unknowns[i]);
      return writer;
    };
    Position.encodeDelimited = function(message, writer) {
      return this.encode(message, (writer || $Writer.create()).fork()).ldelim();
    };
    Position.decode = function(reader, length, _end, _depth, _target) {
      if (!(reader instanceof $Reader))
        reader = $Reader.create(reader);
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $Reader.recursionLimit)
        throw $Error("max depth exceeded");
      let end, message;
      if (length === $undefined)
        end = reader.len;
      else {
        end = reader.pos + length;
        if (end > reader.len)
          throw $RangeError("index out of range");
        length = reader.len;
        reader.len = end;
      }
      message = _target || new $root.transit_realtime.Position();
      while (reader.pos < end) {
        let start = reader.pos;
        let tag = reader.tag();
        if (tag === _end) {
          _end = $undefined;
          break;
        }
        let wireType = tag & 7;
        switch (tag >>>= 3) {
          case 1: {
            if (wireType !== 5)
              break;
            message.latitude = reader.float();
            continue;
          }
          case 2: {
            if (wireType !== 5)
              break;
            message.longitude = reader.float();
            continue;
          }
          case 3: {
            if (wireType !== 5)
              break;
            message.bearing = reader.float();
            continue;
          }
          case 4: {
            if (wireType !== 1)
              break;
            message.odometer = reader.double();
            continue;
          }
          case 5: {
            if (wireType !== 5)
              break;
            message.speed = reader.float();
            continue;
          }
        }
        reader.skipType(wireType, _depth, tag);
        if (!reader.discardUnknown) {
          $util.makeProp(message, "$unknowns", false);
          (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
        }
      }
      if (length !== $undefined) {
        if (reader.pos !== end)
          throw $RangeError("index out of range");
        reader.len = length;
      }
      if (_end !== $undefined)
        throw $Error("missing end group");
      if (!$Object.hasOwnProperty.call(message, "latitude"))
        throw $util.ProtocolError("missing required 'latitude'", { instance: message });
      if (!$Object.hasOwnProperty.call(message, "longitude"))
        throw $util.ProtocolError("missing required 'longitude'", { instance: message });
      return message;
    };
    Position.decodeDelimited = function(reader) {
      if (!(reader instanceof $Reader))
        reader = new $Reader(reader);
      return this.decode(reader, reader.uint32());
    };
    Position.verify = function(message, _depth) {
      if (typeof message !== "object" || message === null)
        return "object expected";
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        return "max depth exceeded";
      if (typeof message.latitude !== "number")
        return "latitude: number expected";
      if (typeof message.longitude !== "number")
        return "longitude: number expected";
      if (message.bearing != null && $Object.hasOwnProperty.call(message, "bearing")) {
        if (typeof message.bearing !== "number")
          return "bearing: number expected";
      }
      if (message.odometer != null && $Object.hasOwnProperty.call(message, "odometer")) {
        if (typeof message.odometer !== "number")
          return "odometer: number expected";
      }
      if (message.speed != null && $Object.hasOwnProperty.call(message, "speed")) {
        if (typeof message.speed !== "number")
          return "speed: number expected";
      }
      return null;
    };
    Position.fromObject = function(object, _depth) {
      if (object instanceof $root.transit_realtime.Position)
        return object;
      if (!$util.isObject(object))
        throw $TypeError(".transit_realtime.Position: object expected");
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let message = new $root.transit_realtime.Position();
      if (object.latitude != null)
        message.latitude = $Number(object.latitude);
      if (object.longitude != null)
        message.longitude = $Number(object.longitude);
      if (object.bearing != null)
        message.bearing = $Number(object.bearing);
      if (object.odometer != null)
        message.odometer = $Number(object.odometer);
      if (object.speed != null)
        message.speed = $Number(object.speed);
      return message;
    };
    Position.toObject = function(message, options, _depth) {
      if (!options)
        options = {};
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let object = {};
      if (options.defaults) {
        object.latitude = 0;
        object.longitude = 0;
        object.bearing = 0;
        object.odometer = 0;
        object.speed = 0;
      }
      if (message.latitude != null && $Object.hasOwnProperty.call(message, "latitude"))
        object.latitude = options.json && !$isFinite(message.latitude) ? $String(message.latitude) : message.latitude;
      if (message.longitude != null && $Object.hasOwnProperty.call(message, "longitude"))
        object.longitude = options.json && !$isFinite(message.longitude) ? $String(message.longitude) : message.longitude;
      if (message.bearing != null && $Object.hasOwnProperty.call(message, "bearing"))
        object.bearing = options.json && !$isFinite(message.bearing) ? $String(message.bearing) : message.bearing;
      if (message.odometer != null && $Object.hasOwnProperty.call(message, "odometer"))
        object.odometer = options.json && !$isFinite(message.odometer) ? $String(message.odometer) : message.odometer;
      if (message.speed != null && $Object.hasOwnProperty.call(message, "speed"))
        object.speed = options.json && !$isFinite(message.speed) ? $String(message.speed) : message.speed;
      return object;
    };
    Position.prototype.toJSON = function() {
      return Position.toObject(this, import_minimal.default.util.toJSONOptions);
    };
    Position.getTypeUrl = function(prefix) {
      if (prefix === $undefined)
        prefix = "type.googleapis.com";
      return prefix + "/transit_realtime.Position";
    };
    return Position;
  })();
  transit_realtime2.TripDescriptor = (function() {
    const TripDescriptor = /* @__PURE__ */ __name(function(properties) {
      if (properties) {
        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
          if (properties[keys[i]] != null && keys[i] !== "__proto__")
            this[keys[i]] = properties[keys[i]];
      }
    }, "TripDescriptor");
    TripDescriptor.prototype.tripId = "";
    TripDescriptor.prototype.routeId = "";
    TripDescriptor.prototype.directionId = 0;
    TripDescriptor.prototype.startTime = "";
    TripDescriptor.prototype.startDate = "";
    TripDescriptor.prototype.scheduleRelationship = 0;
    TripDescriptor.prototype.modifiedTrip = null;
    TripDescriptor.prototype[".transit_realtime.nyctTripDescriptor"] = null;
    TripDescriptor.create = function(properties) {
      return new TripDescriptor(properties);
    };
    TripDescriptor.encode = function(message, writer, _depth) {
      if (!writer)
        writer = $Writer.create();
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      if (message.tripId != null && $Object.hasOwnProperty.call(message, "tripId"))
        writer.uint32(
          /* id 1, wireType 2 =*/
          10
        ).string(message.tripId);
      if (message.startTime != null && $Object.hasOwnProperty.call(message, "startTime"))
        writer.uint32(
          /* id 2, wireType 2 =*/
          18
        ).string(message.startTime);
      if (message.startDate != null && $Object.hasOwnProperty.call(message, "startDate"))
        writer.uint32(
          /* id 3, wireType 2 =*/
          26
        ).string(message.startDate);
      if (message.scheduleRelationship != null && $Object.hasOwnProperty.call(message, "scheduleRelationship"))
        writer.uint32(
          /* id 4, wireType 0 =*/
          32
        ).int32(message.scheduleRelationship);
      if (message.routeId != null && $Object.hasOwnProperty.call(message, "routeId"))
        writer.uint32(
          /* id 5, wireType 2 =*/
          42
        ).string(message.routeId);
      if (message.directionId != null && $Object.hasOwnProperty.call(message, "directionId"))
        writer.uint32(
          /* id 6, wireType 0 =*/
          48
        ).uint32(message.directionId);
      if (message.modifiedTrip != null && $Object.hasOwnProperty.call(message, "modifiedTrip"))
        $root.transit_realtime.TripDescriptor.ModifiedTripSelector.encode(message.modifiedTrip, writer.uint32(
          /* id 7, wireType 2 =*/
          58
        ).fork(), _depth + 1).ldelim();
      if (message[".transit_realtime.nyctTripDescriptor"] != null && $Object.hasOwnProperty.call(message, ".transit_realtime.nyctTripDescriptor"))
        $root.transit_realtime.NyctTripDescriptor.encode(message[".transit_realtime.nyctTripDescriptor"], writer.uint32(
          /* id 1001, wireType 2 =*/
          8010
        ).fork(), _depth + 1).ldelim();
      if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
        for (let i = 0; i < message.$unknowns.length; ++i)
          writer.raw(message.$unknowns[i]);
      return writer;
    };
    TripDescriptor.encodeDelimited = function(message, writer) {
      return this.encode(message, (writer || $Writer.create()).fork()).ldelim();
    };
    TripDescriptor.decode = function(reader, length, _end, _depth, _target) {
      if (!(reader instanceof $Reader))
        reader = $Reader.create(reader);
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $Reader.recursionLimit)
        throw $Error("max depth exceeded");
      let end, message, value;
      if (length === $undefined)
        end = reader.len;
      else {
        end = reader.pos + length;
        if (end > reader.len)
          throw $RangeError("index out of range");
        length = reader.len;
        reader.len = end;
      }
      message = _target || new $root.transit_realtime.TripDescriptor();
      while (reader.pos < end) {
        let start = reader.pos;
        let tag = reader.tag();
        if (tag === _end) {
          _end = $undefined;
          break;
        }
        let wireType = tag & 7;
        switch (tag >>>= 3) {
          case 1: {
            if (wireType !== 2)
              break;
            message.tripId = reader.string();
            continue;
          }
          case 5: {
            if (wireType !== 2)
              break;
            message.routeId = reader.string();
            continue;
          }
          case 6: {
            if (wireType !== 0)
              break;
            message.directionId = reader.uint32();
            continue;
          }
          case 2: {
            if (wireType !== 2)
              break;
            message.startTime = reader.string();
            continue;
          }
          case 3: {
            if (wireType !== 2)
              break;
            message.startDate = reader.string();
            continue;
          }
          case 4: {
            if (wireType !== 0)
              break;
            value = reader.int32();
            if ($root.transit_realtime.TripDescriptor.ScheduleRelationship[value] !== $undefined)
              message.scheduleRelationship = value;
            else if (!reader.discardUnknown) {
              $util.makeProp(message, "$unknowns", false);
              (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
            }
            continue;
          }
          case 7: {
            if (wireType !== 2)
              break;
            message.modifiedTrip = $root.transit_realtime.TripDescriptor.ModifiedTripSelector.decode(reader, reader.uint32(), $undefined, _depth + 1, message.modifiedTrip);
            continue;
          }
          case 1001: {
            if (wireType !== 2)
              break;
            message[".transit_realtime.nyctTripDescriptor"] = $root.transit_realtime.NyctTripDescriptor.decode(reader, reader.uint32(), $undefined, _depth + 1, message[".transit_realtime.nyctTripDescriptor"]);
            continue;
          }
        }
        reader.skipType(wireType, _depth, tag);
        if (!reader.discardUnknown) {
          $util.makeProp(message, "$unknowns", false);
          (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
        }
      }
      if (length !== $undefined) {
        if (reader.pos !== end)
          throw $RangeError("index out of range");
        reader.len = length;
      }
      if (_end !== $undefined)
        throw $Error("missing end group");
      return message;
    };
    TripDescriptor.decodeDelimited = function(reader) {
      if (!(reader instanceof $Reader))
        reader = new $Reader(reader);
      return this.decode(reader, reader.uint32());
    };
    TripDescriptor.verify = function(message, _depth) {
      if (typeof message !== "object" || message === null)
        return "object expected";
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        return "max depth exceeded";
      if (message.tripId != null && $Object.hasOwnProperty.call(message, "tripId")) {
        if (!$util.isString(message.tripId))
          return "tripId: string expected";
      }
      if (message.routeId != null && $Object.hasOwnProperty.call(message, "routeId")) {
        if (!$util.isString(message.routeId))
          return "routeId: string expected";
      }
      if (message.directionId != null && $Object.hasOwnProperty.call(message, "directionId")) {
        if (!$util.isInteger(message.directionId))
          return "directionId: integer expected";
      }
      if (message.startTime != null && $Object.hasOwnProperty.call(message, "startTime")) {
        if (!$util.isString(message.startTime))
          return "startTime: string expected";
      }
      if (message.startDate != null && $Object.hasOwnProperty.call(message, "startDate")) {
        if (!$util.isString(message.startDate))
          return "startDate: string expected";
      }
      if (message.scheduleRelationship != null && $Object.hasOwnProperty.call(message, "scheduleRelationship"))
        switch (message.scheduleRelationship) {
          default:
            return "scheduleRelationship: enum value expected";
          case 0:
          case 1:
          case 2:
          case 3:
          case 5:
          case 6:
          case 7:
          case 8:
            break;
        }
      if (message.modifiedTrip != null && $Object.hasOwnProperty.call(message, "modifiedTrip")) {
        let error = $root.transit_realtime.TripDescriptor.ModifiedTripSelector.verify(message.modifiedTrip, _depth + 1);
        if (error)
          return "modifiedTrip." + error;
      }
      if (message[".transit_realtime.nyctTripDescriptor"] != null && $Object.hasOwnProperty.call(message, ".transit_realtime.nyctTripDescriptor")) {
        let error = $root.transit_realtime.NyctTripDescriptor.verify(message[".transit_realtime.nyctTripDescriptor"], _depth + 1);
        if (error)
          return ".transit_realtime.nyctTripDescriptor." + error;
      }
      return null;
    };
    TripDescriptor.fromObject = function(object, _depth) {
      if (object instanceof $root.transit_realtime.TripDescriptor)
        return object;
      if (!$util.isObject(object))
        throw $TypeError(".transit_realtime.TripDescriptor: object expected");
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let message = new $root.transit_realtime.TripDescriptor();
      if (object.tripId != null)
        message.tripId = $String(object.tripId);
      if (object.routeId != null)
        message.routeId = $String(object.routeId);
      if (object.directionId != null)
        message.directionId = object.directionId >>> 0;
      if (object.startTime != null)
        message.startTime = $String(object.startTime);
      if (object.startDate != null)
        message.startDate = $String(object.startDate);
      switch (object.scheduleRelationship) {
        case "SCHEDULED":
        case 0:
          message.scheduleRelationship = 0;
          break;
        case "ADDED":
        case 1:
          message.scheduleRelationship = 1;
          break;
        case "UNSCHEDULED":
        case 2:
          message.scheduleRelationship = 2;
          break;
        case "CANCELED":
        case 3:
          message.scheduleRelationship = 3;
          break;
        case "REPLACEMENT":
        case 5:
          message.scheduleRelationship = 5;
          break;
        case "DUPLICATED":
        case 6:
          message.scheduleRelationship = 6;
          break;
        case "DELETED":
        case 7:
          message.scheduleRelationship = 7;
          break;
        case "NEW":
        case 8:
          message.scheduleRelationship = 8;
          break;
        default:
      }
      if (object.modifiedTrip != null) {
        if (!$util.isObject(object.modifiedTrip))
          throw $TypeError(".transit_realtime.TripDescriptor.modifiedTrip: object expected");
        message.modifiedTrip = $root.transit_realtime.TripDescriptor.ModifiedTripSelector.fromObject(object.modifiedTrip, _depth + 1);
      }
      if (object[".transit_realtime.nyctTripDescriptor"] != null) {
        if (!$util.isObject(object[".transit_realtime.nyctTripDescriptor"]))
          throw $TypeError(".transit_realtime.TripDescriptor..transit_realtime.nyctTripDescriptor: object expected");
        message[".transit_realtime.nyctTripDescriptor"] = $root.transit_realtime.NyctTripDescriptor.fromObject(object[".transit_realtime.nyctTripDescriptor"], _depth + 1);
      }
      return message;
    };
    TripDescriptor.toObject = function(message, options, _depth) {
      if (!options)
        options = {};
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let object = {};
      if (options.defaults) {
        object.tripId = "";
        object.startTime = "";
        object.startDate = "";
        object.scheduleRelationship = options.enums === $String ? "SCHEDULED" : 0;
        object.routeId = "";
        object.directionId = 0;
        object.modifiedTrip = null;
        object[".transit_realtime.nyctTripDescriptor"] = null;
      }
      if (message.tripId != null && $Object.hasOwnProperty.call(message, "tripId"))
        object.tripId = message.tripId;
      if (message.startTime != null && $Object.hasOwnProperty.call(message, "startTime"))
        object.startTime = message.startTime;
      if (message.startDate != null && $Object.hasOwnProperty.call(message, "startDate"))
        object.startDate = message.startDate;
      if (message.scheduleRelationship != null && $Object.hasOwnProperty.call(message, "scheduleRelationship"))
        object.scheduleRelationship = options.enums === $String ? $root.transit_realtime.TripDescriptor.ScheduleRelationship[message.scheduleRelationship] === $undefined ? message.scheduleRelationship : $root.transit_realtime.TripDescriptor.ScheduleRelationship[message.scheduleRelationship] : message.scheduleRelationship;
      if (message.routeId != null && $Object.hasOwnProperty.call(message, "routeId"))
        object.routeId = message.routeId;
      if (message.directionId != null && $Object.hasOwnProperty.call(message, "directionId"))
        object.directionId = message.directionId;
      if (message.modifiedTrip != null && $Object.hasOwnProperty.call(message, "modifiedTrip"))
        object.modifiedTrip = $root.transit_realtime.TripDescriptor.ModifiedTripSelector.toObject(message.modifiedTrip, options, _depth + 1);
      if (message[".transit_realtime.nyctTripDescriptor"] != null && $Object.hasOwnProperty.call(message, ".transit_realtime.nyctTripDescriptor"))
        object[".transit_realtime.nyctTripDescriptor"] = $root.transit_realtime.NyctTripDescriptor.toObject(message[".transit_realtime.nyctTripDescriptor"], options, _depth + 1);
      return object;
    };
    TripDescriptor.prototype.toJSON = function() {
      return TripDescriptor.toObject(this, import_minimal.default.util.toJSONOptions);
    };
    TripDescriptor.getTypeUrl = function(prefix) {
      if (prefix === $undefined)
        prefix = "type.googleapis.com";
      return prefix + "/transit_realtime.TripDescriptor";
    };
    TripDescriptor.ScheduleRelationship = (function() {
      const valuesById = $Object.create(null), values = $Object.create(valuesById);
      values[valuesById[0] = "SCHEDULED"] = 0;
      values[valuesById[1] = "ADDED"] = 1;
      values[valuesById[2] = "UNSCHEDULED"] = 2;
      values[valuesById[3] = "CANCELED"] = 3;
      values[valuesById[5] = "REPLACEMENT"] = 5;
      values[valuesById[6] = "DUPLICATED"] = 6;
      values[valuesById[7] = "DELETED"] = 7;
      values[valuesById[8] = "NEW"] = 8;
      return values;
    })();
    TripDescriptor.ModifiedTripSelector = (function() {
      const ModifiedTripSelector = /* @__PURE__ */ __name(function(properties) {
        if (properties) {
          for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
            if (properties[keys[i]] != null && keys[i] !== "__proto__")
              this[keys[i]] = properties[keys[i]];
        }
      }, "ModifiedTripSelector");
      ModifiedTripSelector.prototype.modificationsId = "";
      ModifiedTripSelector.prototype.affectedTripId = "";
      ModifiedTripSelector.prototype.startTime = "";
      ModifiedTripSelector.prototype.startDate = "";
      ModifiedTripSelector.create = function(properties) {
        return new ModifiedTripSelector(properties);
      };
      ModifiedTripSelector.encode = function(message, writer, _depth) {
        if (!writer)
          writer = $Writer.create();
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $util.recursionLimit)
          throw $Error("max depth exceeded");
        if (message.modificationsId != null && $Object.hasOwnProperty.call(message, "modificationsId"))
          writer.uint32(
            /* id 1, wireType 2 =*/
            10
          ).string(message.modificationsId);
        if (message.affectedTripId != null && $Object.hasOwnProperty.call(message, "affectedTripId"))
          writer.uint32(
            /* id 2, wireType 2 =*/
            18
          ).string(message.affectedTripId);
        if (message.startTime != null && $Object.hasOwnProperty.call(message, "startTime"))
          writer.uint32(
            /* id 3, wireType 2 =*/
            26
          ).string(message.startTime);
        if (message.startDate != null && $Object.hasOwnProperty.call(message, "startDate"))
          writer.uint32(
            /* id 4, wireType 2 =*/
            34
          ).string(message.startDate);
        if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
          for (let i = 0; i < message.$unknowns.length; ++i)
            writer.raw(message.$unknowns[i]);
        return writer;
      };
      ModifiedTripSelector.encodeDelimited = function(message, writer) {
        return this.encode(message, (writer || $Writer.create()).fork()).ldelim();
      };
      ModifiedTripSelector.decode = function(reader, length, _end, _depth, _target) {
        if (!(reader instanceof $Reader))
          reader = $Reader.create(reader);
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $Reader.recursionLimit)
          throw $Error("max depth exceeded");
        let end, message;
        if (length === $undefined)
          end = reader.len;
        else {
          end = reader.pos + length;
          if (end > reader.len)
            throw $RangeError("index out of range");
          length = reader.len;
          reader.len = end;
        }
        message = _target || new $root.transit_realtime.TripDescriptor.ModifiedTripSelector();
        while (reader.pos < end) {
          let start = reader.pos;
          let tag = reader.tag();
          if (tag === _end) {
            _end = $undefined;
            break;
          }
          let wireType = tag & 7;
          switch (tag >>>= 3) {
            case 1: {
              if (wireType !== 2)
                break;
              message.modificationsId = reader.string();
              continue;
            }
            case 2: {
              if (wireType !== 2)
                break;
              message.affectedTripId = reader.string();
              continue;
            }
            case 3: {
              if (wireType !== 2)
                break;
              message.startTime = reader.string();
              continue;
            }
            case 4: {
              if (wireType !== 2)
                break;
              message.startDate = reader.string();
              continue;
            }
          }
          reader.skipType(wireType, _depth, tag);
          if (!reader.discardUnknown) {
            $util.makeProp(message, "$unknowns", false);
            (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
          }
        }
        if (length !== $undefined) {
          if (reader.pos !== end)
            throw $RangeError("index out of range");
          reader.len = length;
        }
        if (_end !== $undefined)
          throw $Error("missing end group");
        return message;
      };
      ModifiedTripSelector.decodeDelimited = function(reader) {
        if (!(reader instanceof $Reader))
          reader = new $Reader(reader);
        return this.decode(reader, reader.uint32());
      };
      ModifiedTripSelector.verify = function(message, _depth) {
        if (typeof message !== "object" || message === null)
          return "object expected";
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $util.recursionLimit)
          return "max depth exceeded";
        if (message.modificationsId != null && $Object.hasOwnProperty.call(message, "modificationsId")) {
          if (!$util.isString(message.modificationsId))
            return "modificationsId: string expected";
        }
        if (message.affectedTripId != null && $Object.hasOwnProperty.call(message, "affectedTripId")) {
          if (!$util.isString(message.affectedTripId))
            return "affectedTripId: string expected";
        }
        if (message.startTime != null && $Object.hasOwnProperty.call(message, "startTime")) {
          if (!$util.isString(message.startTime))
            return "startTime: string expected";
        }
        if (message.startDate != null && $Object.hasOwnProperty.call(message, "startDate")) {
          if (!$util.isString(message.startDate))
            return "startDate: string expected";
        }
        return null;
      };
      ModifiedTripSelector.fromObject = function(object, _depth) {
        if (object instanceof $root.transit_realtime.TripDescriptor.ModifiedTripSelector)
          return object;
        if (!$util.isObject(object))
          throw $TypeError(".transit_realtime.TripDescriptor.ModifiedTripSelector: object expected");
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $util.recursionLimit)
          throw $Error("max depth exceeded");
        let message = new $root.transit_realtime.TripDescriptor.ModifiedTripSelector();
        if (object.modificationsId != null)
          message.modificationsId = $String(object.modificationsId);
        if (object.affectedTripId != null)
          message.affectedTripId = $String(object.affectedTripId);
        if (object.startTime != null)
          message.startTime = $String(object.startTime);
        if (object.startDate != null)
          message.startDate = $String(object.startDate);
        return message;
      };
      ModifiedTripSelector.toObject = function(message, options, _depth) {
        if (!options)
          options = {};
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $util.recursionLimit)
          throw $Error("max depth exceeded");
        let object = {};
        if (options.defaults) {
          object.modificationsId = "";
          object.affectedTripId = "";
          object.startTime = "";
          object.startDate = "";
        }
        if (message.modificationsId != null && $Object.hasOwnProperty.call(message, "modificationsId"))
          object.modificationsId = message.modificationsId;
        if (message.affectedTripId != null && $Object.hasOwnProperty.call(message, "affectedTripId"))
          object.affectedTripId = message.affectedTripId;
        if (message.startTime != null && $Object.hasOwnProperty.call(message, "startTime"))
          object.startTime = message.startTime;
        if (message.startDate != null && $Object.hasOwnProperty.call(message, "startDate"))
          object.startDate = message.startDate;
        return object;
      };
      ModifiedTripSelector.prototype.toJSON = function() {
        return ModifiedTripSelector.toObject(this, import_minimal.default.util.toJSONOptions);
      };
      ModifiedTripSelector.getTypeUrl = function(prefix) {
        if (prefix === $undefined)
          prefix = "type.googleapis.com";
        return prefix + "/transit_realtime.TripDescriptor.ModifiedTripSelector";
      };
      return ModifiedTripSelector;
    })();
    return TripDescriptor;
  })();
  transit_realtime2.VehicleDescriptor = (function() {
    const VehicleDescriptor = /* @__PURE__ */ __name(function(properties) {
      if (properties) {
        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
          if (properties[keys[i]] != null && keys[i] !== "__proto__")
            this[keys[i]] = properties[keys[i]];
      }
    }, "VehicleDescriptor");
    VehicleDescriptor.prototype.id = "";
    VehicleDescriptor.prototype.label = "";
    VehicleDescriptor.prototype.licensePlate = "";
    VehicleDescriptor.prototype.wheelchairAccessible = 0;
    VehicleDescriptor.create = function(properties) {
      return new VehicleDescriptor(properties);
    };
    VehicleDescriptor.encode = function(message, writer, _depth) {
      if (!writer)
        writer = $Writer.create();
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      if (message.id != null && $Object.hasOwnProperty.call(message, "id"))
        writer.uint32(
          /* id 1, wireType 2 =*/
          10
        ).string(message.id);
      if (message.label != null && $Object.hasOwnProperty.call(message, "label"))
        writer.uint32(
          /* id 2, wireType 2 =*/
          18
        ).string(message.label);
      if (message.licensePlate != null && $Object.hasOwnProperty.call(message, "licensePlate"))
        writer.uint32(
          /* id 3, wireType 2 =*/
          26
        ).string(message.licensePlate);
      if (message.wheelchairAccessible != null && $Object.hasOwnProperty.call(message, "wheelchairAccessible"))
        writer.uint32(
          /* id 4, wireType 0 =*/
          32
        ).int32(message.wheelchairAccessible);
      if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
        for (let i = 0; i < message.$unknowns.length; ++i)
          writer.raw(message.$unknowns[i]);
      return writer;
    };
    VehicleDescriptor.encodeDelimited = function(message, writer) {
      return this.encode(message, (writer || $Writer.create()).fork()).ldelim();
    };
    VehicleDescriptor.decode = function(reader, length, _end, _depth, _target) {
      if (!(reader instanceof $Reader))
        reader = $Reader.create(reader);
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $Reader.recursionLimit)
        throw $Error("max depth exceeded");
      let end, message, value;
      if (length === $undefined)
        end = reader.len;
      else {
        end = reader.pos + length;
        if (end > reader.len)
          throw $RangeError("index out of range");
        length = reader.len;
        reader.len = end;
      }
      message = _target || new $root.transit_realtime.VehicleDescriptor();
      while (reader.pos < end) {
        let start = reader.pos;
        let tag = reader.tag();
        if (tag === _end) {
          _end = $undefined;
          break;
        }
        let wireType = tag & 7;
        switch (tag >>>= 3) {
          case 1: {
            if (wireType !== 2)
              break;
            message.id = reader.string();
            continue;
          }
          case 2: {
            if (wireType !== 2)
              break;
            message.label = reader.string();
            continue;
          }
          case 3: {
            if (wireType !== 2)
              break;
            message.licensePlate = reader.string();
            continue;
          }
          case 4: {
            if (wireType !== 0)
              break;
            value = reader.int32();
            if ($root.transit_realtime.VehicleDescriptor.WheelchairAccessible[value] !== $undefined)
              message.wheelchairAccessible = value;
            else if (!reader.discardUnknown) {
              $util.makeProp(message, "$unknowns", false);
              (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
            }
            continue;
          }
        }
        reader.skipType(wireType, _depth, tag);
        if (!reader.discardUnknown) {
          $util.makeProp(message, "$unknowns", false);
          (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
        }
      }
      if (length !== $undefined) {
        if (reader.pos !== end)
          throw $RangeError("index out of range");
        reader.len = length;
      }
      if (_end !== $undefined)
        throw $Error("missing end group");
      return message;
    };
    VehicleDescriptor.decodeDelimited = function(reader) {
      if (!(reader instanceof $Reader))
        reader = new $Reader(reader);
      return this.decode(reader, reader.uint32());
    };
    VehicleDescriptor.verify = function(message, _depth) {
      if (typeof message !== "object" || message === null)
        return "object expected";
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        return "max depth exceeded";
      if (message.id != null && $Object.hasOwnProperty.call(message, "id")) {
        if (!$util.isString(message.id))
          return "id: string expected";
      }
      if (message.label != null && $Object.hasOwnProperty.call(message, "label")) {
        if (!$util.isString(message.label))
          return "label: string expected";
      }
      if (message.licensePlate != null && $Object.hasOwnProperty.call(message, "licensePlate")) {
        if (!$util.isString(message.licensePlate))
          return "licensePlate: string expected";
      }
      if (message.wheelchairAccessible != null && $Object.hasOwnProperty.call(message, "wheelchairAccessible"))
        switch (message.wheelchairAccessible) {
          default:
            return "wheelchairAccessible: enum value expected";
          case 0:
          case 1:
          case 2:
          case 3:
            break;
        }
      return null;
    };
    VehicleDescriptor.fromObject = function(object, _depth) {
      if (object instanceof $root.transit_realtime.VehicleDescriptor)
        return object;
      if (!$util.isObject(object))
        throw $TypeError(".transit_realtime.VehicleDescriptor: object expected");
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let message = new $root.transit_realtime.VehicleDescriptor();
      if (object.id != null)
        message.id = $String(object.id);
      if (object.label != null)
        message.label = $String(object.label);
      if (object.licensePlate != null)
        message.licensePlate = $String(object.licensePlate);
      switch (object.wheelchairAccessible) {
        case "NO_VALUE":
        case 0:
          message.wheelchairAccessible = 0;
          break;
        case "UNKNOWN":
        case 1:
          message.wheelchairAccessible = 1;
          break;
        case "WHEELCHAIR_ACCESSIBLE":
        case 2:
          message.wheelchairAccessible = 2;
          break;
        case "WHEELCHAIR_INACCESSIBLE":
        case 3:
          message.wheelchairAccessible = 3;
          break;
        default:
      }
      return message;
    };
    VehicleDescriptor.toObject = function(message, options, _depth) {
      if (!options)
        options = {};
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let object = {};
      if (options.defaults) {
        object.id = "";
        object.label = "";
        object.licensePlate = "";
        object.wheelchairAccessible = options.enums === $String ? "NO_VALUE" : 0;
      }
      if (message.id != null && $Object.hasOwnProperty.call(message, "id"))
        object.id = message.id;
      if (message.label != null && $Object.hasOwnProperty.call(message, "label"))
        object.label = message.label;
      if (message.licensePlate != null && $Object.hasOwnProperty.call(message, "licensePlate"))
        object.licensePlate = message.licensePlate;
      if (message.wheelchairAccessible != null && $Object.hasOwnProperty.call(message, "wheelchairAccessible"))
        object.wheelchairAccessible = options.enums === $String ? $root.transit_realtime.VehicleDescriptor.WheelchairAccessible[message.wheelchairAccessible] === $undefined ? message.wheelchairAccessible : $root.transit_realtime.VehicleDescriptor.WheelchairAccessible[message.wheelchairAccessible] : message.wheelchairAccessible;
      return object;
    };
    VehicleDescriptor.prototype.toJSON = function() {
      return VehicleDescriptor.toObject(this, import_minimal.default.util.toJSONOptions);
    };
    VehicleDescriptor.getTypeUrl = function(prefix) {
      if (prefix === $undefined)
        prefix = "type.googleapis.com";
      return prefix + "/transit_realtime.VehicleDescriptor";
    };
    VehicleDescriptor.WheelchairAccessible = (function() {
      const valuesById = $Object.create(null), values = $Object.create(valuesById);
      values[valuesById[0] = "NO_VALUE"] = 0;
      values[valuesById[1] = "UNKNOWN"] = 1;
      values[valuesById[2] = "WHEELCHAIR_ACCESSIBLE"] = 2;
      values[valuesById[3] = "WHEELCHAIR_INACCESSIBLE"] = 3;
      return values;
    })();
    return VehicleDescriptor;
  })();
  transit_realtime2.EntitySelector = (function() {
    const EntitySelector = /* @__PURE__ */ __name(function(properties) {
      if (properties) {
        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
          if (properties[keys[i]] != null && keys[i] !== "__proto__")
            this[keys[i]] = properties[keys[i]];
      }
    }, "EntitySelector");
    EntitySelector.prototype.agencyId = "";
    EntitySelector.prototype.routeId = "";
    EntitySelector.prototype.routeType = 0;
    EntitySelector.prototype.trip = null;
    EntitySelector.prototype.stopId = "";
    EntitySelector.prototype.directionId = 0;
    EntitySelector.prototype[".transit_realtime.mercuryEntitySelector"] = null;
    EntitySelector.create = function(properties) {
      return new EntitySelector(properties);
    };
    EntitySelector.encode = function(message, writer, _depth) {
      if (!writer)
        writer = $Writer.create();
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      if (message.agencyId != null && $Object.hasOwnProperty.call(message, "agencyId"))
        writer.uint32(
          /* id 1, wireType 2 =*/
          10
        ).string(message.agencyId);
      if (message.routeId != null && $Object.hasOwnProperty.call(message, "routeId"))
        writer.uint32(
          /* id 2, wireType 2 =*/
          18
        ).string(message.routeId);
      if (message.routeType != null && $Object.hasOwnProperty.call(message, "routeType"))
        writer.uint32(
          /* id 3, wireType 0 =*/
          24
        ).int32(message.routeType);
      if (message.trip != null && $Object.hasOwnProperty.call(message, "trip"))
        $root.transit_realtime.TripDescriptor.encode(message.trip, writer.uint32(
          /* id 4, wireType 2 =*/
          34
        ).fork(), _depth + 1).ldelim();
      if (message.stopId != null && $Object.hasOwnProperty.call(message, "stopId"))
        writer.uint32(
          /* id 5, wireType 2 =*/
          42
        ).string(message.stopId);
      if (message.directionId != null && $Object.hasOwnProperty.call(message, "directionId"))
        writer.uint32(
          /* id 6, wireType 0 =*/
          48
        ).uint32(message.directionId);
      if (message[".transit_realtime.mercuryEntitySelector"] != null && $Object.hasOwnProperty.call(message, ".transit_realtime.mercuryEntitySelector"))
        $root.transit_realtime.MercuryEntitySelector.encode(message[".transit_realtime.mercuryEntitySelector"], writer.uint32(
          /* id 1001, wireType 2 =*/
          8010
        ).fork(), _depth + 1).ldelim();
      if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
        for (let i = 0; i < message.$unknowns.length; ++i)
          writer.raw(message.$unknowns[i]);
      return writer;
    };
    EntitySelector.encodeDelimited = function(message, writer) {
      return this.encode(message, (writer || $Writer.create()).fork()).ldelim();
    };
    EntitySelector.decode = function(reader, length, _end, _depth, _target) {
      if (!(reader instanceof $Reader))
        reader = $Reader.create(reader);
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $Reader.recursionLimit)
        throw $Error("max depth exceeded");
      let end, message;
      if (length === $undefined)
        end = reader.len;
      else {
        end = reader.pos + length;
        if (end > reader.len)
          throw $RangeError("index out of range");
        length = reader.len;
        reader.len = end;
      }
      message = _target || new $root.transit_realtime.EntitySelector();
      while (reader.pos < end) {
        let start = reader.pos;
        let tag = reader.tag();
        if (tag === _end) {
          _end = $undefined;
          break;
        }
        let wireType = tag & 7;
        switch (tag >>>= 3) {
          case 1: {
            if (wireType !== 2)
              break;
            message.agencyId = reader.string();
            continue;
          }
          case 2: {
            if (wireType !== 2)
              break;
            message.routeId = reader.string();
            continue;
          }
          case 3: {
            if (wireType !== 0)
              break;
            message.routeType = reader.int32();
            continue;
          }
          case 4: {
            if (wireType !== 2)
              break;
            message.trip = $root.transit_realtime.TripDescriptor.decode(reader, reader.uint32(), $undefined, _depth + 1, message.trip);
            continue;
          }
          case 5: {
            if (wireType !== 2)
              break;
            message.stopId = reader.string();
            continue;
          }
          case 6: {
            if (wireType !== 0)
              break;
            message.directionId = reader.uint32();
            continue;
          }
          case 1001: {
            if (wireType !== 2)
              break;
            message[".transit_realtime.mercuryEntitySelector"] = $root.transit_realtime.MercuryEntitySelector.decode(reader, reader.uint32(), $undefined, _depth + 1, message[".transit_realtime.mercuryEntitySelector"]);
            continue;
          }
        }
        reader.skipType(wireType, _depth, tag);
        if (!reader.discardUnknown) {
          $util.makeProp(message, "$unknowns", false);
          (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
        }
      }
      if (length !== $undefined) {
        if (reader.pos !== end)
          throw $RangeError("index out of range");
        reader.len = length;
      }
      if (_end !== $undefined)
        throw $Error("missing end group");
      return message;
    };
    EntitySelector.decodeDelimited = function(reader) {
      if (!(reader instanceof $Reader))
        reader = new $Reader(reader);
      return this.decode(reader, reader.uint32());
    };
    EntitySelector.verify = function(message, _depth) {
      if (typeof message !== "object" || message === null)
        return "object expected";
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        return "max depth exceeded";
      if (message.agencyId != null && $Object.hasOwnProperty.call(message, "agencyId")) {
        if (!$util.isString(message.agencyId))
          return "agencyId: string expected";
      }
      if (message.routeId != null && $Object.hasOwnProperty.call(message, "routeId")) {
        if (!$util.isString(message.routeId))
          return "routeId: string expected";
      }
      if (message.routeType != null && $Object.hasOwnProperty.call(message, "routeType")) {
        if (!$util.isInteger(message.routeType))
          return "routeType: integer expected";
      }
      if (message.trip != null && $Object.hasOwnProperty.call(message, "trip")) {
        let error = $root.transit_realtime.TripDescriptor.verify(message.trip, _depth + 1);
        if (error)
          return "trip." + error;
      }
      if (message.stopId != null && $Object.hasOwnProperty.call(message, "stopId")) {
        if (!$util.isString(message.stopId))
          return "stopId: string expected";
      }
      if (message.directionId != null && $Object.hasOwnProperty.call(message, "directionId")) {
        if (!$util.isInteger(message.directionId))
          return "directionId: integer expected";
      }
      if (message[".transit_realtime.mercuryEntitySelector"] != null && $Object.hasOwnProperty.call(message, ".transit_realtime.mercuryEntitySelector")) {
        let error = $root.transit_realtime.MercuryEntitySelector.verify(message[".transit_realtime.mercuryEntitySelector"], _depth + 1);
        if (error)
          return ".transit_realtime.mercuryEntitySelector." + error;
      }
      return null;
    };
    EntitySelector.fromObject = function(object, _depth) {
      if (object instanceof $root.transit_realtime.EntitySelector)
        return object;
      if (!$util.isObject(object))
        throw $TypeError(".transit_realtime.EntitySelector: object expected");
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let message = new $root.transit_realtime.EntitySelector();
      if (object.agencyId != null)
        message.agencyId = $String(object.agencyId);
      if (object.routeId != null)
        message.routeId = $String(object.routeId);
      if (object.routeType != null)
        message.routeType = object.routeType | 0;
      if (object.trip != null) {
        if (!$util.isObject(object.trip))
          throw $TypeError(".transit_realtime.EntitySelector.trip: object expected");
        message.trip = $root.transit_realtime.TripDescriptor.fromObject(object.trip, _depth + 1);
      }
      if (object.stopId != null)
        message.stopId = $String(object.stopId);
      if (object.directionId != null)
        message.directionId = object.directionId >>> 0;
      if (object[".transit_realtime.mercuryEntitySelector"] != null) {
        if (!$util.isObject(object[".transit_realtime.mercuryEntitySelector"]))
          throw $TypeError(".transit_realtime.EntitySelector..transit_realtime.mercuryEntitySelector: object expected");
        message[".transit_realtime.mercuryEntitySelector"] = $root.transit_realtime.MercuryEntitySelector.fromObject(object[".transit_realtime.mercuryEntitySelector"], _depth + 1);
      }
      return message;
    };
    EntitySelector.toObject = function(message, options, _depth) {
      if (!options)
        options = {};
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let object = {};
      if (options.defaults) {
        object.agencyId = "";
        object.routeId = "";
        object.routeType = 0;
        object.trip = null;
        object.stopId = "";
        object.directionId = 0;
        object[".transit_realtime.mercuryEntitySelector"] = null;
      }
      if (message.agencyId != null && $Object.hasOwnProperty.call(message, "agencyId"))
        object.agencyId = message.agencyId;
      if (message.routeId != null && $Object.hasOwnProperty.call(message, "routeId"))
        object.routeId = message.routeId;
      if (message.routeType != null && $Object.hasOwnProperty.call(message, "routeType"))
        object.routeType = message.routeType;
      if (message.trip != null && $Object.hasOwnProperty.call(message, "trip"))
        object.trip = $root.transit_realtime.TripDescriptor.toObject(message.trip, options, _depth + 1);
      if (message.stopId != null && $Object.hasOwnProperty.call(message, "stopId"))
        object.stopId = message.stopId;
      if (message.directionId != null && $Object.hasOwnProperty.call(message, "directionId"))
        object.directionId = message.directionId;
      if (message[".transit_realtime.mercuryEntitySelector"] != null && $Object.hasOwnProperty.call(message, ".transit_realtime.mercuryEntitySelector"))
        object[".transit_realtime.mercuryEntitySelector"] = $root.transit_realtime.MercuryEntitySelector.toObject(message[".transit_realtime.mercuryEntitySelector"], options, _depth + 1);
      return object;
    };
    EntitySelector.prototype.toJSON = function() {
      return EntitySelector.toObject(this, import_minimal.default.util.toJSONOptions);
    };
    EntitySelector.getTypeUrl = function(prefix) {
      if (prefix === $undefined)
        prefix = "type.googleapis.com";
      return prefix + "/transit_realtime.EntitySelector";
    };
    return EntitySelector;
  })();
  transit_realtime2.TranslatedString = (function() {
    const TranslatedString = /* @__PURE__ */ __name(function(properties) {
      this.translation = [];
      if (properties) {
        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
          if (properties[keys[i]] != null && keys[i] !== "__proto__")
            this[keys[i]] = properties[keys[i]];
      }
    }, "TranslatedString");
    TranslatedString.prototype.translation = $util.emptyArray;
    TranslatedString.create = function(properties) {
      return new TranslatedString(properties);
    };
    TranslatedString.encode = function(message, writer, _depth) {
      if (!writer)
        writer = $Writer.create();
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      if (message.translation != null && message.translation.length)
        for (let i = 0; i < message.translation.length; ++i)
          $root.transit_realtime.TranslatedString.Translation.encode(message.translation[i], writer.uint32(
            /* id 1, wireType 2 =*/
            10
          ).fork(), _depth + 1).ldelim();
      if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
        for (let i = 0; i < message.$unknowns.length; ++i)
          writer.raw(message.$unknowns[i]);
      return writer;
    };
    TranslatedString.encodeDelimited = function(message, writer) {
      return this.encode(message, (writer || $Writer.create()).fork()).ldelim();
    };
    TranslatedString.decode = function(reader, length, _end, _depth, _target) {
      if (!(reader instanceof $Reader))
        reader = $Reader.create(reader);
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $Reader.recursionLimit)
        throw $Error("max depth exceeded");
      let end, message;
      if (length === $undefined)
        end = reader.len;
      else {
        end = reader.pos + length;
        if (end > reader.len)
          throw $RangeError("index out of range");
        length = reader.len;
        reader.len = end;
      }
      message = _target || new $root.transit_realtime.TranslatedString();
      while (reader.pos < end) {
        let start = reader.pos;
        let tag = reader.tag();
        if (tag === _end) {
          _end = $undefined;
          break;
        }
        let wireType = tag & 7;
        switch (tag >>>= 3) {
          case 1: {
            if (wireType !== 2)
              break;
            if (!(message.translation && message.translation.length))
              message.translation = [];
            message.translation.push($root.transit_realtime.TranslatedString.Translation.decode(reader, reader.uint32(), $undefined, _depth + 1));
            continue;
          }
        }
        reader.skipType(wireType, _depth, tag);
        if (!reader.discardUnknown) {
          $util.makeProp(message, "$unknowns", false);
          (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
        }
      }
      if (length !== $undefined) {
        if (reader.pos !== end)
          throw $RangeError("index out of range");
        reader.len = length;
      }
      if (_end !== $undefined)
        throw $Error("missing end group");
      return message;
    };
    TranslatedString.decodeDelimited = function(reader) {
      if (!(reader instanceof $Reader))
        reader = new $Reader(reader);
      return this.decode(reader, reader.uint32());
    };
    TranslatedString.verify = function(message, _depth) {
      if (typeof message !== "object" || message === null)
        return "object expected";
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        return "max depth exceeded";
      if (message.translation != null && $Object.hasOwnProperty.call(message, "translation")) {
        if (!$Array.isArray(message.translation))
          return "translation: array expected";
        for (let i = 0; i < message.translation.length; ++i) {
          let error = $root.transit_realtime.TranslatedString.Translation.verify(message.translation[i], _depth + 1);
          if (error)
            return "translation." + error;
        }
      }
      return null;
    };
    TranslatedString.fromObject = function(object, _depth) {
      if (object instanceof $root.transit_realtime.TranslatedString)
        return object;
      if (!$util.isObject(object))
        throw $TypeError(".transit_realtime.TranslatedString: object expected");
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let message = new $root.transit_realtime.TranslatedString();
      if (object.translation) {
        if (!$Array.isArray(object.translation))
          throw $TypeError(".transit_realtime.TranslatedString.translation: array expected");
        message.translation = $Array(object.translation.length);
        for (let i = 0; i < object.translation.length; ++i) {
          if (!$util.isObject(object.translation[i]))
            throw $TypeError(".transit_realtime.TranslatedString.translation: object expected");
          message.translation[i] = $root.transit_realtime.TranslatedString.Translation.fromObject(object.translation[i], _depth + 1);
        }
      }
      return message;
    };
    TranslatedString.toObject = function(message, options, _depth) {
      if (!options)
        options = {};
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let object = {};
      if (options.arrays || options.defaults)
        object.translation = [];
      if (message.translation && message.translation.length) {
        object.translation = $Array(message.translation.length);
        for (let j = 0; j < message.translation.length; ++j)
          object.translation[j] = $root.transit_realtime.TranslatedString.Translation.toObject(message.translation[j], options, _depth + 1);
      }
      return object;
    };
    TranslatedString.prototype.toJSON = function() {
      return TranslatedString.toObject(this, import_minimal.default.util.toJSONOptions);
    };
    TranslatedString.getTypeUrl = function(prefix) {
      if (prefix === $undefined)
        prefix = "type.googleapis.com";
      return prefix + "/transit_realtime.TranslatedString";
    };
    TranslatedString.Translation = (function() {
      const Translation = /* @__PURE__ */ __name(function(properties) {
        if (properties) {
          for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
            if (properties[keys[i]] != null && keys[i] !== "__proto__")
              this[keys[i]] = properties[keys[i]];
        }
      }, "Translation");
      Translation.prototype.text = "";
      Translation.prototype.language = "";
      Translation.create = function(properties) {
        return new Translation(properties);
      };
      Translation.encode = function(message, writer, _depth) {
        if (!writer)
          writer = $Writer.create();
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $util.recursionLimit)
          throw $Error("max depth exceeded");
        writer.uint32(
          /* id 1, wireType 2 =*/
          10
        ).string(message.text);
        if (message.language != null && $Object.hasOwnProperty.call(message, "language"))
          writer.uint32(
            /* id 2, wireType 2 =*/
            18
          ).string(message.language);
        if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
          for (let i = 0; i < message.$unknowns.length; ++i)
            writer.raw(message.$unknowns[i]);
        return writer;
      };
      Translation.encodeDelimited = function(message, writer) {
        return this.encode(message, (writer || $Writer.create()).fork()).ldelim();
      };
      Translation.decode = function(reader, length, _end, _depth, _target) {
        if (!(reader instanceof $Reader))
          reader = $Reader.create(reader);
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $Reader.recursionLimit)
          throw $Error("max depth exceeded");
        let end, message;
        if (length === $undefined)
          end = reader.len;
        else {
          end = reader.pos + length;
          if (end > reader.len)
            throw $RangeError("index out of range");
          length = reader.len;
          reader.len = end;
        }
        message = _target || new $root.transit_realtime.TranslatedString.Translation();
        while (reader.pos < end) {
          let start = reader.pos;
          let tag = reader.tag();
          if (tag === _end) {
            _end = $undefined;
            break;
          }
          let wireType = tag & 7;
          switch (tag >>>= 3) {
            case 1: {
              if (wireType !== 2)
                break;
              message.text = reader.string();
              continue;
            }
            case 2: {
              if (wireType !== 2)
                break;
              message.language = reader.string();
              continue;
            }
          }
          reader.skipType(wireType, _depth, tag);
          if (!reader.discardUnknown) {
            $util.makeProp(message, "$unknowns", false);
            (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
          }
        }
        if (length !== $undefined) {
          if (reader.pos !== end)
            throw $RangeError("index out of range");
          reader.len = length;
        }
        if (_end !== $undefined)
          throw $Error("missing end group");
        if (!$Object.hasOwnProperty.call(message, "text"))
          throw $util.ProtocolError("missing required 'text'", { instance: message });
        return message;
      };
      Translation.decodeDelimited = function(reader) {
        if (!(reader instanceof $Reader))
          reader = new $Reader(reader);
        return this.decode(reader, reader.uint32());
      };
      Translation.verify = function(message, _depth) {
        if (typeof message !== "object" || message === null)
          return "object expected";
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $util.recursionLimit)
          return "max depth exceeded";
        if (!$util.isString(message.text))
          return "text: string expected";
        if (message.language != null && $Object.hasOwnProperty.call(message, "language")) {
          if (!$util.isString(message.language))
            return "language: string expected";
        }
        return null;
      };
      Translation.fromObject = function(object, _depth) {
        if (object instanceof $root.transit_realtime.TranslatedString.Translation)
          return object;
        if (!$util.isObject(object))
          throw $TypeError(".transit_realtime.TranslatedString.Translation: object expected");
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $util.recursionLimit)
          throw $Error("max depth exceeded");
        let message = new $root.transit_realtime.TranslatedString.Translation();
        if (object.text != null)
          message.text = $String(object.text);
        if (object.language != null)
          message.language = $String(object.language);
        return message;
      };
      Translation.toObject = function(message, options, _depth) {
        if (!options)
          options = {};
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $util.recursionLimit)
          throw $Error("max depth exceeded");
        let object = {};
        if (options.defaults) {
          object.text = "";
          object.language = "";
        }
        if (message.text != null && $Object.hasOwnProperty.call(message, "text"))
          object.text = message.text;
        if (message.language != null && $Object.hasOwnProperty.call(message, "language"))
          object.language = message.language;
        return object;
      };
      Translation.prototype.toJSON = function() {
        return Translation.toObject(this, import_minimal.default.util.toJSONOptions);
      };
      Translation.getTypeUrl = function(prefix) {
        if (prefix === $undefined)
          prefix = "type.googleapis.com";
        return prefix + "/transit_realtime.TranslatedString.Translation";
      };
      return Translation;
    })();
    return TranslatedString;
  })();
  transit_realtime2.TranslatedImage = (function() {
    const TranslatedImage = /* @__PURE__ */ __name(function(properties) {
      this.localizedImage = [];
      if (properties) {
        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
          if (properties[keys[i]] != null && keys[i] !== "__proto__")
            this[keys[i]] = properties[keys[i]];
      }
    }, "TranslatedImage");
    TranslatedImage.prototype.localizedImage = $util.emptyArray;
    TranslatedImage.create = function(properties) {
      return new TranslatedImage(properties);
    };
    TranslatedImage.encode = function(message, writer, _depth) {
      if (!writer)
        writer = $Writer.create();
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      if (message.localizedImage != null && message.localizedImage.length)
        for (let i = 0; i < message.localizedImage.length; ++i)
          $root.transit_realtime.TranslatedImage.LocalizedImage.encode(message.localizedImage[i], writer.uint32(
            /* id 1, wireType 2 =*/
            10
          ).fork(), _depth + 1).ldelim();
      if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
        for (let i = 0; i < message.$unknowns.length; ++i)
          writer.raw(message.$unknowns[i]);
      return writer;
    };
    TranslatedImage.encodeDelimited = function(message, writer) {
      return this.encode(message, (writer || $Writer.create()).fork()).ldelim();
    };
    TranslatedImage.decode = function(reader, length, _end, _depth, _target) {
      if (!(reader instanceof $Reader))
        reader = $Reader.create(reader);
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $Reader.recursionLimit)
        throw $Error("max depth exceeded");
      let end, message;
      if (length === $undefined)
        end = reader.len;
      else {
        end = reader.pos + length;
        if (end > reader.len)
          throw $RangeError("index out of range");
        length = reader.len;
        reader.len = end;
      }
      message = _target || new $root.transit_realtime.TranslatedImage();
      while (reader.pos < end) {
        let start = reader.pos;
        let tag = reader.tag();
        if (tag === _end) {
          _end = $undefined;
          break;
        }
        let wireType = tag & 7;
        switch (tag >>>= 3) {
          case 1: {
            if (wireType !== 2)
              break;
            if (!(message.localizedImage && message.localizedImage.length))
              message.localizedImage = [];
            message.localizedImage.push($root.transit_realtime.TranslatedImage.LocalizedImage.decode(reader, reader.uint32(), $undefined, _depth + 1));
            continue;
          }
        }
        reader.skipType(wireType, _depth, tag);
        if (!reader.discardUnknown) {
          $util.makeProp(message, "$unknowns", false);
          (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
        }
      }
      if (length !== $undefined) {
        if (reader.pos !== end)
          throw $RangeError("index out of range");
        reader.len = length;
      }
      if (_end !== $undefined)
        throw $Error("missing end group");
      return message;
    };
    TranslatedImage.decodeDelimited = function(reader) {
      if (!(reader instanceof $Reader))
        reader = new $Reader(reader);
      return this.decode(reader, reader.uint32());
    };
    TranslatedImage.verify = function(message, _depth) {
      if (typeof message !== "object" || message === null)
        return "object expected";
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        return "max depth exceeded";
      if (message.localizedImage != null && $Object.hasOwnProperty.call(message, "localizedImage")) {
        if (!$Array.isArray(message.localizedImage))
          return "localizedImage: array expected";
        for (let i = 0; i < message.localizedImage.length; ++i) {
          let error = $root.transit_realtime.TranslatedImage.LocalizedImage.verify(message.localizedImage[i], _depth + 1);
          if (error)
            return "localizedImage." + error;
        }
      }
      return null;
    };
    TranslatedImage.fromObject = function(object, _depth) {
      if (object instanceof $root.transit_realtime.TranslatedImage)
        return object;
      if (!$util.isObject(object))
        throw $TypeError(".transit_realtime.TranslatedImage: object expected");
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let message = new $root.transit_realtime.TranslatedImage();
      if (object.localizedImage) {
        if (!$Array.isArray(object.localizedImage))
          throw $TypeError(".transit_realtime.TranslatedImage.localizedImage: array expected");
        message.localizedImage = $Array(object.localizedImage.length);
        for (let i = 0; i < object.localizedImage.length; ++i) {
          if (!$util.isObject(object.localizedImage[i]))
            throw $TypeError(".transit_realtime.TranslatedImage.localizedImage: object expected");
          message.localizedImage[i] = $root.transit_realtime.TranslatedImage.LocalizedImage.fromObject(object.localizedImage[i], _depth + 1);
        }
      }
      return message;
    };
    TranslatedImage.toObject = function(message, options, _depth) {
      if (!options)
        options = {};
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let object = {};
      if (options.arrays || options.defaults)
        object.localizedImage = [];
      if (message.localizedImage && message.localizedImage.length) {
        object.localizedImage = $Array(message.localizedImage.length);
        for (let j = 0; j < message.localizedImage.length; ++j)
          object.localizedImage[j] = $root.transit_realtime.TranslatedImage.LocalizedImage.toObject(message.localizedImage[j], options, _depth + 1);
      }
      return object;
    };
    TranslatedImage.prototype.toJSON = function() {
      return TranslatedImage.toObject(this, import_minimal.default.util.toJSONOptions);
    };
    TranslatedImage.getTypeUrl = function(prefix) {
      if (prefix === $undefined)
        prefix = "type.googleapis.com";
      return prefix + "/transit_realtime.TranslatedImage";
    };
    TranslatedImage.LocalizedImage = (function() {
      const LocalizedImage = /* @__PURE__ */ __name(function(properties) {
        if (properties) {
          for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
            if (properties[keys[i]] != null && keys[i] !== "__proto__")
              this[keys[i]] = properties[keys[i]];
        }
      }, "LocalizedImage");
      LocalizedImage.prototype.url = "";
      LocalizedImage.prototype.mediaType = "";
      LocalizedImage.prototype.language = "";
      LocalizedImage.create = function(properties) {
        return new LocalizedImage(properties);
      };
      LocalizedImage.encode = function(message, writer, _depth) {
        if (!writer)
          writer = $Writer.create();
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $util.recursionLimit)
          throw $Error("max depth exceeded");
        writer.uint32(
          /* id 1, wireType 2 =*/
          10
        ).string(message.url);
        writer.uint32(
          /* id 2, wireType 2 =*/
          18
        ).string(message.mediaType);
        if (message.language != null && $Object.hasOwnProperty.call(message, "language"))
          writer.uint32(
            /* id 3, wireType 2 =*/
            26
          ).string(message.language);
        if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
          for (let i = 0; i < message.$unknowns.length; ++i)
            writer.raw(message.$unknowns[i]);
        return writer;
      };
      LocalizedImage.encodeDelimited = function(message, writer) {
        return this.encode(message, (writer || $Writer.create()).fork()).ldelim();
      };
      LocalizedImage.decode = function(reader, length, _end, _depth, _target) {
        if (!(reader instanceof $Reader))
          reader = $Reader.create(reader);
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $Reader.recursionLimit)
          throw $Error("max depth exceeded");
        let end, message;
        if (length === $undefined)
          end = reader.len;
        else {
          end = reader.pos + length;
          if (end > reader.len)
            throw $RangeError("index out of range");
          length = reader.len;
          reader.len = end;
        }
        message = _target || new $root.transit_realtime.TranslatedImage.LocalizedImage();
        while (reader.pos < end) {
          let start = reader.pos;
          let tag = reader.tag();
          if (tag === _end) {
            _end = $undefined;
            break;
          }
          let wireType = tag & 7;
          switch (tag >>>= 3) {
            case 1: {
              if (wireType !== 2)
                break;
              message.url = reader.string();
              continue;
            }
            case 2: {
              if (wireType !== 2)
                break;
              message.mediaType = reader.string();
              continue;
            }
            case 3: {
              if (wireType !== 2)
                break;
              message.language = reader.string();
              continue;
            }
          }
          reader.skipType(wireType, _depth, tag);
          if (!reader.discardUnknown) {
            $util.makeProp(message, "$unknowns", false);
            (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
          }
        }
        if (length !== $undefined) {
          if (reader.pos !== end)
            throw $RangeError("index out of range");
          reader.len = length;
        }
        if (_end !== $undefined)
          throw $Error("missing end group");
        if (!$Object.hasOwnProperty.call(message, "url"))
          throw $util.ProtocolError("missing required 'url'", { instance: message });
        if (!$Object.hasOwnProperty.call(message, "mediaType"))
          throw $util.ProtocolError("missing required 'mediaType'", { instance: message });
        return message;
      };
      LocalizedImage.decodeDelimited = function(reader) {
        if (!(reader instanceof $Reader))
          reader = new $Reader(reader);
        return this.decode(reader, reader.uint32());
      };
      LocalizedImage.verify = function(message, _depth) {
        if (typeof message !== "object" || message === null)
          return "object expected";
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $util.recursionLimit)
          return "max depth exceeded";
        if (!$util.isString(message.url))
          return "url: string expected";
        if (!$util.isString(message.mediaType))
          return "mediaType: string expected";
        if (message.language != null && $Object.hasOwnProperty.call(message, "language")) {
          if (!$util.isString(message.language))
            return "language: string expected";
        }
        return null;
      };
      LocalizedImage.fromObject = function(object, _depth) {
        if (object instanceof $root.transit_realtime.TranslatedImage.LocalizedImage)
          return object;
        if (!$util.isObject(object))
          throw $TypeError(".transit_realtime.TranslatedImage.LocalizedImage: object expected");
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $util.recursionLimit)
          throw $Error("max depth exceeded");
        let message = new $root.transit_realtime.TranslatedImage.LocalizedImage();
        if (object.url != null)
          message.url = $String(object.url);
        if (object.mediaType != null)
          message.mediaType = $String(object.mediaType);
        if (object.language != null)
          message.language = $String(object.language);
        return message;
      };
      LocalizedImage.toObject = function(message, options, _depth) {
        if (!options)
          options = {};
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $util.recursionLimit)
          throw $Error("max depth exceeded");
        let object = {};
        if (options.defaults) {
          object.url = "";
          object.mediaType = "";
          object.language = "";
        }
        if (message.url != null && $Object.hasOwnProperty.call(message, "url"))
          object.url = message.url;
        if (message.mediaType != null && $Object.hasOwnProperty.call(message, "mediaType"))
          object.mediaType = message.mediaType;
        if (message.language != null && $Object.hasOwnProperty.call(message, "language"))
          object.language = message.language;
        return object;
      };
      LocalizedImage.prototype.toJSON = function() {
        return LocalizedImage.toObject(this, import_minimal.default.util.toJSONOptions);
      };
      LocalizedImage.getTypeUrl = function(prefix) {
        if (prefix === $undefined)
          prefix = "type.googleapis.com";
        return prefix + "/transit_realtime.TranslatedImage.LocalizedImage";
      };
      return LocalizedImage;
    })();
    return TranslatedImage;
  })();
  transit_realtime2.Shape = (function() {
    const Shape = /* @__PURE__ */ __name(function(properties) {
      if (properties) {
        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
          if (properties[keys[i]] != null && keys[i] !== "__proto__")
            this[keys[i]] = properties[keys[i]];
      }
    }, "Shape");
    Shape.prototype.shapeId = "";
    Shape.prototype.encodedPolyline = "";
    Shape.create = function(properties) {
      return new Shape(properties);
    };
    Shape.encode = function(message, writer, _depth) {
      if (!writer)
        writer = $Writer.create();
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      if (message.shapeId != null && $Object.hasOwnProperty.call(message, "shapeId"))
        writer.uint32(
          /* id 1, wireType 2 =*/
          10
        ).string(message.shapeId);
      if (message.encodedPolyline != null && $Object.hasOwnProperty.call(message, "encodedPolyline"))
        writer.uint32(
          /* id 2, wireType 2 =*/
          18
        ).string(message.encodedPolyline);
      if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
        for (let i = 0; i < message.$unknowns.length; ++i)
          writer.raw(message.$unknowns[i]);
      return writer;
    };
    Shape.encodeDelimited = function(message, writer) {
      return this.encode(message, (writer || $Writer.create()).fork()).ldelim();
    };
    Shape.decode = function(reader, length, _end, _depth, _target) {
      if (!(reader instanceof $Reader))
        reader = $Reader.create(reader);
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $Reader.recursionLimit)
        throw $Error("max depth exceeded");
      let end, message;
      if (length === $undefined)
        end = reader.len;
      else {
        end = reader.pos + length;
        if (end > reader.len)
          throw $RangeError("index out of range");
        length = reader.len;
        reader.len = end;
      }
      message = _target || new $root.transit_realtime.Shape();
      while (reader.pos < end) {
        let start = reader.pos;
        let tag = reader.tag();
        if (tag === _end) {
          _end = $undefined;
          break;
        }
        let wireType = tag & 7;
        switch (tag >>>= 3) {
          case 1: {
            if (wireType !== 2)
              break;
            message.shapeId = reader.string();
            continue;
          }
          case 2: {
            if (wireType !== 2)
              break;
            message.encodedPolyline = reader.string();
            continue;
          }
        }
        reader.skipType(wireType, _depth, tag);
        if (!reader.discardUnknown) {
          $util.makeProp(message, "$unknowns", false);
          (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
        }
      }
      if (length !== $undefined) {
        if (reader.pos !== end)
          throw $RangeError("index out of range");
        reader.len = length;
      }
      if (_end !== $undefined)
        throw $Error("missing end group");
      return message;
    };
    Shape.decodeDelimited = function(reader) {
      if (!(reader instanceof $Reader))
        reader = new $Reader(reader);
      return this.decode(reader, reader.uint32());
    };
    Shape.verify = function(message, _depth) {
      if (typeof message !== "object" || message === null)
        return "object expected";
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        return "max depth exceeded";
      if (message.shapeId != null && $Object.hasOwnProperty.call(message, "shapeId")) {
        if (!$util.isString(message.shapeId))
          return "shapeId: string expected";
      }
      if (message.encodedPolyline != null && $Object.hasOwnProperty.call(message, "encodedPolyline")) {
        if (!$util.isString(message.encodedPolyline))
          return "encodedPolyline: string expected";
      }
      return null;
    };
    Shape.fromObject = function(object, _depth) {
      if (object instanceof $root.transit_realtime.Shape)
        return object;
      if (!$util.isObject(object))
        throw $TypeError(".transit_realtime.Shape: object expected");
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let message = new $root.transit_realtime.Shape();
      if (object.shapeId != null)
        message.shapeId = $String(object.shapeId);
      if (object.encodedPolyline != null)
        message.encodedPolyline = $String(object.encodedPolyline);
      return message;
    };
    Shape.toObject = function(message, options, _depth) {
      if (!options)
        options = {};
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let object = {};
      if (options.defaults) {
        object.shapeId = "";
        object.encodedPolyline = "";
      }
      if (message.shapeId != null && $Object.hasOwnProperty.call(message, "shapeId"))
        object.shapeId = message.shapeId;
      if (message.encodedPolyline != null && $Object.hasOwnProperty.call(message, "encodedPolyline"))
        object.encodedPolyline = message.encodedPolyline;
      return object;
    };
    Shape.prototype.toJSON = function() {
      return Shape.toObject(this, import_minimal.default.util.toJSONOptions);
    };
    Shape.getTypeUrl = function(prefix) {
      if (prefix === $undefined)
        prefix = "type.googleapis.com";
      return prefix + "/transit_realtime.Shape";
    };
    return Shape;
  })();
  transit_realtime2.Stop = (function() {
    const Stop = /* @__PURE__ */ __name(function(properties) {
      if (properties) {
        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
          if (properties[keys[i]] != null && keys[i] !== "__proto__")
            this[keys[i]] = properties[keys[i]];
      }
    }, "Stop");
    Stop.prototype.stopId = "";
    Stop.prototype.stopCode = null;
    Stop.prototype.stopName = null;
    Stop.prototype.ttsStopName = null;
    Stop.prototype.stopDesc = null;
    Stop.prototype.stopLat = 0;
    Stop.prototype.stopLon = 0;
    Stop.prototype.zoneId = "";
    Stop.prototype.stopUrl = null;
    Stop.prototype.parentStation = "";
    Stop.prototype.stopTimezone = "";
    Stop.prototype.wheelchairBoarding = 0;
    Stop.prototype.levelId = "";
    Stop.prototype.platformCode = null;
    Stop.create = function(properties) {
      return new Stop(properties);
    };
    Stop.encode = function(message, writer, _depth) {
      if (!writer)
        writer = $Writer.create();
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      if (message.stopId != null && $Object.hasOwnProperty.call(message, "stopId"))
        writer.uint32(
          /* id 1, wireType 2 =*/
          10
        ).string(message.stopId);
      if (message.stopCode != null && $Object.hasOwnProperty.call(message, "stopCode"))
        $root.transit_realtime.TranslatedString.encode(message.stopCode, writer.uint32(
          /* id 2, wireType 2 =*/
          18
        ).fork(), _depth + 1).ldelim();
      if (message.stopName != null && $Object.hasOwnProperty.call(message, "stopName"))
        $root.transit_realtime.TranslatedString.encode(message.stopName, writer.uint32(
          /* id 3, wireType 2 =*/
          26
        ).fork(), _depth + 1).ldelim();
      if (message.ttsStopName != null && $Object.hasOwnProperty.call(message, "ttsStopName"))
        $root.transit_realtime.TranslatedString.encode(message.ttsStopName, writer.uint32(
          /* id 4, wireType 2 =*/
          34
        ).fork(), _depth + 1).ldelim();
      if (message.stopDesc != null && $Object.hasOwnProperty.call(message, "stopDesc"))
        $root.transit_realtime.TranslatedString.encode(message.stopDesc, writer.uint32(
          /* id 5, wireType 2 =*/
          42
        ).fork(), _depth + 1).ldelim();
      if (message.stopLat != null && $Object.hasOwnProperty.call(message, "stopLat"))
        writer.uint32(
          /* id 6, wireType 5 =*/
          53
        ).float(message.stopLat);
      if (message.stopLon != null && $Object.hasOwnProperty.call(message, "stopLon"))
        writer.uint32(
          /* id 7, wireType 5 =*/
          61
        ).float(message.stopLon);
      if (message.zoneId != null && $Object.hasOwnProperty.call(message, "zoneId"))
        writer.uint32(
          /* id 8, wireType 2 =*/
          66
        ).string(message.zoneId);
      if (message.stopUrl != null && $Object.hasOwnProperty.call(message, "stopUrl"))
        $root.transit_realtime.TranslatedString.encode(message.stopUrl, writer.uint32(
          /* id 9, wireType 2 =*/
          74
        ).fork(), _depth + 1).ldelim();
      if (message.parentStation != null && $Object.hasOwnProperty.call(message, "parentStation"))
        writer.uint32(
          /* id 11, wireType 2 =*/
          90
        ).string(message.parentStation);
      if (message.stopTimezone != null && $Object.hasOwnProperty.call(message, "stopTimezone"))
        writer.uint32(
          /* id 12, wireType 2 =*/
          98
        ).string(message.stopTimezone);
      if (message.wheelchairBoarding != null && $Object.hasOwnProperty.call(message, "wheelchairBoarding"))
        writer.uint32(
          /* id 13, wireType 0 =*/
          104
        ).int32(message.wheelchairBoarding);
      if (message.levelId != null && $Object.hasOwnProperty.call(message, "levelId"))
        writer.uint32(
          /* id 14, wireType 2 =*/
          114
        ).string(message.levelId);
      if (message.platformCode != null && $Object.hasOwnProperty.call(message, "platformCode"))
        $root.transit_realtime.TranslatedString.encode(message.platformCode, writer.uint32(
          /* id 15, wireType 2 =*/
          122
        ).fork(), _depth + 1).ldelim();
      if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
        for (let i = 0; i < message.$unknowns.length; ++i)
          writer.raw(message.$unknowns[i]);
      return writer;
    };
    Stop.encodeDelimited = function(message, writer) {
      return this.encode(message, (writer || $Writer.create()).fork()).ldelim();
    };
    Stop.decode = function(reader, length, _end, _depth, _target) {
      if (!(reader instanceof $Reader))
        reader = $Reader.create(reader);
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $Reader.recursionLimit)
        throw $Error("max depth exceeded");
      let end, message, value;
      if (length === $undefined)
        end = reader.len;
      else {
        end = reader.pos + length;
        if (end > reader.len)
          throw $RangeError("index out of range");
        length = reader.len;
        reader.len = end;
      }
      message = _target || new $root.transit_realtime.Stop();
      while (reader.pos < end) {
        let start = reader.pos;
        let tag = reader.tag();
        if (tag === _end) {
          _end = $undefined;
          break;
        }
        let wireType = tag & 7;
        switch (tag >>>= 3) {
          case 1: {
            if (wireType !== 2)
              break;
            message.stopId = reader.string();
            continue;
          }
          case 2: {
            if (wireType !== 2)
              break;
            message.stopCode = $root.transit_realtime.TranslatedString.decode(reader, reader.uint32(), $undefined, _depth + 1, message.stopCode);
            continue;
          }
          case 3: {
            if (wireType !== 2)
              break;
            message.stopName = $root.transit_realtime.TranslatedString.decode(reader, reader.uint32(), $undefined, _depth + 1, message.stopName);
            continue;
          }
          case 4: {
            if (wireType !== 2)
              break;
            message.ttsStopName = $root.transit_realtime.TranslatedString.decode(reader, reader.uint32(), $undefined, _depth + 1, message.ttsStopName);
            continue;
          }
          case 5: {
            if (wireType !== 2)
              break;
            message.stopDesc = $root.transit_realtime.TranslatedString.decode(reader, reader.uint32(), $undefined, _depth + 1, message.stopDesc);
            continue;
          }
          case 6: {
            if (wireType !== 5)
              break;
            message.stopLat = reader.float();
            continue;
          }
          case 7: {
            if (wireType !== 5)
              break;
            message.stopLon = reader.float();
            continue;
          }
          case 8: {
            if (wireType !== 2)
              break;
            message.zoneId = reader.string();
            continue;
          }
          case 9: {
            if (wireType !== 2)
              break;
            message.stopUrl = $root.transit_realtime.TranslatedString.decode(reader, reader.uint32(), $undefined, _depth + 1, message.stopUrl);
            continue;
          }
          case 11: {
            if (wireType !== 2)
              break;
            message.parentStation = reader.string();
            continue;
          }
          case 12: {
            if (wireType !== 2)
              break;
            message.stopTimezone = reader.string();
            continue;
          }
          case 13: {
            if (wireType !== 0)
              break;
            value = reader.int32();
            if ($root.transit_realtime.Stop.WheelchairBoarding[value] !== $undefined)
              message.wheelchairBoarding = value;
            else if (!reader.discardUnknown) {
              $util.makeProp(message, "$unknowns", false);
              (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
            }
            continue;
          }
          case 14: {
            if (wireType !== 2)
              break;
            message.levelId = reader.string();
            continue;
          }
          case 15: {
            if (wireType !== 2)
              break;
            message.platformCode = $root.transit_realtime.TranslatedString.decode(reader, reader.uint32(), $undefined, _depth + 1, message.platformCode);
            continue;
          }
        }
        reader.skipType(wireType, _depth, tag);
        if (!reader.discardUnknown) {
          $util.makeProp(message, "$unknowns", false);
          (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
        }
      }
      if (length !== $undefined) {
        if (reader.pos !== end)
          throw $RangeError("index out of range");
        reader.len = length;
      }
      if (_end !== $undefined)
        throw $Error("missing end group");
      return message;
    };
    Stop.decodeDelimited = function(reader) {
      if (!(reader instanceof $Reader))
        reader = new $Reader(reader);
      return this.decode(reader, reader.uint32());
    };
    Stop.verify = function(message, _depth) {
      if (typeof message !== "object" || message === null)
        return "object expected";
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        return "max depth exceeded";
      if (message.stopId != null && $Object.hasOwnProperty.call(message, "stopId")) {
        if (!$util.isString(message.stopId))
          return "stopId: string expected";
      }
      if (message.stopCode != null && $Object.hasOwnProperty.call(message, "stopCode")) {
        let error = $root.transit_realtime.TranslatedString.verify(message.stopCode, _depth + 1);
        if (error)
          return "stopCode." + error;
      }
      if (message.stopName != null && $Object.hasOwnProperty.call(message, "stopName")) {
        let error = $root.transit_realtime.TranslatedString.verify(message.stopName, _depth + 1);
        if (error)
          return "stopName." + error;
      }
      if (message.ttsStopName != null && $Object.hasOwnProperty.call(message, "ttsStopName")) {
        let error = $root.transit_realtime.TranslatedString.verify(message.ttsStopName, _depth + 1);
        if (error)
          return "ttsStopName." + error;
      }
      if (message.stopDesc != null && $Object.hasOwnProperty.call(message, "stopDesc")) {
        let error = $root.transit_realtime.TranslatedString.verify(message.stopDesc, _depth + 1);
        if (error)
          return "stopDesc." + error;
      }
      if (message.stopLat != null && $Object.hasOwnProperty.call(message, "stopLat")) {
        if (typeof message.stopLat !== "number")
          return "stopLat: number expected";
      }
      if (message.stopLon != null && $Object.hasOwnProperty.call(message, "stopLon")) {
        if (typeof message.stopLon !== "number")
          return "stopLon: number expected";
      }
      if (message.zoneId != null && $Object.hasOwnProperty.call(message, "zoneId")) {
        if (!$util.isString(message.zoneId))
          return "zoneId: string expected";
      }
      if (message.stopUrl != null && $Object.hasOwnProperty.call(message, "stopUrl")) {
        let error = $root.transit_realtime.TranslatedString.verify(message.stopUrl, _depth + 1);
        if (error)
          return "stopUrl." + error;
      }
      if (message.parentStation != null && $Object.hasOwnProperty.call(message, "parentStation")) {
        if (!$util.isString(message.parentStation))
          return "parentStation: string expected";
      }
      if (message.stopTimezone != null && $Object.hasOwnProperty.call(message, "stopTimezone")) {
        if (!$util.isString(message.stopTimezone))
          return "stopTimezone: string expected";
      }
      if (message.wheelchairBoarding != null && $Object.hasOwnProperty.call(message, "wheelchairBoarding"))
        switch (message.wheelchairBoarding) {
          default:
            return "wheelchairBoarding: enum value expected";
          case 0:
          case 1:
          case 2:
            break;
        }
      if (message.levelId != null && $Object.hasOwnProperty.call(message, "levelId")) {
        if (!$util.isString(message.levelId))
          return "levelId: string expected";
      }
      if (message.platformCode != null && $Object.hasOwnProperty.call(message, "platformCode")) {
        let error = $root.transit_realtime.TranslatedString.verify(message.platformCode, _depth + 1);
        if (error)
          return "platformCode." + error;
      }
      return null;
    };
    Stop.fromObject = function(object, _depth) {
      if (object instanceof $root.transit_realtime.Stop)
        return object;
      if (!$util.isObject(object))
        throw $TypeError(".transit_realtime.Stop: object expected");
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let message = new $root.transit_realtime.Stop();
      if (object.stopId != null)
        message.stopId = $String(object.stopId);
      if (object.stopCode != null) {
        if (!$util.isObject(object.stopCode))
          throw $TypeError(".transit_realtime.Stop.stopCode: object expected");
        message.stopCode = $root.transit_realtime.TranslatedString.fromObject(object.stopCode, _depth + 1);
      }
      if (object.stopName != null) {
        if (!$util.isObject(object.stopName))
          throw $TypeError(".transit_realtime.Stop.stopName: object expected");
        message.stopName = $root.transit_realtime.TranslatedString.fromObject(object.stopName, _depth + 1);
      }
      if (object.ttsStopName != null) {
        if (!$util.isObject(object.ttsStopName))
          throw $TypeError(".transit_realtime.Stop.ttsStopName: object expected");
        message.ttsStopName = $root.transit_realtime.TranslatedString.fromObject(object.ttsStopName, _depth + 1);
      }
      if (object.stopDesc != null) {
        if (!$util.isObject(object.stopDesc))
          throw $TypeError(".transit_realtime.Stop.stopDesc: object expected");
        message.stopDesc = $root.transit_realtime.TranslatedString.fromObject(object.stopDesc, _depth + 1);
      }
      if (object.stopLat != null)
        message.stopLat = $Number(object.stopLat);
      if (object.stopLon != null)
        message.stopLon = $Number(object.stopLon);
      if (object.zoneId != null)
        message.zoneId = $String(object.zoneId);
      if (object.stopUrl != null) {
        if (!$util.isObject(object.stopUrl))
          throw $TypeError(".transit_realtime.Stop.stopUrl: object expected");
        message.stopUrl = $root.transit_realtime.TranslatedString.fromObject(object.stopUrl, _depth + 1);
      }
      if (object.parentStation != null)
        message.parentStation = $String(object.parentStation);
      if (object.stopTimezone != null)
        message.stopTimezone = $String(object.stopTimezone);
      switch (object.wheelchairBoarding) {
        case "UNKNOWN":
        case 0:
          message.wheelchairBoarding = 0;
          break;
        case "AVAILABLE":
        case 1:
          message.wheelchairBoarding = 1;
          break;
        case "NOT_AVAILABLE":
        case 2:
          message.wheelchairBoarding = 2;
          break;
        default:
      }
      if (object.levelId != null)
        message.levelId = $String(object.levelId);
      if (object.platformCode != null) {
        if (!$util.isObject(object.platformCode))
          throw $TypeError(".transit_realtime.Stop.platformCode: object expected");
        message.platformCode = $root.transit_realtime.TranslatedString.fromObject(object.platformCode, _depth + 1);
      }
      return message;
    };
    Stop.toObject = function(message, options, _depth) {
      if (!options)
        options = {};
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let object = {};
      if (options.defaults) {
        object.stopId = "";
        object.stopCode = null;
        object.stopName = null;
        object.ttsStopName = null;
        object.stopDesc = null;
        object.stopLat = 0;
        object.stopLon = 0;
        object.zoneId = "";
        object.stopUrl = null;
        object.parentStation = "";
        object.stopTimezone = "";
        object.wheelchairBoarding = options.enums === $String ? "UNKNOWN" : 0;
        object.levelId = "";
        object.platformCode = null;
      }
      if (message.stopId != null && $Object.hasOwnProperty.call(message, "stopId"))
        object.stopId = message.stopId;
      if (message.stopCode != null && $Object.hasOwnProperty.call(message, "stopCode"))
        object.stopCode = $root.transit_realtime.TranslatedString.toObject(message.stopCode, options, _depth + 1);
      if (message.stopName != null && $Object.hasOwnProperty.call(message, "stopName"))
        object.stopName = $root.transit_realtime.TranslatedString.toObject(message.stopName, options, _depth + 1);
      if (message.ttsStopName != null && $Object.hasOwnProperty.call(message, "ttsStopName"))
        object.ttsStopName = $root.transit_realtime.TranslatedString.toObject(message.ttsStopName, options, _depth + 1);
      if (message.stopDesc != null && $Object.hasOwnProperty.call(message, "stopDesc"))
        object.stopDesc = $root.transit_realtime.TranslatedString.toObject(message.stopDesc, options, _depth + 1);
      if (message.stopLat != null && $Object.hasOwnProperty.call(message, "stopLat"))
        object.stopLat = options.json && !$isFinite(message.stopLat) ? $String(message.stopLat) : message.stopLat;
      if (message.stopLon != null && $Object.hasOwnProperty.call(message, "stopLon"))
        object.stopLon = options.json && !$isFinite(message.stopLon) ? $String(message.stopLon) : message.stopLon;
      if (message.zoneId != null && $Object.hasOwnProperty.call(message, "zoneId"))
        object.zoneId = message.zoneId;
      if (message.stopUrl != null && $Object.hasOwnProperty.call(message, "stopUrl"))
        object.stopUrl = $root.transit_realtime.TranslatedString.toObject(message.stopUrl, options, _depth + 1);
      if (message.parentStation != null && $Object.hasOwnProperty.call(message, "parentStation"))
        object.parentStation = message.parentStation;
      if (message.stopTimezone != null && $Object.hasOwnProperty.call(message, "stopTimezone"))
        object.stopTimezone = message.stopTimezone;
      if (message.wheelchairBoarding != null && $Object.hasOwnProperty.call(message, "wheelchairBoarding"))
        object.wheelchairBoarding = options.enums === $String ? $root.transit_realtime.Stop.WheelchairBoarding[message.wheelchairBoarding] === $undefined ? message.wheelchairBoarding : $root.transit_realtime.Stop.WheelchairBoarding[message.wheelchairBoarding] : message.wheelchairBoarding;
      if (message.levelId != null && $Object.hasOwnProperty.call(message, "levelId"))
        object.levelId = message.levelId;
      if (message.platformCode != null && $Object.hasOwnProperty.call(message, "platformCode"))
        object.platformCode = $root.transit_realtime.TranslatedString.toObject(message.platformCode, options, _depth + 1);
      return object;
    };
    Stop.prototype.toJSON = function() {
      return Stop.toObject(this, import_minimal.default.util.toJSONOptions);
    };
    Stop.getTypeUrl = function(prefix) {
      if (prefix === $undefined)
        prefix = "type.googleapis.com";
      return prefix + "/transit_realtime.Stop";
    };
    Stop.WheelchairBoarding = (function() {
      const valuesById = $Object.create(null), values = $Object.create(valuesById);
      values[valuesById[0] = "UNKNOWN"] = 0;
      values[valuesById[1] = "AVAILABLE"] = 1;
      values[valuesById[2] = "NOT_AVAILABLE"] = 2;
      return values;
    })();
    return Stop;
  })();
  transit_realtime2.TripModifications = (function() {
    const TripModifications = /* @__PURE__ */ __name(function(properties) {
      this.selectedTrips = [];
      this.startTimes = [];
      this.serviceDates = [];
      this.modifications = [];
      if (properties) {
        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
          if (properties[keys[i]] != null && keys[i] !== "__proto__")
            this[keys[i]] = properties[keys[i]];
      }
    }, "TripModifications");
    TripModifications.prototype.selectedTrips = $util.emptyArray;
    TripModifications.prototype.startTimes = $util.emptyArray;
    TripModifications.prototype.serviceDates = $util.emptyArray;
    TripModifications.prototype.modifications = $util.emptyArray;
    TripModifications.create = function(properties) {
      return new TripModifications(properties);
    };
    TripModifications.encode = function(message, writer, _depth) {
      if (!writer)
        writer = $Writer.create();
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      if (message.selectedTrips != null && message.selectedTrips.length)
        for (let i = 0; i < message.selectedTrips.length; ++i)
          $root.transit_realtime.TripModifications.SelectedTrips.encode(message.selectedTrips[i], writer.uint32(
            /* id 1, wireType 2 =*/
            10
          ).fork(), _depth + 1).ldelim();
      if (message.startTimes != null && message.startTimes.length)
        for (let i = 0; i < message.startTimes.length; ++i)
          writer.uint32(
            /* id 2, wireType 2 =*/
            18
          ).string(message.startTimes[i]);
      if (message.serviceDates != null && message.serviceDates.length)
        for (let i = 0; i < message.serviceDates.length; ++i)
          writer.uint32(
            /* id 3, wireType 2 =*/
            26
          ).string(message.serviceDates[i]);
      if (message.modifications != null && message.modifications.length)
        for (let i = 0; i < message.modifications.length; ++i)
          $root.transit_realtime.TripModifications.Modification.encode(message.modifications[i], writer.uint32(
            /* id 4, wireType 2 =*/
            34
          ).fork(), _depth + 1).ldelim();
      if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
        for (let i = 0; i < message.$unknowns.length; ++i)
          writer.raw(message.$unknowns[i]);
      return writer;
    };
    TripModifications.encodeDelimited = function(message, writer) {
      return this.encode(message, (writer || $Writer.create()).fork()).ldelim();
    };
    TripModifications.decode = function(reader, length, _end, _depth, _target) {
      if (!(reader instanceof $Reader))
        reader = $Reader.create(reader);
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $Reader.recursionLimit)
        throw $Error("max depth exceeded");
      let end, message;
      if (length === $undefined)
        end = reader.len;
      else {
        end = reader.pos + length;
        if (end > reader.len)
          throw $RangeError("index out of range");
        length = reader.len;
        reader.len = end;
      }
      message = _target || new $root.transit_realtime.TripModifications();
      while (reader.pos < end) {
        let start = reader.pos;
        let tag = reader.tag();
        if (tag === _end) {
          _end = $undefined;
          break;
        }
        let wireType = tag & 7;
        switch (tag >>>= 3) {
          case 1: {
            if (wireType !== 2)
              break;
            if (!(message.selectedTrips && message.selectedTrips.length))
              message.selectedTrips = [];
            message.selectedTrips.push($root.transit_realtime.TripModifications.SelectedTrips.decode(reader, reader.uint32(), $undefined, _depth + 1));
            continue;
          }
          case 2: {
            if (wireType !== 2)
              break;
            if (!(message.startTimes && message.startTimes.length))
              message.startTimes = [];
            message.startTimes.push(reader.string());
            continue;
          }
          case 3: {
            if (wireType !== 2)
              break;
            if (!(message.serviceDates && message.serviceDates.length))
              message.serviceDates = [];
            message.serviceDates.push(reader.string());
            continue;
          }
          case 4: {
            if (wireType !== 2)
              break;
            if (!(message.modifications && message.modifications.length))
              message.modifications = [];
            message.modifications.push($root.transit_realtime.TripModifications.Modification.decode(reader, reader.uint32(), $undefined, _depth + 1));
            continue;
          }
        }
        reader.skipType(wireType, _depth, tag);
        if (!reader.discardUnknown) {
          $util.makeProp(message, "$unknowns", false);
          (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
        }
      }
      if (length !== $undefined) {
        if (reader.pos !== end)
          throw $RangeError("index out of range");
        reader.len = length;
      }
      if (_end !== $undefined)
        throw $Error("missing end group");
      return message;
    };
    TripModifications.decodeDelimited = function(reader) {
      if (!(reader instanceof $Reader))
        reader = new $Reader(reader);
      return this.decode(reader, reader.uint32());
    };
    TripModifications.verify = function(message, _depth) {
      if (typeof message !== "object" || message === null)
        return "object expected";
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        return "max depth exceeded";
      if (message.selectedTrips != null && $Object.hasOwnProperty.call(message, "selectedTrips")) {
        if (!$Array.isArray(message.selectedTrips))
          return "selectedTrips: array expected";
        for (let i = 0; i < message.selectedTrips.length; ++i) {
          let error = $root.transit_realtime.TripModifications.SelectedTrips.verify(message.selectedTrips[i], _depth + 1);
          if (error)
            return "selectedTrips." + error;
        }
      }
      if (message.startTimes != null && $Object.hasOwnProperty.call(message, "startTimes")) {
        if (!$Array.isArray(message.startTimes))
          return "startTimes: array expected";
        for (let i = 0; i < message.startTimes.length; ++i)
          if (!$util.isString(message.startTimes[i]))
            return "startTimes: string[] expected";
      }
      if (message.serviceDates != null && $Object.hasOwnProperty.call(message, "serviceDates")) {
        if (!$Array.isArray(message.serviceDates))
          return "serviceDates: array expected";
        for (let i = 0; i < message.serviceDates.length; ++i)
          if (!$util.isString(message.serviceDates[i]))
            return "serviceDates: string[] expected";
      }
      if (message.modifications != null && $Object.hasOwnProperty.call(message, "modifications")) {
        if (!$Array.isArray(message.modifications))
          return "modifications: array expected";
        for (let i = 0; i < message.modifications.length; ++i) {
          let error = $root.transit_realtime.TripModifications.Modification.verify(message.modifications[i], _depth + 1);
          if (error)
            return "modifications." + error;
        }
      }
      return null;
    };
    TripModifications.fromObject = function(object, _depth) {
      if (object instanceof $root.transit_realtime.TripModifications)
        return object;
      if (!$util.isObject(object))
        throw $TypeError(".transit_realtime.TripModifications: object expected");
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let message = new $root.transit_realtime.TripModifications();
      if (object.selectedTrips) {
        if (!$Array.isArray(object.selectedTrips))
          throw $TypeError(".transit_realtime.TripModifications.selectedTrips: array expected");
        message.selectedTrips = $Array(object.selectedTrips.length);
        for (let i = 0; i < object.selectedTrips.length; ++i) {
          if (!$util.isObject(object.selectedTrips[i]))
            throw $TypeError(".transit_realtime.TripModifications.selectedTrips: object expected");
          message.selectedTrips[i] = $root.transit_realtime.TripModifications.SelectedTrips.fromObject(object.selectedTrips[i], _depth + 1);
        }
      }
      if (object.startTimes) {
        if (!$Array.isArray(object.startTimes))
          throw $TypeError(".transit_realtime.TripModifications.startTimes: array expected");
        message.startTimes = $Array(object.startTimes.length);
        for (let i = 0; i < object.startTimes.length; ++i)
          message.startTimes[i] = $String(object.startTimes[i]);
      }
      if (object.serviceDates) {
        if (!$Array.isArray(object.serviceDates))
          throw $TypeError(".transit_realtime.TripModifications.serviceDates: array expected");
        message.serviceDates = $Array(object.serviceDates.length);
        for (let i = 0; i < object.serviceDates.length; ++i)
          message.serviceDates[i] = $String(object.serviceDates[i]);
      }
      if (object.modifications) {
        if (!$Array.isArray(object.modifications))
          throw $TypeError(".transit_realtime.TripModifications.modifications: array expected");
        message.modifications = $Array(object.modifications.length);
        for (let i = 0; i < object.modifications.length; ++i) {
          if (!$util.isObject(object.modifications[i]))
            throw $TypeError(".transit_realtime.TripModifications.modifications: object expected");
          message.modifications[i] = $root.transit_realtime.TripModifications.Modification.fromObject(object.modifications[i], _depth + 1);
        }
      }
      return message;
    };
    TripModifications.toObject = function(message, options, _depth) {
      if (!options)
        options = {};
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let object = {};
      if (options.arrays || options.defaults) {
        object.selectedTrips = [];
        object.startTimes = [];
        object.serviceDates = [];
        object.modifications = [];
      }
      if (message.selectedTrips && message.selectedTrips.length) {
        object.selectedTrips = $Array(message.selectedTrips.length);
        for (let j = 0; j < message.selectedTrips.length; ++j)
          object.selectedTrips[j] = $root.transit_realtime.TripModifications.SelectedTrips.toObject(message.selectedTrips[j], options, _depth + 1);
      }
      if (message.startTimes && message.startTimes.length) {
        object.startTimes = $Array(message.startTimes.length);
        for (let j = 0; j < message.startTimes.length; ++j)
          object.startTimes[j] = message.startTimes[j];
      }
      if (message.serviceDates && message.serviceDates.length) {
        object.serviceDates = $Array(message.serviceDates.length);
        for (let j = 0; j < message.serviceDates.length; ++j)
          object.serviceDates[j] = message.serviceDates[j];
      }
      if (message.modifications && message.modifications.length) {
        object.modifications = $Array(message.modifications.length);
        for (let j = 0; j < message.modifications.length; ++j)
          object.modifications[j] = $root.transit_realtime.TripModifications.Modification.toObject(message.modifications[j], options, _depth + 1);
      }
      return object;
    };
    TripModifications.prototype.toJSON = function() {
      return TripModifications.toObject(this, import_minimal.default.util.toJSONOptions);
    };
    TripModifications.getTypeUrl = function(prefix) {
      if (prefix === $undefined)
        prefix = "type.googleapis.com";
      return prefix + "/transit_realtime.TripModifications";
    };
    TripModifications.Modification = (function() {
      const Modification = /* @__PURE__ */ __name(function(properties) {
        this.replacementStops = [];
        if (properties) {
          for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
            if (properties[keys[i]] != null && keys[i] !== "__proto__")
              this[keys[i]] = properties[keys[i]];
        }
      }, "Modification");
      Modification.prototype.startStopSelector = null;
      Modification.prototype.endStopSelector = null;
      Modification.prototype.propagatedModificationDelay = 0;
      Modification.prototype.replacementStops = $util.emptyArray;
      Modification.prototype.serviceAlertId = "";
      Modification.prototype.lastModifiedTime = $util.Long ? $util.Long.fromBits(0, 0, true) : 0;
      Modification.create = function(properties) {
        return new Modification(properties);
      };
      Modification.encode = function(message, writer, _depth) {
        if (!writer)
          writer = $Writer.create();
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $util.recursionLimit)
          throw $Error("max depth exceeded");
        if (message.startStopSelector != null && $Object.hasOwnProperty.call(message, "startStopSelector"))
          $root.transit_realtime.StopSelector.encode(message.startStopSelector, writer.uint32(
            /* id 1, wireType 2 =*/
            10
          ).fork(), _depth + 1).ldelim();
        if (message.endStopSelector != null && $Object.hasOwnProperty.call(message, "endStopSelector"))
          $root.transit_realtime.StopSelector.encode(message.endStopSelector, writer.uint32(
            /* id 2, wireType 2 =*/
            18
          ).fork(), _depth + 1).ldelim();
        if (message.propagatedModificationDelay != null && $Object.hasOwnProperty.call(message, "propagatedModificationDelay"))
          writer.uint32(
            /* id 3, wireType 0 =*/
            24
          ).int32(message.propagatedModificationDelay);
        if (message.replacementStops != null && message.replacementStops.length)
          for (let i = 0; i < message.replacementStops.length; ++i)
            $root.transit_realtime.ReplacementStop.encode(message.replacementStops[i], writer.uint32(
              /* id 4, wireType 2 =*/
              34
            ).fork(), _depth + 1).ldelim();
        if (message.serviceAlertId != null && $Object.hasOwnProperty.call(message, "serviceAlertId"))
          writer.uint32(
            /* id 5, wireType 2 =*/
            42
          ).string(message.serviceAlertId);
        if (message.lastModifiedTime != null && $Object.hasOwnProperty.call(message, "lastModifiedTime"))
          writer.uint32(
            /* id 6, wireType 0 =*/
            48
          ).uint64(message.lastModifiedTime);
        if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
          for (let i = 0; i < message.$unknowns.length; ++i)
            writer.raw(message.$unknowns[i]);
        return writer;
      };
      Modification.encodeDelimited = function(message, writer) {
        return this.encode(message, (writer || $Writer.create()).fork()).ldelim();
      };
      Modification.decode = function(reader, length, _end, _depth, _target) {
        if (!(reader instanceof $Reader))
          reader = $Reader.create(reader);
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $Reader.recursionLimit)
          throw $Error("max depth exceeded");
        let end, message;
        if (length === $undefined)
          end = reader.len;
        else {
          end = reader.pos + length;
          if (end > reader.len)
            throw $RangeError("index out of range");
          length = reader.len;
          reader.len = end;
        }
        message = _target || new $root.transit_realtime.TripModifications.Modification();
        while (reader.pos < end) {
          let start = reader.pos;
          let tag = reader.tag();
          if (tag === _end) {
            _end = $undefined;
            break;
          }
          let wireType = tag & 7;
          switch (tag >>>= 3) {
            case 1: {
              if (wireType !== 2)
                break;
              message.startStopSelector = $root.transit_realtime.StopSelector.decode(reader, reader.uint32(), $undefined, _depth + 1, message.startStopSelector);
              continue;
            }
            case 2: {
              if (wireType !== 2)
                break;
              message.endStopSelector = $root.transit_realtime.StopSelector.decode(reader, reader.uint32(), $undefined, _depth + 1, message.endStopSelector);
              continue;
            }
            case 3: {
              if (wireType !== 0)
                break;
              message.propagatedModificationDelay = reader.int32();
              continue;
            }
            case 4: {
              if (wireType !== 2)
                break;
              if (!(message.replacementStops && message.replacementStops.length))
                message.replacementStops = [];
              message.replacementStops.push($root.transit_realtime.ReplacementStop.decode(reader, reader.uint32(), $undefined, _depth + 1));
              continue;
            }
            case 5: {
              if (wireType !== 2)
                break;
              message.serviceAlertId = reader.string();
              continue;
            }
            case 6: {
              if (wireType !== 0)
                break;
              message.lastModifiedTime = reader.uint64();
              continue;
            }
          }
          reader.skipType(wireType, _depth, tag);
          if (!reader.discardUnknown) {
            $util.makeProp(message, "$unknowns", false);
            (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
          }
        }
        if (length !== $undefined) {
          if (reader.pos !== end)
            throw $RangeError("index out of range");
          reader.len = length;
        }
        if (_end !== $undefined)
          throw $Error("missing end group");
        return message;
      };
      Modification.decodeDelimited = function(reader) {
        if (!(reader instanceof $Reader))
          reader = new $Reader(reader);
        return this.decode(reader, reader.uint32());
      };
      Modification.verify = function(message, _depth) {
        if (typeof message !== "object" || message === null)
          return "object expected";
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $util.recursionLimit)
          return "max depth exceeded";
        if (message.startStopSelector != null && $Object.hasOwnProperty.call(message, "startStopSelector")) {
          let error = $root.transit_realtime.StopSelector.verify(message.startStopSelector, _depth + 1);
          if (error)
            return "startStopSelector." + error;
        }
        if (message.endStopSelector != null && $Object.hasOwnProperty.call(message, "endStopSelector")) {
          let error = $root.transit_realtime.StopSelector.verify(message.endStopSelector, _depth + 1);
          if (error)
            return "endStopSelector." + error;
        }
        if (message.propagatedModificationDelay != null && $Object.hasOwnProperty.call(message, "propagatedModificationDelay")) {
          if (!$util.isInteger(message.propagatedModificationDelay))
            return "propagatedModificationDelay: integer expected";
        }
        if (message.replacementStops != null && $Object.hasOwnProperty.call(message, "replacementStops")) {
          if (!$Array.isArray(message.replacementStops))
            return "replacementStops: array expected";
          for (let i = 0; i < message.replacementStops.length; ++i) {
            let error = $root.transit_realtime.ReplacementStop.verify(message.replacementStops[i], _depth + 1);
            if (error)
              return "replacementStops." + error;
          }
        }
        if (message.serviceAlertId != null && $Object.hasOwnProperty.call(message, "serviceAlertId")) {
          if (!$util.isString(message.serviceAlertId))
            return "serviceAlertId: string expected";
        }
        if (message.lastModifiedTime != null && $Object.hasOwnProperty.call(message, "lastModifiedTime")) {
          if (!$util.isInteger(message.lastModifiedTime) && !(message.lastModifiedTime && $util.isInteger(message.lastModifiedTime.low) && $util.isInteger(message.lastModifiedTime.high)))
            return "lastModifiedTime: integer|Long expected";
        }
        return null;
      };
      Modification.fromObject = function(object, _depth) {
        if (object instanceof $root.transit_realtime.TripModifications.Modification)
          return object;
        if (!$util.isObject(object))
          throw $TypeError(".transit_realtime.TripModifications.Modification: object expected");
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $util.recursionLimit)
          throw $Error("max depth exceeded");
        let message = new $root.transit_realtime.TripModifications.Modification();
        if (object.startStopSelector != null) {
          if (!$util.isObject(object.startStopSelector))
            throw $TypeError(".transit_realtime.TripModifications.Modification.startStopSelector: object expected");
          message.startStopSelector = $root.transit_realtime.StopSelector.fromObject(object.startStopSelector, _depth + 1);
        }
        if (object.endStopSelector != null) {
          if (!$util.isObject(object.endStopSelector))
            throw $TypeError(".transit_realtime.TripModifications.Modification.endStopSelector: object expected");
          message.endStopSelector = $root.transit_realtime.StopSelector.fromObject(object.endStopSelector, _depth + 1);
        }
        if (object.propagatedModificationDelay != null)
          message.propagatedModificationDelay = object.propagatedModificationDelay | 0;
        if (object.replacementStops) {
          if (!$Array.isArray(object.replacementStops))
            throw $TypeError(".transit_realtime.TripModifications.Modification.replacementStops: array expected");
          message.replacementStops = $Array(object.replacementStops.length);
          for (let i = 0; i < object.replacementStops.length; ++i) {
            if (!$util.isObject(object.replacementStops[i]))
              throw $TypeError(".transit_realtime.TripModifications.Modification.replacementStops: object expected");
            message.replacementStops[i] = $root.transit_realtime.ReplacementStop.fromObject(object.replacementStops[i], _depth + 1);
          }
        }
        if (object.serviceAlertId != null)
          message.serviceAlertId = $String(object.serviceAlertId);
        if (object.lastModifiedTime != null) {
          if ($util.Long)
            message.lastModifiedTime = $util.Long.fromValue(object.lastModifiedTime, true);
          else if (typeof object.lastModifiedTime === "string")
            message.lastModifiedTime = $parseInt(object.lastModifiedTime, 10);
          else if (typeof object.lastModifiedTime === "number")
            message.lastModifiedTime = object.lastModifiedTime;
          else if (typeof object.lastModifiedTime === "object")
            message.lastModifiedTime = new $util.LongBits(object.lastModifiedTime.low >>> 0, object.lastModifiedTime.high >>> 0).toNumber(true);
        }
        return message;
      };
      Modification.toObject = function(message, options, _depth) {
        if (!options)
          options = {};
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $util.recursionLimit)
          throw $Error("max depth exceeded");
        let object = {};
        if (options.arrays || options.defaults)
          object.replacementStops = [];
        if (options.defaults) {
          object.startStopSelector = null;
          object.endStopSelector = null;
          object.propagatedModificationDelay = 0;
          object.serviceAlertId = "";
          if ($util.Long) {
            let long = new $util.Long(0, 0, true);
            object.lastModifiedTime = options.longs === $String ? long.toString() : options.longs === $Number ? long.toNumber() : typeof $BigInt !== "undefined" && options.longs === $BigInt ? long.toBigInt() : long;
          } else
            object.lastModifiedTime = options.longs === $String ? "0" : typeof $BigInt !== "undefined" && options.longs === $BigInt ? $BigInt("0") : 0;
        }
        if (message.startStopSelector != null && $Object.hasOwnProperty.call(message, "startStopSelector"))
          object.startStopSelector = $root.transit_realtime.StopSelector.toObject(message.startStopSelector, options, _depth + 1);
        if (message.endStopSelector != null && $Object.hasOwnProperty.call(message, "endStopSelector"))
          object.endStopSelector = $root.transit_realtime.StopSelector.toObject(message.endStopSelector, options, _depth + 1);
        if (message.propagatedModificationDelay != null && $Object.hasOwnProperty.call(message, "propagatedModificationDelay"))
          object.propagatedModificationDelay = message.propagatedModificationDelay;
        if (message.replacementStops && message.replacementStops.length) {
          object.replacementStops = $Array(message.replacementStops.length);
          for (let j = 0; j < message.replacementStops.length; ++j)
            object.replacementStops[j] = $root.transit_realtime.ReplacementStop.toObject(message.replacementStops[j], options, _depth + 1);
        }
        if (message.serviceAlertId != null && $Object.hasOwnProperty.call(message, "serviceAlertId"))
          object.serviceAlertId = message.serviceAlertId;
        if (message.lastModifiedTime != null && $Object.hasOwnProperty.call(message, "lastModifiedTime"))
          if (typeof $BigInt !== "undefined" && options.longs === $BigInt)
            object.lastModifiedTime = typeof message.lastModifiedTime === "number" ? $BigInt(message.lastModifiedTime) : $util.Long.fromBits(message.lastModifiedTime.low >>> 0, message.lastModifiedTime.high >>> 0, true).toBigInt();
          else if (typeof message.lastModifiedTime === "number")
            object.lastModifiedTime = options.longs === $String ? $String(message.lastModifiedTime) : message.lastModifiedTime;
          else
            object.lastModifiedTime = options.longs === $String ? $util.Long.prototype.toString.call(message.lastModifiedTime) : options.longs === $Number ? new $util.LongBits(message.lastModifiedTime.low >>> 0, message.lastModifiedTime.high >>> 0).toNumber(true) : message.lastModifiedTime;
        return object;
      };
      Modification.prototype.toJSON = function() {
        return Modification.toObject(this, import_minimal.default.util.toJSONOptions);
      };
      Modification.getTypeUrl = function(prefix) {
        if (prefix === $undefined)
          prefix = "type.googleapis.com";
        return prefix + "/transit_realtime.TripModifications.Modification";
      };
      return Modification;
    })();
    TripModifications.SelectedTrips = (function() {
      const SelectedTrips = /* @__PURE__ */ __name(function(properties) {
        this.tripIds = [];
        if (properties) {
          for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
            if (properties[keys[i]] != null && keys[i] !== "__proto__")
              this[keys[i]] = properties[keys[i]];
        }
      }, "SelectedTrips");
      SelectedTrips.prototype.tripIds = $util.emptyArray;
      SelectedTrips.prototype.shapeId = "";
      SelectedTrips.create = function(properties) {
        return new SelectedTrips(properties);
      };
      SelectedTrips.encode = function(message, writer, _depth) {
        if (!writer)
          writer = $Writer.create();
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $util.recursionLimit)
          throw $Error("max depth exceeded");
        if (message.tripIds != null && message.tripIds.length)
          for (let i = 0; i < message.tripIds.length; ++i)
            writer.uint32(
              /* id 1, wireType 2 =*/
              10
            ).string(message.tripIds[i]);
        if (message.shapeId != null && $Object.hasOwnProperty.call(message, "shapeId"))
          writer.uint32(
            /* id 2, wireType 2 =*/
            18
          ).string(message.shapeId);
        if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
          for (let i = 0; i < message.$unknowns.length; ++i)
            writer.raw(message.$unknowns[i]);
        return writer;
      };
      SelectedTrips.encodeDelimited = function(message, writer) {
        return this.encode(message, (writer || $Writer.create()).fork()).ldelim();
      };
      SelectedTrips.decode = function(reader, length, _end, _depth, _target) {
        if (!(reader instanceof $Reader))
          reader = $Reader.create(reader);
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $Reader.recursionLimit)
          throw $Error("max depth exceeded");
        let end, message;
        if (length === $undefined)
          end = reader.len;
        else {
          end = reader.pos + length;
          if (end > reader.len)
            throw $RangeError("index out of range");
          length = reader.len;
          reader.len = end;
        }
        message = _target || new $root.transit_realtime.TripModifications.SelectedTrips();
        while (reader.pos < end) {
          let start = reader.pos;
          let tag = reader.tag();
          if (tag === _end) {
            _end = $undefined;
            break;
          }
          let wireType = tag & 7;
          switch (tag >>>= 3) {
            case 1: {
              if (wireType !== 2)
                break;
              if (!(message.tripIds && message.tripIds.length))
                message.tripIds = [];
              message.tripIds.push(reader.string());
              continue;
            }
            case 2: {
              if (wireType !== 2)
                break;
              message.shapeId = reader.string();
              continue;
            }
          }
          reader.skipType(wireType, _depth, tag);
          if (!reader.discardUnknown) {
            $util.makeProp(message, "$unknowns", false);
            (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
          }
        }
        if (length !== $undefined) {
          if (reader.pos !== end)
            throw $RangeError("index out of range");
          reader.len = length;
        }
        if (_end !== $undefined)
          throw $Error("missing end group");
        return message;
      };
      SelectedTrips.decodeDelimited = function(reader) {
        if (!(reader instanceof $Reader))
          reader = new $Reader(reader);
        return this.decode(reader, reader.uint32());
      };
      SelectedTrips.verify = function(message, _depth) {
        if (typeof message !== "object" || message === null)
          return "object expected";
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $util.recursionLimit)
          return "max depth exceeded";
        if (message.tripIds != null && $Object.hasOwnProperty.call(message, "tripIds")) {
          if (!$Array.isArray(message.tripIds))
            return "tripIds: array expected";
          for (let i = 0; i < message.tripIds.length; ++i)
            if (!$util.isString(message.tripIds[i]))
              return "tripIds: string[] expected";
        }
        if (message.shapeId != null && $Object.hasOwnProperty.call(message, "shapeId")) {
          if (!$util.isString(message.shapeId))
            return "shapeId: string expected";
        }
        return null;
      };
      SelectedTrips.fromObject = function(object, _depth) {
        if (object instanceof $root.transit_realtime.TripModifications.SelectedTrips)
          return object;
        if (!$util.isObject(object))
          throw $TypeError(".transit_realtime.TripModifications.SelectedTrips: object expected");
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $util.recursionLimit)
          throw $Error("max depth exceeded");
        let message = new $root.transit_realtime.TripModifications.SelectedTrips();
        if (object.tripIds) {
          if (!$Array.isArray(object.tripIds))
            throw $TypeError(".transit_realtime.TripModifications.SelectedTrips.tripIds: array expected");
          message.tripIds = $Array(object.tripIds.length);
          for (let i = 0; i < object.tripIds.length; ++i)
            message.tripIds[i] = $String(object.tripIds[i]);
        }
        if (object.shapeId != null)
          message.shapeId = $String(object.shapeId);
        return message;
      };
      SelectedTrips.toObject = function(message, options, _depth) {
        if (!options)
          options = {};
        if (_depth === $undefined)
          _depth = 0;
        if (_depth > $util.recursionLimit)
          throw $Error("max depth exceeded");
        let object = {};
        if (options.arrays || options.defaults)
          object.tripIds = [];
        if (options.defaults)
          object.shapeId = "";
        if (message.tripIds && message.tripIds.length) {
          object.tripIds = $Array(message.tripIds.length);
          for (let j = 0; j < message.tripIds.length; ++j)
            object.tripIds[j] = message.tripIds[j];
        }
        if (message.shapeId != null && $Object.hasOwnProperty.call(message, "shapeId"))
          object.shapeId = message.shapeId;
        return object;
      };
      SelectedTrips.prototype.toJSON = function() {
        return SelectedTrips.toObject(this, import_minimal.default.util.toJSONOptions);
      };
      SelectedTrips.getTypeUrl = function(prefix) {
        if (prefix === $undefined)
          prefix = "type.googleapis.com";
        return prefix + "/transit_realtime.TripModifications.SelectedTrips";
      };
      return SelectedTrips;
    })();
    return TripModifications;
  })();
  transit_realtime2.StopSelector = (function() {
    const StopSelector = /* @__PURE__ */ __name(function(properties) {
      if (properties) {
        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
          if (properties[keys[i]] != null && keys[i] !== "__proto__")
            this[keys[i]] = properties[keys[i]];
      }
    }, "StopSelector");
    StopSelector.prototype.stopSequence = 0;
    StopSelector.prototype.stopId = "";
    StopSelector.create = function(properties) {
      return new StopSelector(properties);
    };
    StopSelector.encode = function(message, writer, _depth) {
      if (!writer)
        writer = $Writer.create();
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      if (message.stopSequence != null && $Object.hasOwnProperty.call(message, "stopSequence"))
        writer.uint32(
          /* id 1, wireType 0 =*/
          8
        ).uint32(message.stopSequence);
      if (message.stopId != null && $Object.hasOwnProperty.call(message, "stopId"))
        writer.uint32(
          /* id 2, wireType 2 =*/
          18
        ).string(message.stopId);
      if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
        for (let i = 0; i < message.$unknowns.length; ++i)
          writer.raw(message.$unknowns[i]);
      return writer;
    };
    StopSelector.encodeDelimited = function(message, writer) {
      return this.encode(message, (writer || $Writer.create()).fork()).ldelim();
    };
    StopSelector.decode = function(reader, length, _end, _depth, _target) {
      if (!(reader instanceof $Reader))
        reader = $Reader.create(reader);
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $Reader.recursionLimit)
        throw $Error("max depth exceeded");
      let end, message;
      if (length === $undefined)
        end = reader.len;
      else {
        end = reader.pos + length;
        if (end > reader.len)
          throw $RangeError("index out of range");
        length = reader.len;
        reader.len = end;
      }
      message = _target || new $root.transit_realtime.StopSelector();
      while (reader.pos < end) {
        let start = reader.pos;
        let tag = reader.tag();
        if (tag === _end) {
          _end = $undefined;
          break;
        }
        let wireType = tag & 7;
        switch (tag >>>= 3) {
          case 1: {
            if (wireType !== 0)
              break;
            message.stopSequence = reader.uint32();
            continue;
          }
          case 2: {
            if (wireType !== 2)
              break;
            message.stopId = reader.string();
            continue;
          }
        }
        reader.skipType(wireType, _depth, tag);
        if (!reader.discardUnknown) {
          $util.makeProp(message, "$unknowns", false);
          (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
        }
      }
      if (length !== $undefined) {
        if (reader.pos !== end)
          throw $RangeError("index out of range");
        reader.len = length;
      }
      if (_end !== $undefined)
        throw $Error("missing end group");
      return message;
    };
    StopSelector.decodeDelimited = function(reader) {
      if (!(reader instanceof $Reader))
        reader = new $Reader(reader);
      return this.decode(reader, reader.uint32());
    };
    StopSelector.verify = function(message, _depth) {
      if (typeof message !== "object" || message === null)
        return "object expected";
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        return "max depth exceeded";
      if (message.stopSequence != null && $Object.hasOwnProperty.call(message, "stopSequence")) {
        if (!$util.isInteger(message.stopSequence))
          return "stopSequence: integer expected";
      }
      if (message.stopId != null && $Object.hasOwnProperty.call(message, "stopId")) {
        if (!$util.isString(message.stopId))
          return "stopId: string expected";
      }
      return null;
    };
    StopSelector.fromObject = function(object, _depth) {
      if (object instanceof $root.transit_realtime.StopSelector)
        return object;
      if (!$util.isObject(object))
        throw $TypeError(".transit_realtime.StopSelector: object expected");
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let message = new $root.transit_realtime.StopSelector();
      if (object.stopSequence != null)
        message.stopSequence = object.stopSequence >>> 0;
      if (object.stopId != null)
        message.stopId = $String(object.stopId);
      return message;
    };
    StopSelector.toObject = function(message, options, _depth) {
      if (!options)
        options = {};
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let object = {};
      if (options.defaults) {
        object.stopSequence = 0;
        object.stopId = "";
      }
      if (message.stopSequence != null && $Object.hasOwnProperty.call(message, "stopSequence"))
        object.stopSequence = message.stopSequence;
      if (message.stopId != null && $Object.hasOwnProperty.call(message, "stopId"))
        object.stopId = message.stopId;
      return object;
    };
    StopSelector.prototype.toJSON = function() {
      return StopSelector.toObject(this, import_minimal.default.util.toJSONOptions);
    };
    StopSelector.getTypeUrl = function(prefix) {
      if (prefix === $undefined)
        prefix = "type.googleapis.com";
      return prefix + "/transit_realtime.StopSelector";
    };
    return StopSelector;
  })();
  transit_realtime2.ReplacementStop = (function() {
    const ReplacementStop = /* @__PURE__ */ __name(function(properties) {
      if (properties) {
        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
          if (properties[keys[i]] != null && keys[i] !== "__proto__")
            this[keys[i]] = properties[keys[i]];
      }
    }, "ReplacementStop");
    ReplacementStop.prototype.travelTimeToStop = 0;
    ReplacementStop.prototype.stopId = "";
    ReplacementStop.create = function(properties) {
      return new ReplacementStop(properties);
    };
    ReplacementStop.encode = function(message, writer, _depth) {
      if (!writer)
        writer = $Writer.create();
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      if (message.travelTimeToStop != null && $Object.hasOwnProperty.call(message, "travelTimeToStop"))
        writer.uint32(
          /* id 1, wireType 0 =*/
          8
        ).int32(message.travelTimeToStop);
      if (message.stopId != null && $Object.hasOwnProperty.call(message, "stopId"))
        writer.uint32(
          /* id 2, wireType 2 =*/
          18
        ).string(message.stopId);
      if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
        for (let i = 0; i < message.$unknowns.length; ++i)
          writer.raw(message.$unknowns[i]);
      return writer;
    };
    ReplacementStop.encodeDelimited = function(message, writer) {
      return this.encode(message, (writer || $Writer.create()).fork()).ldelim();
    };
    ReplacementStop.decode = function(reader, length, _end, _depth, _target) {
      if (!(reader instanceof $Reader))
        reader = $Reader.create(reader);
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $Reader.recursionLimit)
        throw $Error("max depth exceeded");
      let end, message;
      if (length === $undefined)
        end = reader.len;
      else {
        end = reader.pos + length;
        if (end > reader.len)
          throw $RangeError("index out of range");
        length = reader.len;
        reader.len = end;
      }
      message = _target || new $root.transit_realtime.ReplacementStop();
      while (reader.pos < end) {
        let start = reader.pos;
        let tag = reader.tag();
        if (tag === _end) {
          _end = $undefined;
          break;
        }
        let wireType = tag & 7;
        switch (tag >>>= 3) {
          case 1: {
            if (wireType !== 0)
              break;
            message.travelTimeToStop = reader.int32();
            continue;
          }
          case 2: {
            if (wireType !== 2)
              break;
            message.stopId = reader.string();
            continue;
          }
        }
        reader.skipType(wireType, _depth, tag);
        if (!reader.discardUnknown) {
          $util.makeProp(message, "$unknowns", false);
          (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
        }
      }
      if (length !== $undefined) {
        if (reader.pos !== end)
          throw $RangeError("index out of range");
        reader.len = length;
      }
      if (_end !== $undefined)
        throw $Error("missing end group");
      return message;
    };
    ReplacementStop.decodeDelimited = function(reader) {
      if (!(reader instanceof $Reader))
        reader = new $Reader(reader);
      return this.decode(reader, reader.uint32());
    };
    ReplacementStop.verify = function(message, _depth) {
      if (typeof message !== "object" || message === null)
        return "object expected";
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        return "max depth exceeded";
      if (message.travelTimeToStop != null && $Object.hasOwnProperty.call(message, "travelTimeToStop")) {
        if (!$util.isInteger(message.travelTimeToStop))
          return "travelTimeToStop: integer expected";
      }
      if (message.stopId != null && $Object.hasOwnProperty.call(message, "stopId")) {
        if (!$util.isString(message.stopId))
          return "stopId: string expected";
      }
      return null;
    };
    ReplacementStop.fromObject = function(object, _depth) {
      if (object instanceof $root.transit_realtime.ReplacementStop)
        return object;
      if (!$util.isObject(object))
        throw $TypeError(".transit_realtime.ReplacementStop: object expected");
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let message = new $root.transit_realtime.ReplacementStop();
      if (object.travelTimeToStop != null)
        message.travelTimeToStop = object.travelTimeToStop | 0;
      if (object.stopId != null)
        message.stopId = $String(object.stopId);
      return message;
    };
    ReplacementStop.toObject = function(message, options, _depth) {
      if (!options)
        options = {};
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let object = {};
      if (options.defaults) {
        object.travelTimeToStop = 0;
        object.stopId = "";
      }
      if (message.travelTimeToStop != null && $Object.hasOwnProperty.call(message, "travelTimeToStop"))
        object.travelTimeToStop = message.travelTimeToStop;
      if (message.stopId != null && $Object.hasOwnProperty.call(message, "stopId"))
        object.stopId = message.stopId;
      return object;
    };
    ReplacementStop.prototype.toJSON = function() {
      return ReplacementStop.toObject(this, import_minimal.default.util.toJSONOptions);
    };
    ReplacementStop.getTypeUrl = function(prefix) {
      if (prefix === $undefined)
        prefix = "type.googleapis.com";
      return prefix + "/transit_realtime.ReplacementStop";
    };
    return ReplacementStop;
  })();
  transit_realtime2.TripReplacementPeriod = (function() {
    const TripReplacementPeriod = /* @__PURE__ */ __name(function(properties) {
      if (properties) {
        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
          if (properties[keys[i]] != null && keys[i] !== "__proto__")
            this[keys[i]] = properties[keys[i]];
      }
    }, "TripReplacementPeriod");
    TripReplacementPeriod.prototype.routeId = "";
    TripReplacementPeriod.prototype.replacementPeriod = null;
    TripReplacementPeriod.create = function(properties) {
      return new TripReplacementPeriod(properties);
    };
    TripReplacementPeriod.encode = function(message, writer, _depth) {
      if (!writer)
        writer = $Writer.create();
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      if (message.routeId != null && $Object.hasOwnProperty.call(message, "routeId"))
        writer.uint32(
          /* id 1, wireType 2 =*/
          10
        ).string(message.routeId);
      if (message.replacementPeriod != null && $Object.hasOwnProperty.call(message, "replacementPeriod"))
        $root.transit_realtime.TimeRange.encode(message.replacementPeriod, writer.uint32(
          /* id 2, wireType 2 =*/
          18
        ).fork(), _depth + 1).ldelim();
      if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
        for (let i = 0; i < message.$unknowns.length; ++i)
          writer.raw(message.$unknowns[i]);
      return writer;
    };
    TripReplacementPeriod.encodeDelimited = function(message, writer) {
      return this.encode(message, (writer || $Writer.create()).fork()).ldelim();
    };
    TripReplacementPeriod.decode = function(reader, length, _end, _depth, _target) {
      if (!(reader instanceof $Reader))
        reader = $Reader.create(reader);
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $Reader.recursionLimit)
        throw $Error("max depth exceeded");
      let end, message;
      if (length === $undefined)
        end = reader.len;
      else {
        end = reader.pos + length;
        if (end > reader.len)
          throw $RangeError("index out of range");
        length = reader.len;
        reader.len = end;
      }
      message = _target || new $root.transit_realtime.TripReplacementPeriod();
      while (reader.pos < end) {
        let start = reader.pos;
        let tag = reader.tag();
        if (tag === _end) {
          _end = $undefined;
          break;
        }
        let wireType = tag & 7;
        switch (tag >>>= 3) {
          case 1: {
            if (wireType !== 2)
              break;
            message.routeId = reader.string();
            continue;
          }
          case 2: {
            if (wireType !== 2)
              break;
            message.replacementPeriod = $root.transit_realtime.TimeRange.decode(reader, reader.uint32(), $undefined, _depth + 1, message.replacementPeriod);
            continue;
          }
        }
        reader.skipType(wireType, _depth, tag);
        if (!reader.discardUnknown) {
          $util.makeProp(message, "$unknowns", false);
          (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
        }
      }
      if (length !== $undefined) {
        if (reader.pos !== end)
          throw $RangeError("index out of range");
        reader.len = length;
      }
      if (_end !== $undefined)
        throw $Error("missing end group");
      return message;
    };
    TripReplacementPeriod.decodeDelimited = function(reader) {
      if (!(reader instanceof $Reader))
        reader = new $Reader(reader);
      return this.decode(reader, reader.uint32());
    };
    TripReplacementPeriod.verify = function(message, _depth) {
      if (typeof message !== "object" || message === null)
        return "object expected";
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        return "max depth exceeded";
      if (message.routeId != null && $Object.hasOwnProperty.call(message, "routeId")) {
        if (!$util.isString(message.routeId))
          return "routeId: string expected";
      }
      if (message.replacementPeriod != null && $Object.hasOwnProperty.call(message, "replacementPeriod")) {
        let error = $root.transit_realtime.TimeRange.verify(message.replacementPeriod, _depth + 1);
        if (error)
          return "replacementPeriod." + error;
      }
      return null;
    };
    TripReplacementPeriod.fromObject = function(object, _depth) {
      if (object instanceof $root.transit_realtime.TripReplacementPeriod)
        return object;
      if (!$util.isObject(object))
        throw $TypeError(".transit_realtime.TripReplacementPeriod: object expected");
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let message = new $root.transit_realtime.TripReplacementPeriod();
      if (object.routeId != null)
        message.routeId = $String(object.routeId);
      if (object.replacementPeriod != null) {
        if (!$util.isObject(object.replacementPeriod))
          throw $TypeError(".transit_realtime.TripReplacementPeriod.replacementPeriod: object expected");
        message.replacementPeriod = $root.transit_realtime.TimeRange.fromObject(object.replacementPeriod, _depth + 1);
      }
      return message;
    };
    TripReplacementPeriod.toObject = function(message, options, _depth) {
      if (!options)
        options = {};
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let object = {};
      if (options.defaults) {
        object.routeId = "";
        object.replacementPeriod = null;
      }
      if (message.routeId != null && $Object.hasOwnProperty.call(message, "routeId"))
        object.routeId = message.routeId;
      if (message.replacementPeriod != null && $Object.hasOwnProperty.call(message, "replacementPeriod"))
        object.replacementPeriod = $root.transit_realtime.TimeRange.toObject(message.replacementPeriod, options, _depth + 1);
      return object;
    };
    TripReplacementPeriod.prototype.toJSON = function() {
      return TripReplacementPeriod.toObject(this, import_minimal.default.util.toJSONOptions);
    };
    TripReplacementPeriod.getTypeUrl = function(prefix) {
      if (prefix === $undefined)
        prefix = "type.googleapis.com";
      return prefix + "/transit_realtime.TripReplacementPeriod";
    };
    return TripReplacementPeriod;
  })();
  transit_realtime2.NyctFeedHeader = (function() {
    const NyctFeedHeader = /* @__PURE__ */ __name(function(properties) {
      this.tripReplacementPeriod = [];
      if (properties) {
        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
          if (properties[keys[i]] != null && keys[i] !== "__proto__")
            this[keys[i]] = properties[keys[i]];
      }
    }, "NyctFeedHeader");
    NyctFeedHeader.prototype.nyctSubwayVersion = "";
    NyctFeedHeader.prototype.tripReplacementPeriod = $util.emptyArray;
    NyctFeedHeader.create = function(properties) {
      return new NyctFeedHeader(properties);
    };
    NyctFeedHeader.encode = function(message, writer, _depth) {
      if (!writer)
        writer = $Writer.create();
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      writer.uint32(
        /* id 1, wireType 2 =*/
        10
      ).string(message.nyctSubwayVersion);
      if (message.tripReplacementPeriod != null && message.tripReplacementPeriod.length)
        for (let i = 0; i < message.tripReplacementPeriod.length; ++i)
          $root.transit_realtime.TripReplacementPeriod.encode(message.tripReplacementPeriod[i], writer.uint32(
            /* id 2, wireType 2 =*/
            18
          ).fork(), _depth + 1).ldelim();
      if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
        for (let i = 0; i < message.$unknowns.length; ++i)
          writer.raw(message.$unknowns[i]);
      return writer;
    };
    NyctFeedHeader.encodeDelimited = function(message, writer) {
      return this.encode(message, (writer || $Writer.create()).fork()).ldelim();
    };
    NyctFeedHeader.decode = function(reader, length, _end, _depth, _target) {
      if (!(reader instanceof $Reader))
        reader = $Reader.create(reader);
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $Reader.recursionLimit)
        throw $Error("max depth exceeded");
      let end, message;
      if (length === $undefined)
        end = reader.len;
      else {
        end = reader.pos + length;
        if (end > reader.len)
          throw $RangeError("index out of range");
        length = reader.len;
        reader.len = end;
      }
      message = _target || new $root.transit_realtime.NyctFeedHeader();
      while (reader.pos < end) {
        let start = reader.pos;
        let tag = reader.tag();
        if (tag === _end) {
          _end = $undefined;
          break;
        }
        let wireType = tag & 7;
        switch (tag >>>= 3) {
          case 1: {
            if (wireType !== 2)
              break;
            message.nyctSubwayVersion = reader.string();
            continue;
          }
          case 2: {
            if (wireType !== 2)
              break;
            if (!(message.tripReplacementPeriod && message.tripReplacementPeriod.length))
              message.tripReplacementPeriod = [];
            message.tripReplacementPeriod.push($root.transit_realtime.TripReplacementPeriod.decode(reader, reader.uint32(), $undefined, _depth + 1));
            continue;
          }
        }
        reader.skipType(wireType, _depth, tag);
        if (!reader.discardUnknown) {
          $util.makeProp(message, "$unknowns", false);
          (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
        }
      }
      if (length !== $undefined) {
        if (reader.pos !== end)
          throw $RangeError("index out of range");
        reader.len = length;
      }
      if (_end !== $undefined)
        throw $Error("missing end group");
      if (!$Object.hasOwnProperty.call(message, "nyctSubwayVersion"))
        throw $util.ProtocolError("missing required 'nyctSubwayVersion'", { instance: message });
      return message;
    };
    NyctFeedHeader.decodeDelimited = function(reader) {
      if (!(reader instanceof $Reader))
        reader = new $Reader(reader);
      return this.decode(reader, reader.uint32());
    };
    NyctFeedHeader.verify = function(message, _depth) {
      if (typeof message !== "object" || message === null)
        return "object expected";
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        return "max depth exceeded";
      if (!$util.isString(message.nyctSubwayVersion))
        return "nyctSubwayVersion: string expected";
      if (message.tripReplacementPeriod != null && $Object.hasOwnProperty.call(message, "tripReplacementPeriod")) {
        if (!$Array.isArray(message.tripReplacementPeriod))
          return "tripReplacementPeriod: array expected";
        for (let i = 0; i < message.tripReplacementPeriod.length; ++i) {
          let error = $root.transit_realtime.TripReplacementPeriod.verify(message.tripReplacementPeriod[i], _depth + 1);
          if (error)
            return "tripReplacementPeriod." + error;
        }
      }
      return null;
    };
    NyctFeedHeader.fromObject = function(object, _depth) {
      if (object instanceof $root.transit_realtime.NyctFeedHeader)
        return object;
      if (!$util.isObject(object))
        throw $TypeError(".transit_realtime.NyctFeedHeader: object expected");
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let message = new $root.transit_realtime.NyctFeedHeader();
      if (object.nyctSubwayVersion != null)
        message.nyctSubwayVersion = $String(object.nyctSubwayVersion);
      if (object.tripReplacementPeriod) {
        if (!$Array.isArray(object.tripReplacementPeriod))
          throw $TypeError(".transit_realtime.NyctFeedHeader.tripReplacementPeriod: array expected");
        message.tripReplacementPeriod = $Array(object.tripReplacementPeriod.length);
        for (let i = 0; i < object.tripReplacementPeriod.length; ++i) {
          if (!$util.isObject(object.tripReplacementPeriod[i]))
            throw $TypeError(".transit_realtime.NyctFeedHeader.tripReplacementPeriod: object expected");
          message.tripReplacementPeriod[i] = $root.transit_realtime.TripReplacementPeriod.fromObject(object.tripReplacementPeriod[i], _depth + 1);
        }
      }
      return message;
    };
    NyctFeedHeader.toObject = function(message, options, _depth) {
      if (!options)
        options = {};
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let object = {};
      if (options.arrays || options.defaults)
        object.tripReplacementPeriod = [];
      if (options.defaults)
        object.nyctSubwayVersion = "";
      if (message.nyctSubwayVersion != null && $Object.hasOwnProperty.call(message, "nyctSubwayVersion"))
        object.nyctSubwayVersion = message.nyctSubwayVersion;
      if (message.tripReplacementPeriod && message.tripReplacementPeriod.length) {
        object.tripReplacementPeriod = $Array(message.tripReplacementPeriod.length);
        for (let j = 0; j < message.tripReplacementPeriod.length; ++j)
          object.tripReplacementPeriod[j] = $root.transit_realtime.TripReplacementPeriod.toObject(message.tripReplacementPeriod[j], options, _depth + 1);
      }
      return object;
    };
    NyctFeedHeader.prototype.toJSON = function() {
      return NyctFeedHeader.toObject(this, import_minimal.default.util.toJSONOptions);
    };
    NyctFeedHeader.getTypeUrl = function(prefix) {
      if (prefix === $undefined)
        prefix = "type.googleapis.com";
      return prefix + "/transit_realtime.NyctFeedHeader";
    };
    return NyctFeedHeader;
  })();
  transit_realtime2.NyctTripDescriptor = (function() {
    const NyctTripDescriptor = /* @__PURE__ */ __name(function(properties) {
      if (properties) {
        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
          if (properties[keys[i]] != null && keys[i] !== "__proto__")
            this[keys[i]] = properties[keys[i]];
      }
    }, "NyctTripDescriptor");
    NyctTripDescriptor.prototype.trainId = "";
    NyctTripDescriptor.prototype.isAssigned = false;
    NyctTripDescriptor.prototype.direction = 1;
    NyctTripDescriptor.create = function(properties) {
      return new NyctTripDescriptor(properties);
    };
    NyctTripDescriptor.encode = function(message, writer, _depth) {
      if (!writer)
        writer = $Writer.create();
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      if (message.trainId != null && $Object.hasOwnProperty.call(message, "trainId"))
        writer.uint32(
          /* id 1, wireType 2 =*/
          10
        ).string(message.trainId);
      if (message.isAssigned != null && $Object.hasOwnProperty.call(message, "isAssigned"))
        writer.uint32(
          /* id 2, wireType 0 =*/
          16
        ).bool(message.isAssigned);
      if (message.direction != null && $Object.hasOwnProperty.call(message, "direction"))
        writer.uint32(
          /* id 3, wireType 0 =*/
          24
        ).int32(message.direction);
      if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
        for (let i = 0; i < message.$unknowns.length; ++i)
          writer.raw(message.$unknowns[i]);
      return writer;
    };
    NyctTripDescriptor.encodeDelimited = function(message, writer) {
      return this.encode(message, (writer || $Writer.create()).fork()).ldelim();
    };
    NyctTripDescriptor.decode = function(reader, length, _end, _depth, _target) {
      if (!(reader instanceof $Reader))
        reader = $Reader.create(reader);
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $Reader.recursionLimit)
        throw $Error("max depth exceeded");
      let end, message, value;
      if (length === $undefined)
        end = reader.len;
      else {
        end = reader.pos + length;
        if (end > reader.len)
          throw $RangeError("index out of range");
        length = reader.len;
        reader.len = end;
      }
      message = _target || new $root.transit_realtime.NyctTripDescriptor();
      while (reader.pos < end) {
        let start = reader.pos;
        let tag = reader.tag();
        if (tag === _end) {
          _end = $undefined;
          break;
        }
        let wireType = tag & 7;
        switch (tag >>>= 3) {
          case 1: {
            if (wireType !== 2)
              break;
            message.trainId = reader.string();
            continue;
          }
          case 2: {
            if (wireType !== 0)
              break;
            message.isAssigned = reader.bool();
            continue;
          }
          case 3: {
            if (wireType !== 0)
              break;
            value = reader.int32();
            if ($root.transit_realtime.NyctTripDescriptor.Direction[value] !== $undefined)
              message.direction = value;
            else if (!reader.discardUnknown) {
              $util.makeProp(message, "$unknowns", false);
              (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
            }
            continue;
          }
        }
        reader.skipType(wireType, _depth, tag);
        if (!reader.discardUnknown) {
          $util.makeProp(message, "$unknowns", false);
          (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
        }
      }
      if (length !== $undefined) {
        if (reader.pos !== end)
          throw $RangeError("index out of range");
        reader.len = length;
      }
      if (_end !== $undefined)
        throw $Error("missing end group");
      return message;
    };
    NyctTripDescriptor.decodeDelimited = function(reader) {
      if (!(reader instanceof $Reader))
        reader = new $Reader(reader);
      return this.decode(reader, reader.uint32());
    };
    NyctTripDescriptor.verify = function(message, _depth) {
      if (typeof message !== "object" || message === null)
        return "object expected";
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        return "max depth exceeded";
      if (message.trainId != null && $Object.hasOwnProperty.call(message, "trainId")) {
        if (!$util.isString(message.trainId))
          return "trainId: string expected";
      }
      if (message.isAssigned != null && $Object.hasOwnProperty.call(message, "isAssigned")) {
        if (typeof message.isAssigned !== "boolean")
          return "isAssigned: boolean expected";
      }
      if (message.direction != null && $Object.hasOwnProperty.call(message, "direction"))
        switch (message.direction) {
          default:
            return "direction: enum value expected";
          case 1:
          case 2:
          case 3:
          case 4:
            break;
        }
      return null;
    };
    NyctTripDescriptor.fromObject = function(object, _depth) {
      if (object instanceof $root.transit_realtime.NyctTripDescriptor)
        return object;
      if (!$util.isObject(object))
        throw $TypeError(".transit_realtime.NyctTripDescriptor: object expected");
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let message = new $root.transit_realtime.NyctTripDescriptor();
      if (object.trainId != null)
        message.trainId = $String(object.trainId);
      if (object.isAssigned != null)
        message.isAssigned = $Boolean(object.isAssigned);
      switch (object.direction) {
        case "NORTH":
        case 1:
          message.direction = 1;
          break;
        case "EAST":
        case 2:
          message.direction = 2;
          break;
        case "SOUTH":
        case 3:
          message.direction = 3;
          break;
        case "WEST":
        case 4:
          message.direction = 4;
          break;
        default:
      }
      return message;
    };
    NyctTripDescriptor.toObject = function(message, options, _depth) {
      if (!options)
        options = {};
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let object = {};
      if (options.defaults) {
        object.trainId = "";
        object.isAssigned = false;
        object.direction = options.enums === $String ? "NORTH" : 1;
      }
      if (message.trainId != null && $Object.hasOwnProperty.call(message, "trainId"))
        object.trainId = message.trainId;
      if (message.isAssigned != null && $Object.hasOwnProperty.call(message, "isAssigned"))
        object.isAssigned = message.isAssigned;
      if (message.direction != null && $Object.hasOwnProperty.call(message, "direction"))
        object.direction = options.enums === $String ? $root.transit_realtime.NyctTripDescriptor.Direction[message.direction] === $undefined ? message.direction : $root.transit_realtime.NyctTripDescriptor.Direction[message.direction] : message.direction;
      return object;
    };
    NyctTripDescriptor.prototype.toJSON = function() {
      return NyctTripDescriptor.toObject(this, import_minimal.default.util.toJSONOptions);
    };
    NyctTripDescriptor.getTypeUrl = function(prefix) {
      if (prefix === $undefined)
        prefix = "type.googleapis.com";
      return prefix + "/transit_realtime.NyctTripDescriptor";
    };
    NyctTripDescriptor.Direction = (function() {
      const valuesById = $Object.create(null), values = $Object.create(valuesById);
      values[valuesById[1] = "NORTH"] = 1;
      values[valuesById[2] = "EAST"] = 2;
      values[valuesById[3] = "SOUTH"] = 3;
      values[valuesById[4] = "WEST"] = 4;
      return values;
    })();
    return NyctTripDescriptor;
  })();
  transit_realtime2.NyctStopTimeUpdate = (function() {
    const NyctStopTimeUpdate = /* @__PURE__ */ __name(function(properties) {
      if (properties) {
        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
          if (properties[keys[i]] != null && keys[i] !== "__proto__")
            this[keys[i]] = properties[keys[i]];
      }
    }, "NyctStopTimeUpdate");
    NyctStopTimeUpdate.prototype.scheduledTrack = "";
    NyctStopTimeUpdate.prototype.actualTrack = "";
    NyctStopTimeUpdate.create = function(properties) {
      return new NyctStopTimeUpdate(properties);
    };
    NyctStopTimeUpdate.encode = function(message, writer, _depth) {
      if (!writer)
        writer = $Writer.create();
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      if (message.scheduledTrack != null && $Object.hasOwnProperty.call(message, "scheduledTrack"))
        writer.uint32(
          /* id 1, wireType 2 =*/
          10
        ).string(message.scheduledTrack);
      if (message.actualTrack != null && $Object.hasOwnProperty.call(message, "actualTrack"))
        writer.uint32(
          /* id 2, wireType 2 =*/
          18
        ).string(message.actualTrack);
      if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
        for (let i = 0; i < message.$unknowns.length; ++i)
          writer.raw(message.$unknowns[i]);
      return writer;
    };
    NyctStopTimeUpdate.encodeDelimited = function(message, writer) {
      return this.encode(message, (writer || $Writer.create()).fork()).ldelim();
    };
    NyctStopTimeUpdate.decode = function(reader, length, _end, _depth, _target) {
      if (!(reader instanceof $Reader))
        reader = $Reader.create(reader);
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $Reader.recursionLimit)
        throw $Error("max depth exceeded");
      let end, message;
      if (length === $undefined)
        end = reader.len;
      else {
        end = reader.pos + length;
        if (end > reader.len)
          throw $RangeError("index out of range");
        length = reader.len;
        reader.len = end;
      }
      message = _target || new $root.transit_realtime.NyctStopTimeUpdate();
      while (reader.pos < end) {
        let start = reader.pos;
        let tag = reader.tag();
        if (tag === _end) {
          _end = $undefined;
          break;
        }
        let wireType = tag & 7;
        switch (tag >>>= 3) {
          case 1: {
            if (wireType !== 2)
              break;
            message.scheduledTrack = reader.string();
            continue;
          }
          case 2: {
            if (wireType !== 2)
              break;
            message.actualTrack = reader.string();
            continue;
          }
        }
        reader.skipType(wireType, _depth, tag);
        if (!reader.discardUnknown) {
          $util.makeProp(message, "$unknowns", false);
          (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
        }
      }
      if (length !== $undefined) {
        if (reader.pos !== end)
          throw $RangeError("index out of range");
        reader.len = length;
      }
      if (_end !== $undefined)
        throw $Error("missing end group");
      return message;
    };
    NyctStopTimeUpdate.decodeDelimited = function(reader) {
      if (!(reader instanceof $Reader))
        reader = new $Reader(reader);
      return this.decode(reader, reader.uint32());
    };
    NyctStopTimeUpdate.verify = function(message, _depth) {
      if (typeof message !== "object" || message === null)
        return "object expected";
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        return "max depth exceeded";
      if (message.scheduledTrack != null && $Object.hasOwnProperty.call(message, "scheduledTrack")) {
        if (!$util.isString(message.scheduledTrack))
          return "scheduledTrack: string expected";
      }
      if (message.actualTrack != null && $Object.hasOwnProperty.call(message, "actualTrack")) {
        if (!$util.isString(message.actualTrack))
          return "actualTrack: string expected";
      }
      return null;
    };
    NyctStopTimeUpdate.fromObject = function(object, _depth) {
      if (object instanceof $root.transit_realtime.NyctStopTimeUpdate)
        return object;
      if (!$util.isObject(object))
        throw $TypeError(".transit_realtime.NyctStopTimeUpdate: object expected");
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let message = new $root.transit_realtime.NyctStopTimeUpdate();
      if (object.scheduledTrack != null)
        message.scheduledTrack = $String(object.scheduledTrack);
      if (object.actualTrack != null)
        message.actualTrack = $String(object.actualTrack);
      return message;
    };
    NyctStopTimeUpdate.toObject = function(message, options, _depth) {
      if (!options)
        options = {};
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let object = {};
      if (options.defaults) {
        object.scheduledTrack = "";
        object.actualTrack = "";
      }
      if (message.scheduledTrack != null && $Object.hasOwnProperty.call(message, "scheduledTrack"))
        object.scheduledTrack = message.scheduledTrack;
      if (message.actualTrack != null && $Object.hasOwnProperty.call(message, "actualTrack"))
        object.actualTrack = message.actualTrack;
      return object;
    };
    NyctStopTimeUpdate.prototype.toJSON = function() {
      return NyctStopTimeUpdate.toObject(this, import_minimal.default.util.toJSONOptions);
    };
    NyctStopTimeUpdate.getTypeUrl = function(prefix) {
      if (prefix === $undefined)
        prefix = "type.googleapis.com";
      return prefix + "/transit_realtime.NyctStopTimeUpdate";
    };
    return NyctStopTimeUpdate;
  })();
  transit_realtime2.MercuryFeedHeader = (function() {
    const MercuryFeedHeader = /* @__PURE__ */ __name(function(properties) {
      if (properties) {
        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
          if (properties[keys[i]] != null && keys[i] !== "__proto__")
            this[keys[i]] = properties[keys[i]];
      }
    }, "MercuryFeedHeader");
    MercuryFeedHeader.prototype.mercuryVersion = "";
    MercuryFeedHeader.create = function(properties) {
      return new MercuryFeedHeader(properties);
    };
    MercuryFeedHeader.encode = function(message, writer, _depth) {
      if (!writer)
        writer = $Writer.create();
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      writer.uint32(
        /* id 1, wireType 2 =*/
        10
      ).string(message.mercuryVersion);
      if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
        for (let i = 0; i < message.$unknowns.length; ++i)
          writer.raw(message.$unknowns[i]);
      return writer;
    };
    MercuryFeedHeader.encodeDelimited = function(message, writer) {
      return this.encode(message, (writer || $Writer.create()).fork()).ldelim();
    };
    MercuryFeedHeader.decode = function(reader, length, _end, _depth, _target) {
      if (!(reader instanceof $Reader))
        reader = $Reader.create(reader);
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $Reader.recursionLimit)
        throw $Error("max depth exceeded");
      let end, message;
      if (length === $undefined)
        end = reader.len;
      else {
        end = reader.pos + length;
        if (end > reader.len)
          throw $RangeError("index out of range");
        length = reader.len;
        reader.len = end;
      }
      message = _target || new $root.transit_realtime.MercuryFeedHeader();
      while (reader.pos < end) {
        let start = reader.pos;
        let tag = reader.tag();
        if (tag === _end) {
          _end = $undefined;
          break;
        }
        let wireType = tag & 7;
        switch (tag >>>= 3) {
          case 1: {
            if (wireType !== 2)
              break;
            message.mercuryVersion = reader.string();
            continue;
          }
        }
        reader.skipType(wireType, _depth, tag);
        if (!reader.discardUnknown) {
          $util.makeProp(message, "$unknowns", false);
          (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
        }
      }
      if (length !== $undefined) {
        if (reader.pos !== end)
          throw $RangeError("index out of range");
        reader.len = length;
      }
      if (_end !== $undefined)
        throw $Error("missing end group");
      if (!$Object.hasOwnProperty.call(message, "mercuryVersion"))
        throw $util.ProtocolError("missing required 'mercuryVersion'", { instance: message });
      return message;
    };
    MercuryFeedHeader.decodeDelimited = function(reader) {
      if (!(reader instanceof $Reader))
        reader = new $Reader(reader);
      return this.decode(reader, reader.uint32());
    };
    MercuryFeedHeader.verify = function(message, _depth) {
      if (typeof message !== "object" || message === null)
        return "object expected";
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        return "max depth exceeded";
      if (!$util.isString(message.mercuryVersion))
        return "mercuryVersion: string expected";
      return null;
    };
    MercuryFeedHeader.fromObject = function(object, _depth) {
      if (object instanceof $root.transit_realtime.MercuryFeedHeader)
        return object;
      if (!$util.isObject(object))
        throw $TypeError(".transit_realtime.MercuryFeedHeader: object expected");
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let message = new $root.transit_realtime.MercuryFeedHeader();
      if (object.mercuryVersion != null)
        message.mercuryVersion = $String(object.mercuryVersion);
      return message;
    };
    MercuryFeedHeader.toObject = function(message, options, _depth) {
      if (!options)
        options = {};
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let object = {};
      if (options.defaults)
        object.mercuryVersion = "";
      if (message.mercuryVersion != null && $Object.hasOwnProperty.call(message, "mercuryVersion"))
        object.mercuryVersion = message.mercuryVersion;
      return object;
    };
    MercuryFeedHeader.prototype.toJSON = function() {
      return MercuryFeedHeader.toObject(this, import_minimal.default.util.toJSONOptions);
    };
    MercuryFeedHeader.getTypeUrl = function(prefix) {
      if (prefix === $undefined)
        prefix = "type.googleapis.com";
      return prefix + "/transit_realtime.MercuryFeedHeader";
    };
    return MercuryFeedHeader;
  })();
  transit_realtime2.MercuryStationAlternative = (function() {
    const MercuryStationAlternative = /* @__PURE__ */ __name(function(properties) {
      if (properties) {
        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
          if (properties[keys[i]] != null && keys[i] !== "__proto__")
            this[keys[i]] = properties[keys[i]];
      }
    }, "MercuryStationAlternative");
    MercuryStationAlternative.prototype.affectedEntity = null;
    MercuryStationAlternative.prototype.notes = null;
    MercuryStationAlternative.create = function(properties) {
      return new MercuryStationAlternative(properties);
    };
    MercuryStationAlternative.encode = function(message, writer, _depth) {
      if (!writer)
        writer = $Writer.create();
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      $root.transit_realtime.EntitySelector.encode(message.affectedEntity, writer.uint32(
        /* id 1, wireType 2 =*/
        10
      ).fork(), _depth + 1).ldelim();
      $root.transit_realtime.TranslatedString.encode(message.notes, writer.uint32(
        /* id 2, wireType 2 =*/
        18
      ).fork(), _depth + 1).ldelim();
      if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
        for (let i = 0; i < message.$unknowns.length; ++i)
          writer.raw(message.$unknowns[i]);
      return writer;
    };
    MercuryStationAlternative.encodeDelimited = function(message, writer) {
      return this.encode(message, (writer || $Writer.create()).fork()).ldelim();
    };
    MercuryStationAlternative.decode = function(reader, length, _end, _depth, _target) {
      if (!(reader instanceof $Reader))
        reader = $Reader.create(reader);
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $Reader.recursionLimit)
        throw $Error("max depth exceeded");
      let end, message;
      if (length === $undefined)
        end = reader.len;
      else {
        end = reader.pos + length;
        if (end > reader.len)
          throw $RangeError("index out of range");
        length = reader.len;
        reader.len = end;
      }
      message = _target || new $root.transit_realtime.MercuryStationAlternative();
      while (reader.pos < end) {
        let start = reader.pos;
        let tag = reader.tag();
        if (tag === _end) {
          _end = $undefined;
          break;
        }
        let wireType = tag & 7;
        switch (tag >>>= 3) {
          case 1: {
            if (wireType !== 2)
              break;
            message.affectedEntity = $root.transit_realtime.EntitySelector.decode(reader, reader.uint32(), $undefined, _depth + 1, message.affectedEntity);
            continue;
          }
          case 2: {
            if (wireType !== 2)
              break;
            message.notes = $root.transit_realtime.TranslatedString.decode(reader, reader.uint32(), $undefined, _depth + 1, message.notes);
            continue;
          }
        }
        reader.skipType(wireType, _depth, tag);
        if (!reader.discardUnknown) {
          $util.makeProp(message, "$unknowns", false);
          (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
        }
      }
      if (length !== $undefined) {
        if (reader.pos !== end)
          throw $RangeError("index out of range");
        reader.len = length;
      }
      if (_end !== $undefined)
        throw $Error("missing end group");
      if (!$Object.hasOwnProperty.call(message, "affectedEntity"))
        throw $util.ProtocolError("missing required 'affectedEntity'", { instance: message });
      if (!$Object.hasOwnProperty.call(message, "notes"))
        throw $util.ProtocolError("missing required 'notes'", { instance: message });
      return message;
    };
    MercuryStationAlternative.decodeDelimited = function(reader) {
      if (!(reader instanceof $Reader))
        reader = new $Reader(reader);
      return this.decode(reader, reader.uint32());
    };
    MercuryStationAlternative.verify = function(message, _depth) {
      if (typeof message !== "object" || message === null)
        return "object expected";
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        return "max depth exceeded";
      {
        let error = $root.transit_realtime.EntitySelector.verify(message.affectedEntity, _depth + 1);
        if (error)
          return "affectedEntity." + error;
      }
      {
        let error = $root.transit_realtime.TranslatedString.verify(message.notes, _depth + 1);
        if (error)
          return "notes." + error;
      }
      return null;
    };
    MercuryStationAlternative.fromObject = function(object, _depth) {
      if (object instanceof $root.transit_realtime.MercuryStationAlternative)
        return object;
      if (!$util.isObject(object))
        throw $TypeError(".transit_realtime.MercuryStationAlternative: object expected");
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let message = new $root.transit_realtime.MercuryStationAlternative();
      if (object.affectedEntity != null) {
        if (!$util.isObject(object.affectedEntity))
          throw $TypeError(".transit_realtime.MercuryStationAlternative.affectedEntity: object expected");
        message.affectedEntity = $root.transit_realtime.EntitySelector.fromObject(object.affectedEntity, _depth + 1);
      }
      if (object.notes != null) {
        if (!$util.isObject(object.notes))
          throw $TypeError(".transit_realtime.MercuryStationAlternative.notes: object expected");
        message.notes = $root.transit_realtime.TranslatedString.fromObject(object.notes, _depth + 1);
      }
      return message;
    };
    MercuryStationAlternative.toObject = function(message, options, _depth) {
      if (!options)
        options = {};
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let object = {};
      if (options.defaults) {
        object.affectedEntity = null;
        object.notes = null;
      }
      if (message.affectedEntity != null && $Object.hasOwnProperty.call(message, "affectedEntity"))
        object.affectedEntity = $root.transit_realtime.EntitySelector.toObject(message.affectedEntity, options, _depth + 1);
      if (message.notes != null && $Object.hasOwnProperty.call(message, "notes"))
        object.notes = $root.transit_realtime.TranslatedString.toObject(message.notes, options, _depth + 1);
      return object;
    };
    MercuryStationAlternative.prototype.toJSON = function() {
      return MercuryStationAlternative.toObject(this, import_minimal.default.util.toJSONOptions);
    };
    MercuryStationAlternative.getTypeUrl = function(prefix) {
      if (prefix === $undefined)
        prefix = "type.googleapis.com";
      return prefix + "/transit_realtime.MercuryStationAlternative";
    };
    return MercuryStationAlternative;
  })();
  transit_realtime2.MercuryAlert = (function() {
    const MercuryAlert = /* @__PURE__ */ __name(function(properties) {
      this.stationAlternative = [];
      this.servicePlanNumber = [];
      this.generalOrderNumber = [];
      this.affectedStations = [];
      if (properties) {
        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
          if (properties[keys[i]] != null && keys[i] !== "__proto__")
            this[keys[i]] = properties[keys[i]];
      }
    }, "MercuryAlert");
    MercuryAlert.prototype.createdAt = $util.Long ? $util.Long.fromBits(0, 0, true) : 0;
    MercuryAlert.prototype.updatedAt = $util.Long ? $util.Long.fromBits(0, 0, true) : 0;
    MercuryAlert.prototype.alertType = "";
    MercuryAlert.prototype.stationAlternative = $util.emptyArray;
    MercuryAlert.prototype.servicePlanNumber = $util.emptyArray;
    MercuryAlert.prototype.generalOrderNumber = $util.emptyArray;
    MercuryAlert.prototype.displayBeforeActive = $util.Long ? $util.Long.fromBits(0, 0, true) : 0;
    MercuryAlert.prototype.humanReadableActivePeriod = null;
    MercuryAlert.prototype.directionality = $util.Long ? $util.Long.fromBits(0, 0, true) : 0;
    MercuryAlert.prototype.affectedStations = $util.emptyArray;
    MercuryAlert.prototype.screensSummary = null;
    MercuryAlert.prototype.noAffectedStations = false;
    MercuryAlert.prototype.cloneId = "";
    MercuryAlert.create = function(properties) {
      return new MercuryAlert(properties);
    };
    MercuryAlert.encode = function(message, writer, _depth) {
      if (!writer)
        writer = $Writer.create();
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      writer.uint32(
        /* id 1, wireType 0 =*/
        8
      ).uint64(message.createdAt);
      writer.uint32(
        /* id 2, wireType 0 =*/
        16
      ).uint64(message.updatedAt);
      writer.uint32(
        /* id 3, wireType 2 =*/
        26
      ).string(message.alertType);
      if (message.stationAlternative != null && message.stationAlternative.length)
        for (let i = 0; i < message.stationAlternative.length; ++i)
          $root.transit_realtime.MercuryStationAlternative.encode(message.stationAlternative[i], writer.uint32(
            /* id 4, wireType 2 =*/
            34
          ).fork(), _depth + 1).ldelim();
      if (message.servicePlanNumber != null && message.servicePlanNumber.length)
        for (let i = 0; i < message.servicePlanNumber.length; ++i)
          writer.uint32(
            /* id 5, wireType 2 =*/
            42
          ).string(message.servicePlanNumber[i]);
      if (message.generalOrderNumber != null && message.generalOrderNumber.length)
        for (let i = 0; i < message.generalOrderNumber.length; ++i)
          writer.uint32(
            /* id 6, wireType 2 =*/
            50
          ).string(message.generalOrderNumber[i]);
      if (message.displayBeforeActive != null && $Object.hasOwnProperty.call(message, "displayBeforeActive"))
        writer.uint32(
          /* id 7, wireType 0 =*/
          56
        ).uint64(message.displayBeforeActive);
      if (message.humanReadableActivePeriod != null && $Object.hasOwnProperty.call(message, "humanReadableActivePeriod"))
        $root.transit_realtime.TranslatedString.encode(message.humanReadableActivePeriod, writer.uint32(
          /* id 8, wireType 2 =*/
          66
        ).fork(), _depth + 1).ldelim();
      if (message.directionality != null && $Object.hasOwnProperty.call(message, "directionality"))
        writer.uint32(
          /* id 9, wireType 0 =*/
          72
        ).uint64(message.directionality);
      if (message.affectedStations != null && message.affectedStations.length)
        for (let i = 0; i < message.affectedStations.length; ++i)
          $root.transit_realtime.EntitySelector.encode(message.affectedStations[i], writer.uint32(
            /* id 10, wireType 2 =*/
            82
          ).fork(), _depth + 1).ldelim();
      if (message.screensSummary != null && $Object.hasOwnProperty.call(message, "screensSummary"))
        $root.transit_realtime.TranslatedString.encode(message.screensSummary, writer.uint32(
          /* id 11, wireType 2 =*/
          90
        ).fork(), _depth + 1).ldelim();
      if (message.noAffectedStations != null && $Object.hasOwnProperty.call(message, "noAffectedStations"))
        writer.uint32(
          /* id 12, wireType 0 =*/
          96
        ).bool(message.noAffectedStations);
      if (message.cloneId != null && $Object.hasOwnProperty.call(message, "cloneId"))
        writer.uint32(
          /* id 13, wireType 2 =*/
          106
        ).string(message.cloneId);
      if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
        for (let i = 0; i < message.$unknowns.length; ++i)
          writer.raw(message.$unknowns[i]);
      return writer;
    };
    MercuryAlert.encodeDelimited = function(message, writer) {
      return this.encode(message, (writer || $Writer.create()).fork()).ldelim();
    };
    MercuryAlert.decode = function(reader, length, _end, _depth, _target) {
      if (!(reader instanceof $Reader))
        reader = $Reader.create(reader);
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $Reader.recursionLimit)
        throw $Error("max depth exceeded");
      let end, message;
      if (length === $undefined)
        end = reader.len;
      else {
        end = reader.pos + length;
        if (end > reader.len)
          throw $RangeError("index out of range");
        length = reader.len;
        reader.len = end;
      }
      message = _target || new $root.transit_realtime.MercuryAlert();
      while (reader.pos < end) {
        let start = reader.pos;
        let tag = reader.tag();
        if (tag === _end) {
          _end = $undefined;
          break;
        }
        let wireType = tag & 7;
        switch (tag >>>= 3) {
          case 1: {
            if (wireType !== 0)
              break;
            message.createdAt = reader.uint64();
            continue;
          }
          case 2: {
            if (wireType !== 0)
              break;
            message.updatedAt = reader.uint64();
            continue;
          }
          case 3: {
            if (wireType !== 2)
              break;
            message.alertType = reader.string();
            continue;
          }
          case 4: {
            if (wireType !== 2)
              break;
            if (!(message.stationAlternative && message.stationAlternative.length))
              message.stationAlternative = [];
            message.stationAlternative.push($root.transit_realtime.MercuryStationAlternative.decode(reader, reader.uint32(), $undefined, _depth + 1));
            continue;
          }
          case 5: {
            if (wireType !== 2)
              break;
            if (!(message.servicePlanNumber && message.servicePlanNumber.length))
              message.servicePlanNumber = [];
            message.servicePlanNumber.push(reader.string());
            continue;
          }
          case 6: {
            if (wireType !== 2)
              break;
            if (!(message.generalOrderNumber && message.generalOrderNumber.length))
              message.generalOrderNumber = [];
            message.generalOrderNumber.push(reader.string());
            continue;
          }
          case 7: {
            if (wireType !== 0)
              break;
            message.displayBeforeActive = reader.uint64();
            continue;
          }
          case 8: {
            if (wireType !== 2)
              break;
            message.humanReadableActivePeriod = $root.transit_realtime.TranslatedString.decode(reader, reader.uint32(), $undefined, _depth + 1, message.humanReadableActivePeriod);
            continue;
          }
          case 9: {
            if (wireType !== 0)
              break;
            message.directionality = reader.uint64();
            continue;
          }
          case 10: {
            if (wireType !== 2)
              break;
            if (!(message.affectedStations && message.affectedStations.length))
              message.affectedStations = [];
            message.affectedStations.push($root.transit_realtime.EntitySelector.decode(reader, reader.uint32(), $undefined, _depth + 1));
            continue;
          }
          case 11: {
            if (wireType !== 2)
              break;
            message.screensSummary = $root.transit_realtime.TranslatedString.decode(reader, reader.uint32(), $undefined, _depth + 1, message.screensSummary);
            continue;
          }
          case 12: {
            if (wireType !== 0)
              break;
            message.noAffectedStations = reader.bool();
            continue;
          }
          case 13: {
            if (wireType !== 2)
              break;
            message.cloneId = reader.string();
            continue;
          }
        }
        reader.skipType(wireType, _depth, tag);
        if (!reader.discardUnknown) {
          $util.makeProp(message, "$unknowns", false);
          (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
        }
      }
      if (length !== $undefined) {
        if (reader.pos !== end)
          throw $RangeError("index out of range");
        reader.len = length;
      }
      if (_end !== $undefined)
        throw $Error("missing end group");
      if (!$Object.hasOwnProperty.call(message, "createdAt"))
        throw $util.ProtocolError("missing required 'createdAt'", { instance: message });
      if (!$Object.hasOwnProperty.call(message, "updatedAt"))
        throw $util.ProtocolError("missing required 'updatedAt'", { instance: message });
      if (!$Object.hasOwnProperty.call(message, "alertType"))
        throw $util.ProtocolError("missing required 'alertType'", { instance: message });
      return message;
    };
    MercuryAlert.decodeDelimited = function(reader) {
      if (!(reader instanceof $Reader))
        reader = new $Reader(reader);
      return this.decode(reader, reader.uint32());
    };
    MercuryAlert.verify = function(message, _depth) {
      if (typeof message !== "object" || message === null)
        return "object expected";
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        return "max depth exceeded";
      if (!$util.isInteger(message.createdAt) && !(message.createdAt && $util.isInteger(message.createdAt.low) && $util.isInteger(message.createdAt.high)))
        return "createdAt: integer|Long expected";
      if (!$util.isInteger(message.updatedAt) && !(message.updatedAt && $util.isInteger(message.updatedAt.low) && $util.isInteger(message.updatedAt.high)))
        return "updatedAt: integer|Long expected";
      if (!$util.isString(message.alertType))
        return "alertType: string expected";
      if (message.stationAlternative != null && $Object.hasOwnProperty.call(message, "stationAlternative")) {
        if (!$Array.isArray(message.stationAlternative))
          return "stationAlternative: array expected";
        for (let i = 0; i < message.stationAlternative.length; ++i) {
          let error = $root.transit_realtime.MercuryStationAlternative.verify(message.stationAlternative[i], _depth + 1);
          if (error)
            return "stationAlternative." + error;
        }
      }
      if (message.servicePlanNumber != null && $Object.hasOwnProperty.call(message, "servicePlanNumber")) {
        if (!$Array.isArray(message.servicePlanNumber))
          return "servicePlanNumber: array expected";
        for (let i = 0; i < message.servicePlanNumber.length; ++i)
          if (!$util.isString(message.servicePlanNumber[i]))
            return "servicePlanNumber: string[] expected";
      }
      if (message.generalOrderNumber != null && $Object.hasOwnProperty.call(message, "generalOrderNumber")) {
        if (!$Array.isArray(message.generalOrderNumber))
          return "generalOrderNumber: array expected";
        for (let i = 0; i < message.generalOrderNumber.length; ++i)
          if (!$util.isString(message.generalOrderNumber[i]))
            return "generalOrderNumber: string[] expected";
      }
      if (message.displayBeforeActive != null && $Object.hasOwnProperty.call(message, "displayBeforeActive")) {
        if (!$util.isInteger(message.displayBeforeActive) && !(message.displayBeforeActive && $util.isInteger(message.displayBeforeActive.low) && $util.isInteger(message.displayBeforeActive.high)))
          return "displayBeforeActive: integer|Long expected";
      }
      if (message.humanReadableActivePeriod != null && $Object.hasOwnProperty.call(message, "humanReadableActivePeriod")) {
        let error = $root.transit_realtime.TranslatedString.verify(message.humanReadableActivePeriod, _depth + 1);
        if (error)
          return "humanReadableActivePeriod." + error;
      }
      if (message.directionality != null && $Object.hasOwnProperty.call(message, "directionality")) {
        if (!$util.isInteger(message.directionality) && !(message.directionality && $util.isInteger(message.directionality.low) && $util.isInteger(message.directionality.high)))
          return "directionality: integer|Long expected";
      }
      if (message.affectedStations != null && $Object.hasOwnProperty.call(message, "affectedStations")) {
        if (!$Array.isArray(message.affectedStations))
          return "affectedStations: array expected";
        for (let i = 0; i < message.affectedStations.length; ++i) {
          let error = $root.transit_realtime.EntitySelector.verify(message.affectedStations[i], _depth + 1);
          if (error)
            return "affectedStations." + error;
        }
      }
      if (message.screensSummary != null && $Object.hasOwnProperty.call(message, "screensSummary")) {
        let error = $root.transit_realtime.TranslatedString.verify(message.screensSummary, _depth + 1);
        if (error)
          return "screensSummary." + error;
      }
      if (message.noAffectedStations != null && $Object.hasOwnProperty.call(message, "noAffectedStations")) {
        if (typeof message.noAffectedStations !== "boolean")
          return "noAffectedStations: boolean expected";
      }
      if (message.cloneId != null && $Object.hasOwnProperty.call(message, "cloneId")) {
        if (!$util.isString(message.cloneId))
          return "cloneId: string expected";
      }
      return null;
    };
    MercuryAlert.fromObject = function(object, _depth) {
      if (object instanceof $root.transit_realtime.MercuryAlert)
        return object;
      if (!$util.isObject(object))
        throw $TypeError(".transit_realtime.MercuryAlert: object expected");
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let message = new $root.transit_realtime.MercuryAlert();
      if (object.createdAt != null) {
        if ($util.Long)
          message.createdAt = $util.Long.fromValue(object.createdAt, true);
        else if (typeof object.createdAt === "string")
          message.createdAt = $parseInt(object.createdAt, 10);
        else if (typeof object.createdAt === "number")
          message.createdAt = object.createdAt;
        else if (typeof object.createdAt === "object")
          message.createdAt = new $util.LongBits(object.createdAt.low >>> 0, object.createdAt.high >>> 0).toNumber(true);
      }
      if (object.updatedAt != null) {
        if ($util.Long)
          message.updatedAt = $util.Long.fromValue(object.updatedAt, true);
        else if (typeof object.updatedAt === "string")
          message.updatedAt = $parseInt(object.updatedAt, 10);
        else if (typeof object.updatedAt === "number")
          message.updatedAt = object.updatedAt;
        else if (typeof object.updatedAt === "object")
          message.updatedAt = new $util.LongBits(object.updatedAt.low >>> 0, object.updatedAt.high >>> 0).toNumber(true);
      }
      if (object.alertType != null)
        message.alertType = $String(object.alertType);
      if (object.stationAlternative) {
        if (!$Array.isArray(object.stationAlternative))
          throw $TypeError(".transit_realtime.MercuryAlert.stationAlternative: array expected");
        message.stationAlternative = $Array(object.stationAlternative.length);
        for (let i = 0; i < object.stationAlternative.length; ++i) {
          if (!$util.isObject(object.stationAlternative[i]))
            throw $TypeError(".transit_realtime.MercuryAlert.stationAlternative: object expected");
          message.stationAlternative[i] = $root.transit_realtime.MercuryStationAlternative.fromObject(object.stationAlternative[i], _depth + 1);
        }
      }
      if (object.servicePlanNumber) {
        if (!$Array.isArray(object.servicePlanNumber))
          throw $TypeError(".transit_realtime.MercuryAlert.servicePlanNumber: array expected");
        message.servicePlanNumber = $Array(object.servicePlanNumber.length);
        for (let i = 0; i < object.servicePlanNumber.length; ++i)
          message.servicePlanNumber[i] = $String(object.servicePlanNumber[i]);
      }
      if (object.generalOrderNumber) {
        if (!$Array.isArray(object.generalOrderNumber))
          throw $TypeError(".transit_realtime.MercuryAlert.generalOrderNumber: array expected");
        message.generalOrderNumber = $Array(object.generalOrderNumber.length);
        for (let i = 0; i < object.generalOrderNumber.length; ++i)
          message.generalOrderNumber[i] = $String(object.generalOrderNumber[i]);
      }
      if (object.displayBeforeActive != null) {
        if ($util.Long)
          message.displayBeforeActive = $util.Long.fromValue(object.displayBeforeActive, true);
        else if (typeof object.displayBeforeActive === "string")
          message.displayBeforeActive = $parseInt(object.displayBeforeActive, 10);
        else if (typeof object.displayBeforeActive === "number")
          message.displayBeforeActive = object.displayBeforeActive;
        else if (typeof object.displayBeforeActive === "object")
          message.displayBeforeActive = new $util.LongBits(object.displayBeforeActive.low >>> 0, object.displayBeforeActive.high >>> 0).toNumber(true);
      }
      if (object.humanReadableActivePeriod != null) {
        if (!$util.isObject(object.humanReadableActivePeriod))
          throw $TypeError(".transit_realtime.MercuryAlert.humanReadableActivePeriod: object expected");
        message.humanReadableActivePeriod = $root.transit_realtime.TranslatedString.fromObject(object.humanReadableActivePeriod, _depth + 1);
      }
      if (object.directionality != null) {
        if ($util.Long)
          message.directionality = $util.Long.fromValue(object.directionality, true);
        else if (typeof object.directionality === "string")
          message.directionality = $parseInt(object.directionality, 10);
        else if (typeof object.directionality === "number")
          message.directionality = object.directionality;
        else if (typeof object.directionality === "object")
          message.directionality = new $util.LongBits(object.directionality.low >>> 0, object.directionality.high >>> 0).toNumber(true);
      }
      if (object.affectedStations) {
        if (!$Array.isArray(object.affectedStations))
          throw $TypeError(".transit_realtime.MercuryAlert.affectedStations: array expected");
        message.affectedStations = $Array(object.affectedStations.length);
        for (let i = 0; i < object.affectedStations.length; ++i) {
          if (!$util.isObject(object.affectedStations[i]))
            throw $TypeError(".transit_realtime.MercuryAlert.affectedStations: object expected");
          message.affectedStations[i] = $root.transit_realtime.EntitySelector.fromObject(object.affectedStations[i], _depth + 1);
        }
      }
      if (object.screensSummary != null) {
        if (!$util.isObject(object.screensSummary))
          throw $TypeError(".transit_realtime.MercuryAlert.screensSummary: object expected");
        message.screensSummary = $root.transit_realtime.TranslatedString.fromObject(object.screensSummary, _depth + 1);
      }
      if (object.noAffectedStations != null)
        message.noAffectedStations = $Boolean(object.noAffectedStations);
      if (object.cloneId != null)
        message.cloneId = $String(object.cloneId);
      return message;
    };
    MercuryAlert.toObject = function(message, options, _depth) {
      if (!options)
        options = {};
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let object = {};
      if (options.arrays || options.defaults) {
        object.stationAlternative = [];
        object.servicePlanNumber = [];
        object.generalOrderNumber = [];
        object.affectedStations = [];
      }
      if (options.defaults) {
        if ($util.Long) {
          let long = new $util.Long(0, 0, true);
          object.createdAt = options.longs === $String ? long.toString() : options.longs === $Number ? long.toNumber() : typeof $BigInt !== "undefined" && options.longs === $BigInt ? long.toBigInt() : long;
        } else
          object.createdAt = options.longs === $String ? "0" : typeof $BigInt !== "undefined" && options.longs === $BigInt ? $BigInt("0") : 0;
        if ($util.Long) {
          let long = new $util.Long(0, 0, true);
          object.updatedAt = options.longs === $String ? long.toString() : options.longs === $Number ? long.toNumber() : typeof $BigInt !== "undefined" && options.longs === $BigInt ? long.toBigInt() : long;
        } else
          object.updatedAt = options.longs === $String ? "0" : typeof $BigInt !== "undefined" && options.longs === $BigInt ? $BigInt("0") : 0;
        object.alertType = "";
        if ($util.Long) {
          let long = new $util.Long(0, 0, true);
          object.displayBeforeActive = options.longs === $String ? long.toString() : options.longs === $Number ? long.toNumber() : typeof $BigInt !== "undefined" && options.longs === $BigInt ? long.toBigInt() : long;
        } else
          object.displayBeforeActive = options.longs === $String ? "0" : typeof $BigInt !== "undefined" && options.longs === $BigInt ? $BigInt("0") : 0;
        object.humanReadableActivePeriod = null;
        if ($util.Long) {
          let long = new $util.Long(0, 0, true);
          object.directionality = options.longs === $String ? long.toString() : options.longs === $Number ? long.toNumber() : typeof $BigInt !== "undefined" && options.longs === $BigInt ? long.toBigInt() : long;
        } else
          object.directionality = options.longs === $String ? "0" : typeof $BigInt !== "undefined" && options.longs === $BigInt ? $BigInt("0") : 0;
        object.screensSummary = null;
        object.noAffectedStations = false;
        object.cloneId = "";
      }
      if (message.createdAt != null && $Object.hasOwnProperty.call(message, "createdAt"))
        if (typeof $BigInt !== "undefined" && options.longs === $BigInt)
          object.createdAt = typeof message.createdAt === "number" ? $BigInt(message.createdAt) : $util.Long.fromBits(message.createdAt.low >>> 0, message.createdAt.high >>> 0, true).toBigInt();
        else if (typeof message.createdAt === "number")
          object.createdAt = options.longs === $String ? $String(message.createdAt) : message.createdAt;
        else
          object.createdAt = options.longs === $String ? $util.Long.prototype.toString.call(message.createdAt) : options.longs === $Number ? new $util.LongBits(message.createdAt.low >>> 0, message.createdAt.high >>> 0).toNumber(true) : message.createdAt;
      if (message.updatedAt != null && $Object.hasOwnProperty.call(message, "updatedAt"))
        if (typeof $BigInt !== "undefined" && options.longs === $BigInt)
          object.updatedAt = typeof message.updatedAt === "number" ? $BigInt(message.updatedAt) : $util.Long.fromBits(message.updatedAt.low >>> 0, message.updatedAt.high >>> 0, true).toBigInt();
        else if (typeof message.updatedAt === "number")
          object.updatedAt = options.longs === $String ? $String(message.updatedAt) : message.updatedAt;
        else
          object.updatedAt = options.longs === $String ? $util.Long.prototype.toString.call(message.updatedAt) : options.longs === $Number ? new $util.LongBits(message.updatedAt.low >>> 0, message.updatedAt.high >>> 0).toNumber(true) : message.updatedAt;
      if (message.alertType != null && $Object.hasOwnProperty.call(message, "alertType"))
        object.alertType = message.alertType;
      if (message.stationAlternative && message.stationAlternative.length) {
        object.stationAlternative = $Array(message.stationAlternative.length);
        for (let j = 0; j < message.stationAlternative.length; ++j)
          object.stationAlternative[j] = $root.transit_realtime.MercuryStationAlternative.toObject(message.stationAlternative[j], options, _depth + 1);
      }
      if (message.servicePlanNumber && message.servicePlanNumber.length) {
        object.servicePlanNumber = $Array(message.servicePlanNumber.length);
        for (let j = 0; j < message.servicePlanNumber.length; ++j)
          object.servicePlanNumber[j] = message.servicePlanNumber[j];
      }
      if (message.generalOrderNumber && message.generalOrderNumber.length) {
        object.generalOrderNumber = $Array(message.generalOrderNumber.length);
        for (let j = 0; j < message.generalOrderNumber.length; ++j)
          object.generalOrderNumber[j] = message.generalOrderNumber[j];
      }
      if (message.displayBeforeActive != null && $Object.hasOwnProperty.call(message, "displayBeforeActive"))
        if (typeof $BigInt !== "undefined" && options.longs === $BigInt)
          object.displayBeforeActive = typeof message.displayBeforeActive === "number" ? $BigInt(message.displayBeforeActive) : $util.Long.fromBits(message.displayBeforeActive.low >>> 0, message.displayBeforeActive.high >>> 0, true).toBigInt();
        else if (typeof message.displayBeforeActive === "number")
          object.displayBeforeActive = options.longs === $String ? $String(message.displayBeforeActive) : message.displayBeforeActive;
        else
          object.displayBeforeActive = options.longs === $String ? $util.Long.prototype.toString.call(message.displayBeforeActive) : options.longs === $Number ? new $util.LongBits(message.displayBeforeActive.low >>> 0, message.displayBeforeActive.high >>> 0).toNumber(true) : message.displayBeforeActive;
      if (message.humanReadableActivePeriod != null && $Object.hasOwnProperty.call(message, "humanReadableActivePeriod"))
        object.humanReadableActivePeriod = $root.transit_realtime.TranslatedString.toObject(message.humanReadableActivePeriod, options, _depth + 1);
      if (message.directionality != null && $Object.hasOwnProperty.call(message, "directionality"))
        if (typeof $BigInt !== "undefined" && options.longs === $BigInt)
          object.directionality = typeof message.directionality === "number" ? $BigInt(message.directionality) : $util.Long.fromBits(message.directionality.low >>> 0, message.directionality.high >>> 0, true).toBigInt();
        else if (typeof message.directionality === "number")
          object.directionality = options.longs === $String ? $String(message.directionality) : message.directionality;
        else
          object.directionality = options.longs === $String ? $util.Long.prototype.toString.call(message.directionality) : options.longs === $Number ? new $util.LongBits(message.directionality.low >>> 0, message.directionality.high >>> 0).toNumber(true) : message.directionality;
      if (message.affectedStations && message.affectedStations.length) {
        object.affectedStations = $Array(message.affectedStations.length);
        for (let j = 0; j < message.affectedStations.length; ++j)
          object.affectedStations[j] = $root.transit_realtime.EntitySelector.toObject(message.affectedStations[j], options, _depth + 1);
      }
      if (message.screensSummary != null && $Object.hasOwnProperty.call(message, "screensSummary"))
        object.screensSummary = $root.transit_realtime.TranslatedString.toObject(message.screensSummary, options, _depth + 1);
      if (message.noAffectedStations != null && $Object.hasOwnProperty.call(message, "noAffectedStations"))
        object.noAffectedStations = message.noAffectedStations;
      if (message.cloneId != null && $Object.hasOwnProperty.call(message, "cloneId"))
        object.cloneId = message.cloneId;
      return object;
    };
    MercuryAlert.prototype.toJSON = function() {
      return MercuryAlert.toObject(this, import_minimal.default.util.toJSONOptions);
    };
    MercuryAlert.getTypeUrl = function(prefix) {
      if (prefix === $undefined)
        prefix = "type.googleapis.com";
      return prefix + "/transit_realtime.MercuryAlert";
    };
    return MercuryAlert;
  })();
  transit_realtime2.MercuryEntitySelector = (function() {
    const MercuryEntitySelector = /* @__PURE__ */ __name(function(properties) {
      if (properties) {
        for (let keys = $Object.keys(properties), i = 0; i < keys.length; ++i)
          if (properties[keys[i]] != null && keys[i] !== "__proto__")
            this[keys[i]] = properties[keys[i]];
      }
    }, "MercuryEntitySelector");
    MercuryEntitySelector.prototype.sortOrder = "";
    MercuryEntitySelector.create = function(properties) {
      return new MercuryEntitySelector(properties);
    };
    MercuryEntitySelector.encode = function(message, writer, _depth) {
      if (!writer)
        writer = $Writer.create();
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      writer.uint32(
        /* id 1, wireType 2 =*/
        10
      ).string(message.sortOrder);
      if (message.$unknowns != null && $Object.hasOwnProperty.call(message, "$unknowns"))
        for (let i = 0; i < message.$unknowns.length; ++i)
          writer.raw(message.$unknowns[i]);
      return writer;
    };
    MercuryEntitySelector.encodeDelimited = function(message, writer) {
      return this.encode(message, (writer || $Writer.create()).fork()).ldelim();
    };
    MercuryEntitySelector.decode = function(reader, length, _end, _depth, _target) {
      if (!(reader instanceof $Reader))
        reader = $Reader.create(reader);
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $Reader.recursionLimit)
        throw $Error("max depth exceeded");
      let end, message;
      if (length === $undefined)
        end = reader.len;
      else {
        end = reader.pos + length;
        if (end > reader.len)
          throw $RangeError("index out of range");
        length = reader.len;
        reader.len = end;
      }
      message = _target || new $root.transit_realtime.MercuryEntitySelector();
      while (reader.pos < end) {
        let start = reader.pos;
        let tag = reader.tag();
        if (tag === _end) {
          _end = $undefined;
          break;
        }
        let wireType = tag & 7;
        switch (tag >>>= 3) {
          case 1: {
            if (wireType !== 2)
              break;
            message.sortOrder = reader.string();
            continue;
          }
        }
        reader.skipType(wireType, _depth, tag);
        if (!reader.discardUnknown) {
          $util.makeProp(message, "$unknowns", false);
          (message.$unknowns || (message.$unknowns = [])).push(reader.raw(start, reader.pos));
        }
      }
      if (length !== $undefined) {
        if (reader.pos !== end)
          throw $RangeError("index out of range");
        reader.len = length;
      }
      if (_end !== $undefined)
        throw $Error("missing end group");
      if (!$Object.hasOwnProperty.call(message, "sortOrder"))
        throw $util.ProtocolError("missing required 'sortOrder'", { instance: message });
      return message;
    };
    MercuryEntitySelector.decodeDelimited = function(reader) {
      if (!(reader instanceof $Reader))
        reader = new $Reader(reader);
      return this.decode(reader, reader.uint32());
    };
    MercuryEntitySelector.verify = function(message, _depth) {
      if (typeof message !== "object" || message === null)
        return "object expected";
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        return "max depth exceeded";
      if (!$util.isString(message.sortOrder))
        return "sortOrder: string expected";
      return null;
    };
    MercuryEntitySelector.fromObject = function(object, _depth) {
      if (object instanceof $root.transit_realtime.MercuryEntitySelector)
        return object;
      if (!$util.isObject(object))
        throw $TypeError(".transit_realtime.MercuryEntitySelector: object expected");
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let message = new $root.transit_realtime.MercuryEntitySelector();
      if (object.sortOrder != null)
        message.sortOrder = $String(object.sortOrder);
      return message;
    };
    MercuryEntitySelector.toObject = function(message, options, _depth) {
      if (!options)
        options = {};
      if (_depth === $undefined)
        _depth = 0;
      if (_depth > $util.recursionLimit)
        throw $Error("max depth exceeded");
      let object = {};
      if (options.defaults)
        object.sortOrder = "";
      if (message.sortOrder != null && $Object.hasOwnProperty.call(message, "sortOrder"))
        object.sortOrder = message.sortOrder;
      return object;
    };
    MercuryEntitySelector.prototype.toJSON = function() {
      return MercuryEntitySelector.toObject(this, import_minimal.default.util.toJSONOptions);
    };
    MercuryEntitySelector.getTypeUrl = function(prefix) {
      if (prefix === $undefined)
        prefix = "type.googleapis.com";
      return prefix + "/transit_realtime.MercuryEntitySelector";
    };
    MercuryEntitySelector.Priority = (function() {
      const valuesById = $Object.create(null), values = $Object.create(valuesById);
      values[valuesById[1] = "PRIORITY_NO_SCHEDULED_SERVICE"] = 1;
      values[valuesById[2] = "PRIORITY_INFORMATION_OUTAGE"] = 2;
      values[valuesById[3] = "PRIORITY_STATION_NOTICE"] = 3;
      values[valuesById[4] = "PRIORITY_SPECIAL_NOTICE"] = 4;
      values[valuesById[5] = "PRIORITY_WEEKDAY_SCHEDULE"] = 5;
      values[valuesById[6] = "PRIORITY_WEEKEND_SCHEDULE"] = 6;
      values[valuesById[7] = "PRIORITY_SATURDAY_SCHEDULE"] = 7;
      values[valuesById[8] = "PRIORITY_SUNDAY_SCHEDULE"] = 8;
      values[valuesById[9] = "PRIORITY_EXTRA_SERVICE"] = 9;
      values[valuesById[10] = "PRIORITY_BOARDING_CHANGE"] = 10;
      values[valuesById[11] = "PRIORITY_SPECIAL_SCHEDULE"] = 11;
      values[valuesById[12] = "PRIORITY_EXPECT_DELAYS"] = 12;
      values[valuesById[13] = "PRIORITY_REDUCED_SERVICE"] = 13;
      values[valuesById[14] = "PRIORITY_PLANNED_EXPRESS_TO_LOCAL"] = 14;
      values[valuesById[15] = "PRIORITY_PLANNED_EXTRA_TRANSFER"] = 15;
      values[valuesById[16] = "PRIORITY_PLANNED_STOPS_SKIPPED"] = 16;
      values[valuesById[17] = "PRIORITY_PLANNED_DETOUR"] = 17;
      values[valuesById[18] = "PRIORITY_PLANNED_REROUTE"] = 18;
      values[valuesById[19] = "PRIORITY_PLANNED_SUBSTITUTE_BUSES"] = 19;
      values[valuesById[20] = "PRIORITY_PLANNED_PART_SUSPENDED"] = 20;
      values[valuesById[21] = "PRIORITY_PLANNED_SUSPENDED"] = 21;
      values[valuesById[22] = "PRIORITY_SERVICE_CHANGE"] = 22;
      values[valuesById[23] = "PRIORITY_PLANNED_WORK"] = 23;
      values[valuesById[24] = "PRIORITY_SOME_DELAYS"] = 24;
      values[valuesById[25] = "PRIORITY_EXPRESS_TO_LOCAL"] = 25;
      values[valuesById[26] = "PRIORITY_DELAYS"] = 26;
      values[valuesById[27] = "PRIORITY_CANCELLATIONS"] = 27;
      values[valuesById[28] = "PRIORITY_DELAYS_AND_CANCELLATIONS"] = 28;
      values[valuesById[29] = "PRIORITY_STOPS_SKIPPED"] = 29;
      values[valuesById[30] = "PRIORITY_SEVERE_DELAYS"] = 30;
      values[valuesById[31] = "PRIORITY_DETOUR"] = 31;
      values[valuesById[32] = "PRIORITY_REROUTE"] = 32;
      values[valuesById[33] = "PRIORITY_SUBSTITUTE_BUSES"] = 33;
      values[valuesById[34] = "PRIORITY_PART_SUSPENDED"] = 34;
      values[valuesById[35] = "PRIORITY_SUSPENDED"] = 35;
      return values;
    })();
    return MercuryEntitySelector;
  })();
  return transit_realtime2;
})();

// src/gtfs.ts
var MTA_FEEDS = [
  "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct/gtfs",
  "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct/gtfs-ace",
  "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct/gtfs-bdfm",
  "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct/gtfs-g",
  "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct/gtfs-jz",
  "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct/gtfs-l",
  "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct/gtfs-nqrw",
  "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct/gtfs-si"
];
async function fetchFeeds(kv) {
  const updated_at = Math.floor(Date.now() / 1e3);
  const stopArrivals = /* @__PURE__ */ new Map();
  const results = await Promise.allSettled(
    MTA_FEEDS.map(async (url) => {
      const controller = new AbortController();
      const id = setTimeout(() => controller.abort(), 2e4);
      try {
        const response = await fetch(url, { signal: controller.signal });
        if (!response.ok) throw new Error(`Status ${response.status}`);
        const buffer = await response.arrayBuffer();
        const feed = transit_realtime.FeedMessage.decode(new Uint8Array(buffer));
        for (const entity of feed.entity) {
          if (entity.tripUpdate && entity.tripUpdate.stopTimeUpdate) {
            const trip = entity.tripUpdate.trip;
            const route_id = trip.routeId || "UNKNOWN";
            let nyctDirection = "UNKNOWN";
            const nyctDesc = trip[".transit_realtime.nyctTripDescriptor"];
            if (nyctDesc && nyctDesc.direction) {
              const dirEnum = nyctDesc.direction;
              nyctDirection = dirEnum === 1 ? "NORTH" : dirEnum === 2 ? "EAST" : dirEnum === 3 ? "SOUTH" : dirEnum === 4 ? "WEST" : "UNKNOWN";
            }
            for (const stopTime of entity.tripUpdate.stopTimeUpdate) {
              if (!stopTime.arrival || !stopTime.arrival.time) continue;
              const rawStopId = stopTime.stopId || "";
              const baseStopId = rawStopId.substring(0, 3);
              if (!baseStopId) continue;
              const suffix = rawStopId.length > 3 ? rawStopId.substring(3) : "";
              let direction = nyctDirection;
              if (direction === "UNKNOWN") {
                if (suffix === "N") direction = "NORTH";
                else if (suffix === "S") direction = "SOUTH";
              }
              const timeLow = typeof stopTime.arrival.time === "object" ? stopTime.arrival.time.low : stopTime.arrival.time;
              if (timeLow < updated_at - 60) continue;
              const prediction = {
                route_id,
                direction,
                headsign: "",
                predicted_arrival_epoch: timeLow,
                is_realtime: true
              };
              if (!stopArrivals.has(baseStopId)) {
                stopArrivals.set(baseStopId, []);
              }
              stopArrivals.get(baseStopId).push(prediction);
            }
          }
        }
      } finally {
        clearTimeout(id);
      }
    })
  );
  const groupedStops = /* @__PURE__ */ new Map();
  for (const [stopId, arrivals] of stopArrivals.entries()) {
    const firstChar = stopId.charAt(0).toUpperCase();
    if (!groupedStops.has(firstChar)) {
      groupedStops.set(firstChar, {});
    }
    arrivals.sort((a, b) => a.predicted_arrival_epoch - b.predicted_arrival_epoch);
    groupedStops.get(firstChar)[stopId] = {
      stop_id: stopId,
      updated_at,
      arrivals
    };
  }
  const writePromises = [];
  for (const [firstChar, stopsMap] of groupedStops.entries()) {
    const key = `stops-${firstChar}`;
    writePromises.push(kv.put(key, JSON.stringify(stopsMap), { expirationTtl: 90 }));
  }
  await Promise.allSettled(writePromises);
}
__name(fetchFeeds, "fetchFeeds");
async function getArrivalsForStop(kv, stopId) {
  const firstChar = stopId.charAt(0).toUpperCase();
  const key = `stops-${firstChar}`;
  const data = await kv.get(key, "json");
  if (!data) return null;
  const stopsMap = data;
  return stopsMap[stopId] || null;
}
__name(getArrivalsForStop, "getArrivalsForStop");

// src/index.ts
var ALLOWED_ORIGINS = /* @__PURE__ */ new Set([
  "https://derivee-api.walsh-8de.workers.dev",
  "https://9c770b10.derivee-web.pages.dev",
  "https://derivee.app",
  "http://localhost:5173",
  "http://127.0.0.1:5173"
]);
function isAllowedOrigin(origin) {
  if (!origin) return false;
  if (ALLOWED_ORIGINS.has(origin)) return true;
  if (/^https:\/\/[a-z0-9-]+\.derivee-web\.pages\.dev$/.test(origin)) return true;
  if (/^https:\/\/[a-z0-9-]+\.walsh-8de\.workers\.dev$/.test(origin)) return true;
  return false;
}
__name(isAllowedOrigin, "isAllowedOrigin");
function getPreflightHeaders(origin) {
  const headers = new Headers({ Vary: "Origin" });
  if (isAllowedOrigin(origin)) {
    headers.set("Access-Control-Allow-Origin", origin);
    headers.set("Access-Control-Allow-Methods", "GET, OPTIONS");
    headers.set("Access-Control-Allow-Headers", "Content-Type, Range");
    headers.set("Access-Control-Allow-Credentials", "true");
    headers.set("Access-Control-Max-Age", "86400");
  }
  return headers;
}
__name(getPreflightHeaders, "getPreflightHeaders");
function getCorsHeaders(origin) {
  const headers = { Vary: "Origin" };
  if (isAllowedOrigin(origin)) {
    headers["Access-Control-Allow-Origin"] = origin;
    headers["Access-Control-Allow-Credentials"] = "true";
    headers["Access-Control-Expose-Headers"] = "Content-Length, Content-Disposition, ETag";
  }
  return headers;
}
__name(getCorsHeaders, "getCorsHeaders");
function jsonResponse(body, status, origin, extraHeaders = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      ...getCorsHeaders(origin),
      ...extraHeaders
    }
  });
}
__name(jsonResponse, "jsonResponse");
var src_default = {
  async scheduled(event, env, ctx) {
    ctx.waitUntil(fetchFeeds(env.KV_REALTIME));
  },
  async fetch(request, env) {
    const url = new URL(request.url);
    const origin = request.headers.get("Origin");
    if (request.method === "OPTIONS") {
      if (url.pathname.startsWith("/api/")) {
        return new Response(null, {
          status: 204,
          headers: getPreflightHeaders(origin)
        });
      }
      return jsonResponse({ error: "not_found" }, 404, origin);
    }
    if (url.pathname === "/api/health" && request.method === "GET") {
      return jsonResponse({ ok: true }, 200, origin);
    }
    if (url.pathname === "/api/realtime/arrivals" && request.method === "GET") {
      const stop = url.searchParams.get("stop");
      if (!stop) {
        return jsonResponse({ error: "missing_stop" }, 400, origin);
      }
      const data = await getArrivalsForStop(env.KV_REALTIME, stop);
      if (!data) {
        return jsonResponse({ error: "not_found" }, 404, origin);
      }
      const now = Math.floor(Date.now() / 1e3);
      if (now - data.updated_at > 90) {
        return jsonResponse({ error: "stale", stale: true }, 503, origin);
      }
      return jsonResponse(data, 200, origin);
    }
    if (url.pathname === "/api/me" && request.method === "GET") {
      const userEmail = request.headers.get("cf-access-authenticated-user-email") || request.headers.get("Cf-Access-Authenticated-User-Email");
      if (!userEmail) {
        return jsonResponse({ error: "unauthorized" }, 401, origin);
      }
      return jsonResponse({ email: userEmail }, 200, origin);
    }
    if (url.pathname === "/api/pack" && request.method === "GET") {
      const userEmail = request.headers.get("cf-access-authenticated-user-email") || request.headers.get("Cf-Access-Authenticated-User-Email");
      if (!userEmail) {
        return jsonResponse({ error: "unauthorized" }, 401, origin);
      }
      if (env.RATE_LIMITER) {
        const { success } = await env.RATE_LIMITER.limit({ key: userEmail });
        if (!success) {
          return jsonResponse(
            { error: "rate_limited" },
            429,
            origin,
            { "Retry-After": "60" }
          );
        }
      }
      const city = url.searchParams.get("city") || "nyc";
      const key = `city-${city}.pack.zst`;
      const obj = await env.PACK.get(key);
      if (!obj) {
        return jsonResponse({ error: "not_found" }, 404, origin);
      }
      const headers = new Headers({
        "Content-Type": "application/zstd",
        "Content-Length": obj.size.toString(),
        "Content-Disposition": `attachment; filename="${key}"`,
        "Cache-Control": "no-store",
        ...getCorsHeaders(origin)
      });
      if (obj.httpEtag) {
        headers.set("ETag", obj.httpEtag);
      }
      return new Response(obj.body, {
        status: 200,
        headers
      });
    }
    if (url.pathname === "/api/cities" && request.method === "GET") {
      const userEmail = request.headers.get("cf-access-authenticated-user-email") || request.headers.get("Cf-Access-Authenticated-User-Email");
      if (!userEmail) {
        return jsonResponse({ error: "unauthorized" }, 401, origin);
      }
      if (env.RATE_LIMITER) {
        const { success } = await env.RATE_LIMITER.limit({ key: userEmail });
        if (!success) {
          return jsonResponse(
            { error: "rate_limited" },
            429,
            origin,
            { "Retry-After": "60" }
          );
        }
      }
      const obj = await env.PACK.get("cities.json");
      if (!obj) {
        return jsonResponse({ error: "not_found" }, 404, origin);
      }
      const headers = new Headers({
        "Content-Type": "application/json",
        "Content-Length": obj.size.toString(),
        "Content-Disposition": 'inline; filename="cities.json"',
        "Cache-Control": "no-store",
        ...getCorsHeaders(origin)
      });
      if (obj.httpEtag) {
        headers.set("ETag", obj.httpEtag);
      }
      return new Response(obj.body, {
        status: 200,
        headers
      });
    }
    if (url.pathname === "/api/basemap" && request.method === "GET") {
      const city = url.searchParams.get("city") || "nyc";
      const key = `basemap-${city}.pmtiles`;
      const obj = await env.PACK.get(key, {
        range: request.headers,
        onlyIf: request.headers
      });
      if (!obj) {
        return jsonResponse({ error: "not_found" }, 404, origin);
      }
      const headers = new Headers({
        "Content-Type": "application/vnd.pmtiles",
        "Cache-Control": "public, max-age=86400",
        ...getCorsHeaders(origin)
      });
      if (obj.httpEtag) {
        headers.set("ETag", obj.httpEtag);
      }
      if (!("body" in obj)) {
        return new Response(null, { status: 304, headers });
      }
      if ("range" in obj && obj.range) {
        const r = obj.range;
        headers.set("Content-Range", `bytes ${r.offset}-${r.offset + r.length - 1}/${obj.size}`);
        headers.set("Content-Length", r.length.toString());
        return new Response(obj.body, {
          status: 206,
          headers
        });
      }
      headers.set("Content-Length", obj.size.toString());
      headers.set("Content-Disposition", `attachment; filename="${city}-basemap.pmtiles"`);
      return new Response(obj.body, {
        status: 200,
        headers
      });
    }
    if (url.pathname.startsWith("/api/")) {
      return jsonResponse({ error: "not_found" }, 404, origin);
    }
    if (env.ASSETS) {
      return env.ASSETS.fetch(request);
    }
    return jsonResponse({ error: "not_found" }, 404, origin);
  }
};

// ../../../../../.npm/_npx/32026684e21afda6/node_modules/wrangler/templates/middleware/middleware-ensure-req-body-drained.ts
init_modules_watch_stub();
var drainBody = /* @__PURE__ */ __name(async (request, env, _ctx, middlewareCtx) => {
  try {
    return await middlewareCtx.next(request, env);
  } finally {
    try {
      if (request.body !== null && !request.bodyUsed) {
        const reader = request.body.getReader();
        while (!(await reader.read()).done) {
        }
      }
    } catch (e) {
      console.error("Failed to drain the unused request body.", e);
    }
  }
}, "drainBody");
var middleware_ensure_req_body_drained_default = drainBody;

// ../../../../../.npm/_npx/32026684e21afda6/node_modules/wrangler/templates/middleware/middleware-miniflare3-json-error.ts
init_modules_watch_stub();
function reduceError(e) {
  return {
    name: e?.name,
    message: e?.message ?? String(e),
    stack: e?.stack,
    cause: e?.cause === void 0 ? void 0 : reduceError(e.cause)
  };
}
__name(reduceError, "reduceError");
var jsonError = /* @__PURE__ */ __name(async (request, env, _ctx, middlewareCtx) => {
  try {
    return await middlewareCtx.next(request, env);
  } catch (e) {
    const error = reduceError(e);
    const body = JSON.stringify(error);
    const headers = {
      "Content-Type": "application/json",
      "MF-Experimental-Error-Stack": "true"
    };
    const encoded = encodeURIComponent(body);
    if (encoded.length <= 8192) {
      headers["MF-Experimental-Error-Stack-Payload"] = encoded;
    }
    return new Response(body, { status: 500, headers });
  }
}, "jsonError");
var middleware_miniflare3_json_error_default = jsonError;

// .wrangler/tmp/bundle-PN86BB/middleware-insertion-facade.js
var __INTERNAL_WRANGLER_MIDDLEWARE__ = [
  middleware_ensure_req_body_drained_default,
  middleware_miniflare3_json_error_default
];
var middleware_insertion_facade_default = src_default;

// ../../../../../.npm/_npx/32026684e21afda6/node_modules/wrangler/templates/middleware/common.ts
init_modules_watch_stub();
var __facade_middleware__ = [];
function __facade_register__(...args) {
  __facade_middleware__.push(...args.flat());
}
__name(__facade_register__, "__facade_register__");
function __facade_invokeChain__(request, env, ctx, dispatch, middlewareChain) {
  const [head, ...tail] = middlewareChain;
  const middlewareCtx = {
    dispatch,
    next(newRequest, newEnv) {
      return __facade_invokeChain__(newRequest, newEnv, ctx, dispatch, tail);
    }
  };
  return head(request, env, ctx, middlewareCtx);
}
__name(__facade_invokeChain__, "__facade_invokeChain__");
function __facade_invoke__(request, env, ctx, dispatch, finalMiddleware) {
  return __facade_invokeChain__(request, env, ctx, dispatch, [
    ...__facade_middleware__,
    finalMiddleware
  ]);
}
__name(__facade_invoke__, "__facade_invoke__");

// .wrangler/tmp/bundle-PN86BB/middleware-loader.entry.ts
var __Facade_ScheduledController__ = class ___Facade_ScheduledController__ {
  constructor(scheduledTime, cron, noRetry) {
    this.scheduledTime = scheduledTime;
    this.cron = cron;
    this.#noRetry = noRetry;
  }
  scheduledTime;
  cron;
  static {
    __name(this, "__Facade_ScheduledController__");
  }
  #noRetry;
  noRetry() {
    if (!(this instanceof ___Facade_ScheduledController__)) {
      throw new TypeError("Illegal invocation");
    }
    this.#noRetry();
  }
};
function wrapExportedHandler(worker) {
  if (__INTERNAL_WRANGLER_MIDDLEWARE__ === void 0 || __INTERNAL_WRANGLER_MIDDLEWARE__.length === 0) {
    return worker;
  }
  for (const middleware of __INTERNAL_WRANGLER_MIDDLEWARE__) {
    __facade_register__(middleware);
  }
  const fetchDispatcher = /* @__PURE__ */ __name(function(request, env, ctx) {
    if (worker.fetch === void 0) {
      throw new Error("Handler does not export a fetch() function.");
    }
    return worker.fetch(request, env, ctx);
  }, "fetchDispatcher");
  return {
    ...worker,
    fetch(request, env, ctx) {
      const dispatcher = /* @__PURE__ */ __name(function(type, init) {
        if (type === "scheduled" && worker.scheduled !== void 0) {
          const controller = new __Facade_ScheduledController__(
            Date.now(),
            init.cron ?? "",
            () => {
            }
          );
          return worker.scheduled(controller, env, ctx);
        }
      }, "dispatcher");
      return __facade_invoke__(request, env, ctx, dispatcher, fetchDispatcher);
    }
  };
}
__name(wrapExportedHandler, "wrapExportedHandler");
function wrapWorkerEntrypoint(klass) {
  if (__INTERNAL_WRANGLER_MIDDLEWARE__ === void 0 || __INTERNAL_WRANGLER_MIDDLEWARE__.length === 0) {
    return klass;
  }
  for (const middleware of __INTERNAL_WRANGLER_MIDDLEWARE__) {
    __facade_register__(middleware);
  }
  return class extends klass {
    #fetchDispatcher = /* @__PURE__ */ __name((request, env, ctx) => {
      this.env = env;
      this.ctx = ctx;
      if (super.fetch === void 0) {
        throw new Error("Entrypoint class does not define a fetch() function.");
      }
      return super.fetch(request);
    }, "#fetchDispatcher");
    #dispatcher = /* @__PURE__ */ __name((type, init) => {
      if (type === "scheduled" && super.scheduled !== void 0) {
        const controller = new __Facade_ScheduledController__(
          Date.now(),
          init.cron ?? "",
          () => {
          }
        );
        return super.scheduled(controller);
      }
    }, "#dispatcher");
    fetch(request) {
      return __facade_invoke__(
        request,
        this.env,
        this.ctx,
        this.#dispatcher,
        this.#fetchDispatcher
      );
    }
  };
}
__name(wrapWorkerEntrypoint, "wrapWorkerEntrypoint");
var WRAPPED_ENTRY;
if (typeof middleware_insertion_facade_default === "object") {
  WRAPPED_ENTRY = wrapExportedHandler(middleware_insertion_facade_default);
} else if (typeof middleware_insertion_facade_default === "function") {
  WRAPPED_ENTRY = wrapWorkerEntrypoint(middleware_insertion_facade_default);
}
var middleware_loader_entry_default = WRAPPED_ENTRY;
export {
  __INTERNAL_WRANGLER_MIDDLEWARE__,
  middleware_loader_entry_default as default
};
/*! Bundled license information:

long/umd/index.js:
  (**
   * @license
   * Copyright 2009 The Closure Library Authors
   * Copyright 2020 Daniel Wirtz / The long.js Authors.
   *
   * Licensed under the Apache License, Version 2.0 (the "License");
   * you may not use this file except in compliance with the License.
   * You may obtain a copy of the License at
   *
   *     http://www.apache.org/licenses/LICENSE-2.0
   *
   * Unless required by applicable law or agreed to in writing, software
   * distributed under the License is distributed on an "AS IS" BASIS,
   * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   * See the License for the specific language governing permissions and
   * limitations under the License.
   *
   * SPDX-License-Identifier: Apache-2.0
   *)
*/
//# sourceMappingURL=index.js.map

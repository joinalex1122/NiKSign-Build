/* NiKSign 2.1 — GPL-3.0. Local document tools; no signing simulation. */
(function(root) {
  'use strict';
  const api = {
    parseJSON(text) {
      const value = JSON.parse(text);
      if (value === null || Array.isArray(value) || typeof value !== 'object')
        throw new Error('Cần JSON object ở gốc.');
      return value;
    },
    formatJSON(text) { return JSON.stringify(api.parseJSON(text), null, 2); },
    outputName(name, kind) {
      const base = String(name).split(/[\\/]/).pop().replace(/\.[^.]*$/, '') || 'config';
      return base + (kind === 'plist' ? '.plist' : '.json');
    },
    is3105(bytes) {
      const magic = [51,49,48,53,80,65,84,67,72,0];
      return magic.every((b,i) => bytes[i] === b);
    },
    setField(text, key, type, raw) {
      const object = api.parseJSON(text);
      if (!key || key.length > 255) throw new Error('Tên key cần 1–255 ký tự.');
      let value = raw;
      if (type === 'number') {
        if (!String(raw).trim() || !Number.isFinite(Number(raw))) throw new Error('Số không hợp lệ.');
        value = Number(raw);
      } else if (type === 'boolean') {
        if (raw !== 'true' && raw !== 'false') throw new Error('Boolean phải là true hoặc false.');
        value = raw === 'true';
      } else if (type === 'json') { value = JSON.parse(raw); }
      Object.defineProperty(object, key, {value, enumerable: true, configurable: true, writable: true});
      return JSON.stringify(object, null, 2);
    }
  };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  root.NiKCore = api;
})(globalThis);

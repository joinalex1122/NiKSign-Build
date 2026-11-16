'use strict';
const $ = id => document.getElementById(id);
let filename = 'config.json', kind = 'json';
const status = text => { $('notice').textContent = text; };
const attempt = fn => { try { return fn(); } catch(e) { status(e.message); } };
function validate() {
  if (kind === 'json') return NiKCore.formatJSON($('editor').value);
  const doc = new DOMParser().parseFromString($('editor').value, 'application/xml');
  if (doc.querySelector('parsererror') || doc.documentElement.nodeName !== 'plist' ||
      doc.documentElement.children.length !== 1) throw new Error('XML plist không hợp lệ.');
  const tags = new Set(['plist','dict','array','key','string','integer','real','true','false','date','data']);
  for (const node of doc.getElementsByTagName('*')) {
    if (!tags.has(node.nodeName)) throw new Error('Plist có thẻ không hỗ trợ: '+node.nodeName);
    if (node.nodeName === 'dict') {
      const c = [...node.children];
      if (c.length % 2 || c.some((n,i) => i%2 === 0 ? n.nodeName !== 'key' : n.nodeName === 'key'))
        throw new Error('Dictionary plist cần các cặp key / giá trị.');
    }
  }
  return $('editor').value;
}
function persist() {
  attempt(() => {
    if ($('remember').checked) localStorage.setItem('niksign.draft', JSON.stringify({filename,kind,text:$('editor').value}));
    else localStorage.removeItem('niksign.draft');
  });
}
$('open').addEventListener('change', async e => {
  const file = e.target.files[0]; if (!file) return;
  try {
    if (file.size > 8*1024*1024) throw new Error('Bản web nhận tệp tối đa 8 MB.');
    const bytes = new Uint8Array(await file.arrayBuffer());
    if (NiKCore.is3105(bytes)) throw new Error('Gói mã hóa 3105PATCH: hãy dùng trình nhập .3105 trong bản native.');
    const content = new TextDecoder('utf-8', {fatal:true}).decode(bytes);
    const nextKind = content.trimStart().startsWith('<') ? 'plist' : 'json';
    if (nextKind === 'json') NiKCore.parseJSON(content);
    else {
      const doc = new DOMParser().parseFromString(content,'application/xml');
      if(doc.querySelector('parsererror') || doc.documentElement.nodeName !== 'plist') throw new Error('Cần XML plist hợp lệ. Binary plist dùng bản native.');
    }
    kind = nextKind; filename = NiKCore.outputName(file.name,kind);
    $('filename').textContent = filename; $('editor').value = content;
    status('Đã mở bản sao. Tệp gốc không bị ghi đè.'); persist();
  } catch(e) { status(e.message); }
  e.target.value = '';
});
$('openLabel').addEventListener('keydown', e => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); $('open').click(); } });
$('format').onclick = () => attempt(() => { $('editor').value = validate(); status('Cấu trúc hợp lệ.'); persist(); });
$('set').onclick = () => attempt(() => {
  if (kind !== 'json') throw new Error('Bảng key này chỉ sửa JSON. Sửa XML trực tiếp trong vùng nội dung.');
  $('editor').value = NiKCore.setField($('editor').value,$('key').value,$('type').value,$('value').value); persist(); status('Đã cập nhật key.');
});
function output() { return new File([validate()],filename,{type:kind === 'json' ? 'application/json' : 'application/xml'}); }
$('save').onclick = () => attempt(() => {
  const file = output(); const url = URL.createObjectURL(file);
  const a = document.createElement('a'); a.href = url; a.download = filename;
  document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(url),60000);
  status('Đã yêu cầu tải tệp. Trong Safari, mở mục Tải về để lưu hoặc chia sẻ.');
});
$('share').onclick = async () => {
  try {
    const file = output();
    if (!navigator.canShare?.({files:[file]})) throw new Error('Trình duyệt này không chia sẻ tệp được. Hãy dùng Lưu vào Tệp.');
    await navigator.share({files:[file]}); status('Đã đóng bảng chia sẻ.');
  } catch(e) { if(e.name !== 'AbortError') status(e.message); }
};
$('new').onclick = () => {
  if (!confirm('Tạo tệp mới và bỏ nội dung đang sửa?')) return;
  filename='config.json'; kind='json'; $('filename').textContent=filename;
  $('editor').value='{\n  "enabled": true\n}'; persist(); status('Đã tạo bản nháp mới.');
};
let draftTimer;
$('editor').addEventListener('input', () => { clearTimeout(draftTimer); draftTimer=setTimeout(persist,400); });
$('remember').onchange = persist;
$('forget').onclick = () => attempt(() => { localStorage.removeItem('niksign.draft'); $('remember').checked=false; status('Đã xóa bản nháp lưu trên trình duyệt. Nội dung đang sửa vẫn còn.'); });
attempt(() => {
  const saved=localStorage.getItem('niksign.draft'); if(!saved) return;
  const d=JSON.parse(saved);
  if(typeof d.text==='string' && ['json','plist'].includes(d.kind)) {
    kind=d.kind; filename=NiKCore.outputName(d.filename,kind); $('editor').value=d.text;
    $('filename').textContent=filename; $('remember').checked=true; status('Đã khôi phục bản nháp.');
  }
});

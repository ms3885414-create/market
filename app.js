const sb=supabase.createClient(CFG.URL.trim(),CFG.KEY.trim());
const $=i=>document.getElementById(i);
const E=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const money=n=>Number(n).toLocaleString('ar-EG')+' ج.م';
const link=p=>new URL(p,location.href).href;
function shrink(file,max=800){return new Promise((res,rej)=>{const im=new Image();im.onload=()=>{const k=Math.min(1,max/Math.max(im.width,im.height)),c=document.createElement('canvas');c.width=im.width*k;c.height=im.height*k;c.getContext('2d').drawImage(im,0,0,c.width,c.height);c.toBlob(b=>b?res(b):rej(new Error('صورة غير صالحة')),'image/jpeg',.82)};im.onerror=()=>rej(new Error('صورة غير صالحة'));im.src=URL.createObjectURL(file)})}
async function upImg(file,tid){const b=await shrink(file),p=tid+'/'+Date.now()+'.jpg';const {error}=await sb.storage.from('product-images').upload(p,b,{contentType:'image/jpeg'});if(error)throw error;return sb.storage.from('product-images').getPublicUrl(p).data.publicUrl}
const okT=t=>t&&t.subscription_status==='active'&&(!t.expires_at||t.expires_at>=new Date().toISOString().slice(0,10));
const norm=x=>String(x??'').trim().replace(/\s+/g,' ').toLowerCase().replace(/[أإآ]/g,'ا').replace(/ة/g,'ه').replace(/ى/g,'ي');
const FR=['','تمن','ربع','ربع وتمن','نص','نص وتمن','تلات أرباع','تلات أرباع وتمن'];
function weightText(q){q=Math.round(q*1000)/1000;const k=Math.floor(q+1e-9),f=FR[Math.round((q-k)*8)]||'';
  if(!k)return f?f+' كيلو':'0';const ks=k===1?'كيلو':k===2?'كيلوين':k+' كيلو';return f?ks+' و'+f:ks}
const qtyText=(q,u)=>u==='kg'?weightText(Number(q)):String(Number(q));

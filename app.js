const sb=supabase.createClient(CFG.URL.trim(),CFG.KEY.trim());
const $=i=>document.getElementById(i);
const E=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const money=n=>Number(n).toLocaleString('ar-EG')+' ج.م';
const link=p=>new URL(p,location.href).href;
function shrink(file,max=800){return new Promise((res,rej)=>{const im=new Image();im.onload=()=>{const k=Math.min(1,max/Math.max(im.width,im.height)),c=document.createElement('canvas');c.width=im.width*k;c.height=im.height*k;c.getContext('2d').drawImage(im,0,0,c.width,c.height);c.toBlob(b=>b?res(b):rej(new Error('صورة غير صالحة')),'image/jpeg',.82)};im.onerror=()=>rej(new Error('صورة غير صالحة'));im.src=URL.createObjectURL(file)})}
async function upImg(file,tid){const b=await shrink(file),p=tid+'/'+Date.now()+'.jpg';const {error}=await sb.storage.from('product-images').upload(p,b,{contentType:'image/jpeg'});if(error)throw error;return sb.storage.from('product-images').getPublicUrl(p).data.publicUrl}
const okT=t=>t&&t.subscription_status==='active'&&(!t.expires_at||t.expires_at>=new Date().toISOString().slice(0,10));

/* Approval actions are online-only. This module only caches Outstanding details/photos for read-only offline review. */
(function () {
"use strict";
const C="inspection_approval_cache", A="inspection_approval_queue", P="inspection_photos";
const key=(s,t,id,tab)=>[t,s.e,s.c,s.l,String(tab||""),String(id||"")].join("|");
const req=r=>new Promise((ok,no)=>{r.onsuccess=()=>ok(r.result);r.onerror=()=>no(r.error);});
const done=(tx,msg)=>new Promise((ok,no)=>{tx.oncomplete=ok;tx.onerror=()=>no(tx.error||new Error(msg));tx.onabort=()=>no(tx.error||new Error(msg));});
async function post(method,args){const r=await fetch("inspection.aspx/"+method,{method:"POST",headers:{"Content-Type":"application/json; charset=utf-8"},body:JSON.stringify(args)});const p=await r.json();const d=p&&Object.prototype.hasOwnProperty.call(p,"d")?p.d:p;if(!r.ok||d&&d.success===false)throw new Error(d&&d.message||p.Message||("HTTP "+r.status));return d;}
async function all(store){return req(db.transaction(store,"readonly").objectStore(store).getAll());}
async function putCache(row){const tx=db.transaction(C,"readwrite");tx.objectStore(C).put(row);await done(tx,"Cache approval gagal.");}
async function removePhotoPartition(id){if(!id)return;const tx=db.transaction(P,"readwrite"),r=tx.objectStore(P).index("LocalInspectionID").openCursor(IDBKeyRange.only(id));r.onsuccess=()=>{const c=r.result;if(c){c.delete();c.continue();}};await done(tx,"Hapus foto cache gagal.");}
async function mapLimit(items,limit,worker){const list=Array.isArray(items)?items:[],results=new Array(list.length);let next=0;const workers=Array.from({length:Math.min(Math.max(1,limit|0),list.length)},async()=>{while(next<list.length){const index=next++;results[index]=await worker(list[index],index);}});await Promise.all(workers);return results;}
async function cacheDetail(s,id,d){
 if(!d||!d.header)return;
 const local="SPVAPPROVAL|"+s.e+"|"+s.c+"|"+s.l+"|"+id;
 const createdAt=new Date().toISOString();
 // Convert photo data URLs concurrently, but cap per-detail work to avoid
 // creating too many simultaneous Blobs on mobile devices.
 const photos=(await mapLimit(d.photos||[],3,async p=>{
  if(!p||!p.Data)return null;
  return {LocalInspectionID:local,Type:String(p.Type||"").toUpperCase(),FileName:p.FileName||"",Blob:await(await fetch(p.Data)).blob(),SeqNo:Number(p.SeqNo||p.OrderNo||0),CreatedAt:createdAt,ApprovalCachePhoto:true};
 })).filter(Boolean);
 const safe=Object.assign({},d);delete safe.photos;
 // Store photo replacement and detail metadata atomically. Previously these
 // were three serial IDB transactions (delete photos, write photos, cache detail).
 const tx=db.transaction([P,C],"readwrite"),st=tx.objectStore(P),r=st.index("LocalInspectionID").openCursor(IDBKeyRange.only(local));
 r.onsuccess=()=>{
  const c=r.result;
  if(c){c.delete();c.continue();return;}
  photos.forEach(p=>st.add(p));
  tx.objectStore(C).put({CacheKey:key(s,"DETAIL",id),CacheType:"DETAIL",EmployeeID:s.e,CompanyID:s.c,LocationID:s.l,InspectionID:Number(id),PhotoLocalInspectionID:local,Data:safe,CachedAt:createdAt});
 };
 await done(tx,"Simpan detail/foto approval gagal.");
}
async function deleteConfirmed(s,a){let tx=db.transaction(A,"readwrite");tx.objectStore(A).delete(a.ActionID);await done(tx,"Hapus approval pending gagal.");tx=db.transaction(C,"readwrite");tx.objectStore(C).delete(key(s,"DETAIL",a.InspectionID));await done(tx,"Hapus detail cache gagal.");await removePhotoPartition("SPVAPPROVAL|"+s.e+"|"+s.c+"|"+s.l+"|"+a.InspectionID);}
async function cleanupStaleCache(s,currentIds){
 const actions=(await all(A)).filter(a=>a.EmployeeID===s.e&&a.CompanyID===s.c&&a.LocationID===s.l&&(a.Status==="PENDING"||a.Status==="CONFLICT"));
 const protectedIds=new Set(actions.map(a=>Number(a.InspectionID)));
 const rows=(await all(C)).filter(r=>r.EmployeeID===s.e&&r.CompanyID===s.c&&r.LocationID===s.l);
 for(const row of rows){
  if(row.CacheType==="QUEUE"&&row.ApprovalTab!=="OUTSTANDING"){const tx=db.transaction(C,"readwrite");tx.objectStore(C).delete(row.CacheKey);await done(tx,"Hapus cache history approval gagal.");continue;}
  if(row.CacheType==="DETAIL"&&!currentIds.has(Number(row.InspectionID))&&!protectedIds.has(Number(row.InspectionID))){
   const tx=db.transaction(C,"readwrite");tx.objectStore(C).delete(row.CacheKey);await done(tx,"Hapus detail approval lama gagal.");
   if(String(row.PhotoLocalInspectionID||"").indexOf("SPVAPPROVAL|")===0)await removePhotoPartition(row.PhotoLocalInspectionID);
  }
 }
}
window.syncInspectionApprovalOffline=async function(){
 const l=getLoginData();if(!l||typeof hasAuthorizedMenu!=="function"||!hasAuthorizedMenu(20022))return{synced:0,cached:0,conflicts:0};if(!navigator.onLine)throw new Error("Koneksi internet diperlukan untuk sync approval SPV.");
 if(!db||![C,A,P].every(n=>db.objectStoreNames.contains(n)))throw new Error("IndexedDB approval belum siap.");
 const parts=String(l.curcompany||"").split(";"),s={e:String(l.employeeid),c:String(parts[0]||""),l:String(parts[1]||"")};let synced=0,conflicts=0;
  const now=new Date(),date=now.getFullYear()+"-"+String(now.getMonth()+1).padStart(2,"0")+"-"+String(now.getDate()).padStart(2,"0");
 const q=await post("GetInspectionApprovalQueue",{employeeId:s.e,companyId:s.c,locationId:s.l,approvalTab:"OUTSTANDING",dateFrom:date,dateThru:date,inspectionTypeCode:"",inspectionTypeDetailCode:"",templateId:"",scheduleTime:""});
 await putCache({CacheKey:key(s,"QUEUE","","OUTSTANDING"),CacheType:"QUEUE",EmployeeID:s.e,CompanyID:s.c,LocationID:s.l,ApprovalTab:"OUTSTANDING",Data:q.data||[],Filters:q.filters||[],CachedAt:new Date().toISOString()});
 const queueRows=Array.isArray(q.data)?q.data:[],currentIds=new Set(queueRows.map(row=>Number(row.InspectionID)));
 let cached=0,nextIndex=0;const failures=[];
 // Detail endpoint reads header, results, points, template rules and photos.
 // A small worker pool overlaps network/SQL latency without flooding IIS/SQL.
 const workerCount=Math.min(3,queueRows.length);
 const workers=Array.from({length:workerCount},async function(){
  while(nextIndex<queueRows.length){
   const row=queueRows[nextIndex++];
   if(!navigator.onLine){failures.push({id:row.InspectionID,message:"Koneksi terputus."});continue;}
   try{
    const d=await post("GetInspectionApprovalDetail",{inspectionId:row.InspectionID,employeeId:s.e});
    await cacheDetail(s,row.InspectionID,d);cached++;
   }catch(error){
    failures.push({id:row.InspectionID,message:error&&error.message?error.message:String(error)});
    console.warn("Approval detail cache failed:",row.InspectionID,error);
   }
  }
 });
 await Promise.all(workers);
 if(failures.length)throw new Error(failures.length+" dari "+queueRows.length+" detail approval gagal di-cache. Contoh inspeksi #"+failures[0].id+": "+failures[0].message);
 await cleanupStaleCache(s,currentIds);
 return{synced,cached,conflicts};
};
})();
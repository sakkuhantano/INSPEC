<%@ Page Title="" Language="C#" MasterPageFile="~/MasterPages/Site1.Master" AutoEventWireup="true" CodeBehind="T_LightingInspection.aspx.cs" Inherits="INSPEC.Secure.T_LightingInspection" %>
<%@ MasterType VirtualPath="~/MasterPages/Site1.Master" %>
<asp:Content ID="Content1" ContentPlaceHolderID="head" runat="server">
<style type="text/css">
.li-page {
    font:13px Arial,Tahoma,sans-serif;
    color:#243b50;
    background:#f5f7fa;
    padding:14px
}
.li-page * {
    box-sizing:border-box
}
.li-head,.li-card {
    background:white;
    border:1px solid #dbe3eb;
    border-radius:7px;
    margin-bottom:12px;
    padding:14px
}
.li-head {
    text-align:center
}
.li-head h2 {
    font-size:18px;
    margin:0 0 5px;
    font-weight:bold
}
.li-sub {
    color:#718295
}
.li-controls {
    display:flex;
    gap:12px;
    flex-wrap:wrap;
    align-items:end
}
.li-controls label {
    display:block;
    font-size:11px;
    font-weight:bold;
    margin-bottom:5px
}
.li-controls input {
    padding:7px;
    border:1px solid #c9d5df;
    border-radius:4px
}
.li-btn {
    border:1px solid #ccd6df;
    background:white;
    padding:8px 12px;
    border-radius:5px;
    cursor:pointer
}
.li-btn-primary {
    background:#147d9e;
    color:white;
    border-color:#147d9e
}
.li-btn:disabled {
    opacity:.5;
    cursor:default
}
.li-tabs {
    display:flex;
    gap:6px;
    flex-wrap:wrap;
    margin:10px 0
}
.li-tabs button.active {
    background:#167c9b;
    color:white
}
.li-layout {
    display:grid;
    grid-template-columns:minmax(0,1.1fr) minmax(320px,1fr);
    gap:12px
}
.li-map {
    overflow:hidden;
    position:relative;
    background:#f1f5f8;
    border:1px solid #e0e8ed;
    border-radius:6px;
    min-height:300px;
    display:flex;
    align-items:center;
    justify-content:center;
    touch-action:none;
    user-select:none;
    -webkit-user-select:none;
    cursor:grab
}
.li-map svg {
    max-width:100%;
    max-height:65vh;
    min-height:280px;
    overflow:visible;
    touch-action:none
}
.li-map.li-dragging svg {cursor:grabbing}
.li-map .li-shape {
    cursor:pointer;
    transition:opacity .15s
}
.li-map .li-shape:hover {
    opacity:.75
}
.li-map .li-shape:focus {
    outline:none;
    stroke:#2563eb;
    stroke-width:4
}
.li-map-tools {
    display:flex;
    gap:6px;
    margin:8px 0;
    align-items:center
}
.li-list {
    max-height:67vh;
    overflow:auto
}
.li-area {
    border-bottom:1px solid #e7edf2;
    padding:8px 0
}
.li-area h4 {
    margin:5px 0 9px;
    font-size:13px
}
.li-item {
    display:grid;
    grid-template-columns:minmax(95px,1fr) auto;
    gap:8px;
    align-items:center;
    padding:6px 3px;
    border-top:1px solid #f0f3f6
}
.li-item.selected {
    background:#edf8fc
}
.li-status {
    display:flex;
    gap:3px
}
.li-status button {
    padding:5px 9px;
    border:1px solid #d6e0e7;
    border-radius:4px;
    background:white;
    cursor:pointer
}
.li-status button.on.active {
    background:#16834a;
    color:white
}
.li-status button.off.active {
    background:#c83f3f;
    color:white
}
.li-notes {
    grid-column:1/-1;
    width:100%;
    padding:5px;
    border:1px solid #e0e6ed;
    border-radius:4px;
    font:12px Arial
}
.li-kpis {
    display:flex;
    gap:15px;
    flex-wrap:wrap;
    margin:8px 0;
    color:#5c7080
}
.li-kpis strong {
    color:#20384c
}
.li-msg {
    padding:9px;
    border-radius:5px;
    margin:8px 0
}
.li-error {
    background:#fff0f0;
    color:#9b2424
}
.li-success {
    background:#e9f8ee;
    color:#17633c
}
.li-warning {
    background:#fff7e5;
    color:#815600
}
.li-empty {
    padding:24px;
    color:#718295;
    text-align:center
}
.li-pill {
    display:inline-block;
    border-radius:12px;
    background:#eaf0f4;
    padding:4px 9px;
    font-weight:bold
}
.li-dirty {
    color:#a35b00;
    font-size:12px
}
@media(max-width:850px) {
    .li-layout {
        grid-template-columns:1fr
    }
    .li-list {
        max-height:none
    }
    .li-page {
        padding:7px
    }
    .li-map svg {
        max-height:50vh
    }
    .li-controls {
        align-items:stretch
    }
}

/* Mobile: input only through SVG popup; keep checklist DOM for JS synchronization. */
@media(max-width:850px) {
    .li-checklist-card { display:none !important; }
}

/* Transaction mobile/desktop inspection dialog */
.li-dialog-backdrop{position:fixed;inset:0;background:rgba(15,23,42,.55);z-index:9999;display:none;align-items:center;justify-content:center;padding:12px}
.li-dialog-backdrop.li-open{display:flex}
.li-dialog{background:#fff;border-radius:12px;width:100%;max-width:420px;max-height:calc(100vh - 24px);overflow:auto;padding:18px;box-shadow:0 16px 48px rgba(0,0,0,.25)}
.li-dialog h3{margin:0 0 6px;font-size:18px}
.li-dialog-sub{color:#64748b;margin-bottom:15px}
.li-dialog-options{display:flex;gap:8px;margin-bottom:14px}
.li-dialog-options button{flex:1;min-height:44px;border:1px solid #cbd5e1;border-radius:7px;background:#fff;font-weight:bold}
.li-dialog-options button.li-on{background:#16834a;color:#fff;border-color:#16834a}
.li-dialog-options button.li-off{background:#c83f3f;color:#fff;border-color:#c83f3f}
.li-dialog-options button.li-clear{background:#64748b;color:#fff;border-color:#64748b}
.li-dialog textarea{width:100%;min-height:85px;border:1px solid #cbd5e1;border-radius:7px;padding:9px;font:14px Arial;resize:vertical}
.li-dialog-actions{display:flex;justify-content:flex-end;gap:8px;margin-top:15px}
@media(max-width:600px){.li-dialog-backdrop{align-items:flex-end;padding:0}.li-dialog{max-width:none;border-radius:16px 16px 0 0;max-height:85vh;padding-bottom:calc(18px + env(safe-area-inset-bottom))}}

/* Task 05D-03: approval overview, read-only */
.li-approval-grid{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:10px;margin-top:12px}
.li-approval-step{border:1px solid #dbe3eb;border-radius:7px;padding:12px;min-width:0;background:#fff}
.li-approval-step.is-done{border-color:#a9d9ba;background:#f3fbf5}
.li-approval-step.is-pending{background:#f8fafc}
.li-approval-label{font-weight:bold;font-size:12px;margin-bottom:7px}
.li-approval-state{font-size:11px;color:#64748b;margin-bottom:8px}
.li-approval-user{font-weight:bold;overflow-wrap:anywhere}
.li-approval-date{font-size:11px;color:#64748b;margin-top:5px}
@media(max-width:850px){.li-approval-grid{grid-template-columns:repeat(2,minmax(0,1fr))}}
@media(max-width:420px){.li-approval-grid{grid-template-columns:1fr}}
/* Task 05D-05A: approval action UI only; no server mutation */
.li-approval-action{margin-top:14px;padding-top:12px;border-top:1px solid #e5ebf0;display:flex;align-items:center;gap:10px;flex-wrap:wrap}
.li-approval-action .li-sub{flex:1;min-width:180px}
.li-approval-confirm-backdrop{position:fixed;inset:0;z-index:10001;background:rgba(15,23,42,.55);display:none;align-items:center;justify-content:center;padding:12px}
.li-approval-confirm-backdrop.li-open{display:flex}
.li-approval-confirm{background:white;border-radius:10px;padding:18px;width:100%;max-width:440px;box-shadow:0 16px 48px rgba(0,0,0,.25)}
.li-approval-confirm h3{margin:0 0 10px}
.li-approval-confirm-actions{display:flex;gap:8px;justify-content:flex-end;margin-top:16px}
@media(max-width:600px){.li-approval-confirm-backdrop{align-items:flex-end;padding:0}.li-approval-confirm{max-width:none;border-radius:14px 14px 0 0}}
/* Site1.Master / Bootstrap 5 integration: keep inspection controls isolated. */
#lightingApp { width:100%; max-width:100%; min-width:0; margin:0; }
#lightingApp .li-head, #lightingApp .li-card { box-shadow:none; }
#lightingApp .li-controls input[type="date"] { display:block; width:100%; min-width:170px; max-width:240px; min-height:36px; background:#fff; color:#243b50; font:inherit; }
#lightingApp .li-btn { font:inherit; line-height:1.35; min-height:35px; }
#lightingApp .li-layout > .li-card { min-width:0; }
#lightingApp .li-approval-grid > .li-approval-step { min-width:0; }
@media(max-width:850px) {
  #lightingApp { padding:8px 4px; }
  #lightingApp .li-controls > div:first-child { flex:1 1 190px; }
  #lightingApp .li-controls input[type="date"] { max-width:none; }
  #lightingApp .li-layout { grid-template-columns:minmax(0,1fr); }
}

/* LI-01: target locator after "Lihat di Map" */
.li-map .li-focus-ring{fill:rgba(255,193,7,.13);stroke:#f59e0b;stroke-width:3;stroke-dasharray:5 4;pointer-events:none;vector-effect:non-scaling-stroke;animation:li-focus-pulse 1.15s ease-in-out 4;transform-box:fill-box;transform-origin:center}
.li-map .li-focus-dot{fill:#f59e0b;stroke:#fff;stroke-width:2;pointer-events:none;vector-effect:non-scaling-stroke}
.li-map .li-shape.li-target-shape{filter:drop-shadow(0 0 5px #f59e0b)}
@keyframes li-focus-pulse{0%,100%{opacity:1;transform:scale(1)}50%{opacity:.65;transform:scale(1.13)}}
@media(prefers-reduced-motion:reduce){.li-map .li-focus-ring{animation:none}}

/* LI-01: Missing inspection drilldown */
.li-missing-trigger{border:1px solid #e6bb68;border-radius:6px;background:#fff8e8;color:#79510b;padding:7px 10px;cursor:pointer;font:inherit}
.li-missing-trigger:hover,.li-missing-trigger:focus{background:#ffedc5;outline:2px solid #e7b44f;outline-offset:1px}
.li-missing-dialog{width:min(680px,100%);max-height:85vh;overflow:auto;background:white;border-radius:10px;padding:18px;box-shadow:0 12px 40px rgba(0,0,0,.25)}
.li-missing-table{width:100%;border-collapse:collapse;margin:12px 0}
.li-missing-table th,.li-missing-table td{border-bottom:1px solid #e3e9ef;text-align:left;padding:9px 7px}
.li-missing-table button{cursor:pointer}
.li-missing-actions{display:flex;justify-content:flex-end;margin-top:12px}

/* LI-01 refinement: unified inline inspection summary */
#lightingApp .li-kpis{display:flex;align-items:center;gap:5px 16px;flex-wrap:wrap;margin:10px 0;color:#617286;font-size:13px;line-height:1.4}
#lightingApp .li-kpi-item,#lightingApp .li-missing-trigger{display:inline-flex;align-items:center;gap:5px;min-height:30px;white-space:nowrap}
#lightingApp .li-kpi-label{font-weight:400;color:#68788a}
#lightingApp .li-kpi-value{font-weight:700;font-size:14px;color:#24384b;font-variant-numeric:tabular-nums}
#lightingApp .li-kpi-on .li-kpi-value{color:#17844c}
#lightingApp .li-kpi-off .li-kpi-value{color:#c13d3d}
#lightingApp .li-missing-trigger{border:0;border-radius:5px;background:transparent;padding:3px 5px;margin:-3px -5px;color:#9b6500;font:inherit;cursor:pointer;transition:background-color .15s ease}
#lightingApp .li-missing-trigger .li-kpi-label,#lightingApp .li-missing-trigger .li-kpi-value{color:#9b6500}
#lightingApp .li-missing-trigger .li-kpi-arrow{display:inline-block;flex:0 0 6px;width:6px;height:6px;box-sizing:border-box;border-right:1.5px solid currentColor;border-top:1.5px solid currentColor;transform:rotate(45deg);margin:0 2px 0 3px;align-self:center;font-size:0;line-height:0;color:#a36c11}
#lightingApp .li-missing-trigger:hover{background:#fff5e4}
#lightingApp .li-missing-trigger:focus-visible{outline:2px solid #d89a2b;outline-offset:2px}
#lightingApp .li-kpi-dirty{display:inline-flex;align-items:center;min-height:30px;font-size:12px;color:#7b8997}
@media(max-width:600px){#lightingApp .li-kpis{gap:4px 12px;font-size:12px}#lightingApp .li-kpi-value{font-size:13px}}
</style>
</asp:Content>
<asp:Content ID="Content2" ContentPlaceHolderID="ContentPlaceHolder1" runat="server">
    <asp:ScriptManager ID="smLighting" runat="server" />
    <div class="li-page" id="lightingApp">
        <div class="li-head">
            <h2>
                LIGHTING INSPECTION
            </h2>
            <div class="li-sub">
                Daily Lighting Checklist &amp; Interactive Map
            </div>
        </div>
        <div class="li-card">
            <div class="li-controls">
                <div>
                    <label for="liDate">
                        Tanggal Inspeksi
                    </label>
                    <input type="date" id="liDate" value="<%= Server.HtmlEncode(SelectedDateIso) %>" />
                </div>
                <button type="button" class="li-btn" id="liLoad">
                    Load Date
                </button>
                <div>
                    <label>
                        Workflow
                    </label>
                    <span id="liWorkflow" class="li-pill">
                        NOT CREATED
                    </span>
                </div>
                <button type="button" class="li-btn li-btn-primary" id="liSave">
                    Save Changes
                </button>
               
<asp:Label ID="lblDispatchLightingEmail" runat="server" />
            </div>
            <div id="liMessage" aria-live="polite">
            </div>
            <div class="li-tabs" id="liSchedules">
            </div>
            <div class="li-kpis" id="liStats">
            </div>
        </div>
        <div class="li-card" id="liApprovalPanel" aria-label="Approval workflow">
            <strong>Approval Workflow</strong>
            <div class="li-sub" id="liApprovalCaption">Memuat status persetujuan...</div>
            <div class="li-approval-grid" id="liApprovalSteps"></div>
            <div class="li-approval-action">
                <span class="li-sub" id="liApprovalActionHint" aria-live="polite"></span>
                <button type="button" class="li-btn li-btn-primary" id="liApprovalAction" disabled style="display:none"></button>
            </div>
        </div>
        <div class="li-layout">
            <div class="li-card">
                <strong>
                    Denah Interaktif
                </strong>
                <div class="li-tabs" id="liMaps">
                </div>
                <div class="li-map-tools">
                    <button class="li-btn" type="button" id="liZoomIn">
                        +
                    </button>
                    <button class="li-btn" type="button" id="liZoomOut">
                        −
                    </button>
                    <button class="li-btn" type="button" id="liResetZoom">
                        Reset Zoom
                    </button>
                    <span class="li-sub" id="liMapCaption">
                    </span>
                </div>
                <div class="li-map" id="liMapCanvas">
                </div>
                <div class="li-sub" style="margin-top:9px">
                    Hijau = ON · Merah = OFF · Abu-abu = Belum diperiksa. Drag denah untuk pan; tap/klik lampu untuk ON/OFF dan catatan.
                </div>
            </div>
            <div class="li-card li-checklist-card">
                <strong>
                    Checklist Lampu
                </strong>
                <div class="li-sub" id="liListCaption">
                </div>
                <div class="li-list" id="liChecklist">
                </div>
            </div>
        </div>
        <%-- LI-01: read-only list of unchecked lights for selected schedule --%>
        <div id="liMissingBackdrop" class="li-dialog-backdrop" aria-hidden="true">
            <div class="li-missing-dialog" role="dialog" aria-modal="true" aria-labelledby="liMissingTitle">
                <h3 id="liMissingTitle">Lampu Belum Diperiksa</h3>
                <div id="liMissingCaption" class="li-sub"></div>
                <div id="liMissingContent"></div>
                <div class="li-missing-actions"><button type="button" class="li-btn" id="liMissingClose">Tutup</button></div>
            </div>
        </div>
        <div id="liDialogBackdrop" class="li-dialog-backdrop" aria-hidden="true">
            <div class="li-dialog" role="dialog" aria-modal="true" aria-labelledby="liDialogTitle">
                <h3 id="liDialogTitle">Inspeksi Lampu</h3>
                <div id="liDialogSubtitle" class="li-dialog-sub"></div>
                <div class="li-dialog-options" id="liDialogOptions">
                    <button type="button" data-value="ON">ON</button>
                    <button type="button" data-value="OFF">OFF</button>
                    <button type="button" data-value="">Kosong</button>
                </div>
                <label for="liDialogNotes">Catatan</label>
                <textarea id="liDialogNotes" maxlength="2000" placeholder="Catatan (opsional)"></textarea>
                <div class="li-photo-field" style="margin-top:12px">
                    <label>Foto Bukti (JPEG/PNG, maks. 5 MB)</label>
                    <asp:FileUpload ID="fuLightingPhoto" runat="server" accept="image/jpeg,image/png" />
                    <div class="li-dialog-sub">Pilih foto, kemudian klik Terapkan. Untuk status OFF, foto wajib ada. Status dan foto disimpan sekaligus.</div>
                </div>
                <div id="liPhotoGallery" style="display:flex;flex-wrap:wrap;gap:8px;margin:10px 0" aria-label="Foto inspeksi lampu"></div>
                <div class="li-dialog-actions">
                    <button type="button" class="li-btn" id="liDialogCancel">Batal</button>
                    <button type="button" class="li-btn li-btn-primary" id="liDialogApply">Terapkan</button>
                </div>
            </div>
        </div>
        <div id="liApprovalConfirmBackdrop" class="li-approval-confirm-backdrop" aria-hidden="true">
            <div class="li-approval-confirm" role="dialog" aria-modal="true" aria-labelledby="liApprovalConfirmTitle">
                <h3 id="liApprovalConfirmTitle">Konfirmasi Approval</h3>
                <p id="liApprovalConfirmText"></p>
                <div class="li-warning li-msg" id="liApprovalConfirmWarning">Pastikan semua perubahan sudah disimpan. Tindakan ini akan mengunci checklist.</div>
                <div class="li-approval-confirm-actions">
                    <button type="button" class="li-btn" id="liApprovalCancel">Batal</button>
                    <button type="button" class="li-btn li-btn-primary" id="liApprovalConfirm">Konfirmasi</button>
                </div>
            </div>
        </div>
        <asp:HiddenField ID="hfApprovalRowVer" runat="server" />
        <asp:HiddenField ID="hfLightingPayload" runat="server" />
        <asp:HiddenField ID="hfLightingDate" runat="server" />
        <asp:HiddenField ID="hfLightingPhotoLight" runat="server" />
        <asp:HiddenField ID="hfLightingPhotoSchedule" runat="server" />
        <asp:LinkButton ID="btnLightingApplyWithPhoto" runat="server" OnClick="btnLightingApplyWithPhoto_Click" Style="display:none" CausesValidation="false" />
        <asp:LinkButton ID="btnLightingApprove" runat="server" OnClick="btnLightingApprove_Click" Style="display:none" CausesValidation="false" />
        <asp:LinkButton ID="btnLightingSave" runat="server" OnClick="btnLightingSave_Click" Style="display:none" CausesValidation="false" />
        <asp:LinkButton ID="btnLightingLoad" runat="server" OnClick="btnLightingLoad_Click" Style="display:none" CausesValidation="false" />
    </div>
<script type="text/javascript">
    (function() {
        var root=document.getElementById('lightingApp');if(!root)return;
        var initial=<%= InitialJson %>;
        var data=initial,activeSchedule=null,activeMap=null,selectedLight=null,zoom=1,panX=0,panY=0,svgNode=null,gesture=null,suppressClick=false,dialogLight=null,dialogStatus="",dirty= {
        }
        ,isEditable=false;
        var byId=function(id) {
            return document.getElementById(id);
        }
        ;
        var key=function(s,l) {
            return String(s)+':'+String(l);
        }
        ;
        var esc=function(s) {
            return String(s==null?'':s).replace(/[&<>"']/g,function(c) {
                return {
                    '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'
                }
                [c];
            }
            );
        }
        ;
        var statuses= {
        }
        ;(data.checklist||[]).forEach(function(x) {
            statuses[key(x.ScheduleID,x.LightID)]= {
                status:x.LightStatus||'',notes:x.Notes||''
            }
            ;
        }
        );
        var maps=data.maps||[],lights=data.lights||[],areas=data.areas||[],paths=data.paths||[],rows=data.checklist||[];
        var schedules=[];rows.forEach(function(r) {
            if(!schedules.some(function(x) {
                return x.ScheduleID===r.ScheduleID;
            }
            ))schedules.push( {
                ScheduleID:r.ScheduleID,name:r.ScheduleName,order:r.ScheduleOrder
            }
            );
        }
        );schedules.sort(function(a,b) {
            return a.order-b.order;
        }
        );
        activeSchedule=schedules.length?schedules[0].ScheduleID:null;activeMap=maps.length?maps[0].MapID:null;
        isEditable=!data.workflow||data.workflow==='DRAFT';
        function status(l) {
            return statuses[key(activeSchedule,l)]|| {
                status:'',notes:''
            }
            ;
        }
        function color(l) {
            var s=status(l).status;return s==='ON'?'#16834a':s==='OFF'?'#c83f3f':'#9caab7';
        }
        function button(label,active,fn) {
            var b=document.createElement('button');b.type='button';b.className='li-btn'+(active?' active':'');b.textContent=label;b.onclick=fn;return b;
        }
        function tabs() {
            var el=byId('liSchedules');el.innerHTML='';schedules.forEach(function(s) {
                el.appendChild(button(s.name,s.ScheduleID===activeSchedule,function() {
                    activeSchedule=s.ScheduleID;render();
                }
                ));
            }
            );var m=byId('liMaps');m.innerHTML='';maps.forEach(function(x) {
                m.appendChild(button(x.MapName,x.MapID===activeMap,function() {
                    activeMap=x.MapID;zoom=1;panX=0;panY=0;render();
                }
                ));
            }
            );
        }
        // LI-01: only rows of the active schedule, including unsaved local changes.
        function missingRows() {
            return rows.filter(function(r) {
                if (String(r.ScheduleID)!==String(activeSchedule)) return false;
                var v=(statuses[key(r.ScheduleID,r.LightID)]||{}).status||'';
                return v!=='ON' && v!=='OFF';
            });
        }
        function mappedLocations(lightId) {
            var result=[],seen={};
            paths.forEach(function(p) {
                if (String(p.LightID)!==String(lightId)) return;
                var m=maps.filter(function(x){return String(x.MapID)===String(p.MapID);})[0];
                if (!m || seen[String(m.MapID)]) return;
                seen[String(m.MapID)]=true;result.push(m);
            });
            return result;
        }
        function closeMissing() {
            var d=byId('liMissingBackdrop');d.classList.remove('li-open');d.setAttribute('aria-hidden','true');
        }
        function openMissing() {
            var missing=missingRows(),container=byId('liMissingContent');container.innerHTML='';
            var currentSchedule=schedules.filter(function(x){return String(x.ScheduleID)===String(activeSchedule);})[0];
            byId('liMissingCaption').textContent=(currentSchedule?currentSchedule.name:'Jadwal')+' · '+missing.length+' lampu belum diperiksa';
            if (!missing.length) {container.textContent='Semua lampu pada jadwal ini sudah diperiksa.';}
            else {
                var table=document.createElement('table');table.className='li-missing-table';
                var head=document.createElement('thead'),tr=document.createElement('tr');
                ['Map','Kode Lampu','Nama Lampu','Lokasi'].forEach(function(t){var th=document.createElement('th');th.textContent=t;tr.appendChild(th);});
                head.appendChild(tr);table.appendChild(head);
                var body=document.createElement('tbody');
                missing.forEach(function(r){
                    var locations=mappedLocations(r.LightID),row=document.createElement('tr');
                    var cell=document.createElement('td');cell.textContent=locations.length?locations.map(function(m){return m.MapName||m.MapCode;}).join(', '):'Belum ada mapping SVG';row.appendChild(cell);
                    cell=document.createElement('td');cell.textContent=r.LightCode||String(r.LightID);row.appendChild(cell);
                    cell=document.createElement('td');cell.textContent=r.LightName||'-';row.appendChild(cell);
                    cell=document.createElement('td');
                    if (locations.length) {
                        var btn=document.createElement('button');btn.type='button';btn.className='li-btn';btn.textContent='Lihat di Map';
                        btn.onclick=function(){
                            closeMissing();activeMap=locations[0].MapID;selectedLight=r.LightID;
                            zoom=1;panX=0;panY=0;render();
                            focusLightOnMap(r.LightID);
                            var canvas=byId('liMapCanvas');if(canvas&&canvas.scrollIntoView)canvas.scrollIntoView({block:'center',behavior:'smooth'});
                        };cell.appendChild(btn);
                    } else cell.textContent='Tidak tersedia';
                    row.appendChild(cell);body.appendChild(row);
                });table.appendChild(body);container.appendChild(table);
            }
            var d=byId('liMissingBackdrop');d.classList.add('li-open');d.setAttribute('aria-hidden','false');byId('liMissingClose').focus();
        }
        byId('liMissingClose').onclick=closeMissing;
        byId('liMissingBackdrop').onclick=function(e){if(e.target===this)closeMissing();};
        document.addEventListener('keydown',function(e){if(e.key==='Escape'&&byId('liMissingBackdrop').classList.contains('li-open'))closeMissing();});
        function stats() {
            var selected=rows.filter(function(r){return String(r.ScheduleID)===String(activeSchedule);});
            var on=0,off=0;selected.forEach(function(r){var v=(statuses[key(r.ScheduleID,r.LightID)]||{}).status||'';if(v==='ON')on++;else if(v==='OFF')off++;});
            var el=byId('liStats');el.innerHTML='';
            function metric(label,value,kind){
                var item=document.createElement('span');item.className='li-kpi-item'+(kind?' li-kpi-'+kind:'');
                var caption=document.createElement('span');caption.className='li-kpi-label';caption.textContent=label;
                var number=document.createElement('strong');number.className='li-kpi-value';number.textContent=value;
                item.appendChild(caption);item.appendChild(number);el.appendChild(item);
            }
            metric('Total',selected.length,'total');metric('ON',on,'on');metric('OFF',off,'off');
            var btn=document.createElement('button');btn.type='button';btn.className='li-missing-trigger';
            btn.setAttribute('aria-label','Lihat '+(selected.length-on-off)+' lampu belum diperiksa');
            var missingLabel=document.createElement('span');missingLabel.className='li-kpi-label';missingLabel.textContent='Belum diperiksa';
            var missingNumber=document.createElement('strong');missingNumber.className='li-kpi-value';missingNumber.textContent=selected.length-on-off;
            var arrow=document.createElement('span');arrow.className='li-kpi-arrow';arrow.textContent='';arrow.setAttribute('aria-hidden','true');
            btn.appendChild(missingLabel);btn.appendChild(missingNumber);btn.appendChild(arrow);
            btn.onclick=openMissing;el.appendChild(btn);
            var dirtyLabel=document.createElement('span');dirtyLabel.className='li-dirty li-kpi-dirty';
            dirtyLabel.textContent=Object.keys(dirty).length+' perubahan belum disimpan';el.appendChild(dirtyLabel);
            byId('liWorkflow').textContent=data.workflow||'NOT CREATED';byId('liSave').disabled=!isEditable||!Object.keys(dirty).length;
        }
        function approvalText(v) {
            return v == null || v === '' ? '-' : String(v);
        }
        function approvalDate(value) {
            if (!value) return '-';
            var match = String(value).match(/^\/Date\((-?\d+)(?:[+-]\d{4})?\)\/$/);
            var date = match ? new Date(parseInt(match[1], 10)) : new Date(value);
            if (isNaN(date.getTime())) return '-';
            var months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
            return ('0' + date.getDate()).slice(-2) + '-' +
                   months[date.getMonth()] + '-' + date.getFullYear();
        }
        function renderApproval() {
            var panel=byId('liApprovalSteps'), caption=byId('liApprovalCaption');
            panel.innerHTML='';
            var steps=[
                {label:'Checked By',flag:'IsApproval1',user:'UserApprove1',date:'DateApprove1'},
                {label:'Verified By',flag:'IsApproval2',user:'UserApprove2',date:'DateApprove2'},
                {label:'Acknowledged By 1',flag:'IsApproval3',user:'UserApprove3',date:'DateApprove3'},
                {label:'Acknowledged By 2',flag:'IsApproval4',user:'UserApprove4',date:'DateApprove4'}
            ];
            var ap=data.approval;
            if (!ap) {
                caption.textContent=data.workflow ?
                    'Data detail approval belum tersedia dari header checklist.' :
                    'Inspeksi belum dibuat. Belum ada approval.';
            } else {
                caption.textContent='Workflow: '+(data.workflow||'NOT CREATED')+' · Read-only';
            }
            steps.forEach(function(s){
                var available=ap && Object.prototype.hasOwnProperty.call(ap,s.flag);
                var done=available && (ap[s.flag]===true || ap[s.flag]===1 || ap[s.flag]==='1');
                var card=document.createElement('div');
                card.className='li-approval-step '+(done?'is-done':'is-pending');
                var label=document.createElement('div');label.className='li-approval-label';label.textContent=s.label;
                var state=document.createElement('div');state.className='li-approval-state';
                state.textContent=!available?'Data belum tersedia':(done?'Disetujui':'Menunggu persetujuan');
                var user=document.createElement('div');user.className='li-approval-user';
                user.textContent=done?approvalText(ap[s.user]):'-';
                var date=document.createElement('div');date.className='li-approval-date';
                date.textContent=done?approvalDate(ap[s.date]):'-';
                card.appendChild(label);card.appendChild(state);card.appendChild(user);card.appendChild(date);
                panel.appendChild(card);
            });
        }
        // Only a preview of the next action. Actual permission and checklist
        // completeness MUST be checked again by the server and SQL procedure.
        function renderApprovalAction() {
            var action = byId('liApprovalAction');
            var hint = byId('liApprovalActionHint');
            var workflow = data.workflow || 'NOT CREATED';
            var names = {
                DRAFT: 'Selesaikan Inspeksi',
                CHECKED: 'Verify Inspection',
                VERIFIED: 'Acknowledged By 1',
                ACKNOWLEDGED_1: 'Acknowledged By 2'
            };
            var next = names[workflow];
            action.style.display = next ? '' : 'none';
            if (!next) {
                hint.textContent = workflow === 'ACKNOWLEDGED'
                    ? 'Inspeksi sudah final.'
                    : 'Simpan inspeksi terlebih dahulu.';
                return;
            }
            action.textContent = next;
            var total = rows.length, complete = 0;
            rows.forEach(function (r) {
                var v = statuses[key(r.ScheduleID, r.LightID)];
                if (v && (v.status === 'ON' || v.status === 'OFF')) complete++;
            });
            var unsaved = Object.keys(dirty).length;
            var ready = workflow !== 'DRAFT' || (total > 0 && complete === total);
            action.disabled = !ready || unsaved > 0 || !data.inspectionID ||
                !data.rowVer ||
                byId('liDate').value !== '<%= Server.HtmlEncode(SelectedDateIso) %>';
            hint.textContent = workflow === 'DRAFT'
                ? ('Checklist ' + complete + '/' + total +
                   (unsaved ? ' · Simpan ' + unsaved + ' perubahan terlebih dahulu' : '') +
                   (ready ? ' · Siap diselesaikan' : ' · Belum lengkap'))
                : 'Tahap berikutnya: ' + next;
        }
        function closeApprovalConfirm(){
            var b=byId('liApprovalConfirmBackdrop');b.classList.remove('li-open');b.setAttribute('aria-hidden','true');
        }
        byId('liApprovalAction').onclick=function(){
            if(this.disabled)return;
            byId('liApprovalConfirmText').textContent='Lanjutkan tahap "'+this.textContent+'" untuk inspeksi '+byId('liDate').value+'?';
            var b=byId('liApprovalConfirmBackdrop');b.classList.add('li-open');b.setAttribute('aria-hidden','false');
            byId('liApprovalCancel').focus();
        };
        byId('liApprovalConfirm').onclick = function () {
            if (!validateLightingDate()) { closeApprovalConfirm(); return; }
            var workflow = data.workflow || 'NOT CREATED';

            var validWorkflow =
                workflow === 'DRAFT' ||
                workflow === 'CHECKED' ||
                workflow === 'VERIFIED' ||
                workflow === 'ACKNOWLEDGED_1';

            if (!validWorkflow ||
                !data.inspectionID ||
                !data.rowVer ||
                Object.keys(dirty).length > 0 ||
                byId('liDate').value !== '<%= Server.HtmlEncode(SelectedDateIso) %>') {

                closeApprovalConfirm();
                msg('Data inspeksi berubah. Simpan atau Load Date dahulu.', true);
                return;
            }

            if (workflow === 'DRAFT') {
                var complete = 0;

                rows.forEach(function (r) {
                    var v = statuses[key(r.ScheduleID, r.LightID)];
                    if (v && (v.status === 'ON' || v.status === 'OFF'))
                        complete++;
                });

                if (rows.length === 0 || complete !== rows.length) {
                    closeApprovalConfirm();
                    msg('Checklist belum lengkap.', true);
                    return;
                }
            }

            this.disabled = true;

            byId('<%= hfApprovalRowVer.ClientID %>').value = data.rowVer;
            byId('<%= hfLightingDate.ClientID %>').value = byId('liDate').value;

            byId('<%= btnLightingApprove.ClientID %>').click();
        };
        byId('liApprovalCancel').onclick=closeApprovalConfirm;
        byId('liApprovalConfirmBackdrop').onclick=function(e){if(e.target===this)closeApprovalConfirm();};
        document.addEventListener('keydown',function(e){if(e.key==='Escape')closeApprovalConfirm();});
        function update(s,l,v,n) {
            if(!isEditable)return;var k=key(s,l);statuses[k]= {
                status:v,notes:n
            }
            ;var original=rows.filter(function(r) {
                return r.ScheduleID===s&&r.LightID===l;
            }
            )[0];if(original&&original.LightStatus===v&&(original.Notes||'')===n)delete dirty[k];else dirty[k]= {
                ScheduleID:s,LightID:l,LightStatus:v,Notes:n
            }
            ;render();
        }
        function choose(l) {
            selectedLight=l;render();var item=byId('liRow'+l);if(item)item.scrollIntoView( {
                block:'nearest',behavior:'smooth'
            }
            );
        }
        function list() {
            var el=byId('liChecklist');el.innerHTML='';byId('liListCaption').textContent='Pilih ON/OFF atau tambahkan catatan untuk setiap lampu.';areas.forEach(function(a) {
                var rs=rows.filter(function(r) {
                    return r.ScheduleID===activeSchedule&&r.AreaID===a.AreaID;
                }
                );if(!rs.length)return;var sec=document.createElement('section');sec.className='li-area';var h=document.createElement('h4');h.textContent=a.AreaName+' ('+rs.length+')';sec.appendChild(h);rs.forEach(function(r) {
                    var st=status(r.LightID),div=document.createElement('div');div.className='li-item'+(selectedLight===r.LightID?' selected':'');div.id='liRow'+r.LightID;var title=document.createElement('div');title.textContent=r.LightCode+' — '+r.LightName;title.style.cursor='pointer';title.onclick=function() {
                        selectedLight=r.LightID;renderMap();list();
                    }
                    ;div.appendChild(title);var controls=document.createElement('div');controls.className='li-status';['ON','OFF'].forEach(function(v) {
                        var b=document.createElement('button');b.type='button';b.className=v.toLowerCase()+(st.status===v?' active':'');b.textContent=v;b.disabled=!isEditable;b.onclick=function() {
                            selectedLight=r.LightID;update(activeSchedule,r.LightID,st.status===v?'':v,st.notes);
                        }
                        ;controls.appendChild(b);
                    }
                    );div.appendChild(controls);var note=document.createElement('input');note.className='li-notes';note.type='text';note.maxLength=2000;note.placeholder='Catatan (opsional)';note.value=st.notes;note.disabled=!isEditable;note.onchange=function() {
                        update(activeSchedule,r.LightID,status(r.LightID).status,note.value);
                    }
                    ;div.appendChild(note);sec.appendChild(div);
                }
                );el.appendChild(sec);
            }
            );
        }
        function applyMapTransform() {
            if (!svgNode) return;
            svgNode.style.transform='translate('+panX+'px,'+panY+'px) scale('+zoom+')';
            svgNode.style.transformOrigin='center center';
            var map=maps.filter(function(m){return m.MapID===activeMap;})[0];
            if(map)byId('liMapCaption').textContent=map.MapCode+' · '+Math.round(zoom*100)+'%';
        }
        function boundPan() {
            if(zoom<=1){panX=0;panY=0;return;}
            var canvas=byId('liMapCanvas');
            if(!svgNode)return;
            var r=svgNode.getBoundingClientRect();
            // Approximate untransformed dimensions from transformed SVG size.
            var w=r.width/zoom,h=r.height/zoom;
            var cw=canvas.clientWidth,ch=canvas.clientHeight;
            var maxX=Math.max(0,(w*zoom-cw)/2)+Math.min(45,cw*.1);
            var maxY=Math.max(0,(h*zoom-ch)/2)+Math.min(45,ch*.1);
            panX=Math.max(-maxX,Math.min(maxX,panX));
            panY=Math.max(-maxY,Math.min(maxY,panY));
        }
        function setZoom(next) {
            zoom=Math.max(1,Math.min(4,next));
            if(zoom===1){panX=0;panY=0;}
            boundPan();applyMapTransform();
        }
        function attachMapGestures(svg) {
            var canvas=byId('liMapCanvas'),points={};
            function pointCount(){return Object.keys(points).length;}
            function pair(){var ids=Object.keys(points);return ids.length>=2?[points[ids[0]],points[ids[1]]]:null;}
            function dist(p){return Math.sqrt(Math.pow(p[0].x-p[1].x,2)+Math.pow(p[0].y-p[1].y,2));}
            svg.addEventListener('pointerdown',function(e){
                if(e.button!==undefined && e.button!==0)return;
                if(pointCount()===0)suppressClick=false;
                points[e.pointerId]={x:e.clientX,y:e.clientY};
                // Touch tetap capture untuk pan/pinch. Mouse capture hanya setelah drag.
                // Capture langsung pada mouse membuat click tidak sampai ke PATH/CIRCLE.
                if(e.pointerType !== 'mouse') {
                    try{svg.setPointerCapture(e.pointerId);}catch(ex){}
                }
                if(pointCount()===1)gesture={x:e.clientX,y:e.clientY,lastX:e.clientX,lastY:e.clientY,moved:false};
                else if(pointCount()===2){gesture={pinch:true,distance:dist(pair()),startZoom:zoom,moved:true};suppressClick=true;}
            });
            svg.addEventListener('pointermove',function(e){
                if(!points[e.pointerId])return;
                points[e.pointerId]={x:e.clientX,y:e.clientY};
                if(!gesture)return;
                if(pointCount()>=2){
                    var p=pair();if(p&&gesture.pinch){setZoom(gesture.startZoom*dist(p)/Math.max(1,gesture.distance));}
                    return;
                }
                if(gesture.pinch)return;
                if(!gesture.moved && Math.hypot(e.clientX-gesture.x,e.clientY-gesture.y)>6) {
                    gesture.moved=true;
                    if(e.pointerType === 'mouse') {
                        try{svg.setPointerCapture(e.pointerId);}catch(ex){}
                    }
                }
                if(gesture.moved){
                    suppressClick=true;canvas.classList.add('li-dragging');
                    panX+=e.clientX-gesture.lastX;panY+=e.clientY-gesture.lastY;
                    boundPan();applyMapTransform();
                }
                gesture.lastX=e.clientX;gesture.lastY=e.clientY;
            });
            function finish(e){
                if(!points[e.pointerId])return;
                delete points[e.pointerId];
                if(gesture&&gesture.moved)suppressClick=true;
                canvas.classList.remove('li-dragging');
                if(pointCount()===0)gesture=null;
                else gesture={pinch:true,moved:true};
            }
            svg.addEventListener('pointerup',finish);
            svg.addEventListener('pointercancel',finish);
            svg.addEventListener('lostpointercapture',finish);
            svg.addEventListener('click',function(e){
                if(suppressClick){e.preventDefault();e.stopPropagation();suppressClick=false;}
            },true);
            canvas.onwheel=function(e){
                e.preventDefault();setZoom(zoom+(e.deltaY<0?.15:-.15));
            };
        }
        function renderMap() {
            var map=maps.filter(function(m) {
                return m.MapID===activeMap;
            }
            )[0],el=byId('liMapCanvas');el.innerHTML='';if(!map) {
                el.textContent='Denah tidak tersedia';return;
            }
            byId('liMapCaption').textContent=map.MapCode+' · '+Math.round(zoom*100)+'%';var ns='http://www.w3.org/2000/svg';var svg=document.createElementNS(ns,'svg');svg.setAttribute('viewBox',[map.ViewBoxX,map.ViewBoxY,map.ViewBoxWidth,map.ViewBoxHeight].join(' '));svg.setAttribute('role','img');svg.setAttribute('aria-label',map.MapName);var bg=document.createElementNS(ns,'rect');bg.setAttribute('x',map.ViewBoxX);bg.setAttribute('y',map.ViewBoxY);bg.setAttribute('width',map.ViewBoxWidth);bg.setAttribute('height',map.ViewBoxHeight);bg.setAttribute('fill','#e9eff3');svg.appendChild(bg);
            if (map.ImagePath) {
                var image = document.createElementNS(
                    'http://www.w3.org/2000/svg',
                    'image'
                );

                image.setAttribute('href', map.ImagePath);

                image.setAttribute('x', map.ViewBoxX);
                image.setAttribute('y', map.ViewBoxY);
                image.setAttribute('width', map.ViewBoxWidth);
                image.setAttribute('height', map.ViewBoxHeight);
                image.setAttribute('preserveAspectRatio', 'none');

                svg.appendChild(image);
            }
            var these=paths.filter(function(p) {
                return p.MapID===activeMap;
            }
            ).sort(function(a,b) {
                var aa=a.ShapeType==='PATH'?0:1,bb=b.ShapeType==='PATH'?0:1;return aa-bb||a.DisplayOrder-b.DisplayOrder;
            }
            );these.forEach(function(p) {
                if(p.ShapeType!=='PATH'&&p.ShapeType!=='CIRCLE')return;var shape=document.createElementNS(ns,p.ShapeType==='PATH'?'path':'circle');shape.setAttribute('class','li-shape');shape.setAttribute('data-light-id',p.LightID);shape.setAttribute('stroke',color(p.LightID));shape.setAttribute('stroke-width',p.StrokeWidth||2);shape.setAttribute('fill',p.ShapeType==='PATH'?'none':color(p.LightID));if(p.ShapeType==='PATH') {
                    shape.setAttribute('d',p.SvgPathData||'');shape.setAttribute('stroke-linecap','round');shape.setAttribute('stroke-linejoin','round');
                }
                else {
                    var at= {
                    }
                    ;try {
                        at=JSON.parse(p.ShapeAttributes||'{}');
                    }
                    catch(e) {
                    }
                    ;['cx','cy','r'].forEach(function(k) {
                        if(typeof at[k]==='number')shape.setAttribute(k,at[k]);
                    }
                    );shape.setAttribute('stroke','#ffffff');shape.setAttribute('stroke-width',selectedLight===p.LightID?'3':'1.5');
                }
                shape.setAttribute('tabindex','0');shape.setAttribute('role','button');shape.setAttribute('aria-label','Lampu '+p.LightID+' '+(status(p.LightID).status||'belum diperiksa'));shape.onclick=function() {
                    openInspectionDialog(p.LightID);
                }
                ;shape.onkeydown=function(e) {
                    if(e.key==='Enter'||e.key===' ') {
                        e.preventDefault();openInspectionDialog(p.LightID);
                    }
                }
                ;svg.appendChild(shape);
            }
            );el.appendChild(svg);svgNode=svg;applyMapTransform();attachMapGestures(svg);
        }

        // LI-01: focus on the lamp marker, not the bounding box of a long SVG path.
        // Optional exact coordinates: { "MapCode|LightCode": {x: ..., y: ...} }.
        // Populate only after checking the map editor; never guess physical positions.
        var liFocusOverrides = {};
        function focusLightOnMap(lightId) {
            var canvas=byId('liMapCanvas');
            if(!svgNode||!canvas)return;
            var shapes=svgNode.querySelectorAll('.li-shape[data-light-id="'+String(lightId)+'"]');
            if(!shapes.length)return;
            var currentMap=maps.filter(function(m){return String(m.MapID)===String(activeMap);})[0];
            var currentRow=rows.filter(function(r){return String(r.LightID)===String(lightId) && String(r.ScheduleID)===String(activeSchedule);})[0];
            var overrideKey=(currentMap?(currentMap.MapCode||currentMap.MapID):'')+'|'+(currentRow?(currentRow.LightCode||lightId):lightId);
            var target=liFocusOverrides[overrideKey]||null;
            var i,shape,box,candidate,score,best=null,bestScore=-1;
            for(i=0;i<shapes.length;i++){
                shape=shapes[i];shape.classList.add('li-target-shape');
                candidate=null;score=0;
                if(shape.tagName.toLowerCase()==='circle'){
                    var x=parseFloat(shape.getAttribute('cx')),y=parseFloat(shape.getAttribute('cy'));
                    if(isFinite(x)&&isFinite(y)){candidate={x:x,y:y};score=100000;}
                }else if(typeof shape.getTotalLength==='function'){
                    try{
                        var length=shape.getTotalLength();
                        if(length>0){var pt=shape.getPointAtLength(length/2);candidate={x:pt.x,y:pt.y};score=1000/(1+length);}
                    }catch(ex){}
                }
                if(!candidate){
                    try{box=shape.getBBox();candidate={x:box.x+box.width/2,y:box.y+box.height/2};score=0.01;}catch(ex){}
                }
                if(candidate && score>bestScore){best=candidate;bestScore=score;}
            }
            if(!target)target=best;
            if(!target||!isFinite(target.x)||!isFinite(target.y))return;
            var cx=target.x,cy=target.y,ns='http://www.w3.org/2000/svg';
            // A fixed-size screen-space locator; no huge ring for long paths.
            var ring=document.createElementNS(ns,'circle');
            ring.setAttribute('cx',cx);ring.setAttribute('cy',cy);ring.setAttribute('r','10');
            ring.setAttribute('class','li-focus-ring');svgNode.appendChild(ring);
            var dot=document.createElementNS(ns,'circle');
            dot.setAttribute('cx',cx);dot.setAttribute('cy',cy);dot.setAttribute('r','2.5');
            dot.setAttribute('class','li-focus-dot');svgNode.appendChild(dot);
            zoom=2.25;panX=0;panY=0;applyMapTransform();
            // Recalculate actual screen coordinates, including preserveAspectRatio.
            function screenPoint(){
                try{var p=svgNode.createSVGPoint();p.x=cx;p.y=cy;return p.matrixTransform(svgNode.getScreenCTM());}
                catch(ex){return null;}
            }
            for(var attempt=0;attempt<3;attempt++){
                var point=screenPoint();if(!point)break;
                var rect=canvas.getBoundingClientRect();
                var dx=rect.left+rect.width/2-point.x,dy=rect.top+rect.height/2-point.y;
                if(Math.abs(dx)<0.5&&Math.abs(dy)<0.5)break;
                panX+=dx;panY+=dy;applyMapTransform();
            }
        }

        function closeInspectionDialog(){
            var back=byId('liDialogBackdrop');back.classList.remove('li-open');back.setAttribute('aria-hidden','true');dialogLight=null;
        }
        function dialogButtons(){
            var buttons=byId('liDialogOptions').querySelectorAll('button');
            for(var i=0;i<buttons.length;i++){
                var v=buttons[i].getAttribute('data-value');
                buttons[i].className=(v===dialogStatus?(v==='ON'?'li-on':v==='OFF'?'li-off':'li-clear'):'');
                buttons[i].disabled=!isEditable;
            }
        }
        function openInspectionDialog(lightId){
            selectedLight=lightId;
            var row=rows.filter(function(r){return r.ScheduleID===activeSchedule&&r.LightID===lightId;})[0];
            if(!row){choose(lightId);return;}
            dialogLight=lightId;dialogStatus=status(lightId).status;
            byId('liDialogTitle').textContent=row.LightCode+' — '+row.LightName;
            byId('liDialogSubtitle').textContent=(data.workflow||'NOT CREATED')+' · '+(isEditable?'Belum disimpan sampai Save Changes':'Read-only');
            byId('liDialogNotes').value=status(lightId).notes;
            var gallery=byId('liPhotoGallery');
            gallery.innerHTML='';
            var photos=(data.inspectionPhotos||[]).filter(function(p){
                return String(p.ObjectID)===String(lightId)&&
                    String(p.ScheduleID)===String(activeSchedule);
            });
            if(!photos.length){
                var empty=document.createElement('span');
                empty.className='li-dialog-sub';empty.textContent='Belum ada foto pada tanggal inspeksi ini.';
                gallery.appendChild(empty);
            }
            photos.forEach(function(p){
                var link=document.createElement('a');
                link.href=window.location.pathname+'?inspecPhoto='+encodeURIComponent(p.PhotoID)+
                    '&photoDate=<%= SelectedDateIso %>';
                link.target='_blank';link.rel='noopener noreferrer';
                link.title='Lihat foto '+p.PhotoType;
                var image=document.createElement('img');image.src=link.href;
                image.alt='Foto '+p.PhotoType;
                image.style.cssText='width:84px;height:84px;object-fit:cover;border-radius:6px;border:1px solid #cad6e1';
                link.appendChild(image);gallery.appendChild(link);
            });
        byId('<%= fuLightingPhoto.ClientID %>').value='';
            byId('liDialogNotes').disabled=!isEditable;
            byId('<%= fuLightingPhoto.ClientID %>').disabled=!isEditable;
            byId('liDialogApply').disabled=!isEditable;
            dialogButtons();
            var back=byId('liDialogBackdrop');back.classList.add('li-open');back.setAttribute('aria-hidden','false');
            byId('liDialogCancel').focus();
        }
        byId('liDialogOptions').onclick=function(e){
            var b=e.target.closest?e.target.closest('button'):e.target;
            if(!b||!isEditable)return;
            dialogStatus=b.getAttribute('data-value');dialogButtons();
        };
        byId('liDialogCancel').onclick=closeInspectionDialog;
        byId('liDialogBackdrop').onclick=function(e){if(e.target===this)closeInspectionDialog();};
        byId('liDialogApply').onclick=function(){
            if(dialogLight===null){alert('Lampu belum dipilih.');return;}
            if(!isEditable){alert('Inspeksi sudah dikunci.');return;}
            var l=dialogLight,n=byId('liDialogNotes').value;
            var photoInput=byId('<%= fuLightingPhoto.ClientID %>');
            var hasFile=!!(photoInput.files&&photoInput.files.length);
            if(dialogStatus==='OFF'||(dialogStatus==='ON'&&hasFile)){
                if(!validateLightingDate()){
                    alert('Tanggal inspeksi tidak valid. Klik Load Date terlebih dahulu.');
                    return;
                }
                if(hasFile&&photoInput.files[0].size>5242880){alert('Ukuran foto maksimal 5 MB.');return;}
                var activeId=activeSchedule;
                update(activeId,l,dialogStatus,n);
                var changes=Object.keys(dirty).map(function(k){return dirty[k];})
                    .filter(function(x){return x.LightStatus==='ON'||x.LightStatus==='OFF';});
                if(!changes.some(function(x){return x.ScheduleID===activeId&&x.LightID===l;}))
                    changes.push({ScheduleID:activeId,LightID:l,LightStatus:dialogStatus,Notes:n});
                byId('<%= hfLightingPayload.ClientID %>').value=JSON.stringify(changes);
                byId('<%= hfLightingPhotoLight.ClientID %>').value=l;
                byId('<%= hfLightingPhotoSchedule.ClientID %>').value=activeId;
                byId('<%= hfLightingDate.ClientID %>').value=byId('liDate').value;
                var applyButton=byId('liDialogApply');
                applyButton.disabled=true;
                applyButton.textContent='Menyimpan...';
                try{
                    if(typeof window.__doPostBack!=='function')
                        throw new Error('Fungsi postback ASP.NET belum tersedia. Refresh halaman.');
                    window.__doPostBack('<%= btnLightingApplyWithPhoto.UniqueID %>','');
                }catch(ex){
                    applyButton.disabled=false;
                    applyButton.textContent='Terapkan';
                    alert('Gagal mengirim inspeksi: '+ex.message);
                }
                return;
            }
            closeInspectionDialog();update(activeSchedule,l,dialogStatus,n);
        };
        document.addEventListener('keydown',function(e){if(e.key==='Escape'&&dialogLight!==null)closeInspectionDialog();});
        function render() {
            tabs();stats();renderMap();list();renderApproval();renderApprovalAction();
        }
        function msg(s,error) {
            byId('liMessage').innerHTML='<div class="li-msg '+(error?'li-error':'li-warning')+'">'+esc(s)+'</div>';
        }
        function getTodayLocalIso() {
            var now = new Date();
            return now.getFullYear() + '-' +
                ('0' + (now.getMonth() + 1)).slice(-2) + '-' +
                ('0' + now.getDate()).slice(-2);
        }
        function initializeLightingDateLimit() {
            var dateInput = byId('liDate');
            if (!dateInput) return;
            var today = getTodayLocalIso();
            dateInput.setAttribute('max', today);
            // Do not silently replace the date of the inspection already loaded.
            if (dateInput.value && dateInput.value > today) {
                byId('liLoad').disabled = true;
                msg('Tanggal inspeksi tidak boleh melebihi hari ini.', true);
            }
        }
        function validateLightingDate() {
            var dateInput = byId('liDate');
            var selected = dateInput.value;
            var today = getTodayLocalIso();
            dateInput.setAttribute('max', today);
            if (!/^\d{4}-\d{2}-\d{2}$/.test(selected) ||
                selected > today || !dateInput.checkValidity()) {
                msg('Pilih tanggal inspeksi yang valid dan tidak melebihi hari ini.', true);
                return false;
            }
            return true;
        }
        byId('liDate').addEventListener('change', function () {
            var valid = validateLightingDate();
            byId('liLoad').disabled = !valid;
            renderApprovalAction();
        });
        initializeLightingDateLimit();
        byId('liSave').onclick=function() {
            if(!isEditable||!Object.keys(dirty).length)return;
            if(!validateLightingDate())return;
            var values=Object.keys(dirty).map(function(k) {
                return dirty[k];
            }
            ).filter(function(x) {
                return x.LightStatus==='ON'||x.LightStatus==='OFF';
            }
            );if(!values.length) {
                msg('Tidak ada perubahan ON/OFF yang bisa disimpan. Catatan hanya bisa disimpan bersama status ON/OFF.',true);return;
            }
            var notesOnly=Object.keys(dirty).some(function(k) {
                var x=dirty[k];return x.LightStatus!== 'ON'&&x.LightStatus!=='OFF';
            }
            );if(notesOnly) {
                msg('Masih ada catatan pada lampu yang belum dipilih ON/OFF.',true);return;
            }
            byId('<%= hfLightingPayload.ClientID %>').value=JSON.stringify(values);byId('<%= hfLightingDate.ClientID %>').value=byId('liDate').value;byId('<%= btnLightingSave.ClientID %>').click();
        }
        ;
        byId('liLoad').onclick=function() {
            if(!validateLightingDate())return;
            if(Object.keys(dirty).length&&!confirm('Perubahan belum disimpan akan hilang. Lanjutkan?'))return;byId('<%= hfLightingDate.ClientID %>').value=byId('liDate').value;byId('<%= btnLightingLoad.ClientID %>').click();
        }
        ;
        byId('liZoomIn').onclick=function() {
            setZoom(zoom+.25);
        }
        ;byId('liZoomOut').onclick=function() {
            setZoom(zoom-.25);
        }
        ;byId('liResetZoom').onclick=function() {
            setZoom(1);
        }
        ;
        render();

        if (data.mapWarning) {
            msg(data.mapWarning, false);
        }
    }
)();
</script>
</asp:Content>

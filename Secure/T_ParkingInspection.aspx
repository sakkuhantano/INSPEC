<%@ Page Language="C#" MasterPageFile="~/MasterPages/Site1.Master" AutoEventWireup="true" CodeBehind="T_ParkingInspection.aspx.cs" Inherits="INSPEC.Secure.T_ParkingInspection" %>
<%@ MasterType VirtualPath="~/MasterPages/Site1.Master" %>
<asp:Content ID="headParking" ContentPlaceHolderID="head" runat="server">
<style>
.pi{font:13px Arial,sans-serif;color:#243b50;background:#f5f7fa;padding:14px}.pi *{box-sizing:border-box}.pi-card{background:#fff;border:1px solid #dbe3eb;border-radius:8px;padding:15px;margin-bottom:12px}.pi h2{font-size:20px;margin:0}.pi .muted{color:#687d90}.pi button,.pi input,.pi select,.pi textarea{font:inherit;padding:8px;border:1px solid #cad6e1;border-radius:5px}.pi button{cursor:pointer;background:#fff}.pi button.primary{background:#137e9e;color:white;border-color:#137e9e}.pi button:disabled{opacity:.5;cursor:not-allowed}.pi .toolbar{display:flex;flex-wrap:wrap;gap:10px;align-items:end}.pi label{display:block;font-size:12px;font-weight:bold;margin:6px 0}.pi .layout{display:grid;grid-template-columns:minmax(0,1.3fr) minmax(320px,1fr);gap:12px}.pi .map{height:460px;overflow:auto;background:#edf2f6;border:1px solid #dce4ec;display:flex;align-items:center;justify-content:center}.pi svg{width:100%;max-height:100%;touch-action:none;user-select:none}.pi .map{overflow:hidden;touch-action:none;user-select:none;cursor:grab}.pi .map.pi-dragging{cursor:grabbing}.pi .slot{cursor:pointer;stroke-width:2}.pi .slot:hover{stroke:#0b5c9d;stroke-width:4}.pi .field{margin-bottom:10px}.pi .field input,.pi .field select,.pi .field textarea{width:100%}.pi .list{max-height:520px;overflow:auto;border:1px solid #e3eaf0}.pi .item{display:flex;justify-content:space-between;padding:8px 10px;border-bottom:1px solid #e9edf1;cursor:pointer}.pi .item.active{background:#e5f4fa}.pi .stats{display:flex;gap:16px;flex-wrap:wrap}.pi .stats strong{font-size:18px}.pi .pill{background:#eaf0f5;border-radius:10px;padding:4px 8px}.pi .hidden{display:none}@media(max-width:900px){.pi .layout{grid-template-columns:1fr}.pi .map{height:340px}.pi{padding:6px}}

.pi-dialog-backdrop{position:fixed;inset:0;z-index:2147483000;background:rgba(15,23,42,.62);display:none;align-items:center;justify-content:center;padding:14px}
.pi-dialog-backdrop.pi-open{display:flex}
.pi-dialog{width:100%;max-width:470px;max-height:calc(100vh - 28px);overflow:auto;background:#fff;border-radius:12px;padding:20px;box-shadow:0 20px 60px rgba(0,0,0,.25)}
.pi-dialog h3{margin:0 0 5px;font-size:19px}.pi-dialog .pi-actions{display:flex;justify-content:flex-end;gap:8px;margin-top:14px}
.pi-dialog .pi-actions button{min-height:42px}.pi .map svg .slot:focus{outline:none;stroke:#2563eb;stroke-width:5}
@media(max-width:600px){.pi-dialog-backdrop{align-items:flex-end;padding:0}.pi-dialog{max-width:none;max-height:90vh;border-radius:16px 16px 0 0;padding-bottom:calc(18px + env(safe-area-inset-bottom))}}
.pi #piPlate,.pi #piJenis{text-transform:uppercase}
.pi .map svg{transform-origin:center center}
.pi .map,.pi .map svg{touch-action:none;-webkit-user-select:none;user-select:none}
.pi-approval-grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px;margin:12px 0}
.pi-approval-step{border:1px solid #dbe3eb;border-radius:7px;padding:12px;min-width:0;background:#f8fafc}
.pi-approval-step.done{background:#f3fbf5;border-color:#a9d9ba}
.pi-approval-step strong{display:block;margin-bottom:6px}
.pi-approval-step .muted{overflow-wrap:anywhere}
.pi-approval-actions{display:flex;align-items:center;flex-wrap:wrap;gap:10px}
.pi-approval-actions .muted{flex:1}
@media(max-width:700px){.pi-approval-grid{grid-template-columns:1fr}}
/* PARKING-LOC-01: scoped locator, no Site1.Master changes */
#parkingInspection .pi-search-item{gap:8px;align-items:center;cursor:default}
#parkingInspection .pi-search-info{min-width:0;flex:1;cursor:pointer}
#parkingInspection .pi-search-info small{display:block;color:#687d90;margin-top:3px}
#parkingInspection .pi-locate-btn{flex-shrink:0;background:#eaf6fb;border-color:#91c8db;color:#075d79;font-weight:bold;white-space:nowrap}
#parkingInspection .pi-locate-btn:hover{background:#d4edf6}
#parkingInspection .pi-search-actions{display:flex;align-items:end;gap:8px;flex-wrap:wrap}
#parkingInspection .pi-search-actions > div{min-width:220px;flex:1}
#parkingInspection #piLocateSearch{min-height:35px;background:#eaf6fb;color:#075d79;border-color:#91c8db;font-weight:bold}
#parkingInspection .pi-map-summary{font-size:12px;color:#53687b;display:inline-block;margin:8px 0}
#parkingInspection .pi-search-count{color:#53687b;font-size:11px;margin-top:3px;min-height:14px}
#parkingInspection .pi-search-choice{max-width:230px;min-height:35px}
@media(max-width:900px){#parkingInspection .pi-slot-panel{display:none}#parkingInspection .pi-search-actions{flex:1 1 100%}#parkingInspection .pi-search-actions input{width:100%}#parkingInspection .pi-search-choice{max-width:100%;width:100%}}
@media(max-width:900px){#parkingInspection .pi-search-actions{width:100%}#parkingInspection .pi-search-actions > div{min-width:0}}
#parkingInspection .pi-locator-shape{stroke:#ef8b00!important;stroke-width:5!important;stroke-opacity:1!important;vector-effect:non-scaling-stroke;animation:pi-locator-flash .7s ease-in-out 6}
#parkingInspection .pi-locator-ring{fill:rgba(255,193,7,.14);stroke:#f59e0b;stroke-width:3;stroke-dasharray:6 4;pointer-events:none;vector-effect:non-scaling-stroke;animation:pi-locator-pulse 1s ease-in-out 5;transform-box:fill-box;transform-origin:center}
#parkingInspection .pi-locator-dot{fill:#f59e0b;stroke:white;stroke-width:2;pointer-events:none;vector-effect:non-scaling-stroke}
@keyframes pi-locator-flash{0%,100%{stroke-opacity:1}50%{stroke-opacity:.16}}
@keyframes pi-locator-pulse{0%,100%{opacity:1;transform:scale(1)}50%{opacity:.5;transform:scale(1.25)}}
@media(prefers-reduced-motion:reduce){#parkingInspection .pi-locator-shape,#parkingInspection .pi-locator-ring{animation:none}}
#parkingInspection .pi-workflow-field{display:flex;flex-direction:column;align-items:flex-start;justify-content:flex-end;min-height:48px;white-space:nowrap}
#parkingInspection .pi-workflow-field .pill{display:inline-block;min-height:26px;line-height:18px}

/* PARKING-UI-05B: search takes a complete, comfortable row on narrow screens. */
@media (max-width:900px){
 #parkingInspection .pi-search-actions{
   flex:0 0 100%;width:100%;min-width:0;
   display:grid;grid-template-columns:minmax(0,1fr);
   gap:9px;align-items:stretch;
 }
 #parkingInspection .pi-search-actions > div:first-child{min-width:0;width:100%;}
 #parkingInspection .pi-search-actions label{margin:0 0 6px;white-space:normal;}
 #parkingInspection #piSearch{display:block;width:100%;min-width:0;min-height:44px;font-size:16px;}
 #parkingInspection #piLocateSearch{width:100%;min-height:44px;white-space:normal;}
 #parkingInspection #piSearchChoice{max-width:none;width:100%;min-height:44px;}
 #parkingInspection .pi-search-count{margin:0;min-height:0;grid-column:1;}
 #parkingInspection .pi-search-count:empty{display:none;}
}
@media (max-width:480px){
 #parkingInspection .pi-card{padding:12px;}
 #parkingInspection .toolbar{column-gap:8px;}
}


/* PARKING-UI-05D: full-width top controls on mobile, desktop ordering unchanged. */
@media (max-width:767px){
 #parkingInspection .pi-top-toolbar{display:flex;flex-direction:column;align-items:stretch;gap:10px;}
 #parkingInspection .pi-top-toolbar > .pi-date-field,
 #parkingInspection .pi-top-toolbar > #piLoad,
 #parkingInspection .pi-top-toolbar > .pi-workflow-field,
 #parkingInspection .pi-top-toolbar > .pi-floor-field,
 #parkingInspection .pi-top-toolbar > .pi-search-actions{flex:0 0 auto;width:100%;min-width:0;max-width:none;}
 #parkingInspection .pi-date-field input,
 #parkingInspection .pi-floor-field select{display:block;width:100%;min-width:0;min-height:44px;font-size:16px;}
 #parkingInspection .pi-top-toolbar > #piLoad{min-height:44px;}
 #parkingInspection .pi-workflow-field{min-height:0;align-items:flex-start;white-space:normal;}
 #parkingInspection .pi-top-toolbar label{margin:0 0 6px;line-height:1.4;white-space:normal;}
 #parkingInspection .pi-workflow-field .pill{min-height:28px;}
}
</style>
</asp:Content>
<asp:Content ID="bodyParking" ContentPlaceHolderID="ContentPlaceHolder1" runat="server">
<asp:ScriptManager ID="smParking" runat="server" />
<div class="pi" id="parkingInspection">
 <div class="pi-card"><h2>PARKING INSPECTION</h2><div class="muted">CAR PARK · HK.03 · Daily Inspection</div></div>
 <div class="pi-card"><div class="toolbar pi-top-toolbar"><div class="pi-date-field"><label for="piDate">Tanggal Inspeksi</label><input id="piDate" type="date" value="<%= Server.HtmlEncode(SelectedDateIso) %>" /></div><button type="button" id="piLoad">Load Date</button><div class="pi-workflow-field"><label for="piWorkflow">Workflow</label><span class="pill" id="piWorkflow">DRAFT / NOT CREATED</span></div><div class="pi-floor-field"><label for="piFloor">Lantai</label><select id="piFloor"></select></div><div class="pi-search-actions"><div><label for="piSearch">Cari Slot / No Polisi</label><input id="piSearch" placeholder="Cari..." /></div><button type="button" id="piLocateSearch">Lihat di Map</button><select id="piSearchChoice" class="pi-search-choice hidden" aria-label="Pilih hasil pencarian"></select><div id="piSearchCount" class="pi-search-count" role="status" aria-live="polite"></div></div></div><div class="stats" id="piStats" style="margin-top:12px"></div></div>
  <div class="pi-card" id="piApprovalPanel" aria-label="Approval workflow">
   <strong>Approval Workflow</strong>
   <div class="muted" id="piApprovalCaption">Memuat status...</div>
   <div class="pi-approval-grid" id="piApprovalSteps"></div>
   <div class="pi-approval-actions"><span class="muted" id="piApprovalHint"></span><button type="button" class="primary" id="piApprovalAction" style="display:none" disabled></button></div>
  </div>
  <div class="layout"><div class="pi-card"><strong>Denah Interaktif</strong><div id="piMapSummary" class="pi-map-summary"></div><div class="toolbar" style="margin:10px 0"><button type="button" id="piZoomIn">+</button><button type="button" id="piZoomOut">−</button><button type="button" id="piZoomReset">Reset</button><span class="muted" id="piZoomCaption">100%</span><span class="muted">Hijau: diperiksa · Abu: belum diperiksa · Biru: dipilih</span></div><div id="piMap" class="map"></div></div>
 <div class="pi-card pi-slot-panel"><h3 style="margin-top:0">Daftar Slot</h3><div class="muted" style="margin-bottom:10px">Klik slot untuk membuka inspeksi. Tombol Lihat di Map tersedia di samping field search agar tetap bisa dipakai di mobile.</div><div id="piSlots" class="list"></div></div></div>
 <div class="pi-dialog-backdrop" id="piDialogBackdrop" aria-hidden="true"><div class="pi-dialog" role="dialog" aria-modal="true" aria-labelledby="piTitle"><h3 id="piTitle">Pilih slot parkir</h3><div class="muted" id="piHint">Klik slot pada peta atau daftar.</div><div id="piForm" class="hidden">
 <div class="field"><label for="piPlate">No Polisi *</label><input id="piPlate" maxlength="40" /></div>
 <div class="field"><label for="piJenis">Jenis *</label><input id="piJenis" maxlength="100" placeholder="Contoh: Sedan / SUV / Motor" /></div>
 <div class="field"><label for="piPintu">Pintu *</label><select id="piPintu"><option value="">Belum diisi</option><option>Terkunci</option><option>Tidak terkunci</option></select></div>
 <div class="field"><label for="piBody">Body *</label><select id="piBody"><option value="">Belum diisi</option><option>Bagus</option><option>Baret</option></select></div>
 <div class="field"><label for="piRoda">Roda *</label><select id="piRoda"><option value="">Belum diisi</option><option>Bagus</option><option>Kempes</option></select></div>
 <div class="field"><label for="piNotes">Catatan</label><textarea id="piNotes" maxlength="2000" rows="3"></textarea></div>
 <div class="field">
  <label for="<%= fuParkingPhoto.ClientID %>">Foto Kendaraan / Overview *</label>
  <asp:FileUpload ID="fuParkingPhoto" runat="server" accept=".jpg,.jpeg,.png,image/jpeg,image/png" />
  <div class="muted">Foto kendaraan wajib untuk slot terisi. Jika sudah ada foto overview tersimpan pada tanggal ini, tidak perlu upload ulang.</div>
</div>
<div class="field">
  <label for="<%= fuParkingDamagePhoto.ClientID %>">Foto Kerusakan (wajib untuk Body Baret / Roda Kempes)</label>
  <asp:FileUpload ID="fuParkingDamagePhoto" runat="server" accept=".jpg,.jpeg,.png,image/jpeg,image/png" />
  <div class="muted">Masing-masing foto maksimal 5 MB. Simpan data dan foto sekaligus melalui Save Inspection.</div>
</div>
 <div class="field"><label>Foto Tersimpan (tanggal dipilih)</label><div id="piPhotoGallery" style="display:flex;flex-wrap:wrap;gap:8px"></div></div>
 <div class="pi-actions"><button type="button" id="piCancel">Batal</button><button type="button" class="primary" id="piSave">Save Inspection</button></div><div class="muted" style="margin-top:10px">* Seluruh parameter kendaraan wajib diisi. Slot kosong tidak perlu disimpan.</div>
 </div></div></div>
  <div id="piApprovalBackdrop" class="pi-dialog-backdrop" aria-hidden="true">
   <div class="pi-dialog" role="dialog" aria-modal="true" aria-labelledby="piApprovalTitle">
    <h3 id="piApprovalTitle">Konfirmasi Approval</h3>
    <p id="piApprovalText"></p>
    <p class="muted" id="piApprovalWarning">Pastikan semua data kendaraan dan foto tersimpan. CHECKED akan mengunci seluruh lantai pada tanggal ini.</p>
    <label id="piNoVehiclesLabel" class="hidden"><input type="checkbox" id="piNoVehiclesConfirm" /> Konfirmasi: tidak ada kendaraan tercatat hari ini</label>
    <div class="pi-actions"><button type="button" id="piApprovalCancel">Batal</button><button type="button" class="primary" id="piApprovalConfirm">Konfirmasi</button></div>
   </div>
  </div>
  <asp:HiddenField ID="hfParkingApprovalRowVer" runat="server" />
  <asp:HiddenField ID="hfParkingConfirmNoVehicles" runat="server" />
  <asp:LinkButton ID="btnParkingApprove" runat="server" OnClick="btnParkingApprove_Click" Style="display:none" CausesValidation="false" />
  <asp:HiddenField ID="hfParkingPayload" runat="server"/><asp:HiddenField ID="hfParkingDate" runat="server"/>
 <asp:LinkButton ID="btnParkingSave" runat="server" OnClick="btnParkingSave_Click" Style="display:none" CausesValidation="false" />
 <asp:LinkButton ID="btnParkingLoad" runat="server" OnClick="btnParkingLoad_Click" Style="display:none" CausesValidation="false" />
</div>
<script type="text/javascript">
    (function () {
        var data = <%= InitialJson %>;
        var maps = data.maps || [];
        var slots = data.slots || [];
        var shapes = data.shapes || [];
        var photos = data.inspectionPhotos || [];
        var dailyStatus = data.dailyWorkflow || 'NOT CREATED';
        var dailyReadOnly = dailyStatus !== 'DRAFT' && dailyStatus !== 'NOT CREATED';
        var activeMap = null;
        var selected = null;
        var locatorTarget = null; // {mapID,slotID}, client-only, never modifies saved inspection.
        var zoom = 1;
        var ns = 'http://www.w3.org/2000/svg';


        function el(id) { return document.getElementById(id); }
        function txt(id, value) { el(id).textContent = value == null ? '' : String(value); }
        function field(id, value) { el(id).value = value == null ? '' : String(value); }
        function sameId(a, b) { return String(a) === String(b); }
        function currentSlots() {
            return slots.filter(function (s) { return sameId(s.MapID, activeMap); });
        }
        function getSearchMatches() {
            var q = el('piSearch').value.trim().toLowerCase();
            var pool = q ? slots : currentSlots();
            return pool.filter(function (s) {
                if (!q) return true;
                return (String(s.SlotCode || '') + ' ' + String(s.SlotName || '') + ' ' +
                    String(s.NoPolisi || '')).toLowerCase().indexOf(q) >= 0;
            });
        }
        // Use the actual rendered SVG geometry, never raw path-string token pairing.
        // This supports PATH, POLYGON, RECT and CIRCLE consistently.
        function renderedSlotCenter(mapID, slotID) {
            if (!svgNode || !sameId(activeMap, mapID)) return null;
            var nodes = svgNode.querySelectorAll('.slot');
            for (var i = 0; i < nodes.length; i++) {
                if (!sameId(nodes[i].getAttribute('data-slot-id'), slotID)) continue;
                try {
                    var box = nodes[i].getBBox();
                    if (isFinite(box.x) && isFinite(box.y) && isFinite(box.width) && isFinite(box.height))
                        return { x: box.x + box.width / 2, y: box.y + box.height / 2 };
                } catch(ignore) { }
            }
            return null;
        }
        function resolveLocateCandidate() {
            var q = el('piSearch').value.trim();
            if (!q) return selected || null;
            var matches = getSearchMatches();
            if (!matches.length) return null;
            if (matches.length === 1) return matches[0];
            var choice = el('piSearchChoice').value;
            if (!choice) return null;
            for (var i = 0; i < matches.length; i++) {
                if (String(matches[i].MapID) + ':' + String(matches[i].SlotID) === choice) return matches[i];
            }
            return null;
        }
        function updateSearchChoices() {
            var query = el('piSearch').value.trim();
            var matches = query ? getSearchMatches() : [];
            var dropdown = el('piSearchChoice'), count = el('piSearchCount');
            var oldValue = dropdown.value;
            dropdown.options.length = 0;
            if (!query) { dropdown.className = 'pi-search-choice hidden'; count.textContent = ''; return; }
            count.textContent = matches.length ? matches.length + ' hasil ditemukan' : 'Tidak ditemukan';
            if (matches.length <= 1) { dropdown.className = 'pi-search-choice hidden'; return; }
            dropdown.className = 'pi-search-choice';
            dropdown.add(new Option('Pilih slot (' + matches.length + ' hasil)', ''));
            matches.forEach(function(s) {
                var map = maps.filter(function(m){return sameId(m.MapID,s.MapID);})[0];
                var name = (map ? map.FloorCode : '?') + ' · ' + (s.SlotCode || s.SlotID) + (s.NoPolisi ? ' · ' + s.NoPolisi : '');
                dropdown.add(new Option(name, String(s.MapID)+':'+String(s.SlotID)));
            });
            if (oldValue) dropdown.value = oldValue;
        }
        var panX = 0, panY = 0, svgNode = null, suppressClick = false;
        var dialogOpen = false, previousFocus = null;
        function closeDialog() {
            dialogOpen = false;
            el('piDialogBackdrop').classList.remove('pi-open');
            el('piDialogBackdrop').setAttribute('aria-hidden', 'true');
            if (previousFocus && previousFocus.focus) previousFocus.focus();
        }
        function openDialog() {
            previousFocus = document.activeElement;
            dialogOpen = true;
            el('piDialogBackdrop').classList.add('pi-open');
            el('piDialogBackdrop').setAttribute('aria-hidden', 'false');
            el('piCancel').focus();
        }
        // MOBILE-PAN-01: one transform write per animation frame, no layout reads during drag.
        var framePending = false, panLimitX = 0, panLimitY = 0;
        function scheduleTransform() {
            if (framePending) return;
            framePending = true;
            window.requestAnimationFrame(function () {
                framePending = false;
                if (!svgNode) return;
                // Change the SVG camera rather than scaling a cached raster/composited layer.
                // This keeps SVG text and strokes sharp on mobile at every zoom level.
                var m = maps.filter(function(x) { return sameId(x.MapID, activeMap); })[0];
                if (!m) return;
                var baseX = Number(m.ViewBoxX), baseY = Number(m.ViewBoxY);
                var baseW = Number(m.ViewBoxWidth), baseH = Number(m.ViewBoxHeight);
                var viewW = baseW / zoom, viewH = baseH / zoom;
                var cssW = svgNode.clientWidth || 1, cssH = svgNode.clientHeight || 1;
                var shiftX = panX * (baseW / cssW) / zoom;
                var shiftY = panY * (baseH / cssH) / zoom;
                svgNode.setAttribute('viewBox', [baseX + (baseW-viewW)/2-shiftX,
                    baseY + (baseH-viewH)/2-shiftY, viewW, viewH].join(' '));
                el('piZoomCaption').textContent = Math.round(zoom * 100) + '%';
            });
        }
        function measurePanLimits() {
            if (!svgNode) return;
            var holder = el('piMap');
            // offset dimensions are untransformed; avoid getBoundingClientRect() after transform.
            var width = svgNode.clientWidth || holder.clientWidth;
            var height = svgNode.clientHeight || holder.clientHeight;
            panLimitX = Math.max(0, (width * zoom - holder.clientWidth) / 2) + 35;
            panLimitY = Math.max(0, (height * zoom - holder.clientHeight) / 2) + 35;
        }
        function boundPan() {
            if (zoom <= 1 || !svgNode) { panX = 0; panY = 0; return; }
            panX = Math.max(-panLimitX, Math.min(panLimitX, panX));
            panY = Math.max(-panLimitY, Math.min(panLimitY, panY));
        }
        function setZoom(value) {
            zoom = Math.max(1, Math.min(4, value));
            if (zoom === 1) { panX = 0; panY = 0; }
            measurePanLimits(); boundPan(); scheduleTransform();
        }
        function attachGestures(svg) {
            var pointers = {}, gesture = null, holder = el('piMap');
            function keys() { return Object.keys(pointers); }
            function pair() {
                var k = keys();
                if (k.length < 2) return null;
                return [pointers[k[0]], pointers[k[1]]];
            }
            function distance(p) {
                var dx = p[0].x - p[1].x, dy = p[0].y - p[1].y;
                return Math.sqrt(dx * dx + dy * dy);
            }
            function center(p) { return {x:(p[0].x+p[1].x)/2, y:(p[0].y+p[1].y)/2}; }
            function beginPinch() {
                var p = pair(); if (!p) return;
                gesture = {pinch:true, startDistance:Math.max(1,distance(p)), startZoom:zoom,
                    startPanX:panX, startPanY:panY, center:center(p), moved:true};
                suppressClick = true;
            }
            svg.addEventListener('pointerdown', function(e) {
                if (e.pointerType === 'mouse' && e.button !== 0) return;
                if (!keys().length) suppressClick = false;
                pointers[e.pointerId] = {x:e.clientX,y:e.clientY};
                if (keys().length === 1) gesture = {pinch:false, x:e.clientX,y:e.clientY,
                    startPanX:panX,startPanY:panY,moved:false};
                else if (keys().length >= 2) beginPinch();
                // Capture touch to keep receiving movements outside polygon bounds.
                // Click suppression is handled below; taps still select slots.
                if (e.pointerType !== 'mouse') {
                    try { svg.setPointerCapture(e.pointerId); } catch(ignore) {}
                }
            });
            svg.addEventListener('pointermove', function(e) {
                if (!Object.prototype.hasOwnProperty.call(pointers,e.pointerId)) return;
                pointers[e.pointerId] = {x:e.clientX,y:e.clientY};
                if (!gesture) return;
                var p = pair();
                if (p) {
                    if (!gesture.pinch) beginPinch();
                    var c = center(p);
                    zoom = Math.max(1,Math.min(4,gesture.startZoom * distance(p) / gesture.startDistance));
                    panX = gesture.startPanX + (c.x - gesture.center.x);
                    panY = gesture.startPanY + (c.y - gesture.center.y);
                    measurePanLimits(); boundPan(); scheduleTransform();
                    return;
                }
                if (gesture.pinch) return;
                var dx = e.clientX - gesture.x, dy = e.clientY - gesture.y;
                if (!gesture.moved && dx*dx + dy*dy > 36) gesture.moved = true;
                if (!gesture.moved) return;
                suppressClick = true;
                holder.classList.add('pi-dragging');
                panX = gesture.startPanX + dx;
                panY = gesture.startPanY + dy;
                boundPan(); scheduleTransform();
            });
            function end(e) {
                if (!Object.prototype.hasOwnProperty.call(pointers,e.pointerId)) return;
                delete pointers[e.pointerId];
                if (gesture && gesture.moved) suppressClick = true;
                holder.classList.remove('pi-dragging');
                if (keys().length === 1) {
                    var remaining = pointers[keys()[0]];
                    gesture = {pinch:false,x:remaining.x,y:remaining.y,startPanX:panX,startPanY:panY,moved:true};
                } else if (keys().length >= 2) beginPinch();
                else gesture = null;
            }
            svg.addEventListener('pointerup', end);
            svg.addEventListener('pointercancel', end);
            svg.addEventListener('lostpointercapture', end);
            svg.addEventListener('click', function(e) {
                if (suppressClick) { e.preventDefault(); e.stopPropagation(); suppressClick = false; }
            }, true);
            holder.onwheel = function(e) { e.preventDefault(); setZoom(zoom + (e.deltaY < 0 ? .15 : -.15)); };
        }
        function pick(id) {
            selected = currentSlots().filter(function (s) { return sameId(s.SlotID, id); })[0] || null;
            if (!selected) return;
            txt('piTitle', selected.SlotCode + ' · ' + (selected.SlotName || ''));
            txt('piHint', dailyStatus + (dailyReadOnly ? ' · Read-only' : ''));
            el('piForm').className = '';
            field('piPlate', selected.NoPolisi);
            field('piJenis', selected.Jenis);
            field('piPintu', selected.Pintu);
            field('piBody', selected.Body);
            field('piRoda', selected.Roda);
            field('piNotes', selected.Notes);
            el('<%= fuParkingPhoto.ClientID %>').value = '';
            el('<%= fuParkingDamagePhoto.ClientID %>').value = '';
            var gallery=el('piPhotoGallery');gallery.innerHTML='';
            var currentPhotos=photos.filter(function(p){
                return sameId(p.ObjectID,selected.SlotID)&&sameId(p.MapID,selected.MapID);
            });
            if(!currentPhotos.length){
                var empty=document.createElement('span');empty.className='muted';
                empty.textContent='Belum ada foto pada tanggal inspeksi ini.';
                gallery.appendChild(empty);
            }
            currentPhotos.forEach(function(p){
                var link=document.createElement('a');
                link.href=window.location.pathname+'?inspecPhoto='+encodeURIComponent(p.PhotoID)+
                    '&photoDate=<%= SelectedDateIso %>';
                link.target='_blank';link.rel='noopener noreferrer';
                link.title='Lihat foto '+p.PhotoType;
                var img=document.createElement('img');img.src=link.href;img.alt='Foto '+p.PhotoType;
                img.style.cssText='width:84px;height:84px;object-fit:cover;border-radius:6px;border:1px solid #cad6e1';
                link.appendChild(img);gallery.appendChild(link);
            });
            var locked = dailyReadOnly || (!!selected.WorkflowStatus && selected.WorkflowStatus !== 'DRAFT');
            Array.prototype.forEach.call(el('piForm').querySelectorAll('input,select,textarea,button'), function (node) {
                node.disabled = locked;
            });
            renderMap();
            renderList();
            openDialog();
        }
        // While searching, look across ALL floors. Without query, show selected floor only.
        function renderList() {
            var list = el('piSlots');
            list.innerHTML = '';
            var q = el('piSearch').value.trim().toLowerCase();
            var matches = getSearchMatches();
            if (!matches.length) {
                var empty=document.createElement('div'); empty.className='item muted';
                empty.textContent='Slot / nomor polisi tidak ditemukan pada tanggal ini.';
                list.appendChild(empty); return;
            }
            matches.forEach(function(s) {
                var row = document.createElement('div');
                row.className = 'item pi-search-item' +
                    (selected && sameId(selected.SlotID,s.SlotID) && sameId(selected.MapID,s.MapID) ? ' active' : '');
                row.onclick=function(){
                    if(!sameId(activeMap,s.MapID)) changeFloor(s.MapID);
                    pick(s.SlotID);
                };
                var info=document.createElement('div'); info.className='pi-search-info';
                var title=document.createElement('strong'); title.textContent=s.SlotCode||'Slot '+s.SlotID;
                info.appendChild(title);
                var map=maps.filter(function(m){return sameId(m.MapID,s.MapID);})[0];
                var description=document.createElement('small');
                description.textContent=(s.NoPolisi||'Belum diperiksa') +
                    (q && map ? ' · '+(map.FloorCode||map.MapName||'Lantai') : '');
                info.appendChild(description);
                row.appendChild(info); list.appendChild(row);
            });
        }
        function changeFloor(mapID) {
            activeMap=mapID;
            el('piFloor').value=String(mapID);
            selected=null; zoom=1;panX=0;panY=0;
            closeDialog(); el('piForm').className='hidden';
            txt('piTitle','Pilih slot parkir');
        }
        function focusSlotOnMap(slot) {
            var candidate = shapes.some(function(sh){return sameId(sh.MapID,slot.MapID) && sameId(sh.SlotID,slot.SlotID);});
            if (!candidate) { alert('Slot ' + (slot.SlotCode || slot.SlotID) + ' belum mempunyai mapping pada denah.'); return; }
            if (!sameId(activeMap, slot.MapID)) changeFloor(slot.MapID);
            selected = slot;
            locatorTarget = {mapID:slot.MapID, slotID:slot.SlotID};
            // PARKING-UI-05C: locator search focuses at the global maximum zoom (400%).
            zoom = 4; panX = 0; panY = 0;
            render();
            var pos = renderedSlotCenter(slot.MapID, slot.SlotID);
            var map = maps.filter(function(m){return sameId(m.MapID,slot.MapID);})[0];
            if (!pos || !map || !svgNode) { alert('Posisi slot tidak dapat ditentukan.'); return; }
            var baseW = Number(map.ViewBoxWidth), baseH = Number(map.ViewBoxHeight);
            if (baseW > 0 && baseH > 0) {
                var cx = Number(map.ViewBoxX) + baseW / 2, cy = Number(map.ViewBoxY) + baseH / 2;
                panX = (cx-pos.x) * zoom * (svgNode.clientWidth || 1) / baseW;
                panY = (cy-pos.y) * zoom * (svgNode.clientHeight || 1) / baseH;
                measurePanLimits(); boundPan(); scheduleTransform();
            }
            var canvas=el('piMap');
            if (canvas && canvas.scrollIntoView) canvas.scrollIntoView({block:'center',behavior:'smooth'});
        }
        function renderStats() {
            var ss = currentSlots();
            var done = ss.filter(function (s) { return !!s.NoPolisi; }).length;
            el('piStats').innerHTML = '<span>Total Slot: <strong>' + ss.length + '</strong></span>' +
                '<span>Diperiksa: <strong>' + done + '</strong></span>' +
                '<span>Belum: <strong>' + (ss.length - done) + '</strong></span>';
        }
        function renderMap() {
            var map = maps.filter(function (m) { return sameId(m.MapID, activeMap); })[0];
            var box = el('piMap');
            box.innerHTML = '';
            if (!map) return;

            var svg = document.createElementNS(ns, 'svg');
            svg.setAttribute('viewBox', [map.ViewBoxX, map.ViewBoxY, map.ViewBoxWidth, map.ViewBoxHeight].join(' '));
            svg.setAttribute('role', 'img');
            svg.setAttribute('aria-label', map.MapName || 'Denah parkir');

            var rect = document.createElementNS(ns, 'rect');
            rect.setAttribute('x', map.ViewBoxX);
            rect.setAttribute('y', map.ViewBoxY);
            rect.setAttribute('width', map.ViewBoxWidth);
            rect.setAttribute('height', map.ViewBoxHeight);
            rect.setAttribute('fill', '#edf2f6');
            svg.appendChild(rect);

            // Background image: always append before the interactive slot polygons.
            if (map.ImagePath) {
                var url = map.ImagePath;
                var background = document.createElementNS(ns, 'image');
                background.setAttribute('x', map.ViewBoxX);
                background.setAttribute('y', map.ViewBoxY);
                background.setAttribute('width', map.ViewBoxWidth);
                background.setAttribute('height', map.ViewBoxHeight);
                background.setAttribute('preserveAspectRatio', 'none');
                background.setAttribute('href', url);
                background.setAttributeNS('http://www.w3.org/1999/xlink', 'href', url);
                svg.appendChild(background);
                console.log('[PARKING] Background URL:', url);
                var probe = new Image();
                probe.onload = function () {
                    console.log('[PARKING] Background loaded:', probe.naturalWidth, probe.naturalHeight);
                };
                probe.onerror = function () {
                    console.error('[PARKING] Background gagal dimuat:', url,
                        'Periksa URL, Network status, dan lokasi file di server.');
                };
                probe.src = url;
            } else {
                console.warn('[PARKING] ImagePath kosong untuk MapID:', map.MapID);
            }

            shapes.filter(function (s) { return sameId(s.MapID, activeMap); }).forEach(function (s) {
                var slot = slots.filter(function (x) {
                    return sameId(x.SlotID, s.SlotID) && sameId(x.MapID, s.MapID);
                })[0];
                if (!slot) return;
                var type = String(s.ShapeType || '').toUpperCase();
                var tag = type === 'PATH' ? 'path' : type === 'CIRCLE' ? 'circle' :
                    type === 'RECT' ? 'rect' : type === 'POLYGON' ? 'polygon' : null;
                if (!tag) return;
                var node = document.createElementNS(ns, tag);
                node.setAttribute('class', 'slot');
                node.setAttribute('data-slot-id', s.SlotID);
                if(locatorTarget && sameId(locatorTarget.mapID,s.MapID) && sameId(locatorTarget.slotID,s.SlotID))
                    node.setAttribute('class','slot pi-locator-shape');
                node.setAttribute('fill', selected && sameId(selected.SlotID, s.SlotID) ? '#2d86da' :
                    slot.NoPolisi ? '#16834a' : '#9caab7');
                node.setAttribute('fill-opacity', '.48');
                node.setAttribute('stroke', '#234');
                if (tag === 'path') {
                    node.setAttribute('d', s.SvgPathData || '');
                } else {
                    var attrs = {};
                    try { attrs = JSON.parse(s.ShapeAttributes || '{}'); } catch (ignore) { }
                    Object.keys(attrs).forEach(function (key) {
                        if (['cx', 'cy', 'r', 'x', 'y', 'width', 'height', 'points'].indexOf(key) >= 0) {
                            node.setAttribute(key, attrs[key]);
                        }
                    });
                }
                node.setAttribute('tabindex', '0');
                node.setAttribute('role', 'button');
                node.setAttribute('aria-label', 'Slot ' + (slot.SlotCode || s.SlotID));
                node.onclick = function () { pick(s.SlotID); };
                node.onkeydown = function(e) { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); pick(s.SlotID); } };
                svg.appendChild(node);
            });
            box.appendChild(svg);
            // Point marker follows actual SVG element bbox, not parser approximations.
            if (locatorTarget && sameId(locatorTarget.mapID, activeMap)) {
                var targetPoint = null;
                var targetNodes = svg.querySelectorAll('.pi-locator-shape');
                if (targetNodes.length) {
                    try {
                        var targetBounds = targetNodes[0].getBBox();
                        targetPoint = {x:targetBounds.x + targetBounds.width/2, y:targetBounds.y + targetBounds.height/2};
                    } catch(ignore) { }
                }
                if (targetPoint) {
                    var radius=Math.max(6,(Number(map.ViewBoxWidth)||500)/70);
                    var ring=document.createElementNS(ns,'circle');
                    ring.setAttribute('cx',targetPoint.x); ring.setAttribute('cy',targetPoint.y);
                    ring.setAttribute('r',radius);ring.setAttribute('class','pi-locator-ring');svg.appendChild(ring);
                    var dot=document.createElementNS(ns,'circle');
                    dot.setAttribute('cx',targetPoint.x);dot.setAttribute('cy',targetPoint.y);
                    dot.setAttribute('r',Math.max(3,radius/4));dot.setAttribute('class','pi-locator-dot');svg.appendChild(dot);
                }
            }
            svgNode = svg;
            svg.style.transformOrigin = 'center center';
            measurePanLimits();
            scheduleTransform();
            attachGestures(svg);
        }
        function renderMapSummary() {
            var m=maps.filter(function(x){return sameId(x.MapID,activeMap);})[0];
            if (!m) { txt('piMapSummary',''); return; }
            var hasInspection=currentSlots().some(function(s){return s.InspectionID != null;});
            txt('piMapSummary', (m.FloorCode || m.MapName || 'Lantai') + ' · MapID ' + m.MapID +
                ' · ' + m.ViewBoxWidth + ' × ' + m.ViewBoxHeight +
                (hasInspection ? ' · Peta inspeksi tanggal ini' : ' · Peta tersedia'));
        }
        function render() { renderStats(); renderList(); renderMapSummary(); renderMap(); }

        console.log('[PARKING] Initial payload:', {
            scopePending: !!data.scopePending,
            loadError: !!data.loadError,
            errorMessage: data.errorMessage || '',
            maps: maps.length, slots: slots.length, shapes: shapes.length
        });
        if (data.loadError) console.error('[PARKING] Server error:', data.errorMessage);
        if (data.scopePending) console.warn('[PARKING] CompanyID/LocationID belum tersedia; auto-postback dinonaktifkan.');

        var floor = el('piFloor');
        floor.options.length = 0;
        if (!maps.length) {
            floor.add(new Option(data.scopePending ? 'Menunggu Company / Location' :
                data.loadError ? 'Gagal memuat lantai' : 'Tidak ada lantai tersedia', ''));
        } else {
            maps.forEach(function (m) {
                floor.add(new Option((m.FloorCode || '') + ' - ' + (m.MapName || ''), String(m.MapID)));
            });
            activeMap = maps[0].MapID;
            floor.value = String(activeMap);
        }
        floor.onchange = function () {
            locatorTarget=null;
            changeFloor(this.value);
            render();
        };
        el('piSearch').oninput = function(){ locatorTarget=null; updateSearchChoices(); renderList(); renderMap(); };
        el('piSearch').onkeydown = function(e){ if(e.key==='Enter'){e.preventDefault();el('piLocateSearch').click();} }; 
        el('piLocateSearch').onclick = function () {
            var candidate = resolveLocateCandidate();
            if (!candidate) {
                alert(el('piSearch').value.trim() ? (getSearchMatches().length > 1 ? 'Ada beberapa hasil. Pilih slot dari daftar di samping pencarian.' : 'Slot / nomor polisi tidak ditemukan.') : 'Pilih slot atau isi field search terlebih dahulu.');
                return;
            }
            focusSlotOnMap(candidate);
        };
        el('piZoomIn').onclick = function () { setZoom(zoom + .25); };
        el('piZoomOut').onclick = function () { setZoom(zoom - .25); };
        el('piZoomReset').onclick = function () { setZoom(1); };
        el('piCancel').onclick = closeDialog;
        el('piDialogBackdrop').onclick = function(e) { if (e.target === this) closeDialog(); };
        document.addEventListener('keydown', function(e) { if (e.key === 'Escape' && dialogOpen) closeDialog(); });
        el('piLoad').onclick = function () {
            el('<%= hfParkingDate.ClientID %>').value = el('piDate').value;
            el('<%= btnParkingLoad.ClientID %>').click();
        };
        ['piPlate', 'piJenis'].forEach(function (name) {
            el(name).addEventListener('input', function () {
                var start = this.selectionStart, end = this.selectionEnd;
                this.value = this.value.toUpperCase();
                try { this.setSelectionRange(start, end); } catch (ignore) {}
            });
        });
        el('piSave').onclick = function () {
            if (!selected || dailyReadOnly) return;
            var payload = {
                MapID: selected.MapID, SlotID: selected.SlotID,
                NoPolisi: el('piPlate').value.trim().toUpperCase(), Jenis: el('piJenis').value.trim().toUpperCase(),
                Pintu: el('piPintu').value || null, Body: el('piBody').value || null,
                Roda: el('piRoda').value || null, Notes: el('piNotes').value
            };
            if (!payload.NoPolisi || !payload.Jenis || !payload.Pintu || !payload.Body || !payload.Roda) {
                alert('No Polisi, Jenis, Pintu, Body, dan Roda wajib diisi.');
                return;
            }
            // Presence of existing photo metadata for THIS selected slot/map and selected inspection date.
            // 'photos' is loaded per inspection date from the server; server repeats all checks.
            var currentPhotos = photos.filter(function(p) {
                return sameId(p.ObjectID, selected.SlotID) && sameId(p.MapID, selected.MapID);
            });
            function hasPhoto(type) {
                return currentPhotos.some(function(p) { return p.PhotoType === type; });
            }
            var overviewInput = el('<%= fuParkingPhoto.ClientID %>');
            var damageInput = el('<%= fuParkingDamagePhoto.ClientID %>');
            var newOverview = overviewInput.files && overviewInput.files.length === 1;
            var newDamage = damageInput.files && damageInput.files.length === 1;
            var damageRequired = payload.Body === 'Baret' || payload.Roda === 'Kempes';
            if (!hasPhoto('OVERVIEW') && !newOverview) {
                alert('Foto kendaraan wajib dipilih sebelum Save Inspection.');
                overviewInput.focus(); return;
            }
            if (damageRequired && !hasPhoto('DAMAGE') && !newDamage) {
                alert('Body Baret / Roda Kempes wajib memiliki foto kerusakan.');
                damageInput.focus(); return;
            }
            var inputs = [overviewInput, damageInput];
            for (var i = 0; i < inputs.length; i++) {
                if (inputs[i].files && inputs[i].files.length) {
                    var f = inputs[i].files[0];
                    if (f.size === 0 || f.size > 5242880 || !/\.(jpg|jpeg|png)$/i.test(f.name)) {
                        alert('Foto harus JPG/PNG dan berukuran 1 byte sampai 5 MB.'); return;
                    }
                }
            }
            el('<%= hfParkingPayload.ClientID %>').value = JSON.stringify(payload);
            el('<%= hfParkingDate.ClientID %>').value = el('piDate').value;
            var saveButton = el('piSave');
            saveButton.disabled = true;
            saveButton.textContent = 'Menyimpan...';
            // Full WebForms multipart POST: FileUpload bytes and inspection fields are sent together.
            try {
                var serverButton = el('<%= btnParkingSave.ClientID %>');
                if (typeof window.__doPostBack === 'function')
                    window.__doPostBack('<%= btnParkingSave.UniqueID %>', '');
                else
                    serverButton.click();
            } catch (err) {
                saveButton.disabled = false;
                saveButton.textContent = 'Save Inspection';
                alert('Gagal mengirim inspeksi: ' + err.message);
            }
        };
        function approvalNext(){
            return {DRAFT:'CHECKED',CHECKED:'VERIFIED',VERIFIED:'ACKNOWLEDGED'}[dailyStatus] || null;
        }
        function approvalAllowed(code){
            return (data.approvalPermissions||[]).some(function(x){
                return x.ApprovalCode===code && (x.CanAct===true||x.CanAct===1||x.CanAct==='1');
            });
        }
        function approvalDate(value){
            if(!value)return '-';
            var m=String(value).match(/^\/Date\((-?\d+)(?:[+-]\d{4})?\)\/$/);
            var d=m?new Date(Number(m[1])):new Date(value);
            return isNaN(d.getTime())?'-':d.toLocaleString('id-ID');
        }
        function renderApproval(){
            var steps=el('piApprovalSteps');steps.innerHTML='';
            txt('piWorkflow',dailyStatus);
            txt('piApprovalCaption','Workflow harian seluruh lantai: '+dailyStatus);
            ['CHECKED','VERIFIED','ACKNOWLEDGED'].forEach(function(code,i){
                var history=(data.approvalHistory||[]).filter(function(h){return h.ActionCode===code;})[0];
                var step=document.createElement('div');step.className='pi-approval-step'+(history?' done':'');
                var title=document.createElement('strong');title.textContent=(i+1)+'. '+code;
                var state=document.createElement('div');state.className='muted';
                state.textContent=history?('Disetujui: '+history.ActionBy+' · '+approvalDate(history.ActionDate)):'Menunggu persetujuan';
                step.appendChild(title);step.appendChild(state);steps.appendChild(step);
            });
            var next=approvalNext(),button=el('piApprovalAction'),hint=el('piApprovalHint');
            button.style.display=next?'':'none';
            if(!next){hint.textContent=dailyStatus==='ACKNOWLEDGED'?'Inspeksi FINAL · read-only':'Simpan inspeksi untuk membuat header harian terlebih dahulu.';return;}
            button.textContent=next==='CHECKED'?'Selesaikan Inspeksi':next==='VERIFIED'?'Verify Inspection':'Acknowledge (FINAL)';
            var v=data.approvalValidation||{};
            var ready=next!=='CHECKED'||v.IsReadyForChecked===true||v.IsReadyForChecked===1;
            var zero=Number(v.VehicleCount||0)===0;
            if(next==='CHECKED'&&zero)ready=true; // Explicit confirmation required on modal and server.
            var hasRow=!!data.parkingDailyID&&!!data.approvalRowVer;
            button.disabled=!approvalAllowed(next)||!hasRow||!ready||el('piDate').value!=='<%= Server.HtmlEncode(SelectedDateIso) %>';
             hint.textContent= next==='CHECKED' ? ('Kendaraan: '+(v.VehicleCount||0)+' · Masalah: '+(v.IssueCount||0)+
                 (ready?' · Siap diperiksa untuk CHECKED':' · Lengkapi data/foto sebelum CHECKED'))
                 : 'Tahap berikutnya: '+next;
         }
        function approvalClose(){var b=el('piApprovalBackdrop');b.classList.remove('pi-open');b.setAttribute('aria-hidden','true');}
        el('piApprovalAction').onclick=function(){
            if(this.disabled)return;
            var next=approvalNext();
            txt('piApprovalText','Lanjutkan '+next+' untuk tanggal '+el('piDate').value+' (seluruh lantai)?');
            var zero=next==='CHECKED' && Number((data.approvalValidation||{}).VehicleCount||0)===0;
            el('piNoVehiclesLabel').className=zero?'':'hidden';
            el('piNoVehiclesConfirm').checked=false;
            el('piApprovalBackdrop').classList.add('pi-open');
            el('piApprovalBackdrop').setAttribute('aria-hidden','false');
            el('piApprovalCancel').focus();
        };
        el('piApprovalCancel').onclick=approvalClose;
        el('piApprovalBackdrop').onclick=function(e){if(e.target===this)approvalClose();};
        el('piApprovalConfirm').onclick=function(){
            var next=approvalNext(),zero=next==='CHECKED'&&Number((data.approvalValidation||{}).VehicleCount||0)===0;
            if(!next||!approvalAllowed(next)||!data.approvalRowVer||
               el('piDate').value!=='<%= Server.HtmlEncode(SelectedDateIso) %>')return;
             if(zero&&!el('piNoVehiclesConfirm').checked){alert('Konfirmasi tidak ada kendaraan harus dicentang.');return;}
             el('<%= hfParkingApprovalRowVer.ClientID %>').value=data.approvalRowVer;
             el('<%= hfParkingConfirmNoVehicles.ClientID %>').value=zero?'1':'0';
             el('<%= hfParkingDate.ClientID %>').value=el('piDate').value;
             this.disabled=true;
             try{window.__doPostBack('<%= btnParkingApprove.UniqueID %>','');}
             catch(ex){this.disabled=false;alert('Postback gagal: '+ex.message);}
         };
        el('piDate').addEventListener('change',renderApproval);
        renderApproval();
        render();
    })();
</script>
</asp:Content>

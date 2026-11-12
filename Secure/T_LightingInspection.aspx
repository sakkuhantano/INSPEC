<%@ Page Title="" Language="C#" MasterPageFile="~/MasterPages/Site_BS_5.Master" AutoEventWireup="true" CodeBehind="T_LightingInspection.aspx.cs" Inherits="INSPEC.Secure.T_LightingInspection" %>
<%@ MasterType VirtualPath="~/MasterPages/Site_BS_5.Master" %>
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
    touch-action:pan-y
}
.li-map svg {
    max-width:100%;
    max-height:65vh;
    min-height:280px;
    overflow:visible;
    touch-action:none
}
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
            </div>
            <div id="liMessage" aria-live="polite">
            </div>
            <div class="li-tabs" id="liSchedules">
            </div>
            <div class="li-kpis" id="liStats">
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
                    Hijau = ON · Merah = OFF · Abu-abu = Belum diperiksa. Klik jalur atau marker untuk memilih lampu.
                </div>
            </div>
            <div class="li-card">
                <strong>
                    Checklist Lampu
                </strong>
                <div class="li-sub" id="liListCaption">
                </div>
                <div class="li-list" id="liChecklist">
                </div>
            </div>
        </div>
        <asp:HiddenField ID="hfLightingPayload" runat="server" />
        <asp:HiddenField ID="hfLightingDate" runat="server" />
        <asp:LinkButton ID="btnLightingSave" runat="server" OnClick="btnLightingSave_Click" Style="display:none" CausesValidation="false" />
        <asp:LinkButton ID="btnLightingLoad" runat="server" OnClick="btnLightingLoad_Click" Style="display:none" CausesValidation="false" />
    </div>
<script type="text/javascript">
    (function() {
        var root=document.getElementById('lightingApp');if(!root)return;
        var initial=<%= InitialJson %>;
    var data=initial,activeSchedule=null,activeMap=null,selectedLight=null,zoom=1,dirty= {
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
                activeMap=x.MapID;zoom=1;render();
            }
            ));
        }
        );
    }
    function stats() {
        var selected=rows.filter(function(r) {
            return r.ScheduleID===activeSchedule;
        }
        );var on=0,off=0;selected.forEach(function(r) {
            var v=status(r.LightID).status;if(v==='ON')on++;if(v==='OFF')off++;
        }
        );byId('liStats').innerHTML='<span>Total: <strong>'+selected.length+'</strong></span><span>ON: <strong>'+on+'</strong></span><span>OFF: <strong>'+off+'</strong></span><span>Belum diperiksa: <strong>'+(selected.length-on-off)+'</strong></span><span class="li-dirty">'+Object.keys(dirty).length+' perubahan belum disimpan</span>';byId('liWorkflow').textContent=data.workflow||'NOT CREATED';byId('liSave').disabled=!isEditable||!Object.keys(dirty).length;
    }
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
    function renderMap() {
        var map=maps.filter(function(m) {
            return m.MapID===activeMap;
        }
        )[0],el=byId('liMapCanvas');el.innerHTML='';if(!map) {
            el.textContent='Denah tidak tersedia';return;
        }
        byId('liMapCaption').textContent=map.MapCode+' · '+Math.round(zoom*100)+'%';var ns='http://www.w3.org/2000/svg';var svg=document.createElementNS(ns,'svg');svg.setAttribute('viewBox',[map.ViewBoxX,map.ViewBoxY,map.ViewBoxWidth,map.ViewBoxHeight].join(' '));svg.setAttribute('role','img');svg.setAttribute('aria-label',map.MapName);svg.style.transform='scale('+zoom+')';svg.style.transformOrigin='center center';var bg=document.createElementNS(ns,'rect');bg.setAttribute('x',map.ViewBoxX);bg.setAttribute('y',map.ViewBoxY);bg.setAttribute('width',map.ViewBoxWidth);bg.setAttribute('height',map.ViewBoxHeight);bg.setAttribute('fill','#e9eff3');svg.appendChild(bg);
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
                choose(p.LightID);
            }
            ;shape.onkeydown=function(e) {
                if(e.key==='Enter'||e.key===' ') {
                    e.preventDefault();choose(p.LightID);
                }
            }
            ;svg.appendChild(shape);
        }
        );el.appendChild(svg);
    }
    function render() {
        tabs();stats();renderMap();list();
    }
    function msg(s,error) {
        byId('liMessage').innerHTML='<div class="li-msg '+(error?'li-error':'li-warning')+'">'+esc(s)+'</div>';
    }
    byId('liSave').onclick=function() {
        if(!isEditable||!Object.keys(dirty).length)return;var values=Object.keys(dirty).map(function(k) {
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
        if(Object.keys(dirty).length&&!confirm('Perubahan belum disimpan akan hilang. Lanjutkan?'))return;byId('<%= hfLightingDate.ClientID %>').value=byId('liDate').value;byId('<%= btnLightingLoad.ClientID %>').click();
    }
    ;
    byId('liZoomIn').onclick=function() {
        zoom=Math.min(3,zoom+.25);renderMap();
    }
    ;byId('liZoomOut').onclick=function() {
        zoom=Math.max(.5,zoom-.25);renderMap();
    }
    ;byId('liResetZoom').onclick=function() {
        zoom=1;renderMap();
    }
    ;
    render();
}
)();
</script>
</asp:Content>

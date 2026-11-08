(function () {
    "use strict";

    var wired = false;
    var selectedPoint = null;
    var currentMapRecord = null;
    var currentMaps = [];
    var currentPoints = [];
    var currentMapId = "";
    var currentPdfDocument = null;
    var listPage = 1;
    var listPageSize = 20;
    var listKeyword = "";
    var mapZoom = 1;
    var mapPanX = 0;
    var mapPanY = 0;
    var mapPointers = {};
    var mapGesture = null;
    var mapMinZoom = 1;
    var mapMaxZoom = 4;

    function esc(value) {
        return String(value == null ? "" : value).replace(/[&<>"']/g, function (c) {
            return ({ "&":"&amp;", "<":"&lt;", ">":"&gt;", "\"":"&quot;", "'":"&#39;" })[c];
        });
    }

    function normalizedStatus(status) {
        status = String(status || "PENDING").toUpperCase();
        if (status === "DONE" || status === "INSPECTED") return "DONE";
        if (status === "ABNORMAL") return "ABNORMAL";
        if (status === "INCOMPLETE") return "INCOMPLETE";
        return "PENDING";
    }

    function pointClass(status) {
        return normalizedStatus(status).toLowerCase();
    }

    function statusLabel(status, point) {
        var value = normalizedStatus(status);
        if (value === "PENDING" && point && !pointRequiresInspection(point)) return "BELUM ADA HASIL";
        return value === "DONE" ? "DONE" : value === "ABNORMAL" ? "ABNORMAL" :
            value === "INCOMPLETE" ? "INCOMPLETE" : "PENDING";
    }

    function getPointTransaction(point) {
        if (!currentMapRecord || !Array.isArray(currentMapRecord.Points)) return null;
        return currentMapRecord.Points.find(function (item) {
            return Number(item.InspectionPointID) === Number(point.InspectionPointID);
        }) || null;
    }

    function getPointStatus(point) {
        var transaction = getPointTransaction(point);
        return normalizedStatus(transaction && transaction.Status);
    }

    function pointRequiresInspection(point) {
        if (!point || point.RequireAllPoints === undefined || point.RequireAllPoints === null) return true;
        return !(point.RequireAllPoints === false || point.RequireAllPoints === 0 ||
            String(point.RequireAllPoints).toLowerCase() === "false" || String(point.RequireAllPoints) === "0");
    }

    function getVisiblePoints() {
        return currentPoints.slice();
    }

    function findNextPendingPoint() {
        var pending = currentPoints.filter(function (point) {
            var status = getPointStatus(point);
            return status === "INCOMPLETE" || (status === "PENDING" && pointRequiresInspection(point));
        });
        if (!pending.length) return null;
        pending.sort(function (a, b) {
            var ao = Number(a.DisplayOrder || 0), bo = Number(b.DisplayOrder || 0);
            if (ao !== bo) return ao - bo;
            return String(a.PointCode || "").localeCompare(String(b.PointCode || ""));
        });
        return pending[0];
    }

    function renderPoints() {
        var host = document.getElementById("inspectionMapPoints");
        if (!host) return;
        var mapId = Number(currentMapId || 0);
        var points = currentPoints.filter(function (point) {
            return mapId && Number(point.MapID || 0) === mapId &&
                point.MapX !== null && point.MapX !== undefined &&
                point.MapY !== null && point.MapY !== undefined;
        });
        host.innerHTML = points.map(function (point) {
            var status = getPointStatus(point);
            var code = String(point.PointCode || "");
            var x = Math.max(0, Math.min(100, Number(point.MapX) || 0));
            var y = Math.max(0, Math.min(100, Number(point.MapY) || 0));
            return '<button type="button" class="inspection-map-point ' + pointClass(status) + '" ' +
                'style="left:' + x + '%;top:' + y + '%" ' +
                'data-point-id="' + esc(point.InspectionPointID) + '" aria-label="' +
                esc(code + " " + (point.PointName || "")) + '" title="' +
                esc(code + " - " + (point.PointName || "") + " · " + statusLabel(status, point)) + '">' +
                '<span class="inspection-map-point-dot"></span>' +
                '<span class="inspection-map-point-label">' + esc(code) + '</span></button>';
        }).join("");

        host.querySelectorAll(".inspection-map-point").forEach(function (button) {
            button.addEventListener("click", function () {
                openPoint(button.getAttribute("data-point-id"));
            });
        });
    }

    function renderList() {
        var host = document.getElementById("inspectionPointList");
        if (!host) return;

        var all = getVisiblePoints();
        var keyword = String(listKeyword || "").trim().toLowerCase();
        var filtered = all.filter(function (point) {
            return !keyword ||
                String(point.PointCode || "").toLowerCase().indexOf(keyword) >= 0 ||
                String(point.PointName || "").toLowerCase().indexOf(keyword) >= 0 ||
                false;
        });
        var pageCount = Math.max(1, Math.ceil(filtered.length / listPageSize));
        listPage = Math.min(Math.max(1, listPage), pageCount);
        var start = (listPage - 1) * listPageSize;
        var rows = filtered.slice(start, start + listPageSize);

        host.innerHTML =
            '<div class="inspection-point-list-tools">' +
                '<div class="d-flex gap-2 align-items-center mb-2">' +
                    '<input type="search" id="inspectionPointSearch" class="form-control form-control-sm" ' +
                    'placeholder="Cari Point Code / Name..." value="' + esc(listKeyword) + '">' +
                    '<select id="inspectionPointPageSize" class="form-select form-select-sm" style="width:82px">' +
                        '<option value="10"' + (listPageSize === 10 ? ' selected' : '') + '>10</option>' +
                        '<option value="20"' + (listPageSize === 20 ? ' selected' : '') + '>20</option>' +
                        '<option value="50"' + (listPageSize === 50 ? ' selected' : '') + '>50</option>' +
                    '</select>' +
                '</div>' +
                '<div class="d-flex align-items-center justify-content-between small text-muted">' +
                    '<span>' + (filtered.length ? (start + 1) + '-' + Math.min(start + listPageSize, filtered.length) : 0) +
                    ' dari ' + filtered.length + ' point</span>' +
                    '<div class="btn-group btn-group-sm">' +
                        '<button type="button" class="btn btn-outline-secondary" id="inspectionPointPrev" ' + (listPage <= 1 ? 'disabled' : '') + '><i class="bi bi-chevron-left"></i></button>' +
                        '<span class="btn btn-outline-secondary disabled">' + listPage + ' / ' + pageCount + '</span>' +
                        '<button type="button" class="btn btn-outline-secondary" id="inspectionPointNext" ' + (listPage >= pageCount ? 'disabled' : '') + '><i class="bi bi-chevron-right"></i></button>' +
                    '</div>' +
                '</div>' +
            '</div>' +
            (rows.length ? rows.map(function (point) {
                var status = getPointStatus(point);
                return '<button type="button" class="inspection-point-list-row w-100 text-start" data-point-id="' +
                    esc(point.InspectionPointID) + '">' +
                    '<span class="inspection-map-point-dot ' + pointClass(status) + '"></span>' +
                    '<span class="point-main"><span class="point-code d-block">' + esc(point.PointCode) + '</span>' +
                    '<span class="point-name d-block">' + esc(point.PointName) + '</span></span>' +
                    '<span class="badge ' + (status === "DONE" ? "text-bg-success" :
                    status === "ABNORMAL" ? "text-bg-danger" :
                    status === "INCOMPLETE" ? "text-bg-warning" : "text-bg-secondary") + '">' +
                    statusLabel(status, point) + '</span><i class="bi bi-chevron-right text-muted"></i></button>';
            }).join("") : '<div class="text-muted small text-center py-4">Tidak ada Inspection Point yang cocok.</div>');

        host.querySelectorAll("[data-point-id]").forEach(function (button) {
            button.addEventListener("click", function () {
                openPoint(button.getAttribute("data-point-id"));
            });
        });
        var search = document.getElementById("inspectionPointSearch");
        if (search) search.addEventListener("input", function () {
            listKeyword = this.value;
            listPage = 1;
            renderList();
            var next = document.getElementById("inspectionPointSearch");
            if (next) { next.focus(); next.setSelectionRange(listKeyword.length, listKeyword.length); }
        });
        var size = document.getElementById("inspectionPointPageSize");
        if (size) size.addEventListener("change", function () {
            listPageSize = Number(this.value) || 20;
            listPage = 1;
            renderList();
        });
        var prev = document.getElementById("inspectionPointPrev");
        var next = document.getElementById("inspectionPointNext");
        if (prev) prev.addEventListener("click", function () { listPage--; renderList(); });
        if (next) next.addEventListener("click", function () { listPage++; renderList(); });

        var nextPending = document.getElementById("btnInspectionNextPending");
        if (nextPending) nextPending.addEventListener("click", function () {
            var point = findNextPendingPoint();
            if (!point) {
                if (typeof showInspectionNotice === "function")
                    showInspectionNotice("Tidak ada titik wajib atau checklist yang masih perlu diselesaikan.", "success");
                return;
            }
            openPoint(point.InspectionPointID);
            if (typeof window.openBatchInspectionPointChecklist === "function") {
                window.openBatchInspectionPointChecklist(point);
            }
        });
    }

    function updateSummary() {
        var points = getVisiblePoints();
        var done = points.filter(function (p) { return getPointStatus(p) === "DONE"; }).length;
        var abnormal = points.filter(function (p) { return getPointStatus(p) === "ABNORMAL"; }).length;
        var incomplete = points.filter(function (p) { return getPointStatus(p) === "INCOMPLETE"; }).length;
        var pending = points.filter(function (p) {
            return getPointStatus(p) === "PENDING" && pointRequiresInspection(p);
        }).length;
        var set = function (id, value) {
            var element = document.getElementById(id);
            if (element) element.textContent = String(value);
        };
        set("inspectionMapTotalCount", points.length);
        set("inspectionMapDoneCount", done);
        set("inspectionMapAbnormalCount", abnormal);
        set("inspectionMapPendingCount", pending + incomplete);
        var pendingLegend = document.getElementById("inspectionMapPendingLegend");
        if (pendingLegend) {
            var hasPartialMap = points.some(function (p) {
                return Number(p.MapID || 0) === Number(currentMapId || 0) && !pointRequiresInspection(p);
            });
            pendingLegend.textContent = hasPartialMap ? "Belum ada hasil" : "Belum diperiksa";
        }
    }

    function openPoint(id) {
        selectedPoint = currentPoints.find(function (point) {
            return String(point.InspectionPointID) === String(id);
        }) || null;
        if (!selectedPoint) return;

        document.querySelectorAll(".inspection-map-point").forEach(function (element) {
            element.classList.toggle("selected", element.getAttribute("data-point-id") === String(id));
        });

        var statusValue = getPointStatus(selectedPoint);
        var code = document.getElementById("inspectionMapPointCode");
        var name = document.getElementById("inspectionMapPointName");
        var meta = document.getElementById("inspectionMapPointMeta");
        var status = document.getElementById("inspectionMapPointStatus");
        var desc = document.getElementById("inspectionMapPointDescription");
        if (code) code.textContent = selectedPoint.PointCode || "";
        if (name) name.textContent = selectedPoint.PointName || "";
        if (meta) meta.textContent = (selectedPoint.PointObjectType || "GENERAL") +
            (selectedPoint.MapCode ? " · " + selectedPoint.MapCode : " · Tanpa denah");
        if (status) {
            status.className = "inspection-map-point-status mt-3 " +
                (statusValue === "ABNORMAL" ? "text-danger" : statusValue === "DONE" ? "text-success" :
                statusValue === "INCOMPLETE" ? "text-warning" : "text-secondary");
            status.textContent = statusLabel(statusValue, selectedPoint);
        }
        if (desc) desc.textContent = selectedPoint.PointDescription || selectedPoint.ObjectReferenceCode || "";
        var sheet = document.getElementById("inspectionMapPointSheet");
        if (sheet) sheet.classList.remove("d-none");
    }

    function closePoint() {
        selectedPoint = null;
        var sheet = document.getElementById("inspectionMapPointSheet");
        if (sheet) sheet.classList.add("d-none");
        document.querySelectorAll(".inspection-map-point.selected").forEach(function (element) {
            element.classList.remove("selected");
        });
    }

    function switchMapList(showList) {
        var canvas = document.getElementById("inspectionMapCanvas");
        var list = document.getElementById("inspectionPointList");
        var mapButton = document.getElementById("btnInspectionMapView");
        var listButton = document.getElementById("btnInspectionPointListView");
        if (!canvas || !list) return;
        var hasMap = currentMaps.some(function (map) {
            return Number(map.MapID) === Number(currentMapId) && !!map.MapUrl;
        });
        canvas.classList.toggle("d-none", showList || !hasMap);
        list.classList.toggle("d-none", !showList && hasMap);
        if (mapButton) {
            mapButton.classList.toggle("btn-primary", !showList && hasMap);
            mapButton.classList.toggle("btn-outline-primary", showList || !hasMap);
            mapButton.disabled = !hasMap;
        }
        if (listButton) {
            listButton.classList.toggle("btn-primary", showList || !hasMap);
            listButton.classList.toggle("btn-outline-primary", !showList && hasMap);
        }
    }

    function getMapElements() {
        return {
            viewport: document.getElementById("inspectionMapCanvas"),
            stage: document.getElementById("inspectionMapPdfStage"),
            points: document.getElementById("inspectionMapPoints"),
            zoomLabel: document.getElementById("inspectionMapZoomLabel")
        };
    }

    function applyMapTransform() {
        var elements = getMapElements();
        if (!elements.stage) return;
        elements.stage.style.transformOrigin = "center top";
        elements.stage.style.transform = "translate3d(" + mapPanX + "px," + mapPanY + "px,0) scale(" + mapZoom + ")";
        if (elements.points) elements.points.style.setProperty("--inspection-map-marker-scale", String(1 / mapZoom));
        if (elements.zoomLabel) elements.zoomLabel.textContent = Math.round(mapZoom * 100) + "%";
        var viewport = elements.viewport;
        if (viewport) viewport.classList.toggle("inspection-map-zoomed", mapZoom > 1.001);
    }

    function resetMapView() {
        mapZoom = 1;
        mapPanX = 0;
        mapPanY = 0;
        mapPointers = {};
        mapGesture = null;
        applyMapTransform();
    }

    function zoomMapTo(nextZoom, clientX, clientY) {
        var elements = getMapElements();
        if (!elements.viewport || !elements.stage) return;
        var rect = elements.viewport.getBoundingClientRect();
        var x = clientX == null ? rect.left + rect.width / 2 : clientX;
        var y = clientY == null ? rect.top + rect.height / 2 : clientY;
        var localX = x - rect.left - rect.width / 2;
        var localY = y - rect.top;
        var next = Math.max(mapMinZoom, Math.min(mapMaxZoom, nextZoom));
        if (Math.abs(next - mapZoom) < 0.001) return;
        var ratio = next / mapZoom;
        mapPanX = (mapPanX - localX) * ratio + localX;
        mapPanY = (mapPanY - localY) * ratio + localY;
        mapZoom = next;
        applyMapTransform();
    }

    function wireMapGestures() {
        var elements = getMapElements();
        var viewport = elements.viewport;
        if (!viewport || viewport.getAttribute("data-map-gestures") === "1") return;
        viewport.setAttribute("data-map-gestures", "1");

        viewport.addEventListener("wheel", function (event) {
            if (!currentPdfDocument && !document.querySelector('#inspectionMapPdfStage img.inspection-map-image')) return;
            event.preventDefault();
            var factor = event.deltaY < 0 ? 1.15 : 1 / 1.15;
            zoomMapTo(mapZoom * factor, event.clientX, event.clientY);
        }, { passive: false });

        viewport.addEventListener("pointerdown", function (event) {
            if ((!currentPdfDocument && !document.querySelector("#inspectionMapPdfStage img.inspection-map-image")) || (event.target.closest && event.target.closest(".inspection-map-point"))) return;
            if (event.pointerType === "mouse" && event.button !== 0) return;
            try { viewport.setPointerCapture(event.pointerId); } catch (_) { }
            mapPointers[event.pointerId] = { x: event.clientX, y: event.clientY };
            var ids = Object.keys(mapPointers);
            if (ids.length >= 2) {
                var p1 = mapPointers[ids[0]], p2 = mapPointers[ids[1]];
                var dx = p2.x - p1.x, dy = p2.y - p1.y;
                mapGesture = { type: "pinch", distance: Math.sqrt(dx * dx + dy * dy), zoom: mapZoom };
            } else {
                mapGesture = { type: "pan", x: event.clientX, y: event.clientY, panX: mapPanX, panY: mapPanY };
            }
        });

        viewport.addEventListener("pointermove", function (event) {
            if (!Object.prototype.hasOwnProperty.call(mapPointers, event.pointerId)) return;
            mapPointers[event.pointerId] = { x: event.clientX, y: event.clientY };
            var ids = Object.keys(mapPointers);
            if (ids.length >= 2) {
                var p1 = mapPointers[ids[0]], p2 = mapPointers[ids[1]];
                var dx = p2.x - p1.x, dy = p2.y - p1.y;
                var distance = Math.sqrt(dx * dx + dy * dy);
                if (mapGesture && mapGesture.type === "pinch" && mapGesture.distance > 0) {
                    var midpointX = (p1.x + p2.x) / 2;
                    var midpointY = (p1.y + p2.y) / 2;
                    zoomMapTo(mapGesture.zoom * (distance / mapGesture.distance), midpointX, midpointY);
                } else {
                    mapGesture = { type: "pinch", distance: distance, zoom: mapZoom };
                }
            } else if (mapGesture && mapGesture.type === "pan") {
                mapPanX = mapGesture.panX + event.clientX - mapGesture.x;
                mapPanY = mapGesture.panY + event.clientY - mapGesture.y;
                applyMapTransform();
            }
        });

        function finishPointer(event) {
            delete mapPointers[event.pointerId];
            var ids = Object.keys(mapPointers);
            if (ids.length === 1) {
                var p = mapPointers[ids[0]];
                mapGesture = { type: "pan", x: p.x, y: p.y, panX: mapPanX, panY: mapPanY };
            } else if (!ids.length) {
                mapGesture = null;
            }
        }
        viewport.addEventListener("pointerup", finishPointer);
        viewport.addEventListener("pointercancel", finishPointer);
        viewport.addEventListener("lostpointercapture", finishPointer);
    }

    async function renderPdf(map) {
        var message = document.getElementById('inspectionMapPdfMessage');
        var canvas = document.getElementById('inspectionMapPdfCanvas');
        var stage = document.getElementById('inspectionMapPdfStage');
        if (!canvas || !stage) return;
        resetMapView();
        if (currentPdfDocument && currentPdfDocument.destroy) { try { await currentPdfDocument.destroy(); } catch (_) { } currentPdfDocument = null; }
        var previousImage = stage.querySelector('img.inspection-map-image');
        if (previousImage) { if (previousImage.dataset.objectUrl) URL.revokeObjectURL(previousImage.dataset.objectUrl); previousImage.remove(); }
        var context = canvas.getContext('2d'); context.clearRect(0, 0, canvas.width, canvas.height); canvas.width = 0; canvas.height = 0;
        if (!map || !map.MapUrl) { if (message) { message.textContent = 'Denah belum tersedia. Gunakan tampilan List untuk memilih Inspection Point.'; message.classList.remove('d-none'); } stage.style.width = '100%'; stage.style.minHeight = '260px'; return; }
        try {
            if (message) { message.textContent = 'Memuat denah...'; message.classList.remove('d-none'); }
            var blob = map.MapBlob || map.PdfBlob || null;
            if (!blob || typeof blob.arrayBuffer !== 'function') {
                var response = await fetch(map.MapUrl, { credentials: 'same-origin' });
                if (!response.ok) throw new Error('HTTP ' + response.status);
                blob = await response.blob(); map.MapBlob = blob;
            }
            var mime = String(blob.type || '').toLowerCase();
            var urlPath = String(map.MapUrl).split('?')[0].toLowerCase();
            var isJpeg = mime.indexOf('image/jpeg') === 0 || /\.(jpg|jpeg)$/.test(urlPath);
            if (isJpeg) {
                canvas.style.display = 'none';
                var image = document.createElement('img'); image.className = 'inspection-map-image'; image.alt = 'Inspection floor plan'; image.draggable = false;
                stage.insertBefore(image, document.getElementById('inspectionMapPoints'));
                var objectUrl = URL.createObjectURL(blob); image.dataset.objectUrl = objectUrl;
                image.onload = function () {
                    var available = Math.max(300, Math.min(1200, document.getElementById('inspectionMapCanvas').clientWidth - 28));
                    image.style.width = available + 'px'; image.style.height = 'auto'; image.style.maxWidth = 'none'; image.style.display = 'block';
                    stage.style.width = available + 'px'; stage.style.minHeight = '0';
                    if (message) message.classList.add('d-none'); applyMapTransform(); renderPoints();
                };
                image.onerror = function () { if (message) { message.textContent = 'Gambar JPG/JPEG tidak dapat dibuka.'; message.classList.remove('d-none'); } };
                image.src = objectUrl; return;
            }
            canvas.style.display = 'block';
            if (!window.pdfjsLib) throw new Error('PDF.js belum termuat. Periksa file pdf.min.js.');
            window.pdfjsLib.GlobalWorkerOptions.workerSrc = '../JSCus/pdf.worker.min.js';
            currentPdfDocument = await window.pdfjsLib.getDocument({ data: new Uint8Array(await blob.arrayBuffer()) }).promise;
            var page = await currentPdfDocument.getPage(1); var base = page.getViewport({ scale: 1 });
            var width = Math.max(300, Math.min(1200, document.getElementById('inspectionMapCanvas').clientWidth - 28));
            var ratio = Math.min(window.devicePixelRatio || 1, 1.5); var viewport = page.getViewport({ scale: (width / base.width) * ratio });
            canvas.width = Math.floor(viewport.width); canvas.height = Math.floor(viewport.height);
            canvas.style.width = Math.floor(viewport.width / ratio) + 'px'; canvas.style.height = Math.floor(viewport.height / ratio) + 'px';
            stage.style.width = canvas.style.width; stage.style.minHeight = '0';
            await page.render({ canvasContext: context, viewport: viewport }).promise;
            if (message) message.classList.add('d-none'); applyMapTransform(); renderPoints();
        } catch (error) {
            console.error('Inspection map render failed:', error);
            if (message) { message.textContent = 'Denah gagal dimuat: ' + (error && error.message ? error.message : 'periksa file map.'); message.classList.remove('d-none'); }
        }
    }
    function renderMapOptions() {
        var wrap = document.getElementById("inspectionMapSelectWrap");
        var select = document.getElementById("inspectionMapSelect");
        if (!select || !wrap) return;
        var maps = currentMaps.filter(function (map) { return !!map.MapUrl; });
        wrap.classList.toggle("d-none", maps.length <= 1);
        select.innerHTML = maps.map(function (map) {
            return '<option value="' + esc(map.MapID) + '">' + esc(map.MapCode + " - " + map.MapName + " (v" + map.MapVersion + ")") + '</option>';
        }).join("");
        if (maps.length) {
            if (!maps.some(function (map) { return Number(map.MapID) === Number(currentMapId); }))
                currentMapId = String(maps[0].MapID);
            select.value = currentMapId;
        } else {
            currentMapId = "";
            select.innerHTML = '<option value="">Tanpa denah</option>';
        }
    }

    window.showInspectionMapWorkspace = function (record, activate) {
        if (record) currentMapRecord = record;
        record = record || currentMapRecord;
        var workspace = document.getElementById("inspectionMapWorkspace");
        if (!workspace || !record) return;
        if (typeof window.mountInspectionBatchSummary === "function")
            window.mountInspectionBatchSummary(record);

        var setup = record.BatchMapSetup || {};
        currentMaps = Array.isArray(setup.maps) ? setup.maps : [];
        currentPoints = Array.isArray(setup.points) ? setup.points : [];
        if (!currentPoints.length && Array.isArray(record.PointMaster)) currentPoints = record.PointMaster;
        if (!currentMapId && currentMaps.length) currentMapId = String(currentMaps[0].MapID);
        renderMapOptions();

        var nextPendingButton = document.getElementById("btnInspectionNextPending");
        if (nextPendingButton) nextPendingButton.classList.toggle("d-none", String(record.Status || "").toUpperCase() === "DONE");

        var submitBatchButton = document.getElementById("btnSubmitInspectionBatch");
        if (submitBatchButton) submitBatchButton.classList.toggle("d-none", String(record.Status || "").toUpperCase() === "DONE");

        var typeName = record.InspectionTypeName || "Inspection";
        var detailName = record.InspectionTypeDetailName || "";
        var title = document.getElementById("inspectionMapTitle");
        var subtitle = document.getElementById("inspectionMapSubtitle");
        if (title) title.textContent = typeName + (detailName ? " · " + detailName : "");
        if (subtitle) subtitle.textContent = "Batch " + (record.InspectionNo || "baru") +
            " · " + currentPoints.length + " Unit Inspeksi";

        renderList();
        updateSummary();
        renderPoints();
        var selectedMap = currentMaps.find(function (map) {
            return Number(map.MapID) === Number(currentMapId);
        }) || null;
        renderPdf(selectedMap);

        if (activate) {
            workspace.classList.remove("d-none");
            var paramPane = document.getElementById("inspectionParamsPane");
            var checklistPane = document.getElementById("inspectionChecklistPane");
            if (paramPane) paramPane.classList.add("d-none");
            if (checklistPane) checklistPane.classList.add("d-none");
            var mapTab = document.getElementById("btnInspectionMapTab");
            var paramTab = document.getElementById("btnInspectionParamTab");
            var checklistTab = document.getElementById("btnInspectionChecklistTab");
            if (mapTab) mapTab.classList.add("active");
            if (paramTab) paramTab.classList.remove("active");
            if (checklistTab) checklistTab.classList.remove("active");
            closePoint();
            switchMapList(false);
        }
    };

    window.refreshInspectionMapPointStatuses = function () {
        renderPoints();
        renderList();
        updateSummary();
    };

    window.getSelectedInspectionMapPoint = function () {
        return selectedPoint;
    };

    window.wireInspectionMapWorkspace = function () {
        if (wired) return;
        wired = true;

        wireMapGestures();
        var zoomIn = document.getElementById("btnInspectionMapZoomIn");
        var zoomOut = document.getElementById("btnInspectionMapZoomOut");
        var zoomReset = document.getElementById("btnInspectionMapZoomReset");
        if (zoomIn) zoomIn.addEventListener("click", function () { zoomMapTo(mapZoom * 1.25); });
        if (zoomOut) zoomOut.addEventListener("click", function () { zoomMapTo(mapZoom / 1.25); });
        if (zoomReset) zoomReset.addEventListener("click", resetMapView);

        var mapTab = document.getElementById("btnInspectionMapTab");
        if (mapTab) mapTab.addEventListener("click", async function () {
            if (currentMapRecord && Number(currentMapRecord.ActiveInspectionPointID || 0) > 0 &&
                typeof window.saveBatchInspectionPoint === "function") {
                await window.saveBatchInspectionPoint("DRAFT");
                return;
            }
            if (window.showInspectionMapWorkspace) window.showInspectionMapWorkspace(currentMapRecord, true);
        });

        var checklistTab = document.getElementById("btnInspectionChecklistTab");
        if (checklistTab) checklistTab.addEventListener("click", function () {
            if (currentMapRecord && String(currentMapRecord.InspectionMode || "").toUpperCase() === "BATCH" &&
                !Number(currentMapRecord.ActiveInspectionPointID || 0)) {
                if (typeof showInspectionNotice === "function")
                    showInspectionNotice("Pilih Inspection Point dari denah atau daftar terlebih dahulu.", "info");
                return;
            }
            var workspace = document.getElementById("inspectionMapWorkspace");
            if (workspace) workspace.classList.add("d-none");
        });

        var paramTab = document.getElementById("btnInspectionParamTab");
        if (paramTab) paramTab.addEventListener("click", function () {
            var workspace = document.getElementById("inspectionMapWorkspace");
            if (workspace) workspace.classList.add("d-none");
        });

        var close = document.getElementById("btnCloseInspectionMapPoint");
        if (close) close.addEventListener("click", closePoint);
        var mapView = document.getElementById("btnInspectionMapView");
        var listView = document.getElementById("btnInspectionPointListView");
        if (mapView) mapView.addEventListener("click", function () { switchMapList(false); });
        if (listView) listView.addEventListener("click", function () { switchMapList(true); closePoint(); });

        var reset = document.getElementById("btnInspectionMapReset");
        if (reset) reset.addEventListener("click", function () {
            switchMapList(false);
            closePoint();
            resetMapView();
        });

        var mapSelect = document.getElementById("inspectionMapSelect");
        if (mapSelect) mapSelect.addEventListener("change", function () {
            currentMapId = this.value;
            resetMapView();
            listPage = 1;
            renderList();
            updateSummary();
            var map = currentMaps.find(function (item) { return Number(item.MapID) === Number(currentMapId); });
            renderPdf(map || null);
        });

        var openChecklist = document.getElementById("btnOpenInspectionPointChecklist");
        if (openChecklist) openChecklist.addEventListener("click", function () {
            if (!selectedPoint) return;
            var point = selectedPoint;
            closePoint();
            if (typeof window.openBatchInspectionPointChecklist === "function") {
                window.openBatchInspectionPointChecklist(point);
            } else {
                if (typeof showInspectionNotice === "function")
                    showInspectionNotice("Modul checklist per titik belum siap dibuka.", "warning");
            }
        });

        var submit = document.getElementById("btnSubmitInspectionBatch");
        if (submit) submit.addEventListener("click", function () {
            if (typeof window.submitInspectionBatch === "function") window.submitInspectionBatch();
            else if (typeof showInspectionNotice === "function")
                showInspectionNotice("Submit batch belum tersedia.", "warning");
        });
    };

    document.addEventListener("DOMContentLoaded", function () {
        window.setTimeout(function () {
            if (typeof window.wireInspectionMapWorkspace === "function")
                window.wireInspectionMapWorkspace();
        }, 0);
    });
})();
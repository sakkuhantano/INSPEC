(function () {
    "use strict";

    var wired = false;
    var selectedPoint = null;
    var currentMapRecord = null;
    var currentScheduleTime = "";
    var currentMaps = [];
    var currentPoints = [];
    var currentMapId = "";
    var currentPdfDocument = null;
    var currentPdfPage = null;
    var currentPdfFitScale = 1;
    var pdfCanvasRenderTask = null;
    var pdfCanvasRenderTimer = null;
    var pdfCanvasRenderSequence = 0;
    var pdfRenderSequence = 0;
    var listPage = 1;
    var listPageSize = 20;
    var listKeyword = "";
    var navigatorFocusDismissedPointId = "";
    var navigatorFocusPendingPointId = "";
    var navigatorFocusRequestSequence = 0;
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

    function flagEnabled(value) {
        return value === true || value === 1 || value === "1" ||
            String(value == null ? "" : value).toLowerCase() === "true";
    }

    function normalizedStatus(status) {
        status = String(status || "PENDING").toUpperCase();
        if (status === "DONE" || status === "INSPECTED" || status === "ABNORMAL") return "DONE";
        if (status === "INCOMPLETE") return "INCOMPLETE";
        return "PENDING";
    }

    function pointClass(status) {
        return String(status || "").toUpperCase() === "ABNORMAL" ? "abnormal" : normalizedStatus(status).toLowerCase();
    }

    function statusLabel(status, point) {
        if (String(status || "").toUpperCase() === "ABNORMAL") return "ABNORMAL";
        var value = normalizedStatus(status);
        return value === "DONE" ? "SELESAI" :
            value === "INCOMPLETE" ? "BELUM LENGKAP" : "BELUM DIPERIKSA";
    }

    function statusSymbol(status) {
        if (String(status || "").toUpperCase() === "ABNORMAL") return "!";
        var value = normalizedStatus(status);
        return value === "DONE" ? "✓" : value === "INCOMPLETE" ? "…" : "·";
    }

    function getActiveScheduleTime() {
        if (!currentMapRecord || !(String(currentMapRecord.InspectionMode || "").toUpperCase() === "BATCH" && String(currentMapRecord.ScheduleSelectionMode || "").toUpperCase() === "INSPECT")) return "";
        var schedules = Array.isArray(currentMapRecord.Schedules) ? currentMapRecord.Schedules : [];
        var active = String(currentMapRecord.ActiveScheduleTime || currentScheduleTime || "");
        if (!schedules.some(function (item) { return String(item.ScheduleTime || item) === active; }))
            active = String(schedules.length ? (schedules[0].ScheduleTime || schedules[0]) : "");
        currentScheduleTime = active;
        return active;
    }

    function renderLightningScheduleTabs() {
        var host = document.getElementById("inspectionLightningScheduleTabs");
        if (!host) return;
        var lightning = currentMapRecord && (String(currentMapRecord.InspectionMode || "").toUpperCase() === "BATCH" && String(currentMapRecord.ScheduleSelectionMode || "").toUpperCase() === "INSPECT");
        host.classList.toggle("d-none", !lightning);
        if (!lightning) { host.innerHTML = ""; currentScheduleTime = ""; return; }
        var schedules = Array.isArray(currentMapRecord.Schedules) ? currentMapRecord.Schedules : [];
        if (!currentScheduleTime || !schedules.some(function (item) { return String(item.ScheduleTime || item) === currentScheduleTime; }))
            currentScheduleTime = String(currentMapRecord.ActiveScheduleTime || (schedules.length ? (schedules[0].ScheduleTime || schedules[0]) : ""));
        host.innerHTML = schedules.map(function (item) {
            var time = String(item.ScheduleTime || item);
            var count = (currentMapRecord.Points || []).filter(function (point) {
                return String(point.ScheduleTime || "") === time &&
                    ["DONE", "ABNORMAL"].indexOf(String(point.Status || "").toUpperCase()) >= 0;
            }).length;
            var total = (currentMapRecord.BatchMapSetup && currentMapRecord.BatchMapSetup.points || []).length;
            return '<button type="button" class="nav-link' + (time === currentScheduleTime ? ' active' : '') +
                '" data-lightning-schedule="' + esc(time) + '" aria-current="' + (time === currentScheduleTime ? 'page' : 'false') + '">' +
                '<span class="fw-semibold">' + esc(time) + '</span> <span class="small opacity-75">' + count + '/' + total + '</span></button>';
        }).join("");
        host.querySelectorAll("[data-lightning-schedule]").forEach(function (button) {
            button.addEventListener("click", function () {
                var next = button.getAttribute("data-lightning-schedule");
                if (!next || next === currentScheduleTime) return;
                currentScheduleTime = next;
                if (typeof window.setInspectionActiveScheduleTime === "function")
                    window.setInspectionActiveScheduleTime(next);
                else if (currentMapRecord) currentMapRecord.ActiveScheduleTime = next;
                closePoint();
                listPage = 1;
                listKeyword = "";
                renderLightningScheduleTabs();

                // Every schedule change returns the operator to the first map.
                // Point status and checklist transactions still resolve against
                // the newly selected schedule through getActiveScheduleTime().
                if (currentMaps.length) {
                    showSelectedInspectionMap(currentMaps[0].MapID, false);
                } else {
                    renderList();
                    updateSummary();
                    renderPoints();
                }

                var subtitle = document.getElementById("inspectionMapSubtitle");
                if (subtitle) subtitle.textContent = "Jadwal " + next + " · " + currentPoints.length + " titik inspeksi";
            });
        });
    }

    function getPointTransaction(point) {
        if (!currentMapRecord || !Array.isArray(currentMapRecord.Points)) return null;
        var scheduleTime = getActiveScheduleTime();
        return currentMapRecord.Points.find(function (item) {
            return Number(item.InspectionPointID) === Number(point.InspectionPointID) &&
                String(item.ScheduleTime || "") === scheduleTime;
        }) || null;
    }

    function getPointStatus(point) {
        var transaction = getPointTransaction(point);
        return normalizedStatus(transaction && transaction.Status);
    }

    function isNormalAbnormalRequired(point) {
        var value = point && point.IsNormalAbnormalRequired;
        return value === true || value === 1 || value === "1" ||
            String(value || "").trim().toUpperCase() === "Y" ||
            String(value || "").trim().toUpperCase() === "TRUE";
    }

    function getPointVisualStatus(point) {
        // The master-map flag controls whether this point may be classified as abnormal.
        if (!isNormalAbnormalRequired(point)) return getPointStatus(point);
        var transaction = getPointTransaction(point);
        if (transaction && String(transaction.AbnormalRemark || "").trim()) return "ABNORMAL";
        var template = currentMapRecord && currentMapRecord.TemplateSnapshot;
        var templateItems = [];
        (template && Array.isArray(template.sections) ? template.sections : []).forEach(function (section) {
            (section.items || []).forEach(function (item) { templateItems.push(item); });
        });
        if (templateItems.length === 1 && String(templateItems[0].type || "").toUpperCase() === "OPTION") {
            var answer = transaction && (transaction.Items || []).find(function (item) {
                return Number(item.IDItem) === Number(templateItems[0].idItem);
            });
            var value = String(answer && answer.Value || "").trim().toUpperCase();
            if (/^(OFF|MATI|NO|RUSAK|ABNORMAL|TIDAK|NOT OK)$/.test(value)) return "ABNORMAL";
            if (value) return "DONE";
        }
        return getPointStatus(point);
    }

    function getTemplateOptionItems() {
        var template = currentMapRecord && currentMapRecord.TemplateSnapshot;
        var result = [];
        (template && Array.isArray(template.sections) ? template.sections : []).forEach(function (section) {
            (section.items || []).forEach(function (item) {
                if (String(item.type || "").toUpperCase() === "OPTION") result.push(item);
            });
        });
        return result;
    }

    function renderPointOptionControls(point) {
        var optionItems = getTemplateOptionItems();
        if (!optionItems.length) return "";
        var transaction = getPointTransaction(point);
        var savedItems = transaction && Array.isArray(transaction.Items) ? transaction.Items : [];
        var readOnly = String(currentMapRecord && currentMapRecord.Status || "").toUpperCase() === "DONE";
        var blockReason = typeof window.getBatchPointQuickOptionBlockReason === "function"
            ? window.getBatchPointQuickOptionBlockReason(point) : "";
        return '<div class="inspection-point-option-controls mt-1 d-flex flex-column gap-1">' +
            optionItems.map(function (item) {
                var saved = savedItems.find(function (answer) { return Number(answer.IDItem) === Number(item.idItem); });
                var selected = String(saved && saved.Value || "");
                var options = String(item.optionList || "").split(";").map(function (value) { return value.trim(); }).filter(Boolean);
                if (!options.length) return "";
                var snapshot = currentMapRecord && currentMapRecord.TemplateSnapshot;
                var versionInfo = snapshot && (snapshot.VersionInfo || snapshot.versionInfo || snapshot);
                var versionRemark1 = flagEnabled(item.versionIsRemark1Required) ||
                    flagEnabled(item.VersionIsRemark1Required) || flagEnabled(versionInfo && versionInfo.VersionIsRemark1Required) ||
                    flagEnabled(versionInfo && versionInfo.IsRemark1Required);
                var versionRemark2 = flagEnabled(item.versionIsRemark2Required) ||
                    flagEnabled(item.VersionIsRemark2Required) || flagEnabled(versionInfo && versionInfo.VersionIsRemark2Required) ||
                    flagEnabled(versionInfo && versionInfo.IsRemark2Required);
                var rawRemarkOptions = item.remarkRequiredOptions || item.RemarkRequiredOptions || [];
                var remarkOptions = Array.isArray(rawRemarkOptions) ? rawRemarkOptions.map(function (x) { return String(x).trim(); }) :
                    String(rawRemarkOptions || "").split(";").map(function (x) { return x.trim(); }).filter(Boolean);
                var optionRequiresRemark = remarkOptions.indexOf(selected.trim()) >= 0;
                var remarkHtml = "";
                [1, 2].forEach(function (number) {
                    var versionEnabled = number === 1 ? versionRemark1 : versionRemark2;
                    var itemRequired = number === 1
                        ? (flagEnabled(item.isRemark1Required) || flagEnabled(item.IsRemark1Required))
                        : (flagEnabled(item.isRemark2Required) || flagEnabled(item.IsRemark2Required));
                    var mandatory = number === 1
                        ? (flagEnabled(item.isRemark1Mandatory) || flagEnabled(item.IsRemark1Mandatory))
                        : (flagEnabled(item.isRemark2Mandatory) || flagEnabled(item.IsRemark2Mandatory));
                    var text = number === 1
                        ? (item.remark1Text || item.Remark1Text)
                        : (item.remark2Text || item.Remark2Text);
                    var field = number === 1 ? "Remark1" : "Remark2";
                    if (!(itemRequired || (versionEnabled && remarkOptions.length))) return;
                    var visible = itemRequired || (versionEnabled && optionRequiresRemark);
                    var inputRequired = visible && (!!mandatory || optionRequiresRemark);
                    var value = saved && saved[field] != null ? saved[field] : "";
                    remarkHtml += '<div class="inspection-point-remark' + (visible ? "" : " d-none") + '">' +
                        '<label class="small text-muted mb-1">' + esc(text || "Remark" + number) +
                        (inputRequired ? ' (wajib)' : '') + '</label>' +
                        '<input type="text" maxlength="500" class="form-control form-control-sm" ' +
                        'data-point-remark-item="' + esc(item.idItem) + '" data-point-remark-field="' + number +
                        '" data-point-id="' + esc(point.InspectionPointID) + '" value="' + esc(value) + '"' +
                        (readOnly ? " disabled" : "") + (inputRequired ? " required" : "") + '></div>';
                });
                return '<div class="inspection-point-option-group">' +
                    '<div class="small text-muted mb-1">' + esc(item.label || "Checklist") + '</div>' +
                    '<div class="d-flex flex-wrap gap-1">' + options.map(function (option) {
                        var active = selected === option;
                        return '<button type="button" class="btn btn-sm ' +
                            (active ? 'btn-primary' : 'btn-outline-primary') +
                            ' inspection-point-option-choice" ' + ((readOnly || blockReason) ? 'disabled aria-disabled="true" title="' + esc(blockReason || "Inspection sudah read-only.") + '" ' : '') +
                            'data-point-option-item="' + esc(item.idItem) +
                            '" data-point-option-value="' + esc(option) + '" data-point-id="' +
                            esc(point.InspectionPointID) + '">' + esc(option) + '</button>';
                    }).join("") + '</div>' + remarkHtml + '</div>';
            }).join("") + '</div>';
    }

    function pointRequiresInspection(point) {
        if (!point || point.RequireAllPoints === undefined || point.RequireAllPoints === null) return true;
        return !(point.RequireAllPoints === false || point.RequireAllPoints === 0 ||
            String(point.RequireAllPoints).toLowerCase() === "false" || String(point.RequireAllPoints) === "0");
    }

    function getVisiblePoints() {
        if (currentMapRecord && String(currentMapRecord.InspectionLayoutCode || '').toUpperCase() === 'DYNAMIC_LIST' && String(currentMapRecord.InspectionPointMode || '').toUpperCase() === 'DYNAMIC') return currentPoints.slice();
        if (!currentMapId) return [];
        return currentPoints.filter(function (point) { return Number(point.MapID || 0) === Number(currentMapId); });
    }

    function findNextPendingPoint() {
        var pending = getVisiblePoints().filter(function (point) {
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

    function getPointMapFocusPosition(point) {
        var x = Math.max(0, Math.min(100, Number(point && point.MapX) || 0));
        var y = Math.max(0, Math.min(100, Number(point && point.MapY) || 0));
        var shapeType = String(point && point.ShapeType || "CIRCLE").toUpperCase();
        if (shapeType === "RECTANGLE" || shapeType === "RECT") {
            var shape = {};
            try {
                shape = typeof point.ShapeAttributes === "string"
                    ? JSON.parse(point.ShapeAttributes || "{}")
                    : (point.ShapeAttributes || {});
            } catch (_) {
                shape = {};
            }
            var width = Number(shape.width || shape.w || shape.widthPercent || 0);
            var height = Number(shape.height || shape.h || shape.heightPercent || 0);
            if (isFinite(width) && width > 0 && isFinite(height) && height > 0) {
                var left = isFinite(Number(shape.x)) ? Number(shape.x) :
                    (isFinite(Number(shape.left)) ? Number(shape.left) :
                    (isFinite(Number(shape.x1)) ? Number(shape.x1) : x - width / 2));
                var top = isFinite(Number(shape.y)) ? Number(shape.y) :
                    (isFinite(Number(shape.top)) ? Number(shape.top) :
                    (isFinite(Number(shape.y1)) ? Number(shape.y1) : y - height / 2));
                x = left + width / 2;
                y = top + height / 2;
            }
        }
        return { x: Math.max(0, Math.min(100, x)), y: Math.max(0, Math.min(100, y)) };
    }

    function removeNavigatorFocusRing(pointId) {
        if (pointId !== undefined && pointId !== null)
            navigatorFocusDismissedPointId = String(pointId);
        var pointHost = document.getElementById("inspectionMapPoints");
        if (!pointHost) return;
        var ring = pointHost.querySelector(".inspection-map-navigator-focus-ring");
        if (ring) {
            if (pointId === undefined || pointId === null)
                navigatorFocusDismissedPointId = String(ring.getAttribute("data-navigator-target") || "");
            ring.remove();
        }
    }

    function inspectionMapDistanceToPathScreen(path, svg, clientX, clientY) {
        if (!path || !svg || typeof path.getTotalLength !== "function" ||
            typeof path.getPointAtLength !== "function") return Infinity;
        var total = 0;
        try { total = path.getTotalLength(); } catch (_) { return Infinity; }
        if (!isFinite(total) || total <= 0) return Infinity;

        var ctm;
        try { ctm = path.getScreenCTM(); } catch (_) { ctm = null; }
        if (!ctm) return Infinity;

        var samples = Math.max(12, Math.min(160, Math.ceil(total / 18)));
        var best = Infinity;
        for (var i = 0; i <= samples; i++) {
            var p;
            try { p = path.getPointAtLength(total * i / samples); } catch (_) { continue; }
            var screen = new DOMPoint(p.x, p.y).matrixTransform(ctm);
            var dx = screen.x - clientX, dy = screen.y - clientY;
            var d = Math.sqrt(dx * dx + dy * dy);
            if (d < best) best = d;
        }
        return best;
    }

    function resolveInspectionMapPointIdFromGeometry(clickedShape, clientX, clientY) {
        var overlay = document.getElementById("inspectionMapPoints");
        var svg = overlay && overlay.querySelector(".inspection-map-svg-overlay");
        if (!svg) return clickedShape && clickedShape.getAttribute("data-point-id");

        var clickedId = clickedShape && clickedShape.getAttribute
            ? clickedShape.getAttribute("data-point-id") : "";
        var paths = Array.prototype.slice.call(
            svg.querySelectorAll(".inspection-map-svg-path[data-point-id]")
        );
        if (!paths.length) return clickedId;

        // Closed PATHs are resolved by the actual SVG fill geometry first.
        // This avoids any dependency on DOM paint order or overlapping hit boxes.
        try {
            var inverse = svg.getScreenCTM().inverse();
            var point = svg.createSVGPoint();
            point.x = clientX;
            point.y = clientY;
            point = point.matrixTransform(inverse);

            var containing = [];
            paths.forEach(function (path) {
                if (!/[Zz]/.test(path.getAttribute("d") || "") ||
                    typeof path.isPointInFill !== "function") return;
                try {
                    if (path.isPointInFill(point)) {
                        var box = path.getBBox();
                        containing.push({
                            id: path.getAttribute("data-point-id"),
                            area: Math.max(0, box.width) * Math.max(0, box.height)
                        });
                    }
                } catch (_) { }
            });
            if (containing.length) {
                containing.sort(function (a, b) { return a.area - b.area; });
                return containing[0].id || clickedId;
            }
        } catch (_) { }

        // Open PATHs and border clicks use the nearest real visible geometry.
        // The tolerance is deliberately in CSS pixels, so it remains stable
        // while the map is zoomed/panned.
        var nearestId = clickedId;
        var nearestDistance = Infinity;
        paths.forEach(function (path) {
            var distance = inspectionMapDistanceToPathScreen(path, svg, clientX, clientY);
            if (distance < nearestDistance) {
                nearestDistance = distance;
                nearestId = path.getAttribute("data-point-id") || clickedId;
            }
        });
        return nearestDistance <= 18 ? nearestId : clickedId;
    }

    function renderPoints() {
        var host = document.getElementById("inspectionMapPoints");
        if (!host) return;
        if (host.getAttribute("data-point-click-wired") !== "1") {
            /* Delegate from the stable overlay host. renderPoints() replaces
               the SVG and marker buttons on every refresh, so direct listeners
               attached to individual nodes are easy to lose. */
            host.addEventListener("click", function (event) {
                var shape = event.target && event.target.closest
                    ? event.target.closest("[data-point-id]") : null;
                if (!shape || !host.contains(shape)) return;
                event.preventDefault();
                event.stopPropagation();
                removeNavigatorFocusRing();
                var pointId = resolveInspectionMapPointIdFromGeometry(
                    shape,
                    event.clientX,
                    event.clientY
                );
                openPoint(pointId || shape.getAttribute("data-point-id"));
            });
            host.addEventListener("keydown", function (event) {
                if (event.key !== "Enter" && event.key !== " ") return;
                var shape = event.target && event.target.closest
                    ? event.target.closest("[data-point-id]") : null;
                if (!shape || !host.contains(shape)) return;
                event.preventDefault();
                event.stopPropagation();
                removeNavigatorFocusRing();
                openPoint(shape.getAttribute("data-point-id"));
            });
            host.setAttribute("data-point-click-wired", "1");
        }
        var mapViewport = document.getElementById("inspectionMapCanvas");
        if (mapViewport && mapViewport.getAttribute("data-navigator-dismiss-wired") !== "1") {
            // Any deliberate click on the floor-plan viewport dismisses the
            // Navigator pulse. Marker clicks continue to their own handlers.
            mapViewport.addEventListener("click", function (event) {
                if (event.target && event.target.closest &&
                    event.target.closest(".inspection-map-zoom-tools")) return;
                navigatorFocusRequestSequence++;
                navigatorFocusPendingPointId = "";
                removeNavigatorFocusRing();
            }, true);
            mapViewport.setAttribute("data-navigator-dismiss-wired", "1");
        }
        var mapId = Number(currentMapId || 0);
        var points = currentPoints.filter(function (point) {
            return mapId && Number(point.MapID || 0) === mapId &&
                point.MapX !== null && point.MapX !== undefined &&
                point.MapY !== null && point.MapY !== undefined;
        });
        var svg = ['<svg class="inspection-map-svg-overlay" viewBox="0 0 100 100" preserveAspectRatio="none" aria-label="Inspection point vector shapes">'];
        var circleMarkers = [];
        points.forEach(function (point) {
            var status = getPointVisualStatus(point);
            var code = String(point.PointCode || "");
            var pointName = String(point.PointName || "");
            var title = code + " - " + pointName + " · " + statusLabel(status, point);
            var pointShapeType = String(point.ShapeType || point.shapeType || "CIRCLE").toUpperCase();
            var pointPathData = String(point.SvgPathData || point.svgPathData || "").trim();
            // Prefer explicit PATH type, but also accept geometry supplied by a
            // cached/older payload whose ShapeType property may be missing.
            if ((pointShapeType === "PATH" || pointPathData) && pointPathData) {
                var shapeAttributes = {};
                try { shapeAttributes = typeof point.ShapeAttributes === "string" ? JSON.parse(point.ShapeAttributes || "{}") : (point.ShapeAttributes || {}); } catch (_) { shapeAttributes = {}; }
                var renderMode = String(shapeAttributes.renderMode || "").toUpperCase();
                var isOrthogonal = renderMode === "ORTHOGONAL";
                // Imported StrokeWidth is expressed in source-image coordinates
                // and becomes tiny after normalization. Use screen-pixel strokes
                // so outlines remain visible at every map zoom level.
                var strokeWidth = isOrthogonal ? 2.0 : 1.25;
                var pathFill = 'none';
                var pathStroke = '#0d6efd';
                svg.push('<path class="inspection-map-svg-path ' + pointClass(status) + (selectedPoint && String(selectedPoint.InspectionPointID) === String(point.InspectionPointID) ? " selected" : "") + '" d="' +
                    esc(pointPathData) + '" fill="' + pathFill + '" stroke="' + pathStroke +
                    '" stroke-linecap="round" stroke-linejoin="round" stroke-width="' + strokeWidth +
                    '" vector-effect="non-scaling-stroke" data-point-id="' +
                    esc(point.InspectionPointID) + '" role="button" tabindex="0" aria-label="' +
                    esc(title) + '" title="' + esc(title) + '"><title>' + esc(title) + '</title></path>');
                return;
            }
            var x = Math.max(0, Math.min(100, Number(point.MapX) || 0));
            var y = Math.max(0, Math.min(100, Number(point.MapY) || 0));
            var shape = {};
            try { shape = typeof point.ShapeAttributes === "string" ? JSON.parse(point.ShapeAttributes || "{}") : (point.ShapeAttributes || {}); } catch (_) { shape = {}; }
            var shapeType = String(point.ShapeType || "CIRCLE").toUpperCase();
            if (shapeType === "RECTANGLE" || shapeType === "RECT") {
                var rectWidth = Number(shape.width || shape.w || shape.widthPercent || 0);
                var rectHeight = Number(shape.height || shape.h || shape.heightPercent || 0);
                rectWidth = Math.max(0.2, Math.min(100, isFinite(rectWidth) && rectWidth > 0 ? rectWidth : 3));
                rectHeight = Math.max(0.2, Math.min(100, isFinite(rectHeight) && rectHeight > 0 ? rectHeight : 3));
                var rectLeft = isFinite(Number(shape.x)) ? Number(shape.x) :
                    (isFinite(Number(shape.left)) ? Number(shape.left) :
                    (isFinite(Number(shape.x1)) ? Number(shape.x1) : x - rectWidth / 2));
                var rectTop = isFinite(Number(shape.y)) ? Number(shape.y) :
                    (isFinite(Number(shape.top)) ? Number(shape.top) :
                    (isFinite(Number(shape.y1)) ? Number(shape.y1) : y - rectHeight / 2));
                rectLeft = Math.max(0, Math.min(100 - rectWidth, rectLeft));
                rectTop = Math.max(0, Math.min(100 - rectHeight, rectTop));
                svg.push('<rect class="inspection-map-svg-rect ' + pointClass(status) +
                    '" x="' + rectLeft + '" y="' + rectTop + '" width="' + rectWidth +
                    '" height="' + rectHeight + '" data-point-id="' + esc(point.InspectionPointID) +
                    '" role="button" tabindex="0" aria-label="' + esc(title) + '" title="' + esc(title) +
                    '"><title>' + esc(title) + '</title></rect>');
                return;
            }
            var cx = isFinite(Number(shape.cx)) ? Math.max(0, Math.min(100, Number(shape.cx))) : x;
            var cy = isFinite(Number(shape.cy)) ? Math.max(0, Math.min(100, Number(shape.cy))) : y;
            // CIRCLE is a point dot; use PATH for larger vector areas.
            var radius = Math.max(3.0, Math.min(50, Number(shape.r) || 3.0));
            var circleAspect = host.clientWidth && host.clientHeight ? host.clientWidth / host.clientHeight : 1;
            var circleTransform = 'translate(' + cx + ' ' + cy + ') scale(1 ' + circleAspect + ') translate(' + (-cx) + ' ' + (-cy) + ')';
            svg.push('<circle class="inspection-map-svg-circle ' + pointClass(status) + '" cx="' + cx + '" cy="' + cy + '" r="' + radius + '" transform="' + circleTransform + '" data-point-id="' + esc(point.InspectionPointID) + '" role="button" tabindex="0" aria-label="' + esc(title) + '" title="' + esc(title) + '"><title>' + esc(title) + '</title></circle>');
            circleMarkers.push('<button type="button" class="inspection-map-point ' + pointClass(status) + '" ' +
                'style="left:' + x + '%;top:' + y + '%" data-point-id="' + esc(point.InspectionPointID) +
                '" aria-label="' + esc(title) + '" title="' + esc(title) + '">' +
                '<span class="inspection-map-point-dot">' + statusSymbol(status) + '</span>' +
                '<span class="inspection-map-point-label">' + esc(code) + '</span></button>');
        });
        svg.push('</svg>');
        host.innerHTML = svg.join("") + circleMarkers.join("");

        // Do NOT create transparent bounding-box hit targets for PATHs.
        // Adjacent PATH bounding boxes can overlap, and SVG paint order then makes
        // a click on one visible PATH resolve to a neighboring PATH. Selection is
        // resolved from the actual rendered geometry in the delegated click handler.
        host.querySelectorAll("[data-point-id]").forEach(function (shape) {
            // SVG point shapes are keyboard-focusable for accessibility, but the
            // browser's native focus outline is not useful on top of the floor plan.
            // Selection is handled by the delegated listener on the stable host.
            if (shape.style) shape.style.outline = "none";
        });
    }

    function getPointPlateSearchText(point) {
        var values = [
            point && point.PlateNumber,
            point && point.PlateNo,
            point && point.LicensePlate,
            point && point.VehiclePlate,
            point && point.NoPol,
            point && point.Nopol
        ].filter(function (value) { return String(value || "").trim(); });

        var transaction = getPointTransaction(point);
        var template = currentMapRecord && currentMapRecord.TemplateSnapshot;
        var items = [];
        (template && Array.isArray(template.sections) ? template.sections : []).forEach(function (section) {
            (section.items || []).forEach(function (item) { items.push(item); });
        });
        items.forEach(function (item) {
            var label = [
                item && item.label, item && item.Label,
                item && item.name, item && item.Name,
                item && item.code, item && item.Code
            ].join(" ");
            if (!/(plat|plate|nopol|no\s*pol|nomor\s*polisi|license)/i.test(label)) return;
            var answer = transaction && Array.isArray(transaction.Items)
                ? transaction.Items.find(function (entry) {
                    return Number(entry.IDItem) === Number(item.idItem || item.IDItem);
                })
                : null;
            if (answer && String(answer.Value || "").trim())
                values.push(String(answer.Value).trim());
        });
        return values.join(" ");
    }

    function renderDynamicMotorList(host, points) {
        var record = currentMapRecord;
        var readOnly = !!currentInspectionReadOnly || String(record && record.Status || "").toUpperCase() === "DONE";
        var template = record && record.TemplateSnapshot;
        var visiblePoints = Array.isArray(points) ? points : [];
        var allRegistered = visiblePoints.length > 0 && visiblePoints.every(function (point) {
            return !!String(point.PointName || point.Nopol || "").trim();
        });

        function ensurePlateAnswer(point) {
            point.Items = Array.isArray(point.Items) ? point.Items : [];
            var sections = template && Array.isArray(template.sections) ? template.sections : [];
            var plateTemplate = null;
            sections.forEach(function (section) {
                (section.items || []).forEach(function (item) {
                    if (!plateTemplate &&
                        String(item.type || item.ItemType || "").toUpperCase() === "TEXT" &&
                        /(nopol|no\\s*pol|polisi|plat|nomor polisi|license)/i.test(String(item.label || item.ItemLabel || item.name || ""))) {
                        plateTemplate = item;
                    }
                });
            });
            if (!plateTemplate) return;
            var plateId = Number(plateTemplate.idItem || plateTemplate.IDItem);
            var answer = point.Items.find(function (item) { return Number(item.IDItem) === plateId; });
            if (!answer) {
                point.Items.unshift({
                    IDItem: plateId,
                    ItemLabel: String(plateTemplate.label || plateTemplate.ItemLabel || "Nopol"),
                    Type: "TEXT",
                    Value: String(point.PointName || point.Nopol || ""),
                    Remark1: "",
                    Remark2: "",
                    IsAnomali: false
                });
            } else if (!String(answer.Value || "").trim() && String(point.PointName || point.Nopol || "").trim()) {
                answer.Value = String(point.PointName || point.Nopol || "");
            }
        }

        function cardId(point) {
            return "motorPoint_" + String(point.InspectionPointID).replace(/[^0-9A-Za-z_-]/g, "_");
        }

        function saveMotorPoint(point, card) {
            if (!record || readOnly) return;
            var plateInput = card.querySelector("[data-motor-nopol]");
            var plate = String(plateInput && plateInput.value || "").trim().toUpperCase();
            if (!plate) {
                showToast("Nopol wajib diisi untuk " + point.PointCode + ".", "warning");
                if (plateInput) plateInput.focus();
                return;
            }
            var duplicate = visiblePoints.some(function (other) {
                return Number(other.InspectionPointID) !== Number(point.InspectionPointID) &&
                    String(other.PointName || other.Nopol || "").trim().toUpperCase() === plate;
            });
            if (duplicate) {
                showToast("Nopol " + plate + " sudah ada di daftar inspeksi ini.", "warning");
                if (plateInput) plateInput.focus();
                return;
            }

            ensurePlateAnswer(point);
            var plateAnswer = point.Items.find(function (item) {
                return String(item.Type || item.ItemType || "").toUpperCase() === "TEXT" &&
                    /(nopol|no\\s*pol|polisi|plat|nomor polisi|license)/i.test(String(item.ItemLabel || item.label || ""));
            });
            if (plateAnswer) plateAnswer.Value = plate;

            var checklistHost = card.querySelector("[data-motor-checklist-host]");
            var items = typeof window.collectInspectionItems === "function"
                ? window.collectInspectionItems(checklistHost)
                : [];
            var errors = typeof window.validateInspectionItemsAll === "function"
                ? window.validateInspectionItemsAll(items) : [];
            if (errors.length) {
                point.ValidationIssueCount = errors.length;
                showToast(point.PointCode + ": " + errors.slice(0, 2).map(function (error) { return error.message; }).join(" · ") +
                    (errors.length > 2 ? " · +" + (errors.length - 2) + " lainnya." : ""), "warning");
                return;
            }

            point.PointName = plate;
            point.Nopol = plate;
            point.Items = items;
            point.ValidationIssueCount = 0;
            if (["DONE", "ABNORMAL"].indexOf(String(point.Status || "").toUpperCase()) < 0)
                point.Status = "INCOMPLETE";
            point.UpdatedAt = new Date().toISOString();
            record.SyncStatus = "PENDING";
            record.UpdatedAt = new Date().toISOString();
            persistInspectionRecord(record).then(function () {
                showToast(point.PointCode + " · " + plate + " tersimpan.", "success");
                renderList();
                updateSummary();
            }).catch(function (error) {
                console.error("Unable to save Motor point:", error);
                showToast(error.message || "Gagal menyimpan Motor.", "warning");
            });
        }

        host.innerHTML =
            '<div class="inspection-motor-list-intro small text-muted mb-2">' +
                '<i class="bi bi-info-circle me-1"></i>' +
                'Motor pertama sudah tersedia. Isi Nopol dan checklist pada barisnya. ' +
                'Motor berikutnya ditambahkan dengan tombol <strong>Tambah Motor</strong>.' +
            '</div>' +
            visiblePoints.map(function (point, index) {
                ensurePlateAnswer(point);
                var status = getPointVisualStatus(point);
                var pointId = String(point.InspectionPointID);
                var checklistHostId = cardId(point) + "_checklist";
                var checklistHtml = typeof window.renderInspectionSections === "function"
                    ? window.renderInspectionSections(template, point.Items || [], readOnly, "motor_" + String(point.InspectionPointID).replace(/[^0-9A-Za-z_-]/g, "_"))
                    : '<div class="alert alert-warning small">Checklist template tidak tersedia.</div>';
                return '<div class="inspection-motor-card border rounded-3 p-3 mb-3" data-motor-point-id="' + esc(pointId) + '">' +
                    '<div class="d-flex flex-wrap align-items-start justify-content-between gap-2 mb-2">' +
                        '<div><div class="small text-primary fw-bold">' + esc(point.PointCode || ("M" + String(index + 1).padStart(3, "0"))) + '</div>' +
                        '<div class="fw-bold">Motor ' + (index + 1) + '</div></div>' +
                        '<span class="badge ' + (status === "DONE" ? "text-bg-success" : status === "ABNORMAL" ? "text-bg-danger" : status === "INCOMPLETE" ? "text-bg-warning" : "text-bg-secondary") + '">' +
                            esc(statusLabel(status, point)) + '</span>' +
                    '</div>' +
                    '<div class="row g-2 align-items-end mb-3">' +
                        '<div class="col-12 col-md-5"><label class="form-label small fw-semibold mb-1">Nomor Polisi / Nopol</label>' +
                            '<input type="text" class="form-control text-uppercase" maxlength="30" autocomplete="off" placeholder="Contoh: B 1234 XYZ" data-motor-nopol value="' + esc(point.PointName || point.Nopol || "") + '"' + (readOnly ? " disabled" : "") + '></div>' +
                        '<div class="col-12 col-md-auto d-flex flex-wrap gap-2">' +
                            '<button type="button" class="btn btn-primary btn-sm" data-save-motor' + (readOnly ? " disabled" : "") + '><i class="bi bi-save me-1"></i>Simpan Motor</button>' +
                            '<button type="button" class="btn btn-outline-secondary btn-sm" data-open-motor-detail><i class="bi bi-camera me-1"></i>Checklist & Foto</button>' +
                        '</div>' +
                    '</div>' +
                    '<div class="inspection-motor-checklist" data-motor-checklist-host id="' + esc(checklistHostId) + '">' +
                        checklistHtml +
                    '</div>' +
                '</div>';
            }).join("") +
            (!visiblePoints.length ? '<div class="text-muted small text-center py-4">Belum ada Motor.</div>' : '') +
            '<div class="d-flex justify-content-center mt-2">' +
                '<button type="button" id="btnAddInspectionDynamicPointInline" class="btn btn-outline-primary btn-sm"' +
                    (readOnly || !allRegistered ? " disabled" : "") + '>' +
                    '<i class="bi bi-plus-circle me-1"></i>Tambah Motor' +
                '</button>' +
            '</div>';

        if (typeof window.updateInspectionRemarkPanels === "function")
            host.querySelectorAll("[data-motor-checklist-host]").forEach(function (checklist) {
                window.updateInspectionRemarkPanels(checklist);
            });

        host.querySelectorAll("[data-motor-nopol]").forEach(function (input) {
            input.addEventListener("input", function () {
                this.value = String(this.value || "").toUpperCase();
            });
        });

        host.querySelectorAll("[data-save-motor]").forEach(function (button) {
            button.addEventListener("click", function (event) {
                event.preventDefault();
                var card = button.closest("[data-motor-point-id]");
                if (!card) return;
                var point = visiblePoints.find(function (item) {
                    return String(item.InspectionPointID) === String(card.getAttribute("data-motor-point-id"));
                });
                if (point) saveMotorPoint(point, card);
            });
        });

        host.querySelectorAll("[data-open-motor-detail]").forEach(function (button) {
            button.addEventListener("click", async function () {
                var card = button.closest("[data-motor-point-id]");
                if (!card) return;
                var point = visiblePoints.find(function (item) {
                    return String(item.InspectionPointID) === String(card.getAttribute("data-motor-point-id"));
                });
                if (!point) return;
                var nopol = String(card.querySelector("[data-motor-nopol]") && card.querySelector("[data-motor-nopol]").value || "").trim().toUpperCase();
                if (nopol && nopol !== String(point.PointName || point.Nopol || "").trim().toUpperCase()) {
                    card.querySelector("[data-save-motor]").click();
                    return;
                }
                await openPoint(point.InspectionPointID);
            });
        });

        host.querySelectorAll("[data-motor-checklist-host]").forEach(function (checklist) {
            checklist.addEventListener("change", function () {
                if (typeof window.updateInspectionRemarkPanels === "function")
                    window.updateInspectionRemarkPanels(checklist);
            });
        });

        var addButton = document.getElementById("btnAddInspectionDynamicPointInline");
        if (addButton) addButton.addEventListener("click", async function () {
            if (readOnly || !allRegistered || !record) return;
            var setup = record.BatchMapSetup || (record.BatchMapSetup = { success: true, maps: [], points: [] });
            setup.points = Array.isArray(setup.points) ? setup.points : visiblePoints;
            var sequence = setup.points.reduce(function (max, item) {
                return Math.max(max, Number(String(item.PointCode || "").replace(/^M/i, "")) || 0);
            }, 0) + 1;
            var point = {
                InspectionPointID: -sequence,
                ClientPointID: newInspectionId(),
                PointCode: "M" + String(sequence).padStart(3, "0"),
                PointName: "",
                Nopol: "",
                DisplayOrder: sequence,
                MapID: 0,
                Status: "PENDING",
                IsNormalAbnormalRequired: false,
                Items: []
            };
            setup.points.push(point);
            record.Points = record.Points || [];
            await persistInspectionRecord(record);
            renderList();
            updateSummary();
            var nextCard = host.querySelector('[data-motor-point-id="' + CSS.escape(String(point.InspectionPointID)) + '"]');
            if (nextCard) nextCard.scrollIntoView({ behavior: "smooth", block: "center" });
        });
    }

    function renderList() {
        var host = document.getElementById("inspectionPointList");
        if (!host) return;

        var all = getVisiblePoints();
        var keyword = String(listKeyword || "").trim().toLowerCase();
        var searchMatches = keyword ? all.filter(function (point) {
            return String(point.PointCode || "").toLowerCase().indexOf(keyword) >= 0 ||
                String(point.PointName || "").toLowerCase().indexOf(keyword) >= 0 ||
                getPointPlateSearchText(point).toLowerCase().indexOf(keyword) >= 0;
        }) : [];
        var filtered = all.filter(function (point) {
            return !keyword ||
                String(point.PointCode || "").toLowerCase().indexOf(keyword) >= 0 ||
                String(point.PointName || "").toLowerCase().indexOf(keyword) >= 0 ||
                getPointPlateSearchText(point).toLowerCase().indexOf(keyword) >= 0;
        });
        var pageCount = Math.max(1, Math.ceil(filtered.length / listPageSize));
        listPage = Math.min(Math.max(1, listPage), pageCount);
        var start = (listPage - 1) * listPageSize;
        var rows = filtered.slice(start, start + listPageSize);

        if (window.bootstrap && bootstrap.Tooltip) {
            host.querySelectorAll('[data-bs-toggle="tooltip"]').forEach(function (element) {
                var oldTooltip = bootstrap.Tooltip.getInstance(element);
                if (oldTooltip) oldTooltip.dispose();
            });
        }

        host.setAttribute("data-selected-point-id", selectedPoint ? String(selectedPoint.InspectionPointID) : "");
        host.innerHTML =
            '<div class="inspection-point-list-tools">' +
                '<div class="d-flex gap-2 align-items-center mb-2">' +
                    '<input type="search" id="inspectionPointSearch" class="form-control form-control-sm" ' +
                    'placeholder="Cari Point Code / No. Plat..." value="' + esc(listKeyword) + '">' +
                    (searchMatches.length > 1 ? '<select id="inspectionPointSearchChoice" class="form-select form-select-sm" aria-label="Pilih hasil pencarian">' +
                        '<option value="">Pilih hasil (' + searchMatches.length + ')</option>' +
                        searchMatches.slice(0, 100).map(function (point) {
                            return '<option value="' + esc(point.InspectionPointID) + '">' +
                                esc((point.PointCode || point.PointName || "Point") + ' · ' + (point.PointName || "") +
                                    (getPointPlateSearchText(point) ? ' · ' + getPointPlateSearchText(point) : "")) +
                                '</option>';
                        }).join("") +
                        '</select>' : '') +
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
                var status = getPointVisualStatus(point);
                var transaction = getPointTransaction(point);
                var issueCount = Number(transaction && transaction.ValidationIssueCount || point.ValidationIssueCount || 0);
                var quickOptionBlockReason = typeof window.getBatchPointQuickOptionBlockReason === "function"
                    ? window.getBatchPointQuickOptionBlockReason(point) : "";
                return '<div class="inspection-point-list-entry mb-1">' +
                    '<div role="button" tabindex="0" class="inspection-point-list-row w-100 text-start ' + (issueCount ? "validation-has-issues" : "") + '" data-point-id="' +
                    esc(point.InspectionPointID) + '">' +
                    '<span class="inspection-map-point-dot ' + pointClass(status) + '">' + statusSymbol(status) + '</span>' +
                    '<span class="point-main"><span class="point-code d-block">' + esc(point.PointCode) + '</span>' +
                    '<span class="point-name-line"><span class="point-name">' + esc(point.PointName) + '</span>' +
                    (quickOptionBlockReason ? '<button type="button" class="point-info-button" data-bs-toggle="tooltip" data-bs-trigger="click focus" data-bs-placement="top" data-bs-container="body" data-bs-title="' +
                        esc(quickOptionBlockReason) + '" aria-label="Informasi persyaratan point ' + esc(point.PointCode) + '"><i class="bi bi-info-circle"></i></button>' : '') +
                    '</span></span>' +
                    '<span class="badge ' + (issueCount ? "text-bg-danger" : status === "ABNORMAL" ? "text-bg-danger" :
                    status === "DONE" ? "text-bg-success" :
                    status === "INCOMPLETE" ? "text-bg-warning" : "text-bg-secondary") + '">' +
                    (issueCount ? issueCount + " temuan" : statusLabel(status, point)) + '</span><i class="bi bi-chevron-right text-muted"></i></div>' +
                    renderPointOptionControls(point) +
                    '<div class="text-end mt-1"><button type="button" class="btn btn-outline-secondary btn-sm py-0 px-2" data-open-point-checklist="' +
                    esc(point.InspectionPointID) + '"><i class="bi bi-list-check me-1"></i>Checklist</button></div>' + '</div>';
            }).join("") : '<div class="text-muted small text-center py-4">Tidak ada Inspection Point yang cocok.</div>');

        if (window.bootstrap && bootstrap.Tooltip) {
            host.querySelectorAll('[data-bs-toggle="tooltip"]').forEach(function (element) {
                bootstrap.Tooltip.getOrCreateInstance(element, {
                    trigger: "click focus",
                    container: "body",
                    placement: "top",
                    boundary: "viewport"
                });
                element.addEventListener("click", function (event) {
                    event.preventDefault();
                    event.stopPropagation();
                });
            });
        }
        host.querySelectorAll(".inspection-point-list-row[data-point-id]").forEach(function (row) {
            row.classList.toggle("active",
                row.getAttribute("data-point-id") === String(host.getAttribute("data-selected-point-id") || ""));
            row.addEventListener("click", function () {
                openPoint(row.getAttribute("data-point-id"));
            });
            row.addEventListener("keydown", function (event) {
                if (event.key === "Enter" || event.key === " ") {
                    event.preventDefault();
                    openPoint(row.getAttribute("data-point-id"));
                }
            });
        });
        host.querySelectorAll(".inspection-point-option-choice").forEach(function (button) {
            button.addEventListener("click", async function (event) {
                event.preventDefault();
                event.stopPropagation();
                if (typeof window.setBatchInspectionPointOption !== "function") {
                    if (typeof showToast === "function") showToast("Penyimpanan pilihan checklist belum tersedia.", "warning");
                    return;
                }
                button.disabled = true;
                try {
                    await window.setBatchInspectionPointOption(
                        button.getAttribute("data-point-id"),
                        button.getAttribute("data-point-option-item"),
                        button.getAttribute("data-point-option-value")
                    );
                    renderList();
                    renderPoints();
                    updateSummary();
                } catch (error) {
                    console.error("Unable to save batch point option:", error);
                    if (typeof showToast === "function") showToast(error.message || "Pilihan point gagal disimpan.", "warning");
                } finally {
                    button.disabled = false;
                }
            });
        });
        host.querySelectorAll("[data-point-remark-item]").forEach(function (input) {
            input.addEventListener("change", async function () {
                if (typeof window.setBatchInspectionPointRemark !== "function") return;
                input.disabled = true;
                try {
                    await window.setBatchInspectionPointRemark(
                        input.getAttribute("data-point-id"),
                        input.getAttribute("data-point-remark-item"),
                        input.getAttribute("data-point-remark-field"),
                        input.value
                    );
                    renderList();
                    renderPoints();
                    updateSummary();
                } catch (error) {
                    console.error("Unable to save batch point remark:", error);
                    if (typeof showToast === "function") showToast(error.message || "Remark point gagal disimpan.", "warning");
                    input.disabled = false;
                }
            });
        });
        host.querySelectorAll("[data-open-point-checklist]").forEach(function (button) {
            button.addEventListener("click", function (event) {
                event.preventDefault();
                event.stopPropagation();
                var point = currentPoints.find(function (item) {
                    return String(item.InspectionPointID) === button.getAttribute("data-open-point-checklist");
                });
                if (point && typeof window.openBatchInspectionPointChecklist === "function")
                    window.openBatchInspectionPointChecklist(point);
            });
        });
        // Delegate from the stable list host so live search keeps working
        // even though renderList() rebuilds the search input on each keystroke.
        if (host.getAttribute("data-point-search-wired") !== "1") {
            host.addEventListener("input", function (event) {
                var search = event.target && event.target.closest
                    ? event.target.closest("#inspectionPointSearch") : null;
                if (!search) return;
                listKeyword = String(search.value || "");
                listPage = 1;
                var cursor = search.selectionStart;
                renderList();
                var refreshed = document.getElementById("inspectionPointSearch");
                if (refreshed) {
                    refreshed.focus();
                    try { refreshed.setSelectionRange(cursor, cursor); } catch (_) { }
                }
            });
            host.setAttribute("data-point-search-wired", "1");
        }
        var searchChoice = document.getElementById("inspectionPointSearchChoice");
        if (searchChoice) searchChoice.addEventListener("change", function () {
            var id = String(this.value || "");
            if (id) openPoint(id);
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
                if (typeof showToast === "function")
                    showToast("Tidak ada titik wajib atau checklist yang masih perlu diselesaikan.", "success");
                return;
            }
            openPoint(point.InspectionPointID);
        });
    }

    function resetOptionSummaryPopoverPosition(host) {
        if (!host) return;
        ["position", "left", "right", "top", "width", "max-width", "max-height", "z-index"].forEach(function (property) {
            host.style.removeProperty(property);
        });
    }

    function positionOptionSummaryPopover() {
        var host = document.getElementById("inspectionMapOptionSummaryHost");
        var button = document.getElementById("btnInspectionMapOptionInfo");
        var isMobile = window.matchMedia &&
            window.matchMedia("(max-width: 767.98px)").matches;
        if (!host || !button || !isMobile) {
            if (host) resetOptionSummaryPopoverPosition(host);
            return;
        }

        // The option summary lives inside the last toolbar action. Absolute
        // positioning from that tiny wrapper pushes most of the panel beyond
        // the phone's left edge. Anchor it to the viewport using the button's
        // rendered coordinates instead.
        var rect = button.getBoundingClientRect();
        var viewportWidth = Math.max(1, document.documentElement.clientWidth || window.innerWidth || 1);
        var viewportHeight = Math.max(1, window.innerHeight || document.documentElement.clientHeight || 1);
        var width = Math.max(1, Math.min(340, viewportWidth - 16));
        var left = Math.max(8, Math.min(rect.right - width, viewportWidth - width - 8));
        var top = Math.min(rect.bottom + 6, Math.max(8, viewportHeight - 112));
        var maxHeight = Math.max(96, Math.min(viewportHeight * 0.42, viewportHeight - top - 12));

        host.style.position = "fixed";
        host.style.left = left + "px";
        host.style.right = "auto";
        host.style.top = top + "px";
        host.style.width = width + "px";
        host.style.maxWidth = width + "px";
        host.style.maxHeight = maxHeight + "px";
        host.style.zIndex = "1090";
    }

    function closeOptionSummaryPopover() {
        var host = document.getElementById("inspectionMapOptionSummaryHost");
        var button = document.getElementById("btnInspectionMapOptionInfo");
        if (host) {
            host.classList.add("d-none");
            resetOptionSummaryPopoverPosition(host);
        }
        if (button) button.setAttribute("aria-expanded", "false");
    }

    function renderTemplateOptionSummary(points) {
        var host = document.getElementById("inspectionMapOptionSummaryHost");
        if (!host) return;

        host.setAttribute("data-has-summary", "false");
        host.classList.add("d-none");
        closeOptionSummaryPopover();

        var template = currentMapRecord && currentMapRecord.TemplateSnapshot;
        if (typeof template === "string") {
            try { template = JSON.parse(template); }
            catch (ignore) { template = null; }
        }

        var optionItems = [];
        var sections = template && (template.sections || template.Sections);
        (Array.isArray(sections) ? sections : []).forEach(function (section) {
            var items = section && (section.items || section.Items);
            (Array.isArray(items) ? items : []).forEach(function (item) {
                if (String(item && (item.type || item.Type || item.ItemType) || "").toUpperCase() === "OPTION")
                    optionItems.push(item);
            });
        });

        // currentPoints contains the master points across every map. The status
        // helpers resolve each point's transaction using only getActiveScheduleTime().
        var allPoints = Array.isArray(points) ? points : [];
        var totalPoints = allPoints.length;
        var completedPoints = allPoints.filter(function (point) {
            return getPointStatus(point) === "DONE";
        }).length;
        var unfilledPoints = Math.max(0, totalPoints - completedPoints);
        var incompletePoints = allPoints.filter(function (point) {
            return getPointStatus(point) === "INCOMPLETE";
        }).length;

        var hasNormalAbnormal = allPoints.some(isNormalAbnormalRequired);
        var normalPoints = hasNormalAbnormal ? allPoints.filter(function (point) {
            return isNormalAbnormalRequired(point) && getPointVisualStatus(point) === "DONE";
        }).length : 0;
        var abnormalPoints = hasNormalAbnormal ? allPoints.filter(function (point) {
            return isNormalAbnormalRequired(point) && getPointVisualStatus(point) === "ABNORMAL";
        }).length : 0;

        // Build the summary labels from each OPTION item's own configured
        // optionList. This supports arbitrary values such as ON/OFF, GOOD/BAD,
        // OPEN/CLOSED, etc.; no option values are hardcoded here.
        var optionCounts = [];
        function getOptionCountEntry(optionValue) {
            var label = String(optionValue == null ? "" : optionValue).trim();
            if (!label) return null;
            var key = label.toUpperCase();
            var entry = optionCounts.find(function (item) { return item.key === key; });
            if (!entry) {
                entry = { key: key, label: label, count: 0 };
                optionCounts.push(entry);
            }
            return entry;
        }

        optionItems.forEach(function (optionItem) {
            var rawOptions = optionItem.optionList != null ? optionItem.optionList :
                (optionItem.OptionList != null ? optionItem.OptionList : []);
            var configuredOptions = Array.isArray(rawOptions) ? rawOptions :
                String(rawOptions || "").split(";");
            configuredOptions.forEach(getOptionCountEntry);
        });

        if (optionCounts.length) {
            allPoints.forEach(function (point) {
                var transaction = getPointTransaction(point);
                var transactionItems = transaction && (transaction.Items || transaction.items);
                if (!Array.isArray(transactionItems)) return;

                optionItems.forEach(function (optionItem) {
                    var itemId = optionItem.idItem != null ? optionItem.idItem :
                        (optionItem.IDItem != null ? optionItem.IDItem : optionItem.id);
                    if (itemId == null || itemId === "") return;
                    var answer = transactionItems.find(function (result) {
                        var answerId = result.IDItem != null ? result.IDItem :
                            (result.idItem != null ? result.idItem : result.id);
                        return Number(answerId) === Number(itemId);
                    });
                    var rawValue = answer && (answer.Value != null ? answer.Value :
                        (answer.value != null ? answer.value : answer.Result));
                    var selectedValue = String(rawValue == null ? "" : rawValue).trim().toUpperCase();
                    if (!selectedValue) return;

                    var countEntry = optionCounts.find(function (item) {
                        return item.key === selectedValue;
                    });
                    if (countEntry) countEntry.count++;
                });
            });
        }

        var isLightning = currentMapRecord &&
            (String(currentMapRecord.InspectionMode || "").toUpperCase() === "BATCH" && String(currentMapRecord.ScheduleSelectionMode || "").toUpperCase() === "INSPECT");
        var scheduleLabel = isLightning ? (getActiveScheduleTime() || "Belum dipilih") : "Batch";
        var html =
            '<div class="small fw-semibold text-muted mb-1"><i class="bi bi-bar-chart-line me-1"></i>Ringkasan Semua Denah' +
                '<span class="fw-normal"> · Jadwal ' + esc(scheduleLabel) + '</span></div>' +
            '<div class="inspection-map-global-summary">' +
                '<div class="inspection-map-global-stat"><strong>' + totalPoints + '</strong><span>Total Point</span></div>' +
                '<div class="inspection-map-global-stat"><strong>' + completedPoints + '</strong><span>Selesai</span></div>' +
                '<button type="button" class="inspection-map-global-stat inspection-map-global-stat-action" data-open-inspection-unfilled aria-label="Lihat point yang belum diisi pada jadwal aktif"><strong>' + unfilledPoints + '</strong><span>Belum diisi</span></button>' +
                '<div class="inspection-map-global-stat"><strong>' + incompletePoints + '</strong><span>Belum lengkap</span></div>';

        if (hasNormalAbnormal) {
            html +=
                '<div class="inspection-map-global-stat"><strong>' + normalPoints + '</strong><span>Normal</span></div>' +
                '<div class="inspection-map-global-stat"><strong>' + abnormalPoints + '</strong><span>Abnormal</span></div>';
        }

        html += '</div>';
        if (optionCounts.length) {
            html +=
                '<div class="inspection-map-option-summary">' +
                    '<div class="inspection-map-option-summary-card">' +
                        '<div class="inspection-map-option-chip-row">' +
                            optionCounts.map(function (item) {
                                return '<button type="button" class="inspection-map-option-chip inspection-map-option-chip-action" data-open-inspection-option="' + esc(item.label) +
                                    '" title="Lihat point dengan hasil ' + esc(item.label) + '">' +
                                    '<span class="inspection-map-option-chip-label">' + esc(item.label) + '</span>' +
                                    '<strong>' + item.count + '</strong>' +
                                    '</button>';
                            }).join("") +
                        '</div>' +
                    '</div>' +
                '</div>';
        }

        host.innerHTML = html;
        host.setAttribute("data-has-summary", totalPoints > 0 ? "true" : "false");
    }

    function updateSummary() {
        // The old full-width per-map status strip has been retired. Keep only
        // the compact popover summary, aggregated across all maps for the
        // currently selected schedule time.
        renderTemplateOptionSummary(currentPoints);
        var optionSummaryHost = document.getElementById("inspectionMapOptionSummaryHost");
        var optionInfoButton = document.getElementById("btnInspectionMapOptionInfo");
        var hasOptionSummary = !!(optionSummaryHost && optionSummaryHost.getAttribute("data-has-summary") === "true");
        if (optionInfoButton) {
            optionInfoButton.classList.toggle("d-none", !hasOptionSummary);
            if (!hasOptionSummary) closeOptionSummaryPopover();
        }
    }

    function scrollPointListToRow(pointId) {
        listKeyword = "";
        var visiblePoints = getVisiblePoints();
        var pointIndex = visiblePoints.findIndex(function (point) {
            return String(point.InspectionPointID) === String(pointId);
        });
        if (pointIndex < 0) {
            console.warn("Inspection map marker has no matching visible Point List row:", pointId);
            return false;
        }

        listPage = Math.floor(pointIndex / listPageSize) + 1;
        var selectedId = String(pointId);
        switchMapList();
        renderList();

        var listHost = document.getElementById("inspectionPointList");
        if (!listHost) return false;
        listHost.setAttribute("data-selected-point-id", selectedId);

        var row = Array.prototype.find.call(
            listHost.querySelectorAll(".inspection-point-list-row[data-point-id]"),
            function (item) { return String(item.getAttribute("data-point-id")) === selectedId; }
        );
        if (!row) return false;

        listHost.querySelectorAll(".inspection-point-list-row.active, .inspection-point-list-row.selected")
            .forEach(function (item) { item.classList.remove("active", "selected"); });
        row.classList.add("active", "selected");
        row.setAttribute("aria-current", "true");

        function scrollSelectedRow() {
            if (!document.documentElement.contains(row) || !listHost.clientHeight) return;
            row.classList.add("active", "selected");
            row.setAttribute("aria-current", "true");

            var hostRect = listHost.getBoundingClientRect();
            var rowRect = row.getBoundingClientRect();
            var targetTop = listHost.scrollTop + rowRect.top - hostRect.top -
                Math.max(0, (listHost.clientHeight - rowRect.height) / 2);
            var maxScroll = Math.max(0, listHost.scrollHeight - listHost.clientHeight);
            targetTop = Math.max(0, Math.min(maxScroll, targetTop));
            if (typeof listHost.scrollTo === "function")
                listHost.scrollTo({ top: targetTop, behavior: "smooth" });
            else
                listHost.scrollTop = targetTop;
        }

        var isMobile = window.matchMedia &&
            window.matchMedia("(max-width: 767.98px)").matches;
        var modalElement = document.getElementById("inspectionPointListModal");
        var modalBody = document.getElementById("inspectionPointListModalBody");
        if (isMobile && modalElement && modalBody && window.bootstrap && bootstrap.Modal) {
            if (listHost.parentElement !== modalBody) modalBody.appendChild(listHost);
            var modal = bootstrap.Modal.getOrCreateInstance(modalElement);
            var pointListButton = document.getElementById("btnInspectionMapPointList");
            if (pointListButton) pointListButton.setAttribute("aria-expanded", "true");
            var runScrollAfterShow = function () {
                window.requestAnimationFrame(function () {
                    window.requestAnimationFrame(scrollSelectedRow);
                });
            };
            if (modalElement.classList.contains("show")) {
                runScrollAfterShow();
            } else {
                modalElement.addEventListener("shown.bs.modal", function onPointListShown() {
                    modalElement.removeEventListener("shown.bs.modal", onPointListShown);
                    runScrollAfterShow();
                });
                modal.show();
            }
            return true;
        }

        window.requestAnimationFrame(function () {
            window.requestAnimationFrame(scrollSelectedRow);
        });
        return true;
    }

    function getQuickPointOptionItems() {
        var template = currentMapRecord && currentMapRecord.TemplateSnapshot;
        var items = [];
        (template && Array.isArray(template.sections) ? template.sections : []).forEach(function (section) {
            (section.items || []).forEach(function (item) {
                if (String(item.type || item.ItemType || "").toUpperCase() === "OPTION")
                    items.push(item);
            });
        });
        return items;
    }

    function getQuickPointSavedValue(point, itemId) {
        var transaction = getPointTransaction(point);
        var savedItems = transaction && Array.isArray(transaction.Items) ? transaction.Items : [];
        var answer = savedItems.find(function (item) { return Number(item.IDItem) === Number(itemId); });
        return String(answer && answer.Value || "");
    }

    function renderQuickPointSheet(point) {
        var host = document.getElementById("inspectionMapQuickOptions");
        var note = document.getElementById("inspectionMapQuickNote");
        if (!host) return;
        var items = getQuickPointOptionItems();
        var readOnly = currentMapRecord && (currentMapRecord.Status === "DONE" || currentInspectionReadOnly);
        var blockReason = typeof window.getBatchPointQuickOptionBlockReason === "function"
            ? window.getBatchPointQuickOptionBlockReason(point) : "";
        host.innerHTML = items.map(function (item) {
            var options = String(item.optionList || item.OptionList || "")
                .split(";").map(function (value) { return value.trim(); }).filter(Boolean);
            if (!options.length) return "";
            var selected = getQuickPointSavedValue(point, item.idItem != null ? item.idItem : item.IDItem);
            return '<div class="w-100 mb-2">' +
                (items.length > 1 ? '<div class="small fw-semibold mb-1">' + esc(item.label || item.ItemLabel || "Checklist") + '</div>' : '') +
                '<div class="inspection-map-quick-options">' +
                options.map(function (option) {
                    var active = String(selected).trim().toUpperCase() === String(option).trim().toUpperCase();
                    return '<button type="button" class="inspection-map-quick-option' + (active ? ' active' : '') + '" ' +
                        'data-quick-option-item="' + esc(item.idItem != null ? item.idItem : item.IDItem) + '" ' +
                        'data-quick-option-value="' + esc(option) + '"' +
                        (readOnly || blockReason ? ' disabled aria-disabled="true"' : '') + '>' + esc(option) + '</button>';
                }).join("") + '</div></div>';
        }).join("");
        if (!items.length) {
            host.innerHTML = '<div class="alert alert-light border small mb-0">Point ini tidak memiliki checklist pilihan cepat. Gunakan Checklist Lengkap.</div>';
        }
        if (note) {
            note.textContent = blockReason
                ? blockReason
                : (items.length ? "Pilih hasil pemeriksaan lalu tekan Terapkan. Checklist lengkap tetap tersedia bila point membutuhkan pemeriksaan detail." : "");
            note.className = "inspection-map-quick-note text-muted mt-2" + (blockReason ? " text-danger" : "");
        }
    }

    function showQuickPointSheet(point) {
        if (!point) return;
        var sheet = document.getElementById("inspectionMapPointSheet");
        var backdrop = document.getElementById("inspectionMapPointSheetBackdrop");
        var formPanel = document.getElementById("inspectionFormPanel");
        if (!sheet) return;
        renderQuickPointSheet(point);
        sheet.classList.remove("checklist-mode");
        if (formPanel) formPanel.classList.add("d-none");
        ["inspectionMapQuickOptions", "inspectionMapQuickNote", "btnOpenInspectionPointChecklist",
            "btnCancelInspectionMapPoint", "btnApplyInspectionMapPoint"].forEach(function (id) {
            var element = document.getElementById(id);
            if (element) element.classList.remove("d-none");
        });
        sheet.classList.remove("d-none");
        if (backdrop) {
            backdrop.classList.remove("d-none");
            backdrop.setAttribute("aria-hidden", "false");
        }
    }

    window.showInspectionMapPointChecklistSheet = function (point) {
        if (!point) return;
        selectedPoint = currentPoints.find(function (item) {
            return Number(item.InspectionPointID) === Number(point.InspectionPointID);
        }) || point;
        var sheet = document.getElementById("inspectionMapPointSheet");
        var backdrop = document.getElementById("inspectionMapPointSheetBackdrop");
        var mount = document.getElementById("inspectionMapPointChecklistMount");
        var formPanel = document.getElementById("inspectionFormPanel");
        if (!sheet || !mount || !formPanel) return;
        var code = document.getElementById("inspectionMapPointCode");
        var name = document.getElementById("inspectionMapPointName");
        var meta = document.getElementById("inspectionMapPointMeta");
        var status = document.getElementById("inspectionMapPointStatus");
        if (code) code.textContent = point.PointCode || "";
        if (name) name.textContent = point.PointName || "Inspection Point";
        if (meta) meta.textContent = "Checklist lengkap · " + (point.ScheduleTime || currentMapRecord && currentMapRecord.ActiveScheduleTime || "Batch");
        if (status) status.textContent = "Isi seluruh item pemeriksaan dan remark yang diminta";
        mount.appendChild(formPanel);
        formPanel.classList.remove("d-none");
        sheet.classList.add("checklist-mode");
        ["inspectionMapQuickOptions", "inspectionMapQuickNote", "btnOpenInspectionPointChecklist",
            "btnCancelInspectionMapPoint", "btnApplyInspectionMapPoint"].forEach(function (id) {
            var element = document.getElementById(id);
            if (element) element.classList.add("d-none");
        });
        sheet.classList.remove("d-none");
        if (backdrop) {
            backdrop.classList.remove("d-none");
            backdrop.setAttribute("aria-hidden", "false");
        }
        var scrollHost = document.getElementById("inspectionMapPointChecklistScroll");
        if (scrollHost) scrollHost.scrollTop = 0;
    };

    window.closeInspectionMapPointChecklistSheet = function (restoreForm) {
        var sheet = document.getElementById("inspectionMapPointSheet");
        var backdrop = document.getElementById("inspectionMapPointSheetBackdrop");
        var formPanel = document.getElementById("inspectionFormPanel");
        var mount = document.getElementById("inspectionMapPointChecklistMount");
        var pane = document.getElementById("inspectionChecklistPane");
        if (restoreForm && formPanel && pane && mount && mount.contains(formPanel)) {
            pane.appendChild(formPanel);
            formPanel.classList.add("d-none");
            formPanel.removeAttribute("data-map-point-id");
            window.inspectionReturnToPointNavigator = false;
        }
        if (sheet) {
            sheet.classList.remove("checklist-mode");
            sheet.classList.add("d-none");
        }
        if (backdrop) {
            backdrop.classList.add("d-none");
            backdrop.setAttribute("aria-hidden", "true");
        }
    };

        function hideQuickPointSheet() {
        var sheet = document.getElementById("inspectionMapPointSheet");
        var backdrop = document.getElementById("inspectionMapPointSheetBackdrop");
        if (sheet) sheet.classList.add("d-none");
        if (backdrop) {
            backdrop.classList.add("d-none");
            backdrop.setAttribute("aria-hidden", "true");
        }
    }

    async function applyQuickPointSheet() {
        if (!selectedPoint) return;
        var items = getQuickPointOptionItems();
        if (!items.length) {
            hideQuickPointSheet();
            return;
        }
        var changed = [];
        items.forEach(function (item) {
            var itemId = item.idItem != null ? item.idItem : item.IDItem;
            var current = getQuickPointSavedValue(selectedPoint, itemId);
            var selector = '#inspectionMapQuickOptions [data-quick-option-item="' + String(itemId).replace(/"/g, '\\"') + '"].active';
            var button = document.querySelector(selector);
            var desired = button ? String(button.getAttribute("data-quick-option-value") || "") : "";
            if (String(current).trim() !== String(desired).trim())
                changed.push({ itemId: itemId, current: current, desired: desired });
        });
        try {
            for (var i = 0; i < changed.length; i++) {
                var itemChange = changed[i];
                if (itemChange.desired) {
                    await window.setBatchInspectionPointOption(selectedPoint.InspectionPointID, itemChange.itemId, itemChange.desired);
                } else if (itemChange.current) {
                    await window.setBatchInspectionPointOption(selectedPoint.InspectionPointID, itemChange.itemId, itemChange.current);
                }
            }
            hideQuickPointSheet();
            if (typeof window.refreshInspectionMapPointStatuses === "function")
                window.refreshInspectionMapPointStatuses();
            if (typeof showToast === "function" && changed.length)
                showToast("Hasil point " + (selectedPoint.PointCode || "") + " berhasil diterapkan.", "success");
        } catch (error) {
            console.error("Unable to apply quick point result:", error);
            if (typeof showToast === "function")
                showToast(error.message || "Hasil point gagal disimpan.", "warning");
        }
    }

    function ensureQuickPointRing(point) {
        var pointHost = document.getElementById("inspectionMapPoints");
        if (!pointHost || !point) return;
        var old = pointHost.querySelector(".inspection-map-quick-focus-ring");
        if (old) old.remove();
        var pos = getPointMapFocusPosition(point);
        var ring = document.createElement("div");
        ring.className = "inspection-map-quick-focus-ring";
        ring.style.left = pos.x + "%";
        ring.style.top = pos.y + "%";
        ring.setAttribute("data-quick-focus-point", String(point.InspectionPointID));
        pointHost.appendChild(ring);
    }

    function openPoint(id) {
        selectedPoint = currentPoints.find(function (point) {
            return String(point.InspectionPointID) === String(id);
        }) || null;
        if (!selectedPoint) return;
        var pointListHost = document.getElementById("inspectionPointList");
        if (pointListHost) pointListHost.setAttribute("data-selected-point-id", String(id));
        navigatorFocusRequestSequence++;
        navigatorFocusPendingPointId = "";
        removeNavigatorFocusRing();

        document.querySelectorAll(".inspection-map-point, .inspection-map-svg-path, .inspection-map-svg-rect, .inspection-map-svg-circle").forEach(function (element) {
            var isSelected = element.getAttribute("data-point-id") === String(id);
            // Navigator focus adds a separate class for the blue target fill.
            // Clear it from every previous marker when the user picks another
            // point, otherwise a former RECTANGLE remains filled after its
            // focus ring has been dismissed.
            element.classList.toggle("selected", isSelected);
            element.classList.remove("navigator-target");
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
                (statusValue === "ABNORMAL" ? "text-danger" :
                statusValue === "DONE" ? "text-success" :
                statusValue === "INCOMPLETE" ? "text-warning" : "text-secondary");
            status.textContent = statusLabel(statusValue, selectedPoint);
        }
        var pointTransaction = getPointTransaction(selectedPoint);
        var abnormalRemark = String(pointTransaction && pointTransaction.AbnormalRemark || "").trim();
        if (desc) desc.textContent = abnormalRemark
            ? "ABNORMAL: " + abnormalRemark
            : (selectedPoint.PointDescription || selectedPoint.ObjectReferenceCode || "");
        var sheet = document.getElementById("inspectionMapPointSheet");
        if (sheet) sheet.classList.add("d-none");

        removeNavigatorFocusRing();
        var isMobileMapViewport = window.matchMedia &&
            window.matchMedia("(max-width: 767.98px)").matches;

        if (isMobileMapViewport) {
            // On mobile, map selection opens the actual checklist in the
            // bottom sheet. Do not open/scroll the obsolete Point List modal.
            if (typeof window.openBatchInspectionPointChecklist === "function") {
                Promise.resolve(window.openBatchInspectionPointChecklist(selectedPoint)).catch(function (error) {
                    console.error("Unable to open mobile inspection checklist:", error);
                    if (typeof showToast === "function")
                        showToast(error && error.message ? error.message : "Checklist point gagal dibuka.", "warning");
                });
            } else {
                ensureQuickPointRing(selectedPoint);
                showQuickPointSheet(selectedPoint);
            }
            return;
        }

        // Map selection is a direct inspection action on both desktop and
        // mobile: open the point checklist dialog immediately. The list remains
        // available separately and is no longer used as an intermediate step.
        if (typeof window.openBatchInspectionPointChecklist === "function") {
            Promise.resolve(window.openBatchInspectionPointChecklist(selectedPoint)).catch(function (error) {
                console.error("Unable to open inspection checklist:", error);
                if (typeof showToast === "function")
                    showToast(error && error.message ? error.message : "Checklist point gagal dibuka.", "warning");
            });
        } else {
            scrollPointListToRow(id);
        }
    }

    function closePoint() {
        selectedPoint = null;
        hideQuickPointSheet();
        var pointHost = document.getElementById("inspectionMapPoints");
        if (pointHost) {
            var quickRing = pointHost.querySelector(".inspection-map-quick-focus-ring");
            if (quickRing) quickRing.remove();
        }
        document.querySelectorAll(".inspection-map-point.selected, .inspection-map-svg-path.selected, .inspection-map-svg-rect.selected, .inspection-map-svg-circle.selected, .inspection-map-point.navigator-target, .inspection-map-svg-path.navigator-target, .inspection-map-svg-rect.navigator-target, .inspection-map-svg-circle.navigator-target").forEach(function (element) {
            element.classList.remove("selected");
            element.classList.remove("navigator-target");
        });
    }

    function switchMapList() {
        var canvas = document.getElementById("inspectionMapCanvas");
        var list = document.getElementById("inspectionPointList");
        if (!canvas || !list) return;
        var hasMap = currentMaps.some(function (map) {
            return Number(map.MapID) === Number(currentMapId) && !!map.MapUrl;
        });
        canvas.classList.toggle("d-none", !hasMap);
        list.classList.remove("d-none");
        var content = document.querySelector(".inspection-map-content");
        if (content) content.classList.toggle("no-map", !hasMap);
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
        if (elements.points) {
            elements.points.style.setProperty("--inspection-map-marker-scale", String(1 / mapZoom));
            elements.points.style.setProperty("--inspection-map-ring-scale", String(1 / mapZoom));
        }
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
        schedulePdfCanvasRender();
    }

    function wireMapGestures() {
        var elements = getMapElements();
        var viewport = elements.viewport;
        if (!viewport || viewport.getAttribute("data-map-gestures") === "1") return;
        viewport.setAttribute("data-map-gestures", "1");

        viewport.addEventListener("wheel", function (event) {
            if (!event.ctrlKey && !event.shiftKey) return;
            if (!currentPdfDocument && !document.querySelector('#inspectionMapPdfStage img.inspection-map-image')) return;
            event.preventDefault();
            var factor = event.deltaY < 0 ? 1.15 : 1 / 1.15;
            zoomMapTo(mapZoom * factor, event.clientX, event.clientY);
        }, { passive: false });

        viewport.addEventListener("pointerdown", function (event) {
            /* Mobile Chrome can deliver the floor-plan pinch as Touch Events
               even though the rest of the editor uses Pointer Events. Keep
               touch handling in one path below so a two-finger gesture is
               never mistaken for a one-finger pan. */
            if (event.pointerType === "touch") return;

            /* Do not capture a pointer that started on ANY map marker. SVG
               PATH/RECT/CIRCLE targets are not .inspection-map-point buttons;
               capturing them here retargets pointerup/click to the canvas. */
            if ((!currentPdfDocument && !document.querySelector("#inspectionMapPdfStage img.inspection-map-image")) ||
                (event.target.closest && (event.target.closest("[data-point-id]") || event.target.closest(".inspection-map-zoom-tools")))) return;
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

        /* Explicit Touch Event fallback for mobile floor-plan gestures.
           Pointer Events remain responsible for mouse/pen interaction; touch
           gestures use the browser's native multi-touch coordinates directly. */
        viewport.addEventListener("touchstart", function (event) {
            if ((!currentPdfDocument && !document.querySelector("#inspectionMapPdfStage img.inspection-map-image")) ||
                (event.target.closest && (event.target.closest("[data-point-id]") || event.target.closest(".inspection-map-zoom-tools")))) return;

            if (event.touches.length >= 2) {
                event.preventDefault();
                var first = event.touches[0];
                var second = event.touches[1];
                var dx = second.clientX - first.clientX;
                var dy = second.clientY - first.clientY;
                mapGesture = {
                    type: "pinch",
                    distance: Math.sqrt(dx * dx + dy * dy),
                    zoom: mapZoom
                };
            } else if (event.touches.length === 1) {
                var touch = event.touches[0];
                mapGesture = {
                    type: "pan",
                    x: touch.clientX,
                    y: touch.clientY,
                    panX: mapPanX,
                    panY: mapPanY
                };
            }
        }, { passive: false });

        viewport.addEventListener("touchmove", function (event) {
            if (!mapGesture || !event.touches.length) return;

            if (event.touches.length >= 2) {
                event.preventDefault();
                var first = event.touches[0];
                var second = event.touches[1];
                var dx = second.clientX - first.clientX;
                var dy = second.clientY - first.clientY;
                var distance = Math.sqrt(dx * dx + dy * dy);

                if (mapGesture.type === "pinch" && mapGesture.distance > 0) {
                    var midpointX = (first.clientX + second.clientX) / 2;
                    var midpointY = (first.clientY + second.clientY) / 2;
                    zoomMapTo(
                        mapGesture.zoom * (distance / mapGesture.distance),
                        midpointX,
                        midpointY
                    );
                } else {
                    mapGesture = {
                        type: "pinch",
                        distance: distance,
                        zoom: mapZoom
                    };
                }
            } else if (event.touches.length === 1 && mapGesture.type === "pan") {
                event.preventDefault();
                var touch = event.touches[0];
                mapPanX = mapGesture.panX + touch.clientX - mapGesture.x;
                mapPanY = mapGesture.panY + touch.clientY - mapGesture.y;
                applyMapTransform();
            }
        }, { passive: false });

        function finishTouch() {
            mapGesture = null;
        }

        viewport.addEventListener("touchend", finishTouch, { passive: false });
        viewport.addEventListener("touchcancel", finishTouch, { passive: false });
    }

    function schedulePdfCanvasRender() {
        if (!currentPdfPage) return;
        if (pdfCanvasRenderTimer) clearTimeout(pdfCanvasRenderTimer);
        pdfCanvasRenderTimer = setTimeout(function () {
            pdfCanvasRenderTimer = null;
            renderPdfCanvasAtZoom();
        }, 140);
    }

    async function renderPdfCanvasAtZoom() {
        if (!currentPdfPage) return;
        var canvas = document.getElementById('inspectionMapPdfCanvas');
        if (!canvas) return;
        var sequence = ++pdfCanvasRenderSequence;
        var previousTask = pdfCanvasRenderTask;
        if (previousTask && previousTask.cancel) {
            try { previousTask.cancel(); } catch (_) { }
            try { await previousTask.promise; } catch (_) { }
        }
        if (sequence !== pdfCanvasRenderSequence) return;
        pdfCanvasRenderTask = null;
        var ratio = Math.min(window.devicePixelRatio || 1, 2);
        var renderScale = currentPdfFitScale * mapZoom * ratio;
        var viewport = currentPdfPage.getViewport({ scale: renderScale });
        var displayViewport = currentPdfPage.getViewport({ scale: currentPdfFitScale });
        canvas.width = Math.max(1, Math.floor(viewport.width));
        canvas.height = Math.max(1, Math.floor(viewport.height));
        canvas.style.width = Math.max(1, displayViewport.width) + 'px';
        canvas.style.height = Math.max(1, displayViewport.height) + 'px';
        var stage = document.getElementById('inspectionMapPdfStage');
        if (stage) {
            // Keep the floor plan and point overlay in one exact CSS coordinate space.
            stage.style.width = canvas.style.width;
            stage.style.height = canvas.style.height;
            stage.style.minHeight = '0';
            stage.style.maxWidth = 'none';
            stage.style.maxHeight = 'none';
        }
        var context = canvas.getContext('2d');
        try {
            var task = currentPdfPage.render({ canvasContext: context, viewport: viewport });
            pdfCanvasRenderTask = task;
            await task.promise;
            if (sequence !== pdfCanvasRenderSequence) return;
            pdfCanvasRenderTask = null;
        } catch (error) {
            if (sequence !== pdfCanvasRenderSequence) return;
            pdfCanvasRenderTask = null;
            if (!(error && (error.name === 'RenderingCancelledException' || /cancel/i.test(error.message || '')))) {
                console.error('Inspection map PDF zoom render failed:', error);
            }
        }
    }

    function getInspectionMapFitBounds() {
        var viewport = document.getElementById('inspectionMapCanvas');
        if (!viewport) return { width: 1, height: 1 };
        var style = window.getComputedStyle(viewport);
        var horizontalPadding = (parseFloat(style.paddingLeft) || 0) + (parseFloat(style.paddingRight) || 0);
        var verticalPadding = (parseFloat(style.paddingTop) || 0) + (parseFloat(style.paddingBottom) || 0);
        return {
            width: Math.max(1, Math.min(2400, viewport.clientWidth - horizontalPadding)),
            height: Math.max(1, viewport.clientHeight - verticalPadding)
        };
    }

    async function renderPdf(map) {
        var requestId = ++pdfRenderSequence;
        var message = document.getElementById('inspectionMapPdfMessage');
        var canvas = document.getElementById('inspectionMapPdfCanvas');
        var stage = document.getElementById('inspectionMapPdfStage');
        if (!canvas || !stage) return;
        resetMapView();
        currentPdfPage = null;
        currentPdfFitScale = 1;
        if (pdfCanvasRenderTimer) { clearTimeout(pdfCanvasRenderTimer); pdfCanvasRenderTimer = null; }
        pdfCanvasRenderSequence++;
        if (pdfCanvasRenderTask && pdfCanvasRenderTask.cancel) { try { pdfCanvasRenderTask.cancel(); } catch (_) { } pdfCanvasRenderTask = null; }
        if (currentPdfDocument && currentPdfDocument.destroy) { try { await currentPdfDocument.destroy(); } catch (_) { } currentPdfDocument = null; }
        if (requestId !== pdfRenderSequence) return;
        var previousImage = stage.querySelector('img.inspection-map-image');
        if (previousImage) { if (previousImage.dataset.objectUrl) URL.revokeObjectURL(previousImage.dataset.objectUrl); previousImage.remove(); }
        canvas.style.display = 'block';
        var pointsHost = document.getElementById("inspectionMapPoints");
        if (pointsHost) pointsHost.innerHTML = "";
        var context = canvas.getContext('2d'); context.clearRect(0, 0, canvas.width, canvas.height); canvas.width = 0; canvas.height = 0;
        if (!map || !map.MapUrl) {
            if (message) { message.textContent = 'Denah belum tersedia. Pilih Inspection Point dari daftar.'; message.classList.remove('d-none'); }
            stage.style.width = '100%';
            stage.style.minHeight = '260px';
            return;
        }
        try {
            if (message) { message.textContent = 'Memuat denah...'; message.classList.remove('d-none'); }
            var urlPath = String(map.MapUrl).split('?')[0].toLowerCase();
            var directImage = /\.(png|jpg|jpeg|gif|bmp|webp|svg)$/.test(urlPath);
            if (directImage) {
                // Raster floor plans are best loaded directly by the browser.
                // This avoids fetch/Blob/PDF.js handling and works with image
                // endpoints that send non-standard Content-Type headers.
                canvas.style.display = 'none';
                var direct = document.createElement('img');
                direct.className = 'inspection-map-image';
                direct.alt = 'Inspection floor plan';
                direct.draggable = false;
                stage.insertBefore(direct, document.getElementById('inspectionMapPoints'));
                direct.onload = function () {
                    if (requestId !== pdfRenderSequence) return;
                    var bounds = getInspectionMapFitBounds();
                    var naturalWidth = direct.naturalWidth || direct.clientWidth;
                    var naturalHeight = direct.naturalHeight || direct.clientHeight;
                    if (!naturalWidth || !naturalHeight) {
                        if (message) { message.textContent = 'File gambar denah kosong atau tidak valid.'; message.classList.remove('d-none'); }
                        return;
                    }
                    var scale = Math.min(bounds.width / naturalWidth, bounds.height / naturalHeight, 1);
                    var displayWidth = Math.max(1, Math.round(naturalWidth * scale));
                    var displayHeight = Math.max(1, Math.round(naturalHeight * scale));
                    direct.style.width = displayWidth + 'px';
                    direct.style.height = displayHeight + 'px';
                    direct.style.maxWidth = 'none';
                    direct.style.maxHeight = 'none';
                    direct.style.objectFit = 'contain';
                    direct.style.display = 'block';
                    stage.style.width = displayWidth + 'px';
                    stage.style.height = displayHeight + 'px';
                    stage.style.minHeight = '0';
                    stage.style.maxWidth = 'none';
                    stage.style.maxHeight = 'none';
                    if (message) message.classList.add('d-none');
                    applyMapTransform();
                    renderPoints();
                };
                direct.onerror = function () {
                    if (requestId !== pdfRenderSequence) return;
                    console.error('Inspection map image URL failed:', map.MapUrl);
                    if (message) {
                        message.textContent = 'Gambar denah tidak dapat dibuka dari URL: ' + map.MapUrl;
                        message.classList.remove('d-none');
                    }
                };
                direct.src = map.MapUrl;
                return;
            }

            var blob = map.MapBlob || map.PdfBlob || null;
            if (!blob || typeof blob.arrayBuffer !== 'function') {
                var response = await fetch(map.MapUrl, { credentials: 'same-origin' });
                if (requestId !== pdfRenderSequence) return;
                if (!response.ok) throw new Error('HTTP ' + response.status);
                blob = await response.blob();
                if (requestId !== pdfRenderSequence) return;
                map.MapBlob = blob;
            }
            var mime = String(blob.type || '').toLowerCase();
            var urlPath = String(map.MapUrl).split('?')[0].toLowerCase();
            // Do not rely only on Content-Type or URL extension: some download
            // endpoints return PNG bytes as application/octet-stream with an
            // extensionless URL. Detect the actual file signature as well.
            var fileHead = new Uint8Array(await blob.slice(0, 16).arrayBuffer());
            if (requestId !== pdfRenderSequence) return;
            var isPng = fileHead.length >= 8 &&
                fileHead[0] === 0x89 && fileHead[1] === 0x50 && fileHead[2] === 0x4e &&
                fileHead[3] === 0x47 && fileHead[4] === 0x0d && fileHead[5] === 0x0a &&
                fileHead[6] === 0x1a && fileHead[7] === 0x0a;
            var isJpeg = fileHead.length >= 3 && fileHead[0] === 0xff &&
                fileHead[1] === 0xd8 && fileHead[2] === 0xff;
            var isGif = fileHead.length >= 6 && String.fromCharCode.apply(null, fileHead.slice(0, 6)).indexOf('GIF8') === 0;
            var isWebp = fileHead.length >= 12 && String.fromCharCode.apply(null, fileHead.slice(0, 4)) === 'RIFF' &&
                String.fromCharCode.apply(null, fileHead.slice(8, 12)) === 'WEBP';
            var isBmp = fileHead.length >= 2 && fileHead[0] === 0x42 && fileHead[1] === 0x4d;
            var isImage = mime.indexOf('image/') === 0 || isPng || isJpeg || isGif || isWebp || isBmp ||
                /\.(jpg|jpeg|png|gif|bmp|webp|svg)$/.test(urlPath);
            if (isImage) {
                canvas.style.display = 'none';
                var image = document.createElement('img'); image.className = 'inspection-map-image'; image.alt = 'Inspection floor plan'; image.draggable = false;
                stage.insertBefore(image, document.getElementById('inspectionMapPoints'));
                var objectUrl = URL.createObjectURL(blob); image.dataset.objectUrl = objectUrl;
                image.onload = function () {
                    if (requestId !== pdfRenderSequence) return;
                    var fitBounds = getInspectionMapFitBounds();
                    var availableWidth = fitBounds.width;
                    var availableHeight = fitBounds.height;
                    var naturalWidth = image.naturalWidth || image.clientWidth;
                    var naturalHeight = image.naturalHeight || image.clientHeight;
                    var imageScale = Math.min(availableWidth / naturalWidth, availableHeight / naturalHeight, 1);
                    var displayWidth = Math.max(1, Math.round(naturalWidth * imageScale));
                    var displayHeight = Math.max(1, Math.round(naturalHeight * imageScale));
                    image.style.width = displayWidth + 'px';
                    image.style.height = displayHeight + 'px';
                    image.style.maxWidth = 'none'; image.style.maxHeight = 'none';
                    image.style.objectFit = 'contain'; image.style.display = 'block';
                    stage.style.width = displayWidth + 'px';
                    stage.style.height = displayHeight + 'px';
                    stage.style.minHeight = '0';
                    stage.style.maxWidth = 'none'; stage.style.maxHeight = 'none';
                    if (message) message.classList.add('d-none'); applyMapTransform(); renderPoints();
                };
                image.onerror = function () {
                    if (requestId !== pdfRenderSequence) return;
                    if (message) { message.textContent = 'File gambar denah tidak dapat dibuka.'; message.classList.remove('d-none'); }
                };
                image.src = objectUrl; return;
            }
            canvas.style.display = 'block';
            if (!window.pdfjsLib) throw new Error('PDF.js belum termuat. Periksa file pdf.min.js.');
            window.pdfjsLib.GlobalWorkerOptions.workerSrc = '../JSCus/pdf.worker.min.js';
            var pdfData = new Uint8Array(await blob.arrayBuffer());
            if (requestId !== pdfRenderSequence) return;
            // A successful HTTP response can still contain a login/error HTML page
            // or an unexpected file. Validate the PDF header before invoking PDF.js.
            var pdfHeaderFound = false;
            var headerLimit = Math.min(pdfData.length, 1024);
            for (var headerIndex = 0; headerIndex <= headerLimit - 5; headerIndex++) {
                if (pdfData[headerIndex] === 0x25 && pdfData[headerIndex + 1] === 0x50 &&
                    pdfData[headerIndex + 2] === 0x44 && pdfData[headerIndex + 3] === 0x46 &&
                    pdfData[headerIndex + 4] === 0x2d) {
                    pdfHeaderFound = true;
                    break;
                }
            }
            if (!pdfHeaderFound) {
                var signature = Array.prototype.slice.call(pdfData.subarray(0, 8)).map(function (value) {
                    return value.toString(16).padStart(2, '0');
                }).join(' ');
                throw new Error('Respons denah bukan PDF yang valid (Content-Type: ' +
                    (mime || 'tidak diketahui') + ', ukuran: ' + blob.size + ' byte, signature: ' +
                    (signature || 'kosong') + '). Periksa URL atau file map di server.');
            }
            var loadedDocument = await window.pdfjsLib.getDocument({ data: pdfData }).promise;
            if (requestId !== pdfRenderSequence) {
                if (loadedDocument && loadedDocument.destroy) loadedDocument.destroy();
                return;
            }
            currentPdfDocument = loadedDocument;
            var page = await currentPdfDocument.getPage(1);
            if (requestId !== pdfRenderSequence) return;
            currentPdfPage = page;
            var base = page.getViewport({ scale: 1 });
            var fitBounds = getInspectionMapFitBounds();
            var width = fitBounds.width;
            var height = fitBounds.height;
            var fitScale = Math.min(width / base.width, height / base.height);
            // Keep the canvas at its fitted CSS size, but render enough backing pixels
            // for the current zoom level. Zoom changes trigger a fresh PDF.js render.
            currentPdfFitScale = fitScale;
            await renderPdfCanvasAtZoom();
            if (requestId !== pdfRenderSequence) return;
            if (message) message.classList.add('d-none'); applyMapTransform(); renderPoints();
        } catch (error) {
            if (requestId !== pdfRenderSequence) return;
            console.error('Inspection map render failed:', error);
            if (message) { message.textContent = 'Denah gagal dimuat: ' + (error && error.message ? error.message : 'periksa file map.'); message.classList.remove('d-none'); }
        }
    }
    function hasMapGroups() {
        return currentMaps.some(function (map) {
            var groupId = map.MapGroupID;
            if (groupId === null || groupId === undefined) return false;
            var value = String(groupId).trim();
            return value !== "" && value !== "0" && value.toLowerCase() !== "null" && value.toLowerCase() !== "undefined";
        });
    }

    function renderMapCards() {
        var host = document.getElementById("inspectionMapCards");
        var picker = document.getElementById("inspectionMapPicker");
        if (!host) return;
        if (!hasMapGroups()) {
            host.innerHTML = "";
            if (picker) picker.classList.add("d-none");
            return;
        }
        if (picker) picker.classList.remove("d-none");
        if (!currentMaps.length) {
            host.innerHTML = '<div class="alert alert-light border small mb-0">Belum ada Inspection Map untuk Inspection Detail Code ini.</div>';
            return;
        }
        host.innerHTML = currentMaps.map(function (map) {
            var mapName = String(map.MapName || "Inspection Map");
            return '<button type="button" class="inspection-map-choice-card" data-inspection-map-id="' + esc(map.MapID) +
                '" title="' + esc(mapName) + '" aria-label="Pilih denah ' + esc(mapName) + '">' +
                '<i class="bi bi-map" aria-hidden="true"></i>' +
                '<span class="inspection-map-choice-title">' + esc(mapName) + '</span>' +
                '</button>';
        }).join("");
        host.querySelectorAll("[data-inspection-map-id]").forEach(function (button) {
            button.addEventListener("click", function () {
                showSelectedInspectionMap(this.getAttribute("data-inspection-map-id"));
            });
        });
        updateSelectedMapCard();
    }

    function updateSelectedMapCard() {
        var host = document.getElementById("inspectionMapCards");
        if (!host) return;
        host.querySelectorAll("[data-inspection-map-id]").forEach(function (button) {
            var selected = String(button.getAttribute("data-inspection-map-id")) === String(currentMapId);
            button.classList.toggle("selected", selected);
            if (selected) button.setAttribute("aria-current", "true");
            else button.removeAttribute("aria-current");
        });
    }

    function showMapPicker() {
        var picker = document.getElementById("inspectionMapPicker");
        var content = document.getElementById("inspectionMapContent");
        var summaryHost = document.getElementById("inspectionMapSummaryHost");
        var submitBar = document.getElementById("inspectionMapSubmitBar");
        var nextButton = document.getElementById("btnInspectionNextPending");
        if (picker) picker.classList.toggle("d-none", !hasMapGroups());
        if (content) content.classList.add("d-none");
        if (summaryHost) summaryHost.classList.add("d-none");
        if (submitBar) submitBar.classList.add("d-none");
        if (nextButton) nextButton.classList.add("d-none");
        currentMapId = "";
        renderMapCards();
        closePoint();
        resetMapView();
        if (currentMaps.length) showSelectedInspectionMap(currentMaps[0].MapID);
    }

    function showSelectedInspectionMap(mapId, preserveView) {
        var map = currentMaps.find(function (item) { return Number(item.MapID) === Number(mapId); });
        if (!map) return;
        closeOptionSummaryPopover();
        currentMapId = String(map.MapID);
        var workspace = document.getElementById("inspectionMapWorkspace");
        var toolbar = workspace && workspace.querySelector(".inspection-map-toolbar");
        var content = document.getElementById("inspectionMapContent");
        var summaryHost = document.getElementById("inspectionMapSummaryHost");
        var submitBar = document.getElementById("inspectionMapSubmitBar");
        var nextButton = document.getElementById("btnInspectionNextPending");
        // Lihat Map must always restore the map chrome even if a previous tab
        // transition left a stale hidden state on one of these workspace rows.
        if (workspace) workspace.classList.remove("d-none");
        if (toolbar) {
            toolbar.classList.remove("d-none");
            toolbar.removeAttribute("hidden");
            toolbar.style.removeProperty("display");
        }
        if (content) content.classList.remove("d-none");
        if (summaryHost) summaryHost.classList.remove("d-none");
        if (submitBar) submitBar.classList.remove("d-none");
        if (nextButton) nextButton.classList.toggle("d-none", String(currentMapRecord && currentMapRecord.Status || "").toUpperCase() === "DONE");
        var title = document.getElementById("inspectionMapTitle");
        var subtitle = document.getElementById("inspectionMapSubtitle");
        if (title) title.textContent = map.MapName || "Inspection Map";
        if (subtitle) subtitle.textContent = (map.MapCode || "") + " · " + currentPoints.filter(function (point) {
                return Number(point.MapID) === Number(map.MapID);
            }).length + " inspection points";
        updateSelectedMapCard();
        var listHost = document.getElementById("inspectionPointList");
        var previousListScrollTop = preserveView && listHost ? listHost.scrollTop : 0;
        closePoint();
        switchMapList();
        if (!preserveView) {
            resetMapView();
            listPage = 1;
            listKeyword = "";
        }
        renderList();
        if (preserveView && listHost) listHost.scrollTop = previousListScrollTop;
        updateSummary();
        renderPoints();
        window.requestAnimationFrame(function () {
            if (preserveView) applyMapTransform();
            else renderPdf(map);
        });
    }

    function setInspectionSectionNavForTab(tabName) {
        var navHost = document.getElementById("inspectionSectionNavHost");
        if (!navHost) return;
        // Section navigation is useful only while filling checklist sections.
        navHost.classList.toggle("d-none", tabName !== "checklist");
    }

    window.resetInspectionMapWorkspace = async function () {
        closeOptionSummaryPopover();
        document.body.classList.remove("inspection-map-mobile-active");
        document.body.classList.remove("inspection-map-tab-active");
        currentMapRecord = null;
        currentScheduleTime = "";
        var scheduleTabs = document.getElementById("inspectionLightningScheduleTabs");
        if (scheduleTabs) { scheduleTabs.innerHTML = ""; scheduleTabs.classList.add("d-none"); }
        currentMaps = [];
        currentPoints = [];
        currentMapId = "";
        selectedPoint = null;
        listPage = 1;
        listKeyword = "";
        resetMapView();
        closePoint();
        var list = document.getElementById("inspectionPointList");
        if (list) { list.scrollTop = 0; list.innerHTML = ""; }
        var points = document.getElementById("inspectionMapPoints");
        if (points) points.innerHTML = "";
        var summary = document.getElementById("inspectionMapSummaryHost");
        var checklistPane = document.getElementById("inspectionChecklistPane");
        if (checklistPane) {
            ["inspectionFollowUpPanel", "inspectionSummaryPanel", "inspectionReasonVoidPanel"].forEach(function (id) {
                var panel = document.getElementById(id);
                if (panel) checklistPane.appendChild(panel);
            });
        }
        if (summary) summary.innerHTML = "";
        var title = document.getElementById("inspectionMapTitle");
        var subtitle = document.getElementById("inspectionMapSubtitle");
        if (title) title.textContent = "Inspection Map";
        if (subtitle) subtitle.textContent = "Warna titik menunjukkan status inspeksi";
        await renderPdf(null);
        var workspace = document.getElementById("inspectionMapWorkspace");
        if (workspace) workspace.classList.add("d-none");
    };

    window.showInspectionMapWorkspace = function (record, activate) {
        var isDifferentRecord = !!record && (!currentMapRecord ||
            String(currentMapRecord.LocalInspectionID || "") !== String(record.LocalInspectionID || ""));
        if (isDifferentRecord) {
            currentScheduleTime = "";
            currentMapId = "";
            selectedPoint = null;
            listPage = 1;
            listKeyword = "";
            resetMapView();
            closePoint();
        }
        if (record) currentMapRecord = record;
        record = record || currentMapRecord;
        var workspace = document.getElementById("inspectionMapWorkspace");
        if (!workspace || !record) return;
        if (typeof window.mountInspectionBatchSummary === "function")
            window.mountInspectionBatchSummary(record);

        var setup = record.BatchMapSetup || {};
        if (String(record.InspectionPointMode || "").toUpperCase() === "DYNAMIC" &&
            (!Array.isArray(setup.points) || !setup.points.length) && Array.isArray(record.Points)) {
            setup.points = record.Points.map(function (transaction, index) {
                return {
                    InspectionPointID: Number(transaction.InspectionPointID),
                    ClientPointID: transaction.ClientPointID,
                    PointCode: transaction.PointCode || ("M" + String(index + 1).padStart(3, "0")),
                    PointName: transaction.PointName || "",
                    Nopol: transaction.PointName || "",
                    MapID: 0,
                    DisplayOrder: index + 1,
                    IsNormalAbnormalRequired: false
                };
            });
            setup.maps = [];
            record.BatchMapSetup = setup;
        }
        currentMaps = Array.isArray(setup.maps) ? setup.maps : [];
        if ((String(record.InspectionMode || "").toUpperCase() === "BATCH" && String(record.ScheduleSelectionMode || "").toUpperCase() === "INSPECT")) {
            var recordActiveSchedule = String(record.ActiveScheduleTime || "");
            var scheduleExists = function (value) {
                return Array.isArray(record.Schedules) &&
                    record.Schedules.some(function (item) { return String(item.ScheduleTime || item) === value; });
            };
            if (recordActiveSchedule && scheduleExists(recordActiveSchedule))
                currentScheduleTime = recordActiveSchedule;
            else if (!currentScheduleTime || !scheduleExists(currentScheduleTime))
                currentScheduleTime = String(record.Schedules && record.Schedules.length
                    ? (record.Schedules[0].ScheduleTime || record.Schedules[0]) : "");
            if (typeof window.setInspectionActiveScheduleTime === "function")
                window.setInspectionActiveScheduleTime(currentScheduleTime);
        } else currentScheduleTime = "";
        renderLightningScheduleTabs();
        currentPoints = Array.isArray(setup.points) ? setup.points : [];
        if (!currentPoints.length && Array.isArray(record.PointMaster)) currentPoints = record.PointMaster;
        if (!currentMaps.some(function (map) { return Number(map.MapID) === Number(currentMapId); }))
            currentMapId = "";

        var nextPendingButton = document.getElementById("btnInspectionNextPending");
        if (nextPendingButton) nextPendingButton.classList.toggle("d-none", String(record.Status || "").toUpperCase() === "DONE");

        var submitBatchButton = document.getElementById("btnSubmitInspectionBatch");
        if (submitBatchButton) submitBatchButton.classList.toggle("d-none", String(record.Status || "").toUpperCase() === "DONE");

        var typeName = record.InspectionTypeName || "Inspection";
        var detailName = record.InspectionTypeDetailName || "";
        var title = document.getElementById("inspectionMapTitle");
        var subtitle = document.getElementById("inspectionMapSubtitle");
        if (title) title.textContent = typeName + (detailName ? " · " + detailName : "");
        if (subtitle) subtitle.textContent = ((String(record.InspectionMode || "").toUpperCase() === "BATCH" && String(record.ScheduleSelectionMode || "").toUpperCase() === "INSPECT")
            ? "Jadwal " + getActiveScheduleTime() + " · "
            : "Batch " + (record.InspectionNo || "baru") + " · ") + currentPoints.length + " Unit Inspeksi";

        var selectedMap = currentMaps.find(function (map) {
            return Number(map.MapID) === Number(currentMapId);
        }) || null;

        var dynamicListMode = String(record.InspectionLayoutCode || "").toUpperCase() === "DYNAMIC_LIST" &&
            String(record.InspectionPointMode || "").toUpperCase() === "DYNAMIC";
        if (activate && dynamicListMode) {
            workspace.classList.add("inspection-dynamic-list-mode");
            document.body.classList.add("inspection-map-tab-active");
            document.body.classList.remove("inspection-map-mobile-active");
            workspace.classList.remove("d-none");
            var paramPane = document.getElementById("inspectionParamsPane");
            var checklistPane = document.getElementById("inspectionChecklistPane");
            if (paramPane) paramPane.classList.add("d-none");
            if (checklistPane) checklistPane.classList.add("d-none");
            var picker = document.getElementById("inspectionMapPicker");
            var content = document.getElementById("inspectionMapContent");
            var mapPanel = workspace.querySelector(".inspection-map-panel");
            var list = document.getElementById("inspectionPointList");
            var entry = document.getElementById("inspectionDynamicPointEntry");
            var submitBar = document.getElementById("inspectionMapSubmitBar");
            var summary = document.getElementById("inspectionMapSummaryHost");
            var toolbar = workspace.querySelector(".inspection-map-toolbar");
            if (picker) picker.classList.add("d-none");
            if (content) { content.classList.remove("d-none"); content.classList.add("no-map"); }
            if (mapPanel) mapPanel.classList.add("d-none");
            if (list) { list.classList.remove("d-none"); list.style.display = "block"; }
            if (entry) {
                var dynamicReadOnly = !!currentInspectionReadOnly || String(record.Status || "").toUpperCase() === "DONE";
                // Do not ask for another motor before the automatically-created
                // first motor has a Nopol. Its Nopol is entered in the checklist.
                var hasRegisteredMotor = currentPoints.some(function (point) {
                    return !!String(point.PointName || point.Nopol || "").trim();
                });
                entry.classList.toggle("d-none", dynamicReadOnly || !hasRegisteredMotor);
                var plateInput = document.getElementById("txtInspectionDynamicPointName");
                var addPlateButton = document.getElementById("btnAddInspectionDynamicPoint");
                if (plateInput) plateInput.disabled = dynamicReadOnly;
                if (addPlateButton) addPlateButton.disabled = dynamicReadOnly;
            }
            if (submitBar) submitBar.classList.toggle("d-none", String(record.Status || "").toUpperCase() === "DONE");
            if (summary) summary.classList.remove("d-none");
            if (toolbar) toolbar.classList.remove("d-none");
            var mapTab = document.getElementById("btnInspectionMapTab");
            var paramTab = document.getElementById("btnInspectionParamTab");
            var checklistTab = document.getElementById("btnInspectionChecklistTab");
            if (mapTab) mapTab.classList.add("active");
            if (paramTab) paramTab.classList.remove("active");
            if (checklistTab) checklistTab.classList.remove("active");
            setInspectionSectionNavForTab("map");
            currentMapId = "";
            selectedPoint = null;
            renderList();
            updateSummary();
            if (typeof window.updateInspectionParameterTabGate === "function")
                window.updateInspectionParameterTabGate();
        } else if (activate) {
            workspace.classList.remove("inspection-dynamic-list-mode");
            // Apply the mobile full-height layout before revealing the map so PDF.js measures a real viewport.
            document.body.classList.add("inspection-map-tab-active");
            var mobileMapViewport = window.matchMedia &&
                window.matchMedia("(max-width: 767.98px)").matches;
            document.body.classList.toggle("inspection-map-mobile-active", !!mobileMapViewport);
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
            setInspectionSectionNavForTab("map");
            closePoint();
            switchMapList();
            if (!isDifferentRecord && selectedMap) {
                showSelectedInspectionMap(selectedMap.MapID, true);
            } else {
                showMapPicker();
            }
            if (typeof window.updateInspectionParameterTabGate === "function")
                window.updateInspectionParameterTabGate();
        } else if (!workspace.classList.contains("d-none") && selectedMap) {
            renderPdf(selectedMap);
        }

        // MAP activation changes the editor into a full-height flex layout.
        // Refresh Approval Workflow after that transition so new BATCH / INSPECT drafts
        // are visible even though none of the workflow stages has been submitted.
        if (typeof window.renderInspectionApprovalWorkflowCards === "function")
            window.renderInspectionApprovalWorkflowCards(record, record.InspectionMode);
    };

    async function waitForInspectionMapStage() {
        return new Promise(function (resolve) {
            var attempts = 0;
            function check() {
                var stage = document.getElementById("inspectionMapPdfStage");
                var canvas = document.getElementById("inspectionMapPdfCanvas");
                var image = stage && stage.querySelector("img.inspection-map-image");
                var message = document.getElementById("inspectionMapPdfMessage");
                var imageReady = !!(image && image.complete && image.naturalWidth > 0);
                var pdfReady = !!(canvas && canvas.width > 0 && canvas.height > 0);
                var ready = !!(stage && stage.clientWidth > 1 && (imageReady || pdfReady) &&
                    (!message || message.classList.contains("d-none")));
                if (ready || attempts++ >= 240) {
                    resolve(ready);
                    return;
                }
                window.requestAnimationFrame(check);
            }
            window.requestAnimationFrame(check);
        });
    }

    window.focusInspectionMapPoint = async function (pointId) {
        var focusSequence = ++navigatorFocusRequestSequence;
        navigatorFocusDismissedPointId = "";
        navigatorFocusPendingPointId = String(pointId);
        var point = currentPoints.find(function (item) {
            return Number(item.InspectionPointID) === Number(pointId);
        });
        if (!point) return false;
        var map = currentMaps.find(function (item) {
            return Number(item.MapID) === Number(point.MapID);
        });
        if (!map) return false;

        showSelectedInspectionMap(map.MapID);
        var ready = await waitForInspectionMapStage();
        if (focusSequence !== navigatorFocusRequestSequence) return false;
        renderPoints();
        if (!ready) {
            // The Point List is a desktop fallback only. Mobile Navigator
            // remains map-first and must never open the obsolete list modal.
            var isMobileMapViewport = window.matchMedia &&
                window.matchMedia("(max-width: 767.98px)").matches;
            var listHost = !isMobileMapViewport ? document.getElementById("inspectionPointList") : null;
            if (listHost) {
                var fallbackRow = Array.from(listHost.querySelectorAll("[data-point-id]")).find(function (item) {
                    return Number(item.getAttribute("data-point-id")) === Number(pointId);
                });
                if (fallbackRow) fallbackRow.scrollIntoView({ behavior: "smooth", block: "center" });
            }
            return false;
        }

        var viewport = document.getElementById("inspectionMapCanvas");
        var stage = document.getElementById("inspectionMapPdfStage");
        if (!viewport || !stage || point.MapX === null || point.MapX === undefined ||
            point.MapY === null || point.MapY === undefined) return false;

        resetMapView();
        var viewportRect = viewport.getBoundingClientRect();
        var stageRect = stage.getBoundingClientRect();
        var focusPosition = getPointMapFocusPosition(point);
        var x = focusPosition.x;
        var y = focusPosition.y;
        var pointX = stageRect.left + stageRect.width * x / 100;
        var pointY = stageRect.top + stageRect.height * y / 100;
        var stageCenterX = stageRect.left + stageRect.width / 2;
        var zoom = Math.min(mapMaxZoom, Math.max(2.2, mapMinZoom));
        mapZoom = zoom;
        mapPanX = viewportRect.left + viewportRect.width / 2 -
            (stageCenterX + (pointX - stageCenterX) * zoom);
        mapPanY = viewportRect.top + viewportRect.height / 2 -
            (stageRect.top + (pointY - stageRect.top) * zoom);
        applyMapTransform();
        schedulePdfCanvasRender();

        if (focusSequence !== navigatorFocusRequestSequence) return false;
        var pointHost = document.getElementById("inspectionMapPoints");
        if (pointHost) {
            pointHost.querySelectorAll("[data-point-id]").forEach(function (element) {
                var isTarget = Number(element.getAttribute("data-point-id")) === Number(pointId);
                element.classList.toggle("selected", isTarget);
                element.classList.toggle("navigator-target", isTarget);
            });

            // Keep a dedicated animated ring above the map so the target remains
            // obvious even when its normal marker is small or is a vector PATH.
            removeNavigatorFocusRing();
            if (navigatorFocusDismissedPointId !== String(pointId)) {
                var targetPosition = getPointMapFocusPosition(point);
                var targetX = targetPosition.x;
                var targetY = targetPosition.y;
                var ring = document.createElement("div");
                ring.className = "inspection-map-navigator-focus-ring";
                ring.style.left = targetX + "%";
                ring.style.top = targetY + "%";
                ring.setAttribute("aria-hidden", "true");
                ring.setAttribute("data-navigator-target", String(pointId));
                pointHost.appendChild(ring);
            }
        }
        selectedPoint = point;
        // Desktop retains the Point List page/highlight synchronization.
        // On phones the requested interaction is map-first: keep the focus
        // pulse on the marker and wait for the user to tap it to open checklist.
        var isMobileMapViewport = window.matchMedia &&
            window.matchMedia("(max-width: 767.98px)").matches;
        if (!isMobileMapViewport) scrollPointListToRow(pointId);
        return true;
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
        var optionInfoButton = document.getElementById("btnInspectionMapOptionInfo");
        var optionSummaryHost = document.getElementById("inspectionMapOptionSummaryHost");
        if (optionInfoButton && optionSummaryHost) {
            optionSummaryHost.addEventListener("click", function (event) {
                var optionButton = event.target && event.target.closest
                    ? event.target.closest("[data-open-inspection-option]") : null;
                if (optionButton) {
                    event.preventDefault();
                    event.stopPropagation();
                    closeOptionSummaryPopover();
                    if (typeof window.openInspectionPointNavigator === "function")
                        window.openInspectionPointNavigator({
                            mapId: "all",
                            optionFilter: optionButton.getAttribute("data-open-inspection-option") || ""
                        });
                    return;
                }
                var unfilledButton = event.target && event.target.closest
                    ? event.target.closest("[data-open-inspection-unfilled]") : null;
                if (!unfilledButton) return;
                event.preventDefault();
                event.stopPropagation();
                closeOptionSummaryPopover();
                if (typeof window.openInspectionPointNavigator === "function")
                    window.openInspectionPointNavigator({ mapId: "all", statusFilter: "unfilled" });
            });
            optionInfoButton.addEventListener("click", function (event) {
                event.stopPropagation();
                if (optionSummaryHost.getAttribute("data-has-summary") !== "true") return;
                var opening = optionSummaryHost.classList.contains("d-none");
                optionSummaryHost.classList.toggle("d-none", !opening);
                optionInfoButton.setAttribute("aria-expanded", opening ? "true" : "false");
                if (opening) positionOptionSummaryPopover();
                else resetOptionSummaryPopoverPosition(optionSummaryHost);
            });
            window.addEventListener("resize", function () {
                if (!optionSummaryHost.classList.contains("d-none"))
                    positionOptionSummaryPopover();
            });
            document.addEventListener("click", function (event) {
                if (optionSummaryHost.classList.contains("d-none")) return;
                if (event.target && event.target.closest &&
                    event.target.closest("#inspectionMapOptionSummaryHost, #btnInspectionMapOptionInfo")) return;
                optionSummaryHost.classList.add("d-none");
                optionInfoButton.setAttribute("aria-expanded", "false");
            });
            document.addEventListener("keydown", function (event) {
                if (event.key !== "Escape" || optionSummaryHost.classList.contains("d-none")) return;
                optionSummaryHost.classList.add("d-none");
                optionInfoButton.setAttribute("aria-expanded", "false");
                optionInfoButton.focus();
            });
        }
        var pointNavigatorButton = document.getElementById("btnInspectionPointNavigator");
        if (pointNavigatorButton) pointNavigatorButton.addEventListener("click", function () {
            if (typeof window.openInspectionPointNavigator === "function")
                window.openInspectionPointNavigator();
            else if (typeof showToast === "function")
                showToast("Point Navigator belum siap. Refresh aplikasi setelah update.", "warning");
        });
        var pointListButton = document.getElementById("btnInspectionMapPointList");
        var pointListModalElement = document.getElementById("inspectionPointListModal");
        var pointListModalBody = document.getElementById("inspectionPointListModalBody");
        var pointListHost = document.getElementById("inspectionPointList");
        var mapContentHost = document.getElementById("inspectionMapContent");
        if (pointListButton && pointListModalElement && pointListModalBody && pointListHost && window.bootstrap && bootstrap.Modal) {
            var pointListModal = bootstrap.Modal.getOrCreateInstance(pointListModalElement);
            pointListButton.addEventListener("click", function () {
                pointListModalBody.appendChild(pointListHost);
                pointListButton.setAttribute("aria-expanded", "true");
                pointListModal.show();
            });
            pointListModalElement.addEventListener("hidden.bs.modal", function () {
                if (mapContentHost) mapContentHost.appendChild(pointListHost);
                pointListButton.setAttribute("aria-expanded", "false");
            });
            pointListModalElement.addEventListener("shown.bs.modal", function () {
                var search = pointListHost.querySelector("#inspectionPointSearch");
                if (search) search.focus();
            });
        }
        var zoomIn = document.getElementById("btnInspectionMapZoomIn");
        var zoomOut = document.getElementById("btnInspectionMapZoomOut");
        var zoomReset = document.getElementById("btnInspectionMapZoomReset");
        if (zoomIn) zoomIn.addEventListener("click", function () { zoomMapTo(mapZoom * 1.25); });
        if (zoomOut) zoomOut.addEventListener("click", function () { zoomMapTo(mapZoom / 1.25); });
        if (zoomReset) zoomReset.addEventListener("click", resetMapView);

        var mapTab = document.getElementById("btnInspectionMapTab");
        if (mapTab) mapTab.addEventListener("click", function () {
            if (currentMapRecord && Number(currentMapRecord.ActiveInspectionPointID || 0) !== 0) {
                // Returning to MAP is navigation, not Save Point. Discard the
                // unsaved editor values and leave previously saved point data intact.
                currentMapRecord.ActiveInspectionPointID = 0;
                currentMapRecord.Items = [];
            }
            setInspectionSectionNavForTab("map");
            if (window.showInspectionMapWorkspace) window.showInspectionMapWorkspace(currentMapRecord, true);
        });

        var checklistTab = document.getElementById("btnInspectionChecklistTab");
        if (checklistTab) checklistTab.addEventListener("click", function () {
            document.body.classList.remove("inspection-map-tab-active");
            if (currentMapRecord && String(currentMapRecord.InspectionMode || "").toUpperCase() === "BATCH" &&
                !Number(currentMapRecord.ActiveInspectionPointID || 0)) {
                if (typeof showToast === "function")
                    showToast("Pilih Inspection Point dari denah atau daftar terlebih dahulu.", "info");
                return;
            }
            setInspectionSectionNavForTab("checklist");
            var workspace = document.getElementById("inspectionMapWorkspace");
            if (workspace) workspace.classList.add("d-none");
        });

        var paramTab = document.getElementById("btnInspectionParamTab");
        if (paramTab) paramTab.addEventListener("click", function () {
            setInspectionSectionNavForTab("param");
            document.body.classList.remove("inspection-map-tab-active");
            var workspace = document.getElementById("inspectionMapWorkspace");
            if (workspace) workspace.classList.add("d-none");
        });

        var close = document.getElementById("btnCloseInspectionMapPoint");
        if (close) close.addEventListener("click", function () {
            if (document.getElementById("inspectionMapPointSheet")?.classList.contains("checklist-mode")) {
                window.closeInspectionMapPointChecklistSheet(false);
                if (window.inspectionReturnToPointNavigator) {
                    var navigatorModal = document.getElementById("inspectionPointNavigatorModal");
                    if (navigatorModal && window.bootstrap && bootstrap.Modal)
                        bootstrap.Modal.getOrCreateInstance(navigatorModal).show();
                }
                return;
            }
            closePoint();
        });
        var cancelQuick = document.getElementById("btnCancelInspectionMapPoint");
        if (cancelQuick) cancelQuick.addEventListener("click", closePoint);
        var applyQuick = document.getElementById("btnApplyInspectionMapPoint");
        if (applyQuick) applyQuick.addEventListener("click", applyQuickPointSheet);
        var quickBackdrop = document.getElementById("inspectionMapPointSheetBackdrop");
        if (quickBackdrop) quickBackdrop.addEventListener("click", function () {
            if (document.getElementById("inspectionMapPointSheet")?.classList.contains("checklist-mode")) {
                window.closeInspectionMapPointChecklistSheet(false);
                if (window.inspectionReturnToPointNavigator) {
                    var navigatorModal = document.getElementById("inspectionPointNavigatorModal");
                    if (navigatorModal && window.bootstrap && bootstrap.Modal)
                        bootstrap.Modal.getOrCreateInstance(navigatorModal).show();
                }
                return;
            }
            closePoint();
        });
                var quickOptions = document.getElementById("inspectionMapQuickOptions");
        if (quickOptions) quickOptions.addEventListener("click", function (event) {
            var button = event.target.closest("[data-quick-option-item]");
            if (!button || button.disabled) return;
            var itemId = button.getAttribute("data-quick-option-item");
            var wasActive = button.classList.contains("active");
            quickOptions.querySelectorAll('[data-quick-option-item="' + itemId.replace(/"/g, '\\"') + '"]').forEach(function (option) {
                option.classList.remove("active");
            });
            if (!wasActive) button.classList.add("active");
        });
        var mapView = document.getElementById("btnInspectionMapView");
        var listView = document.getElementById("btnInspectionPointListView");
        if (mapView) mapView.addEventListener("click", function () { switchMapList(); });
        if (listView) listView.addEventListener("click", function () { switchMapList(); closePoint(); });

        var reset = document.getElementById("btnInspectionMapReset");
        if (reset) reset.addEventListener("click", function () {
            switchMapList();
            closePoint();
            resetMapView();
        });


        var openChecklist = document.getElementById("btnOpenInspectionPointChecklist");
        if (openChecklist) openChecklist.addEventListener("click", function () {
            if (!selectedPoint) return;
            var point = selectedPoint;
            closePoint();
            if (typeof window.openBatchInspectionPointChecklist === "function") {
                window.openBatchInspectionPointChecklist(point);
            } else {
                if (typeof showToast === "function")
                    showToast("Modul checklist per titik belum siap dibuka.", "warning");
            }
        });

        var submit = document.getElementById("btnSubmitInspectionBatch");
        if (submit) submit.addEventListener("click", function () {
            if (typeof window.submitInspectionBatch === "function") window.submitInspectionBatch();
            else if (typeof showToast === "function")
                showToast("Submit batch belum tersedia.", "warning");
        });
    };

    document.addEventListener("DOMContentLoaded", function () {
        window.setTimeout(function () {
            if (typeof window.wireInspectionMapWorkspace === "function")
                window.wireInspectionMapWorkspace();
        }, 0);
    });
})();
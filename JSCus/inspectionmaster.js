(function () {
    var inspectionDraftDbPromise = null;
    var inspectionDraftWritePromise = Promise.resolve();
    var inspectionDraftRestorePromise = Promise.resolve();
    var inspectionDraftObjectUrl = null;

    function inspectionDraftKey() {
        var input = document.getElementById('fuMapPdf');
        return input ? input.getAttribute('data-inspection-draft-key') : null;
    }
    function inspectionSetUploadPostbackMode(control) {
        var input = document.getElementById('fuMapPdf');
        if (!input) return;
        if (!input.getAttribute('data-inspection-original-name') && input.name)
            input.setAttribute('data-inspection-original-name', input.name);
        var originalName = input.getAttribute('data-inspection-original-name');
        var isSaveMap = !!(control && control.id && control.id.indexOf('lbtn_TB_Save') >= 0);
        var isSavePoint = !!(control && control.id && control.id.indexOf('btnSavePoint') >= 0);
        var mapId = document.getElementById('hidMapID');
        var mapIsDraft = document.getElementById('hidMapIsDraft');
        var isNewOrDraftMap = !mapId || !mapId.value || (mapIsDraft && mapIsDraft.value === '1');
        // Upload the browser draft with the first Save Point that persists a new Map.
        // Existing saved Maps keep the file local until the toolbar Save creates a new version.
        var uploadWithPoint = isSavePoint && isNewOrDraftMap;
        if ((isSaveMap || uploadWithPoint) && originalName) input.name = originalName;
        else input.removeAttribute('name');
    }
    function inspectionOpenDraftDb() {
        if (inspectionDraftDbPromise) return inspectionDraftDbPromise;
        inspectionDraftDbPromise = new Promise(function (resolve, reject) {
            if (!window.indexedDB) { reject(new Error('Browser tidak mendukung IndexedDB.')); return; }
            var request = indexedDB.open('INSPEC_InspectionMapDraft', 1);
            request.onupgradeneeded = function () {
                var db = request.result;
                if (!db.objectStoreNames.contains('drafts')) db.createObjectStore('drafts');
            };
            request.onsuccess = function () { resolve(request.result); };
            request.onerror = function () { reject(request.error || new Error('Gagal membuka IndexedDB.')); };
        });
        return inspectionDraftDbPromise;
    }
    function inspectionDraftStore(mode, key, value) {
        return inspectionOpenDraftDb().then(function (db) {
            return new Promise(function (resolve, reject) {
                var tx = db.transaction('drafts', mode);
                var store = tx.objectStore('drafts');
                var request = mode === 'readwrite'
                    ? (value === null ? store.delete(key) : store.put(value, key))
                    : store.get(key);
                var result;
                request.onsuccess = function () { result = request.result; };
                request.onerror = function () { reject(request.error || new Error('IndexedDB request failed.')); };
                tx.oncomplete = function () { resolve(result); };
                tx.onerror = function () { reject(tx.error || new Error('IndexedDB transaction failed.')); };
                tx.onabort = function () { reject(tx.error || new Error('IndexedDB transaction aborted.')); };
            });
        });
    }
    function inspectionShowDraftPreview(blob, fileName) {
        var board = document.getElementById('inspectionCoordinateBoard');
        var content = document.getElementById('inspectionCoordinateContent');
        if (!board || !content) return;
        var extension = (fileName || '').toLowerCase().split('.').pop();
        if (inspectionDraftObjectUrl) URL.revokeObjectURL(inspectionDraftObjectUrl);
        inspectionDraftObjectUrl = URL.createObjectURL(blob);
        var old = document.getElementById('inspectionPdfCanvas');
        if (extension === 'jpg' || extension === 'jpeg' || (blob.type || '').toLowerCase() === 'image/jpeg') {
            var img = old && old.tagName === 'IMG' ? old : document.createElement('img');
            img.id = 'inspectionPdfCanvas';
            img.className = 'inspection-coordinate-pdf';
            img.alt = 'Inspection floor plan';
            img.onload = function () {
                board.style.aspectRatio = img.naturalWidth + ' / ' + img.naturalHeight;
                var status = document.getElementById('inspectionPdfStatus');
                if (status) status.style.display = 'none';
            };
            if (old && old !== img && old.parentNode) old.parentNode.replaceChild(img, old);
            else if (!old) content.insertBefore(img, content.firstChild);
            img.src = inspectionDraftObjectUrl;
        } else {
            var canvas = old && old.tagName === 'CANVAS' ? old : document.createElement('canvas');
            canvas.id = 'inspectionPdfCanvas';
            canvas.className = 'inspection-coordinate-pdf';
            canvas.setAttribute('data-map-url', inspectionDraftObjectUrl);
            if (old && old !== canvas && old.parentNode) old.parentNode.replaceChild(canvas, old);
            else if (!old) content.insertBefore(canvas, content.firstChild);
            var status = document.getElementById('inspectionPdfStatus');
            if (!status) {
                status = document.createElement('div');
                status.id = 'inspectionPdfStatus';
                status.className = 'inspection-pdf-status';
                content.insertBefore(status, canvas.nextSibling);
            }
            status.textContent = 'Memuat denah draft...';
            status.style.display = 'flex';
            window.requestAnimationFrame(renderInspectionPdf);
        }
    }
    function inspectionRestoreDraft() {
        var key = inspectionDraftKey();
        var input = document.getElementById('fuMapPdf');
        if (!key || !input) return Promise.resolve();
        return inspectionDraftStore('readonly', key).then(function (draft) {
            if (!draft || !draft.blob) return;
            // The DOM is rebuilt on every WebForms postback. Preserve the
            // rendered FileUpload name before removing it from ordinary postbacks.
            if (!input.getAttribute('data-inspection-original-name') && input.name)
                input.setAttribute('data-inspection-original-name', input.name);
            if (!input.files || !input.files.length) {
                try {
                    var file = new File([draft.blob], draft.fileName || 'inspection-map.pdf', {
                        type: draft.fileType || draft.blob.type || 'application/pdf',
                        lastModified: draft.lastModified || Date.now()
                    });
                    var transfer = new DataTransfer();
                    transfer.items.add(file);
                    input.files = transfer.files;
                } catch (error) {
                    console.error('Cannot restore inspection map draft to FileUpload:', error);
                }
            }
            // Keep the Blob local during Add Point / other postbacks. Only the
            // toolbar Save action temporarily restores the FileUpload name.
            input.removeAttribute('name');
            inspectionShowDraftPreview(draft.blob, draft.fileName);
        }).catch(function (error) {
            console.error('Inspection map draft restore failed:', error);
        });
    }
    window.inspectionMasterClearDraft = function () {
        var key = inspectionDraftKey();
        var input = document.getElementById('fuMapPdf');
        if (input) input.value = '';
        inspectionDraftWritePromise = Promise.all([
            inspectionDraftWritePromise,
            inspectionDraftRestorePromise
        ]).then(function () {
            if (input) {
                input.value = '';
                input.removeAttribute('name');
            }
            return key ? inspectionDraftStore('readwrite', key, null) : null;
        }).then(function () {
            if (inspectionDraftObjectUrl) URL.revokeObjectURL(inspectionDraftObjectUrl);
            inspectionDraftObjectUrl = null;
        }).catch(function (error) { console.error('Inspection map draft clear failed:', error); });
        return true;
    };
    function restoreTab() {
        var hidden = document.getElementById('hidActiveTab');
        var target = hidden && hidden.value ? hidden.value : '#tab-map';
        var tab = document.querySelector('[data-bs-target="' + target + '"]');
        if (tab && window.bootstrap && window.bootstrap.Tab) {
            window.bootstrap.Tab.getOrCreateInstance(tab).show();
        }
    }
    var inspectionMapPreviewPage = null;
    var inspectionMapPreviewFitScale = 1;
    var inspectionMapPreviewRenderTask = null;
    var inspectionMapPreviewRenderTimer = null;
    var inspectionMapPreviewRenderVersion = 0;
    var inspectionMapPreviewZoom = 1;

    function renderMapPreviewCanvasAtZoom() {
        var canvas = document.getElementById('inspectionMapPreviewCanvas');
        if (!canvas || !inspectionMapPreviewPage) return;
        var version = ++inspectionMapPreviewRenderVersion;
        var previousTask = inspectionMapPreviewRenderTask;
        inspectionMapPreviewRenderTask = null;
        var waitForPrevious = Promise.resolve();
        if (previousTask && previousTask.cancel) {
            try { previousTask.cancel(); } catch (ignore) { }
            waitForPrevious = previousTask.promise.catch(function () { });
        }
        waitForPrevious.then(function () {
            if (version !== inspectionMapPreviewRenderVersion) return;
            var ratio = Math.min(window.devicePixelRatio || 1, 2);
            var scale = inspectionMapPreviewFitScale * inspectionMapPreviewZoom * ratio;
            var viewport = inspectionMapPreviewPage.getViewport({ scale: scale });
            canvas.width = Math.max(1, Math.floor(viewport.width));
            canvas.height = Math.max(1, Math.floor(viewport.height));
            var context = canvas.getContext('2d');
            inspectionMapPreviewRenderTask = inspectionMapPreviewPage.render({ canvasContext: context, viewport: viewport });
            return inspectionMapPreviewRenderTask.promise;
        }).then(function () {
            if (version !== inspectionMapPreviewRenderVersion) return;
            inspectionMapPreviewRenderTask = null;
        }).catch(function (error) {
            if (version !== inspectionMapPreviewRenderVersion || (error && error.name === 'RenderingCancelledException')) return;
            inspectionMapPreviewRenderTask = null;
            if (window.console && console.error) console.error('Inspection map preview render error:', error);
        });
    }
    function scheduleMapPreviewCanvasRender() {
        if (!inspectionMapPreviewPage) return;
        if (inspectionMapPreviewRenderTimer) clearTimeout(inspectionMapPreviewRenderTimer);
        inspectionMapPreviewRenderTimer = setTimeout(function () {
            inspectionMapPreviewRenderTimer = null;
            renderMapPreviewCanvasAtZoom();
        }, 140);
    }
    function renderMapPreviewPdf() {
        var canvas = document.getElementById('inspectionMapPreviewCanvas');
        if (!canvas) return;
        var url = canvas.getAttribute('data-map-url');
        var media = document.getElementById('inspectionMapPreviewMedia');
        var stage = document.getElementById('inspectionMapPreviewStage');
        var status = document.getElementById('inspectionMapPreviewStatus');
        if (!url || !media || !stage) return;
        if (!window.pdfjsLib) {
            if (status) status.textContent = 'PDF.js tidak berhasil dimuat. Periksa JSCus/pdf.min.js.';
            return;
        }
        window.pdfjsLib.GlobalWorkerOptions.workerSrc = '../JSCus/pdf.worker.min.js';
        window.pdfjsLib.getDocument({ url: url }).promise.then(function (pdf) {
            return pdf.getPage(1);
        }).then(function (page) {
            var base = page.getViewport({ scale: 1 });
            var width = stage.clientWidth;
            var height = stage.clientHeight;
            if (!width || !height) throw new Error('Area preview denah belum terlihat.');
            inspectionMapPreviewFitScale = Math.min(width / base.width, height / base.height);
            var fitted = page.getViewport({ scale: inspectionMapPreviewFitScale });
            inspectionMapPreviewPage = page;
            inspectionMapPreviewZoom = 1;
            media.style.width = fitted.width + 'px';
            media.style.height = fitted.height + 'px';
            updatePreviewVectorCircleAspect();
            canvas.style.width = '100%';
            canvas.style.height = '100%';
            renderMapPreviewCanvasAtZoom();
        }).then(function () {
            if (status) status.style.display = 'none';
        }).catch(function (error) {
            if (status) {
                status.style.display = 'flex';
                status.textContent = 'Gagal memuat denah PDF: ' + (error && error.message ? error.message : error);
            }
            if (window.console && console.error) console.error('Inspection map preview error:', error);
        });
    }
    function initMapPreviewInteraction() {
        var stage = document.getElementById('inspectionMapPreviewStage');
        var media = document.getElementById('inspectionMapPreviewMedia');
        if (!stage || !media) return;
        var zoom = 1, panX = 0, panY = 0, dragging = false, moved = false, startX = 0, startY = 0;
        var label = document.getElementById('lblMapPreviewZoom');
        function updatePreviewVectorCircleAspect() {
            var svg = media.querySelector('.inspection-map-preview-svg');
            if (!svg || !media.clientWidth || !media.clientHeight) return;
            var aspect = media.clientWidth / media.clientHeight;
            svg.querySelectorAll('.inspection-map-preview-circle').forEach(function (circle) {
                var cx = Number(circle.getAttribute('cx')) || 0;
                var cy = Number(circle.getAttribute('cy')) || 0;
                circle.setAttribute('transform', 'translate(' + cx + ' ' + cy + ') scale(1 ' + aspect + ') translate(' + (-cx) + ' ' + (-cy) + ')');
            });
        }
        var image = media.querySelector('.inspection-image-preview');
        if (image) {
            var sizeImage = function () {
                if (!image.naturalWidth || !image.naturalHeight) return;
                var scale = Math.min(stage.clientWidth / image.naturalWidth, stage.clientHeight / image.naturalHeight);
                var width = Math.max(1, Math.round(image.naturalWidth * scale));
                var height = Math.max(1, Math.round(image.naturalHeight * scale));
                media.style.width = width + 'px';
                media.style.height = height + 'px';
                updatePreviewVectorCircleAspect();
                image.style.width = width + 'px';
                image.style.height = height + 'px';
                image.style.maxWidth = 'none';
                image.style.maxHeight = 'none';
                image.style.objectFit = 'contain';
            };
            image.addEventListener('load', sizeImage);
            if (image.complete) sizeImage();
        }
        function apply() {
            media.style.transform = 'translate(' + panX + 'px,' + panY + 'px) scale(' + zoom + ')';
            updatePreviewVectorCircleAspect();
            if (label) label.textContent = Math.round(zoom * 100) + '%';
            stage.classList.toggle('inspection-map-preview-zoomed', zoom > 1);
        }
        function setZoom(next, cx, cy) {
            next = Math.max(1, Math.min(5, next));
            if (next === zoom) return;
            var rect = stage.getBoundingClientRect();
            var x = cx == null ? rect.width / 2 : cx;
            var y = cy == null ? rect.height / 2 : cy;
            var ratio = next / zoom;
            panX = x - (x - panX) * ratio;
            panY = y - (y - panY) * ratio;
            zoom = next;
            inspectionMapPreviewZoom = zoom;
            if (zoom === 1) { panX = 0; panY = 0; }
            apply();
            scheduleMapPreviewCanvasRender();
        }
        var zoomIn = document.getElementById('btnMapPreviewZoomIn');
        var zoomOut = document.getElementById('btnMapPreviewZoomOut');
        var fit = document.getElementById('btnMapPreviewZoomFit');
        if (zoomIn) zoomIn.addEventListener('click', function () { setZoom(zoom + 0.25); });
        if (zoomOut) zoomOut.addEventListener('click', function () { setZoom(zoom - 0.25); });
        if (fit) fit.addEventListener('click', function () {
            zoom = 1; inspectionMapPreviewZoom = 1; panX = 0; panY = 0; apply(); scheduleMapPreviewCanvasRender();
        });
        stage.addEventListener('wheel', function (event) {
            if (!event.ctrlKey && !event.shiftKey) return;
            event.preventDefault();
            var rect = stage.getBoundingClientRect();
            setZoom(zoom + (event.deltaY < 0 ? 0.25 : -0.25), event.clientX - rect.left, event.clientY - rect.top);
        }, { passive: false });
        stage.addEventListener('pointerdown', function (event) {
            if (zoom <= 1 || event.button !== 0) return;
            dragging = true; moved = false;
            startX = event.clientX - panX; startY = event.clientY - panY;
            stage.setPointerCapture(event.pointerId);
        });
        stage.addEventListener('pointermove', function (event) {
            if (!dragging) return;
            var nx = event.clientX - startX, ny = event.clientY - startY;
            if (Math.abs(nx - panX) + Math.abs(ny - panY) > 3) moved = true;
            panX = nx; panY = ny; apply();
        });
        stage.addEventListener('pointerup', function () { dragging = false; });
        stage.addEventListener('pointercancel', function () { dragging = false; });
        apply();
    }
    var inspectionPdfRenderVersion = 0;
    var inspectionPdfRenderTask = null;
    var inspectionPdfRenderTimer = null;
    var inspectionPdfPage = null;
    var inspectionPdfFitScale = 1;
    var inspectionCoordinateZoom = 1;

    function renderInspectionPdfCanvasAtZoom() {
        var media = document.getElementById('inspectionPdfCanvas');
        if (!media || media.tagName !== 'CANVAS' || !inspectionPdfPage) return;
        var renderVersion = ++inspectionPdfRenderVersion;
        var previousTask = inspectionPdfRenderTask;
        inspectionPdfRenderTask = null;
        var waitForPrevious = Promise.resolve();
        if (previousTask && previousTask.cancel) {
            try { previousTask.cancel(); } catch (ignore) { }
            waitForPrevious = previousTask.promise.catch(function () { });
        }
        waitForPrevious.then(function () {
            if (renderVersion !== inspectionPdfRenderVersion) return;
            var ratio = Math.min(window.devicePixelRatio || 1, 2);
            var viewport = inspectionPdfPage.getViewport({
                scale: inspectionPdfFitScale * inspectionCoordinateZoom * ratio
            });
            media.width = Math.max(1, Math.floor(viewport.width));
            media.height = Math.max(1, Math.floor(viewport.height));
            media.style.width = '100%';
            media.style.height = '100%';
            var context = media.getContext('2d');
            inspectionPdfRenderTask = inspectionPdfPage.render({ canvasContext: context, viewport: viewport });
            return inspectionPdfRenderTask.promise;
        }).then(function () {
            if (renderVersion !== inspectionPdfRenderVersion) return;
            inspectionPdfRenderTask = null;
            var status = document.getElementById('inspectionPdfStatus');
            if (status) status.style.display = 'none';
        }).catch(function (error) {
            if (renderVersion !== inspectionPdfRenderVersion || (error && error.name === 'RenderingCancelledException')) return;
            inspectionPdfRenderTask = null;
            var status = document.getElementById('inspectionPdfStatus');
            if (status) { status.style.display = 'flex'; status.textContent = 'Gagal memuat denah: ' + (error && error.message ? error.message : error); }
            if (window.console && console.error) console.error('Inspection map render error:', error);
        });
    }
    function scheduleInspectionPdfRender() {
        if (!inspectionPdfPage) return;
        if (inspectionPdfRenderTimer) clearTimeout(inspectionPdfRenderTimer);
        inspectionPdfRenderTimer = setTimeout(function () {
            inspectionPdfRenderTimer = null;
            renderInspectionPdfCanvasAtZoom();
        }, 140);
    }
    function renderInspectionPdf() {
        var media = document.getElementById('inspectionPdfCanvas');
        if (!media) return;
        var url = media.getAttribute('data-map-url') || media.getAttribute('data-pdf-url');
        if (!url) return;
        var board = document.getElementById('inspectionCoordinateBoard');
        var content = document.getElementById('inspectionCoordinateContent');
        var status = document.getElementById('inspectionPdfStatus');
        if (media.tagName === 'IMG') {
            inspectionPdfPage = null;
            media.onload = function () { if (board) board.style.aspectRatio = media.naturalWidth + ' / ' + media.naturalHeight; if (status) status.style.display = 'none'; };
            media.onerror = function () { if (status) { status.style.display = 'flex'; status.textContent = 'Gagal memuat gambar denah JPG/JPEG.'; } };
            media.src = url;
            if (media.complete && media.naturalWidth) { if (board) board.style.aspectRatio = media.naturalWidth + ' / ' + media.naturalHeight; if (status) status.style.display = 'none'; }
            return;
        }
        if (!window.pdfjsLib) { if (status) status.textContent = 'PDF.js tidak berhasil dimuat. Periksa file JSCus/pdf.min.js.'; return; }
        window.pdfjsLib.GlobalWorkerOptions.workerSrc = '../JSCus/pdf.worker.min.js';
        window.pdfjsLib.getDocument({ url: url }).promise.then(function (pdf) { return pdf.getPage(1); }).then(function (page) {
            var base = page.getViewport({ scale: 1 });
            var width = board.clientWidth;
            if (!width) throw new Error('Area denah belum terlihat.');
            inspectionPdfFitScale = width / base.width;
            inspectionPdfPage = page;
            inspectionCoordinateZoom = 1;
            board.style.aspectRatio = base.width + ' / ' + base.height;
            content.style.width = '100%';
            content.style.height = '100%';
            renderInspectionPdfCanvasAtZoom();
        }).catch(function (error) {
            if (status) { status.style.display = 'flex'; status.textContent = 'Gagal memuat denah: ' + (error && error.message ? error.message : error); }
            if (window.console && console.error) console.error('Inspection map render error:', error);
        });
    }
    document.addEventListener('DOMContentLoaded', function () {
        var draftInput = document.getElementById('fuMapPdf');
        if (draftInput) {
            draftInput.addEventListener('change', function () {
                var file = draftInput.files && draftInput.files[0];
                var key = inspectionDraftKey();
                if (!file || !key) return;
                if (!draftInput.getAttribute('data-inspection-original-name') && draftInput.name)
                    draftInput.setAttribute('data-inspection-original-name', draftInput.name);
                inspectionDraftWritePromise = inspectionDraftWritePromise.then(function () {
                    return inspectionDraftStore('readwrite', key, {
                        blob: file, fileName: file.name, fileType: file.type,
                        lastModified: file.lastModified
                    });
                }).then(function () { inspectionShowDraftPreview(file, file.name); });
            });
            inspectionDraftRestorePromise = inspectionRestoreDraft();
        }
        document.addEventListener('click', function (event) {
            var control = event.target && event.target.closest
                ? event.target.closest('a,button,input[type="submit"]') : null;
            if (!control || control.id === 'fuMapPdf' || control.getAttribute('data-inspection-click-ready') === '1') return;
            var href = control.getAttribute('href') || '';
            var clickCode = control.getAttribute('onclick') || '';
            var isPostback = /__doPostBack|WebForm_DoPostBackWithOptions/.test(href + ' ' + clickCode) ||
                control.type === 'submit' || control.getAttribute('type') === 'submit';
            if (!isPostback) return;
            event.preventDefault();
            event.stopImmediatePropagation();
            Promise.all([inspectionDraftWritePromise, inspectionDraftRestorePromise]).then(function () {
                inspectionSetUploadPostbackMode(control);
                control.setAttribute('data-inspection-click-ready', '1');
                control.click();
                control.removeAttribute('data-inspection-click-ready');
            }).catch(function (error) {
                console.error('Cannot prepare inspection map draft before postback:', error);
                alert('Gagal menyiapkan draft denah di browser. Silakan coba lagi.');
            });
        }, true);
        if (document.forms && document.forms.length) {
            document.forms[0].addEventListener('submit', function (event) {
                if (document.forms[0].getAttribute('data-inspection-draft-ready') === '1') return;
                event.preventDefault();
                Promise.all([inspectionDraftWritePromise, inspectionDraftRestorePromise]).then(function () {
                    document.forms[0].setAttribute('data-inspection-draft-ready', '1');
                    if (document.forms[0].requestSubmit) document.forms[0].requestSubmit(event.submitter || undefined);
                    else document.forms[0].submit();
                });
            }, true);
        }
        restoreTab();
        if (window.bootstrap && window.bootstrap.Tooltip) {
            document.querySelectorAll('[data-bs-toggle="tooltip"]').forEach(function (element) {
                window.bootstrap.Tooltip.getOrCreateInstance(element);
            });
        }
        window.requestAnimationFrame(renderMapPreviewPdf);
        window.requestAnimationFrame(renderInspectionPdf);
        initMapPreviewInteraction();
        var pointModal = document.getElementById('pnlPointEditor');
        if (pointModal) pointModal.addEventListener('shown.bs.modal', function () { window.requestAnimationFrame(renderInspectionPdf); });
        var board = document.getElementById('inspectionCoordinateBoard');
        var content = document.getElementById('inspectionCoordinateContent');
        var markerX = document.getElementById('txtMarkerX');
        var markerY = document.getElementById('txtMarkerY');
        var swapTarget = document.getElementById('hidSwapPointID');
        var swapLabel = document.getElementById('lblSwapTarget');
        var clearCoordinateButton = document.getElementById('btnClearCoordinate');
        if (clearCoordinateButton) {
            clearCoordinateButton.addEventListener('click', function (event) {
                event.preventDefault();
                event.stopPropagation();
                var xField = document.getElementById('txtMarkerX');
                var yField = document.getElementById('txtMarkerY');
                if (xField) xField.value = '';
                if (yField) yField.value = '';
                var shapeAttributesField = document.getElementById('hidShapeAttributes');
                if (shapeAttributesField) shapeAttributesField.value = '{}';
                var preview = document.getElementById('inspectionCoordinatePreview');
                if (preview && preview.parentNode) preview.parentNode.removeChild(preview);
                var swapTargetField = document.getElementById('hidSwapPointID');
                var swapTargetLabel = document.getElementById('lblSwapTarget');
                if (swapTargetField) swapTargetField.value = '';
                if (swapTargetLabel) swapTargetLabel.textContent = 'Koordinat dikosongkan.';
            });
        }
        if (board && content && markerX && markerY) {
            var zoom = 1, panX = 0, panY = 0, dragging = false, moved = false, startX = 0, startY = 0;
            var zoomLabel = document.getElementById('lblMapZoom');
            function updateMarkerScale() {
                // Markers are children of the zoomed content, so compensate for
                // the content scale. Include dynamically-created preview markers.
                var markers = content.querySelectorAll('.inspection-coordinate-marker, .inspection-coordinate-preview');
                var inverseScale = 1 / zoom;
                for (var i = 0; i < markers.length; i++) {
                    markers[i].style.transform = 'translate(-50%, -50%) scale(' + inverseScale + ')';
                }
            }
            function applyView() {
                content.style.transform = 'translate(' + panX + 'px,' + panY + 'px) scale(' + zoom + ')';
                var vectorSvg = content.querySelector('#inspectionCoordinateSvgOverlay');
                if (vectorSvg && content.clientWidth && content.clientHeight) {
                    var vectorAspect = content.clientWidth / content.clientHeight;
                    vectorSvg.querySelectorAll('.inspection-coordinate-circle').forEach(function (circle) {
                        var cx = Number(circle.getAttribute('cx')) || 0;
                        var cy = Number(circle.getAttribute('cy')) || 0;
                        circle.setAttribute('transform', 'translate(' + cx + ' ' + cy + ') scale(1 ' + vectorAspect + ') translate(' + (-cx) + ' ' + (-cy) + ')');
                    });
                }
                updateMarkerScale();
                if (zoomLabel) zoomLabel.textContent = Math.round(zoom * 100) + '%';
                board.classList.toggle('inspection-map-zoomed', zoom > 1);
            }
            function setZoom(next, centerX, centerY) {
                next = Math.max(1, Math.min(5, next));
                if (next === zoom) return;
                var rect = board.getBoundingClientRect();
                var cx = centerX == null ? rect.width / 2 : centerX;
                var cy = centerY == null ? rect.height / 2 : centerY;
                var ratio = next / zoom;
                panX = cx - (cx - panX) * ratio;
                panY = cy - (cy - panY) * ratio;
                zoom = next;
                inspectionCoordinateZoom = zoom;
                if (zoom === 1) { panX = 0; panY = 0; }
                applyView();
                scheduleInspectionPdfRender();
            }
            var shapeSelect = document.getElementById('ddlPointShapeType');
            var pathField = document.getElementById('hidSvgPathData');
            var shapeAttributesField = document.getElementById('hidShapeAttributes');
            function updateCircleShapeAttributes(x, y) {
                if (!shapeAttributesField) return;
                var radius = 2.0;
                try {
                    var saved = JSON.parse(shapeAttributesField.value || '{}');
                    if (saved && isFinite(Number(saved.r)) && Number(saved.r) > 0) radius = Number(saved.r);
                } catch (_) { }
                radius = Math.max(0.2, Math.min(8, radius));
                shapeAttributesField.value = JSON.stringify({ cx: Number(x.toFixed(2)), cy: Number(y.toFixed(2)), r: radius });
            }
            var drawButton = document.getElementById('btnStartPathDraw');
            var undoButton = document.getElementById('btnUndoPath');
            var clearPathButton = document.getElementById('btnClearPath');
            var pathStatus = document.getElementById('lblPathDrawStatus');
            var drawMode = false, drawingPath = false, suppressNextClick = false;
            var pathPoints = [], pathPreview = null;
            function pathStatusText(text) { if (pathStatus) pathStatus.textContent = text; }
            function mapPointFromEvent(event) {
                // Measure the actual image content, not the outer 16:10 board.
                // This keeps coordinates aligned when the floor plan has a different aspect ratio.
                var rect = content.getBoundingClientRect();
                if (!rect.width || !rect.height) return { x: 0, y: 0 };
                return {
                    x: Math.max(0, Math.min(100, ((event.clientX - rect.left) / rect.width) * 100)),
                    y: Math.max(0, Math.min(100, ((event.clientY - rect.top) / rect.height) * 100))
                };
            }
            function ensurePathPreview() {
                var svg = content.querySelector('#inspectionCoordinateSvgOverlay');
                if (!svg) {
                    svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
                    svg.id = 'inspectionCoordinateSvgOverlay';
                    svg.setAttribute('class', 'inspection-coordinate-svg-overlay');
                    svg.setAttribute('viewBox', '0 0 100 100');
                    svg.setAttribute('preserveAspectRatio', 'none');
                    content.appendChild(svg);
                }
                if (!pathPreview) {
                    pathPreview = document.createElementNS('http://www.w3.org/2000/svg', 'path');
                    pathPreview.id = 'inspectionCoordinatePathPreview';
                    pathPreview.setAttribute('fill', 'rgba(13,110,253,.16)');
                    pathPreview.setAttribute('stroke', '#0d6efd');
                    pathPreview.setAttribute('stroke-width', '0.8');
                    pathPreview.setAttribute('stroke-linejoin', 'round');
                    pathPreview.setAttribute('vector-effect', 'non-scaling-stroke');
                    svg.appendChild(pathPreview);
                }
                return pathPreview;
            }
            function renderPathPreview(closePath) {
                var path = ensurePathPreview();
                if (!pathPoints.length) { path.setAttribute('d', ''); return; }
                var d = 'M ' + pathPoints[0].x.toFixed(2) + ' ' + pathPoints[0].y.toFixed(2);
                for (var p = 1; p < pathPoints.length; p++)
                    d += ' L ' + pathPoints[p].x.toFixed(2) + ' ' + pathPoints[p].y.toFixed(2);
                if (closePath && pathPoints.length >= 3) d += ' Z';
                path.setAttribute('d', d);
            }
            function startPathDrawing() {
                if (shapeSelect) shapeSelect.value = 'PATH';
                drawMode = true; drawingPath = false; pathPoints = [];
                if (pathField) pathField.value = '';
                var activeId = document.getElementById('hidPointID');
                var svg = content.querySelector('#inspectionCoordinateSvgOverlay');
                if (svg && activeId && activeId.value) {
                    var oldPath = svg.querySelector('.inspection-coordinate-path[data-point-id="' + activeId.value + '"]');
                    if (oldPath) oldPath.style.display = 'none';
                }
                renderPathPreview(false);
                board.classList.add('path-drawing');
                pathStatusText('Draw mode aktif: drag mengikuti batas area, lalu lepaskan untuk menutup path.');
            }
            function finishPathDrawing() {
                drawingPath = false; dragging = false;
                if (pathPoints.length < 3) {
                    pathPoints = []; renderPathPreview(false);
                    pathStatusText('Path perlu minimal 3 titik. Klik Draw SVG Path untuk mencoba lagi.');
                    return;
                }
                renderPathPreview(true);
                var d = 'M ' + pathPoints[0].x.toFixed(2) + ' ' + pathPoints[0].y.toFixed(2);
                for (var p = 1; p < pathPoints.length; p++)
                    d += ' L ' + pathPoints[p].x.toFixed(2) + ' ' + pathPoints[p].y.toFixed(2);
                d += ' Z';
                if (pathField) pathField.value = d;
                var sx = 0, sy = 0;
                pathPoints.forEach(function (point) { sx += point.x; sy += point.y; });
                if (markerX) markerX.value = (sx / pathPoints.length).toFixed(2);
                if (markerY) markerY.value = (sy / pathPoints.length).toFixed(2);
                drawMode = false;
                board.classList.remove('path-drawing');
                pathStatusText('SVG Path siap disimpan. Save Inspection Point untuk menyimpan area ini.');
            }
            if (drawButton) drawButton.addEventListener('click', startPathDrawing);
            if (undoButton) undoButton.addEventListener('click', function () {
                if (pathPoints.length) {
                    pathPoints.pop();
                    if (!drawingPath && pathPoints.length >= 3) {
                        renderPathPreview(true);
                        var d = 'M ' + pathPoints[0].x.toFixed(2) + ' ' + pathPoints[0].y.toFixed(2);
                        for (var p = 1; p < pathPoints.length; p++)
                            d += ' L ' + pathPoints[p].x.toFixed(2) + ' ' + pathPoints[p].y.toFixed(2);
                        d += ' Z';
                        if (pathField) pathField.value = d;
                        var sx = 0, sy = 0;
                        pathPoints.forEach(function (point) { sx += point.x; sy += point.y; });
                        if (markerX) markerX.value = (sx / pathPoints.length).toFixed(2);
                        if (markerY) markerY.value = (sy / pathPoints.length).toFixed(2);
                    } else {
                        renderPathPreview(false);
                        if (pathField) pathField.value = '';
                        if (!drawingPath && shapeSelect) shapeSelect.value = 'CIRCLE';
                    }
                    pathStatusText('Titik terakhir dibatalkan.');
                } else {
                    drawMode = false; drawingPath = false;
                    board.classList.remove('path-drawing');
                    if (pathField) pathField.value = '';
                    if (shapeSelect) shapeSelect.value = 'CIRCLE';
                    if (pathPreview) pathPreview.setAttribute('d', '');
                    var activeId = document.getElementById('hidPointID');
                    var svg = content.querySelector('#inspectionCoordinateSvgOverlay');
                    if (svg && activeId && activeId.value) {
                        var oldPath = svg.querySelector('.inspection-coordinate-path[data-point-id="' + activeId.value + '"]');
                        if (oldPath) oldPath.style.display = 'none';
                    }
                    pathStatusText('Path dikosongkan.');
                }
            });
            if (clearPathButton) clearPathButton.addEventListener('click', function () {
                drawMode = false; drawingPath = false; pathPoints = [];
                if (pathField) pathField.value = '';
                if (shapeSelect) shapeSelect.value = 'CIRCLE';
                var shapeAttributesField = document.getElementById('hidShapeAttributes');
                if (shapeAttributesField) shapeAttributesField.value = '{}';
                var activeId = document.getElementById('hidPointID');
                var svg = content.querySelector('#inspectionCoordinateSvgOverlay');
                if (svg && activeId && activeId.value) {
                    var oldPath = svg.querySelector('.inspection-coordinate-path[data-point-id="' + activeId.value + '"]');
                    if (oldPath) oldPath.style.display = 'none';
                }
                board.classList.remove('path-drawing');
                if (pathPreview) pathPreview.setAttribute('d', '');
                pathStatusText('Path dihapus. Circle marker dapat ditempatkan dengan klik map.');
            });
            if (shapeSelect) shapeSelect.addEventListener('change', function () {
                if (this.value === 'CIRCLE') {
                    drawMode = false; drawingPath = false; board.classList.remove('path-drawing');
                    if (pathField) pathField.value = '';
                    if (pathPreview) pathPreview.setAttribute('d', '');
                    var activeId = document.getElementById('hidPointID');
                    var svg = content.querySelector('#inspectionCoordinateSvgOverlay');
                    if (svg && activeId && activeId.value) {
                        var oldPath = svg.querySelector('.inspection-coordinate-path[data-point-id="' + activeId.value + '"]');
                        if (oldPath) oldPath.style.display = 'none';
                    }
                    pathStatusText('Circle: klik map untuk menentukan satu koordinat.');
                } else {
                    pathStatusText('Klik Draw SVG Path, lalu drag mengikuti batas area pada denah.');
                }
            });
            board.addEventListener('pointerdown', function (event) {
                if (!drawMode || event.button !== 0) return;
                event.preventDefault(); event.stopImmediatePropagation();
                drawingPath = true; suppressNextClick = true;
                pathPoints = [mapPointFromEvent(event)];
                renderPathPreview(false);
                try { board.setPointerCapture(event.pointerId); } catch (_) { }
            }, true);
            board.addEventListener('pointermove', function (event) {
                if (!drawMode || !drawingPath) return;
                event.preventDefault(); event.stopImmediatePropagation();
                var next = mapPointFromEvent(event), last = pathPoints[pathPoints.length - 1];
                var dx = next.x - last.x, dy = next.y - last.y;
                if (Math.sqrt(dx * dx + dy * dy) >= 0.25) {
                    pathPoints.push(next); renderPathPreview(false);
                }
            }, true);
            board.addEventListener('pointerup', function (event) {
                if (!drawMode || !drawingPath) return;
                event.preventDefault(); event.stopImmediatePropagation();
                finishPathDrawing();
            }, true);
            board.addEventListener('pointercancel', function (event) {
                if (!drawMode || !drawingPath) return;
                event.preventDefault(); event.stopImmediatePropagation();
                drawingPath = false; pathPoints = []; suppressNextClick = false; renderPathPreview(false);
            }, true);

            document.getElementById('btnMapZoomIn').addEventListener('click', function () { setZoom(zoom + 0.25); });
            document.getElementById('btnMapZoomOut').addEventListener('click', function () { setZoom(zoom - 0.25); });
            document.getElementById('btnMapZoomFit').addEventListener('click', function () { zoom = 1; inspectionCoordinateZoom = 1; panX = 0; panY = 0; applyView(); scheduleInspectionPdfRender(); });
            board.addEventListener('wheel', function (event) {
                if (!event.ctrlKey && !event.shiftKey) return;
                event.preventDefault();
                var rect = board.getBoundingClientRect();
                setZoom(zoom + (event.deltaY < 0 ? 0.25 : -0.25), event.clientX - rect.left, event.clientY - rect.top);
            }, { passive: false });
            board.addEventListener('pointerdown', function (event) {
                if ((event.target.closest && event.target.closest('.inspection-coordinate-marker, .inspection-coordinate-circle, .inspection-coordinate-path')) || zoom <= 1 || event.button !== 0) return;
                dragging = true; moved = false; startX = event.clientX - panX; startY = event.clientY - panY;
                board.setPointerCapture(event.pointerId);
            });
            board.addEventListener('pointermove', function (event) {
                if (!dragging) return;
                var nx = event.clientX - startX, ny = event.clientY - startY;
                if (Math.abs(nx - panX) + Math.abs(ny - panY) > 3) moved = true;
                panX = nx; panY = ny; applyView();
            });
            board.addEventListener('pointerup', function () { dragging = false; });
            board.addEventListener('pointercancel', function () { dragging = false; });
            content.addEventListener('click', function (event) {
                var marker = event.target.closest ? event.target.closest('.inspection-coordinate-marker, .inspection-coordinate-circle, .inspection-coordinate-path') : null;
                if (marker) {
                    event.preventDefault(); event.stopPropagation();
                    var activeId = document.getElementById('hidPointID');
                    if (activeId && marker.getAttribute('data-point-id') !== activeId.value) {
                        if (marker.getAttribute('data-can-swap') === '1') {
                            if (swapTarget) swapTarget.value = marker.getAttribute('data-point-id');
                            if (swapLabel) swapLabel.textContent = 'Swap target: ' + marker.getAttribute('title');
                        } else {
                            if (swapTarget) swapTarget.value = '';
                            if (swapLabel) swapLabel.textContent = 'Point lain berada di Profit Center berbeda; swap tidak tersedia.';
                        }
                    }
                }
            });
            board.addEventListener('click', function (event) {
                if (suppressNextClick) { suppressNextClick = false; event.preventDefault(); return; }
                if (drawMode) { event.preventDefault(); return; }
                if (moved) { moved = false; return; }
                // Coordinate against the actual map image content so its original
                // aspect ratio and any letterboxing never distort saved point positions.
                var rect = content.getBoundingClientRect();
                if (!rect.width || !rect.height) return;
                var x = Math.max(0, Math.min(100, ((event.clientX - rect.left) / rect.width) * 100));
                var y = Math.max(0, Math.min(100, ((event.clientY - rect.top) / rect.height) * 100));
                markerX.value = x.toFixed(2); markerY.value = y.toFixed(2);
                if (!shapeSelect || shapeSelect.value === 'CIRCLE') updateCircleShapeAttributes(x, y);
                if (swapTarget) swapTarget.value = '';
                if (swapLabel) swapLabel.textContent = 'Posisi baru dipilih.';
                var preview = document.getElementById('inspectionCoordinatePreview');
                if (!preview) {
                    preview = document.createElement('span');
                    preview.id = 'inspectionCoordinatePreview';
                    preview.className = 'inspection-coordinate-preview';
                    preview.textContent = '+';
                    content.appendChild(preview);
                }
                preview.style.left = x + '%'; preview.style.top = y + '%';
                // A preview may be created after the last zoom event. Apply the
                // current inverse scale immediately so its visible size stays fixed.
                updateMarkerScale();
            });
            applyView();
        }
        document.querySelectorAll('#inspectionMasterTabs [data-bs-toggle="tab"]').forEach(function (tab) {
            tab.addEventListener('shown.bs.tab', function (event) {
                var hidden = document.getElementById('hidActiveTab');
                if (hidden) hidden.value = event.target.getAttribute('data-bs-target');
            });
        });
    });
    window.inspectionMasterSetTab = function (selector) {
        var hidden = document.getElementById('hidActiveTab');
        if (hidden) hidden.value = selector;
    };
})();
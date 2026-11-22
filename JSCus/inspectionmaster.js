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
        // A new/draft Map must keep the FileUpload participating in every
        // postback until its first Save Point persists the floor plan. Otherwise
        // WebForms can rebuild the input between Add Point and Save Point and
        // the browser draft is no longer part of the multipart request.
        // Existing saved Maps keep the file local until the toolbar Save creates
        // a new version.
        if ((isNewOrDraftMap || isSaveMap) && originalName) input.name = originalName;
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
    function inspectionShowDraftMapPreview(blob, fileName) {
        var panel = document.getElementById('pnlMapPreview');
        if (!panel) return;
        panel.style.display = 'block';

        var title = document.getElementById('lblMapPreviewTitle');
        if (title) title.textContent = 'Denah Draft - ' + (fileName || 'Floor Plan');

        var link = document.getElementById('lnkMapPdf');
        if (link) {
            link.style.display = 'inline-block';
            if (inspectionDraftObjectUrl) link.href = inspectionDraftObjectUrl;
            link.textContent = 'Open Floor Plan';
        }

        var literalHost = panel.querySelector('.inspection-map-preview-draft-host');
        if (!literalHost) {
            literalHost = document.createElement('div');
            literalHost.className = 'inspection-map-preview-draft-host';
            var body = panel.querySelector('.p-2');
            if (body) body.innerHTML = '';
            if (body) body.appendChild(literalHost);
            else panel.appendChild(literalHost);
        }

        literalHost.innerHTML =
            '<div class="inspection-map-preview-toolbar d-flex align-items-center gap-1 mb-2">' +
            '<button type="button" class="btn btn-sm btn-outline-secondary" id="btnMapPreviewZoomOut" title="Zoom out"><i class="bi bi-zoom-out"></i></button>' +
            '<button type="button" class="btn btn-sm btn-outline-secondary" id="btnMapPreviewZoomIn" title="Zoom in"><i class="bi bi-zoom-in"></i></button>' +
            '<button type="button" class="btn btn-sm btn-outline-secondary" id="btnMapPreviewZoomFit">Fit</button>' +
            '<span class="small text-muted ms-1" id="lblMapPreviewZoom">100%</span>' +
            '<span class="small text-muted ms-auto">Denah draft belum tersimpan</span>' +
            '</div>' +
            '<div class="inspection-map-preview-stage" id="inspectionMapPreviewStage">' +
            '<div class="inspection-map-preview-media" id="inspectionMapPreviewMedia">' +
            '<div class="inspection-map-preview-draft-status inspection-pdf-status">Memuat denah draft...</div>' +
            '</div></div>';

        var media = document.getElementById('inspectionMapPreviewMedia');
        var extension = (fileName || '').toLowerCase().split('.').pop();
        if (!media) return;

        if (extension === 'jpg' || extension === 'jpeg' || extension === 'png' ||
            (blob.type || '').toLowerCase().indexOf('image/') === 0) {
            var img = document.createElement('img');
            img.className = 'inspection-image-preview';
            img.alt = 'Inspection floor plan draft';
            img.onload = function () {
                var status = media.querySelector('.inspection-map-preview-draft-status');
                if (status) status.remove();
            };
            img.onerror = function () {
                var status = media.querySelector('.inspection-map-preview-draft-status');
                if (status) status.textContent = 'Gagal memuat gambar denah draft.';
            };
            media.innerHTML = '';
            media.appendChild(img);
            img.src = inspectionDraftObjectUrl;
        } else {
            var canvas = document.createElement('canvas');
            canvas.id = 'inspectionMapPreviewCanvas';
            canvas.className = 'inspection-map-preview-canvas';
            canvas.setAttribute('data-map-url', inspectionDraftObjectUrl);
            media.innerHTML = '';
            media.appendChild(canvas);
            var status = document.createElement('div');
            status.id = 'inspectionMapPreviewStatus';
            status.className = 'inspection-pdf-status';
            status.textContent = 'Memuat denah draft...';
            media.appendChild(status);
            window.requestAnimationFrame(renderMapPreviewPdf);
        }

        // Reuse the existing map-preview interaction wiring for the
        // dynamically-created draft preview (zoom/pan/fit).
        initMapPreviewInteraction();
    }

    function inspectionShowDraftPreview(blob, fileName) {
        // The shared object URL belongs to the selected draft file, not to the
        // Point Editor. The lower Map Preview must work while Point Editor is
        // still hidden and its coordinate board is not rendered in the DOM.
        if (inspectionDraftObjectUrl) URL.revokeObjectURL(inspectionDraftObjectUrl);
        inspectionDraftObjectUrl = URL.createObjectURL(blob);

        var board = document.getElementById('inspectionCoordinateBoard');
        var content = document.getElementById('inspectionCoordinateContent');
        if (!board || !content) return;

        var extension = (fileName || '').toLowerCase().split('.').pop();
        var old = document.getElementById('inspectionPdfCanvas');
        if (extension === 'jpg' || extension === 'jpeg' || extension === 'png' || (blob.type || '').toLowerCase().indexOf('image/') === 0) {
            var img = old && old.tagName === 'IMG' ? old : document.createElement('img');
            img.id = 'inspectionPdfCanvas';
            img.className = 'inspection-coordinate-pdf';
            img.alt = 'Inspection floor plan';
            img.setAttribute('data-map-url', inspectionDraftObjectUrl);
            img.onload = function () {
                // Draft images use the same aspect-ratio-aware content sizing as
                // saved maps. Do not stretch them to the fixed-height point modal.
                fitInspectionCoordinateContent(board, content, img.naturalWidth, img.naturalHeight);
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
            // Keep the name for a new/draft Map so the next Add Point /
            // Save Point postback can carry the same multipart file.
            var mapIsDraft = document.getElementById('hidMapIsDraft');
            var originalName = input.getAttribute('data-inspection-original-name');
            if (!(mapIsDraft && mapIsDraft.value === '1') && originalName)
                input.removeAttribute('name');
            else if (originalName)
                input.name = originalName;
            inspectionShowDraftPreview(draft.blob, draft.fileName);
            inspectionShowDraftMapPreview(draft.blob, draft.fileName);
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
            var mapPreviewPanel = document.getElementById('pnlMapPreview');
            if (mapPreviewPanel) mapPreviewPanel.style.display = 'none';
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
    function updateMapPreviewCircleAspect(media) {
        if (!media || !media.clientWidth || !media.clientHeight) return;
        var svg = media.querySelector('.inspection-map-preview-svg');
        if (!svg) return;
        var aspect = media.clientWidth / media.clientHeight;
        svg.querySelectorAll('.inspection-map-preview-circle').forEach(function (circle) {
            var cx = Number(circle.getAttribute('cx')) || 0;
            var cy = Number(circle.getAttribute('cy')) || 0;
            circle.setAttribute('transform', 'translate(' + cx + ' ' + cy + ') scale(1 ' + aspect + ') translate(' + (-cx) + ' ' + (-cy) + ')');
        });
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
            updateMapPreviewCircleAspect(media);
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
        var image = media.querySelector('.inspection-image-preview');
        if (image) {
            var sizeImage = function () {
                if (!image.naturalWidth || !image.naturalHeight) return;
                var scale = Math.min(stage.clientWidth / image.naturalWidth, stage.clientHeight / image.naturalHeight);
                var width = Math.max(1, Math.round(image.naturalWidth * scale));
                var height = Math.max(1, Math.round(image.naturalHeight * scale));
                media.style.width = width + 'px';
                media.style.height = height + 'px';
                updateMapPreviewCircleAspect(media);
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
            media.style.left = '50%';
            media.style.top = '50%';
            media.style.transformOrigin = 'center center';
            media.style.transform = 'translate(-50%,-50%) translate(' + panX + 'px,' + panY + 'px) scale(' + zoom + ')';
            updateMapPreviewCircleAspect(media);
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
            var centerX = rect.width / 2, centerY = rect.height / 2;
            var offsetX = x - centerX, offsetY = y - centerY;
            panX = offsetX - (offsetX - panX) * ratio;
            panY = offsetY - (offsetY - panY) * ratio;
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
    function fitInspectionCoordinateContent(board, content, naturalWidth, naturalHeight) {
        if (!board || !content || !naturalWidth || !naturalHeight) return null;
        var availableWidth = board.clientWidth;
        var availableHeight = board.clientHeight;
        if (!availableWidth || !availableHeight) return null;

        // Fit the complete floor plan inside the drawing viewport without changing
        // its native aspect ratio. Coordinates/markers use this exact content box,
        // not the larger modal viewport (which may contain letterbox space).
        var scale = Math.min(availableWidth / naturalWidth, availableHeight / naturalHeight);
        var width = Math.max(1, Math.round(naturalWidth * scale));
        var height = Math.max(1, Math.round(naturalHeight * scale));
        content.style.left = Math.round((availableWidth - width) / 2) + 'px';
        content.style.top = Math.round((availableHeight - height) / 2) + 'px';
        content.style.width = width + 'px';
        content.style.height = height + 'px';
        return { width: width, height: height };
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
            var fitImage = function () {
                if (!media.naturalWidth || !media.naturalHeight) return;
                fitInspectionCoordinateContent(board, content, media.naturalWidth, media.naturalHeight);
                if (status) status.style.display = 'none';
            };
            media.onload = fitImage;
            media.onerror = function () { if (status) { status.style.display = 'flex'; status.textContent = 'Gagal memuat gambar denah JPG/JPEG/PNG.'; } };
            media.src = url;
            if (media.complete && media.naturalWidth) fitImage();
            return;
        }
        if (!window.pdfjsLib) { if (status) status.textContent = 'PDF.js tidak berhasil dimuat. Periksa file JSCus/pdf.min.js.'; return; }
        window.pdfjsLib.GlobalWorkerOptions.workerSrc = '../JSCus/pdf.worker.min.js';
        window.pdfjsLib.getDocument({ url: url }).promise.then(function (pdf) { return pdf.getPage(1); }).then(function (page) {
            var base = page.getViewport({ scale: 1 });
            var fitted = fitInspectionCoordinateContent(board, content, base.width, base.height);
            if (!fitted) throw new Error('Area denah belum terlihat.');
            inspectionPdfFitScale = fitted.width / base.width;
            inspectionPdfPage = page;
            inspectionCoordinateZoom = 1;
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
                if (!file) return;

                // Render the selected file immediately. The visual preview must
                // not depend on IndexedDB completing first; IndexedDB is only
                // the persistence layer used to restore the draft after a
                // WebForms postback.
                inspectionShowDraftPreview(file, file.name);
                inspectionShowDraftMapPreview(file, file.name);

                if (!key) return;
                if (!draftInput.getAttribute('data-inspection-original-name') && draftInput.name)
                    draftInput.setAttribute('data-inspection-original-name', draftInput.name);
                inspectionDraftWritePromise = inspectionDraftWritePromise.then(function () {
                    return inspectionDraftStore('readwrite', key, {
                        blob: file, fileName: file.name, fileType: file.type,
                        lastModified: file.lastModified
                    });
                }).catch(function (error) {
                    console.error('Inspection map draft save failed:', error);
                });
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
                var shapeAttributesField = document.getElementById('hidShapeAttributes');
                var pathFieldForClear = document.getElementById('hidSvgPathData');
                var shapeSelectForClear = document.getElementById('ddlPointShapeType');
                var hasSavedPolyline = shapeSelectForClear &&
                    (shapeSelectForClear.value === 'PATH' || shapeSelectForClear.value === 'ORTHOGONAL') &&
                    pathFieldForClear && pathFieldForClear.value;
                // A finished open path still needs its centroid as the required
                // anchor. Clear Coordinate may remove a loose marker preview, but
                // must not erase that anchor or the path metadata.
                if (!hasSavedPolyline) {
                    if (xField) xField.value = '';
                    if (yField) yField.value = '';
                    if (shapeAttributesField) shapeAttributesField.value = '{}';
                }
                var preview = document.getElementById('inspectionCoordinatePreview');
                if (preview && preview.parentNode) preview.parentNode.removeChild(preview);
                var swapTargetField = document.getElementById('hidSwapPointID');
                var swapTargetLabel = document.getElementById('lblSwapTarget');
                if (swapTargetField) swapTargetField.value = '';
                if (swapTargetLabel) swapTargetLabel.textContent = hasSavedPolyline
                    ? 'Anchor polyline dipertahankan.'
                    : 'Koordinat dikosongkan.';
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
                // Match the inspection.aspx map workspace: zoom is anchored to the
                // viewport center/top coordinate system, while the fitted floor plan
                // itself remains centered inside the board.
                content.style.transformOrigin = 'center top';
                content.style.transform = 'translate3d(' + panX + 'px,' + panY + 'px,0) scale(' + zoom + ')';
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

                // Same zoom math used by inspection.aspx: the zoom anchor is measured
                // from the board center horizontally and from its top vertically.
                var rect = board.getBoundingClientRect();
                var x = centerX == null ? rect.width / 2 : centerX;
                var y = centerY == null ? rect.height / 2 : centerY;
                var localX = x - rect.width / 2;
                var localY = y;
                var ratio = next / zoom;

                panX = (panX - localX) * ratio + localX;
                panY = (panY - localY) * ratio + localY;

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
                // CIRCLE is a small point dot; area geometry belongs to PATH.
                var radius = 3.0;
                shapeAttributesField.value = JSON.stringify({ cx: Number(x.toFixed(2)), cy: Number(y.toFixed(2)), r: radius });
            }
            // Action-based Undo/Redo for unsaved map geometry edits.
            var redoButton = document.getElementById('btnRedoPath');
            var pathUndoStack = [], pathRedoStack = [];
            function capturePathEditorState() {
                var svg = content.querySelector('#inspectionCoordinateSvgOverlay');
                var preview = document.getElementById('inspectionCoordinatePreview');
                return {
                    points: pathPoints.map(function (p) { return { x: p.x, y: p.y }; }),
                    path: pathField ? pathField.value : '',
                    shape: shapeSelect ? shapeSelect.value : 'CIRCLE',
                    attributes: shapeAttributesField ? shapeAttributesField.value : '{}',
                    x: markerX ? markerX.value : '', y: markerY ? markerY.value : '',
                    drawMode: drawMode, svgHtml: svg ? svg.innerHTML : null,
                    previewHtml: preview ? preview.outerHTML : null
                };
            }
            function updatePathHistoryButtons() {
                if (undoButton) undoButton.disabled = pathUndoStack.length === 0;
                if (redoButton) redoButton.disabled = pathRedoStack.length === 0;
            }
            function recordPathEditorAction() {
                pathUndoStack.push(capturePathEditorState());
                if (pathUndoStack.length > 40) pathUndoStack.shift();
                pathRedoStack = [];
                updatePathHistoryButtons();
            }
            function restorePathEditorState(state) {
                if (!state) return;
                pathPoints = state.points || []; drawMode = !!state.drawMode; drawingPath = false;
                if (pathField) pathField.value = state.path || '';
                if (shapeSelect) shapeSelect.value = state.shape || 'CIRCLE';
                if (shapeAttributesField) shapeAttributesField.value = state.attributes || '{}';
                if (markerX) markerX.value = state.x || '';
                if (markerY) markerY.value = state.y || '';
                board.classList.toggle('path-drawing', drawMode);
                var svg = content.querySelector('#inspectionCoordinateSvgOverlay');
                if (state.svgHtml !== null) {
                    if (!svg) {
                        svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
                        svg.id = 'inspectionCoordinateSvgOverlay';
                        svg.setAttribute('class', 'inspection-coordinate-svg-overlay');
                        svg.setAttribute('viewBox', '0 0 100 100');
                        svg.setAttribute('preserveAspectRatio', 'none');
                        content.appendChild(svg);
                    }
                    svg.innerHTML = state.svgHtml;
                } else if (svg && svg.parentNode) svg.parentNode.removeChild(svg);
                var oldPreview = document.getElementById('inspectionCoordinatePreview');
                if (oldPreview && oldPreview.parentNode) oldPreview.parentNode.removeChild(oldPreview);
                if (state.previewHtml) {
                    var holder = document.createElement('div');
                    holder.innerHTML = state.previewHtml;
                    content.appendChild(holder.firstChild);
                }
                pathPreview = document.getElementById('inspectionCoordinatePathPreview');
                if (pathPreview) renderPathPreview(!!(pathField && pathField.value));
                pathStatusText(pathField && pathField.value
                    ? 'SVG Path siap disimpan. Save Inspection Point untuk menyimpan area ini.'
                    : (drawMode ? 'Draw mode aktif: drag mengikuti batas area.' : 'Perubahan geometri dipulihkan.'));
                updatePathHistoryButtons();
            }
            function undoPathAction() {
                if (!pathUndoStack.length) return;
                pathRedoStack.push(capturePathEditorState());
                restorePathEditorState(pathUndoStack.pop());
            }
            function redoPathAction() {
                if (!pathRedoStack.length) return;
                pathUndoStack.push(capturePathEditorState());
                restorePathEditorState(pathRedoStack.pop());
            }
            document.addEventListener('keydown', function (event) {
                if (!(event.ctrlKey || event.metaKey) || event.altKey) return;
                var target = event.target;
                if (target && (target.matches('input, textarea, select') || target.isContentEditable)) return;
                var key = String(event.key || '').toLowerCase();
                if (key === 'z' && !event.shiftKey && pathUndoStack.length) {
                    event.preventDefault(); undoPathAction();
                } else if ((key === 'y' || (key === 'z' && event.shiftKey)) && pathRedoStack.length) {
                    event.preventDefault(); redoPathAction();
                }
            });
            var drawButton = document.getElementById('btnStartPathDraw');
            var undoButton = document.getElementById('btnUndoPath');
            var clearPathButton = document.getElementById('btnClearPath');
            var pathStatus = document.getElementById('lblPathDrawStatus');
            var drawMode = false, drawingPath = false, suppressNextClick = false;
            var pathPoints = [], pathPreview = null;
            var rectangleDrawing = false, rectangleStart = null, rectanglePreview = null;
            var orthogonalDrawing = false, orthogonalPreviewPoint = null;
            if (shapeSelect && shapeSelect.value === 'RECTANGLE') board.classList.add('rectangle-drawing');
            function pathStatusText(text) { if (pathStatus) pathStatus.textContent = text; }
            function updateRectanglePreview(point) {
                if (!rectangleStart || !point) return;
                var left = Math.min(rectangleStart.x, point.x);
                var top = Math.min(rectangleStart.y, point.y);
                var width = Math.abs(point.x - rectangleStart.x);
                var height = Math.abs(point.y - rectangleStart.y);
                if (!rectanglePreview) {
                    rectanglePreview = document.createElement('div');
                    rectanglePreview.className = 'inspection-coordinate-rectangle-preview';
                    rectanglePreview.style.cssText = 'position:absolute;border:2px dashed #0d6efd;background:rgba(13,110,253,.16);pointer-events:none;z-index:20;box-sizing:border-box;';
                    content.appendChild(rectanglePreview);
                }
                rectanglePreview.style.left = left + '%';
                rectanglePreview.style.top = top + '%';
                rectanglePreview.style.width = width + '%';
                rectanglePreview.style.height = height + '%';
            }
            function renderRectangleEditorShape(left, top, width, height) {
                var svg = content.querySelector('#inspectionCoordinateSvgOverlay');
                if (!svg) {
                    svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
                    svg.id = 'inspectionCoordinateSvgOverlay';
                    svg.setAttribute('class', 'inspection-coordinate-svg-overlay');
                    svg.setAttribute('viewBox', '0 0 100 100');
                    svg.setAttribute('preserveAspectRatio', 'none');
                    content.appendChild(svg);
                }
                svg.querySelectorAll('.inspection-coordinate-rectangle-current[data-editor-preview="1"]').forEach(function (oldRect) {
                    if (oldRect.parentNode) oldRect.parentNode.removeChild(oldRect);
                });
                var rect = document.createElementNS('http://www.w3.org/2000/svg', 'rect');
                rect.setAttribute('class', 'inspection-coordinate-rectangle inspection-coordinate-rectangle-current');
                rect.setAttribute('data-editor-preview', '1');
                rect.setAttribute('x', Number(left.toFixed(3)));
                rect.setAttribute('y', Number(top.toFixed(3)));
                rect.setAttribute('width', Number(width.toFixed(3)));
                rect.setAttribute('height', Number(height.toFixed(3)));
                rect.setAttribute('fill', 'rgba(13,110,253,.30)');
                rect.setAttribute('stroke', '#0d6efd');
                rect.setAttribute('stroke-width', '1.4');
                rect.setAttribute('vector-effect', 'non-scaling-stroke');
                rect.setAttribute('pointer-events', 'none');
                svg.appendChild(rect);
            }
            function removeRectangleEditorShape() {
                var svg = content.querySelector('#inspectionCoordinateSvgOverlay');
                if (!svg) return;
                svg.querySelectorAll('.inspection-coordinate-rectangle-current[data-editor-preview="1"]').forEach(function (rect) {
                    if (rect.parentNode) rect.parentNode.removeChild(rect);
                });
            }
            function finishRectangleDrawing(event) {
                if (!rectangleDrawing) return;
                var end = mapPointFromEvent(event);
                var left = Math.min(rectangleStart.x, end.x);
                var top = Math.min(rectangleStart.y, end.y);
                var width = Math.abs(end.x - rectangleStart.x);
                var height = Math.abs(end.y - rectangleStart.y);
                rectangleDrawing = false;
                rectangleStart = null;
                if (rectanglePreview && rectanglePreview.parentNode) rectanglePreview.parentNode.removeChild(rectanglePreview);
                rectanglePreview = null;
                suppressNextClick = true;
                if (width < 0.35 || height < 0.35) {
                    removeRectangleEditorShape();
                    pathStatusText('Area terlalu kecil. Drag kembali untuk membuat rectangle.');
                    return;
                }
                if (pathField) pathField.value = '';
                if (shapeAttributesField) shapeAttributesField.value = JSON.stringify({
                    coordinateSpace: 'PERCENT_100',
                    x: Number(left.toFixed(3)), y: Number(top.toFixed(3)),
                    width: Number(width.toFixed(3)), height: Number(height.toFixed(3))
                });
                if (markerX) markerX.value = Number((left + width / 2).toFixed(3)).toFixed(2);
                if (markerY) markerY.value = Number((top + height / 2).toFixed(3)).toFixed(2);
                renderRectangleEditorShape(left, top, width, height);
                pathStatusText('Rectangle area siap disimpan. Save Inspection Point untuk menyimpan blok ini.');
            }
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
                    pathPreview.setAttribute('fill', 'none');
                    pathPreview.setAttribute('stroke', '#0d6efd');
                    pathPreview.setAttribute('stroke-width', '0.8');
                    pathPreview.setAttribute('stroke-linejoin', 'round');
                    pathPreview.setAttribute('vector-effect', 'non-scaling-stroke');
                    svg.appendChild(pathPreview);
                }
                return pathPreview;
            }
            function renderPathPreview(closePath, previewPoint) {
                var path = ensurePathPreview();
                if (!pathPoints.length && !previewPoint) { path.setAttribute('d', ''); return; }
                var points = pathPoints.slice(0);
                if (previewPoint) points.push(previewPoint);
                var orthogonal = shapeSelect && shapeSelect.value === 'ORTHOGONAL';
                var d = '';
                if (orthogonal) {
                    if (points.length) {
                        d = 'M ' + points[0].x.toFixed(2) + ' ' + points[0].y.toFixed(2);
                        for (var p = 1; p < points.length; p++) {
                            var prev = points[p - 1], next = points[p];
                            if (Math.abs(next.x - prev.x) >= Math.abs(next.y - prev.y)) {
                                if (Math.abs(next.x - prev.x) >= 0.01)
                                    d += ' L ' + next.x.toFixed(2) + ' ' + prev.y.toFixed(2);
                                d += ' L ' + next.x.toFixed(2) + ' ' + next.y.toFixed(2);
                            } else {
                                if (Math.abs(next.y - prev.y) >= 0.01)
                                    d += ' L ' + prev.x.toFixed(2) + ' ' + next.y.toFixed(2);
                                d += ' L ' + next.x.toFixed(2) + ' ' + next.y.toFixed(2);
                            }
                        }
                    }
                    path.setAttribute('fill', 'none');
                    path.setAttribute('stroke-width', '3.5');
                    path.setAttribute('stroke-linecap', 'round');
                } else {
                    d = 'M ' + points[0].x.toFixed(2) + ' ' + points[0].y.toFixed(2);
                    for (var q = 1; q < points.length; q++)
                        d += ' L ' + points[q].x.toFixed(2) + ' ' + points[q].y.toFixed(2);
                    if (closePath && points.length >= 3) d += ' Z';
                    path.setAttribute('fill', 'none');
                    path.setAttribute('stroke-width', '0.8');
                    path.setAttribute('stroke-linecap', 'round');
                }
                path.setAttribute('d', d);
            }
            function startPathDrawing() {
                recordPathEditorAction();
                if (shapeSelect && shapeSelect.value !== 'ORTHOGONAL') shapeSelect.value = 'PATH';
                drawMode = true; drawingPath = false; orthogonalDrawing = false; orthogonalPreviewPoint = null; pathPoints = []; suppressNextClick = false;
                if (pathField) pathField.value = '';
                if (shapeAttributesField && shapeSelect) {
                    if (shapeSelect.value === 'ORTHOGONAL')
                        shapeAttributesField.value = JSON.stringify({ renderMode: 'ORTHOGONAL' });
                    else if (shapeSelect.value === 'PATH')
                        shapeAttributesField.value = '{}';
                }
                var activeId = document.getElementById('hidPointID');
                var svg = content.querySelector('#inspectionCoordinateSvgOverlay');
                if (svg && activeId && activeId.value) {
                    var oldPath = svg.querySelector('.inspection-coordinate-path[data-point-id="' + activeId.value + '"]');
                    if (oldPath) oldPath.style.display = 'none';
                }
                renderPathPreview(false);
                board.classList.add('path-drawing');
                board.style.setProperty('cursor', 'crosshair', 'important');
                content.style.setProperty('cursor', 'crosshair', 'important');
                board.style.setProperty('touch-action', 'none', 'important');
                content.style.setProperty('touch-action', 'none', 'important');
                if (shapeSelect && shapeSelect.value === 'ORTHOGONAL')
                    pathStatusText('Siku aktif: klik titik demi titik untuk membuat segmen 90°. Double-click untuk selesai.');
                else
                    pathStatusText('PATH aktif: klik titik-titik jalur, lalu double-click untuk selesai tanpa garis penutup.');
            }
            function finishPathDrawing() {
                drawingPath = false; dragging = false; orthogonalDrawing = false; orthogonalPreviewPoint = null;
                if (shapeSelect && shapeSelect.value === 'ORTHOGONAL') {
                    if (pathPoints.length < 2) {
                        pathPoints = []; renderPathPreview(false);
                        pathStatusText('Garis siku perlu minimal 2 titik. Klik Draw SVG Path untuk mencoba lagi.');
                        return;
                    }
                    renderPathPreview(false);
                    var d = 'M ' + pathPoints[0].x.toFixed(2) + ' ' + pathPoints[0].y.toFixed(2);
                    for (var o = 1; o < pathPoints.length; o++) {
                        var prev = pathPoints[o - 1], next = pathPoints[o];
                        if (Math.abs(next.x - prev.x) >= Math.abs(next.y - prev.y)) {
                            if (Math.abs(next.x - prev.x) >= 0.01) d += ' L ' + next.x.toFixed(2) + ' ' + prev.y.toFixed(2);
                            d += ' L ' + next.x.toFixed(2) + ' ' + next.y.toFixed(2);
                        } else {
                            if (Math.abs(next.y - prev.y) >= 0.01) d += ' L ' + prev.x.toFixed(2) + ' ' + next.y.toFixed(2);
                            d += ' L ' + next.x.toFixed(2) + ' ' + next.y.toFixed(2);
                        }
                    }
                    if (pathField) pathField.value = d;
                    if (shapeAttributesField) shapeAttributesField.value = JSON.stringify({ renderMode: 'ORTHOGONAL' });
                    var sx = 0, sy = 0;
                    pathPoints.forEach(function (point) { sx += point.x; sy += point.y; });
                    if (markerX) markerX.value = (sx / pathPoints.length).toFixed(2);
                    if (markerY) markerY.value = (sy / pathPoints.length).toFixed(2);
                    drawMode = false;
                    board.classList.remove('path-drawing');
                    board.style.removeProperty('cursor'); content.style.removeProperty('cursor'); board.style.removeProperty('touch-action'); content.style.removeProperty('touch-action');
                    pathStatusText('Garis siku siap disimpan. Save Inspection Point untuk menyimpan jalur ini.');
                    return;
                }
                if (pathPoints.length < 2) {
                    pathPoints = []; renderPathPreview(false);
                    pathStatusText('PATH perlu minimal 2 titik. Klik Draw SVG Path untuk mencoba lagi.');
                    return;
                }
                renderPathPreview(false);
                var d = 'M ' + pathPoints[0].x.toFixed(2) + ' ' + pathPoints[0].y.toFixed(2);
                for (var p = 1; p < pathPoints.length; p++)
                    d += ' L ' + pathPoints[p].x.toFixed(2) + ' ' + pathPoints[p].y.toFixed(2);
                if (pathField) pathField.value = d;
                var sx = 0, sy = 0;
                pathPoints.forEach(function (point) { sx += point.x; sy += point.y; });
                if (markerX) markerX.value = (sx / pathPoints.length).toFixed(2);
                if (markerY) markerY.value = (sy / pathPoints.length).toFixed(2);
                drawMode = false;
                board.classList.remove('path-drawing');
                board.style.removeProperty('cursor'); content.style.removeProperty('cursor');
                board.style.removeProperty('touch-action'); content.style.removeProperty('touch-action');
                if (shapeAttributesField) shapeAttributesField.value = JSON.stringify({
                    coordinateSpace: 'PERCENT_100',
                    closed: false
                });
                pathStatusText('PATH / Polyline siap disimpan. Save Inspection Point untuk menyimpan garis ini.');
            }
            if (drawButton) drawButton.addEventListener('click', function () {
                if (shapeSelect && shapeSelect.value === 'RECTANGLE') {
                    recordPathEditorAction();
                    drawMode = false;
                    drawingPath = false;
                    orthogonalDrawing = false;
                    orthogonalPreviewPoint = null;
                    rectangleDrawing = false;
                    rectangleStart = null;
                    removeRectangleEditorShape();
                    board.classList.remove('path-drawing');
                    board.classList.add('rectangle-drawing');
                    board.style.setProperty('cursor', 'crosshair', 'important');
                    content.style.setProperty('cursor', 'crosshair', 'important');
                    board.style.setProperty('touch-action', 'none', 'important');
                    content.style.setProperty('touch-action', 'none', 'important');
                    pathStatusText('Rectangle aktif: drag dari sudut pertama ke sudut berlawanan untuk membuat blok area.');
                    return;
                }
                if (shapeSelect && shapeSelect.value === 'ORTHOGONAL' && drawMode && pathPoints.length >= 2) {
                    finishPathDrawing();
                    return;
                }
                startPathDrawing();
            });
            updatePathHistoryButtons();
            if (undoButton) undoButton.addEventListener('click', undoPathAction);
            if (redoButton) redoButton.addEventListener('click', redoPathAction);
            if (clearPathButton) clearPathButton.addEventListener('click', function (event) {
                event.preventDefault();
                event.stopPropagation();
                recordPathEditorAction();
                drawMode = false;
                drawingPath = false;
                orthogonalDrawing = false;
                orthogonalPreviewPoint = null;
                pathPoints = [];
                if (pathField) pathField.value = '';
                if (shapeSelect) shapeSelect.value = 'CIRCLE';
                if (shapeAttributesField) shapeAttributesField.value = '{}';
                if (rectanglePreview && rectanglePreview.parentNode) rectanglePreview.parentNode.removeChild(rectanglePreview);
                rectanglePreview = null; rectangleDrawing = false; rectangleStart = null;
                board.classList.remove('path-drawing', 'rectangle-drawing');
                board.style.cursor = ''; content.style.cursor = '';

                // Remove both the persisted path overlay and the temporary drawing.
                var activeId = document.getElementById('hidPointID');
                var svg = content.querySelector('#inspectionCoordinateSvgOverlay');
                if (svg) {
                    // Clear both shape types belonging to the active point.
                    // The orange circle is a separately-rendered current-point overlay,
                    // so removing only the PATH leaves that old dot visible.
                    if (activeId && activeId.value) {
                        svg.querySelectorAll(
                            '.inspection-coordinate-path[data-point-id="' + activeId.value + '"],' +
                            '.inspection-coordinate-circle[data-point-id="' + activeId.value + '"],' +
                            '.inspection-coordinate-rectangle[data-point-id="' + activeId.value + '"]'
                        ).forEach(function (oldShape) {
                            if (oldShape.parentNode) oldShape.parentNode.removeChild(oldShape);
                        });
                    }
                    var previewPath = svg.querySelector('#inspectionCoordinatePathPreview');
                    if (previewPath && previewPath.parentNode) previewPath.parentNode.removeChild(previewPath);
                }
                if (pathPreview && pathPreview.parentNode) pathPreview.parentNode.removeChild(pathPreview);
                pathPreview = null;
                var coordinatePreview = document.getElementById('inspectionCoordinatePreview');
                if (coordinatePreview && coordinatePreview.parentNode) coordinatePreview.parentNode.removeChild(coordinatePreview);
                removeRectangleEditorShape();
                pathStatusText('Path dan marker aktif dihapus. Klik map untuk menempatkan titik baru, lalu Save Inspection Point.');
            });
            if (shapeSelect) shapeSelect.addEventListener('change', function () {
                recordPathEditorAction();
                board.classList.toggle('rectangle-drawing', this.value === 'RECTANGLE');
                if (this.value !== 'ORTHOGONAL') {
                    orthogonalDrawing = false;
                    orthogonalPreviewPoint = null;
                }
                if (this.value === 'CIRCLE') {
                    drawMode = false; drawingPath = false; board.classList.remove('path-drawing'); board.style.cursor = ''; content.style.cursor = '';
                    if (pathField) pathField.value = '';
                    if (pathPreview) pathPreview.setAttribute('d', '');
                    var activeId = document.getElementById('hidPointID');
                    var svg = content.querySelector('#inspectionCoordinateSvgOverlay');
                    if (svg && activeId && activeId.value) {
                        var oldPath = svg.querySelector('.inspection-coordinate-path[data-point-id="' + activeId.value + '"]');
                        if (oldPath) oldPath.style.display = 'none';
                    }
                    pathStatusText('Circle: klik map untuk menentukan satu koordinat.');
                } else if (this.value === 'RECTANGLE') {
                    drawMode = false; drawingPath = false; board.classList.remove('path-drawing');
                    if (pathField) pathField.value = '';
                    if (pathPreview) pathPreview.setAttribute('d', '');
                    if (shapeAttributesField) shapeAttributesField.value = '{}';
                    removeRectangleEditorShape();
                    pathStatusText('Rectangle: klik Draw SVG Path, lalu drag dari sudut pertama ke sudut berlawanan untuk membuat blok area.');
                } else if (this.value === 'ORTHOGONAL') {
                    drawMode = false; drawingPath = false; board.classList.remove('path-drawing');
                    if (pathField) pathField.value = '';
                    if (pathPreview) pathPreview.setAttribute('d', '');
                    if (shapeAttributesField) shapeAttributesField.value = JSON.stringify({ renderMode: 'ORTHOGONAL' });
                    pathStatusText('Siku: klik Draw SVG Path, lalu klik titik demi titik. Double-click untuk selesai.');
                } else {
                    // PATH is a click-by-click polygon. Clear previous geometry
                    // when switching modes so a fresh set of vertices is required.
                    if (this.value === 'PATH') {
                        if (pathField) pathField.value = '';
                        if (pathPreview) pathPreview.setAttribute('d', '');
                        if (shapeAttributesField) shapeAttributesField.value = '{}';
                    }
                    pathStatusText('PATH: klik Draw SVG Path, klik titik-titik jalur, lalu double-click untuk selesai.');
                }
            });
            board.addEventListener('pointerdown', function (event) {
                if (shapeSelect && shapeSelect.value === 'RECTANGLE' && event.button === 0 &&
                    !(event.target.closest && event.target.closest('.inspection-coordinate-marker, .inspection-coordinate-circle, .inspection-coordinate-path, .inspection-coordinate-rectangle'))) {
                    event.preventDefault(); event.stopImmediatePropagation();
                    recordPathEditorAction();
                    rectangleDrawing = true;
                    rectangleStart = mapPointFromEvent(event);
                    suppressNextClick = true;
                    updateRectanglePreview(rectangleStart);
                    try { board.setPointerCapture(event.pointerId); } catch (_) { }
                    return;
                }
                // PATH uses the click event for each vertex so normal browser
                // click/double-click sequencing remains intact. Map panning already
                // ignores all pointerdowns while drawMode is active.
                if (drawMode && shapeSelect && shapeSelect.value === 'PATH' && event.button === 0) return;
                if (!drawMode || event.button !== 0) return;
                event.preventDefault(); event.stopImmediatePropagation();
                if (shapeSelect && shapeSelect.value === 'ORTHOGONAL') {
                    if (!drawingPath) {
                        drawingPath = true;
                        pathPoints = [mapPointFromEvent(event)];
                        orthogonalDrawing = true;
                        orthogonalPreviewPoint = null;
                        renderPathPreview(false);
                    }
                    suppressNextClick = true;
                    return;
                }
            }, true);
            board.addEventListener('pointermove', function (event) {
                if (rectangleDrawing) {
                    event.preventDefault(); event.stopImmediatePropagation();
                    updateRectanglePreview(mapPointFromEvent(event));
                    return;
                }
                if (!drawMode || !drawingPath) return;
                event.preventDefault(); event.stopImmediatePropagation();
                if (shapeSelect && shapeSelect.value === 'PATH') {
                    renderPathPreview(false, mapPointFromEvent(event));
                    return;
                }
                if (shapeSelect && shapeSelect.value === 'ORTHOGONAL') {
                    orthogonalPreviewPoint = mapPointFromEvent(event);
                    renderPathPreview(false, orthogonalPreviewPoint);
                    return;
                }
                var next = mapPointFromEvent(event), last = pathPoints[pathPoints.length - 1];
                var dx = next.x - last.x, dy = next.y - last.y;
                if (Math.sqrt(dx * dx + dy * dy) >= 0.25) {
                    pathPoints.push(next); renderPathPreview(false);
                }
            }, true);
            board.addEventListener('pointerup', function (event) {
                if (rectangleDrawing) {
                    event.preventDefault(); event.stopImmediatePropagation();
                    finishRectangleDrawing(event);
                    return;
                }
                if (!drawMode || !drawingPath) return;
                // Do not cancel pointerup for PATH: the following native click
                // is what commits each polygon vertex.
                if (shapeSelect && shapeSelect.value === 'PATH') return;
                event.preventDefault(); event.stopImmediatePropagation();
                if (shapeSelect && shapeSelect.value === 'ORTHOGONAL') {
                    var point = mapPointFromEvent(event);
                    var last = pathPoints[pathPoints.length - 1];
                    var distance = last ? Math.hypot(point.x - last.x, point.y - last.y) : 0;
                    if (distance >= 0.5) {
                        pathPoints.push(point);
                        orthogonalPreviewPoint = null;
                        renderPathPreview(false);
                        if (pathPoints.length === 2)
                            pathStatusText('Siku: titik berikutnya akan otomatis dikunci horizontal/vertikal. Double-click untuk selesai.');
                    }
                    return;
                }
                finishPathDrawing();
            }, true);
            board.addEventListener('dblclick', function (event) {
                if (drawMode && drawingPath && shapeSelect &&
                    (shapeSelect.value === 'PATH' || shapeSelect.value === 'ORTHOGONAL')) {
                    event.preventDefault(); event.stopImmediatePropagation();
                    if (pathPoints.length >= 2) finishPathDrawing();
                }
            }, true);
            board.addEventListener('pointercancel', function (event) {
                if (rectangleDrawing) {
                    event.preventDefault(); event.stopImmediatePropagation();
                    rectangleDrawing = false; rectangleStart = null; suppressNextClick = false;
                    if (rectanglePreview && rectanglePreview.parentNode) rectanglePreview.parentNode.removeChild(rectanglePreview);
                    rectanglePreview = null;
                    return;
                }
                if (!drawMode || !drawingPath) return;
                event.preventDefault(); event.stopImmediatePropagation();
                drawingPath = false; orthogonalDrawing = false; orthogonalPreviewPoint = null; pathPoints = []; suppressNextClick = false; renderPathPreview(false);
            }, true);

            var floatingZoomToolbar = board.querySelector('.inspection-map-toolbar-floating');
            if (floatingZoomToolbar) {
                // Toolbar interaction must not bubble to the map: otherwise a
                // zoom-button click can also move the active inspection point.
                ['pointerdown', 'click', 'dblclick'].forEach(function (eventName) {
                    floatingZoomToolbar.addEventListener(eventName, function (event) {
                        event.stopPropagation();
                    });
                });
            }
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
                // Drawing mode owns the pointer; never start map panning while a path is being drawn.
                if (drawMode || (event.target.closest && event.target.closest('.inspection-coordinate-marker, .inspection-coordinate-circle, .inspection-coordinate-path, .inspection-coordinate-rectangle')) || zoom <= 1 || event.button !== 0) return;
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
                var marker = event.target.closest ? event.target.closest('.inspection-coordinate-marker, .inspection-coordinate-circle, .inspection-coordinate-path, .inspection-coordinate-rectangle') : null;
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
                if (drawMode && shapeSelect && shapeSelect.value === 'PATH') {
                    event.preventDefault();
                    var vertex = mapPointFromEvent(event);
                    var previousVertex = pathPoints[pathPoints.length - 1];
                    if (!previousVertex || Math.hypot(vertex.x - previousVertex.x, vertex.y - previousVertex.y) >= 0.5)
                        pathPoints.push(vertex);
                    drawingPath = true;
                    renderPathPreview(false);
                    pathStatusText('PATH: ' + pathPoints.length + ' titik · klik titik berikutnya, double-click untuk selesai.');
                    return;
                }
                if (drawMode) { event.preventDefault(); return; }
                // Once PATH/ORTHOGONAL geometry is finished, ordinary map clicks
                // must not replace its centroid anchor with a stray yellow marker.
                if (shapeSelect && (shapeSelect.value === 'PATH' || shapeSelect.value === 'ORTHOGONAL') &&
                    pathField && pathField.value) {
                    event.preventDefault();
                    return;
                }
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
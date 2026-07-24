/*
  InteractiveMacOSDesktopHeroController.js
  -----------------------------------------
  Product story (user, 2026-07-24): the landing hero should feel like a real
  tiny macOS desktop — not a static mock. Visitors can drag/resize windows by
  the title bar, type in the document/IDE, close windows into desktop file
  icons, and drop those icons into a folder. SuperDimmer’s isolation proof
  stays: ONLY the dim handle bar changes the bright-page veil. Clicking the
  wallpaper or window body does not move windows or change dimming.

  Why a dedicated file: the hero used to be a clip-path slider plus an app-name
  cycle timer. That became hard to reason about once window chrome, icons, and
  folder drops were requested. One controller keeps the “desktop OS” graph in
  one place for later agents.

  Wired from index.html after DOM ready (IIFE at bottom of this file).
*/

(function InteractiveMacOSDesktopHeroController() {
    const desktop = document.getElementById('heroDesktop');
    if (!desktop) return;

    const menubarApp = document.getElementById('heroMenubarAppName');
    const iconsLayer = document.getElementById('heroDesktopIcons');
    const folderEl = document.getElementById('heroDeskFolder');
    const folderBadge = document.getElementById('heroFolderBadge');
    const folderWindow = document.getElementById('heroFolderWindow');
    const folderWindowBody = document.getElementById('heroFolderWindowBody');
    const dimHandle = document.getElementById('heroDimHandle');
    const brightPage = document.getElementById('heroPdfPage');
    const dimVeil = document.getElementById('heroPdfDim');
    const statusApp = document.getElementById('heroStatusAppName');

    let zCounter = 20;
    let dimDragging = false;
    /*
      Folder inventory: file ids that live inside the folder instead of on the
      desktop. Kept separate from DOM so reopen / drag-out stay consistent.
    */
    const folderContents = new Set();

    const windows = Array.from(desktop.querySelectorAll('.hc-window[data-window-id]'));

    function bringToFront(win) {
        zCounter += 1;
        win.style.zIndex = String(zCounter);
        windows.forEach((w) => w.classList.toggle('is-focused', w === win));
        const app = win.getAttribute('data-app-name') || 'Finder';
        if (menubarApp) menubarApp.textContent = app;
        if (statusApp && win.getAttribute('data-window-id') === 'doc') {
            statusApp.textContent = app;
        }
    }

    function desktopRect() {
        return desktop.getBoundingClientRect();
    }

    function clampWindowRect(left, top, width, height) {
        const rect = desktopRect();
        const menuH = 28;
        const minW = 180;
        const minH = 140;
        width = Math.max(minW, Math.min(width, rect.width - 8));
        height = Math.max(minH, Math.min(height, rect.height - menuH - 8));
        left = Math.max(0, Math.min(left, rect.width - width));
        top = Math.max(menuH, Math.min(top, rect.height - height));
        return { left, top, width, height };
    }

    function setWindowBox(win, left, top, width, height) {
        const box = clampWindowRect(left, top, width, height);
        win.style.left = box.left + 'px';
        win.style.top = box.top + 'px';
        win.style.width = box.width + 'px';
        win.style.height = box.height + 'px';
        /*
          After move/resize, re-sync dim clip so the veil still bisects the
          bright page correctly in page-local coordinates.
        */
        if (win.getAttribute('data-window-id') === 'doc') {
            syncDimFromHandle();
        }
    }

    function initWindowGeometry() {
        const rect = desktopRect();
        /*
          Leave a ~88px desktop-icon column on the left so the Projects folder
          is never buried under the IDE (caught in browser QA on first layout).
        */
        const iconRail = 96;
        windows.forEach((win) => {
            const id = win.getAttribute('data-window-id');
            if (id === 'ide') {
                setWindowBox(win, iconRail, rect.height * 0.14, rect.width * 0.31, rect.height * 0.70);
            } else if (id === 'doc') {
                setWindowBox(win, iconRail + rect.width * 0.33, rect.height * 0.14, rect.width * 0.50, rect.height * 0.70);
            } else if (id === 'folder') {
                setWindowBox(win, rect.width * 0.28, rect.height * 0.22, Math.min(340, rect.width * 0.42), Math.min(260, rect.height * 0.45));
            }
        });
    }

    /* ---------- Dim handle: ONLY the bar changes the veil ---------- */
    function applyDimFromClientX(clientX) {
        if (!dimHandle || !brightPage || !dimVeil) return;
        const stageRect = desktopRect();
        const pageRect = brightPage.getBoundingClientRect();
        if (pageRect.width < 4) return;

        let pct = ((clientX - stageRect.left) / stageRect.width) * 100;
        pct = Math.max(4, Math.min(96, pct));
        dimHandle.style.left = pct + '%';

        const handleX = stageRect.left + (pct / 100) * stageRect.width;
        let leftClipPct = ((handleX - pageRect.left) / pageRect.width) * 100;
        leftClipPct = Math.max(0, Math.min(100, leftClipPct));
        dimVeil.style.clipPath = 'inset(0 0 0 ' + leftClipPct + '%)';
    }

    function syncDimFromHandle() {
        if (!dimHandle) return;
        const stageRect = desktopRect();
        const pct = parseFloat(dimHandle.style.left) || 55;
        applyDimFromClientX(stageRect.left + (pct / 100) * stageRect.width);
    }

    function wireDimHandle() {
        if (!dimHandle) return;
        dimHandle.addEventListener('pointerdown', (e) => {
            e.preventDefault();
            e.stopPropagation();
            dimDragging = true;
            dimHandle.setPointerCapture(e.pointerId);
            applyDimFromClientX(e.clientX);
        });
        dimHandle.addEventListener('pointermove', (e) => {
            if (!dimDragging) return;
            applyDimFromClientX(e.clientX);
        });
        const stop = () => { dimDragging = false; };
        dimHandle.addEventListener('pointerup', stop);
        dimHandle.addEventListener('pointercancel', stop);
    }

    /* ---------- Window drag (title bar only) + resize ---------- */
    function wireWindowChrome(win) {
        const titlebar = win.querySelector('.hc-titlebar');
        const closeBtn = win.querySelector('.hc-traffic .r');
        const minBtn = win.querySelector('.hc-traffic .y');
        const zoomBtn = win.querySelector('.hc-traffic .g');

        win.addEventListener('pointerdown', () => bringToFront(win));

        if (titlebar) {
            titlebar.addEventListener('pointerdown', (e) => {
                /*
                  Traffic lights handle their own clicks — do not start a drag
                  when the user is aiming at close/minimize/zoom.
                */
                if (e.target.closest('.hc-traffic')) return;
                e.preventDefault();
                bringToFront(win);
                const startX = e.clientX;
                const startY = e.clientY;
                const startLeft = win.offsetLeft;
                const startTop = win.offsetTop;
                const width = win.offsetWidth;
                const height = win.offsetHeight;

                function onMove(ev) {
                    setWindowBox(
                        win,
                        startLeft + (ev.clientX - startX),
                        startTop + (ev.clientY - startY),
                        width,
                        height
                    );
                }
                function onUp() {
                    window.removeEventListener('pointermove', onMove);
                    window.removeEventListener('pointerup', onUp);
                }
                window.addEventListener('pointermove', onMove);
                window.addEventListener('pointerup', onUp);
            });
        }

        // Resize grips: eight edges/corners. Content area never starts resize.
        win.querySelectorAll('.hc-resize').forEach((grip) => {
            grip.addEventListener('pointerdown', (e) => {
                e.preventDefault();
                e.stopPropagation();
                bringToFront(win);
                const dir = grip.getAttribute('data-dir') || 'se';
                const startX = e.clientX;
                const startY = e.clientY;
                const startLeft = win.offsetLeft;
                const startTop = win.offsetTop;
                const startW = win.offsetWidth;
                const startH = win.offsetHeight;

                function onMove(ev) {
                    const dx = ev.clientX - startX;
                    const dy = ev.clientY - startY;
                    let left = startLeft;
                    let top = startTop;
                    let width = startW;
                    let height = startH;
                    if (dir.includes('e')) width = startW + dx;
                    if (dir.includes('s')) height = startH + dy;
                    if (dir.includes('w')) {
                        left = startLeft + dx;
                        width = startW - dx;
                    }
                    if (dir.includes('n')) {
                        top = startTop + dy;
                        height = startH - dy;
                    }
                    setWindowBox(win, left, top, width, height);
                }
                function onUp() {
                    window.removeEventListener('pointermove', onMove);
                    window.removeEventListener('pointerup', onUp);
                }
                window.addEventListener('pointermove', onMove);
                window.addEventListener('pointerup', onUp);
            });
        });

        function closeToDesktopIcon() {
            const fileId = win.getAttribute('data-file-id');
            if (!fileId) {
                win.classList.add('is-closed');
                return;
            }
            win.classList.add('is-closed');
            if (folderContents.has(fileId)) {
                renderFolderWindowBody();
                updateFolderBadge();
                return;
            }
            ensureDesktopFileIcon(fileId, win);
            refreshMenubarAfterClose();
        }

        if (closeBtn) {
            closeBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                if (win.getAttribute('data-window-id') === 'folder') {
                    win.classList.add('is-closed');
                    refreshMenubarAfterClose();
                    return;
                }
                closeToDesktopIcon();
            });
        }
        if (minBtn) {
            minBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                if (win.getAttribute('data-window-id') === 'folder') {
                    win.classList.add('is-closed');
                    refreshMenubarAfterClose();
                    return;
                }
                // Yellow = park as desktop icon (same mental model as close here)
                closeToDesktopIcon();
            });
        }
        if (zoomBtn) {
            zoomBtn.addEventListener('click', (e) => {
                e.stopPropagation();
                bringToFront(win);
                const rect = desktopRect();
                const isZoomed = win.classList.toggle('is-zoomed');
                if (isZoomed) {
                    win.setAttribute('data-prev-box', JSON.stringify({
                        left: win.offsetLeft,
                        top: win.offsetTop,
                        width: win.offsetWidth,
                        height: win.offsetHeight
                    }));
                    setWindowBox(win, 8, 36, rect.width - 16, rect.height - 48);
                } else {
                    try {
                        const prev = JSON.parse(win.getAttribute('data-prev-box') || '{}');
                        if (prev.width) setWindowBox(win, prev.left, prev.top, prev.width, prev.height);
                    } catch (_) { /* ignore bad restore */ }
                }
            });
        }
    }

    function refreshMenubarAfterClose() {
        const open = windows.find((w) => !w.classList.contains('is-closed') && w.getAttribute('data-window-id') !== 'folder');
        const folderOpen = folderWindow && !folderWindow.classList.contains('is-closed');
        if (open) bringToFront(open);
        else if (folderOpen) {
            if (menubarApp) menubarApp.textContent = 'Finder';
        } else if (menubarApp) {
            menubarApp.textContent = 'Finder';
        }
    }

    /* ---------- Desktop file icons ---------- */
    function fileMetaFromWindow(win) {
        return {
            id: win.getAttribute('data-file-id'),
            label: win.getAttribute('data-file-label') || 'Untitled',
            kind: win.getAttribute('data-file-kind') || 'doc',
            app: win.getAttribute('data-app-name') || 'App'
        };
    }

    function ensureDesktopFileIcon(fileId, win) {
        let icon = iconsLayer.querySelector('.hc-desk-icon[data-file-id="' + fileId + '"]');
        if (!icon) {
            const meta = fileMetaFromWindow(win);
            icon = document.createElement('div');
            icon.className = 'hc-desk-icon hc-file-icon';
            icon.setAttribute('data-file-id', meta.id);
            icon.setAttribute('data-file-kind', meta.kind);
            icon.setAttribute('tabindex', '0');
            icon.innerHTML =
                '<div class="hc-desk-icon-art" aria-hidden="true"></div>' +
                '<div class="hc-desk-icon-label"></div>';
            icon.querySelector('.hc-desk-icon-label').textContent = meta.label;
            iconsLayer.appendChild(icon);
            placeIconInFreeSlot(icon);
            wireFileIcon(icon);
        }
        icon.classList.remove('is-in-folder');
        icon.hidden = false;
    }

    function placeIconInFreeSlot(icon) {
        const rect = desktopRect();
        const used = Array.from(iconsLayer.querySelectorAll('.hc-desk-icon:not([hidden])'))
            .filter((el) => el !== icon)
            .map((el) => ({ left: el.offsetLeft, top: el.offsetTop }));
        // Right column of desktop, below menu bar — classic Finder layout.
        let top = 48;
        const left = rect.width - 96;
        const step = 88;
        while (used.some((u) => Math.abs(u.left - left) < 40 && Math.abs(u.top - top) < 40)) {
            top += step;
        }
        icon.style.left = left + 'px';
        icon.style.top = Math.min(top, rect.height - 90) + 'px';
    }

    function openWindowForFile(fileId) {
        const win = windows.find((w) => w.getAttribute('data-file-id') === fileId);
        if (!win) return;
        folderContents.delete(fileId);
        updateFolderBadge();
        renderFolderWindowBody();
        const icon = iconsLayer.querySelector('.hc-desk-icon[data-file-id="' + fileId + '"]');
        if (icon) icon.hidden = true;
        win.classList.remove('is-closed');
        bringToFront(win);
        syncDimFromHandle();
    }

    function wireFileIcon(icon) {
        icon.addEventListener('dblclick', (e) => {
            e.preventDefault();
            openWindowForFile(icon.getAttribute('data-file-id'));
        });
        icon.addEventListener('pointerdown', (e) => {
            if (e.button !== 0) return;
            e.preventDefault();
            e.stopPropagation();
            const startX = e.clientX;
            const startY = e.clientY;
            const startLeft = icon.offsetLeft;
            const startTop = icon.offsetTop;
            let moved = false;
            icon.classList.add('is-dragging');

            function onMove(ev) {
                moved = true;
                const desk = desktopRect();
                let left = startLeft + (ev.clientX - startX);
                let top = startTop + (ev.clientY - startY);
                left = Math.max(4, Math.min(left, desk.width - 72));
                top = Math.max(32, Math.min(top, desk.height - 80));
                icon.style.left = left + 'px';
                icon.style.top = top + 'px';

                if (folderEl) {
                    const fr = folderEl.getBoundingClientRect();
                    const over = ev.clientX >= fr.left && ev.clientX <= fr.right &&
                        ev.clientY >= fr.top && ev.clientY <= fr.bottom;
                    folderEl.classList.toggle('is-drop-target', over);
                }
            }
            function onUp(ev) {
                window.removeEventListener('pointermove', onMove);
                window.removeEventListener('pointerup', onUp);
                icon.classList.remove('is-dragging');
                if (folderEl) folderEl.classList.remove('is-drop-target');

                if (folderEl) {
                    const fr = folderEl.getBoundingClientRect();
                    const over = ev.clientX >= fr.left && ev.clientX <= fr.right &&
                        ev.clientY >= fr.top && ev.clientY <= fr.bottom;
                    if (over) {
                        dropIconIntoFolder(icon);
                        return;
                    }
                }
                // Single click without move = select only; reopen is double-click.
                if (!moved) {
                    iconsLayer.querySelectorAll('.hc-desk-icon').forEach((el) => el.classList.remove('is-selected'));
                    icon.classList.add('is-selected');
                }
            }
            window.addEventListener('pointermove', onMove);
            window.addEventListener('pointerup', onUp);
        });
    }

    function dropIconIntoFolder(icon) {
        const fileId = icon.getAttribute('data-file-id');
        if (!fileId) return;
        folderContents.add(fileId);
        icon.hidden = true;
        icon.classList.add('is-in-folder');
        updateFolderBadge();
        renderFolderWindowBody();
        // Brief bounce feedback on the folder
        if (folderEl) {
            folderEl.classList.add('is-accepted');
            window.setTimeout(() => folderEl.classList.remove('is-accepted'), 420);
        }
    }

    function updateFolderBadge() {
        if (!folderBadge) return;
        const n = folderContents.size;
        folderBadge.textContent = String(n);
        folderBadge.hidden = n === 0;
    }

    function renderFolderWindowBody() {
        if (!folderWindowBody) return;
        folderWindowBody.innerHTML = '';
        if (folderContents.size === 0) {
            folderWindowBody.innerHTML = '<div class="hc-folder-empty">Folder is empty — drag file icons here</div>';
            return;
        }
        folderContents.forEach((fileId) => {
            const win = windows.find((w) => w.getAttribute('data-file-id') === fileId);
            if (!win) return;
            const meta = fileMetaFromWindow(win);
            const row = document.createElement('button');
            row.type = 'button';
            row.className = 'hc-folder-item';
            row.setAttribute('data-file-id', fileId);
            row.innerHTML =
                '<span class="hc-folder-item-art" data-kind="' + meta.kind + '"></span>' +
                '<span class="hc-folder-item-label"></span>' +
                '<span class="hc-folder-item-hint">Double-click to open · drag out</span>';
            row.querySelector('.hc-folder-item-label').textContent = meta.label;
            row.addEventListener('dblclick', () => openWindowForFile(fileId));
            // Drag out of folder back to desktop
            row.addEventListener('pointerdown', (e) => {
                if (e.button !== 0) return;
                e.preventDefault();
                const ghost = row;
                ghost.classList.add('is-dragging');
                function onUp(ev) {
                    window.removeEventListener('pointerup', onUp);
                    ghost.classList.remove('is-dragging');
                    const desk = desktopRect();
                    const insideFolderWin = folderWindow && !folderWindow.classList.contains('is-closed') &&
                        ev.clientX >= folderWindow.getBoundingClientRect().left &&
                        ev.clientX <= folderWindow.getBoundingClientRect().right &&
                        ev.clientY >= folderWindow.getBoundingClientRect().top &&
                        ev.clientY <= folderWindow.getBoundingClientRect().bottom;
                    if (insideFolderWin) return;
                    // Dropped outside folder window → restore desktop icon
                    folderContents.delete(fileId);
                    updateFolderBadge();
                    ensureDesktopFileIcon(fileId, win);
                    const icon = iconsLayer.querySelector('.hc-desk-icon[data-file-id="' + fileId + '"]');
                    if (icon) {
                        icon.style.left = Math.max(8, ev.clientX - desk.left - 28) + 'px';
                        icon.style.top = Math.max(36, ev.clientY - desk.top - 28) + 'px';
                        icon.hidden = false;
                    }
                    renderFolderWindowBody();
                }
                window.addEventListener('pointerup', onUp);
            });
            folderWindowBody.appendChild(row);
        });
    }

    function wireFolder() {
        if (!folderEl) return;
        // Initial folder position — left side of desktop
        folderEl.style.left = '18px';
        folderEl.style.top = '48px';

        folderEl.addEventListener('dblclick', (e) => {
            e.preventDefault();
            if (!folderWindow) return;
            folderWindow.classList.remove('is-closed');
            bringToFront(folderWindow);
            if (menubarApp) menubarApp.textContent = 'Finder';
            renderFolderWindowBody();
        });

        folderEl.addEventListener('pointerdown', (e) => {
            if (e.button !== 0) return;
            e.preventDefault();
            e.stopPropagation();
            const startX = e.clientX;
            const startY = e.clientY;
            const startLeft = folderEl.offsetLeft;
            const startTop = folderEl.offsetTop;
            function onMove(ev) {
                const desk = desktopRect();
                let left = startLeft + (ev.clientX - startX);
                let top = startTop + (ev.clientY - startY);
                left = Math.max(4, Math.min(left, desk.width - 72));
                top = Math.max(32, Math.min(top, desk.height - 80));
                folderEl.style.left = left + 'px';
                folderEl.style.top = top + 'px';
            }
            function onUp() {
                window.removeEventListener('pointermove', onMove);
                window.removeEventListener('pointerup', onUp);
            }
            window.addEventListener('pointermove', onMove);
            window.addEventListener('pointerup', onUp);
        });
    }

    /* ---------- App-name cycle for the bright doc (paused while typing) ---------- */
    let cyclePaused = false;
    let cycleIndex = 0;
    const scenes = [
        { app: 'Preview', title: 'Q3-Roadmap.pdf — Preview', toolbarMeta: 'Page 1 of 12', toolbarHint: '· Bright page in Preview', heading: 'Q3 Product Roadmap', meta: 'White PDF · dark mode cannot restyle this' },
        { app: 'Safari', title: 'Design Spec — Safari', toolbarMeta: 'superdimmer.com', toolbarHint: '· Bright page in Safari', heading: 'Product Design Spec', meta: 'White webpage · site chrome stays dark around it' },
        { app: 'Mail', title: 'Re: Q3 Brief — Mail', toolbarMeta: 'Inbox · 1 of 48', toolbarHint: '· Bright message in Mail', heading: 'Re: Q3 Product Brief', meta: 'White email body · client chrome stays dark' },
        { app: 'Pages', title: 'Proposal.docx — Pages', toolbarMeta: 'Page 1', toolbarHint: '· Bright doc in Pages', heading: 'Client Proposal', meta: 'White document · cannot force dark theme' },
        { app: 'Google Chrome', title: 'Research Notes — Chrome', toolbarMeta: 'docs.google.com', toolbarHint: '· Bright tab in Chrome', heading: 'Shared Research Notes', meta: 'White web document · browser UI stays untouched' },
        { app: 'Notes', title: 'Meeting Notes — Notes', toolbarMeta: 'Today', toolbarHint: '· Bright note in Notes', heading: 'Monday Meeting Notes', meta: 'White note · light content in a dark evening' },
        { app: 'Numbers', title: 'Budget-Q3.numbers — Numbers', toolbarMeta: 'Sheet 1', toolbarHint: '· Bright sheet in Numbers', heading: 'Q3 Budget Spreadsheet', meta: 'White spreadsheet · cells stay legible when softened' },
        { app: 'Microsoft Word', title: 'Contract-v4.docx — Word', toolbarMeta: 'Page 1 of 18', toolbarHint: '· Bright doc in Word', heading: 'Service Agreement v4', meta: 'White Word page · office docs rarely offer true dark mode' }
    ];

    function applyBrightScene(scene) {
        const docWin = windows.find((w) => w.getAttribute('data-window-id') === 'doc');
        if (!docWin || docWin.classList.contains('is-closed')) return;
        docWin.setAttribute('data-app-name', scene.app);
        docWin.setAttribute('data-file-label', scene.heading);
        const title = document.getElementById('heroBrightWindowTitle');
        const toolbarMeta = document.getElementById('heroBrightToolbarMeta');
        const toolbarHint = document.getElementById('heroBrightToolbarHint');
        const heading = document.getElementById('heroBrightDocHeading');
        const meta = document.getElementById('heroBrightDocMeta');
        if (title) title.textContent = scene.title;
        if (toolbarMeta) toolbarMeta.textContent = scene.toolbarMeta;
        if (toolbarHint) toolbarHint.textContent = scene.toolbarHint;
        if (heading) heading.textContent = scene.heading;
        if (meta) meta.textContent = scene.meta;
        if (docWin.classList.contains('is-focused')) {
            if (menubarApp) menubarApp.textContent = scene.app;
            if (statusApp) statusApp.textContent = scene.app;
        }
        // Keep desktop icon label in sync if parked
        const icon = iconsLayer && iconsLayer.querySelector('.hc-desk-icon[data-file-id="roadmap"]');
        if (icon) {
            const label = icon.querySelector('.hc-desk-icon-label');
            if (label) label.textContent = scene.heading;
        }
    }

    function wireTypingPause() {
        desktop.querySelectorAll('[contenteditable="true"]').forEach((el) => {
            el.addEventListener('focus', () => { cyclePaused = true; });
            el.addEventListener('input', () => { cyclePaused = true; });
        });
    }

    function startAppCycle() {
        applyBrightScene(scenes[0]);
        window.setInterval(() => {
            if (cyclePaused || document.hidden) return;
            const docWin = windows.find((w) => w.getAttribute('data-window-id') === 'doc');
            if (!docWin || docWin.classList.contains('is-closed')) return;
            cycleIndex = (cycleIndex + 1) % scenes.length;
            applyBrightScene(scenes[cycleIndex]);
        }, 3400);
    }

    /* ---------- Boot ---------- */
    windows.forEach(wireWindowChrome);
    wireDimHandle();
    wireFolder();
    wireTypingPause();
    initWindowGeometry();
    bringToFront(windows.find((w) => w.getAttribute('data-window-id') === 'doc') || windows[0]);
    requestAnimationFrame(() => {
        const rect = desktopRect();
        applyDimFromClientX(rect.left + rect.width * 0.58);
        startAppCycle();
    });
    window.addEventListener('resize', () => {
        // Keep icons/windows inside after layout changes; re-clamp positions.
        windows.forEach((win) => {
            if (win.classList.contains('is-closed')) return;
            setWindowBox(win, win.offsetLeft, win.offsetTop, win.offsetWidth, win.offsetHeight);
        });
        syncDimFromHandle();
    });
})();

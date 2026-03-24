window.onload = function () {
    var statusEl = document.getElementById('loading-status');
    function setStatus(message) {
        if (statusEl) statusEl.textContent = message;
    }

    window.addEventListener('error', function (event) {
        setStatus('Startup failed: ' + (event.message || 'Unknown web error'));
    });
    window.addEventListener('unhandledrejection', function (event) {
        var reason = event && event.reason ? event.reason : 'Unhandled promise rejection';
        setStatus('Startup failed: ' + reason);
    });

    // Check for Flutter engine periodically
    var checkInterval = setInterval(function () {
        // 'flt-glass-pane' is commonly used by Flutter Web.
        // We also check if the body has significantly more children (Flutter adding itself)
        if (document.querySelector('flt-glass-pane') || document.body.children.length > 3) {
            removeLoader();
        }
    }, 100);

    // Failsafe: show status after timeout so users don't stare at a blank page.
    setTimeout(function () {
        var hasFlutterRoot = document.querySelector('flt-glass-pane') || document.body.children.length > 3;
        if (!hasFlutterRoot) {
            setStatus('Still starting... If this persists, check browser console for errors.');
        } else {
            removeLoader();
        }
    }, 6000);

    function removeLoader() {
        clearInterval(checkInterval);
        var loader = document.getElementById('app-loading');
        if (loader) {
            loader.classList.add('fade-out');
            setTimeout(() => {
                loader.style.display = 'none';
            }, 500); // Wait for transition
        }
    }
};

// Config removed: window.flutterConfiguration is deprecated.
// Defaulting to auto-renderer (CanvasKit on Desktop) which supports Glassmorphism better.

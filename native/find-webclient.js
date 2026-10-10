async function tryConnect(server) {
    try {
        if (!server.startsWith("http")) {
            server = "http://" + server;
        }

        console.log("Checking connectivity to:", server);

        const resolvedUrl = await window.jmpCheckServerConnectivity(server);
        console.log("Server connectivity check passed");
        console.log("Resolved URL:", resolvedUrl);

        // Ensure the NativeShell settings proxy is ready before persisting
        // the Jellyfin server address.
        if (window.initCompleted) {
            await window.initCompleted;
        }

        // In Minitiger Desktop this setting represents the Jellyfin API/server,
        // not a separate web-client host. Property assignment is asynchronous
        // behind the NativeShell proxy, so persist it explicitly and wait for
        // the Qt settings callback before navigating to the bundled web origin.
        await new Promise((resolve, reject) => {
            try {
                window.api.settings.setValue(
                    'main',
                    'userWebClient',
                    server,
                    resolve
                );
            } catch (error) {
                reject(error);
            }
        });

        // Keep the in-page snapshot in sync too. This is only a local mirror;
        // the authoritative value above is now safely persisted.
        window.jmpInfo.settings.main.userWebClient = server;

        // When the full Minitiger Web build is embedded, stay inside the
        // desktop executable and let that local frontend talk to this server.
        // Non-Minitiger/upstream builds keep the original server-web behavior.
        if (window.jmpInfo.bundledMinitigerWeb && window.jmpInfo.bundledMinitigerWebUrl) {
            console.log("Opening bundled Minitiger Web:", window.jmpInfo.bundledMinitigerWebUrl);
            window.location = window.jmpInfo.bundledMinitigerWebUrl;
        } else {
            window.location = resolvedUrl;
        }

        return true;
    } catch (e) {
        console.error("Server connectivity check failed:", e);
        return false;
    }
}

const CONNECTION_TIMEOUT_MS = 15000;

const abortConnectivityCheck = () => {
    if (
        window.api
        && window.api.system
    ) {
        window.api.system.cancelServerConnectivity();
    }

    if (
        window.jmpCheckServerConnectivity
        && window.jmpCheckServerConnectivity.abort
    ) {
        window.jmpCheckServerConnectivity.abort();
    }
};

const tryConnectWithTimeout = async (
    server,
    timeoutMs = CONNECTION_TIMEOUT_MS
) => {
    let timedOut = false;
    let timeoutId = 0;

    const timeoutPromise =
        new Promise(resolve => {
            timeoutId = window.setTimeout(
                () => {
                    timedOut = true;
                    console.warn(
                        `Server connection timed out after ${timeoutMs} ms:`,
                        server
                    );
                    abortConnectivityCheck();
                    resolve(false);
                },
                timeoutMs
            );
        });

    const connected =
        await Promise.race([
            tryConnect(server),
            timeoutPromise
        ]);

    if (timeoutId) {
        window.clearTimeout(timeoutId);
    }

    return {
        connected: Boolean(connected),
        timedOut
    };
};

const showConnectionForm = (
    timedOut = false
) => {
    const address =
        document.getElementById('address');
    const title =
        document.getElementById('title');
    const spinner =
        document.getElementById('spinner');
    const button =
        document.getElementById('connect-button');

    isConnecting = false;

    title.textContent =
        timedOut
            ? (
                window.savedServerRecoveryTitle
                || 'Ist die Server-Adresse noch aktuell?'
            )
            : document
                .getElementById('title')
                .getAttribute('data-original-text');

    title.style.visibility = 'visible';
    address.classList.remove('connecting');
    address.style.visibility = 'visible';
    address.disabled = false;
    spinner.style.display = 'none';
    button.style.visibility = 'visible';

    document.removeEventListener(
        'keydown',
        cancelOnEscape
    );

    address.focus();

    if (timedOut) {
        address.select();
    }

    updateButtonState();
};

let isConnecting = false;

const updateButtonState = () => {
    const address = document.getElementById('address');
    const button = document.getElementById('connect-button');
    const hasValue = address.value.trim().length > 0;

    if (!isConnecting) {
        button.disabled = !hasValue;
    }
};

const cancelOnEscape = (e) => {
    if (isConnecting && e.key === 'Escape') {
        cancelConnection();
    }
};

const startConnecting = async () => {
    const address = document.getElementById('address');
    const title = document.getElementById('title');
    const spinner = document.getElementById('spinner');
    const button = document.getElementById('connect-button');
    const server = address.value;

    isConnecting = true;
    title.textContent = '';
    title.style.visibility = 'hidden';
    address.classList.add('connecting');
    address.style.visibility = 'hidden';
    address.disabled = true;
    spinner.style.display = 'block';
    button.style.visibility = 'hidden';
    document.addEventListener('keydown', cancelOnEscape);

    const {
        connected,
        timedOut
    } = await tryConnectWithTimeout(
        server
    );

    if (!connected) {
        showConnectionForm(
            timedOut
        );
    }
};

const cancelConnection = () => {
    if (!isConnecting) return;

    console.log("Cancelling connection");
    isConnecting = false;

    // Cancel C++ connectivity check and abort JS promise
    abortConnectivityCheck();

    const address = document.getElementById('address');
    const title = document.getElementById('title');
    const spinner = document.getElementById('spinner');
    const button = document.getElementById('connect-button');

    title.textContent = document.getElementById('title').getAttribute('data-original-text');
    title.style.visibility = 'visible';
    address.classList.remove('connecting');
    address.style.visibility = 'visible';
    address.disabled = false;
    spinner.style.display = 'none';
    button.style.visibility = 'visible';
    document.removeEventListener('keydown', cancelOnEscape);
    updateButtonState();
};

// Button click handler
document.getElementById('connect-button').addEventListener('click', (e) => {
    e.preventDefault();
    e.stopPropagation();

    if (!e.target.disabled) {
        startConnecting();
    }
});

// Form submit handler
document.getElementById('connect-form').addEventListener('submit', (e) => {
    e.preventDefault();
    if (!isConnecting) {
        startConnecting();
    }
});

// Input change handler
document.getElementById('address').addEventListener('input', updateButtonState);


// Enter key handler
document.addEventListener('keydown', (e) => {
    const address = document.getElementById('address');
    if (e.key === 'Enter' && !isConnecting && !address.disabled && address.value.trim()) {
        e.preventDefault();
        startConnecting();
    }
});

// Auto-connect on load
(async () => {
    console.log('Auto-connect: starting');

    await window.apiPromise;

    const savedServer = window.jmpInfo.settings.main.userWebClient;
    console.log('Auto-connect: savedServer =', savedServer);

    if (savedServer) {
        console.log('Auto-connect: checking saved server', savedServer);

        const address = document.getElementById('address');
        const title = document.getElementById('title');
        const spinner = document.getElementById('spinner');
        const button = document.getElementById('connect-button');

        // Set address value for potential display later
        address.value = savedServer;

        // Show connecting UI
        isConnecting = true;
        title.textContent = '';
        title.style.visibility = 'hidden';
        address.classList.add('connecting');
        address.style.visibility = 'hidden';
        address.disabled = true;
        spinner.style.display = 'block';
        button.style.visibility = 'hidden';
        document.addEventListener('keydown', cancelOnEscape);

        const {
            connected,
            timedOut
        } = await tryConnectWithTimeout(
            savedServer
        );

        if (!connected) {
            // After 15 seconds do not retry forever. Put the saved address
            // back into an editable field so an IP/server change can be
            // recovered without reinstalling the client.
            showConnectionForm(
                timedOut
            );
        }
    } else {
        const title = document.getElementById('title');
        const address = document.getElementById('address');
        const button = document.getElementById('connect-button');

        title.style.visibility = 'visible';
        address.style.visibility = 'visible';
        button.style.visibility = 'visible';
        address.focus();
        updateButtonState();
    }
})();

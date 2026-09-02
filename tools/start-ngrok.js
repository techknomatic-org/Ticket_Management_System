const ngrok = require('@ngrok/ngrok');
const fs = require('fs');
const path = require('path');

let activeListener = null;

async function startTunnel() {
  try {
    const port = process.env.PORT || 8080;
    console.log(`[ngrok] Starting tunnel for port ${port}...`);

    let configPath = path.join(process.env.LOCALAPPDATA || '', 'ngrok', 'ngrok.yml');
    console.log(`[ngrok] Using config path: ${configPath}`);

    const forwardOptions = {
      addr: port,
    };

    if (fs.existsSync(configPath)) {
      try {
        const content = fs.readFileSync(configPath, 'utf8');
        const match = content.match(/authtoken:\s*([^\r\n#]+)/);
        if (match && match[1]) {
          forwardOptions.authtoken = match[1].trim();
          console.log('[ngrok] Authtoken loaded from ngrok.yml');
        }
      } catch (e) {
        console.log('[ngrok] Passing config_path to ngrok');
        forwardOptions.config_path = configPath;
      }
    }

    // Assign to module-level variable to prevent V8 GC from calling Rust destructor
    activeListener = await ngrok.forward(forwardOptions);
    
    const url = activeListener.url();
    console.log('================================================================');
    console.log(`NGROK TUNNEL ONLINE: ${url}`);
    console.log(`Forwarding -> http://127.0.0.1:${port}`);
    console.log('================================================================');
    
    // Save URL to file for easy access
    const logDir = path.join(__dirname, '..', 'files', '_log');
    if (!fs.existsSync(logDir)) {
      fs.mkdirSync(logDir, { recursive: true });
    }
    fs.writeFileSync(path.join(logDir, 'ngrok_url.txt'), url, 'utf8');

    // Keep process alive indefinitely
    const keepAliveTimer = setInterval(() => {
      if (activeListener) {
        // Ping listener reference to ensure it never gets collected
        const currentUrl = activeListener.url ? activeListener.url() : url;
      }
    }, 5000);

    process.on('SIGINT', async () => {
      console.log('[ngrok] Stopping tunnel...');
      clearInterval(keepAliveTimer);
      if (activeListener) {
        await activeListener.close();
      }
      process.exit(0);
    });

    process.on('SIGTERM', async () => {
      console.log('[ngrok] Stopping tunnel...');
      clearInterval(keepAliveTimer);
      if (activeListener) {
        await activeListener.close();
      }
      process.exit(0);
    });

  } catch (err) {
    console.error('[ngrok] ERROR starting tunnel:', err);
    process.exit(1);
  }
}

// Keep global reference
global.ngrokRunner = startTunnel;
startTunnel();

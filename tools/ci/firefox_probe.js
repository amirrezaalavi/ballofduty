#!/usr/bin/env node
// CI FEASIBILITY PROBE — not a release gate.
//
// Minimal version of research Q3a: prove that a Linux CI runner can boot the
// Godot 4.7.2 Compatibility/WebGL2 web build in Firefox without a physical GPU.
// Firefox must run headed inside Xvfb; the prefs below are the research doc's
// software-WebRender overrides.
//
//   xvfb-run --auto-servernum --server-args="-screen 0 1280x720x24" \
//     node tools/ci/firefox_probe.js --url http://127.0.0.1:8099/index.html
//
// This script only prints observations. It is intentionally separate from
// browser_smoke.mjs so a failed feasibility run cannot be mistaken for a
// browser-matrix pass.

import { firefox } from 'playwright';

const args = process.argv.slice(2);
let url = 'http://127.0.0.1:8099/index.html';
for (let index = 0; index < args.length; index += 1) {
  if (args[index] === '--url' && args[index + 1]) {
    url = args[index + 1];
    index += 1;
  }
}

const browser = await firefox.launch({
  headless: false,
  firefoxUserPrefs: {
    'webgl.force-enabled': true,
    'webgl.disabled': false,
    'webgl.allow-immediate-mode': true,
    'gfx.webrender.all': true,
    'gfx.webrender.software': true,
    'layers.acceleration.force-enabled': true,
  },
});

const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
page.on('console', (message) => console.log(`[console ${message.type()}] ${message.text()}`));
page.on('pageerror', (error) => console.log(`[pageerror] ${error.message}`));

let exitCode = 0;
try {
  console.log(`navigating to ${url}`);
  await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 });

  console.log('waiting for #canvas and #boot removal');
  await page.waitForSelector('#canvas', { state: 'visible', timeout: 30000 });
  await page.waitForSelector('#boot', { state: 'detached', timeout: 30000 });

  const version = await page.evaluate(() => {
    const canvas = document.getElementById('canvas');
    const gl = canvas ? canvas.getContext('webgl2') : null;
    return gl ? gl.getParameter(gl.VERSION) : null;
  });
  const renderer = await page.evaluate(() => {
    const canvas = document.getElementById('canvas');
    const gl = canvas ? canvas.getContext('webgl2') : null;
    return gl ? gl.getParameter(gl.RENDERER) : null;
  });
  console.log(`webgl2: ${version || 'MISSING'}`);
  console.log(`renderer: ${renderer || 'unknown'}`);
  if (!version) {
    exitCode = 1;
  }

  await page.waitForTimeout(5000);
  console.log('probe finished');
} catch (error) {
  console.log(`probe failed: ${error.message}`);
  exitCode = 1;
} finally {
  await browser.close();
}

process.exitCode = exitCode;

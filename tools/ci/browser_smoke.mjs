#!/usr/bin/env node
// L9 browser smoke harness. Boots the exported web build, checks WebGL 2,
// pointer lock and (optionally) the in-match bridge, then writes metrics,
// the raw console stream and a screenshot.
//
//   node browser_smoke.mjs --url http://127.0.0.1:8080/index.html \
//     --browser chromium --out ../../artifacts/browser-smoke
//
// Exit code is non-zero only for: boot timeout, missing WebGL 2, or a
// non-harmless console error / pageerror. A failed pointer lock is a warning.
//
// Firefox needs a display (Xvfb in CI) and the firefoxUserPrefs below; see
// README.md. WebKit on Linux is a layout smoke test, not Safari.

import { mkdir, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { chromium, firefox, webkit } from 'playwright';

const BROWSERS = { chromium, firefox, webkit };

// Known-harmless engine/driver chatter from docs/research/L9-BROWSER-MATRIX.md.
const HARMLESS_PATTERNS = [
  /TexImage:\s*filter LINEAR/i,
  /filter LINEAR not supported on depth texture/i,
  /try_table/i,
  /WebAssembly.*\btry\b.*(deprecat|removed)/i,
  /\btry\b.*(deprecat|removed).*WebAssembly/i,
  /Vertex attribute 0/i,
  /viewport.*destination rect/i,
  /destination rect.*viewport/i,
  /Viewport rect differs/i,
];

const FIREFOX_PREFS = {
  'webgl.force-enabled': true,
  'webgl.disabled': false,
  'webgl.allow-immediate-mode': true,
  'gfx.webrender.all': true,
  'gfx.webrender.software': true,
  'layers.acceleration.force-enabled': true,
};

function parseArgs(argv) {
  const options = {
    url: 'http://127.0.0.1:8080/index.html',
    browser: 'chromium',
    out: 'artifacts/browser-smoke',
    headed: false,
    bootTimeout: 30000,
    joinTimeout: 20000,
  };
  for (let index = 2; index < argv.length; index += 1) {
    const arg = argv[index];
    const value = argv[index + 1];
    switch (arg) {
      case '--url':
        options.url = value;
        index += 1;
        break;
      case '--browser':
        options.browser = value;
        index += 1;
        break;
      case '--out':
        options.out = value;
        index += 1;
        break;
      case '--headed':
        options.headed = true;
        break;
      case '--headless':
        options.headed = false;
        break;
      case '--boot-timeout':
        options.bootTimeout = Number(value);
        index += 1;
        break;
      case '--join-timeout':
        options.joinTimeout = Number(value);
        index += 1;
        break;
      case '--help':
      case '-h':
        console.log(
          'usage: browser_smoke.mjs --url <url> --browser chromium|firefox|webkit --out <dir> '
          + '[--headed] [--boot-timeout ms] [--join-timeout ms]',
        );
        process.exit(0);
        break;
      default:
        throw new Error(`unknown argument: ${arg}`);
    }
  }
  if (!BROWSERS[options.browser]) {
    throw new Error(`unknown browser: ${options.browser}`);
  }
  return options;
}

function isHarmless(text) {
  return HARMLESS_PATTERNS.some((pattern) => pattern.test(text));
}

function fpsFromMs(ms) {
  return typeof ms === 'number' && ms > 0 ? 1000 / ms : null;
}

async function main() {
  const options = parseArgs(process.argv);
  await mkdir(options.out, { recursive: true });

  const consoleLines = [];
  const failures = [];
  const warnings = [];
  let consoleErrors = 0;
  let consoleWarnings = 0;
  let harmlessCount = 0;
  let pageErrors = 0;
  let realErrors = 0;

  function recordConsole(type, text, location) {
    const harmless = isHarmless(text);
    if (type === 'error') {
      consoleErrors += 1;
      if (!harmless) {
        realErrors += 1;
        failures.push(`console error: ${text}`);
      }
    } else if (type === 'warning') {
      consoleWarnings += 1;
    }
    if (harmless) {
      harmlessCount += 1;
    }
    const where = location && location.url
      ? ` (${location.url}:${location.lineNumber || 0})`
      : '';
    consoleLines.push(`${new Date().toISOString()} [${type}]${harmless ? ' [harmless]' : ''} ${text}${where}`);
  }

  const launchOptions = { headless: !options.headed };
  if (options.browser === 'firefox') {
    launchOptions.firefoxUserPrefs = FIREFOX_PREFS;
  }

  const browser = await BROWSERS[options.browser].launch(launchOptions);
  const context = await browser.newContext({ viewport: { width: 1280, height: 720 } });
  const page = await context.newPage();

  page.on('console', (message) => {
    recordConsole(message.type(), message.text(), message.location());
  });
  page.on('pageerror', (error) => {
    pageErrors += 1;
    const text = String(error && error.message ? error.message : error);
    const harmless = isHarmless(text);
    if (harmless) {
      harmlessCount += 1;
    } else {
      realErrors += 1;
      failures.push(`pageerror: ${text}`);
    }
    consoleLines.push(`${new Date().toISOString()} [pageerror]${harmless ? ' [harmless]' : ''} ${text}`);
  });

  const started = Date.now();
  let bootMs = null;
  let firstFrameMs = null;
  let webgl = null;
  let pointerLock = false;
  let inMatch = false;
  let bridgePresent = false;
  let bodState = null;
  let perf = null;
  let screenshotPath = join(options.out, `screenshot_${options.browser}.png`);

  try {
    await page.goto(options.url, { waitUntil: 'domcontentloaded', timeout: options.bootTimeout });
    await page.waitForSelector('#canvas', { state: 'visible', timeout: options.bootTimeout });
    await page.waitForSelector('#boot', { state: 'detached', timeout: options.bootTimeout });
    bootMs = Date.now() - started;

    firstFrameMs = await page.evaluate(() => new Promise((resolve) => {
      requestAnimationFrame((timestamp) => resolve(Math.round(timestamp)));
    }));

    webgl = await page.evaluate(() => {
      const canvas = document.getElementById('canvas');
      const gl = canvas ? canvas.getContext('webgl2') : null;
      if (!gl) {
        return null;
      }
      return {
        version: gl.getParameter(gl.VERSION),
        vendor: gl.getParameter(gl.VENDOR),
        renderer: gl.getParameter(gl.RENDERER),
      };
    });
    if (!webgl || !webgl.version) {
      failures.push('no WebGL 2 context on #canvas');
    }

    await page.waitForTimeout(400);
    await page.mouse.click(640, 360);
    pointerLock = await page.evaluate(
      () => document.pointerLockElement === document.getElementById('canvas'),
    );
    if (!pointerLock) {
      await page.waitForTimeout(350);
      await page.mouse.click(640, 360);
      pointerLock = await page.evaluate(
        () => document.pointerLockElement === document.getElementById('canvas'),
      );
    }
    if (!pointerLock) {
      warnings.push('pointerLock: false (click did not acquire the lock; not fatal)');
    }

    bridgePresent = await page.evaluate(() => typeof window.__bod_state !== 'undefined');
    bodState = await page.evaluate(
      () => (typeof window.__bod_state !== 'undefined' ? window.__bod_state : null),
    );
    const wantsJoin = /[?&]join=1(?:&|$)/.test(options.url);
    if (wantsJoin) {
      if (bridgePresent) {
        try {
          await page.waitForFunction(
            () => window.__bod_state && window.__bod_state.in_game === true,
            undefined,
            { timeout: options.joinTimeout },
          );
          inMatch = true;
        } catch {
          warnings.push(
            `join: bridge present but in_game did not become true within ${options.joinTimeout} ms`,
          );
        }
      } else {
        warnings.push('join: no __bod_state bridge, falling back to a fixed 15 s wait');
      }
      if (!inMatch) {
        await page.waitForTimeout(15000);
      }
    }

    const hasPerf = await page.evaluate(() => typeof window.__bod_perf === 'function');
    if (hasPerf) {
      try {
        await page.waitForFunction(
          () => {
            try {
              const report = JSON.parse(window.__bod_perf());
              return typeof report.frames_total === 'number' && report.frames_total > 0;
            } catch {
              return false;
            }
          },
          undefined,
          { timeout: 8000 },
        );
      } catch {
        warnings.push('perf: bridge did not publish a frame count within 8 s');
      }
      const raw = await page.evaluate(() => window.__bod_perf());
      try {
        perf = JSON.parse(raw);
      } catch {
        warnings.push('perf: __bod_perf() did not return valid JSON');
      }
    }
  } catch (error) {
    failures.push(`boot: ${String(error && error.message ? error.message : error)}`);
  }

  try {
    await page.screenshot({ path: screenshotPath, fullPage: false });
  } catch (error) {
    warnings.push(`screenshot failed: ${String(error && error.message ? error.message : error)}`);
    screenshotPath = null;
  }

  const metrics = {
    browser: options.browser,
    url: options.url,
    headed: options.headed,
    generated_at: new Date().toISOString(),
    boot_ms: bootMs,
    first_frame_ms: firstFrameMs,
    console_errors: consoleErrors,
    console_warnings: consoleWarnings,
    harmless_warnings: harmlessCount,
    page_errors: pageErrors,
    real_errors: realErrors,
    webgl_version: webgl ? webgl.version : null,
    webgl_vendor: webgl ? webgl.vendor : null,
    webgl_renderer: webgl ? webgl.renderer : null,
    pointer_lock: pointerLock,
    in_match: inMatch,
    bridge_present: bridgePresent,
    bod_state: bodState,
    fps_p50: perf ? fpsFromMs(perf.frame_ms_p50) : null,
    fps_p95: perf ? fpsFromMs(perf.frame_ms_p95) : null,
    fps_p99: perf ? fpsFromMs(perf.frame_ms_p99) : null,
    perf,
    warnings,
    failures,
  };

  await writeFile(
    join(options.out, `metrics_${options.browser}.json`),
    `${JSON.stringify(metrics, null, 2)}\n`,
  );
  await writeFile(
    join(options.out, `console_${options.browser}.log`),
    `${consoleLines.join('\n')}\n`,
  );

  await context.close();
  await browser.close();

  console.log(`browser: ${options.browser}`);
  console.log(`boot_ms: ${bootMs}`);
  console.log(`webgl: ${metrics.webgl_version}`);
  console.log(`pointer_lock: ${pointerLock}`);
  console.log(`in_match: ${inMatch}`);
  console.log(`console: ${consoleErrors} errors, ${consoleWarnings} warnings, ${harmlessCount} harmless`);
  console.log(`artifacts: ${options.out}`);
  for (const warning of warnings) {
    console.log(`warning: ${warning}`);
  }
  for (const failure of failures) {
    console.error(`failure: ${failure}`);
  }
  process.exitCode = failures.length > 0 ? 1 : 0;
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

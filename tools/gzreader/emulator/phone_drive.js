// The phone for phone_shots.lua: a real browser (Playwright's Chromium, at a
// phone's size) on the Kindle's phone page. Waits for <out>/phone-url.txt,
// connects Grimmory, Notes, a CalDAV account and two calendar links, sends the
// books given, and takes the README's phone screenshots (<out>/phone-*.png).
//   node phone_drive.js <out> <book.epub>...
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const OUT = process.argv[2];
const BOOKS = process.argv.slice(3);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const T0 = Date.now();
const say = (...a) => console.log('[phone ' + ((Date.now() - T0) / 1000).toFixed(1) + 's]', ...a);

async function waitForUrl() {
  for (let i = 0; i < 600; i++) {
    const p = path.join(OUT, 'phone-url.txt');
    if (fs.existsSync(p)) {
      const u = fs.readFileSync(p, 'utf8').trim();
      if (u) return u;
    }
    await sleep(1000);
  }
  throw new Error('no phone-url.txt');
}

const step = (n) => fs.writeFileSync(path.join(OUT, 'phone-step-' + n), '');

(async () => {
  const url = await waitForUrl();
  say('page open');
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, colorScheme: 'light' });
  page.setDefaultTimeout(90000);
  const shot = async (name, opts) => {
    await page.screenshot({ path: path.join(OUT, name + '.png'), ...(opts || {}) });
    say('shot', name);
  };
  const section = async (id, name) => {
    const el = page.locator('#' + id);
    await el.scrollIntoViewIfNeeded();
    await el.screenshot({ path: path.join(OUT, name + '.png') });
    say('shot', name);
  };
  const submit = async (button) => {
    await Promise.all([page.waitForNavigation({ waitUntil: 'load' }), button.click()]);
    const flash = await page.locator('.flash').first().textContent({ timeout: 1000 }).catch(() => '');
    say('->', (flash || '').trim());
  };
  await page.goto(url, { waitUntil: 'load' });
  await page.evaluate(() => window.scrollTo(0, 0));
  await shot('phone-1-start');
  await shot('phone-1-start-full', { fullPage: true });

  // Grimmory (a local password: the demo server has no single sign-on)
  await page.evaluate(() => document.querySelectorAll('#grimmory details').forEach((d) => { d.open = true; }));
  await page.fill('#g_server', 'http://127.0.0.1:18080');
  await page.fill('#g_username', 'reader');
  await page.fill('#g_password', 'demo');
  await submit(page.locator('#grimmory button[value="password"]'));
  await page.evaluate(() => window.scrollTo(0, 0));
  await shot('phone-2-grimmory');
  step(1);
  await sleep(4000);

  // Notes (Memos)
  await page.fill('#m_server', 'http://127.0.0.1:18097');
  await page.fill('#m_token', 'memos-test-token');
  await submit(page.locator('#notes button[type="submit"]').last());
  // Calendar: a CalDAV account, then two links (one Proton-style, with keys in it)
  await page.fill('#c_server', 'http://127.0.0.1:18095');
  await page.fill('#c_username', 'reader');
  await page.fill('#c_password', 'demo-app-password');
  await submit(page.locator('#calendar form').filter({ has: page.locator('#c_server') }).locator('button[type="submit"]'));
  await page.fill('#calendar textarea[name="links"]',
    'Family | webcal://127.0.0.1:18096/proton_sample.ics?CacheKey=s3cr3tCacheKey&PassphraseKey=s3cr3tPassphrase\n' +
    'Holidays | http://127.0.0.1:18096/holidays_sample.ics');
  await submit(page.locator('#calendar form').filter({ has: page.locator('textarea[name="links"]') }).locator('button[type="submit"]'));
  say('links:', (await page.locator('#calendar .results').textContent().catch(() => '')).trim());
  // edit a calendar on the phone: hide "Work"
  const work = page.locator('#calendar .row').filter({ hasText: 'Work' }).first();
  if (await work.count()) {
    const box = work.locator('input[type="checkbox"]');
    say('hiding Work');
    if (await box.isChecked()) await box.uncheck();
    await submit(work.locator('button[type="submit"]').first());
  }
  await section('calendar', 'phone-3-calendar');
  step(2);
  await sleep(4000);

  // Send books
  await page.locator('#books').scrollIntoViewIfNeeded();
  await page.setInputFiles('#files', BOOKS);
  await page.click('#send');
  await page.waitForFunction((n) => document.querySelectorAll('#up p.ok, #up .ok').length >= n, BOOKS.length, { timeout: 120000 })
    .catch(() => say('uploads: no confirmation seen'));
  await sleep(500);
  await section('books', 'phone-4-books');
  step(3);
  await page.goto(url.replace(/#.*$/, ''), { waitUntil: 'load' });
  await shot('phone-5-all-set-full', { fullPage: true });
  await shot('phone-5-all-set');
  step(4);
  await browser.close();
  say('done');
})().catch((e) => { console.error('[phone] error:', e.message); try { step(4); } catch (_e) { /* */ } process.exit(1); });

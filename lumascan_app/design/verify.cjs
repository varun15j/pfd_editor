// Source/logic verification only. Does not open a browser or validate layout.
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const listeners = {};
const elements = new Map();
const element = (selector) => {
  if (!elements.has(selector)) elements.set(selector, {
    innerHTML: '', textContent: '', hidden: true, style: {}, dataset: {},
    classList: { add() {}, remove() {}, toggle() {} },
    setAttribute() {}, focus() {}, querySelectorAll() { return []; },
  });
  return elements.get(selector);
};
const context = vm.createContext({
  document: {
    querySelector: element, querySelectorAll: () => [], activeElement: null,
    addEventListener: (name, callback) => { listeners[name] = callback; },
  },
  window: { addEventListener() {} }, location: { hash: '' }, navigator: {},
  setTimeout: () => 1, clearTimeout() {}, setInterval: () => 1, clearInterval() {},
});
const source = fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8');
vm.runInContext(source, context);
const evaluate = (expression) => vm.runInContext(expression, context);
let checks = 0;
const check = (label, expression) => { assert.ok(evaluate(expression), label); checks++; };
async function action(value) {
  await listeners.click({ target: { closest: () => ({ dataset: { action: value }, disabled: false }) } });
}
(async () => {
  check('12 distinct screens', 'screens.length === 12 && new Set(screens.map(s => s[0])).size === 12');
  for (const route of evaluate('screens.map(s => s[0])')) {
    const html = evaluate(`views[${JSON.stringify(route)}]()`);
    assert.ok(html.length > 300, route + ' has a rendered template');
    assert.ok(!html.includes('undefined'), route + ' has no undefined output');
    checks += 2;
  }
  check('reject crossed crop', '!validQuad([[0,0],[1,1],[1,0],[0,1]])');
  check('accept rectangular crop', 'validQuad([[0,0],[1,0],[1,1],[0,1]])');
  check('escape dynamic content', 'esc("<script>&") === "&lt;script&gt;&amp;"');
  await action('go:capture');
  check('new scan starts empty', 'state.pages.length === 0 && state.captured === 0');
  await action('shutter');
  check('shutter adds one sample', 'state.pages.length === 1 && state.captured === 1');
  await action('capture-done');
  check('done navigates to crop', 'state.screen === "crop"');
  await action('filter:B&W');
  check('filter selection retained', 'state.filter === "B&W"');
  await action('save-filter');
  check('save opens organizer', 'state.screen === "pages" && state.filterSaved === "B&W"');
  await action('page-copy:0');
  check('duplicate gets unique ID', 'state.pages.length === 2 && state.pages[0].id !== state.pages[1].id');
  await action('page-delete:0');
  await action('undo-page');
  check('deletion is reversible', 'state.pages.length === 2');
  await action('go:id');
  await action('id-front');
  await action('id-back');
  await action('id-swap');
  check('swap changes sample side content', 'idMini("front").includes("EXAMPLE / BACK")');
  await action('id-save');
  check('ID produces one layout page', 'state.pages.length === 1 && state.screen === "pages"');
  await action('go:video');
  await action('frame:2');
  await action('replace-frame');
  await action('video-save');
  check('video keeps chosen frames', 'state.pages.length === 5');
  check('replacement timestamp preserved', 'state.pages.some(p => p.name === "Frame at 00:10")');
  await action('go:photo');
  await action('photo-style:Warm');
  check('photo style selected', 'state.photoStyle === "Warm"');
  await action('photo-reset');
  check('photo reset restores defaults', 'state.photoStyle === "Natural" && state.exposure === 0');
  await action('go:export');
  await action('export');
  check('export opens simulation', '!document.querySelector("#modal").hidden');
  await action('cancel-job');
  check('cancel preserves pages', 'document.querySelector("#modal").hidden && state.pages.length === 5');
  for (const file of ['index.html', 'styles.css', 'app.js']) {
    const text = fs.readFileSync(path.join(__dirname, file), 'utf8');
    assert.ok(!/https?:\/\//.test(text), file + ' has no remote resources');
    checks++;
  }
  console.log(`${checks} source/logic checks passed. Browser layout and native processing are not tested.`);
})().catch(error => { console.error(error); process.exitCode = 1; });

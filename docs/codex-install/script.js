// Progressive enhancement: without JavaScript both OS guides stay readable.
const tabs = [...document.querySelectorAll('[data-os]')];
const panels = [...document.querySelectorAll('[data-os-panel]')];
const tablist = document.querySelector('[data-os-tabs]');
const validOS = new Set(['mac', 'windows']);

function selectOS(os, { focus = false, updateHash = false } = {}) {
  if (!validOS.has(os)) return;
  for (const tab of tabs) {
    const selected = tab.dataset.os === os;
    tab.setAttribute('aria-selected', String(selected));
    tab.tabIndex = selected ? 0 : -1;
    if (selected && focus) tab.focus();
  }
  for (const panel of panels) panel.hidden = panel.dataset.osPanel !== os;
  if (updateHash) history.replaceState(null, '', `#${os}`);
}
function osFromHash() {
  const hash = window.location.hash.slice(1);
  if (hash === 'windows' || hash === 'windows-open-app' || hash === 'codex-install-windows') return 'windows';
  return 'mac';
}
if (tablist && tabs.length === 2 && panels.length === 2) {
  tablist.setAttribute('role', 'tablist');
  for (const panel of panels) {
    panel.setAttribute('role', 'tabpanel');
    panel.setAttribute('aria-labelledby', `tab-${panel.dataset.osPanel}`);
    panel.tabIndex = 0;
  }
  for (const tab of tabs) {
    tab.setAttribute('role', 'tab');
    tab.addEventListener('click', () => selectOS(tab.dataset.os, { updateHash: true }));
    tab.addEventListener('keydown', (event) => {
      let target;
      if (event.key === 'ArrowRight' || event.key === 'ArrowLeft') target = tabs[(tabs.indexOf(tab) + 1) % tabs.length];
      else if (event.key === 'Home') target = tabs[0];
      else if (event.key === 'End') target = tabs[tabs.length - 1];
      if (!target) return;
      event.preventDefault();
      selectOS(target.dataset.os, { focus: true, updateHash: true });
    });
  }
  selectOS(osFromHash());
  window.addEventListener('hashchange', () => selectOS(osFromHash()));
}
for (const panel of panels) {
  const checks = [...panel.querySelectorAll('[data-install-check]')];
  const progress = panel.querySelector('[data-install-progress]');
  const update = () => { progress.textContent = `${checks.filter(check => check.checked).length} / ${checks.length} 完了`; };
  checks.forEach(check => check.addEventListener('change', update));
  update();
}
const printButton = document.querySelector('[data-print-guide]');
if (printButton) { printButton.hidden = false; printButton.addEventListener('click', () => window.print()); }
// Native collapsed details can omit their body in print; restore their state afterwards.
let printDetails = [];
window.addEventListener('beforeprint', () => {
  printDetails = [...document.querySelectorAll('details')].map(element => ({ element, open: element.open }));
  printDetails.forEach(({ element }) => { element.open = true; });
});
window.addEventListener('afterprint', () => { printDetails.forEach(({ element, open }) => { element.open = open; }); printDetails = []; });

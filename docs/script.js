function revealHashTarget() {
  let id;
  try { id = decodeURIComponent(window.location.hash.slice(1)); } catch { return; }
  const target = document.getElementById(id);
  if (target instanceof HTMLDetailsElement) target.open = true;
}
window.addEventListener('hashchange', revealHashTarget);
revealHashTarget();

document.querySelectorAll('.resource-prompt').forEach((block) => {
  const button = block.querySelector('button');
  const code = block.querySelector('pre code');
  const status = block.querySelector('[role="status"]');
  button?.addEventListener('click', async () => {
    button.disabled = true;
    try {
      await navigator.clipboard.writeText(code.textContent);
      status.textContent = 'コピーしました';
    } catch {
      status.textContent = 'コピーできませんでした。下の文章を選択してコピーしてください。';
      const selection = window.getSelection();
      const range = document.createRange();
      range.selectNodeContents(code);
      selection.removeAllRanges();
      selection.addRange(range);
    } finally { button.disabled = false; }
  });
});

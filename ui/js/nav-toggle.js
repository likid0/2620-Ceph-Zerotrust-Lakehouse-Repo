/* ui/js/nav-toggle.js ---------------------------------------------------- */
(() => {
  // Collapse / expand the LEFT component navigation
  const navBtn = document.getElementById('toggle-nav');
  if (navBtn) {
    navBtn.addEventListener('click', () => {
      document.body.classList.toggle('collapsed-nav');
    });
  }

  // Collapse / expand the RIGHT page‑local TOC (only if it exists)
  const pageToc = document.getElementById('page-toc');
  if (pageToc) {
    // floating button on the right
    const tocBtn = document.createElement('button');
    tocBtn.id = 'toggle-toc';
    tocBtn.className = 'toc-toggle';
    tocBtn.title = 'Toggle page contents';
    tocBtn.textContent = '☰';
    document.body.appendChild(tocBtn);

    tocBtn.addEventListener('click', () => {
      document.body.classList.toggle('collapsed-toc');
    });
  }
})();


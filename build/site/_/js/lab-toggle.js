
(()=>{

  /* LEFT component navigation ------------------------------------------ */
  const navBtn = document.getElementById('toggle-nav');
  if (navBtn) {
    navBtn.addEventListener('click', () =>
      document.body.classList.toggle('lab--nav-collapsed')
    );
  }

  /* RIGHT page‑local TOC ----------------------------------------------- */
  const rightToc = document.querySelector('aside.toc.sidebar');
  if (rightToc) {
    const btn = document.createElement('button');
    btn.id        = 'toggle-toc';
    btn.className = 'lab-toc-toggle';
    btn.title     = 'Toggle contents';
    btn.textContent = '☰';
    document.body.appendChild(btn);

    btn.addEventListener('click', () =>
      document.body.classList.toggle('lab--toc-collapsed')
    );
  }
})();


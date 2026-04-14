(function () {
  var modal = document.createElement('div');
  modal.className = 'img-modal';
  var modalImg = document.createElement('img');
  modal.appendChild(modalImg);
  document.body.appendChild(modal);

  function open(src, alt) {
    modalImg.src = src;
    modalImg.alt = alt || '';
    requestAnimationFrame(function () { modal.classList.add('open'); });
    document.body.style.overflow = 'hidden';
  }

  function close() {
    modal.classList.remove('open');
    document.body.style.overflow = '';
  }

  modal.addEventListener('click', close);

  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') close();
  });

  document.querySelectorAll('#page-content img').forEach(function (img) {
    img.addEventListener('click', function () {
      open(img.src, img.alt);
    });
  });
})();

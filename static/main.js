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

(function () {
  var form = document.querySelector('[data-newsletter-form]');
  var status = document.querySelector('[data-newsletter-status]');

  if (!form || !status) return;

  var emailInput = form.querySelector('input[name="email"]');
  var submitButton = form.querySelector('button[type="submit"]');

  function setStatus(message, state) {
    status.textContent = message;
    if (state) {
      status.dataset.state = state;
    } else {
      delete status.dataset.state;
    }
  }

  form.addEventListener('submit', async function (event) {
    event.preventDefault();

    var email = emailInput.value.trim();
    if (!email) {
      setStatus('Enter an email address first.', 'error');
      emailInput.focus();
      return;
    }

    submitButton.disabled = true;
    setStatus('Subscribing...', null);

    try {
      var res = await fetch('https://neusletter.yakko-majuri.workers.dev', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: email })
      });

      if (!res.ok) {
        throw new Error('Request failed');
      }

      form.reset();
      setStatus('You are subscribed. Check your inbox for confirmation.', 'success');
    } catch (error) {
      setStatus('Could not subscribe right now. Please try again in a moment.', 'error');
    } finally {
      submitButton.disabled = false;
    }
  });
})();

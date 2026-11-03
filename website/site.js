const stage = document.querySelector('.photo-stage');
if (stage) {
  const photos = [
    {name: '海边', style: 'sea', description: '松树下的海岸，AI 合成示例'},
    {name: '山野', style: 'mountain', description: '山间草地，AI 合成示例'},
    {name: '日常', style: 'coffee', description: '窗边桌上的水杯，AI 合成示例'}
  ];
  const history = [];
  const picture = document.querySelector('#current-photo');
  const print = document.querySelector('.print');
  const complete = document.querySelector('.complete');
  const feedback = document.querySelector('#feedback');
  const save = document.querySelector('#save');
  const skip = document.querySelector('#skip');
  const undo = document.querySelector('#undo');
  let current = 0;
  let saved = 0;

  function render() {
    const finished = current === photos.length;
    print.hidden = finished;
    document.querySelector('.back-print').hidden = finished;
    complete.hidden = !finished;
    save.disabled = finished;
    skip.disabled = finished;
    undo.disabled = history.length === 0;
    document.querySelector('#counter').textContent = finished ? '已完成' : (current + 1) + ' / 3';
    document.querySelector('#saved-count').textContent = saved + ' 张';
    for (const item of document.querySelectorAll('.mini')) {
      const index = Number(item.dataset.photo);
      item.classList.toggle('selected', index === current);
      item.classList.toggle('done', index < current);
    }
    if (!finished) {
      const photo = photos[current];
      picture.className = 'picture ' + photo.style;
      picture.setAttribute('aria-label', photo.description);
      document.querySelector('#photo-name').textContent = photo.name;
      document.querySelector('#photo-index').textContent = '0' + (current + 1);
    }
  }

  function advance(action) {
    if (current >= photos.length) return;
    const name = photos[current].name;
    history.push(action);
    if (action === 'save') saved += 1;
    current += 1;
    render();
    feedback.textContent = action === 'save' ? name + '已放入旅行相册' : '已跳过' + name;
    if (current === photos.length) document.querySelector('#restart').focus();
  }

  save.addEventListener('click', () => advance('save'));
  skip.addEventListener('click', () => advance('skip'));
  undo.addEventListener('click', () => {
    if (!history.length) return;
    if (history.pop() === 'save') saved -= 1;
    current -= 1;
    render();
    feedback.textContent = '已撤回上一步';
  });
  document.querySelector('#restart').addEventListener('click', () => {
    current = 0;
    saved = 0;
    history.length = 0;
    render();
    feedback.textContent = '仅在此网页演示';
    save.focus();
  });
  render();
}

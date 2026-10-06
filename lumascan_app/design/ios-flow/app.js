'use strict';
const navButtons = [...document.querySelectorAll('.nav-pill')];
const steps = [...document.querySelectorAll('.flow-step')];
const noteButton = document.querySelector('#toggle-notes');
const sheetTitle = document.querySelector('#sheet-title');
const sheetCopy = document.querySelector('#sheet-copy');
const sheetOptions = document.querySelector('#sheet-options');

navButtons.forEach(button => button.addEventListener('click', () => {
  navButtons.forEach(item => item.classList.toggle('active', item === button));
  steps.forEach(step => step.classList.toggle('hidden', button.dataset.filter !== 'all' && step.dataset.lane !== button.dataset.filter));
  document.querySelector('#flow').scrollIntoView({behavior:'smooth', block:'start'});
}));

noteButton.addEventListener('click', () => {
  const hidden = document.body.classList.toggle('hide-notes');
  noteButton.textContent = hidden ? 'Show annotations' : 'Hide annotations';
});

const sheets = {
  enhance: ['Enhance selected','Choose a filter and preview it before applying.',[['✦','Auto enhance','Balanced color and contrast'],['◐','Choose filter','Color, grayscale or B&W'],['⌁','Remove marks','Clean page background']]],
  rotate: ['Rotate selected','Apply one rotation to all selected pages.',[['↺','Rotate left','Quarter turn counter-clockwise'],['↻','Rotate right','Quarter turn clockwise'],['⌗','Review crop','Check each page boundary']]],
  organize: ['Organize selected','Change order or duplicate pages safely.',[['↕','Move pages','Choose a destination'],['▣','Duplicate','Create editable copies'],['⌫','Delete','Confirmation and undo']]],
  more: ['More actions','Additional tools for the current selection.',[['T','Extract text','Run OCR on selected pages'],['□','Export selected','Create a new document'],['•••','Page details','Size and processing history']]]
};

document.querySelectorAll('[data-sheet]').forEach(button => button.addEventListener('click', () => {
  const [title, copy, options] = sheets[button.dataset.sheet];
  sheetTitle.textContent = title;
  sheetCopy.textContent = copy;
  sheetOptions.innerHTML = options.map(([icon,name,detail]) => `<button><i>${icon}</i><span><b>${name}</b><small>${detail}</small></span><em>›</em></button>`).join('');
  sheetTitle.closest('.flow-step').scrollIntoView({behavior:'smooth', block:'center', inline:'center'});
}));

const cameraPreview = document.querySelector('#camera-preview');
const cameraSettings = document.querySelector('#camera-settings');
const cameraStates = {batch:true, flash:false, auto:true, grid:false};

function renderCameraState(name, enabled) {
  cameraStates[name] = enabled;
  const quickControl = document.querySelector(`[data-camera-toggle="${name}"]`);
  const settingsControl = document.querySelector(`[data-camera-check="${name}"]`);
  if (quickControl) {
    quickControl.classList.toggle('active', enabled);
    quickControl.setAttribute('aria-pressed', String(enabled));
    quickControl.querySelector('b').textContent = enabled ? 'On' : 'Off';
  }
  if (settingsControl) settingsControl.checked = enabled;
  cameraPreview.classList.toggle(`${name}-on`, enabled);
  if (name === 'batch') document.querySelector('.capture-count').hidden = !enabled;
  if (name === 'auto') document.querySelector('.camera-guidance').textContent = enabled ? 'Hold steady' : 'Tap shutter to capture';
}

function setCameraSettings(open) {
  cameraSettings.classList.toggle('open', open);
  cameraSettings.setAttribute('aria-hidden', String(!open));
}

document.querySelectorAll('[data-camera-toggle]').forEach(button => button.addEventListener('click', () => {
  const name = button.dataset.cameraToggle;
  renderCameraState(name, !cameraStates[name]);
}));
document.querySelectorAll('[data-camera-check]').forEach(control => control.addEventListener('change', () => renderCameraState(control.dataset.cameraCheck, control.checked)));
document.querySelectorAll('[data-capture-mode]').forEach(button => button.addEventListener('click', () => {
  document.querySelectorAll('[data-capture-mode]').forEach(item => item.classList.toggle('active', item === button));
  const mode = button.dataset.captureMode;
  const overlay = document.querySelector('#capture-mode-overlay');
  overlay.className = `capture-mode-overlay ${mode === 'Book' ? 'book' : mode === 'Text' ? 'text' : mode === 'OCR Doc' ? 'ocr' : mode === 'QR' ? 'qr' : ''}`;
  document.querySelector('.camera-guidance').textContent = ({Book:'Align the book spine',Text:'Point at text to recognize','OCR Doc':'Fill the frame with the page',QR:'Place QR code in the frame',Photo:'Compose your photo'})[mode] || 'Hold steady';
}));
document.querySelector('#camera-settings-button').addEventListener('click', () => setCameraSettings(true));
document.querySelector('#close-camera-settings').addEventListener('click', () => setCameraSettings(false));
document.querySelector('#settings-scrim').addEventListener('click', () => setCameraSettings(false));
const discardDialog = document.querySelector('#discard-dialog');
const capturedPhotosDialog = document.querySelector('#captured-photos-dialog');
function setDiscardDialog(open) {
  discardDialog.classList.toggle('open', open);
  discardDialog.setAttribute('aria-hidden', String(!open));
}
document.querySelector('#discard-capture').addEventListener('click', () => setDiscardDialog(true));
function setCapturedPhotos(open) {
  capturedPhotosDialog.classList.toggle('open', open);
  capturedPhotosDialog.setAttribute('aria-hidden', String(!open));
}
document.querySelector('#open-captured-photos').addEventListener('click', () => setCapturedPhotos(true));
document.querySelector('#close-captured-photos').addEventListener('click', () => setCapturedPhotos(false));
document.querySelector('#captured-photos-scrim').addEventListener('click', () => setCapturedPhotos(false));
document.querySelector('#continue-scanning').addEventListener('click', () => setCapturedPhotos(false));
document.querySelector('#cancel-discard').addEventListener('click', () => setDiscardDialog(false));
document.querySelector('#discard-scrim').addEventListener('click', () => setDiscardDialog(false));
document.querySelector('#confirm-discard').addEventListener('click', () => {
  setDiscardDialog(false);
  document.querySelector('.capture-count').hidden = true;
  document.querySelector('.thumb-button i').textContent = '0';
  document.querySelector('.thumb-button').setAttribute('aria-label', 'No scanned pages');
  document.querySelector('#library-flow').scrollIntoView({behavior:'smooth', block:'center'});
});
document.addEventListener('keydown', event => { if (event.key === 'Escape') { setCameraSettings(false); setCapturedPhotos(false); setDiscardDialog(false); } });

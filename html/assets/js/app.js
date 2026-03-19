/* ===== Dei Multichar - App.js ===== */

const IS_BROWSER = !window.invokeNative;

// ===== State =====
let characters = [];
let maxSlots = 5;
let selectedSlot = null;
let enableLastPlayed = true;
let deleteTargetSlot = null;

// ===== DOM =====
const container = document.getElementById('multichar-container');
const slotsList = document.getElementById('slots-list');
const infoPanel = document.getElementById('info-panel');
const infoEmpty = document.getElementById('info-empty');
const infoContent = document.getElementById('info-content');
const formPanel = document.getElementById('form-panel');
const confirmOverlay = document.getElementById('confirm-overlay');

// ===== NUI Message Handler =====
window.addEventListener('message', (event) => {
    const data = event.data;

    switch (data.action) {
        case 'showMultichar':
            characters = data.characters || [];
            maxSlots = data.maxSlots || 5;
            enableLastPlayed = data.enableLastPlayed !== false;
            if (data.theme) setTheme(data.theme);
            if (data.lightMode !== undefined) setLightMode(data.lightMode);
            showUI();
            break;

        case 'hideMultichar':
            hideUI();
            break;

        case 'updateTheme':
            if (data.theme) setTheme(data.theme);
            if (data.lightMode !== undefined) setLightMode(data.lightMode);
            break;

        case 'selectCharacter':
            if (data.slot !== undefined) selectSlot(data.slot);
            break;

        case 'createCharacter':
            showCreateForm();
            break;
    }
});

// ===== Theme =====
function setTheme(theme) {
    document.body.setAttribute('data-theme', theme);
}

function setLightMode(enabled) {
    document.body.classList.toggle('light-mode', enabled);
}

// ===== Show / Hide =====
function showUI() {
    selectedSlot = null;
    container.classList.add('active');
    hideCreateForm();
    hideConfirm();
    renderSlots();
    showInfoEmpty();
}

function hideUI() {
    container.classList.remove('active');
    selectedSlot = null;
}

// ===== Render Slots =====
function renderSlots() {
    slotsList.innerHTML = '';

    // Map characters by slot
    const charMap = {};
    characters.forEach(c => {
        charMap[c.slot] = c;
    });

    for (let i = 1; i <= maxSlots; i++) {
        const char = charMap[i];
        const card = document.createElement('div');
        card.className = 'slot-card' + (char ? '' : ' empty');
        card.dataset.slot = i;

        if (char) {
            const genderIcon = char.gender === 'female' ? '&#9792;' : '&#9794;';
            const cashFormatted = formatCash(char.cash || 0);
            const dateText = enableLastPlayed && char.lastPlayed ? getRelativeDate(char.lastPlayed) : '';

            card.innerHTML = `
                <div class="slot-header">
                    <span class="char-name">${escapeHtml(char.firstname)} ${escapeHtml(char.lastname)}</span>
                    <span class="gender-icon">${genderIcon}</span>
                </div>
                <div class="slot-details">
                    <span class="char-job">${escapeHtml(char.job || 'Desempleado')}</span>
                    <div class="char-meta">
                        <span class="char-cash">$${cashFormatted}</span>
                        ${dateText ? `<span class="char-date">${dateText}</span>` : ''}
                    </div>
                </div>
            `;

            card.addEventListener('click', () => {
                selectSlot(i);
                // Tell Lua to preview this character's ped
                fetch(`https://dei_multichar/selectChar`, {
                    method: 'POST',
                    body: JSON.stringify({ slot: i })
                });
            });
        } else {
            card.innerHTML = `
                <span class="empty-icon">+</span>
                <span class="empty-text">Crear Personaje</span>
            `;

            card.addEventListener('click', () => {
                // Trigger character creation via Lua (esx_identity handles the form)
                fetch('https://dei_multichar/createChar', {
                    method: 'POST',
                    body: JSON.stringify({})
                });
            });
        }

        slotsList.appendChild(card);
    }
}

// ===== Select Slot =====
function selectSlot(slot) {
    selectedSlot = slot;

    // Update slot visual
    document.querySelectorAll('.slot-card').forEach(card => {
        card.classList.toggle('selected', parseInt(card.dataset.slot) === slot);
    });

    // Find character
    const char = characters.find(c => c.slot === slot);
    if (!char) {
        showInfoEmpty();
        return;
    }

    // Show info
    showInfoContent(char);
}

// ===== Info Panel =====
function showInfoEmpty() {
    infoEmpty.style.display = 'flex';
    infoContent.classList.remove('active');
}

function showInfoContent(char) {
    infoEmpty.style.display = 'none';
    infoContent.classList.add('active');

    document.getElementById('info-name').textContent = `${char.firstname} ${char.lastname}`;
    document.getElementById('info-subtitle').textContent = char.gender === 'female' ? 'Femenino' : 'Masculino';
    document.getElementById('info-job').textContent = char.job || 'Desempleado';
    document.getElementById('info-cash').textContent = '$' + formatCash(char.cash || 0);
    document.getElementById('info-dob').textContent = char.dob || '-';
    document.getElementById('info-gender').textContent = char.gender === 'female' ? 'Femenino' : 'Masculino';
    document.getElementById('info-nationality').textContent = char.nationality || 'Desconocida';

    const lastPlayedGroup = document.getElementById('info-lastplayed-group');
    if (enableLastPlayed && char.lastPlayed) {
        lastPlayedGroup.style.display = 'flex';
        document.getElementById('info-lastplayed').textContent = getRelativeDate(char.lastPlayed);
    } else {
        lastPlayedGroup.style.display = 'none';
    }

    // Re-animate
    const panel = document.querySelector('.info-panel');
    panel.style.animation = 'none';
    panel.offsetHeight; // trigger reflow
    panel.style.animation = 'fadeInUp 0.4s ease';
}

// ===== Play Button =====
document.getElementById('btn-play').addEventListener('click', () => {
    if (selectedSlot === null) return;
    fetch(`https://dei_multichar/playChar`, {
        method: 'POST',
        body: JSON.stringify({ slot: selectedSlot })
    });
});

// ===== Delete Button =====
document.getElementById('btn-delete').addEventListener('click', () => {
    if (selectedSlot === null) return;
    const char = characters.find(c => c.slot === selectedSlot);
    if (!char) return;

    deleteTargetSlot = selectedSlot;
    document.getElementById('confirm-text').textContent =
        `Seguro que quieres eliminar a ${char.firstname} ${char.lastname}? Esta accion es irreversible.`;
    confirmOverlay.classList.add('active');
});

// ===== Confirm Delete =====
document.getElementById('btn-confirm-delete').addEventListener('click', () => {
    if (deleteTargetSlot === null) return;

    fetch(`https://dei_multichar/deleteChar`, {
        method: 'POST',
        body: JSON.stringify({ slot: deleteTargetSlot })
    });

    hideConfirm();
    selectedSlot = null;
    showInfoEmpty();
});

document.getElementById('btn-confirm-cancel').addEventListener('click', () => {
    hideConfirm();
});

function hideConfirm() {
    confirmOverlay.classList.remove('active');
    deleteTargetSlot = null;
}

// ===== Create Form =====
function showCreateForm() {
    formPanel.classList.add('active');
    infoPanel.classList.add('hidden');
    clearForm();
}

function hideCreateForm() {
    formPanel.classList.remove('active');
    infoPanel.classList.remove('hidden');
}

function clearForm() {
    document.getElementById('form-firstname').value = '';
    document.getElementById('form-lastname').value = '';
    document.getElementById('form-dob').value = '';
    document.getElementById('form-gender').value = 'male';
    document.getElementById('form-nationality').value = '';
    document.querySelectorAll('.form-input.error').forEach(el => el.classList.remove('error'));
}

document.getElementById('btn-form-create').addEventListener('click', () => {
    const firstname = document.getElementById('form-firstname').value.trim();
    const lastname = document.getElementById('form-lastname').value.trim();
    const dob = document.getElementById('form-dob').value;
    const gender = document.getElementById('form-gender').value;
    const nationality = document.getElementById('form-nationality').value.trim();

    // Validate
    let valid = true;
    document.querySelectorAll('.form-input.error').forEach(el => el.classList.remove('error'));

    if (!firstname) {
        document.getElementById('form-firstname').classList.add('error');
        valid = false;
    }
    if (!lastname) {
        document.getElementById('form-lastname').classList.add('error');
        valid = false;
    }
    if (!dob) {
        document.getElementById('form-dob').classList.add('error');
        valid = false;
    }

    if (!valid) return;

    fetch(`https://dei_multichar/createChar`, {
        method: 'POST',
        body: JSON.stringify({
            firstname,
            lastname,
            dob,
            gender,
            nationality: nationality || undefined
        })
    });

    hideCreateForm();
});

document.getElementById('btn-form-cancel').addEventListener('click', () => {
    hideCreateForm();
});

// ===== Utilities =====
function formatCash(amount) {
    return amount.toLocaleString('es-ES');
}

function escapeHtml(str) {
    const div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
}

function getRelativeDate(dateStr) {
    if (!dateStr) return '';
    const now = new Date();
    const date = new Date(dateStr);
    const diffMs = now - date;
    const diffMins = Math.floor(diffMs / 60000);
    const diffHours = Math.floor(diffMins / 60);
    const diffDays = Math.floor(diffHours / 24);

    if (diffMins < 1) return 'Ahora';
    if (diffMins < 60) return `hace ${diffMins} min`;
    if (diffHours < 24) return `hace ${diffHours}h`;
    if (diffDays === 1) return 'hace 1 dia';
    if (diffDays < 30) return `hace ${diffDays} dias`;
    if (diffDays < 365) return `hace ${Math.floor(diffDays / 30)} meses`;
    return `hace ${Math.floor(diffDays / 365)} anos`;
}

// ===== Keyboard =====
document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
        if (confirmOverlay.classList.contains('active')) {
            hideConfirm();
        } else if (formPanel.classList.contains('active')) {
            hideCreateForm();
        }
        // Don't close multichar on ESC - player must select a character
    }
});

// ===== Signal NUI Ready to Lua =====
if (!IS_BROWSER) {
    fetch(`https://dei_multichar/nuiReady`, {
        method: 'POST',
        body: JSON.stringify({})
    });
}

// ===== Browser Preview Mode =====
if (IS_BROWSER) {
    document.body.style.background = 'linear-gradient(135deg, #0a0a1a 0%, #1a1a3e 50%, #0a0a1a 100%)';

    const mockCharacters = [
        {
            slot: 1,
            firstname: 'Carlos',
            lastname: 'Rodriguez',
            job: 'Policia',
            cash: 45230,
            dob: '1995-03-15',
            gender: 'male',
            nationality: 'Mexicano',
            lastPlayed: new Date(Date.now() - 7200000).toISOString()
        },
        {
            slot: 2,
            firstname: 'Maria',
            lastname: 'Lopez',
            job: 'Mecanico',
            cash: 12800,
            dob: '1998-07-22',
            gender: 'female',
            nationality: 'Argentina',
            lastPlayed: new Date(Date.now() - 172800000).toISOString()
        },
        // Slot 3 empty
        {
            slot: 4,
            firstname: 'Diego',
            lastname: 'Fernandez',
            job: 'Desempleado',
            cash: 500,
            dob: '2000-11-01',
            gender: 'male',
            nationality: 'Chileno',
            lastPlayed: new Date(Date.now() - 604800000).toISOString()
        }
    ];

    // Simulate showMultichar
    window.postMessage({
        action: 'showMultichar',
        characters: mockCharacters,
        maxSlots: 5,
        theme: 'dark',
        lightMode: false,
        enableLastPlayed: true
    }, '*');

    // Override fetch for browser mode
    window.fetch = function (url, options) {
        return Promise.resolve({ json: () => Promise.resolve({}) });
    };
}

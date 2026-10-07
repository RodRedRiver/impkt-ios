/* HTML mirrors of the four SwiftUI tabs, for tools/preview.py. The strings are copied from the Swift views
   (LeaderboardView, UpdateView, DevicesView, ProfileView); the people and numbers are made up, there to
   show a state. Each tab lists the app states worth looking at, and the preview offers them as buttons. */
window.FW_VERSION = window.FW_VERSION || '2.23';

const sec = (head, rows, foot) => (head ? `<div class="sh">${head}</div>` : '<div style="height:26px"></div>') + (rows ? `<div class="grp">${rows}</div>` : '') + (foot ? `<div class="sf">${foot}</div>` : '');
const row = (k, v) => `<div class="r"><span class="f13">${k}</span><span class="f13" style="color:var(--sec);text-align:right">${v}</span></div>`;
const text = (t, cls = 'foot') => `<div class="r col"><div class="${cls}">${t}</div></div>`;
const page = (title, body, trailing = '') => `<div class="nav">${trailing}</div><div class="scroll"><div class="ltitle">${title}</div>${body}</div>`;
const card = inner => `<div class="card">${inner}</div>`;

/* ───────── Leaderboard ───────── */
const fig = (n, speed, mode) => `<div class="fig ${mode}"><b>${n}</b><span>power</span></div>` + (speed ? `<div class="cap" style="margin-top:2px">${speed} m/s at the hand</div>` : '');
const entry = (label, chips) => `<div class="entry"><div class="in">Name</div><span class="go">${label}</span></div>` + (chips ? `<div class="chips">${chips.map(c => `<span>${c}</span>`).join('')}</div>` : '');
const medal = n => `<div class="m ${n <= 3 ? 'p' + n : ''}">${n}</div>`;
const standing = (n, name, note, best) => `<div class="row">${medal(n)}<div class="nm"><div style="${n === 1 ? 'font-weight:600' : ''}">${name}</div><div class="cap2">${note}</div></div><div class="pw ${n === 1 ? 'red' : ''}">${best}</div></div>`;
const standings = `<div class="card" style="padding:18px"><div style="display:flex;justify-content:space-between;align-items:baseline;padding-bottom:4px;text-align:left"><b style="font-size:15px;font-weight:600">Standings</b><span class="cap">4 boxers</span></div><div class="stand">`
  + standing(1, 'Jordan', '5 punches  ·  right +12%  ·  9.1 m/s', 78) + standing(2, 'Riley', '3 punches  ·  left +4%  ·  8.4 m/s', 71)
  + standing(3, 'Sam', '4 punches  ·  8.0 m/s', 66) + standing(4, 'Alex', '1 punch  ·  6.2 m/s', 52) + `</div></div>`;
const lbFoot = '';
const banner = card(`<div style="text-align:left" class="stack"><div class="f13" style="font-weight:500">&#9678;&nbsp; No band connected</div>
  <div class="link" style="font-weight:500">Connect a band</div></div>`);
const idleEmpty = card(`<div class="stack"><div class="t" style="font-weight:600">Nobody has hit it yet</div>${entry('Put them up')}</div>`);
const live = card(`<div class="hd"><b>&#129354; Jordan</b><span class="cap">3 thrown</span></div><div class="stack">${fig(74, '9.4', 'hot')}
  <div><div class="f13" style="font-weight:500;font-size:15px">Best of this turn, 74</div><div style="margin-top:8px" class="bar"><i style="width:94%"></i></div><div class="cap" style="margin-top:5px">4 off Jordan</div>
  <div class="hands" style="margin-top:6px"><div class="tr"><i class="s" style="width:56%"></i><i style="flex:1"></i></div><div class="lb"><span>Left 61</span><span class="red" style="font-weight:600">Left 21% harder</span><span>Right 74</span></div></div></div>
  <button class="btn">Done, put 74 on the board</button></div>`);
const who = card(`<div class="stack"><div class="t" style="font-weight:600">Who threw that?</div>${fig(63, '8.1', 'hot')}
  <div class="cap">Tap a name and it counts for them, and they stay up for the rest of their turn.</div>${entry('Count it', ['Jordan', 'Riley', 'Sam', 'Alex'])}<div class="cap">Nobody, drop it</div></div>`);
const idleBoard = card(`<div class="stack"><div class="cap" style="font-weight:500;text-transform:uppercase">Hardest so far</div>${fig(78, '9.1', 'hot')}
  <div class="f13 red" style="font-size:15px;font-weight:600">&#9818; Jordan</div>${entry('Put them up', ['Jordan', 'Riley', 'Sam', 'Alex'])}</div>`);

/* ───────── Update ───────── */
const wrapRow = (name, sub, btn) => `<div class="r"><div><div class="t">${name}</div><div class="cap">${sub}</div></div><span class="f13 red">${btn}</span></div>`;
const wraps = sec('Wraps nearby', wrapRow('Impktband 1', 'signal -58 dBm', 'Update') + wrapRow('Impktband 2', 'signal -71 dBm', 'Update'));
const updateTail = '';
const upHead = () => `Firmware in this app: ${window.FW_VERSION}`;

/* ───────── Devices ───────── */
const hand = (side, line, btn) => `<div class="r"><div><div class="f13">${side}</div><div class="cap">${line}</div></div><span class="link">${btn}</span></div>`;

/* ───────── Profile ───────── */
const slider = (k, v, min, max, val) => `<div class="r col" style="gap:4px"><div style="display:flex;justify-content:space-between" class="f13"><span>${k}</span><span style="color:var(--sec)">${v}</span></div><input type="range" min="${min}" max="${max}" value="${val}" style="--slider-fill:calc(12px + (100% - 24px) * ${(val - min) / (max - min)})"></div>`;
const pickRow = (k, v) => `<div class="r"><span class="t" style="font-size:17px">${k}</span><span class="pick">${v}</span></div>`;

window.TABS = [
  null,
  { name: 'Leaderboard', trailing: '&#8943;', states: {
      'Empty, no band': () => page('Leaderboard', banner + idleEmpty + lbFoot, '&#9711;'),
      'Someone is up': () => page('Leaderboard', live + standings + lbFoot, '&#9711;'),
      'Who threw that': () => page('Leaderboard', who + standings + lbFoot, '&#9711;'),
      'Standings': () => page('Leaderboard', idleBoard + standings + lbFoot, '&#9711;') } },
  { name: 'Devices', states: {
      'Wraps found': () => page('Devices',
        sec('Listening', '')
        + sec('Your wraps', hand('Left hand', 'Connected, battery 82%, signal good', 'Disconnect') + `<div class="r"><span class="link">Update to ${window.FW_VERSION}</span></div>` + hand('Right hand', 'Not connected', 'Connect')
          + `<div class="r"><span class="link">Look for my wraps</span></div>`)
        + sec('Nearby', `<div class="r"><div><div class="t">Impktband 1</div><div class="cap">Connected to this phone</div></div><span class="foot">Strong &nbsp; <span class="link">Update</span></span></div><div class="r"><div><div class="t">Impktband 2</div><div class="cap">signal -71 dBm</div></div><span class="foot">Fair &nbsp; <span class="link">Update</span></span></div>`)
        + sec('Remembered', '')),
      'Updating': () => page('Devices',
        sec('Update', `<div class="r col" style="gap:8px"><div class="bar"><i style="width:42%"></i></div><div class="foot">Sending the firmware, 42%</div><div class="cap">Do not close the app or walk away with the phone.</div><div class="f13 red">Stop</div></div>`)
        + sec('Listening', '')
        + sec('Your wraps', hand('Left hand', 'Connected, battery 82%, signal good', 'Disconnect') + hand('Right hand', 'Not connected', 'Connect'))
        + sec('Nearby', `<div class="r"><div><div class="t">Impktband 1</div><div class="cap">Connected to this phone</div></div><span class="foot">Strong &nbsp; <span class="cap">&#9696;</span></span></div>`)),
      'Before the code': () => page('Devices',
        sec('Listening', '')
        + sec('Your wraps', text('Enter your code on the Test tab first. Until the page is past its front door there is no pilot for a wrap to be recording for, and connecting one would record into nothing.'))
        + sec('Nearby', text('Nothing yet. Shake a wrap to wake it.')) + sec('Remembered', text('Nothing yet. A wrap is remembered the first time it is connected, here or on the Test tab, and stays remembered so it never has to be picked twice.'))) } },
  { name: 'Profile', states: {
      'Filled in': () => page('Profile',
        sec('You', row('Name', 'Alex Sample') + row('Gym', 'Sample Boxing Club') + row('Your pair', 'IMPKT-0000'))
        + sec('Your code', `<div class="r"><span class="f13">Code</span><span class="mono f13" style="color:var(--sec)">ABCDE-FGHJK</span></div>` + text('It is the only way back into the page and we cannot recover it. Keep a copy somewhere that is not this phone.', 'cap'))
        + sec('Your profile', `<div class="r col"><div class="seg"><span class="on">Metric</span><span>Pounds and feet</span></div></div>` + slider('Weight', '78 kg', 35, 160, 78) + slider('Height', '178 cm', 140, 215, 178)
          + `<div class="r"><span class="f13">Work reach out from my height</span><div class="sw"></div></div>` + row('Reach', '178 cm, from your height')
          + pickRow('Stance', 'Orthodox') + pickRow('Gloves', '16 oz') + pickRow('Level', 'Training')
          + text('Changing any of it here changes it on the Test tab, because there is one profile and the page holds it. None of it is asked for its own sake, and what each answer is for is written on the setup screen.', 'cap'))
        + sec('This build', row('App', '0.1') + row('Firmware in this app', window.FW_VERSION))
        + sec('', `<div class="r"><span class="f13">Privacy policy</span><span class="ch">&#8250;</span></div>`)
        + sec('', `<div class="r"><span class="f13" style="color:#ff3b30">Clear my profile and code</span></div>` + text('This is what the page means by clearing the stored data. It empties this phone, not our copy of anything already sent.', 'cap'))),
      'Before the code': () => page('Profile',
        sec('', text('Nothing yet. Enter your code on the Test tab and this fills itself in: the profile is stored by the page, and the page has not been past its front door on this phone.'))
        + sec('This build', row('App', '0.1') + row('Firmware in this app', window.FW_VERSION))
        + sec('', `<div class="r"><span class="f13">Privacy policy</span><span class="ch">&#8250;</span></div>`)) } },
];

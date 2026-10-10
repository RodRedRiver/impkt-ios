#!/usr/bin/env node
/* Does pressing Connect on a hand find a wrap that has been renamed?
     node tools/test-page-hands.js

   Runs the page's own hand-matching code, lifted out of IMPKT/Resources/Web/index.html, so a
   change to it that brings the bug back fails here rather than on somebody's phone. The bug: a wrap
   named "left 1" that says it is a RIGHT hand wrap, with a stale "left" in the phone's memory, was
   refused by Connect on the right hand and the page said nothing was found. */
const fs = require('fs'), path = require('path');
const src = fs.readFileSync(path.join(__dirname, '..', 'IMPKT/Resources/Web/index.html'), 'utf8');

function lift(startMarker, endMarker) {
  const a = src.indexOf(startMarker);
  const b = src.indexOf(endMarker, a);
  if (a < 0 || b < 0) { console.error('FAIL: cannot find ' + startMarker); process.exit(1); }
  return src.slice(a, b);
}
const hands = lift('const handNamed = d =>', 'const otherHand');
const pickSrc = lift('const pick = list =>', '/* Whatever the search has already turned up');

let fails = 0;
const expect = (ok, what) => { console.log((ok ? '  PASS  ' : '  FAIL  ') + what); if (!ok) fails++; };

function run(memo, used) {
  const code = `const side = 'right'; const handMemo = ${JSON.stringify(memo)}; const inUse = d => ${JSON.stringify(used || [])}.includes(d.id);
    ${hands} ${pickSrc} return { handOf, handNamed, pick, pickFrom };`;
  return new Function(code)();
}

const wrap = (id, name) => ({ id, name });

console.log('naming');
let k = run({});
expect(k.handNamed(wrap('a', 'BOXING-01R')) === 'right', 'BOXING-01R states the right hand');
expect(k.handNamed(wrap('a', 'right test')) === '', 'a renamed wrap ("right test") states no hand in its name');
expect(k.handNamed(wrap('a', 'left 1')) === '', 'a renamed wrap ("left 1") states no hand in its name');

console.log('Connect on the right hand');
const w = wrap('wrap-1', 'left 1');
k = run({ 'wrap-1': 'left' });                       // stale: the wrap itself says right
expect(k.pick([w]) === w, 'a renamed wrap with a stale "left" memory is still tried for the right hand');
k = run({ 'wrap-1': 'right' });
expect(k.pick([w]) === w, 'a renamed wrap remembered as right is picked');
k = run({});
expect(k.pick([w]) === w, 'a renamed wrap with no memory is picked');

console.log('a wrap that really is on the other hand by name is never taken');
const left = wrap('wrap-2', 'BOXING-01L');
k = run({});
expect(k.pick([left]) === undefined, 'BOXING-01L is not offered to the right hand');

console.log('the right wrap wins when there is a choice');
const right = wrap('wrap-3', 'BOXING-01R');
k = run({ 'wrap-1': 'left' });
expect(k.pick([w, right]) === right, 'a wrap that states right beats a stale memory');
k = run({ 'wrap-1': 'right' });
expect(k.pick([left, w]) === w, 'a remembered-right wrap beats a stale-left one');
expect(run({}, ['wrap-1']).pick([w]) === undefined, 'a wrap already connected is not picked again');

console.log('a wrap the phone can hear beats one it only remembers (the log from build 47)');
const ghost = { id: 'aa8dd53c', name: 'Impkt 1', present: false };
const real = { id: 'efe9e904', name: 'right test', present: true };
k = run({ aa8dd53c: 'right' });
expect(k.pickFrom([ghost, real]) === real, 'the advertising wrap is picked over a remembered one the memory says is right');
k = run({ aa8dd53c: 'right', efe9e904: 'left' });
expect(k.pickFrom([ghost, real]) === real, 'even when the memory of the real wrap is a stale left');
k = run({ aa8dd53c: 'right' });
expect(k.pickFrom([ghost]) === ghost, 'with nothing on the air, a remembered wrap is still tried');
const browser = [{ id: 'x', name: 'BOXING-01R' }];
expect(run({}).pickFrom(browser) === browser[0], 'in a browser, where nothing says present, the pick is unchanged');

console.log(fails ? '\n' + fails + ' FAILED' : '\nALL PASSED');
process.exit(fails ? 1 : 0);

// Local data-only compatibility overlay. Does not execute any resource scripts.
const fs = require('fs');
const path = require('path');
const root = path.dirname(__dirname);
const dir = path.join(root, 'server', 'resources', 'TextMap');
const first = JSON.parse(fs.readFileSync(path.join(dir, 'TextMapTH_1.json'), 'utf8'));
const second = JSON.parse(fs.readFileSync(path.join(dir, 'TextMapTH_2.json'), 'utf8'));
let conflicts = 0;
for (const key of Object.keys(second)) {
  if (Object.hasOwn(first, key) && first[key] !== second[key]) conflicts++;
}
// Stop rather than silently choose between contradictory translations.
if (conflicts) throw new Error(`Thai text map has ${conflicts} conflicting keys; review before merging.`);
const merged = {...first, ...second};
const text = JSON.stringify(merged, null, 2) + '\n';
const overlay = path.join(root, 'server', 'resource-overrides', 'TextMap');
fs.mkdirSync(overlay, {recursive:true});
fs.writeFileSync(path.join(overlay, 'TextMapTH.json'), text, 'utf8');
fs.writeFileSync(path.join(dir, 'TextMapTH.json'), text, 'utf8');
const result = {first:Object.keys(first).length,second:Object.keys(second).length,merged:Object.keys(merged).length,conflicts};
fs.writeFileSync(path.join(root, 'audit', 'textmap-merge.json'), JSON.stringify(result, null, 2));
console.log(JSON.stringify(result));

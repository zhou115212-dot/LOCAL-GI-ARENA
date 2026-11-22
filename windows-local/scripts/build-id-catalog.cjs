// Read JSON data only. Name translations do not replace any server/client resources.
const fs=require('fs'),path=require('path');
const root=path.dirname(__dirname);
const source=path.join(root,'name-data/src/data/ChineseSimplified');
function loadNames(kind){const out=new Map();for(const file of fs.readdirSync(path.join(source,kind))){if(!file.endsWith('.json'))continue;const row=JSON.parse(fs.readFileSync(path.join(source,kind,file),'utf8'));if(Number.isInteger(row.id)&&row.name)out.set(row.id,row);}return out;}
const characters=loadNames('characters'),weapons=loadNames('weapons');
const resource=path.join(root,'server/resources/ExcelBinOutput');
const illegal=new Set();const constants=fs.readFileSync(path.join(root,'source/src/main/java/emu/grasscutter/GameConstants.java'),'utf8');
const ranges=constants.match(/ILLEGAL_WEAPONS\s*=\s*new SparseSet\("""([\s\S]*?)"""\)/)[1];
for(const token of ranges.trim().split(/[\s,]+/)){if(!token)continue;const [a,z]=token.split('-').map(Number);for(let id=a;id<=(z??a);id++)illegal.add(id);}
// Explicit, reviewed local exceptions; never unhide all internal/unfinished weapons.
const overridePath=path.join(root,'catalog/overrides.json');
const overrides=fs.existsSync(overridePath)?JSON.parse(fs.readFileSync(overridePath,'utf8')):{allowNamedWeaponIds:[]};
const allowed=new Set(overrides.allowNamedWeaponIds||[]);
const weaponRows=JSON.parse(fs.readFileSync(path.join(resource,'WeaponExcelConfigData.json'),'utf8'));
const affixRows=JSON.parse(fs.readFileSync(path.join(resource,'EquipAffixExcelConfigData.json'),'utf8'));
const promoteRows=JSON.parse(fs.readFileSync(path.join(resource,'WeaponPromoteExcelConfigData.json'),'utf8'));
for(const id of allowed){
 const row=weaponRows.find(x=>x.id===id);
 if(!Number.isInteger(id)||!weapons.has(id)||!row||row.itemType!=='ITEM_WEAPON'||row.rankLevel<3)throw Error(`Unverified catalog exception: ${id}`);
 if(!promoteRows.some(x=>x.weaponPromoteId===row.weaponPromoteId&&x.unlockMaxLevel===90))throw Error(`Missing promotion resources: ${id}`);
 const affixes=(row.skillAffix||[]).filter(x=>x>0);
 if(!affixes.length||affixes.some(a=>[0,1,2,3,4].some(r=>!affixRows.some(x=>x.affixId===a*10+r))))throw Error(`Missing refinement resources: ${id}`);
}
const types={WEAPON_SWORD_ONE_HAND:'单手剑',WEAPON_CLAYMORE:'双手剑',WEAPON_POLE:'长柄武器',WEAPON_CATALYST:'法器',WEAPON_BOW:'弓'};
const entries=[];
for(const row of JSON.parse(fs.readFileSync(path.join(resource,'AvatarExcelConfigData.json'),'utf8'))){
 if(row.id<10000002||row.id>=10000901||row.useType==='AVATAR_TEST')continue;
 const found=characters.get(row.id);let name=found?.name||row.iconName?.replace('UI_AvatarIcon_','')||String(row.id);
 if(row.id===10000005)name='旅行者（男）';if(row.id===10000007)name='旅行者（女）';
 entries.push({kind:'角色',id:row.id,name,type:types[row.weaponType]||row.weaponType||'',stars:found?.rarity||0,named:!!found,internal:row.iconName||'',command:`/give ${row.id} lv90 c0 sl9`});
}
for(const row of weaponRows){
 if(row.id<11100||row.id>16000||row.itemType!=='ITEM_WEAPON'||(illegal.has(row.id)&&!allowed.has(row.id)))continue;
 const found=weapons.get(row.id);entries.push({kind:'武器',id:row.id,name:found?.name||row.icon?.replace('UI_EquipIcon_','')||String(row.id),type:types[row.weaponType]||row.weaponType||'',stars:row.rankLevel||0,named:!!found,internal:row.icon||'',command:`/give ${row.id} lv90 r1 x1`});
}
entries.sort((a,b)=>a.kind.localeCompare(b.kind,'zh-CN')||a.id-b.id);
fs.mkdirSync(path.join(root,'catalog'),{recursive:true});
fs.writeFileSync(path.join(root,'catalog/items.json'),JSON.stringify(entries,null,2));
const lines=['角色、武器中文名称与ID对照（本机7.1资源）','中文标签来源：theBowja/genshin-db（MIT）；按本地资源ID合并，仅作查询。','未确认中文名的内部条目不纳入一键补齐。','单个角色 give 会调整已有角色；保留配置请用只补缺少入口。',''];
for(const entry of entries)lines.push(`${entry.kind}\t${entry.name}${entry.named?'':' [内部名/未确认]'}\t${entry.id}\t${entry.type}\t${entry.command}`);
fs.writeFileSync(path.join(root,'角色武器代码表.txt'),'\ufeff'+lines.join('\r\n'));
const report={source:'https://github.com/theBowja/genshin-db',sourceCommit:'49a6544a6c6ae36089cb42fa591fc46f01de8bcf',characters:entries.filter(e=>e.kind==='角色').length,weapons:entries.filter(e=>e.kind==='武器').length,namedCharacters:entries.filter(e=>e.kind==='角色'&&e.named).length,namedWeapons:entries.filter(e=>e.kind==='武器'&&e.named).length,allowedNamedWeaponOverrides:[...allowed],serverResourcesChanged:false};
fs.writeFileSync(path.join(root,'audit/id-catalog-source.json'),JSON.stringify(report,null,2));console.log(report);
for(const name of ['雷电将军','芙宁娜','玛薇卡','薙草之稻光','狼的末路','天空之傲','护摩之杖'])console.log(entries.find(e=>e.name===name));

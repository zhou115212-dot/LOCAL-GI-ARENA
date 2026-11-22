// JSON data only: merge MIT Chinese labels with local server artifact/stat resources.
const fs=require('fs'),path=require('path');
const root=path.dirname(__dirname),excel=path.join(root,'server/resources/ExcelBinOutput');
const read=f=>JSON.parse(fs.readFileSync(path.join(excel,f),'utf8'));
const dir=path.join(root,'name-data/src/data/ChineseSimplified/artifacts'),names=new Map();
for(const file of fs.readdirSync(dir)){if(!file.endsWith('.json'))continue;const row=JSON.parse(fs.readFileSync(path.join(dir,file),'utf8'));names.set(row.id,row);}
const slots={EQUIP_BRACER:['生之花','flower'],EQUIP_NECKLACE:['死之羽','plume'],EQUIP_SHOES:['时之沙','sands'],EQUIP_RING:['空之杯','goblet'],EQUIP_DRESS:['理之冠','circlet']};
const labels={HP:'生命值',HP_PERCENT:'生命值%',ATTACK:'攻击力',ATTACK_PERCENT:'攻击力%',DEFENSE:'防御力',DEFENSE_PERCENT:'防御力%',CRITICAL:'暴击率',CRITICAL_HURT:'暴击伤害',CHARGE_EFFICIENCY:'元素充能效率',ELEMENT_MASTERY:'元素精通',HEAL_ADD:'治疗加成',FIRE_ADD_HURT:'火元素伤害',WATER_ADD_HURT:'水元素伤害',ICE_ADD_HURT:'冰元素伤害',ELEC_ADD_HURT:'雷元素伤害',WIND_ADD_HURT:'风元素伤害',ROCK_ADD_HURT:'岩元素伤害',GRASS_ADD_HURT:'草元素伤害',PHYSICAL_ADD_HURT:'物理伤害'};
const percent=p=>!['FIGHT_PROP_HP','FIGHT_PROP_ATTACK','FIGHT_PROP_DEFENSE','FIGHT_PROP_ELEMENT_MASTERY'].includes(p);
const label=p=>labels[p.replace('FIGHT_PROP_','')]||p;
const main=read('ReliquaryMainPropExcelConfigData.json'),sub=read('ReliquaryAffixExcelConfigData.json'),levels=read('ReliquaryLevelExcelConfigData.json');
const pieces=[];
for(const r of read('ReliquaryExcelConfigData.json')){
 if(!names.has(r.setId)||![4,5].includes(r.rankLevel)||!slots[r.equipType]||![2,3,4].includes(r.appendPropNum)||![401,501].includes(r.appendPropDepotId)||r.itemType!=='ITEM_RELIQUARY')continue;
 // Match named set rarities and standard stat depots. New sets use IDs below70000;
 // trial/transmuter pieces use special 96x depots and must not replace normal pieces.
 if(!names.get(r.setId).rarityList.includes(r.rankLevel))continue;
 const n=names.get(r.setId),slot=slots[r.equipType],mains=[];
 for(const m of main.filter(x=>x.propDepotId===r.mainPropDepotId&&x.weight>0)){
  const values=[];for(let level=1;level<=r.maxLevel;level++){
   const row=levels.find(x=>x.rank===r.rankLevel&&x.level===level),value=row?.addProps.find(x=>x.propType===m.propType)?.value;
   if(!Number.isFinite(value))throw Error(`Missing main stat level: ${r.id}/${m.id}/${level}`);values.push(value);
  }
  mains.push({id:m.id,prop:m.propType,label:label(m.propType),percent:percent(m.propType),values});
 }
 const grouped=new Map();for(const a of sub.filter(x=>x.depotId===r.appendPropDepotId&&x.weight>0)){
  if(!grouped.has(a.propType))grouped.set(a.propType,[]);grouped.get(a.propType).push({id:a.id,value:a.propValue});
 }
 const subs=[...grouped].map(([prop,rolls])=>({prop,label:label(prop),percent:percent(prop),rolls:rolls.sort((a,b)=>a.value-b.value)}));
 if(!mains.length||subs.length<4)continue;
 pieces.push({id:r.id,setId:r.setId,stars:r.rankLevel,slot:r.equipType,slotName:slot[0],name:n[slot[1]]?.name||slot[0],initial:r.appendPropNum,maxLevel:r.maxLevel-1,mains,subs});
}
pieces.sort((a,b)=>a.id-b.id);
const sets=[...names.values()].filter(n=>pieces.some(p=>p.setId===n.id)).map(n=>({id:n.id,name:n.name,twoPiece:n.effect2Pc||'',fourPiece:n.effect4Pc||''})).sort((a,b)=>a.id-b.id);
const catalog={version:1,source:'https://github.com/theBowja/genshin-db',gameVersion:'7.1.0',sets,pieces};
fs.writeFileSync(path.join(root,'catalog/artifacts.json'),JSON.stringify(catalog,null,2));
const report={sets:sets.length,pieces:pieces.length,star4:pieces.filter(p=>p.stars===4).length,star5:pieces.filter(p=>p.stars===5).length,labelsAreDataOnly:true,clientChanged:false,serverResourceChanged:false};
fs.writeFileSync(path.join(root,'audit/artifact-catalog.json'),JSON.stringify(report,null,2));console.log(report);
if(!sets.some(s=>s.name==='绝缘之旗印')||!pieces.some(p=>p.id===94554))throw Error('Expected Emblem sample missing');

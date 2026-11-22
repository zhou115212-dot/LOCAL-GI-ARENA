using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using System.Globalization;
using System.Web.Script.Serialization;

public static class ArenaBinding {
    public static int Uid {get; private set;}
    public static void Bind(string root) {
        var path=Path.Combine(root,"run","test-account.json");
        if(!File.Exists(path)||new FileInfo(path).Length>8192)throw new InvalidDataException("请先在本次安装中创建本地测试账号。");
        var row=new JavaScriptSerializer().Deserialize<Dictionary<string,object>>(File.ReadAllText(path));
        object uid,user;
        if(row==null||!row.TryGetValue("uid",out uid)||!(uid is int)||(int)uid<=0||!row.TryGetValue("username",out user)||!(user is string)||String.IsNullOrWhiteSpace((string)user))throw new InvalidDataException("本地测试账号配置无效。");
        if(Uid!=0&&Uid!=(int)uid)throw new InvalidDataException("账号绑定已变化，请重新打开控制器。");
        Uid=(int)uid;
    }
}
public class ArtifactCatalog { public List<ArtifactSet> sets; public List<ArtifactPiece> pieces; public string gameVersion; }
public class ArtifactSet { public int id; public string name,twoPiece,fourPiece; public override string ToString(){return name+" · "+id;} }
public class ArtifactPiece { public int id,setId,stars,initial,maxLevel;public string slot,slotName,name;public List<ArtifactMain> mains;public List<ArtifactSub> subs; }
public class ArtifactMain { public int id;public string prop,label;public bool percent;public double[] values;public override string ToString(){return label;} }
public class ArtifactSub { public string prop,label;public bool percent;public List<ArtifactRoll> rolls;public override string ToString(){return label;} }
public class ArtifactRoll { public int id;public double value; }
public class AffixCount {public int id,count;}
public class ArtifactRequest {public int uid=ArenaBinding.Uid,itemId,level,mainPropId,quantity=1;public string mode="standard";public List<AffixCount> affixes=new List<AffixCount>();}
public class ArtifactSetRequest {public int uid=ArenaBinding.Uid;public string kind="set";public List<ArtifactRequest> pieces=new List<ArtifactRequest>();}
public class ArtifactReceipt {public bool ok;public int added;public List<string> objectIds;public string request,command;}

public static class ArtifactMath {
    public static readonly string[] Slots={"EQUIP_BRACER","EQUIP_NECKLACE","EQUIP_SHOES","EQUIP_RING","EQUIP_DRESS"};
    public static ArtifactRequest Default(ArtifactCatalog catalog,int setId,string slot,int stars,int level,string mode){
        var p=catalog.pieces.Where(x=>x.setId==setId&&x.slot==slot&&x.stars==stars).OrderByDescending(x=>x.initial).ThenByDescending(x=>x.id).FirstOrDefault();
        if(p==null)throw new ArgumentException("该套装在所选星级没有这个部位。");
        var preferred=slot=="EQUIP_SHOES"?"FIGHT_PROP_CHARGE_EFFICIENCY":slot=="EQUIP_RING"?"FIGHT_PROP_FIRE_ADD_HURT":slot=="EQUIP_DRESS"?"FIGHT_PROP_CRITICAL":"";
        var main=p.mains.FirstOrDefault(x=>x.prop==preferred)??p.mains[0];
        var r=new ArtifactRequest(){itemId=p.id,mainPropId=main.id,level=level,mode=mode};
        int budget=p.initial+level/4,n=Math.Min(4,budget);
        var order=new[]{"FIGHT_PROP_CRITICAL","FIGHT_PROP_CRITICAL_HURT","FIGHT_PROP_ATTACK_PERCENT","FIGHT_PROP_CHARGE_EFFICIENCY","FIGHT_PROP_ELEMENT_MASTERY","FIGHT_PROP_HP_PERCENT","FIGHT_PROP_DEFENSE_PERCENT","FIGHT_PROP_ATTACK","FIGHT_PROP_HP","FIGHT_PROP_DEFENSE"};
        var subs=p.subs.Where(x=>x.prop!=main.prop).OrderBy(x=>Array.IndexOf(order,x.prop)<0?999:Array.IndexOf(order,x.prop)).Take(n).ToList();
        for(int i=0;i<n;i++)r.affixes.Add(new AffixCount(){id=subs[i].rolls.Last().id,count=1+(i==0?(budget-n)/2:0)+(i==Math.Min(1,n-1)?budget-n-(budget-n)/2:0)});
        Validate(p,r);return r;
    }
    public static void ValidateSet(ArtifactCatalog catalog,ArtifactSetRequest batch) {
        if(ArenaBinding.Uid<=0||batch==null||batch.uid!=ArenaBinding.Uid||batch.kind!="set"||batch.pieces==null||batch.pieces.Count!=5)throw new ArgumentException("五件套需要五个不同部位，各1件。");
        var slots=new HashSet<string>();int setId=-1,stars=-1,level=-1;string mode=null;
        foreach(var r in batch.pieces){var p=catalog.pieces.FirstOrDefault(x=>x.id==r.itemId);Validate(p,r);
            if(r.quantity!=1||!Slots.Contains(p.slot)||!slots.Add(p.slot))throw new ArgumentException("五件套必须每个部位各1件。");
            if(setId<0){setId=p.setId;stars=p.stars;level=r.level;mode=r.mode;}
            if(setId!=p.setId||stars!=p.stars||level!=r.level||mode!=r.mode)throw new ArgumentException("五件套需使用同一套装、星级、等级和模式。");
        }
    }
    public static ArtifactCatalog Load(string root){return new JavaScriptSerializer(){MaxJsonLength=30000000}.Deserialize<ArtifactCatalog>(File.ReadAllText(Path.Combine(root,"catalog\\artifacts.json")));}
    public static string Display(double value,bool percent){return percent?(value*100).ToString("0.0",CultureInfo.InvariantCulture)+"%":value.ToString("0.#",CultureInfo.InvariantCulture);}
    public static double Total(ArtifactSub stat,int[] counts){double value=0;for(int i=0;i<counts.Length;i++)value+=stat.rolls[i].value*counts[i];return value;}
    // At most C(203,3) candidates at200 rolls, bounded and deterministic; mixed game tiers.
    public static int[] Nearest(ArtifactSub stat,int total,double displayedTarget) {
        if(total<1||total>200||stat.rolls.Count!=4||double.IsNaN(displayedTarget)||double.IsInfinity(displayedTarget))throw new ArgumentException("目标匹配需要1–200次和四档数值。");
        double target=stat.percent?displayedTarget/100:displayedTarget,best=double.MaxValue;int[] result=new int[4];
        for(int a=0;a<=total;a++)for(int b=0;b<=total-a;b++)for(int c=0;c<=total-a-b;c++) {
            int d=total-a-b-c;double value=a*stat.rolls[0].value+b*stat.rolls[1].value+c*stat.rolls[2].value+d*stat.rolls[3].value;
            double error=Math.Abs(value-target);if(error<best){best=error;result=new[]{a,b,c,d};}
        }return result;
    }
    public static string Command(ArtifactRequest request) {
        return "give @"+request.uid+" "+request.itemId+" lv"+request.level+" x"+request.quantity+" "+request.mainPropId+" "+String.Join(" ",request.affixes.Select(a=>a.id+","+a.count));
    }
    public static void Validate(ArtifactPiece piece,ArtifactRequest r) {
        if(ArenaBinding.Uid<=0||r.uid!=ArenaBinding.Uid||piece==null||piece.id!=r.itemId||r.quantity<1||r.quantity>5||r.level<0||r.level>piece.maxLevel)throw new ArgumentException("请选择有效圣遗物、等级以及1–5件数量。");
        var main=piece.mains.FirstOrDefault(m=>m.id==r.mainPropId);if(main==null)throw new ArgumentException("主词条与部位不匹配。");
        if(r.mode!="standard"&&r.mode!="free")throw new ArgumentException("无效生成模式。");
        var props=new HashSet<string>();var ids=new HashSet<int>();var totals=new Dictionary<string,int>();int sum=0;
        foreach(var a in r.affixes) {
            var sub=piece.subs.FirstOrDefault(s=>s.rolls.Any(t=>t.id==a.id));
            if(sub==null||a.count<1||a.count>200||!ids.Add(a.id)||sub.prop==main.prop)throw new ArgumentException("副词条无效、重复或与主词条冲突。");
            props.Add(sub.prop);sum+=a.count;if(!totals.ContainsKey(sub.prop))totals[sub.prop]=0;totals[sub.prop]+=a.count;
        }
        int budget=piece.initial+r.level/4;
        if(props.Count>4||props.Count<1||totals.Values.Any(n=>n>200))throw new ArgumentException("选择1–4种不同副词条，每种至多200次。");
        if(r.mode=="standard"&&(sum!=budget||props.Count!=Math.Min(4,budget)))throw new ArgumentException("标准范围需要 "+budget+" 次总词条贡献、"+Math.Min(4,budget)+" 种副词条（包含初始词条）。");
        if(r.mode=="free"&&sum<budget)throw new ArgumentException("自由测试至少需要 "+budget+" 次总贡献，避免服务端随机补词条。");
    }
}

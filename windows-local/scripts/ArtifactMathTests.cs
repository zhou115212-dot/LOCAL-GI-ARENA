using System;
using System.Linq;
using System.Collections.Generic;
class ArtifactMathTests {
    static int count;
    static void Check(bool ok){if(!ok)throw new Exception("Test "+count);count++;}
    static void Bad(Action action){try{action();}catch(ArgumentException){count++;return;}throw new Exception("Expected rejection");}
    static ArtifactRequest Standard(ArtifactPiece p,ArtifactMain m,int level) {
        int budget=p.initial+level/4,n=Math.Min(4,budget);var r=new ArtifactRequest(){itemId=p.id,level=level,mainPropId=m.id};
        var available=p.subs.Where(s=>s.prop!=m.prop).Take(n).ToList();
        for(int i=0;i<available.Count;i++)r.affixes.Add(new AffixCount(){id=available[i].rolls.Last().id,count=1+(i==0?budget-n:0)});return r;
    }
    static void Main(string[] args){ArenaBinding.Bind(args[0]);var c=ArtifactMath.Load(args[0]);Check(c.sets.Count==60);Check(c.sets.Any(s=>s.name=="深林的记忆"));Check(c.sets.Any(s=>s.name=="绝缘之旗印"));Check(c.sets.Any(s=>s.name=="黑曜秘典"));
        foreach(var p in c.pieces)foreach(var m in p.mains){ArtifactMath.Validate(p,Standard(p,m,0));count++;ArtifactMath.Validate(p,Standard(p,m,p.maxLevel));count++;Check(m.values.Length==p.maxLevel+1);}
        var piece=c.pieces.First(p=>p.id==94554);var main=piece.mains.First(m=>m.prop=="FIGHT_PROP_CHARGE_EFFICIENCY");Check(ArtifactMath.Display(main.values[20],true)=="51.8%");
        var r=Standard(piece,main,20);Check(r.affixes.Sum(a=>a.count)==9);Check(ArtifactMath.Command(r).StartsWith("give @"+ArenaBinding.Uid+" 94554 lv20 x1 10007 "));
        r.mainPropId=13007;Bad(()=>ArtifactMath.Validate(piece,r));r.mainPropId=main.id;
        r.quantity=6;Bad(()=>ArtifactMath.Validate(piece,r));r.quantity=1;r.uid=0;Bad(()=>ArtifactMath.Validate(piece,r));r.uid=ArenaBinding.Uid;
        r.level=21;Bad(()=>ArtifactMath.Validate(piece,r));r.level=20;r.affixes[0].count--;Bad(()=>ArtifactMath.Validate(piece,r));r.mode="free";Bad(()=>ArtifactMath.Validate(piece,r));r.affixes[0].count+=4;ArtifactMath.Validate(piece,r);count++;
        r.affixes[0].count=201;Bad(()=>ArtifactMath.Validate(piece,r));
        var crit=piece.subs.First(s=>s.prop=="FIGHT_PROP_CRITICAL");var match=ArtifactMath.Nearest(crit,3,11.7);Check(match.Sum()==3);Check(ArtifactMath.Display(ArtifactMath.Total(crit,match),true)=="11.7%");
        match=ArtifactMath.Nearest(crit,3,9.33);Check(Math.Abs(ArtifactMath.Total(crit,match)*100-9.33)<0.001);
        Bad(()=>ArtifactMath.Nearest(crit,0,11.7));Bad(()=>ArtifactMath.Nearest(crit,201,11.7));
        Check(c.pieces.Any(p=>p.setId==15038&&p.stars==5));Check(!c.pieces.Any(p=>p.setId==10010&&p.stars==4));
        foreach(var set in c.sets)foreach(int rarity in new[]{4,5})if(ArtifactMath.Slots.All(slot=>c.pieces.Any(p=>p.setId==set.id&&p.stars==rarity&&p.slot==slot)))foreach(int lv in new[]{0,rarity==4?16:20}){
            var batch=new ArtifactSetRequest();foreach(var slot in ArtifactMath.Slots)batch.pieces.Add(ArtifactMath.Default(c,set.id,slot,rarity,lv,"standard"));ArtifactMath.ValidateSet(c,batch);count++;Check(batch.pieces.Count==5);Check(batch.pieces.All(x=>x.quantity==1));
        }
        var five=new ArtifactSetRequest();foreach(var slot in ArtifactMath.Slots)five.pieces.Add(ArtifactMath.Default(c,15020,slot,5,20,"standard"));ArtifactMath.ValidateSet(c,five);count++;
        five.pieces.RemoveAt(4);Bad(()=>ArtifactMath.ValidateSet(c,five));five.pieces.Add(ArtifactMath.Default(c,15020,ArtifactMath.Slots[0],5,20,"standard"));Bad(()=>ArtifactMath.ValidateSet(c,five));five.pieces[4]=ArtifactMath.Default(c,15020,ArtifactMath.Slots[4],5,20,"standard");
        five.pieces[4].quantity=2;Bad(()=>ArtifactMath.ValidateSet(c,five));five.pieces[4].quantity=1;five.pieces[4].mode="free";Bad(()=>ArtifactMath.ValidateSet(c,five));five.pieces[4]=ArtifactMath.Default(c,15020,ArtifactMath.Slots[4],5,16,"standard");Bad(()=>ArtifactMath.ValidateSet(c,five));
        five.pieces[4]=ArtifactMath.Default(c,15001,ArtifactMath.Slots[4],5,20,"standard");Bad(()=>ArtifactMath.ValidateSet(c,five));
        Console.WriteLine("PASS "+count+" artifact model/range/slot/numerical/set tests (no DB writes)");
    }
}

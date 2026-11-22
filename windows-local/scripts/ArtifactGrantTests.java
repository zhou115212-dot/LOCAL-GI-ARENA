import com.google.gson.*;
import java.nio.file.*;
public class ArtifactGrantTests {
    static int count;
    static void check(boolean ok){if(!ok)throw new AssertionError("Test "+count);count++;}
    static void bad(Path root,JsonObject request){try{ArtifactGrant.validate(root,request);}catch(Exception expected){count++;return;}throw new AssertionError("Expected invalid plan");}
    static void badBatch(Path root,JsonObject request){try{ArtifactGrant.validateBatch(root,request);}catch(Exception expected){count++;return;}throw new AssertionError("Expected invalid batch");}
    static JsonObject batch(Path root)throws Exception{
        var batch=new JsonObject();batch.addProperty("uid",10001);batch.addProperty("kind","set");var pieces=new JsonArray();
        var catalog=ArtifactGrant.read(root.resolve("catalog/artifacts.json"));
        for(String slot:new String[]{"EQUIP_BRACER","EQUIP_NECKLACE","EQUIP_SHOES","EQUIP_RING","EQUIP_DRESS"}){
            JsonObject p=null;for(var e:catalog.getAsJsonArray("pieces")){var x=e.getAsJsonObject();if(x.get("setId").getAsInt()==15020&&x.get("stars").getAsInt()==5&&x.get("initial").getAsInt()==4&&x.get("slot").getAsString().equals(slot))p=x;}
            var main=p.getAsJsonArray("mains").get(0).getAsJsonObject();var r=new JsonObject();r.addProperty("uid",10001);r.addProperty("itemId",p.get("id").getAsInt());r.addProperty("level",20);r.addProperty("quantity",1);r.addProperty("mode","standard");r.add("mainPropId",main.get("id"));var affixes=new JsonArray();
            for(var e:p.getAsJsonArray("subs")){var sub=e.getAsJsonObject();if(sub.get("prop").equals(main.get("prop")))continue;var rolls=sub.getAsJsonArray("rolls");var a=new JsonObject();a.add("id",rolls.get(rolls.size()-1).getAsJsonObject().get("id"));a.addProperty("count",affixes.size()==0?6:1);affixes.add(a);if(affixes.size()==4)break;}r.add("affixes",affixes);pieces.add(r);
        }batch.add("pieces",pieces);return batch;
    }
    static JsonObject request(){return JsonParser.parseString("{\"uid\":10001,\"itemId\":94554,\"level\":20,\"mainPropId\":10007,\"quantity\":1,\"mode\":\"standard\",\"affixes\":[{\"id\":501204,\"count\":3},{\"id\":501224,\"count\":4},{\"id\":501064,\"count\":1},{\"id\":501244,\"count\":1}]}").getAsJsonObject();}
    public static void main(String[] args)throws Exception{Path root=Path.of(args[0]);var r=request();var p=ArtifactGrant.validate(root,r);check(p.get("totalRolls").getAsInt()==9);check(Math.abs(p.get("mainValue").getAsDouble()-.518)<1e-6);check(ArtifactGrant.expanded(r).size()==9);
        r.addProperty("uid",10002);bad(root,r);r=request();r.addProperty("itemId",13509);bad(root,r);r=request();r.addProperty("mainPropId",13007);bad(root,r);r=request();r.addProperty("quantity",6);bad(root,r);r=request();r.addProperty("level",21);bad(root,r);
        r=request();r.getAsJsonArray("affixes").get(0).getAsJsonObject().addProperty("count",2);bad(root,r);r.addProperty("mode","free");bad(root,r);r.getAsJsonArray("affixes").get(0).getAsJsonObject().addProperty("count",20);check(ArtifactGrant.validate(root,r).get("totalRolls").getAsInt()==26);
        r=request();r.getAsJsonArray("affixes").get(3).getAsJsonObject().addProperty("id",501234);bad(root,r); // ER duplicates the main stat.
        r=request();r.getAsJsonArray("affixes").get(0).getAsJsonObject().addProperty("count",201);bad(root,r);
        r=request();r.getAsJsonArray("affixes").add(r.getAsJsonArray("affixes").get(0).deepCopy());bad(root,r);
        var batch=batch(root);var bp=ArtifactGrant.validateBatch(root,batch);check(bp.get("quantity").getAsInt()==5);check(bp.getAsJsonArray("pieces").size()==5);
        var bad=batch.deepCopy();bad.getAsJsonArray("pieces").remove(4);badBatch(root,bad);bad=batch.deepCopy();bad.getAsJsonArray("pieces").set(4,bad.getAsJsonArray("pieces").get(0).deepCopy());badBatch(root,bad);
        bad=batch.deepCopy();bad.getAsJsonArray("pieces").get(4).getAsJsonObject().addProperty("quantity",2);badBatch(root,bad);bad=batch.deepCopy();bad.getAsJsonArray("pieces").get(4).getAsJsonObject().addProperty("mainPropId",-1);badBatch(root,bad);
        bad=batch.deepCopy();bad.getAsJsonArray("pieces").get(4).getAsJsonObject().addProperty("mode","free");badBatch(root,bad);bad=batch.deepCopy();bad.addProperty("uid",10002);badBatch(root,bad);bad=batch.deepCopy();bad.addProperty("kind","other");badBatch(root,bad);
        var token="1234567890abcdef1234567890abcdef";check(ArtifactGrant.childToken(token,0).equals(ArtifactGrant.childToken(token,0)));check(!ArtifactGrant.childToken(token,0).equals(ArtifactGrant.childToken(token,1)));
        System.out.println("PASS "+count+" independent artifact server-plan/set tests (no DB writes)");
    }
}

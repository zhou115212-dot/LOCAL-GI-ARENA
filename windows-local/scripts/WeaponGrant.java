import arena.install.ArenaAccount;
import com.google.gson.*;
import com.mongodb.client.MongoClients;
import org.bson.Document;
import java.nio.file.*;
import java.nio.channels.FileChannel;
import java.util.*;

/** Local weapon copies via normal server command. MongoDB is read-only here. */
public class WeaponGrant {
    static final Gson JSON=new GsonBuilder().setPrettyPrinting().create();
    static JsonObject read(Path p)throws Exception{return JsonParser.parseString(Files.readString(p)).getAsJsonObject();}
    static JsonObject validate(Path root,int id,int level,int refine,int quantity)throws Exception{
        if(level<1||level>90||refine<1||refine>5||quantity<1||quantity>100)throw new Exception("Expected level 1..90, refinement 1..5, copies 1..100");
        JsonObject named=null,weapon=null;
        for(var v:JsonParser.parseString(Files.readString(root.resolve("catalog/items.json"))).getAsJsonArray()){
            var e=v.getAsJsonObject();if(e.get("id").getAsInt()==id&&e.get("kind").getAsString().equals("武器")&&e.get("named").getAsBoolean())named=e;
        }
        for(var v:JsonParser.parseString(Files.readString(root.resolve("server/resources/ExcelBinOutput/WeaponExcelConfigData.json"))).getAsJsonArray()){
            var e=v.getAsJsonObject();if(e.get("id").getAsInt()==id&&e.get("itemType").getAsString().equals("ITEM_WEAPON"))weapon=e;
        }
        if(named==null||weapon==null)throw new Exception("Select a named weapon present in the installed resources");
        boolean canRefine=false;for(var a:weapon.getAsJsonArray("skillAffix"))if(a.getAsInt()>0)canRefine=true;
        if(!canRefine&&refine!=1)throw new Exception("This weapon has no refinement effect; choose refinement 1");
        var p=new JsonObject();p.addProperty("uid",ArenaAccount.uid(root));p.addProperty("itemId",id);p.addProperty("name",named.get("name").getAsString());
        p.addProperty("level",level);p.addProperty("refinement",refine);p.addProperty("quantity",quantity);
        p.addProperty("command","give @"+ArenaAccount.uid(root)+" "+id+" lv"+level+" r"+refine+" x"+quantity);return p;
    }
    static boolean matches(Document row,JsonObject plan){return row.getInteger("level",1)==plan.get("level").getAsInt()&&row.getInteger("refinement",0)+1==plan.get("refinement").getAsInt()&&row.getInteger("equipCharacter",0)==0;}
    static void atomic(Path p,JsonObject value)throws Exception{
        Files.createDirectories(p.getParent());Path temp=p.resolveSibling(p.getFileName()+".tmp");Files.writeString(temp,JSON.toJson(value));Files.move(temp,p,StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);
    }
    public static void main(String[] args){try{
        Path root=Path.of(args[0]).toAbsolutePath().normalize();ArenaAccount.toolRoot(ArenaAccount.class,root);
        String token=args[1];if(!token.matches("[a-f0-9]{32}"))throw new Exception("Invalid request ID");
        var plan=validate(root,Integer.parseInt(args[2]),Integer.parseInt(args[3]),Integer.parseInt(args[4]),Integer.parseInt(args[5]));
        if(args.length>6&&args[6].equals("plan")){System.out.println(JSON.toJson(plan));return;}
        ArtifactGrant.localOnline();System.setProperty("logback.configurationFile",root.resolve("scripts/mongo-logback.xml").toString());
        Path result=root.resolve("run/weapon-results/"+token+".json"),auditPath=root.resolve("audit/weapon-grants/"+token+".json");
        try(var channel=FileChannel.open(root.resolve("run/content-sync.lock"),StandardOpenOption.CREATE,StandardOpenOption.WRITE);var lock=channel.tryLock()){
            if(lock==null)throw new Exception("Another content grant is running");
            if(Files.exists(result)){var receipt=read(result);if(!receipt.getAsJsonObject("plan").equals(plan))throw new Exception("Completed request has different settings");System.out.println(JSON.toJson(receipt));return;}
            try(var mongo=MongoClients.create("mongodb://127.0.0.1:27018/?directConnection=true&serverSelectionTimeoutMS=5000")){
                var items=mongo.getDatabase("astaps_local").getCollection("items");var filter=new Document("ownerId",ArenaAccount.uid(root)).append("itemId",plan.get("itemId").getAsInt());
                var before=new HashSet<String>();JsonObject audit;
                if(Files.exists(auditPath)){audit=read(auditPath);if(!audit.getAsJsonObject("plan").equals(plan))throw new Exception("Submitted request has different settings");for(var v:audit.getAsJsonArray("beforeIds"))before.add(v.getAsString());}
                else{
                    var weaponIds=new ArrayList<Integer>();for(var v:JsonParser.parseString(Files.readString(root.resolve("server/resources/ExcelBinOutput/WeaponExcelConfigData.json"))).getAsJsonArray())weaponIds.add(v.getAsJsonObject().get("id").getAsInt());
                    int limit=read(root.resolve("server/config.json")).getAsJsonObject("server").getAsJsonObject("game").getAsJsonObject("gameOptions").getAsJsonObject("inventoryLimits").get("weapons").getAsInt();
                    if(items.countDocuments(new Document("ownerId",ArenaAccount.uid(root)).append("itemId",new Document("$in",weaponIds)))+plan.get("quantity").getAsInt()>limit)throw new Exception("Weapon inventory capacity would be exceeded");
                    for(var row:items.find(filter))before.add(row.getObjectId("_id").toHexString());
                    audit=new JsonObject();audit.add("plan",plan);audit.add("beforeIds",JSON.toJsonTree(before));audit.addProperty("created",java.time.Instant.now().toString());audit.addProperty("directDatabaseWrites",false);atomic(auditPath,audit);
                    // A previously audited request is never automatically submitted again.
                    Path temp=root.resolve("run/commands/"+token+".tmp");Files.writeString(temp,plan.get("command").getAsString());Files.move(temp,root.resolve("run/commands/"+token+".txt"),StandardCopyOption.ATOMIC_MOVE);
                }
                var found=new ArrayList<String>();int amount=plan.get("quantity").getAsInt();
                for(int i=0;i<300;i++){found.clear();for(var row:items.find(filter)){var id=row.getObjectId("_id").toHexString();if(!before.contains(id)&&matches(row,plan))found.add(id);}if(found.size()==amount)break;if(found.size()>amount)throw new Exception("Concurrent matching grant detected; inspect request audit");Thread.sleep(100);}
                if(found.size()!=amount)throw new Exception("Saved copies not fully confirmed for request "+token+"; inspect audit/weapon-grants before adding again");
                var receipt=new JsonObject();receipt.addProperty("ok",true);receipt.addProperty("added",found.size());receipt.addProperty("verifiedSaved",true);receipt.add("plan",plan);receipt.add("objectIds",JSON.toJsonTree(found));atomic(result,receipt);System.out.println(JSON.toJson(receipt));
            }
        }
    }catch(Exception e){System.err.println(e.getMessage());System.exit(1);}}
}

import com.google.gson.*;
import com.mongodb.client.MongoClients;
import org.bson.Document;
import java.nio.file.*;
import java.nio.channels.FileChannel;
import java.net.*;
import java.util.*;

/** Validate artifact plans, use server's normal give command, verify saved new records.
 * MongoDB operations here are read-only. No live cache/direct-save inconsistency. */
public class ArtifactGrant {
    static final Gson JSON=new GsonBuilder().setPrettyPrinting().create();
    static record Validated(int itemId,int level,int mainPropId,int quantity,String command,List<Integer> affixes,JsonObject piece){}
    static JsonObject read(Path p)throws Exception{return JsonParser.parseString(Files.readString(p)).getAsJsonObject();}
    static JsonObject validate(Path root,JsonObject r)throws Exception {
        if(r.get("uid").getAsInt()!=10001)throw new Exception("Only UID10001 is supported");
        int id=r.get("itemId").getAsInt(),level=r.get("level").getAsInt(),quantity=r.get("quantity").getAsInt(),mainId=r.get("mainPropId").getAsInt();
        String mode=r.get("mode").getAsString();if(!Set.of("standard","free").contains(mode))throw new Exception("Invalid mode");
        JsonObject piece=null;
        for(var e:read(root.resolve("catalog/artifacts.json")).getAsJsonArray("pieces"))if(e.getAsJsonObject().get("id").getAsInt()==id)piece=e.getAsJsonObject();
        if(piece==null||level<0||level>piece.get("maxLevel").getAsInt()||quantity<1||quantity>5)throw new Exception("Invalid artifact/level/quantity");
        JsonObject main=null;
        for(var e:piece.getAsJsonArray("mains"))if(e.getAsJsonObject().get("id").getAsInt()==mainId)main=e.getAsJsonObject();
        if(main==null)throw new Exception("Main stat does not belong to this slot");
        Map<Integer,JsonObject> stats=new HashMap<>();Map<Integer,Double> values=new HashMap<>();
        for(var e:piece.getAsJsonArray("subs")){var s=e.getAsJsonObject();for(var tier:s.getAsJsonArray("rolls")){var t=tier.getAsJsonObject();int tid=t.get("id").getAsInt();stats.put(tid,s);values.put(tid,t.get("value").getAsDouble());}}
        Set<Integer> seen=new HashSet<>();Map<String,Integer> counts=new LinkedHashMap<>();Map<String,Double> totals=new LinkedHashMap<>();int sum=0;
        StringBuilder command=new StringBuilder("give @10001 "+id+" lv"+level+" x"+quantity+" "+mainId);
        for(var e:r.getAsJsonArray("affixes")){
            var a=e.getAsJsonObject();int aid=a.get("id").getAsInt(),count=a.get("count").getAsInt();
            if(!stats.containsKey(aid)||!seen.add(aid)||count<1||count>200)throw new Exception("Invalid or duplicate affix/count");
            String prop=stats.get(aid).get("prop").getAsString();
            if(prop.equals(main.get("prop").getAsString()))throw new Exception("Substat conflicts with main stat");
            counts.merge(prop,count,Integer::sum);totals.merge(prop,count*values.get(aid),Double::sum);sum+=count;
            command.append(" ").append(aid).append(",").append(count);
        }
        int budget=piece.get("initial").getAsInt()+level/4;
        if(counts.size()<1||counts.size()>4||counts.values().stream().anyMatch(n->n>200))throw new Exception("Expected1..4 distinct substats, at most200 rolls per stat");
        if(mode.equals("standard")&&(sum!=budget||counts.size()!=Math.min(4,budget)))throw new Exception("Standard roll budget/unique count is not satisfied");
        if(mode.equals("free")&&sum<budget)throw new Exception("Too few rolls: server would randomly fill the remaining affixes");
        var report=new JsonObject();report.addProperty("uid",10001);report.addProperty("itemId",id);report.addProperty("level",level);report.addProperty("mainPropId",mainId);report.addProperty("quantity",quantity);report.addProperty("mode",mode);report.addProperty("totalRolls",sum);report.addProperty("standardBudget",budget);report.addProperty("command",command.toString());report.add("substatValues",JSON.toJsonTree(totals));report.addProperty("mainValue",main.getAsJsonArray("values").get(level).getAsDouble());return report;
    }
    static List<Integer> expanded(JsonObject r){List<Integer> out=new ArrayList<>();for(var e:r.getAsJsonArray("affixes")){var a=e.getAsJsonObject();for(int i=0;i<a.get("count").getAsInt();i++)out.add(a.get("id").getAsInt());}Collections.sort(out);return out;}
    static void atomic(Path p,JsonObject value)throws Exception {
        Files.createDirectories(p.getParent());Path tmp=p.resolveSibling(p.getFileName()+".tmp");Files.writeString(tmp,JSON.toJson(value));Files.move(tmp,p,StandardCopyOption.ATOMIC_MOVE,StandardCopyOption.REPLACE_EXISTING);
    }
    static boolean matches(Document d,JsonObject request,List<Integer> affixes) {
        if(d.getInteger("level",0)!=request.get("level").getAsInt()+1||d.getInteger("mainPropId",0)!=request.get("mainPropId").getAsInt())return false;
        var actual=new ArrayList<>(d.getList("appendPropIdList",Integer.class,List.of()));Collections.sort(actual);return actual.equals(affixes);
    }
    static void localOnline()throws Exception {
        var c=(HttpURLConnection)URI.create("http://127.0.0.1:8088/api/status").toURL().openConnection(Proxy.NO_PROXY);c.setConnectTimeout(3000);c.setReadTimeout(3000);
        try(var in=c.getInputStream()){var h=JsonParser.parseString(new String(in.readAllBytes(),java.nio.charset.StandardCharsets.UTF_8)).getAsJsonObject();if(h.getAsJsonObject("game").get("players").getAsInt()<1)throw new Exception("Enter the world with localtest UID10001 first");}finally{c.disconnect();}
    }
    static JsonObject validateBatch(Path root,JsonObject request)throws Exception {
        if(!request.has("kind")||!request.get("kind").getAsString().equals("set")||request.get("uid").getAsInt()!=10001||!request.has("pieces")||request.getAsJsonArray("pieces").size()!=5)throw new Exception("Expected one full five-piece set for UID10001");
        var catalog=read(root.resolve("catalog/artifacts.json"));var slots=new HashSet<String>();int setId=-1,stars=-1,level=-1;String mode=null;var plans=new JsonArray();
        for(var e:request.getAsJsonArray("pieces")) {
            var r=e.getAsJsonObject();var plan=validate(root,r);JsonObject piece=null;
            for(var x:catalog.getAsJsonArray("pieces"))if(x.getAsJsonObject().get("id").getAsInt()==r.get("itemId").getAsInt())piece=x.getAsJsonObject();
            if(piece==null||r.get("quantity").getAsInt()!=1||!slots.add(piece.get("slot").getAsString())||!Set.of("EQUIP_BRACER","EQUIP_NECKLACE","EQUIP_SHOES","EQUIP_RING","EQUIP_DRESS").contains(piece.get("slot").getAsString()))throw new Exception("Five-piece set must contain each slot exactly once");
            if(setId<0){setId=piece.get("setId").getAsInt();stars=piece.get("stars").getAsInt();level=r.get("level").getAsInt();mode=r.get("mode").getAsString();}
            if(setId!=piece.get("setId").getAsInt()||stars!=piece.get("stars").getAsInt()||level!=r.get("level").getAsInt()||!mode.equals(r.get("mode").getAsString()))throw new Exception("Set/rarity/level/mode must match across all five pieces");
            plans.add(plan);
        }
        var result=new JsonObject();result.addProperty("uid",10001);result.addProperty("kind","set");result.addProperty("setId",setId);result.addProperty("stars",stars);result.addProperty("quantity",5);result.add("pieces",plans);return result;
    }
    static void capacity(Path root,com.mongodb.client.MongoCollection<Document> items,int quantity)throws Exception {
        int limit=read(root.resolve("server/config.json")).getAsJsonObject("server").getAsJsonObject("game").getAsJsonObject("gameOptions").getAsJsonObject("inventoryLimits").get("relics").getAsInt();
        var all=new ArrayList<Integer>();for(var e:JsonParser.parseString(Files.readString(root.resolve("server/resources/ExcelBinOutput/ReliquaryExcelConfigData.json"))).getAsJsonArray())all.add(e.getAsJsonObject().get("id").getAsInt());
        long owned=items.countDocuments(new Document("ownerId",10001).append("itemId",new Document("$in",all)));
        if(owned+quantity>limit)throw new Exception("Artifact inventory limit would be exceeded");
    }
    // Caller holds the shared content lock across the complete batch. Once audited, never requeue.
    static JsonObject grantOne(Path root,String token,JsonObject request,JsonObject plan,com.mongodb.client.MongoCollection<Document> items)throws Exception {
        Path resultPath=root.resolve("run/artifact-results/"+token+".json");
        if(Files.exists(resultPath)){var receipt=read(resultPath);if(!receipt.getAsJsonObject("plan").equals(plan))throw new Exception("Request changed after completed grant");return receipt;}
        int itemId=request.get("itemId").getAsInt(),quantity=request.get("quantity").getAsInt();var filter=new Document("ownerId",10001).append("itemId",itemId);
        Path auditPath=root.resolve("audit/artifact-grants/"+token+".json");JsonObject audit;Set<String> before=new HashSet<>();
        if(Files.exists(auditPath)) {
            audit=read(auditPath);if(!audit.getAsJsonObject("requestData").equals(request))throw new Exception("Request changed after submission");
            for(var id:audit.getAsJsonArray("beforeIds"))before.add(id.getAsString());
        } else {
            capacity(root,items,quantity);for(var d:items.find(filter))before.add(d.getObjectId("_id").toHexString());
            audit=new JsonObject();audit.addProperty("request",token);audit.addProperty("created",java.time.Instant.now().toString());audit.addProperty("command",plan.get("command").getAsString());audit.add("requestData",request);audit.add("plan",plan);audit.add("beforeIds",JSON.toJsonTree(before));audit.addProperty("directDatabaseWrites",false);atomic(auditPath,audit);
            Path tmp=root.resolve("run/commands/"+token+".tmp"),queued=root.resolve("run/commands/"+token+".txt");Files.writeString(tmp,plan.get("command").getAsString());Files.move(tmp,queued,StandardCopyOption.ATOMIC_MOVE);
        }
        var expected=expanded(request);var found=new ArrayList<String>();
        for(int i=0;i<300;i++){found.clear();for(var d:items.find(filter)){String id=d.getObjectId("_id").toHexString();if(!before.contains(id)&&matches(d,request,expected))found.add(id);}if(found.size()==quantity)break;if(found.size()>quantity)throw new Exception("Multiple matching grants detected; inspect audit before repeating");Thread.sleep(100);}
        if(found.size()!=quantity)throw new Exception("Grant/save verification pending for "+token+". Do not create a new request; inspect audit/artifact-grants");
        var receipt=new JsonObject();receipt.addProperty("ok",true);receipt.addProperty("request",token);receipt.addProperty("added",found.size());receipt.addProperty("verifiedSaved",true);receipt.addProperty("command",plan.get("command").getAsString());receipt.add("objectIds",JSON.toJsonTree(found));receipt.add("plan",plan);atomic(resultPath,receipt);audit.add("receipt",receipt);atomic(auditPath,audit);return receipt;
    }
    static String childToken(String token,int index)throws Exception{return java.util.HexFormat.of().formatHex(java.security.MessageDigest.getInstance("MD5").digest(("artifact-set:"+token+":"+index).getBytes(java.nio.charset.StandardCharsets.UTF_8)));}
    public static void main(String[] args) {
        JsonObject progress=null;Path progressPath=null;
        try {
            Path root=Path.of(args[0]).toAbsolutePath().normalize();if(!root.toString().equalsIgnoreCase("E:\\Genshin-Local-Server"))throw new Exception("Unexpected root");
            String token=args[1];if(!token.matches("[a-f0-9]{32}"))throw new Exception("Invalid request token");
            var request=read(root.resolve("run/artifact-requests/"+token+".json"));boolean batch=request.has("pieces");var plan=batch?validateBatch(root,request):validate(root,request);
            if(args.length>2&&args[2].equals("plan")){System.out.println(plan);return;}
            localOnline();System.setProperty("logback.configurationFile",root.resolve("scripts/mongo-logback.xml").toString());
            try(var channel=FileChannel.open(root.resolve("run/content-sync.lock"),StandardOpenOption.CREATE,StandardOpenOption.WRITE);var lock=channel.tryLock()){
                if(lock==null)throw new Exception("Another grant/edit is in progress");
                Path resultPath=root.resolve("run/artifact-results/"+token+".json");if(Files.exists(resultPath)){var receipt=read(resultPath);if(!receipt.getAsJsonObject("plan").equals(plan))throw new Exception("Request changed after completion; nothing queued");System.out.println(receipt);return;}
                try(var client=MongoClients.create("mongodb://127.0.0.1:27018/?directConnection=true&serverSelectionTimeoutMS=5000")){
                    var db=client.getDatabase("astaps_local");if(db.getCollection("players").countDocuments(new Document("_id",10001))!=1)throw new Exception("Local player not found");var items=db.getCollection("items");
                    if(!batch){System.out.println(grantOne(root,token,request,plan,items));return;}
                    progressPath=root.resolve("audit/artifact-batches/"+token+".json");
                    if(Files.exists(progressPath)){progress=read(progressPath);if(!progress.getAsJsonObject("requestData").equals(request)||!progress.getAsJsonObject("plan").equals(plan))throw new Exception("Batch changed after submission; nothing queued");}
                    else {capacity(root,items,5);progress=new JsonObject();progress.addProperty("request",token);progress.addProperty("created",java.time.Instant.now().toString());progress.add("requestData",request);progress.add("plan",plan);progress.addProperty("confirmed",0);progress.addProperty("directDatabaseWrites",false);atomic(progressPath,progress);}
                    var receipts=new JsonArray();var ids=new JsonArray();
                    for(int i=0;i<5;i++){var receipt=grantOne(root,childToken(token,i),request.getAsJsonArray("pieces").get(i).getAsJsonObject(),plan.getAsJsonArray("pieces").get(i).getAsJsonObject(),items);receipts.add(receipt);for(var id:receipt.getAsJsonArray("objectIds"))ids.add(id);progress.addProperty("confirmed",i+1);progress.add("pieceReceipts",receipts.deepCopy());progress.addProperty("status","in-progress");atomic(progressPath,progress);}
                    var result=new JsonObject();result.addProperty("ok",true);result.addProperty("request",token);result.addProperty("added",5);result.addProperty("verifiedSaved",true);result.add("objectIds",ids);result.add("pieces",receipts);result.add("plan",plan);atomic(resultPath,result);progress.addProperty("status","complete");progress.add("receipt",result);atomic(progressPath,progress);System.out.println(result);
                }
            }
        }catch(Exception error){if(progress!=null&&progressPath!=null)try{progress.addProperty("status","pending");progress.addProperty("error",error.getMessage());atomic(progressPath,progress);}catch(Exception ignored){}System.err.println("Artifact generation: "+error.getMessage());System.exit(2);}
    }
}
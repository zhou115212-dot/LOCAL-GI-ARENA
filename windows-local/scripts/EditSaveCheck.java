import arena.install.ArenaAccount;
import com.google.gson.*;
import com.mongodb.client.MongoClients;
import org.bson.Document;
import org.bson.types.ObjectId;
import java.nio.file.*;
import java.util.*;

/** Read-only saved-state verification and test snapshots. Never updates MongoDB. */
public class EditSaveCheck {
    static boolean verified(JsonObject row, Document saved) {
        if(saved==null)return false;
        if(saved.getInteger("level",1)!=row.get("level").getAsInt() || saved.getInteger("promoteLevel",0)!=row.get("promoteLevel").getAsInt())return false;
        if(row.get("kind").getAsString().equals("avatar")) {
            if(saved.getInteger("skillDepotId",0)!=row.get("skillDepotId").getAsInt())return false;
            Set<Integer> owned=new HashSet<>(saved.getList("talentIdList",Integer.class,List.of()));
            var active=row.getAsJsonArray("activeTalentIds");int desired=row.get("after").getAsInt();
            for(int i=0;i<active.size();i++)if(owned.contains(active.get(i).getAsInt())!=(i<desired))return false;
            // C3/C5 add displayed talent bonuses, not trained/base skill levels.
            var json=JsonParser.parseString(saved.toJson()).getAsJsonObject();
            if(!json.has("skillLevelMap"))return row.getAsJsonObject("baseSkillLevels").size()==0;
            var base=json.getAsJsonObject("skillLevelMap");
            for(var e:row.getAsJsonObject("baseSkillLevels").entrySet())if(!base.has(e.getKey())||!base.get(e.getKey()).equals(e.getValue()))return false;
            return true;
        }
        return saved.getInteger("refinement",0)+1==row.get("after").getAsInt()
            && saved.getInteger("equipCharacter",0)==row.get("equippedBy").getAsInt()
            && saved.getBoolean("locked",false)==row.get("locked").getAsBoolean();
    }
    public static void main(String[] args)throws Exception {
        Path root=Path.of(args[0]).toAbsolutePath().normalize();
        ArenaAccount.toolRoot(ArenaAccount.class,root);
        System.setProperty("logback.configurationFile",root.resolve("scripts/mongo-logback.xml").toString());
        try(var client=MongoClients.create("mongodb://127.0.0.1:27018/?directConnection=true&serverSelectionTimeoutMS=5000")) {
            var db=client.getDatabase("astaps_local");
            if(args[1].equals("snapshot")) {
                Path output=Path.of(args[2]).toAbsolutePath().normalize();
                if(!output.startsWith(root.resolve("audit")))throw new Exception("Snapshot must stay under audit");
                var data=new JsonObject();
                for(String collection:List.of("avatars","items")) {
                    var rows=new JsonArray();
                    for(var row:db.getCollection(collection).find(new Document("ownerId",ArenaAccount.uid(root))))rows.add(JsonParser.parseString(row.toJson()));
                    data.add(collection,rows);
                }
                Files.writeString(output,new GsonBuilder().setPrettyPrinting().create().toJson(data));
                System.out.println("Snapshot: "+data.getAsJsonArray("avatars").size()+" avatars; "+data.getAsJsonArray("items").size()+" inventory rows");return;
            }
            String token=args[1];if(!token.matches("[a-f0-9]{32}"))throw new Exception("Invalid request token");
            var receipt=JsonParser.parseString(Files.readString(root.resolve("run/edit-results/"+token+".json"))).getAsJsonObject();
            if(receipt.get("uid").getAsInt()!=ArenaAccount.uid(root))throw new Exception("Wrong receipt account");
            if(!receipt.get("ok").getAsBoolean())throw new Exception(receipt.toString());
            if(receipt.has("backup")) {
                var backup=JsonParser.parseString(Files.readString(root.resolve("backups/edits/"+token+".json"))).getAsJsonObject();
                if(backup.get("uid").getAsInt()!=ArenaAccount.uid(root))throw new Exception("Wrong backup account");
                for(var e:backup.getAsJsonArray("changes")) {
                    var row=e.getAsJsonObject();boolean avatar=row.get("kind").getAsString().equals("avatar");
                    var collection=db.getCollection(avatar?"avatars":"items");
                    var filter=new Document("ownerId",ArenaAccount.uid(root)).append(avatar?"avatarId":"_id",avatar?row.get("id").getAsInt():new ObjectId(row.get("objectId").getAsString()));
                    boolean found=false;
                    for(int i=0;i<120;i++) { if(verified(row,collection.find(filter).first())) {found=true;break;}Thread.sleep(100); }
                    if(!found)throw new Exception("Saved edit/invariant check not confirmed for ID "+row.get("id")+"; inspect backup and server logs before retrying.");
                }
            }
            receipt.addProperty("verifiedSaved",true);System.out.println(receipt);
        }
    }
}

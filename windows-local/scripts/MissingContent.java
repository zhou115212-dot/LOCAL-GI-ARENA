import arena.install.ArenaAccount;
import com.mongodb.client.MongoClients;
import org.bson.Document;
import com.google.gson.*;
import java.nio.file.*;
import java.nio.channels.FileChannel;
import java.util.*;

// Planner reads the local save. Optional grants use server commands, never direct DB writes.
public class MissingContent {
 public static void main(String[] args)throws Exception {
  Path root=Path.of(args[0]).toAbsolutePath().normalize();
  ArenaAccount.toolRoot(ArenaAccount.class,root);
  String mode=args.length>1?args[1]:"avatars";
  if(!Set.of("avatars","weapons","all").contains(mode))throw new Exception("Unknown content kind");
  boolean grant=args.length>2&&args[2].equals("grant");
  System.setProperty("logback.configurationFile",root.resolve("scripts/mongo-logback.xml").toString());
  try(var client=MongoClients.create("mongodb://127.0.0.1:27018/?directConnection=true&serverSelectionTimeoutMS=5000")) {
   var db=client.getDatabase("astaps_local");
   if(db.getCollection("players").countDocuments(new Document("_id",ArenaAccount.uid(root)))==0)throw new Exception("Enter the world with the configured test account first.");
   Set<Integer> avatars=new HashSet<>(),weapons=new HashSet<>();
   for(var row:db.getCollection("avatars").find(new Document("ownerId",ArenaAccount.uid(root))).projection(new Document("avatarId",1)))avatars.add(row.getInteger("avatarId"));
   for(var row:db.getCollection("items").find(new Document("ownerId",ArenaAccount.uid(root))).projection(new Document("itemId",1))){int id=row.getInteger("itemId");if(id>=11100&&id<=16000)weapons.add(id);}
   List<Integer> missingAvatars=new ArrayList<>(),missingWeapons=new ArrayList<>();
   var entries=JsonParser.parseString(Files.readString(root.resolve("catalog/items.json"))).getAsJsonArray();
   for(var entry:entries){var row=entry.getAsJsonObject();if(!row.get("named").getAsBoolean())continue;int id=row.get("id").getAsInt();boolean avatar=row.get("kind").getAsString().equals("角色");
    if(avatar&&!mode.equals("weapons")&&!avatars.contains(id))missingAvatars.add(id);
    if(!avatar&&!mode.equals("avatars")&&!weapons.contains(id))missingWeapons.add(id);
   }
   Collections.sort(missingAvatars);Collections.sort(missingWeapons);
   var report=new JsonObject();report.addProperty("uid",ArenaAccount.uid(root));report.addProperty("ownedCount",avatars.size());report.addProperty("ownedWeaponTypes",weapons.size());report.addProperty("directDatabaseWrites",false);
   var aa=new JsonArray();for(int id:missingAvatars)aa.add(id);report.add("missingAvatarIds",aa);var wa=new JsonArray();for(int id:missingWeapons)wa.add(id);report.add("missingWeaponIds",wa);
   if(!grant){System.out.println(report);return;}
   ArtifactGrant.localOnline();
   try(var channel=FileChannel.open(root.resolve("run/content-sync.lock"),StandardOpenOption.CREATE,StandardOpenOption.WRITE);var lock=channel.tryLock()) {
    if(lock==null)throw new Exception("Another missing-content sync is running");
    int total=missingAvatars.size()+missingWeapons.size(),done=0;
    System.out.println("Missing-only sync: "+total+" entries; existing content is skipped.");
    for(boolean avatar:new boolean[]{true,false})for(int id:avatar?missingAvatars:missingWeapons){
     var collection=db.getCollection(avatar?"avatars":"items");var filter=new Document("ownerId",ArenaAccount.uid(root)).append(avatar?"avatarId":"itemId",id);
     if(collection.countDocuments(filter)>0)continue;
     String command="give @"+ArenaAccount.uid(root)+" "+id+(avatar?" lv90 c0 sl9":" lv90 r1 x1");
     String file=System.currentTimeMillis()+"-"+UUID.randomUUID();Path temporary=root.resolve("run/commands/"+file+".tmp"),destination=root.resolve("run/commands/"+file+".txt");
     Files.writeString(temporary,command);Files.move(temporary,destination,StandardCopyOption.ATOMIC_MOVE);
     boolean received=false;
     for(int i=0;i<200;i++){if(collection.countDocuments(filter)>0){received=true;break;}Thread.sleep(100);}
     if(!received)throw new Exception("No saved grant confirmation for ID "+id+". Remaining grants stopped; inspect server log and check that the configured test account is online.");
     System.out.println("Added "+(++done)+"/"+total+": "+id);
    }
    System.out.println("DONE. Existing avatar levels/constellations/talents and owned weapons were not targeted.");
   }
  }
 }
}

import arena.install.ArenaAccount;
import com.mongodb.client.MongoClients;
import org.bson.Document;
import com.google.gson.*;
import java.nio.file.*;
import java.util.*;

// Read-only planner. Inventory changes are made by the existing server console, not database edits.
public class MissingAvatars {
 public static void main(String[] args)throws Exception {
  Path root=ArenaAccount.toolRoot(ArenaAccount.class,Path.of(args[0]));
  System.setProperty("logback.configurationFile",root.resolve("scripts/mongo-logback.xml").toString());
  Set<Integer> owned=new HashSet<>();
  try(var client=MongoClients.create("mongodb://127.0.0.1:27018/?directConnection=true&serverSelectionTimeoutMS=5000")) {
   var db=client.getDatabase("astaps_local");
   if(db.getCollection("players").countDocuments(new Document("_id",ArenaAccount.uid(root)))==0)throw new Exception("Enter the world with the configured test account first.");
   for(var avatar:db.getCollection("avatars").find(new Document("ownerId",ArenaAccount.uid(root))).projection(new Document("avatarId",1)))owned.add(avatar.getInteger("avatarId"));
  }
  List<Integer> missing=new ArrayList<>();
  var rows=JsonParser.parseString(Files.readString(root.resolve("server/resources/ExcelBinOutput/AvatarExcelConfigData.json"))).getAsJsonArray();
  for(var row:rows){var avatar=row.getAsJsonObject();int id=avatar.get("id").getAsInt();if(id<10000002||id>=10000901)continue;if(avatar.has("useType")&&"AVATAR_TEST".equals(avatar.get("useType").getAsString()))continue;if(!owned.contains(id))missing.add(id);}
  Collections.sort(missing);
  var report=new JsonObject();report.addProperty("uid",ArenaAccount.uid(root));report.addProperty("ownedCount",owned.size());report.addProperty("databaseModified",false);var array=new JsonArray();for(int id:missing)array.add(id);report.add("missingAvatarIds",array);
  System.out.println(report);
 }
}

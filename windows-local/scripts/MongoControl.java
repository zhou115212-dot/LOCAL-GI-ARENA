import com.mongodb.client.MongoClients;
import com.mongodb.MongoSocketReadException;
import com.mongodb.MongoSocketException;
import org.bson.Document;

public class MongoControl {
    public static void main(String[] args) {
        // Keep database diagnostics independent of the game's custom logging appenders.
        System.setProperty("logback.configurationFile", args.length > 1 ? args[1] : "E:/Genshin-Local-Server/scripts/mongo-logback.xml");
        String uri = "mongodb://127.0.0.1:27018/?directConnection=true&serverSelectionTimeoutMS=5000";
        try (var client = MongoClients.create(uri)) {
            if (args.length > 0 && args[0].equals("shutdown")) {
                try { client.getDatabase("admin").runCommand(new Document("shutdown", 1)); }
                catch (MongoSocketException expected) { System.out.println("MongoDB shutdown requested."); }
            } else {
                System.out.println(client.getDatabase("admin").runCommand(new Document("ping", 1)).toJson());
                var db = client.getDatabase("astaps_local");
                for (String name : db.listCollectionNames()) {
                    System.out.println(name + ": " + db.getCollection(name).countDocuments());
                }
                for (var account : db.getCollection("accounts").find()) {
                    System.out.println("account: " + account.getString("username"));
                }
            }
        }
    }
}

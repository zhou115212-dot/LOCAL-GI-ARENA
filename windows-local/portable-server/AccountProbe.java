import java.io.*;
import at.favre.lib.crypto.bcrypt.BCrypt;
import com.mongodb.client.MongoClients;
import org.bson.Document;

/** Read-only, loopback only; never prints a hash, password, player ID or session token. */
final class AccountProbe {
    public static void main(String[] args) throws Exception {
        if(args.length != 4) throw new IllegalArgumentException("mode username uid logback.xml");
        System.setProperty("logback.configurationFile",args[3]);
        String username=args[1]; int uid=Integer.parseInt(args[2]); int result;
        try(var c=MongoClients.create("mongodb://127.0.0.1:27018/?directConnection=true&serverSelectionTimeoutMS=2500")){
            var db=c.getDatabase("astaps_local");var a=db.getCollection("accounts");
            var account=a.find(new Document("username",username)).first();
            if(args[0].equals("available")){
                boolean available=account==null && a.find(new Document("reservedPlayerId",uid)).first()==null
                    && db.getCollection("players").find(new Document("_id",uid)).first()==null;
                result=available?0:4;
            }else if(args[0].equals("verify")){
                String password=new BufferedReader(new InputStreamReader(System.in,"UTF-8")).readLine();
                result=account!=null && account.get("reservedPlayerId") instanceof Number n && n.intValue()==uid
                    && password!=null && account.getString("password")!=null
                    && BCrypt.verifyer().verify(password.toCharArray(),account.getString("password")).verified ? 0:3;
            }else throw new IllegalArgumentException("Unexpected mode");
        }
        System.exit(result);
    }
}

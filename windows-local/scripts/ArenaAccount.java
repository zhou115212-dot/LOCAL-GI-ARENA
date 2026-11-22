package arena.install;

import java.nio.file.*;
import com.google.gson.*;

/** Public, immutable per-install binding; no credentials and never guesses the first player. */
public final class ArenaAccount {
    private ArenaAccount(){}
    public static int uid(Path root) {
        try {
            var p=root.resolve("run/test-account.json");
            if(Files.size(p)>8192) throw new IllegalArgumentException("Invalid test-account binding");
            var data=JsonParser.parseString(Files.readString(p)).getAsJsonObject();
            var u=data.getAsJsonPrimitive("uid");
            var n=data.getAsJsonPrimitive("username");
            if(u==null||!u.isNumber()||!u.getAsString().matches("[1-9][0-9]{0,9}")||n==null||!n.isString()||n.getAsString().isBlank())throw new IllegalArgumentException("Invalid test-account binding");
            return Integer.parseInt(u.getAsString());
        } catch(Exception ex){throw new IllegalStateException("Create the local test account in this installation before using controllers.",ex);}
    }
    public static Path toolRoot(Class<?> helper,Path requested) throws Exception {
        Path expected=Path.of(helper.getProtectionDomain().getCodeSource().getLocation().toURI()).toRealPath();
        Path root=requested.toRealPath();
        if(!expected.equals(root.resolve("scripts/classes").toRealPath()))throw new IllegalArgumentException("Helper belongs to a different installation");
        return root;
    }
    public static Path pluginRoot(Class<?> owner) {
        try{
            Path server=Path.of("").toRealPath();
            Path jar=Path.of(owner.getProtectionDomain().getCodeSource().getLocation().toURI()).toRealPath();
            if(!"server".equalsIgnoreCase(server.getFileName().toString())||!jar.getParent().equals(server.resolve("plugins").toRealPath())||!Files.isRegularFile(server.resolve("config.json")))throw new IllegalStateException("Plugin is not running in its own local server directory");
            return server.getParent();
        }catch(Exception ex){throw new IllegalStateException("Invalid local server/plugin root",ex);}
    }
}

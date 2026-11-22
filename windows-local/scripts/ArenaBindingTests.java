import arena.install.ArenaAccount;
import java.nio.file.*;
import java.util.List;

/** Offline binding tests; only writes to a new directory inside the caller's disposable fixture. */
public class ArenaBindingTests {
    static int checks;
    static void deny(Runnable r){try{r.run();}catch(RuntimeException ok){checks++;return;}throw new AssertionError("unsafe binding accepted");}
    public static void main(String[] args)throws Exception{
        Path fixture=Path.of(args[0]).toRealPath();
        Path root=Files.createTempDirectory(fixture,"binding-");
        var binding=root.resolve("run/test-account.json");Files.createDirectory(binding.getParent());
        deny(()->ArenaAccount.uid(root)); // missing: do not guess 10001 or pick the first player
        for(var bad:List.of("{}","{\"uid\":0,\"username\":\"test\"}","{\"uid\":123,\"username\":\" \"}","{\"uid\":-3,\"username\":\"test\"}","{\"uid\":2147483648,\"username\":\"test\"}","{\"uid\":\"123\",\"username\":\"test\"}","{\"uid\":3.2,\"username\":\"test\"}")){
            Files.writeString(binding,bad);deny(()->ArenaAccount.uid(root));
        }
        Files.writeString(binding,"{\"uid\":782314,\"username\":\"test\"}");
        if(ArenaAccount.uid(root)!=782314)throw new AssertionError("wrong UID");checks++;
        Path actual=Path.of(args[1]).toRealPath();
        if(!actual.equals(ArenaAccount.toolRoot(ArenaAccount.class,actual)))throw new AssertionError("wrong helper root");checks++;
        Files.createDirectories(root.resolve("scripts/classes"));
        try{ArenaAccount.toolRoot(ArenaAccount.class,root);throw new AssertionError("wrong installation accepted");}catch(IllegalArgumentException ok){checks++;}
        System.out.println("PASS "+checks+" binding and install-origin assertions");
    }
}

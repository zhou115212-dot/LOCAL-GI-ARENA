import com.google.gson.*;
import org.bson.Document;
import java.nio.file.*;
import java.lang.reflect.*;
import java.util.*;
import emu.grasscutter.data.GameData;
import emu.grasscutter.data.excels.ItemData;
import emu.grasscutter.game.inventory.GameItem;
import emu.grasscutter.command.commands.GiveCommand;
import emu.grasscutter.utils.JsonUtils;
public class WeaponGrantTests {
    static int checks;
    static void ok(boolean b,String text){checks++;if(!b)throw new AssertionError(text);}
    static void rejects(Path root,int id,int lv,int r,int qty)throws Exception{try{WeaponGrant.validate(root,id,lv,r,qty);throw new AssertionError("Invalid plan accepted");}catch(AssertionError e){throw e;}catch(Exception expected){checks++;}}
    public static void main(String[] args)throws Exception{
        Path root=Path.of(args[0]);var p=WeaponGrant.validate(root,12501,90,5,3);
        ok(p.get("command").getAsString().equals("give @10001 12501 lv90 r5 x3"),"Explicit copy count");
        ok(p.get("quantity").getAsInt()==3,"3 extra copies");
        ok(WeaponGrant.matches(new Document("level",90).append("refinement",4).append("equipCharacter",0),p),"Stored refinement is zero-based");
        ok(!WeaponGrant.matches(new Document("level",90).append("refinement",5),p),"Reject incorrect refinement");
        ok(!WeaponGrant.matches(new Document("level",89).append("refinement",4),p),"Reject incorrect level");
        ok(!WeaponGrant.matches(new Document("level",90).append("refinement",4).append("equipCharacter",10000016),p),"Existing equipped weapon not counted as a fresh copy");
        for(int qty:new int[]{0,-1,101,Integer.MAX_VALUE})rejects(root,12501,90,5,qty);
        for(int lv:new int[]{0,91})rejects(root,12501,lv,5,1);
        for(int refine:new int[]{0,6})rejects(root,12501,90,refine,1);
        rejects(root,10000016,90,5,1);rejects(root,202,90,5,1);rejects(root,99999,90,5,1);
        ok(WeaponGrant.validate(root,12501,1,1,1).get("quantity").getAsInt()==1,"Minimum boundaries");
        ok(WeaponGrant.validate(root,12501,90,5,100).get("quantity").getAsInt()==100,"Maximum boundaries");
        int weapons=0;for(var v:JsonParser.parseString(Files.readString(root.resolve("catalog/items.json"))).getAsJsonArray()){
            var e=v.getAsJsonObject();if(e.get("kind").getAsString().equals("武器")&&e.get("named").getAsBoolean()){
                var plan=WeaponGrant.validate(root,e.get("id").getAsInt(),90,1,3);ok(plan.get("command").getAsString().endsWith("r1 x3"),"Catalog weapon accepts copies");weapons++;
            }
        }
        ItemData actual=null;for(var v:JsonParser.parseString(Files.readString(root.resolve("server/resources/ExcelBinOutput/WeaponExcelConfigData.json"))).getAsJsonArray())if(v.getAsJsonObject().get("id").getAsInt()==12501)actual=JsonUtils.decode(v,ItemData.class);
        var params=Class.forName("emu.grasscutter.command.commands.GiveCommand$GiveItemParameters");var constructor=params.getDeclaredConstructor();constructor.setAccessible(true);
        var factory=GiveCommand.class.getDeclaredMethod("makeUnstackableItems",params);factory.setAccessible(true);
        for(int quantity:new int[]{1,3,5,100})for(int level:new int[]{1,90})for(int refinement:new int[]{1,5}){
            var input=constructor.newInstance();for(var e:Map.of("data",actual,"amount",quantity,"lvl",level,"refinement",refinement).entrySet()){var f=params.getDeclaredField(e.getKey());f.setAccessible(true);f.set(input,e.getValue());}
            var items=(List<GameItem>)factory.invoke(null,input);ok(items.size()==quantity,"Real give factory produces exact copy count");
            var distinct=Collections.newSetFromMap(new IdentityHashMap<GameItem,Boolean>());
            for(var item:items){ok(distinct.add(item),"Every weapon is a separate instance");ok(item.getLevel()==level&&item.getRefinement()==refinement-1,"Real factory honors level and refinement");}
        }
        System.out.println("PASS "+checks+" offline plan/matching checks across "+weapons+" named weapons; no DB, grants or account changes.");
    }
}

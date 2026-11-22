import com.google.gson.*;
import org.bson.Document;
import java.util.*;

/** Synthetic fixtures only: no Mongo connection, player loading or save operations. */
public class EditSaveCheckTest {
    static int count;
    static void check(boolean value){if(!value)throw new AssertionError("Verification test "+count);count++;}
    public static void main(String[] args) {
        JsonObject role=JsonParser.parseString("{\"kind\":\"avatar\",\"level\":90,\"promoteLevel\":6,\"skillDepotId\":5201,\"after\":2,\"activeTalentIds\":[521,522,523,524,525,526],\"baseSkillLevels\":{\"10521\":9,\"10522\":9}}").getAsJsonObject();
        Document a=Document.parse("{\"level\":90,\"promoteLevel\":6,\"skillDepotId\":5201,\"talentIdList\":[521,522],\"skillLevelMap\":{\"10521\":9,\"10522\":9}}");
        check(EditSaveCheck.verified(role,a));check(!EditSaveCheck.verified(role,null));
        Document b=Document.parse(a.toJson());b.put("level",80);check(!EditSaveCheck.verified(role,b));
        b=Document.parse(a.toJson());b.put("promoteLevel",5);check(!EditSaveCheck.verified(role,b));
        b=Document.parse(a.toJson());b.put("talentIdList",List.of(521));check(!EditSaveCheck.verified(role,b));
        b=Document.parse(a.toJson());b.put("talentIdList",List.of(521,522,523));check(!EditSaveCheck.verified(role,b));
        b=Document.parse(a.toJson());b.put("talentIdList",List.of(521,522,999));check(EditSaveCheck.verified(role,b));
        b=Document.parse(a.toJson());((Document)b.get("skillLevelMap")).put("10522",10);check(!EditSaveCheck.verified(role,b));
        b=Document.parse(a.toJson());b.put("skillDepotId",5202);check(!EditSaveCheck.verified(role,b));
        role.addProperty("after",0);b=Document.parse(a.toJson());b.put("talentIdList",List.of());check(EditSaveCheck.verified(role,b));
        JsonObject weapon=JsonParser.parseString("{\"kind\":\"weapon\",\"level\":90,\"promoteLevel\":6,\"after\":5,\"equippedBy\":10000052,\"locked\":true}").getAsJsonObject();
        Document w=Document.parse("{\"level\":90,\"promoteLevel\":6,\"refinement\":4,\"equipCharacter\":10000052,\"locked\":true}");
        check(EditSaveCheck.verified(weapon,w));
        b=Document.parse(w.toJson());b.put("refinement",3);check(!EditSaveCheck.verified(weapon,b));
        b=Document.parse(w.toJson());b.put("equipCharacter",0);check(!EditSaveCheck.verified(weapon,b));
        b=Document.parse(w.toJson());b.put("locked",false);check(!EditSaveCheck.verified(weapon,b));
        weapon.addProperty("after",1);b=Document.parse(w.toJson());b.put("refinement",0);check(EditSaveCheck.verified(weapon,b));
        System.out.println("PASS "+count+" saved-state/invariant tests (synthetic fixtures, no DB writes)");
    }
}

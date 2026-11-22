import localtools.EditRules;
public class EditRulesTest {
    static int passed;
    static void check(boolean ok) { if(!ok)throw new AssertionError();passed++; }
    static void bad(Runnable r) { try {r.run();}catch(IllegalArgumentException e){passed++;return;}throw new AssertionError("Expected rejection"); }
    public static void main(String[] args) {
        check(EditRules.matches("stars4",10000014,4));check(!EditRules.matches("stars4",10000052,5));
        check(EditRules.matches("stars5",13509,5));check(!EditRules.matches("stars5",13501,4));
        check(EditRules.matches("all",11101,1));check(EditRules.matches("13509,13501",13501,5));check(!EditRules.matches("13509",13501,5));
        check(EditRules.validateSelector("10000052").equals("10000052"));
        check(EditRules.refinable(new int[]{0,114501}));check(!EditRules.refinable(new int[]{0}));check(!EditRules.refinable(null));
        EditRules.validateLevel("avatar",0);EditRules.validateLevel("avatar",6);EditRules.validateLevel("weapon",1);EditRules.validateLevel("weapon",5);
        bad(()->EditRules.validateLevel("avatar",7));bad(()->EditRules.validateLevel("avatar",-1));bad(()->EditRules.validateLevel("weapon",0));bad(()->EditRules.validateLevel("weapon",6));
        bad(()->EditRules.validateSelector("stars3"));bad(()->EditRules.validateSelector("1;stop"));bad(()->EditRules.validateSelector("0"));bad(()->EditRules.validateSelector("2147483648"));
        bad(()->EditRules.token("../../server/config"));bad(()->EditRules.token("../x"));
        check(EditRules.token("0123456789abcdef0123456789abcdef").length()==32);
        System.out.println("PASS "+passed+" selection/range/path tests");
    }
}

package localtools;

import java.util.*;

/** Pure selection/validation helpers; no game, database or network initialization. */
public final class EditRules {
    public static void validateLevel(String kind, int level) {
        if (!(kind.equals("avatar") || kind.equals("weapon"))) throw new IllegalArgumentException("Unknown kind");
        if (level < (kind.equals("avatar") ? 0 : 1) || level > (kind.equals("avatar") ? 6 : 5))
            throw new IllegalArgumentException("Constellation must be 0..6; refinement must be 1..5");
    }
    public static String validateSelector(String selector) {
        if (selector.equals("all") || selector.equals("stars4") || selector.equals("stars5")) return selector;
        if (!selector.matches("[0-9]{1,9}(,[0-9]{1,9}){0,399}")) throw new IllegalArgumentException("Invalid selector");
        for (String part : selector.split(",")) if (Integer.parseInt(part) <= 0) throw new IllegalArgumentException("Invalid ID");
        return selector;
    }
    public static boolean matches(String selector, int id, int stars) {
        if (selector.equals("all")) return true;
        if (selector.equals("stars4")) return stars == 4;
        if (selector.equals("stars5")) return stars == 5;
        return Arrays.stream(selector.split(",")).anyMatch(s -> Integer.parseInt(s) == id);
    }
    public static boolean refinable(int[] affixes) {
        return affixes != null && Arrays.stream(affixes).anyMatch(n -> n > 0);
    }
    public static String token(String s) {
        if (!s.matches("[a-f0-9]{32}")) throw new IllegalArgumentException("Invalid request/backup token");
        return s;
    }
}

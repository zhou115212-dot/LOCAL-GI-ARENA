package emu.grasscutter.game.avatar;

import emu.grasscutter.data.GameData;
import java.util.List;
import java.util.TreeSet;

/** Wire-only partition of already unlocked passives. Never grants talents, edits
 * quests, changes saved state, or guesses packet fields. Uses existing generated
 * protocol builders for inventory, scene, showcase and depot notifications. */
public final class QuestProudSkillSyncHelper {
    private QuestProudSkillSyncHelper() {}

    public static List<Integer> special(Avatar avatar) {
        if (avatar == null || avatar.getSkillDepot() == null
                || avatar.getProudSkillList() == null) return List.of();
        var groups = avatar.getSkillDepot().getQuestProudSkillGroupIds();
        if (groups == null || groups.isEmpty()) return List.of();
        var result = new TreeSet<Integer>();
        for (int id : avatar.getProudSkillList()) {
            if (id > 0 && groups.contains(id / 100)
                    && GameData.getProudSkillDataMap().containsKey(id)) result.add(id);
        }
        return List.copyOf(result);
    }

    public static List<Integer> inherent(Avatar avatar) {
        if (avatar == null || avatar.getProudSkillList() == null) return List.of();
        var result = new TreeSet<Integer>(avatar.getProudSkillList());
        result.removeAll(special(avatar));
        return List.copyOf(result);
    }
}

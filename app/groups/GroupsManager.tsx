"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Plus, X, Pencil, Trash2 } from "lucide-react";
import { createClient } from "@/lib/supabase/client";
import { Person, Group } from "@/lib/types";

export default function GroupsManager({ people, initialGroups }: { people: Person[]; initialGroups: Group[] }) {
  const [groups, setGroups] = useState(initialGroups);
  const [creating, setCreating] = useState(false);
  const [editingId, setEditingId] = useState<string | null>(null);
  const [name, setName] = useState("");
  const [memberIds, setMemberIds] = useState<string[]>([]);
  const router = useRouter();
  const supabase = createClient();

  function startCreate() {
    setCreating(true);
    setEditingId(null);
    setName("");
    setMemberIds([]);
  }

  function startEdit(g: Group) {
    setEditingId(g.id);
    setCreating(false);
    setName(g.name);
    setMemberIds(g.memberIds);
  }

  function toggleMember(id: string) {
    setMemberIds((cur) => (cur.includes(id) ? cur.filter((x) => x !== id) : [...cur, id]));
  }

  async function save() {
    if (!name.trim()) return;
    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) return;

    if (editingId) {
      await supabase.from("groups").update({ name: name.trim() }).eq("id", editingId);
      await supabase.from("group_members").delete().eq("group_id", editingId);
      if (memberIds.length) {
        await supabase.from("group_members").insert(memberIds.map((person_id) => ({ group_id: editingId, person_id })));
      }
    } else {
      const { data: group } = await supabase.from("groups").insert({ user_id: user.id, name: name.trim() }).select().single();
      if (group && memberIds.length) {
        await supabase.from("group_members").insert(memberIds.map((person_id) => ({ group_id: group.id, person_id })));
      }
    }

    setCreating(false);
    setEditingId(null);
    router.refresh();
    const { data: freshGroups } = await supabase.from("groups").select("*").order("name");
    const { data: freshMembers } = await supabase.from("group_members").select("*");
    setGroups(
      (freshGroups ?? []).map((g) => ({
        ...g,
        memberIds: (freshMembers ?? []).filter((m) => m.group_id === g.id).map((m) => m.person_id),
      }))
    );
  }

  async function remove(id: string) {
    if (!confirm("Delete this group?")) return;
    await supabase.from("groups").delete().eq("id", id);
    setGroups(groups.filter((g) => g.id !== id));
  }

  const editorOpen = creating || editingId !== null;

  return (
    <div>
      {!editorOpen && (
        <button
          onClick={startCreate}
          className="w-full rounded-xl border-2 border-dashed border-line py-3 flex items-center justify-center gap-1.5 text-[13px] font-semibold text-accent mb-4"
        >
          <Plus size={16} /> New group
        </button>
      )}

      {editorOpen && (
        <div className="bg-white rounded-xl border border-line p-3.5 mb-4">
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Group name, e.g. Drinkers"
            className="w-full rounded-xl border border-line bg-white px-3.5 py-3 text-[15px] outline-none focus:ring-2 focus:ring-accent/40 mb-3"
          />
          <p className="text-[11px] font-semibold uppercase tracking-wide text-muted mb-1.5">Members</p>
          <div className="flex flex-wrap gap-1.5 mb-3">
            {people.map((p) => (
              <button
                key={p.id}
                onClick={() => toggleMember(p.id)}
                className={`px-3.5 py-2 rounded-full text-[13px] font-medium border ${
                  memberIds.includes(p.id) ? "bg-ink text-white border-ink" : "bg-white text-[#5B5748] border-line"
                }`}
              >
                {p.name}
              </button>
            ))}
            {people.length === 0 && <p className="text-[13px] text-muted">Add people first, from the People tab.</p>}
          </div>
          <div className="flex gap-2">
            <button onClick={save} className="flex-1 rounded-xl bg-accent text-white font-semibold py-2.5 text-[14px]">
              Save group
            </button>
            <button
              onClick={() => {
                setCreating(false);
                setEditingId(null);
              }}
              className="px-4 rounded-xl bg-[#F0EDE1] text-[#5B5748] font-semibold py-2.5 text-[14px]"
            >
              Cancel
            </button>
          </div>
        </div>
      )}

      <div className="space-y-2">
        {groups.map((g) => (
          <div key={g.id} className="bg-white rounded-xl border border-line px-4 py-3 flex items-center gap-3">
            <div className="flex-1 min-w-0">
              <p className="text-[14px] font-medium text-ink">{g.name}</p>
              <p className="text-[12px] text-muted truncate">
                {g.memberIds.map((id) => people.find((p) => p.id === id)?.name).filter(Boolean).join(", ") || "No members"}
              </p>
            </div>
            <button onClick={() => startEdit(g)} className="p-2 rounded-full active:bg-[#F5F3EC]">
              <Pencil size={15} className="text-muted" />
            </button>
            <button onClick={() => remove(g.id)} className="p-2 rounded-full active:bg-[#FBEDEA]">
              <Trash2 size={15} className="text-owe" />
            </button>
          </div>
        ))}
        {groups.length === 0 && !editorOpen && <p className="text-[13px] text-muted py-2">No groups yet.</p>}
      </div>
    </div>
  );
}

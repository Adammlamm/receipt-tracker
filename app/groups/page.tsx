import Link from "next/link";
import { loadPeople, loadGroups } from "@/lib/data";
import BottomNav from "@/components/BottomNav";
import GroupsManager from "./GroupsManager";

export default async function GroupsPage() {
  const [people, groups] = await Promise.all([loadPeople(), loadGroups()]);

  return (
    <div>
      <div className="h-14 flex items-center px-5 border-b border-line">
        <Link href="/people" className="text-[13px] text-muted">Back</Link>
        <h1 className="flex-1 text-center font-semibold text-[15px] text-ink pr-8">Groups</h1>
      </div>
      <div className="px-5 pt-4 pb-8">
        <p className="text-[13px] text-muted mb-4">
          Groups let you assign a whole table or crowd to an item in one tap — like "Drinkers" or "Table 2".
        </p>
        <GroupsManager people={people} initialGroups={groups} />
      </div>
      <BottomNav />
    </div>
  );
}

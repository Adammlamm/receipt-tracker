import { LucideIcon } from "lucide-react";

export default function EmptyState({
  icon: Icon,
  title,
  body,
}: {
  icon: LucideIcon;
  title: string;
  body?: string;
}) {
  return (
    <div className="bg-white rounded-2xl border border-dashed border-line px-5 py-10 text-center">
      <div className="w-11 h-11 rounded-full bg-[#F0EDE1] flex items-center justify-center mx-auto mb-3">
        <Icon size={20} className="text-muted" />
      </div>
      <p className="text-[14px] font-semibold text-ink">{title}</p>
      {body && <p className="text-[13px] text-muted mt-1">{body}</p>}
    </div>
  );
}

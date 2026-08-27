import Link from "next/link";
import { Receipt } from "lucide-react";

export default function NotFound() {
  return (
    <div className="min-h-screen bg-paper flex items-center justify-center px-6">
      <div className="text-center max-w-sm">
        <div className="w-12 h-12 rounded-full bg-[#F0EDE1] flex items-center justify-center mx-auto mb-4">
          <Receipt size={22} className="text-muted" />
        </div>
        <h1 className="text-[17px] font-semibold text-ink mb-1.5">Not found</h1>
        <p className="text-[13px] text-muted mb-6">This page or receipt doesn't exist — it may have been deleted.</p>
        <Link href="/" className="inline-block rounded-xl bg-accent text-white font-semibold py-3 px-6 text-[14px]">
          Back to Home
        </Link>
      </div>
    </div>
  );
}

import Skeleton from "@/components/Skeleton";

export default function Loading() {
  return (
    <div>
      <div className="h-14 flex items-center px-5 border-b border-line">
        <Skeleton className="h-4 w-16" />
      </div>
      <div className="px-5 pt-4">
        <Skeleton className="h-48 w-full rounded-xl mb-4" />
        <Skeleton className="h-3 w-20 mb-4" />
        <Skeleton className="h-56 w-full rounded-xl mb-5" />
        <Skeleton className="h-3 w-28 mb-2" />
        <div className="space-y-2">
          <Skeleton className="h-14 w-full rounded-xl" />
          <Skeleton className="h-14 w-full rounded-xl" />
        </div>
      </div>
    </div>
  );
}

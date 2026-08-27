import Skeleton from "@/components/Skeleton";

export default function Loading() {
  return (
    <div>
      <div className="px-5 pt-6 pb-2">
        <Skeleton className="h-3 w-24 mb-2" />
        <Skeleton className="h-10 w-40 mb-2" />
        <Skeleton className="h-3 w-32" />
      </div>
      <div className="px-5 mt-6">
        <Skeleton className="h-3 w-20 mb-2" />
        <Skeleton className="h-32 w-full rounded-xl" />
      </div>
      <div className="px-5 mt-7 space-y-3">
        <Skeleton className="h-3 w-28 mb-1" />
        <Skeleton className="h-40 w-full rounded-xl" />
        <Skeleton className="h-32 w-full rounded-xl" />
      </div>
      <div className="px-5 mt-7 space-y-2">
        <Skeleton className="h-3 w-32 mb-2" />
        <Skeleton className="h-16 w-full rounded-xl" />
        <Skeleton className="h-16 w-full rounded-xl" />
      </div>
    </div>
  );
}

import Skeleton from "@/components/Skeleton";

export default function Loading() {
  return (
    <div>
      <div className="h-14 flex items-center px-5 border-b border-line">
        <Skeleton className="h-4 w-20" />
      </div>
      <div className="px-5 pt-4">
        <Skeleton className="h-12 w-full rounded-xl mb-4" />
        <div className="space-y-2">
          {[0, 1, 2, 3, 4].map((i) => (
            <Skeleton key={i} className="h-16 w-full rounded-xl" />
          ))}
        </div>
      </div>
    </div>
  );
}
